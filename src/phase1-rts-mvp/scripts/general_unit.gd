extends "res://scripts/base_unit.gd"

## Phase 15A 将领单位 — 继承 base_unit，玩家直接控制。
## 比普通士兵稍快，视觉上尺寸 1.5 倍、有明显标识。
## 阵亡时在 base_unit.died 之外额外发出 general_died(team_name) 信号，
## 供 Phase 16 士气系统监听。
## Phase 16：路径队列 + 阵型状态机（MARCHING / DEPLOYED），
## 通过 get_formation_slot() 向哑兵提供目标点。

signal general_died(team_name: String)
## 15C：补兵请求信号。parent（game_world / bootstrap）监听后创建哑兵并调用 add_dummy_soldier()。
signal replenish_requested(general: Node)

var move_speed: float = 180.0
var unit_radius: float = 12.0
var visual_scale: float = 1.5

var _agent: NavigationAgent3D
var _nav_available: bool = false
var _has_command: bool = false
var _command_frame: int = 0
var target_position: Vector3 = Vector3.ZERO
var has_command: bool = false  ## 镜像 _has_command，供 AI Renderer 采样

## 15B：兵团跟随状态
var follow_mode: bool = true   ## true=跟随，false=待命
var _dummy_soldiers: Array = []        ## 所属哑兵列表（由 game_world 注入）
var _follow_toggle_key: String = "Space"  ## 切换键，可通过 config 覆盖

## UI：待命/跟随状态文字标签（窗口模式下显示）
var _status_label: Label3D = null

## 15C：补兵计时
var _replenish_interval: int = 180    ## 每隔多少帧补一批
var _replenish_count: int = 3         ## 每次补多少个
var _replenish_rate_growth: float = 0.05  ## 蓝方每次补兵后速度系数增幅（红方不用）
var _replenish_timer: int = 0         ## 帧计数
var _replenish_cycle: int = 0         ## 已触发的补兵轮次（用于蓝方加速）
var _general_cfg: Dictionary = {}     ## 保存原始 cfg，供补兵时传给 DummySoldier

## 16：阵型状态机
var _formation_state: String = "marching"  ## "marching" | "deployed"
var _path_buffer: Array = []               ## 历史位置环形队列（Vector3 数组）
var _path_buffer_size: int = 60            ## 最大历史点数
var _path_sample_interval: int = 5         ## 每几帧采样一次
var _path_sample_timer: int = 0            ## 采样帧计数
var _march_column_width: int = 3           ## 纵队横向并列人数
var _march_direction: Vector3 = Vector3(0.0, 0.0, -1.0)  ## 最后有效前进方向（默认朝北）
var _deploy_timer: int = 0                 ## 静止帧计数
var _deploy_trigger_frames: int = 30       ## 静止多少帧触发横阵
var _deploy_columns: int = 3              ## 横阵列数
var _deploy_row_spacing: float = 26.4      ## 横阵排距（radius × 2.2）
var _deploy_col_spacing: float = 13.2      ## 横阵列距（radius × 1.1）
var _prev_position: Vector3 = Vector3.ZERO ## 上一帧位置，用于检测静止


