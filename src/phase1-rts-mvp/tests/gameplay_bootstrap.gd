extends Node3D

## GameplayBootstrap — 将领 / 兵团玩法测试公共基类
## 职责：读本场景 config.json → 按 units 数组生成单位（含 general）→ 初始化 Calibrator → 帧驱动
##
## 与 combat_bootstrap 的区别：
##   - 支持 "general" 类型单位生成
##   - 不包含 ArrowManager（将领测试不需要弹道）
##   - 支持在 _ready 之后用 move_to() 注入移动指令

const _AIRendererScript = preload("res://tools/ai-renderer/ai_renderer.gd")
const _GeneralScript    = preload("res://scripts/general_unit.gd")
const _DummyScript      = preload("res://scripts/dummy_soldier.gd")

var _config: Dictionary = {}
var _units: Array = []
var _frame_count: int = 0
var _total_frames: int = 600
var _is_headless: bool = false
var _renderer: RefCounted
var _start_msec: int = 0


func _ready() -> void:
	name = "GameplayBootstrap"
	_is_headless = DisplayServer.get_name() == "headless"
	_start_msec = Time.get_ticks_msec()

	_config = _load_config()
	if _config.is_empty():
		push_error("[GAMEPLAY] Failed to load config: %s" % _get_config_path())
		_abort_scenario("Failed to load config")
		return

	_total_frames = int(_config.get("physics", {}).get("total_frames", 600))
	Engine.set_physics_ticks_per_second(int(_config.get("physics", {}).get("fps", 60)))

	_renderer = _AIRendererScript.new({"mode": "off", "sample_rate": 60, "calibrate": true})

	_spawn_units()
	_post_spawn()
	_register_assertions()

	if not _is_headless:
		_setup_scene_visuals()

	print("[GAMEPLAY] %s — %d units, %d frames max" % [
		_config.get("name", "unnamed"),
		_units.size(),
		_total_frames
	])


func _physics_process(_delta: float) -> void:
	_frame_count += 1

	# 清理死亡单位
	var i = _units.size() - 1
	while i >= 0:
		if not is_instance_valid(_units[i]):
			_units.remove_at(i)
		i -= 1

	var all_done = _renderer.tick()
	if all_done or _frame_count >= _total_frames:
		if all_done:
			print("[GAMEPLAY] Early exit at frame %d (all assertions resolved)" % _frame_count)
		_renderer.print_results()
		_perf_report()
		_finish()


## 子类覆盖此方法，在所有单位 spawn 后注入指令（如 move_to）
func _post_spawn() -> void:
	pass


## 子类覆盖此方法注册专项断言
func _register_assertions() -> void:
	pass


# ─── 单位生成 ─────────────────────────────────────────────────────

func _spawn_units() -> void:
	var unit_cfgs: Array = _config.get("units", [])
	for ucfg in unit_cfgs:
		var unit_type: String = ucfg.get("type", "fighter")
		var team: String = ucfg.get("team", "red")
		var x: float = float(ucfg.get("x", 250.0))
		var z: float = float(ucfg.get("z", 250.0))
		var pos = Vector3(x, 0.0, z)

		match unit_type:
			"general":
				_spawn_general(team, pos, ucfg)
			_:
				push_warning("[GAMEPLAY] Unknown unit type: %s" % unit_type)


func _spawn_general(team: String, pos: Vector3, overrides: Dictionary) -> void:
	## 从主 config.json 读 general 段，overrides 允许场景覆盖（如 hp=1）
	var general_cfg: Dictionary = _load_global_unit_config("general").duplicate()
	for key in overrides:
		if key not in ["type", "team", "x", "z"]:
			general_cfg[key] = overrides[key]

	## general_unit.gd 继承 base_unit → CharacterBody3D，必须用 CharacterBody3D.new()
	var general = CharacterBody3D.new()
	general.set_script(_GeneralScript)

	var map_size = _get_map_size()

	## setup 必须在 add_child 之前：_ready 会找 $NavAgent，setup 负责 add_child(NavAgent)
	general.setup(_units.size(), team, pos, general_cfg, _is_headless, map_size, null)

	add_child(general)
	_units.append(general)

	## 如果 config 里声明需要哑兵，则按照配置生成
	var spawn_dummies: bool = bool(overrides.get("spawn_dummies", false))
	if spawn_dummies:
		_spawn_dummy_soldiers(general, general_cfg)


