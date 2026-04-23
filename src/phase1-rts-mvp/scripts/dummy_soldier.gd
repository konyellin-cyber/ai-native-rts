extends RigidBody3D
class_name DummySoldier

## Phase 17 哑兵 — RigidBody3D + Seek Force 物理碰撞版本。
## Phase 19 升级：NavigationAgent3D + RVO 寻路，士兵绕路避让彼此。
## Phase 23 升级：多行军算法可切换（path_follow / flow_field / direct_seek）。
## follow_mode = false 时：linear_velocity 锁定为零，不施力。

var _general: Node = null          ## 跟随的将领（general_unit.gd 实例）
var _soldier_index: int = 0        ## 在兵团中的编号（0-based）
var _total_count: int = 30         ## 兵团总兵力
var _collision_radius: float = 7.0 ## 碰撞胶囊半径

var _is_headless: bool = false
var _standby_pos: Vector3 = Vector3.ZERO

## Phase 17 物理参数（从 config 读取）
var _drive_strength: float = 400.0
var _arrive_threshold: float = 8.0
var _slow_radius: float = 120.0

## Phase 23 行军算法选择
var _march_algorithm: String = "path_follow"

## Phase 19 稳定目标点
var _my_target: Vector3 = Vector3.ZERO
var _deploy_settled: bool = false  ## deployed 状态下是否已到达槽位并 freeze
var _waiting: bool = true
var _last_formation_state: String = ""

## deployed→marching 过渡期：关闭 reform，依靠虚拟锚点机制自然展开
var _reform_frames: int = 0
const _REFORM_DURATION: int = 0

## 卡死检测：连续 N 帧位移 < 阈值时施加随机侧向扰动力，打破 RVO 对称僵局
var _stuck_frames: int = 0                ## 连续低速帧计数
var _stuck_nudge_count: int = 0           ## 累计卡死扰动触发次数（23C 评估指标）
var _last_pos: Vector3 = Vector3.ZERO     ## 上帧位置（用于检测位移）
const _STUCK_THRESHOLD_FRAMES: int = 20  ## 连续多少帧不动才算卡住
const _STUCK_MIN_MOVE: float = 2.0       ## 每帧最小期望位移（units）
const _STUCK_NUDGE_STRENGTH: float = 0.6 ## 侧向扰动力系数（相对 drive_strength）

## Phase 19 寻路（窗口模式）
var _agent: NavigationAgent3D = null
var _rvo_velocity: Vector3 = Vector3.ZERO

## Phase 22 Context Steering
const _CS_DIRECTIONS: int = 8                ## 方向数量
const _CS_DANGER_WEIGHT: float = 2.0         ## 危险图权重
var _cs_sense_radius: float = 40.0           ## 感知半径（setup 时计算）


func setup(general: Node, index: int, total: int, cfg: Dictionary, headless: bool) -> void:
	_general = general
	_soldier_index = index
	_total_count = total
	_collision_radius = float(cfg.get("radius", 12.0)) * float(cfg.get("dummy_collision_radius_factor", 0.55))
	_drive_strength = float(cfg.get("dummy_drive_strength", 400.0))
	_arrive_threshold = float(cfg.get("dummy_arrive_threshold", 8.0))
	_slow_radius = float(cfg.get("dummy_slow_radius", 120.0))
	_is_headless = headless
	name = "Dummy_%d" % index
	_march_algorithm = String(cfg.get("march_algorithm", "path_follow"))
	_cs_sense_radius = _collision_radius * 4.0  ## 感知半径 = 碰撞半径 × 4

	mass = float(cfg.get("dummy_mass", 1.0))
	linear_damp = float(cfg.get("dummy_linear_damp", 8.0))

	axis_lock_angular_x = true
	axis_lock_angular_y = true
	axis_lock_angular_z = true
	axis_lock_linear_y = true

	collision_layer = 4
	collision_mask = 1 | 2 | 4

	var shape_node = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = _collision_radius
	capsule.height = _collision_radius * 2.5
	shape_node.shape = capsule
	add_child(shape_node)

	## 窗口模式：添加 NavigationAgent3D + RVO
	if not headless:
		_agent = NavigationAgent3D.new()
		_agent.name = "NavAgent"
		_agent.path_desired_distance = float(cfg.get("dummy_nav_path_distance", 15.0))
		_agent.target_desired_distance = float(cfg.get("dummy_nav_target_distance", 15.0))
		_agent.avoidance_enabled = true
		_agent.radius = _collision_radius
		_agent.neighbor_distance = float(cfg.get("dummy_nav_neighbor_distance", 60.0))
		_agent.max_neighbors = int(cfg.get("dummy_nav_max_neighbors", 10))
		_agent.max_speed = _drive_strength / float(cfg.get("dummy_linear_damp", 8.0))
		add_child(_agent)

	if is_instance_valid(_general) and _general.has_method("get_initial_slot"):
		position = _general.get_initial_slot(index, total)
	elif is_instance_valid(_general):
		position = _general.get_anchor_position()

	if not headless:
		_add_visual()


