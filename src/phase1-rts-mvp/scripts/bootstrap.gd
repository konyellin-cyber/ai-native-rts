extends Node3D

## Phase 1 Bootstrap — 主序
## 职责：读 config，按顺序创建子管理器，驱动每帧 tick 分发。
## 不包含：实体创建、断言逻辑、生命周期管理、故障注入（见各子模块）。

const CONFIG_PATH = "res://config.json"

var config: Dictionary
var frame_count: int = 0
var total_frames: int = 3600
var start_time_msec: int = 0
var is_headless: bool = false
var _game_over: bool = false

var renderer: RefCounted
var _world: RefCounted        ## GameWorld
var _lifecycle: RefCounted    ## UnitLifecycleManager
var _assertions: RefCounted   ## AssertionSetup
var _sim_player: RefCounted = null
var _fault_injector: Node = null  ## FaultInjector，仅 config.fault_injection 非空时创建
var _window_frame_count: int = 0
var _window_assertions: RefCounted = null  ## WindowAssertionSetup，仅窗口模式


func _ready() -> void:
	config = _load_config()
	total_frames = config.physics.total_frames
	Engine.set_physics_ticks_per_second(config.physics.fps)
	Engine.set_max_fps(config.physics.fps)
	is_headless = DisplayServer.get_name() == "headless"

	# 窗口模式设置（headless 下跳过）
	if not is_headless:
		var window_config = config.get("window", {})
		if window_config.get("fullscreen", false):
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_setup_3d_scene()

	# 1. 初始化 Renderer
	var AIRendererScript = load("res://tools/ai-renderer/ai_renderer.gd")
	renderer = AIRendererScript.new(config.get("renderer", {"mode": "off", "sample_rate": 60, "calibrate": false}))

	# 注册 Camera3D 为 sensor（窗口模式下 _setup_3d_scene 已 add_child，此处注册）
	if not is_headless:
		var cam = get_node_or_null("Camera3D")
		if cam:
			renderer.register("Camera3D", cam, ["global_position", "rotation_degrees", "size"], "camera")

	# 2. 构建游戏世界（实体创建）
	var GameWorldScript = load("res://scripts/game_world.gd")
	if GameWorldScript == null:
		push_error("[BOOT] Failed to load game_world.gd — aborting scenario")
		_abort_scenario("game_world.gd load failed")
		return
	_world = GameWorldScript.new()
	_world.setup(self, config, is_headless, renderer)
	_world.build()

	# 3. 初始化生命周期管理器
	var LifecycleScript = load("res://scripts/unit_lifecycle_manager.gd")
	_lifecycle = LifecycleScript.new()
	_lifecycle.setup(_world.units, _world.hq_blue, func(): return frame_count,
		func(): # 首次击杀回调 → 转发给 ux_observer
			if _world.ux_observer and _world.ux_observer.is_enabled():
				_world.ux_observer.on_signal("battle_first_kill", [])
	)
	_lifecycle.init_alive_counts(3, 3)

	# 4. 连接 world 信号到 lifecycle / 本地处理器
	_world.unit_died.connect(_lifecycle.on_unit_died)
	_world.unit_produced.connect(_lifecycle.on_unit_produced)
	_world.hq_destroyed.connect(_on_hq_destroyed)
	_world.move_command_issued.connect(_on_move_command)
	_world.units_selected.connect(_on_units_selected)
	_world.hq_selected.connect(_on_hq_selected)
	_world.click_missed.connect(_on_click_missed)
	_world.selection_rect_drawn.connect(_on_selection_rect_drawn)
	_world.produce_requested.connect(_on_produce_requested)

	# 5. 注册 InputServer（窗口模式自动开启，headless 按 config）
	var input_server_config = config.get("input_server", {})
	if not is_headless:
		input_server_config["enabled"] = true
	if input_server_config.get("enabled", false):
		var InputServerScript = load("res://tools/ai-renderer/input_server.gd")
		var srv = Node.new()
		srv.set_script(InputServerScript)
		srv.setup(input_server_config, _world.selection_manager)
		add_child(srv)
		_world.input_server = srv

	# 6. SimulatedPlayer 不限于 headless，窗口模式也需要自动剧本触发 hq_selected 信号
	_setup_simulated_player()

	# 7. headless 专属：FaultInjector + 断言
	if is_headless:
		start_time_msec = Time.get_ticks_msec()
		print("[BOOT] Headless mode: %d frames" % total_frames)
		_setup_fault_injector()
		_setup_assertions()
	else:
		# 窗口模式：读取 scenario 的 screenshot_on_signals 传给 UXObserver
		_setup_window_screenshot_signals()
		_setup_window_assertions()