func setup(id: int, team: String, pos: Vector3, cfg: Dictionary, headless: bool, map_size: Vector2, _home: Node) -> void:
	unit_id = id
	team_name = team
	position = pos
	unit_type = "general"
	move_speed = float(cfg.speed)
	unit_radius = float(cfg.radius)
	visual_scale = float(cfg.get("visual_scale", 1.5))
	max_hp = float(cfg.hp)
	hp = max_hp
	name = "General_%s_%d" % [team, id]
	_follow_toggle_key = cfg.get("follow_toggle_key", "Space")
	_replenish_interval = int(cfg.get("replenish_interval", 180))
	_replenish_count = int(cfg.get("replenish_count", 3))
	_replenish_rate_growth = float(cfg.get("replenish_rate_growth", 0.05))
	_general_cfg = cfg

	## 16：阵型参数
	_path_buffer_size = int(cfg.get("path_buffer_size", 60))
	_path_sample_interval = int(cfg.get("path_sample_interval", 5))
	_march_column_width = int(cfg.get("march_column_width", 3))
	_deploy_trigger_frames = int(cfg.get("deploy_trigger_frames", 30))
	_deploy_columns = int(cfg.get("deploy_columns", _march_column_width))
	var row_factor = float(cfg.get("deploy_row_spacing_factor", 2.2))
	var col_factor = float(cfg.get("deploy_col_spacing_factor", 1.1))
	_deploy_row_spacing = unit_radius * row_factor
	_deploy_col_spacing = unit_radius * col_factor

	collision_layer = 1
	collision_mask = 2

	var capsule = CapsuleShape3D.new()
	capsule.radius = unit_radius
	capsule.height = unit_radius * 2.0
	var col = CollisionShape3D.new()
	col.shape = capsule
	add_child(col)

	var agent = NavigationAgent3D.new()
	agent.path_desired_distance = 20.0
	agent.target_desired_distance = 20.0
	agent.name = "NavAgent"
	add_child(agent)

	if not headless:
		_add_visual()
		_add_status_label()

	## 将领颜色：红方用金色，蓝方用银色，与士兵颜色有明显区分
	_idle_color = Color(1.0, 0.8, 0.0) if team == "red" else Color(0.8, 0.8, 0.8)


func _ready() -> void:
	_agent = $NavAgent
	add_to_group("team_%s" % team_name)
	add_to_group("units")
	add_to_group("generals")
	_prev_position = global_position
	_detect_nav.call_deferred()


func _detect_nav() -> void:
	var nav_map = get_world_3d().get_navigation_map()
	_nav_available = NavigationServer3D.map_get_iteration_id(nav_map) > 0


func _die() -> void:
	## 先发出将领专属信号，再走 base_unit 死亡流程（died + queue_free）
	general_died.emit(team_name)
	super._die()


## 15B：注册哑兵列表（由 game_world 或 gameplay_bootstrap 注入）
func register_dummy_soldiers(soldiers: Array) -> void:
	_dummy_soldiers = soldiers


## 15B：切换跟随/待命模式
func toggle_follow_mode() -> void:
	follow_mode = not follow_mode
	if not follow_mode:
		## 刚切换到待命：通知所有哑兵锁定当前位置
		for s in _dummy_soldiers:
			if is_instance_valid(s):
				s.freeze_at_current()
	_update_status_label()
	print("[GENERAL] follow_mode=%s" % str(follow_mode))


## 15C：供 parent 在收到 replenish_requested 信号后调用，注入新哑兵
func add_dummy_soldier(soldier: Node) -> void:
	_dummy_soldiers.append(soldier)


## 15C：查询当前哑兵数量（供测试断言使用）
func get_dummy_count() -> int:
	var count = 0
	for s in _dummy_soldiers:
		if is_instance_valid(s):
			count += 1
	return count


## 15C：查询补兵配置（供 parent 创建时使用）
func get_general_cfg() -> Dictionary:
	return _general_cfg


## 15C：蓝方加速公式 — 每轮次间隔缩短 rate_growth 比例，最少为原始间隔的 30%
func _get_effective_replenish_interval() -> int:
	if team_name == "red":
		return _replenish_interval
	## 蓝方：interval × (1 - cycle × growth)，下限 30% of original
	var factor = max(0.3, 1.0 - float(_replenish_cycle) * _replenish_rate_growth)
	return max(1, int(float(_replenish_interval) * factor))


