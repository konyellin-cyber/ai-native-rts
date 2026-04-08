extends Node3D

## general_visual bootstrap — 15B.15
## 独立干净的目视演示场景：将领 + 哑兵，无 HQ / 工人 / 矿点 / AI / UI。
## 直接继承 Node3D，不走 GameplayBootstrap 的 calibrator/断言链路。
##
## 操作：
##   右键点击地面 → 将领带队移动
##   Space         → 切换跟随/待命（将领头顶标签变色）
##   手动关窗口   → 退出

const _GeneralScript = preload("res://scripts/general_unit.gd")
const _DummyScript   = preload("res://scripts/dummy_soldier.gd")

var _general: CharacterBody3D = null
var _camera: Camera3D = null
var _config: Dictionary = {}
var _is_headless: bool = false
var _ground_y: float = 0.0


func _ready() -> void:
	_is_headless = DisplayServer.get_name() == "headless"
	if _is_headless:
		## 目视演示场景不应在 headless 下运行（scene_registry 已标 window_mode=true）
		push_warning("[VISUAL] Headless mode detected — scene intended for window mode only")
		get_tree().quit()
		return

	_config = _load_config()
	if _config.is_empty():
		push_error("[VISUAL] Failed to load config")
		return

	var map_size = Vector2(
		float(_config.get("map", {}).get("width", 1000.0)),
		float(_config.get("map", {}).get("height", 1000.0))
	)
	var general_cfg: Dictionary = _load_global_unit_config("general")

	## 生成将领
	_general = CharacterBody3D.new()
	_general.set_script(_GeneralScript)
	_general.setup(0, "red", Vector3(map_size.x / 2.0, 0.0, map_size.y / 2.0),
		general_cfg, false, map_size, null)
	add_child(_general)

	## 生成哑兵
	var count = int(general_cfg.get("dummy_soldier_count", 30))
	var soldiers: Array = []
	for i in range(count):
		var dummy = RigidBody3D.new()
		dummy.set_script(_DummyScript)
		dummy.setup(_general, i, count, general_cfg, false)
		add_child(dummy)
		soldiers.append(dummy)
	_general.register_dummy_soldiers(soldiers)

	## 相机、灯光、地面
	_setup_visuals(map_size)

	print("[VISUAL] Ready — general=%s  dummies=%d" % [_general.name, count])
	print("[VISUAL] Controls: right-click=move  Space=follow/standby")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
	   and event.button_index == MOUSE_BUTTON_RIGHT \
	   and event.pressed:
		if _general == null or not is_instance_valid(_general):
			return
		var target = _raycast_ground(event.position)
		if target != Vector3.ZERO:
			_general.move_to(target)
			print("[VISUAL] move_to (%.0f, 0, %.0f)" % [target.x, target.z])


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


func _setup_visuals(map_size: Vector2) -> void:
	var map_w = map_size.x
	var map_h = map_size.y

	var cam_height = map_h * 1.2
	var lateral = cam_height / sqrt(2.0)
	var map_diag = sqrt(map_w * map_w + map_h * map_h)

	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = map_diag * 0.55
	_camera.position = Vector3(map_w / 2.0 - lateral, cam_height, map_h / 2.0 + lateral)
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
	plane.size = Vector2(map_w, map_h)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.26, 0.20)
	plane.material = mat
	ground.mesh = plane
	ground.position = Vector3(map_w / 2.0, -1.0, map_h / 2.0)
	add_child(ground)


func _load_config() -> Dictionary:
	var script_path: String = get_script().resource_path
	var path = script_path.get_base_dir() + "/config.json"
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