func _spawn_dummy_soldiers(general: CharacterBody3D, general_cfg: Dictionary) -> void:
	## 按 general_cfg.dummy_soldier_count 为此将领生成哑兵
	var count = int(general_cfg.get("dummy_soldier_count", 30))
	var soldiers: Array = []
	for i in range(count):
		var dummy = RigidBody3D.new()
		dummy.set_script(_DummyScript)
		dummy.setup(general, i, count, general_cfg, _is_headless)
		add_child(dummy)
		soldiers.append(dummy)
	general.register_dummy_soldiers(soldiers)
	print("[GAMEPLAY] Spawned %d dummy soldiers" % count)

	## 15C：监听补兵信号
	general.replenish_requested.connect(func(g: Node): _on_replenish_requested(g))


func _on_replenish_requested(general: Node) -> void:
	## 15C：收到补兵请求，创建新哑兵并注入将领
	if not is_instance_valid(general):
		return
	var cfg: Dictionary = general.get_general_cfg()
	var count: int = general.get_dummy_count()
	var add_count: int = int(cfg.get("replenish_count", 3))
	for i in range(add_count):
		var dummy = RigidBody3D.new()
		dummy.set_script(_DummyScript)
		dummy.setup(general, count + i, count + add_count, cfg, _is_headless)
		add_child(dummy)
		general.add_dummy_soldier(dummy)


# ─── 工具 ────────────────────────────────────────────────────────

func _get_config_path() -> String:
	var script_path: String = get_script().resource_path
	return script_path.get_base_dir() + "/config.json"


func _load_config() -> Dictionary:
	var path = _get_config_path()
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text = f.get_as_text()
	f.close()
	var result = JSON.parse_string(text)
	return result if result is Dictionary else {}


func _load_global_unit_config(unit_type: String) -> Dictionary:
	var f = FileAccess.open("res://config.json", FileAccess.READ)
	if f == null:
		return {}
	var text = f.get_as_text()
	f.close()
	var cfg = JSON.parse_string(text)
	if cfg is Dictionary:
		return cfg.get(unit_type, {})
	return {}


func _get_map_size() -> Vector2:
	return Vector2(
		float(_config.get("map", {}).get("width", 500.0)),
		float(_config.get("map", {}).get("height", 500.0))
	)


func _perf_report() -> void:
	var elapsed = Time.get_ticks_msec() - _start_msec
	var fps = float(_frame_count) / (elapsed / 1000.0) if elapsed > 0 else 0.0
	print("[PERF] frames=%d units=%d elapsed_ms=%d avg_fps=%.1f" % [
		_frame_count, _units.size(), elapsed, fps
	])


func _setup_scene_visuals() -> void:
	var map_w = float(_config.get("map", {}).get("width", 500.0))
	var map_h = float(_config.get("map", {}).get("height", 500.0))

	var cam_height = map_h * 3.0
	var lateral = cam_height / sqrt(2.0)
	var map_diag = sqrt(map_w * map_w + map_h * map_h)
	var cam_size = map_diag * 0.85

	var camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = cam_size
	camera.position = Vector3(map_w / 2.0 - lateral, cam_height, map_h / 2.0 + lateral)
	camera.rotation_degrees = Vector3(-45.0, -45.0, 0.0)
	camera.near = 1.0
	camera.far = cam_height * 4.0
	add_child(camera)

	var light = DirectionalLight3D.new()
	light.name = "SunLight"
	light.rotation_degrees = Vector3(-45.0, -45.0, 0.0)
	light.light_energy = 1.0
	light.shadow_enabled = false
	add_child(light)

	var ground = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(map_w, map_h)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.28, 0.22)
	plane.material = mat
	ground.mesh = plane
	ground.position = Vector3(map_w / 2.0, -1.0, map_h / 2.0)
	add_child(ground)


func _finish() -> void:
	var runner = get_tree().root.get_node_or_null("TestRunner")
	if runner and runner.has_method("on_scenario_done"):
		var results = {}
		if _renderer.get_calibrator():
			results = _renderer.get_calibrator().get_results()
		runner.on_scenario_done(results)
	else:
		get_tree().quit()


func _abort_scenario(reason: String) -> void:
	print("[GAMEPLAY] ABORT: %s" % reason)
	var runner = get_tree().root.get_node_or_null("TestRunner")
	if runner and runner.has_method("on_scenario_done"):
		runner.on_scenario_done({"__abort__": {"passed": false, "detail": reason}})
	else:
		get_tree().quit(1)