func _input(event: InputEvent) -> void:
	if _world.ux_observer and _world.ux_observer.is_enabled():
		_world.ux_observer.on_input(event)


func _physics_process(_delta: float) -> void:
	## _world 为 null 说明 _ready 中途 abort 了，停止处理防止每帧报错
	if _lifecycle == null:
		return
	_lifecycle.clean_dead_units()
	if _game_over:
		return

	if not is_headless:
		_window_frame_count += 1
		# SimulatedPlayer 在窗口模式也需要 tick，确保剧本按帧执行（如 hq_selected 触发）
		if _sim_player:
			_sim_player.tick(_window_frame_count)
		_lifecycle.tick()
		if _world.bottom_bar:
			_update_ui()
		if _world.ux_observer and _world.ux_observer.is_enabled():
			_world.ux_observer.tick(_window_frame_count, _delta)
		if renderer and config.get("renderer", {}).get("mode", "off") != "off":
			renderer.set_extra(_build_extra())
			var all_done = renderer.tick()
			# 窗口模式：所有断言完成或达到 total_frames 时自动退出（与 headless 行为一致）
			if all_done or _window_frame_count >= total_frames:
				renderer.print_results()
				_perf_report()
				_finish()
				return
		elif _window_frame_count >= total_frames:
			_perf_report()
			_finish()
	else:
		frame_count += 1
		if _sim_player:
			_sim_player.tick(frame_count)
		_lifecycle.tick()
		if _fault_injector:
			_fault_injector.tick(frame_count)
		renderer.set_extra(_build_extra())
		var all_assertions_done = renderer.tick()
		if all_assertions_done or frame_count >= total_frames:
			if all_assertions_done:
				print("[BOOT] Early exit at frame %d (all assertions resolved)" % frame_count)
			renderer.print_results()
			_perf_report()
			_finish()


# ─── Extra data builder ──────────────────────────────────────────

func _build_extra() -> Dictionary:
	var extra = {
		"red_alive": _lifecycle.red_alive,
		"blue_alive": _lifecycle.blue_alive,
		"kill_count": _lifecycle.kill_log.size(),
		"red_crystal": _world.hq_red.crystal if is_instance_valid(_world.hq_red) else 0,
		"blue_crystal": _world.hq_blue.crystal if is_instance_valid(_world.hq_blue) else 0,
	}
	if _sim_player:
		extra["simulated_player"] = {
			"select": _sim_player.last_select_count,
			"invalid_refs": _sim_player.last_invalid_refs,
			"move_commands": _sim_player.last_move_commands,
			"errors": _sim_player.last_errors,
		}
	if _world.ux_observer and _world.ux_observer.is_enabled():
		extra["ux"] = _world.ux_observer.get_ux_data()
	return extra


# ─── UI handlers (window mode) ───────────────────────────────────

func _update_ui() -> void:
	if is_instance_valid(_world.bottom_bar):
		var sel = _world.selection_manager.selected_units if _world.selection_manager else []
		_world.bottom_bar.update_data(_world.hq_red, sel, _lifecycle.red_alive, _lifecycle.blue_alive)
	if is_instance_valid(_world.prod_panel) and _world.prod_panel.visible_state:
		var prod = config.production
		_world.prod_panel.update_state(_world.hq_red, int(prod.worker_cost), int(prod.fighter_cost), int(prod.archer_cost))


func _on_units_selected(selected: Array) -> void:
	if selected.size() > 0 and is_instance_valid(_world.prod_panel):
		_world.prod_panel.hide_panel()


func _on_hq_selected(hq: Node) -> void:
	if is_instance_valid(_world.prod_panel):
		_world.prod_panel.show_panel(hq)
		if _world.ux_observer and _world.ux_observer.is_enabled():
			_world.ux_observer.mark_ui_dirty()
			_world.ux_observer.on_signal("prod_panel_shown", ["HQ_red (click)"])


func _on_click_missed() -> void:
	## 左键单击落空（未命中单位或 HQ）→ 关闭生产面板
	if is_instance_valid(_world.prod_panel):
		_world.prod_panel.hide_panel()


func _on_selection_rect_drawn(rect: Rect2) -> void:
	if _world.ux_observer and _world.ux_observer.is_enabled():
		_world.ux_observer.on_signal("selection_rect_drawn", [str(rect)])
	if is_instance_valid(_world.prod_panel):
		_world.prod_panel.hide_panel()
	if is_instance_valid(_world.hq_red) and rect.has_point(Vector2(_world.hq_red.global_position.x, _world.hq_red.global_position.z)):
		if is_instance_valid(_world.prod_panel):
			_world.prod_panel.show_panel(_world.hq_red)
			if _world.ux_observer and _world.ux_observer.is_enabled():
				_world.ux_observer.mark_ui_dirty()
				_world.ux_observer.on_signal("prod_panel_shown", ["HQ_red"])