func _unhandled_input(event: InputEvent) -> void:
	## 仅红方玩家将领响应 Space 键切换（蓝方 AI 将领不处理）
	if team_name != "red":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if OS.get_keycode_string(event.keycode) == _follow_toggle_key or \
		   event.keycode == KEY_SPACE:
			toggle_follow_mode()
			get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if _state == "dead":
		return
	if _process_combat_effects(delta):
		return

	if _has_command:
		if _is_at_target():
			_has_command = false
			has_command = false
			_command_frame = 0
			_state = "idle"
			velocity = Vector3.ZERO
			return
		_move_along_path()
		_command_frame += 1

	## 16：路径采样 + 阵型状态检测（follow_mode=true 时才运行）
	if follow_mode:
		_update_path_buffer()
		_detect_formation_state()

	## 15C：补兵计时
	_replenish_timer += 1
	var effective_interval = _get_effective_replenish_interval()
	if _replenish_timer >= effective_interval:
		_replenish_timer = 0
		_replenish_cycle += 1
		replenish_requested.emit(self)

	_prev_position = global_position


func move_to(target_pos: Vector3) -> void:
	_has_command = true
	has_command = true
	_command_frame = 0
	_state = "wander"
	_set_agent_target(target_pos)
	## 16：立即更新行军方向（不等下一次路径采样），防止转向时方向滞后
	var dir = target_pos - global_position
	dir.y = 0.0
	if dir.length_squared() > 0.01:
		_march_direction = dir.normalized()


func get_unit_state() -> Dictionary:
	return {
		"id": unit_id,
		"team": team_name,
		"type": unit_type,
		"pos_x": roundf(position.x * 100.0) / 100.0,
		"pos_z": roundf(position.z * 100.0) / 100.0,
		"hp": hp,
		"max_hp": max_hp,
		"state": _state,
		"follow_mode": follow_mode,
	}


func get_anchor_position() -> Vector3:
	## 15B 兼容接口：保留供遗留代码使用，返回将领自身位置。
	return global_position


## 16：供哑兵查询目标点的唯一接口。
## 根据当前 _formation_state 返回：
##   MARCHING  → 路径历史点 + 横向槽位
##   DEPLOYED  → 横阵格位
func get_formation_slot(index: int, total: int) -> Vector3:
	if _formation_state == "deployed":
		return _get_deploy_slot(index)
	else:
		return _get_march_slot(index)


## 16：返回当前阵型状态（供测试断言）
func get_formation_state() -> String:
	return _formation_state


## 16：路径采样 — 将领移动时每帧更新方向，每隔 N 帧记录位置（仅保留历史，不再用于槽位计算）
func _update_path_buffer() -> void:
	var moved = global_position.distance_to(_prev_position) > 1.0
	if moved:
		## 每帧更新前进方向，防止转向滞后
		var dir = global_position - _prev_position
		if dir.length_squared() > 0.01:
			_march_direction = Vector3(dir.x, 0.0, dir.z).normalized()
		_path_sample_timer += 1
		if _path_sample_timer >= _path_sample_interval:
			_path_sample_timer = 0
			_path_buffer.push_front(global_position)
			if _path_buffer.size() > _path_buffer_size:
				_path_buffer.pop_back()


## 16：阵型状态检测 — 根据将领是否静止切换 MARCHING / DEPLOYED
func _detect_formation_state() -> void:
	var moved = global_position.distance_to(_prev_position) > 1.0
	if moved:
		## 将领移动：重置静止计时，若当前是 deployed 则切回 marching
		_deploy_timer = 0
		if _formation_state == "deployed":
			_formation_state = "marching"
			_path_buffer.clear()  ## 清空旧路径，防止跳回旧轨迹
	else:
		## 将领静止：累计计时
		_deploy_timer += 1
		if _formation_state == "marching" and _deploy_timer >= _deploy_trigger_frames:
			_formation_state = "deployed"


