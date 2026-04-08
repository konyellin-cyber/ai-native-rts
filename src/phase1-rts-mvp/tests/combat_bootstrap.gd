extends Node3D

## CombatBootstrap — 战斗专项测试场景公共基类
## 职责：读本场景 config.json → 按 units 数组生成单位 → 初始化 Calibrator → 帧驱动 → _finish()
##
## 特意不包含：地图生成、经济系统、AI 对手、NavigationAgent
## 单位使用直线移动（nav_available=false fallback），500×500 平坦地图
##
## 接口约定：
##   - 场景目录下必须有 config.json（通过 _get_config_path() 定位）
##   - 子类可覆盖 _register_assertions() 添加额外断言
##   - _finish() 与主游戏 bootstrap 完全一致，TestRunner 无需区分来源

const _AIRendererScript  = preload("res://tools/ai-renderer/ai_renderer.gd")
const _CalibratorScript  = preload("res://tools/ai-renderer/calibrator.gd")
const _FighterScript     = preload("res://scripts/fighter.gd")
const _ArcherScript      = preload("res://scripts/archer.gd")
const _ArrowManagerScript = preload("res://scripts/arrow_manager.gd")

var _config: Dictionary = {}
var _units: Array = []
var _kill_log: Array = []
var _frame_count: int = 0
var _total_frames: int = 7200
var _is_headless: bool = false
var _renderer: RefCounted   ## AIRenderer（只用 Calibrator，mode=off）
var _arrow_manager: Node = null
var _start_msec: int = 0


