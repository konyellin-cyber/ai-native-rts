extends Node3D

## Phase 20 弓箭手对战演示
## 红方（玩家）：右键控制将领，30 名弓箭手 Phase 19 蛇形纵队跟随，停止展开横阵射击
## 蓝方（AI）：将领静止，弓箭手展开横阵待命，自动攻击进入射程的红方单位

const _GeneralScript      = preload("res://scripts/general_unit.gd")
const _ArcherSoldierScript = preload("res://scripts/archer_soldier.gd")
const _ArrowManagerScript  = preload("res://scripts/arrow_manager.gd")
const _AIRendererScript    = preload("res://tools/ai-renderer/ai_renderer.gd")
const _UXObserverScript    = preload("res://tools/ai-renderer/ux_observer.gd")

var _red_general: CharacterBody3D = null
var _blue_general: CharacterBody3D = null
var _camera: Camera3D = null
var _arrow_manager: Node = null
var _config: Dictionary = {}
var _ground_y: float = 0.0
var _frame: int = 0

var _renderer = null
var _ux_observer = null
var _last_formation_state: String = ""

const MAP_W := 1500.0
const MAP_H := 1000.0
const RED_START  := Vector3(250.0,  0.0, 500.0)
const BLUE_START := Vector3(1250.0, 0.0, 500.0)
const ARCHER_COUNT := 30


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_warning("[ARCHER_BATTLE] headless not supported")
		get_tree().quit()
		return

	_config = _load_config()
	var general_cfg = _load_global_unit_config("general")
	var archer_cfg  = _load_global_unit_config("archer")

	## ArrowManager
	_arrow_manager = Node.new()
	_arrow_manager.set_script(_ArrowManagerScript)
	_arrow_manager.name = "ArrowManager"
	add_child(_arrow_manager)
	_arrow_manager.setup([], false)

	## 红方将领 + 弓箭手
	_red_general = _create_general(0, "red", RED_START, general_cfg)
	var red_archers = _create_archers(_red_general, "red", general_cfg, archer_cfg)
	_red_general.register_dummy_soldiers(red_archers)

	## 蓝方将领 + 弓箭手
	_blue_general = _create_general(1, "blue", BLUE_START, general_cfg)
	var blue_archers = _create_archers(_blue_general, "blue", general_cfg, archer_cfg)
	_blue_general.register_dummy_soldiers(blue_archers)

	_setup_visuals()

	_renderer = _AIRendererScript.new({"mode": "ai_debug", "sample_rate": 30, "calibrate": false})
	_renderer.register("RedFormation", _red_general, ["formation_state", "path_buffer_size"], "formation")

	_ux_observer = _UXObserverScript.new()
	_ux_observer.setup(self, get_viewport(), null, {
		"screenshot_interval": 999999.0,
		"screenshot_dir": "res://tests/screenshots/"
	})

	print("[ARCHER_BATTLE] Ready — 右键移动红方将领 | Space 切换待命")


func _create_general(id: int, team: String, pos: Vector3, cfg: Dictionary) -> CharacterBody3D:
	var g = CharacterBody3D.new()
	g.set_script(_GeneralScript)
	g.setup(id, team, pos, cfg, false, Vector2(MAP_W, MAP_H), null)
	add_child(g)
	return g


func _create_archers(general: Node, team: String, general_cfg: Dictionary,
					 archer_cfg: Dictionary) -> Array:
	var enemy_group = "team_blue" if team == "red" else "team_red"
	var my_group    = "team_red"  if team == "red" else "team_blue"
	var archers: Array = []
	for i in range(ARCHER_COUNT):
		var a = RigidBody3D.new()
		a.set_script(_ArcherSoldierScript)
		a.setup_archer(general, i, ARCHER_COUNT, general_cfg, false,
					   archer_cfg, _arrow_manager, enemy_group)
		a.add_to_group(my_group)
		add_child(a)
		archers.append(a)
	return archers


func _physics_process(_delta: float) -> void:
	_frame += 1

	if _renderer and is_instance_valid(_red_general):
		if _red_general.has_method("get_formation_summary"):
			var summary = _red_general.get_formation_summary()
			_renderer.set_extra(summary)
			var cur_state = _red_general.get("_formation_state")
			if cur_state != _last_formation_state and _last_formation_state != "":
				print("[ARCHER_BATTLE] formation_state: %s → %s (f=%d)" % [
					_last_formation_state, cur_state, _frame])
				if _ux_observer:
					_ux_observer.take_screenshot("state_%s_f%d" % [cur_state, _frame])
			_last_formation_state = cur_state
		_renderer.tick(_frame)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
	   and event.button_index == MOUSE_BUTTON_RIGHT \
	   and event.pressed:
		var target = _raycast_ground(event.position)
		if target != Vector3.ZERO and is_instance_valid(_red_general):
			_red_general.move_to(target)
			print("[ARCHER_BATTLE] move_to (%.0f, 0, %.0f)" % [target.x, target.z])

	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		if is_instance_valid(_red_general):
			_red_general.follow_mode = not _red_general.follow_mode
			print("[ARCHER_BATTLE] follow_mode =", _red_general.follow_mode)


func _raycast_ground(screen_pos: Vector2) -> Vector3:
	if _camera == null:
		return Vector3.ZERO
	var from = _camera.project_ray_origin(screen_pos)
	var dir  = _camera.project_ray_normal(screen_pos)
	if abs(dir.y) < 0.0001:
		return Vector3.ZERO
	var t = (_ground_y - from.y) / dir.y
	if t < 0.0:
		return Vector3.ZERO
	return from + dir * t


func _setup_visuals() -> void:
	var cam_height = MAP_H * 1.2
	var lateral = cam_height / sqrt(2.0)
	var map_diag = sqrt(MAP_W * MAP_W + MAP_H * MAP_H)
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = map_diag * 0.55
	_camera.position = Vector3(MAP_W / 2.0 - lateral, cam_height, MAP_H / 2.0 + lateral)
	_camera.rotation_degrees = Vector3(-45.0, -45.0, 0.0)
	_camera.near = 1.0
	_camera.far = cam_height * 4.0
	add_child(_camera)

	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -45.0, 0.0)
	light.light_energy = 1.2
	add_child(light)

	var ground = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(MAP_W, MAP_H)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.26, 0.20)
	plane.material = mat
	ground.mesh = plane
	ground.position = Vector3(MAP_W / 2.0, -1.0, MAP_H / 2.0)
	add_child(ground)


func _load_config() -> Dictionary:
	var script_path: String = get_script().resource_path
	var path = script_path.get_base_dir() + "/config.json"
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null: return {}
	var text = f.get_as_text(); f.close()
	var result = JSON.parse_string(text)
	return result if result is Dictionary else {}


func _load_global_unit_config(unit_type: String) -> Dictionary:
	var f = FileAccess.open("res://config.json", FileAccess.READ)
	if f == null: return {}
	var text = f.get_as_text(); f.close()
	var cfg = JSON.parse_string(text)
	if cfg is Dictionary:
		return cfg.get(unit_type, {})
	return {}