## 16：纵队行军槽位计算 — AoE2 整体平移风格
## 以将领当前位置为锚点，沿 -_march_direction 方向排排列，横向居中分列
func _get_march_slot(index: int) -> Vector3:
	var row = index / _march_column_width
	var col_slot = index % _march_column_width
	## 列居中：col_offset 以 0 为中心，范围 -(w-1)/2 ~ +(w-1)/2
	var col_offset = float(col_slot) - float(_march_column_width - 1) * 0.5
	## 横向方向 = 前进方向旋转 90°（XZ 平面）
	var lateral_dir = Vector3(-_march_direction.z, 0.0, _march_direction.x)
	## 整体跟随将领当前位置（整体平移，非路径拖尾）
	return global_position \
		- _march_direction * _deploy_row_spacing * float(row + 1) \
		+ lateral_dir * _deploy_col_spacing * col_offset


## 16：横阵列阵槽位计算
func _get_deploy_slot(index: int) -> Vector3:
	var row = index / _deploy_columns
	var col = index % _deploy_columns
	## 列居中：col 从左到右，整体居中
	var col_offset = float(col) - float(_deploy_columns - 1) * 0.5
	## 横向方向
	var lateral_dir = Vector3(-_march_direction.z, 0.0, _march_direction.x)

	return global_position \
		+ _march_direction * _deploy_row_spacing * float(row + 1) \
		+ lateral_dir * _deploy_col_spacing * col_offset


func _set_agent_target(pos: Vector3) -> void:
	target_position = pos
	_agent.target_position = pos


func _is_at_target() -> bool:
	return global_position.distance_to(target_position) < 20.0


func _move_along_path() -> void:
	var dist = global_position.distance_to(target_position)
	if dist < 20.0:
		velocity = Vector3.ZERO
		return
	if _nav_available:
		var next_pos = _agent.get_next_path_position()
		var nav_dir = global_position.direction_to(next_pos)
		if nav_dir.length_squared() < 0.01:
			nav_dir = global_position.direction_to(target_position)
		velocity = Vector3(nav_dir.x, 0.0, nav_dir.z) * move_speed
	else:
		var dir = global_position.direction_to(target_position)
		velocity = Vector3(dir.x, 0.0, dir.z) * move_speed
	move_and_slide()


func _add_visual() -> void:
	var mesh_inst = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	## 将领视觉：半径 1.5 倍于配置值，高度 2 倍，使其明显高于士兵
	var vis_radius = unit_radius * visual_scale
	cylinder.top_radius = vis_radius
	cylinder.bottom_radius = vis_radius
	cylinder.height = vis_radius * 3.0
	var mat = StandardMaterial3D.new()
	## 红方将领：金色；蓝方将领：银色
	mat.albedo_color = Color(1.0, 0.8, 0.0) if team_name == "red" else Color(0.8, 0.8, 0.8)
	cylinder.material = mat
	mesh_inst.mesh = cylinder
	mesh_inst.position = Vector3(0.0, vis_radius * 1.5, 0.0)
	_body_mat = mat
	add_child(mesh_inst)

	## 顶部标记：小球体作为将领旗帜标识
	var marker_inst = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = vis_radius * 0.5
	sphere.height = vis_radius
	var marker_mat = StandardMaterial3D.new()
	marker_mat.albedo_color = Color(1.0, 1.0, 1.0)
	sphere.material = marker_mat
	marker_inst.mesh = sphere
	marker_inst.position = Vector3(0.0, vis_radius * 3.5, 0.0)
	add_child(marker_inst)


func _add_status_label() -> void:
	## 将领头顶显示当前跟随/待命状态
	_status_label = Label3D.new()
	_status_label.name = "StatusLabel"
	_status_label.text = "[跟随]"
	_status_label.font_size = 32
	_status_label.modulate = Color(1.0, 1.0, 0.0) if team_name == "red" else Color(0.8, 0.8, 0.8)
	_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_label.no_depth_test = true
	var vis_radius = unit_radius * visual_scale
	_status_label.position = Vector3(0.0, vis_radius * 4.5, 0.0)
	add_child(_status_label)


func _update_status_label() -> void:
	if _status_label == null:
		return
	_status_label.text = "[跟随]" if follow_mode else "[待命]"
	_status_label.modulate = Color(1.0, 1.0, 0.0) if follow_mode else Color(1.0, 0.4, 0.0)
