extends Node3D

## gamepad_test bootstrap — Phase 23F
## 复用 general_visual 全部逻辑（将领 + 哑兵 + 调试层），新增手柄输入处理。
##
## 操作：
##   左摇杆          → 将领移动（持续推杆时每 20 帧发一次 move_to）
##   右键点击地面    → 将领移动（与鼠标并存）
##   Space           → 切换跟随/待命
##
## 手柄适配：
##   摇杆死区 0.15，超过死区才触发
##   方向映射到等距摄像机的世界坐标方向（-45°/-45° 旋转）

const _GeneralScript    = preload("res://scripts/general_unit.gd")
const _DummyScript      = preload("res://scripts/dummy_soldier.gd")
const _AIRendererScript = preload("res://tools/ai-renderer/ai_renderer.gd")
const _UXObserverScript = preload("res://tools/ai-renderer/ux_observer.gd")

var _general: CharacterBody3D = null
var _camera: Camera3D = null
var _config: Dictionary = {}
var _ground_y: float = 0.0

## AI Renderer + 可视化调试（复用 general_visual）
var _renderer = null
var _ux_observer = null
var _last_formation_state: String = ""
var _frame: int = 0
var _debug_lines: Array = []
var _debug_waiting: Array = []
var _debug_path_dots: Array = []

## 手柄输入状态
const _GAMEPAD_DEADZONE: float = 0.15       ## 摇杆死区
const _GAMEPAD_MOVE_INTERVAL: int = 20      ## 持续推杆时每 N 帧发一次 move_to
const _GAMEPAD_MOVE_DIST: float = 200.0     ## 每次 move_to 的前进距离
var _gamepad_timer: int = 0                 ## 距上次发出 move_to 的帧数
var _gamepad_active: bool = false           ## 上帧是否有推杆输入

## deployed 收敛追踪
var _deployed_since_frame: int = -1
var _last_deploy_screenshot_frame: int = -1
const _DEPLOY_SCREENSHOT_INTERVAL: int = 60


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_warning("[GAMEPAD] Headless mode — scene is window-only")
		get_tree().quit()
		return

	_config = _load_config()
	if _config.is_empty():
		push_error("[GAMEPAD] Failed to load config")
		return

	var map_size = Vector2(
		float(_config.get("map", {}).get("width", 1000.0)),
		float(_config.get("map", {}).get("height", 1000.0))
	)
	var general_cfg: Dictionary = _load_global_unit_config("general")

	_general = CharacterBody3D.new()
	_general.set_script(_GeneralScript)
	_general.setup(0, "red", Vector3(map_size.x / 2.0, 0.0, map_size.y / 2.0),
		general_cfg, false, map_size, null)
	add_child(_general)

	var count = int(general_cfg.get("dummy_soldier_count", 30))
	var soldiers: Array = []
	for i in range(count):
		var dummy = RigidBody3D.new()
		dummy.set_script(_DummyScript)
		dummy.setup(_general, i, count, general_cfg, false)
		add_child(dummy)
		soldiers.append(dummy)
	_general.register_dummy_soldiers(soldiers)

	_setup_visuals(map_size)

	_renderer = _AIRendererScript.new({"mode": "ai_debug", "sample_rate": 30, "calibrate": false})
	_renderer.register("Formation", _general, ["formation_state", "path_buffer_size"], "formation")

	_ux_observer = _UXObserverScript.new()
	_ux_observer.setup(self, get_viewport(), null, {
		"screenshot_interval": 999999.0,
		"screenshot_dir": "res://tests/screenshots/"
	})
	_last_formation_state = _general.get("_formation_state") if is_instance_valid(_general) else ""

	## 打印已连接手柄
	var pads = Input.get_connected_joypads()
	if pads.is_empty():
		print("[GAMEPAD] 未检测到手柄 — 可使用鼠标右键控制")
	else:
		for pad_id in pads:
			print("[GAMEPAD] 手柄已连接: id=%d name=%s" % [pad_id, Input.get_joy_name(pad_id)])

	print("[GAMEPAD] Ready — dummies=%d  左摇杆/右键移动 Space切换待命 算法=%s" % [
		count, general_cfg.get("march_algorithm", "path_follow")
	])


func _physics_process(_delta: float) -> void:
	_frame += 1
	_process_gamepad()

	if _renderer and is_instance_valid(_general) and _general.has_method("get_formation_summary"):
		var summary = _general.get_formation_summary()
		_renderer.set_extra(summary)
		var cur_state = _general.get("_formation_state")

		if cur_state != _last_formation_state and _last_formation_state != "":
			print("[GAMEPAD] formation_state: %s → %s (frame=%d)" % [_last_formation_state, cur_state, _frame])
			if _ux_observer:
				_ux_observer.take_screenshot("state_%s_f%d" % [cur_state, _frame])
			if cur_state == "deployed":
				_deployed_since_frame = _frame
				_last_deploy_screenshot_frame = _frame
			else:
				_deployed_since_frame = -1
		_last_formation_state = cur_state

		if cur_state == "deployed" and _deployed_since_frame >= 0:
			var t = _frame - _deployed_since_frame
			if _frame - _last_deploy_screenshot_frame >= _DEPLOY_SCREENSHOT_INTERVAL:
				_last_deploy_screenshot_frame = _frame
				if _ux_observer:
					_ux_observer.take_screenshot("deployed_%ds" % (t / 60))

		if _frame % 10 == 0:
			var avg_err = summary.get("avg_slot_error", -1)
			var waiting = summary.get("waiting_count", -1)
			var coh = summary.get("velocity_coherence", -1)
			var freeze_r = summary.get("freeze_rate", 0.0)
			print("[DBG f=%d] state=%s avg_err=%.1f waiting=%d coh=%.2f freeze=%.0f%% gamepad=%s" % [
				_frame, cur_state, avg_err, waiting, coh, freeze_r * 100.0,
				str(_gamepad_active)
			])

		_renderer.tick(_frame)

	_update_debug_visuals()