func _on_move_command(target: Vector3, selected_units: Array) -> void:
	if is_instance_valid(_world.prod_panel):
		_world.prod_panel.hide_panel()
	for u in selected_units:
		if is_instance_valid(u) and u.has_method("move_to"):
			u.move_to(target)


func _on_produce_requested(unit_type_str: String) -> void:
	if _world.ux_observer and _world.ux_observer.is_enabled():
		_world.ux_observer.on_signal("produce_requested", [unit_type_str])
	var prod = config.production
	var cost_key = unit_type_str + "_cost"
	var time_key = unit_type_str + "_time"
	if not prod.has(cost_key) or not prod.has(time_key):
		push_warning("[BOOT] Unknown unit type for production: %s" % unit_type_str)
		return
	var cost = int(prod[cost_key])
	var time_val = float(prod[time_key])
	if is_instance_valid(_world.hq_red):
		var result = _world.hq_red.enqueue(unit_type_str, cost, time_val)
		if _world.ux_observer and _world.ux_observer.is_enabled():
			_world.ux_observer.on_signal("enqueue_result", [unit_type_str, str(result)])


# ─── Game events ─────────────────────────────────────────────────

func _on_hq_destroyed(team: String) -> void:
	_game_over = true
	var winner = "blue" if team == "red" else "red"
	print("[GAME] HQ_%s destroyed! %s wins!" % [team, winner.to_upper()])
	if not is_headless and is_instance_valid(_world.game_over_ui):
		var hq = _world.hq_red if winner == "red" else _world.hq_blue
		_world.game_over_ui.show_game_over(winner, {
			"survived": _lifecycle.red_alive if winner == "red" else _lifecycle.blue_alive,
			"kills": _lifecycle.kill_log.size(),
			"crystal": hq.crystal if is_instance_valid(hq) else 0,
		})
		if _world.ux_observer and _world.ux_observer.is_enabled():
			_world.ux_observer.on_signal("game_over", [team])
		# 窗口模式游戏结束时输出断言结果，供 AI 调试工具链读取
		renderer.print_results()
	if is_headless:
		renderer.print_results()
		_perf_report()
		_finish()


# ─── FaultInjector setup ─────────────────────────────────────────

func _setup_fault_injector() -> void:
	var fi_config = config.get("fault_injection", [])
	if fi_config.is_empty():
		return
	var FaultScript = load("res://tools/ai-renderer/fault_injector.gd")
	_fault_injector = Node.new()
	_fault_injector.set_script(FaultScript)
	_fault_injector.setup(func(): return _world.units, fi_config)
	add_child(_fault_injector)


# ─── Assertions setup ────────────────────────────────────────────

func _setup_assertions() -> void:
	var AssertionScript = load("res://scripts/assertion_setup.gd")
	_assertions = AssertionScript.new()
	var obstacles = config.get("obstacles", [])
	_assertions.setup(renderer, _lifecycle, _sim_player, _fault_injector, _world.mineral_nodes.size(), obstacles)
	_assertions.register_all()
	if _world.selection_manager:
		renderer.register_ref_holder("SelectionManager", _world.selection_manager.get_all_units)
	# 若 scenario_file 指定了 assertions 列表，限定 Calibrator 只跑这些断言
	var scenario_path = config.get("scenario_file", "")
	if scenario_path != "":
		var f = FileAccess.open(scenario_path, FileAccess.READ)
		if f:
			var scenario = JSON.parse_string(f.get_as_text())
			f.close()
			if scenario and scenario.has("assertions"):
				renderer.get_calibrator().set_run_only(scenario["assertions"])
				print("[BOOT] Calibrator run_only: %s" % str(scenario["assertions"]))
			if scenario and scenario.has("screenshot_on_signals"):
				if _world.ux_observer and _world.ux_observer.is_enabled():
					_world.ux_observer.set_screenshot_signals(scenario["screenshot_on_signals"])


# ─── SimulatedPlayer ─────────────────────────────────────────────