func _ready() -> void:
	## 初始冻结：_waiting=true 时彻底锁定物理体，防止胶囊体重叠产生接触冲量弹飞。
	## FREEZE_MODE_STATIC：冻结期间不产生任何碰撞响应（包括静力推开），完全透明。
	## 解除冻结（_waiting=false）时，士兵已离开密集初始区域，不会再发生重叠冲击。
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true

	if _agent != null:
		## RVO 速度修正回调：物理引擎计算好避让速度后通知我们
		_agent.velocity_computed.connect(_on_velocity_computed)


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	_rvo_velocity = safe_velocity


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_general):
		return

	var follow_mode: bool = _general.get("follow_mode") if _general.get("follow_mode") != null else true

	if not follow_mode:
		linear_velocity = Vector3.ZERO
		return

	if not _general.has_method("get_formation_slot"):
		return

	## 检测阵型状态切换，切换时重置等待状态
	var current_state: String = _general.get_formation_state() if _general.has_method("get_formation_state") else "marching"
	if current_state != _last_formation_state:
		_last_formation_state = current_state
		_waiting = true
		_rvo_velocity = Vector3.ZERO
		_deploy_settled = false
		if current_state == "deployed":
			## 切入 deployed：保持哑兵互碰（士兵已分散在纵队，不会爆炸）
			## 最近邻分配确保每人走最短路径，碰撞减少交叉穿越的不自然感
			if freeze:
				freeze = false
			_waiting = false
			_reform_frames = 0
		else:
			## 切回 marching：恢复哑兵互碰
			## 只有从 deployed 切换过来才启动过渡期（_last_formation_state == "deployed"）
			## 初始化切换（从 "" 到 "marching"）不触发，避免游戏启动时物理爆炸
			collision_mask = 1 | 2 | 4
			if _last_formation_state == "deployed":
				_reform_frames = _REFORM_DURATION

	## DEPLOYED 状态：从当前位置用力驱动走向横阵槽位
	## 切入时已关闭哑兵互碰（collision_mask 去掉 layer 4），到位后恢复碰撞并 freeze
	if current_state == "deployed":
		if _deploy_settled:
			## 已到位并 freeze，保持静止
			return
		var target = _general.get_formation_slot(_soldier_index, _total_count, global_position)
		var dist_d = global_position.distance_to(target)
		if dist_d <= _arrive_threshold:
			## 到位：恢复阻尼、哑兵互碰，freeze 锁定
			linear_velocity = Vector3.ZERO
			linear_damp = 8.0  ## 恢复正常阻尼
			collision_mask = 1 | 2 | 4
			freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			freeze = true
			_deploy_settled = true
			return
		## 展开期间：距离远时降低阻尼（提升最大速度），近时恢复正常阻尼平滑停止
		linear_damp = 3.0 if dist_d > _slow_radius else 8.0
		var fd = (target - global_position)
		fd.y = 0.0
		if fd.length_squared() > 0.001:
			apply_central_force(fd.normalized() * _drive_strength * clamp(dist_d / _slow_radius, 0.0, 1.0))
		return

	## deployed→marching 过渡期：向将领正后方集结，让所有人方向一致后再展开队形
	## 消除横阵→纵队切换时 velocity_coherence 骤降（incoherent 告警）
	if _reform_frames > 0:
		_reform_frames -= 1
		if freeze:
			freeze = false
		## 目标：将领正后方 _collision_radius * 2 处（近距离集结点）
		var march_dir = _general.get("_march_direction") if _general.get("_march_direction") != null else Vector3(0,0,-1)
		var rally = _general.global_position - march_dir * _collision_radius * 2.0
		rally.y = 0.0
		var fd = rally - global_position
		fd.y = 0.0
		if fd.length_squared() > 0.001:
			var dist_r = fd.length()
			apply_central_force(fd.normalized() * _drive_strength * clamp(dist_r / _slow_radius, 0.0, 1.0))
		return

	if _waiting:
		## 等待逻辑：将领有移动命令且 path_buffer 已有对应点才解锁
		## direct_seek 和 flow_field 不需要等 path_buffer，将领移动即解锁
		var general_moving = _general.get("has_command") == true
		if not general_moving:
			if freeze:
				freeze = false
			var forced_target = _general.get_formation_slot(_soldier_index, _total_count, global_position)
			_my_target = forced_target
			_waiting = false
			if _agent != null:
				_agent.target_position = _my_target
			return
		if freeze:
			freeze = false
		if _march_algorithm == "path_follow":
			## path_follow: 等 path_buffer 有真实路径点才解锁
			var queried = _general.get_formation_slot(_soldier_index, _total_count, global_position)
			var pb_size: int = _general.get("_path_buffer").size() if _general.get("_path_buffer") != null else 0
			var lead_offset: int = _general.get("_march_lead_offset") if _general.get("_march_lead_offset") != null else 3
			var has_real_path = pb_size > lead_offset
			if has_real_path and queried.distance_squared_to(global_position) > 100.0:
				_my_target = queried
				_waiting = false
				if _agent != null:
					_agent.target_position = _my_target
			else:
				return
		else:
			## flow_field / direct_seek: 将领移动即解锁
			_waiting = false

	## Phase 23: 按算法分发行军逻辑
	match _march_algorithm:
		"flow_field":
			_march_flow_field()
		"direct_seek":
			_march_direct_seek()
		_:
			_march_path_follow()