func _ready() -> void:
	name = "CombatBootstrap"
	_is_headless = DisplayServer.get_name() == "headless"
	_start_msec = Time.get_ticks_msec()

	_config = _load_config()
	if _config.is_empty():
		push_error("[COMBAT] Failed to load config: %s" % _get_config_path())
		_abort_scenario("Failed to load config")
		return

	_total_frames = int(_config.get("physics", {}).get("total_frames", 7200))
	Engine.set_physics_ticks_per_second(int(_config.get("physics", {}).get("fps", 60)))

	# Renderer：mode=off（不输出 AI debug），只开 calibrate
	_renderer = _AIRendererScript.new({"mode": "off", "sample_rate": 60, "calibrate": true})

	# ArrowManager：供 archer 使用，无障碍物（战斗场景平坦地图）
	_arrow_manager = Node.new()
	_arrow_manager.set_script(_ArrowManagerScript)
	_arrow_manager.name = "ArrowManager"
	add_child(_arrow_manager)
	var obstacles = _config.get("obstacles", [])
	var arrow_speed = float(_config.get("archer", {}).get("arrow_speed", 600.0))
	_arrow_manager.setup(obstacles, _is_headless, arrow_speed)

	_spawn_units()
	_register_assertions()

	if not _is_headless:
		_setup_scene_visuals()

	print("[COMBAT] %s — %d units, %d frames max" % [
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
			print("[COMBAT] Early exit at frame %d (all assertions resolved)" % _frame_count)
		_renderer.print_results()
		_perf_report()
		_finish()


# ─── 单位生成 ────────────────────────────────────────────────────

func _spawn_units() -> void:
	var unit_cfgs: Array = _config.get("units", [])
	for ucfg in unit_cfgs:
		var unit_type: String = ucfg.get("type", "fighter")
		var team: String = ucfg.get("team", "red")
		var x: float = float(ucfg.get("x", 250.0))
		var z: float = float(ucfg.get("z", 250.0))
		var pos = Vector3(x, 0.0, z)

		match unit_type:
			"fighter":
				_spawn_fighter(team, pos, ucfg)
			"archer":
				_spawn_archer(team, pos, ucfg)
			_:
				push_warning("[COMBAT] Unknown unit type: %s" % unit_type)


func _spawn_fighter(team: String, pos: Vector3, overrides: Dictionary) -> void:
	var fighter_cfg: Dictionary = _config.get("fighter", {}).duplicate()
	# 允许场景 config 里的 units 条目覆盖默认参数
	for key in overrides:
		if key not in ["type", "team", "x", "z"]:
			fighter_cfg[key] = overrides[key]

	# 用全局 config.json 的 fighter 段作为基础参数
	var global_cfg = _load_global_unit_config("fighter")
	for key in global_cfg:
		if not fighter_cfg.has(key):
			fighter_cfg[key] = global_cfg[key]

	## 为什么用 CharacterBody3D.new() 而非 Node3D.new()：
	## fighter.gd 继承自 CharacterBody3D，set_script 要求节点类型与脚本基类一致，
	## 用 Node3D 会报 "Script inherits from native type 'CharacterBody3D'" 并静默失败。
	var fighter = CharacterBody3D.new()
	fighter.set_script(_FighterScript)

	var map_size = _get_map_size()

	## setup() 必须在 add_child() 之前调用：
	## fighter._ready() 在 add_child 时立即执行，会去找 $NavAgent。
	## setup() 负责 add_child(NavAgent)，必须先跑完，_ready 才能找到它。
	fighter.setup(
		_units.size(),  # unit_id
		team,
		pos,
		fighter_cfg,
		_is_headless,
		map_size,
		null  # home_hq：战斗场景无基地
	)

	add_child(fighter)
	fighter.died.connect(_on_unit_died)
	_units.append(fighter)


func _spawn_archer(team: String, pos: Vector3, overrides: Dictionary) -> void:
	var archer_cfg: Dictionary = _config.get("archer", {}).duplicate()
	for key in overrides:
		if key not in ["type", "team", "x", "z"]:
			archer_cfg[key] = overrides[key]

	var global_cfg = _load_global_unit_config("archer")
	for key in global_cfg:
		if not archer_cfg.has(key):
			archer_cfg[key] = global_cfg[key]

	var archer = CharacterBody3D.new()
	archer.set_script(_ArcherScript)

	var map_size = _get_map_size()

	## archer.setup() 需要额外的 arrow_manager 参数
	archer.setup(
		_units.size(),  # unit_id
		team,
		pos,
		archer_cfg,
		_is_headless,
		map_size,
		null,            # home_hq：战斗场景无基地
		_arrow_manager   # ArrowManager 引用
	)

	add_child(archer)
	archer.died.connect(_on_unit_died)
	_units.append(archer)


func _on_unit_died(unit_id: int, team: String) -> void:
	_kill_log.append({"frame": _frame_count, "id": unit_id, "team": team})


# ─── 断言注册（子类可覆盖扩展）─────────────────────────────────────

func _register_assertions() -> void:
	## 所有战斗场景共用的基础断言
	_renderer.add_assertion("battle_resolution", _assert_battle_resolution)

	## 读取场景 config 中的 assertions 列表，限定 Calibrator 只跑指定断言
	var assertions: Array = _config.get("assertions", [])
	if not assertions.is_empty():
		_renderer.get_calibrator().set_run_only(assertions)
		print("[COMBAT] run_only: %s" % str(assertions))


func _assert_battle_resolution() -> Dictionary:
	if _kill_log.size() > 0:
		return {"status": "pass", "detail": "kills=%d" % _kill_log.size()}
	return {"status": "pending", "detail": "no kills yet"}


# ─── 工具 ────────────────────────────────────────────────────────

func _get_config_path() -> String:
	## 场景 config.json 与 scene.tscn 在同一目录下
	## 通过脚本路径推导：res://tests/core/<name>/bootstrap.gd → res://tests/core/<name>/config.json
	var script_path: String = get_script().resource_path  # e.g. res://tests/core/smoke_test/bootstrap.gd
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
	## 从主游戏 config.json 读取指定单位类型的基础参数作为默认值
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
	## 窗口模式：复用主场景相同的等距正交相机 + 光照 + 地面。
	## 相机参数与 bootstrap._setup_3d_scene() 完全一致。
	var map_w = float(_config.get("map", {}).get("width", 500.0))
	var map_h = float(_config.get("map", {}).get("height", 500.0))

	# 等距正交相机（45° 俯仰，-45° 偏航）
	# size 根据地图对角线自适应：主场景 map≈2560×1664 → size=2000
	# 战斗场景 map=500×500 → size ≈ 2000 * (500/2560) * sqrt(2) ≈ 552，向上取整留余白
	var cam_height = map_h * 3.0
	var lateral = cam_height / sqrt(2.0)
	var map_diag = sqrt(map_w * map_w + map_h * map_h)
	var cam_size = map_diag * 0.85   ## 覆盖地图对角线，留 15% 余白

	var camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = cam_size
	camera.position = Vector3(map_w / 2.0 - lateral, cam_height, map_h / 2.0 + lateral)
	camera.rotation_degrees = Vector3(-45.0, -45.0, 0.0)
	camera.near = 1.0
	camera.far = cam_height * 4.0
	add_child(camera)

	# 平行光：与视角方向一致，避免单位正面全黑
	var light = DirectionalLight3D.new()
	light.name = "SunLight"
	light.rotation_degrees = Vector3(-45.0, -45.0, 0.0)
	light.light_energy = 1.0
	light.shadow_enabled = false
	add_child(light)

	# 地面（深色平面，突出单位颜色）
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
	## 与主游戏 bootstrap._finish() 接口完全一致：
	## 找到 TestRunner 则回调，否则直接 quit。
	var runner = get_tree().root.get_node_or_null("TestRunner")
	if runner and runner.has_method("on_scenario_done"):
		var results = {}
		if _renderer.get_calibrator():
			results = _renderer.get_calibrator().get_results()
		runner.on_scenario_done(results)
	else:
		get_tree().quit()


func _abort_scenario(reason: String) -> void:
	## 初始化失败时立即中止，向 TestRunner 报告 fail，不继续跑帧。
	print("[COMBAT] ABORT: %s" % reason)
	var runner = get_tree().root.get_node_or_null("TestRunner")
	if runner and runner.has_method("on_scenario_done"):
		runner.on_scenario_done({"__abort__": {"passed": false, "detail": reason}})
	else:
		get_tree().quit(1)