func _setup_simulated_player() -> void:
	var SimPlayerScript = load("res://tools/ai-renderer/simulated_player.gd")
	_sim_player = SimPlayerScript.new()

	# 窗口模式优先使用 window_scenario_file，headless 使用 scenario_file
	var scenario_path: String
	if not is_headless and config.has("window_scenario_file"):
		scenario_path = config.get("window_scenario_file", "")
	else:
		scenario_path = config.get("scenario_file", "")
	if scenario_path != "":
		var loaded = _sim_player.load_scenario(scenario_path)
		if not loaded:
			push_warning("[BOOT] Failed to load scenario '%s', falling back to test_actions" % scenario_path)
			scenario_path = ""
	if scenario_path == "":
		var actions = config.get("test_actions", [])
		if actions.is_empty():
			_sim_player = null
			return
		_sim_player.setup(
			actions, _world.selection_box, _world.selection_manager,
			float(config.map.width), float(config.map.height),
			_on_produce_requested, "xz",
			get_viewport() if not is_headless else null,
		)
	else:
		_sim_player.setup(
			[], _world.selection_box, _world.selection_manager,
			float(config.map.width), float(config.map.height),
			_on_produce_requested, "xz",
			get_viewport() if not is_headless else null,
		)

	var action_count = _sim_player._actions.size()
	var name_prefix = "[%s] " % _sim_player.scenario_name if _sim_player.scenario_name != "" else ""
	print("[BOOT] SimulatedPlayer: %s%d actions queued" % [name_prefix, action_count])


# ─── Config ──────────────────────────────────────────────────────

func _load_config() -> Dictionary:
	var file = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("Failed to open config: %s" % CONFIG_PATH)
		return {}
	var json_text = file.get_as_text()
	file.close()
	var json = JSON.new()
	var err = json.parse(json_text)
	if err != OK:
		push_error("JSON parse error: %s" % json.get_error_message())
		return {}
	var cfg: Dictionary = json.data

	# 若 scenario_file 中包含 config_overrides，浅合并覆盖对应字段
	# 为什么在这里合并：config 在 _ready 最早读取，覆盖必须在任何子系统初始化前生效
	# 窗口模式（非 headless）优先使用 window_scenario_file，否则回退到 scenario_file
	var _headless_now = DisplayServer.get_name() == "headless"
	var scenario_path: String
	if not _headless_now and cfg.has("window_scenario_file"):
		scenario_path = cfg.get("window_scenario_file", "")
	else:
		scenario_path = cfg.get("scenario_file", "")
	if scenario_path != "":
		var sf = FileAccess.open(scenario_path, FileAccess.READ)
		if sf:
			var scenario = JSON.parse_string(sf.get_as_text())
			sf.close()
			if scenario and scenario.has("config_overrides"):
				for key in scenario["config_overrides"]:
					if cfg.has(key) and cfg[key] is Dictionary:
						cfg[key].merge(scenario["config_overrides"][key], true)
					else:
						cfg[key] = scenario["config_overrides"][key]
				print("[BOOT] Applied config_overrides from scenario: %s" % str(scenario["config_overrides"].keys()))
	return cfg


# ─── Finish ──────────────────────────────────────────────────────

func _finish() -> void:
	## 结束当前场景。若 TestRunner 存在，回调结果让它继续跑下一个场景；
	## 否则直接 quit（单场景 / 原始 run_scenarios.sh 模式）。
	## 为什么用 get_node_or_null：避免在普通 headless 运行时报错
	var runner = get_tree().root.get_node_or_null("TestRunner")
	if runner and runner.has_method("on_scenario_done"):
		runner.on_scenario_done(renderer.get_calibrator().get_results())
	else:
		get_tree().quit()


func _abort_scenario(reason: String) -> void:
	## 脚本加载或初始化失败时立即中止，向 TestRunner 报告 fail，不继续跑帧。
	## 为什么需要 abort 而不是直接 quit：TestRunner 需要收到 on_scenario_done
	## 才能继续下一个场景，若直接 quit 整个进程会退出。
	print("[BOOT] ABORT: %s" % reason)
	var runner = get_tree().root.get_node_or_null("TestRunner")
	if runner and runner.has_method("on_scenario_done"):
		runner.on_scenario_done({"__abort__": {"passed": false, "detail": reason}})
	else:
		get_tree().quit(1)


# ─── Performance ─────────────────────────────────────────────────
func _perf_report() -> void:
	var elapsed = Time.get_ticks_msec() - start_time_msec
	var fps = float(frame_count) / (elapsed / 1000.0)
	print("[PERF] frames=%d units=%d elapsed_ms=%d avg_fps=%.1f" % [frame_count, _world.units.size(), elapsed, fps])


# ─── 3D Scene Setup ───────────────────────────────────────────────