## Phase 23: path_follow 行军 — 原 Phase 19 逻辑（锁定目标点 + NavAgent + RVO + CS）
func _march_path_follow() -> void:
	var dist = global_position.distance_to(_my_target)
	if dist <= _arrive_threshold:
		var next = _general.get_formation_slot(_soldier_index, _total_count, global_position)
		if next.distance_squared_to(global_position) > 100.0:
			_my_target = next
			if _agent != null:
				_agent.target_position = _my_target
		return

	var force_dir: Vector3
	if _agent != null and not _agent.is_navigation_finished():
		var next_nav = _agent.get_next_path_position()
		var nav_dir = (next_nav - global_position)
		nav_dir.y = 0.0
		if nav_dir.length_squared() > 25.0:
			force_dir = nav_dir
			_agent.set_velocity(linear_velocity)
			if _rvo_velocity.length_squared() > 0.01:
				force_dir = Vector3(_rvo_velocity.x, 0.0, _rvo_velocity.z)
		else:
			force_dir = _context_steer(_my_target)
	else:
		force_dir = (_my_target - global_position)
		force_dir.y = 0.0
		if not _is_headless:
			force_dir = _context_steer(_my_target)

	if force_dir.length_squared() > 0.001:
		var speed_factor = clamp(dist / _slow_radius, 0.0, 1.0)
		apply_central_force(force_dir.normalized() * _drive_strength * speed_factor)

	_stuck_detect(dist)


## Phase 23: direct_seek 行军 — 每帧直追将领槽位，最简基线
func _march_direct_seek() -> void:
	var target = _general.get_formation_slot(_soldier_index, _total_count, global_position)
	var fd = target - global_position
	fd.y = 0.0
	var dist = fd.length()
	if dist <= _arrive_threshold:
		return
	if fd.length_squared() > 0.001:
		var speed_factor = clamp(dist / _slow_radius, 0.0, 1.0)
		apply_central_force(fd.normalized() * _drive_strength * speed_factor)

	_stuck_detect(dist)


## Phase 23: flow_field 行军 — 查将领流场方向 + 编队槽位偏移
func _march_flow_field() -> void:
	var slot_target = _general.get_formation_slot(_soldier_index, _total_count, global_position)
	var to_slot = slot_target - global_position
	to_slot.y = 0.0
	var dist = to_slot.length()

	if dist <= _arrive_threshold:
		return

	## 将领停止时：退回直线追槽位（保证 avg_slot_error 收敛，触发展开）
	var general_moving = _general.get("has_command") == true
	if not general_moving:
		var speed_factor = clamp(dist / _slow_radius, 0.0, 1.0)
		if to_slot.length_squared() > 0.001:
			apply_central_force(to_slot.normalized() * _drive_strength * speed_factor)
		_stuck_detect(dist)
		return

	## 查流场方向
	var flow_dir: Vector3 = Vector3.ZERO
	if _general.has_method("get_flow_direction"):
		flow_dir = _general.get_flow_direction(global_position)
	if flow_dir.length_squared() < 0.001:
		## 流场无数据：退回直线追槽位
		_march_direct_seek()
		return

	## 计算编队横向偏移（供后续扩展，当前混合方向已覆盖）
	var march_cw: int = _general.get("_march_column_width") if _general.get("_march_column_width") != null else 2
	var actual_col = _soldier_index % march_cw
	var _col_offset = float(actual_col) - float(march_cw - 1) * 0.5

	## 混合方向：70% 流场方向 + 30% 直线朝槽位（保证最终收敛）
	var blended_dir: Vector3
	if to_slot.length_squared() > 0.001:
		blended_dir = (flow_dir.normalized() * 0.7 + to_slot.normalized() * 0.3).normalized()
	else:
		blended_dir = flow_dir.normalized()

	var speed_factor = clamp(dist / _slow_radius, 0.0, 1.0)
	apply_central_force(blended_dir * _drive_strength * speed_factor)

	_stuck_detect(dist)


