extends RigidBody3D
class_name DummySoldier

## Phase 17 哑兵 — RigidBody3D + Seek Force 物理碰撞版本。
## 移动方式：每帧向槽位施加驱动力（apply_central_force），高阻尼自然减速。
## 单位间碰撞由物理引擎自动处理，无需手写分离力。
## follow_mode = false 时：linear_velocity 锁定为零，不施力。
##
## [Phase 16 → 17 变更]
## 旧：extends Node3D，_move_toward() 直接位移
## 新：extends RigidBody3D，apply_central_force() 力驱动

var _general: Node = null          ## 跟随的将领（general_unit.gd 实例）
var _soldier_index: int = 0        ## 在兵团中的编号（0-based）
var _total_count: int = 30         ## 兵团总兵力
var _collision_radius: float = 7.0 ## 碰撞胶囊半径

var _is_headless: bool = false
var _standby_pos: Vector3 = Vector3.ZERO   ## 待命时的锁定位置（接口保留）

## Phase 17 物理参数（从 config 读取）
var _drive_strength: float = 400.0    ## Seek Force 驱动力强度
var _arrive_threshold: float = 8.0    ## 到达阈值：距槽位 < 此值时停止施力，靠阻尼减速防抖


func setup(general: Node, index: int, total: int, cfg: Dictionary, headless: bool) -> void:
	_general = general
	_soldier_index = index
	_total_count = total
	_collision_radius = float(cfg.get("radius", 12.0)) * float(cfg.get("dummy_collision_radius_factor", 0.55))
	_drive_strength = float(cfg.get("dummy_drive_strength", 400.0))
	_arrive_threshold = float(cfg.get("dummy_arrive_threshold", 8.0))
	_is_headless = headless
	name = "Dummy_%d" % index

	## RigidBody3D 物理属性：从 config 读取 mass / linear_damp
	mass = float(cfg.get("dummy_mass", 1.0))
	linear_damp = float(cfg.get("dummy_linear_damp", 8.0))

	## 锁定所有旋转轴（防止单位翻倒），锁定 Y 轴线速度（只在 XZ 平面运动）
	axis_lock_angular_x = true
	axis_lock_angular_y = true
	axis_lock_angular_z = true
	axis_lock_linear_y = true

	## 碰撞层：哑兵 Layer 3（bit 2 = 4），碰地形(1) + 主战(2) + 哑兵(4)
	collision_layer = 4
	collision_mask = 1 | 2 | 4

	## 添加胶囊碰撞体
	var shape_node = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = _collision_radius
	capsule.height = _collision_radius * 2.5
	shape_node.shape = capsule
	add_child(shape_node)

	## 初始位置：直接使用阵型槽位（setup 在 add_child 前调用，position == global_position）
	if is_instance_valid(_general) and _general.has_method("get_formation_slot"):
		position = _general.get_formation_slot(index, total)
	elif is_instance_valid(_general):
		position = _general.get_anchor_position()

	if not headless:
		_add_visual()


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_general):
		return

	var follow_mode: bool = _general.get("follow_mode") if _general.get("follow_mode") != null else true

	if not follow_mode:
		## 待命模式：锁定速度为零，不施力
		linear_velocity = Vector3.ZERO
		return

	## 跟随模式：Seek Force 驱动
	if not _general.has_method("get_formation_slot"):
		return

	var target = _general.get_formation_slot(_soldier_index, _total_count)
	var dist = global_position.distance_to(target)

	if dist > _arrive_threshold:
		## 距槽位较远：施加朝向槽位的驱动力，物理引擎处理碰撞推挤
		var dir = (target - global_position)
		dir.y = 0.0
		if dir.length_squared() > 0.001:
			apply_central_force(dir.normalized() * _drive_strength)
	## 距槽位 <= arrive_threshold：停止施力，靠 linear_damp 自然减速到零（防抖）


func freeze_at_current() -> void:
	## 将领切换到待命模式时调用（接口保留供 general_unit 调用）
	_standby_pos = global_position


func _add_visual() -> void:
	var mesh_inst = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	var vis_r = _collision_radius * 0.9
	cylinder.top_radius = vis_r
	cylinder.bottom_radius = vis_r
	cylinder.height = vis_r * 2.5
	var mat = StandardMaterial3D.new()
	## 哑兵颜色：红方暗红，蓝方深蓝，与将领金/银色有区别
	if is_instance_valid(_general):
		var team = _general.get("team_name") if _general.get("team_name") != null else "red"
		mat.albedo_color = Color(0.7, 0.1, 0.1) if team == "red" else Color(0.1, 0.2, 0.7)
	else:
		mat.albedo_color = Color(0.5, 0.5, 0.5)
	cylinder.material = mat
	mesh_inst.mesh = cylinder
	mesh_inst.position = Vector3(0.0, vis_r * 1.25, 0.0)
	add_child(mesh_inst)