func _setup_3d_scene() -> void:
	## 添加 Camera3D（等距正交）和 DirectionalLight3D。
	## 仅在窗口模式调用，headless 下无需摄像机和光照。
	var map_w = float(config.map.width)
	var map_h = float(config.map.height)

	# Camera3D：正交投影，45° 等距视角
	# rotation_degrees(-45, -45, 0)：俯仰 -45° 斜视，偏航 -45° 经典等距方向
	# 居中推导：forward = R_Y(-45)*R_X(-45)*(0,0,-1) = (0.5, -0.707, -0.5)
	#   t = cam_y / |forward.y| = 1500/0.707 ≈ 2121
	#   x_drift = forward.x * t = 0.5 * 2121 ≈ 1061 = cam_height/sqrt(2)
	#   z_drift = forward.z * t = -0.5 * 2121 ≈ -1061
	#   cam_x = map_w/2 - x_drift，cam_z = map_h/2 - z_drift
	# size 2000：地图对角线 ≈ 3606，等距投影后约 2550，size=2000 配合视口宽高比刚好铺满
	var camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2000.0
	var cam_height = 1500.0
	var lateral = cam_height / sqrt(2.0)  # ≈ 1061，视线水平偏移量
	camera.position = Vector3(map_w / 2.0 - lateral, cam_height, map_h / 2.0 + lateral)
	camera.rotation_degrees = Vector3(-45.0, -45.0, 0.0)
	add_child(camera)

	# DirectionalLight3D：光源与视角方向对齐，避免单位正面全黑
	var light = DirectionalLight3D.new()
	light.name = "SunLight"
	light.rotation_degrees = Vector3(-45.0, -45.0, 0.0)
	light.light_energy = 1.0
	light.shadow_enabled = false  # 等距 RTS 阴影无必要，性能优先
	add_child(light)


# ─── Window mode screenshot signals ──────────────────────────────

func _setup_window_screenshot_signals() -> void:
	## 窗口模式下读取 scenario 的 screenshot_on_signals，传给 UXObserver。
	## headless 模式在 _setup_assertions() 里处理同一字段。
	if not (_world.ux_observer and _world.ux_observer.is_enabled()):
		return
	var scenario_path: String
	if config.has("window_scenario_file"):
		scenario_path = config.get("window_scenario_file", "")
	else:
		scenario_path = config.get("scenario_file", "")
	if scenario_path == "":
		return
	var f = FileAccess.open(scenario_path, FileAccess.READ)
	if not f:
		return
	var scenario = JSON.parse_string(f.get_as_text())
	f.close()
	if scenario and scenario.has("screenshot_on_signals"):
		_world.ux_observer.set_screenshot_signals(scenario["screenshot_on_signals"])


# ─── Window assertions setup ──────────────────────────────────────

func _setup_window_assertions() -> void:
	## 窗口模式专属断言注册。
	## 为什么单独一个函数：与 headless 的 _setup_assertions 完全分离，互不干扰。
	var WinAssertScript = load("res://scripts/window_assertion_setup.gd")
	_window_assertions = WinAssertScript.new()
	# expected_drag_count 从 scenario 的 config_overrides.window_test.expected_drag_count 读取；
	# 若未配置（-1），real_drag_selects_correct_count 断言自动跳过精确验证
	var expected_drag_count: int = -1
	var scenario_path: String
	if config.has("window_scenario_file"):
		scenario_path = config.get("window_scenario_file", "")
	else:
		scenario_path = config.get("scenario_file", "")
	if scenario_path != "":
		var f = FileAccess.open(scenario_path, FileAccess.READ)
		if f:
			var scenario = JSON.parse_string(f.get_as_text())
			f.close()
			if scenario and scenario.has("config_overrides"):
				var wt = scenario["config_overrides"].get("window_test", {})
				if wt.has("expected_drag_count"):
					expected_drag_count = int(wt["expected_drag_count"])
	_window_assertions.setup(renderer, _world, self, float(config.map.width), float(config.map.height), expected_drag_count)
	_window_assertions.register_all()
	## 注意：窗口模式不调用 set_run_only，全部 16 条断言均需通过。
	## window_interaction.json 的 assertions 字段仅供未来 headless 窗口场景使用，此处不适用。

	# 连接 action_executor 的 real_click 前置回调：注入点击前通知 window_assertions 设置 _expecting_real_click，
	# 确保 units_selected 信号触发时能正确区分 box_select 引发的选中和 real_click 引发的点选。
	# 为什么在 register_all 之后：两端均已初始化，回调引用安全。
	if _sim_player and _window_assertions:
		_sim_player._executor.set_pre_real_click_cb(func(): _window_assertions.notify_real_click_starting())