## 卡死检测（共用）
func _stuck_detect(dist_to_target: float) -> void:
	var moved_this_frame = global_position.distance_to(_last_pos)
	_last_pos = global_position
	if moved_this_frame < _STUCK_MIN_MOVE and dist_to_target > _arrive_threshold * 2.0:
		_stuck_frames += 1
		if _stuck_frames >= _STUCK_THRESHOLD_FRAMES:
			_stuck_frames = 0
			_stuck_nudge_count += 1
			var march_dir = _general.get("_march_direction") if _general.get("_march_direction") != null else Vector3(0, 0, -1)
			var side = Vector3(-march_dir.z, 0.0, march_dir.x)
			var sign_val = 1.0 if (_soldier_index % 2 == 0) else -1.0
			sign_val *= (1.0 + randf_range(-0.3, 0.3))
			apply_central_force(side * sign_val * _drive_strength * _STUCK_NUDGE_STRENGTH)
	else:
		_stuck_frames = 0


func freeze_at_current() -> void:
	_standby_pos = global_position


func _add_visual() -> void:
	var mesh_inst = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	var vis_r = _collision_radius * 0.9
	cylinder.top_radius = vis_r
	cylinder.bottom_radius = vis_r
	cylinder.height = vis_r * 2.5
	var mat = StandardMaterial3D.new()
	if is_instance_valid(_general):
		var team = _general.get("team_name") if _general.get("team_name") != null else "red"
		mat.albedo_color = Color(0.7, 0.1, 0.1) if team == "red" else Color(0.1, 0.2, 0.7)
	else:
		mat.albedo_color = Color(0.5, 0.5, 0.5)
	cylinder.material = mat
	mesh_inst.mesh = cylinder
	mesh_inst.position = Vector3(0.0, vis_r * 1.25, 0.0)
	add_child(mesh_inst)


## Phase 22 Context Steering
## 把周围分成 _CS_DIRECTIONS 个方向，每个方向打兴趣分和危险分，
## 选综合得分最高的方向作为施力方向。
## headless 模式不调用此函数（直接用直线方向）。
func _context_steer(target: Vector3) -> Vector3:
	var to_target = target - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.001:
		return Vector3.ZERO

	var desired_dir = to_target.normalized()

	## 预计算 8 个均匀分布的方向向量
	var dirs: Array = []
	for i in range(_CS_DIRECTIONS):
		var angle = i * TAU / float(_CS_DIRECTIONS)
		dirs.append(Vector3(cos(angle), 0.0, sin(angle)))

	## 兴趣图：各方向与目标方向的 dot product（越对齐分越高）
	var interest: Array = []
	for d in dirs:
		interest.append(maxf(0.0, d.dot(desired_dir)))

	## 危险图：感知范围内的其他士兵 → 在其方向上施加负权
	var danger: Array = []
	for i in range(_CS_DIRECTIONS):
		danger.append(0.0)

	## 扫描同组士兵（collision layer 4）
	var space = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = _cs_sense_radius
	query.shape = sphere
	query.transform = Transform3D(Basis(), global_position)
	query.collision_mask = 4  ## layer 4 = 哑兵
	var results = space.intersect_shape(query, 16)

	for hit in results:
		var obj = hit.get("collider")
		if not is_instance_valid(obj) or obj == self:
			continue
		var away = global_position - obj.global_position
		away.y = 0.0
		if away.length_squared() < 0.001:
			continue
		var away_dir = away.normalized()
		## 距离越近危险分越高
		var dist_factor = 1.0 - clamp(away.length() / _cs_sense_radius, 0.0, 1.0)
		for i in range(_CS_DIRECTIONS):
			var d_val = dirs[i].dot(-away_dir)  ## 朝向障碍的方向得高危险分
			if d_val > 0.0:
				danger[i] = maxf(danger[i], d_val * dist_factor)

	## 综合评分 = interest - danger * weight，找最高分方向
	var best_score := -INF
	var best_dir: Vector3 = desired_dir
	for i in range(_CS_DIRECTIONS):
		var score = interest[i] - danger[i] * _CS_DANGER_WEIGHT
		if score > best_score:
			best_score = score
			best_dir = dirs[i]

	return best_dir