## 手柄输入处理：每帧读取左摇杆，超过死区且到达间隔时发出 move_to
func _process_gamepad() -> void:
	if not is_instance_valid(_general):
		return

	## 读取所有已连接手柄的左摇杆（取第一个有效输入）
	var axis_x: float = 0.0
	var axis_y: float = 0.0
	for pad_id in Input.get_connected_joypads():
		var ax = Input.get_joy_axis(pad_id, JOY_AXIS_LEFT_X)
		var ay = Input.get_joy_axis(pad_id, JOY_AXIS_LEFT_Y)
		if abs(ax) > _GAMEPAD_DEADZONE or abs(ay) > _GAMEPAD_DEADZONE:
			axis_x = ax
			axis_y = ay
			break

	var magnitude = sqrt(axis_x * axis_x + axis_y * axis_y)
	if magnitude < _GAMEPAD_DEADZONE:
		## 死区内：停止发新指令，将领自然停止
		_gamepad_active = false
		_gamepad_timer = _GAMEPAD_MOVE_INTERVAL  ## 重置计时器，松开后再推杆立即响应
		return

	_gamepad_active = true
	_gamepad_timer += 1
	if _gamepad_timer < _GAMEPAD_MOVE_INTERVAL:
		return
	_gamepad_timer = 0

	## 摇杆方向 → 世界坐标（等距摄像机 -45°/-45°）
	## 摄像机绕 Y 轴旋转 -45°，摇杆 (x, y) 对应世界 (右, 前)
	## 摇杆向上 (axis_y=-1) = 世界前方；摇杆向右 (axis_x=1) = 世界右方
	var cam_yaw_rad: float = deg_to_rad(-45.0)
	var world_x = axis_x * cos(cam_yaw_rad) - axis_y * sin(cam_yaw_rad)
	var world_z = axis_x * sin(cam_yaw_rad) + axis_y * cos(cam_yaw_rad)
	var world_dir = Vector3(world_x, 0.0, world_z).normalized()

	var target = _general.global_position + world_dir * _GAMEPAD_MOVE_DIST
	target.y = 0.0
	_general.move_to(target)


func _unhandled_input(event: InputEvent) -> void:
	## 鼠标右键移动（与手柄并存）
	if event is InputEventMouseButton \
	   and event.button_index == MOUSE_BUTTON_RIGHT \
	   and event.pressed:
		if not is_instance_valid(_general):
			return
		var target = _raycast_ground(event.position)
		if target != Vector3.ZERO:
			_general.move_to(target)
			print("[GAMEPAD] mouse move_to (%.0f, 0, %.0f)" % [target.x, target.z])
			if _ux_observer:
				_ux_observer.take_screenshot("move_cmd_f%d" % _frame)


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


func _update_debug_visuals() -> void:
	if not is_instance_valid(_general):
		return
	for node in _debug_lines + _debug_waiting + _debug_path_dots:
		if is_instance_valid(node):
			node.queue_free()
	_debug_lines.clear()
	_debug_waiting.clear()
	_debug_path_dots.clear()

	var soldiers = _general.get("_dummy_soldiers") if _general.get("_dummy_soldiers") != null else []
	var total = soldiers.size()
	for i in range(total):
		var s = soldiers[i]
		if not is_instance_valid(s):
			continue
		var ideal = _general.get_formation_slot(i, total, s.global_position)
		var err = s.global_position.distance_to(ideal)
		var is_waiting = err < 1.0 and _general.get_formation_state() == "marching"
		if is_waiting:
			var marker = _make_sphere(s.global_position + Vector3(0, 15, 0), 5.0, Color(1, 0.1, 0.1))
			add_child(marker)
			_debug_waiting.append(marker)
		else:
			_make_line(s.global_position + Vector3(0, 5, 0), ideal + Vector3(0, 5, 0), Color(0.1, 0.9, 0.2))

	var pb = _general.get("_path_buffer") if _general.get("_path_buffer") != null else []
	for j in range(min(pb.size(), 20)):
		var dot = _make_sphere(pb[j] + Vector3(0, 3, 0), 3.0, Color(1.0, 0.9, 0.1))
		add_child(dot)
		_debug_path_dots.append(dot)


func _make_sphere(pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var inst = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = mat
	inst.mesh = sphere
	inst.position = pos
	return inst


func _make_line(from: Vector3, to: Vector3, color: Color) -> void:
	var diff = to - from
	var length = diff.length()
	if length < 1.0:
		return
	var inst = MeshInstance3D.new()
	var capsule = CapsuleMesh.new()
	capsule.radius = 1.5
	capsule.height = length
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	capsule.material = mat
	inst.mesh = capsule
	inst.position = (from + to) * 0.5
	if diff.length_squared() > 0.001:
		inst.basis = Basis.looking_at(diff.normalized(), Vector3.UP).rotated(
			Basis.looking_at(diff.normalized(), Vector3.UP).x, PI * 0.5)
	add_child(inst)
	_debug_lines.append(inst)


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
