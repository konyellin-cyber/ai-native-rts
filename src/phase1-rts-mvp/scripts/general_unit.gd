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
var _march_row_path_step: int = 4          ## 每排间隔几个历史路径点（控制排间距）
var _march_lead_offset: int = 3            ## 队首额外偏移的历史点数（控制将领与队首的距离）
var _march_direction: Vector3 = Vector3(0.0, 0.0, -1.0)  ## 最后有效前进方向（默认朝北）
var _deploy_timer: int = 0                 ## 静止帧计数
var _deploy_trigger_frames: int = 30       ## 静止多少帧触发横阵（条件一）
var _deploy_ready_threshold: float = 45.0  ## 全员到位误差阈值（条件二：avg_slot_error < 此值才展开）
var _deploy_cooldown: int = 90             ## 初始冷却帧数，避免游戏启动瞬间误触发展开
var _deploy_anchor: Vector3 = Vector3.ZERO ## 将领停止时快照的锚点，横阵槽位固定在此，不随将领微移漂动
											## headless 模式下冷却更短（由 _ready 覆盖）
var _deploy_columns: int = 3              ## 横阵列数
var _deploy_row_spacing: float = 26.4      ## 横阵排距（radius × 2.2）
var _deploy_col_spacing: float = 13.2      ## 横阵列距（radius × 1.1）
var _prev_position: Vector3 = Vector3.ZERO
var _static_frames: int = 0  ## 将领静止帧数（兜底展开超时用）

## 19C：体验质量感知 — overshoot 检测缓存
var _prev_slot_errors: Dictionary = {}

## 19E：槽位最近邻分配
var _slot_assignment: Dictionary = {}

## 23B：局部流场（flow_field 算法用）
var _flow_field: Dictionary = {}          ## key=Vector2i 网格坐标，value=Vector3 方向
var _flow_field_cell_size: float = 20.0   ## 格子边长（世界坐标 units）
var _flow_field_half_width: int = 4       ## 轨迹两侧扩展格数
var _flow_field_update_interval: int = 10 ## 每隔多少帧重建一次流场
var _flow_field_timer: int = 0

## 23C：展开收敛追踪
var _convergence_start_frame: int = -1   ## 将领停止帧（-1=未统计）
var _convergence_frames: int = -1        ## 最近一次展开收敛帧数（-1=未完成）
var _current_frame: int = 0              ## 当前帧计数（_physics_process 递增）

## 行军中定时 Minimax 重分配
var _reassign_timer: int = 0
const _REASSIGN_INTERVAL: int = 30
## 士兵最大可达范围：drive_strength/damp/fps × interval × 1.5 余量
## 运行时从 config 动态计算，此处为默认值
var _max_reach: float = 240.0
## 从横阵切回纵队后的宽松期：此期间不限制 max_reach（士兵需要从横阵位置出发）
var _post_deploy_grace: int = 0
const _POST_DEPLOY_GRACE_FRAMES: int = 300  ## 5 秒宽松期


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
	_march_row_path_step = int(cfg.get("march_row_path_step", 4))
	_march_lead_offset = int(cfg.get("march_lead_offset", 3))
	_deploy_trigger_frames = int(cfg.get("deploy_trigger_frames", 30))
	_deploy_ready_threshold = float(cfg.get("deploy_ready_threshold", 45.0))
	_deploy_columns = int(cfg.get("deploy_columns", _march_column_width))
	var row_factor = float(cfg.get("deploy_row_spacing_factor", 2.2))
	var col_factor = float(cfg.get("deploy_col_spacing_factor", 1.1))
	_deploy_row_spacing = unit_radius * row_factor
	_deploy_col_spacing = unit_radius * col_factor

	## 23B：流场参数
	_flow_field_cell_size = float(cfg.get("flow_field_cell_size", 20.0))
	_flow_field_half_width = int(cfg.get("flow_field_half_width", 4))
	_flow_field_update_interval = int(cfg.get("flow_field_update_interval", 10))

	## 计算士兵在一个重分配间隔内的最大可达距离（仅窗口模式使用）
	## headless 模式不限制 max_reach（避免严格条件导致测试超时）
	var dummy_drive = float(cfg.get("dummy_drive_strength", 1600.0))
	var dummy_damp  = float(cfg.get("dummy_linear_damp", 8.0))
	var max_speed   = dummy_drive / dummy_damp / 60.0  ## units/frame
	_max_reach = max_speed * _REASSIGN_INTERVAL * 1.5 if not headless else INF

	collision_layer = 1
	collision_mask = 2 | 4  # layer=2 墙/障碍物，layer=4 哑兵（主战推哑兵）

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
	## headless 模式冷却期更短（测试场景帧数紧凑）
	if DisplayServer.get_name() == "headless":
		_deploy_cooldown = 5
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
		_update_flow_field()
		_detect_formation_state()
		## 行军中定时重分配槽位（减少长途跋涉）
		if _formation_state == "marching" and _has_command:
			_reassign_timer += 1
			if _reassign_timer >= _REASSIGN_INTERVAL:
				_reassign_timer = 0
				_try_reassign_marching()
		else:
			_reassign_timer = 0

	## 15C：补兵计时
	_replenish_timer += 1
	var effective_interval = _get_effective_replenish_interval()
	if _replenish_timer >= effective_interval:
		_replenish_timer = 0
		_replenish_cycle += 1
		replenish_requested.emit(self)

	_prev_position = global_position
	_current_frame += 1


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
	## 19：收到新移动指令时立即切回 marching，清除锚点和计时器
	if _formation_state == "deployed":
		_path_buffer.clear()
		_path_sample_timer = 0
		_formation_state = "marching"
		_rebuild_slot_assignment("marching")
		_post_deploy_grace = _POST_DEPLOY_GRACE_FRAMES
	_deploy_timer = 0
	_static_frames = 0
	_deploy_anchor = Vector3.ZERO


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
	return global_position


## Phase 22：手柄 RT 触发前方横阵展开
## anchor_pos：横阵中心点（将领前方 N units）
## deploy_dir：横阵朝向（摇杆方向），决定横排的法线方向
func deploy_forward(anchor_pos: Vector3, deploy_dir: Vector3) -> void:
	## 更新行军方向为摇杆方向，横阵展开时以此为基准
	if deploy_dir.length_squared() > 0.01:
		_march_direction = deploy_dir.normalized()
	## 设置锚点并切换到 deployed 状态
	_deploy_anchor = anchor_pos
	_deploy_anchor.y = 0.0
	_deploy_timer = _deploy_trigger_frames  ## 直接满足计时器，立即触发
	_formation_state = "deployed"
	_rebuild_slot_assignment("deployed")
	print("[GENERAL] deploy_forward anchor=(%.0f,%.0f) dir=(%.2f,%.2f)" % [
		anchor_pos.x, anchor_pos.z, _march_direction.x, _march_direction.z])


## 19：初始槽位计算 — 用整体平移公式（不依赖 path_buffer），供 DummySoldier setup 时初始化位置
func get_initial_slot(index: int, total: int) -> Vector3:
	var row = index / _march_column_width
	var col_slot = index % _march_column_width
	var col_offset = float(col_slot) - float(_march_column_width - 1) * 0.5
	var lateral_dir = Vector3(-_march_direction.z, 0.0, _march_direction.x)
	return global_position \
		- _march_direction * _deploy_col_spacing * float(row + 1) \
		+ lateral_dir * _deploy_col_spacing * col_offset


## 16：供哑兵查询目标点的唯一接口。
## 19E：先查 _slot_assignment 获取重新分配的槽位 index，再计算坐标。
## current_pos：士兵当前世界坐标，用于 path_buffer 不足时的原地等待
func get_formation_slot(index: int, total: int, current_pos: Vector3 = Vector3.ZERO) -> Vector3:
	## 查槽位分配表（若有）
	var slot_idx = _slot_assignment.get(index, index)
	if _formation_state == "deployed":
		return _get_deploy_slot(slot_idx)
	else:
		return _get_march_slot(slot_idx, current_pos)


## 19E：最近邻贪心槽位重分配
## 阵型切换时调用一次，为每个士兵找最近可用槽位，避免路径交叉。
## target_state: "deployed" 或 "marching"（决定槽位坐标来源）
func _rebuild_slot_assignment(target_state: String) -> void:
	var total = _dummy_soldiers.size()
	if total == 0:
		_slot_assignment = {}
		return

	## 收集有效士兵列表
	var soldiers_valid: Array = []
	for i in range(total):
		if is_instance_valid(_dummy_soldiers[i]):
			soldiers_valid.append(i)

	## 计算所有槽位坐标（临时切换 _formation_state 来借用现有接口）
	var prev_state = _formation_state
	_formation_state = target_state
	var slot_coords: Array = []
	for j in range(total):
		if target_state == "deployed":
			slot_coords.append(_get_deploy_slot(j))
		else:
			## marching 槽位：用将领当前位置作为 current_pos 占位（不影响分配结果）
			slot_coords.append(_get_march_slot(j, global_position))
	_formation_state = prev_state

	## 贪心最近邻匹配：每轮找所有未分配对中距离最小的 (i, j)
	var unassigned_soldiers = soldiers_valid.duplicate()
	var unassigned_slots: Array = range(total)
	var assignment: Dictionary = {}

	while unassigned_soldiers.size() > 0 and unassigned_slots.size() > 0:
		var best_dist := INF
		var best_si := -1   ## unassigned_soldiers 中的索引
		var best_sj := -1   ## unassigned_slots 中的索引

		for si in range(unassigned_soldiers.size()):
			var soldier_idx = unassigned_soldiers[si]
			var spos: Vector3 = _dummy_soldiers[soldier_idx].global_position
			for sj in range(unassigned_slots.size()):
				var slot_j = unassigned_slots[sj]
				var d = spos.distance_squared_to(slot_coords[slot_j])
				if d < best_dist:
					best_dist = d
					best_si = si
					best_sj = sj

		if best_si < 0:
			break
		var soldier_idx = unassigned_soldiers[best_si]
		var slot_j = unassigned_slots[best_sj]
		assignment[soldier_idx] = slot_j
		unassigned_soldiers.remove_at(best_si)
		unassigned_slots.remove_at(best_sj)

	_slot_assignment = assignment


## 行军中定时 Minimax 重分配
## 用二分搜索 + 二分图最大匹配，找最小化"最大分配距离"的方案
## max_reach 限制可分配范围（宽松期内不限制）
func _try_reassign_marching() -> void:
	var total = _dummy_soldiers.size()
	if total == 0 or _formation_state != "marching":
		return

	## 宽松期递减
	if _post_deploy_grace > 0:
		_post_deploy_grace -= _REASSIGN_INTERVAL

	## 收集活跃士兵（非 waiting）
	var s_pos: Array = []   ## 士兵位置
	var s_idx: Array = []   ## soldier_index
	for i in range(total):
		var s = _dummy_soldiers[i]
		if not is_instance_valid(s) or s.get("_waiting") == true:
			continue
		s_pos.append(s.global_position)
		s_idx.append(i)

	var n = s_idx.size()
	if n < 2:
		return

	## 收集这些士兵当前分配的 slot 坐标
	var slot_idx_list: Array = []
	var slot_pos_list: Array = []
	for ii in range(n):
		var si = s_idx[ii]
		var slot_i = _slot_assignment.get(si, si)
		slot_idx_list.append(slot_i)
		slot_pos_list.append(_get_march_slot(slot_i, s_pos[ii]))

	## 构建距离矩阵，同时过滤超出 max_reach 的 (i,j) 对
	var use_reach = _post_deploy_grace <= 0
	var reach = _max_reach if use_reach else INF
	var dist_mat: Array = []   ## dist_mat[i][j] = 距离，INF 表示不可达
	for ii in range(n):
		var row: Array = []
		for jj in range(n):
			var d = s_pos[ii].distance_to(slot_pos_list[jj])
			row.append(d if d <= reach else INF)
		dist_mat.append(row)

	## 收集所有有限距离值并排序（候选阈值）
	var candidates: Array = []
	for ii in range(n):
		for jj in range(n):
			if dist_mat[ii][jj] < INF:
				candidates.append(dist_mat[ii][jj])
	if candidates.is_empty():
		return
	candidates.sort()
	## 去重
	var thresholds: Array = [candidates[0]]
	for v in candidates:
		if v > thresholds[-1] + 0.01:
			thresholds.append(v)

	## 计算当前 minimax 值（当前分配方案中最大距离）
	var current_minimax := 0.0
	for ii in range(n):
		var si = s_idx[ii]
		var slot_i = _slot_assignment.get(si, si)
		var d = s_pos[ii].distance_to(_get_march_slot(slot_i, s_pos[ii]))
		if d > current_minimax:
			current_minimax = d

	## 二分搜索最小可行阈值
	var lo := 0
	var hi := thresholds.size() - 1
	var best_thresh: float = thresholds[hi]
	var best_match: Array = []

	while lo <= hi:
		var mid = (lo + hi) / 2
		var thresh = thresholds[mid]
		var match = _hopcroft_karp(dist_mat, n, thresh)
		if match.size() == n:  ## 完美匹配
			best_thresh = thresh
			best_match = match.duplicate()
			hi = mid - 1
		else:
			lo = mid + 1

	## 只有 minimax 明显改善才切换（避免抖动）
	if best_match.size() == n and best_thresh < current_minimax * 0.85:
		for ii in range(n):
			_slot_assignment[s_idx[ii]] = slot_idx_list[best_match[ii]]


## Hopcroft-Karp 二分图最大匹配
## dist_mat[i][j] <= thresh 时 i 和 j 之间有边
## 返回 match 数组：match[i] = j（左侧 i 匹配到右侧 j），不完整匹配时 size < n
func _hopcroft_karp(dist_mat: Array, n: int, thresh: float) -> Array:
	var match_l: Array = []  ## 左侧（士兵）匹配到的右侧 index，-1=未匹配
	var match_r: Array = []  ## 右侧（slot）匹配到的左侧 index，-1=未匹配
	match_l.resize(n)
	match_r.resize(n)
	for i in range(n):
		match_l[i] = -1
		match_r[i] = -1

	## 增广路径 BFS + DFS（简化版 Hopcroft-Karp）
	var matched := 0
	for i in range(n):
		var visited: Array = []
		visited.resize(n)
		for k in range(n): visited[k] = false
		if _hk_dfs(i, dist_mat, n, thresh, match_l, match_r, visited):
			matched += 1

	## 提取结果
	var result: Array = []
	if matched == n:
		for i in range(n):
			result.append(match_l[i])
	return result


func _hk_dfs(u: int, dist_mat: Array, n: int, thresh: float,
			 match_l: Array, match_r: Array, visited: Array) -> bool:
	for v in range(n):
		if dist_mat[u][v] > thresh or visited[v]:
			continue
		visited[v] = true
		if match_r[v] == -1 or _hk_dfs(match_r[v], dist_mat, n, thresh, match_l, match_r, visited):
			match_l[u] = v
			match_r[v] = u
			return true
	return false


## 16：返回当前阵型状态（供测试断言）
func get_formation_state() -> String:
	return _formation_state


## 19B：阵型整齐度摘要，供 AI Renderer SensorRegistry 采集
## 计算每个哑兵实际位置与理想槽位的误差，输出 avg/max/waiting 统计
## 19C：新增体验质量指标：pos_std_dev / lateral_spread / velocity_coherence / overshoot_count / freeze_rate
## 23C：新增评估指标：stuck_nudge_total / convergence_frames / direction_change_rate
func get_formation_summary() -> Dictionary:
	var total = _dummy_soldiers.size()
	if total == 0:
		return {"formation_state": _formation_state, "path_buffer_size": _path_buffer.size(),
				"avg_slot_error": 9999.0, "max_slot_error": 9999.0, "waiting_count": 0,
				"pos_std_dev": 0.0, "lateral_spread": 0.0, "velocity_coherence": 0.0,
				"overshoot_count": 0, "freeze_rate": 0.0,
				"stuck_nudge_total": 0, "convergence_frames": -1, "direction_change_rate": 0.0}
	var sum_err := 0.0
	var max_err := 0.0
	var waiting := 0
	var frozen := 0
	var overshoot := 0

	## 位置列表（用于 std_dev / lateral_spread）
	var positions: Array = []
	## 速度列表（用于 velocity_coherence）
	var velocities: Array = []

	for i in range(total):
		var s = _dummy_soldiers[i]
		if not is_instance_valid(s):
			continue
		var spos: Vector3 = s.global_position
		var ideal = get_formation_slot(i, total, spos)
		var err = spos.distance_to(ideal)

		if s.freeze:
			frozen += 1
		if s.get("_waiting") == true:
			waiting += 1
			_prev_slot_errors.erase(i)
			## waiting 的士兵跳过误差计算
			continue
		sum_err += err
		if err > max_err:
			max_err = err

		## overshoot 检测：上帧距离 < arrive_threshold，本帧反而更大
		var arrive_thr: float = s.get("_arrive_threshold") if s.get("_arrive_threshold") != null else 8.0
		if _prev_slot_errors.has(i):
			var prev_err: float = _prev_slot_errors[i]
			if prev_err < arrive_thr and err > prev_err + 2.0:
				overshoot += 1
		_prev_slot_errors[i] = err

		positions.append(spos)
		var vel = s.get("linear_velocity")
		if vel != null:
			var vel_xz = Vector3(vel.x, 0.0, vel.z)
			## 速度阈值 5 units/s：过滤静止/近静止士兵，避免 coh=0 假阳性
			if vel_xz.length_squared() > 25.0:
				velocities.append(vel_xz)

	## --- pos_std_dev（XZ 位置标准差） ---
	var pos_std_dev := 0.0
	if positions.size() > 1:
		var centroid := Vector3.ZERO
		for p in positions:
			centroid += Vector3(p.x, 0.0, p.z)
		centroid /= float(positions.size())
		var variance := 0.0
		for p in positions:
			var d = Vector2(p.x - centroid.x, p.z - centroid.z).length()
			variance += d * d
		pos_std_dev = sqrt(variance / float(positions.size()))

	## --- lateral_spread（垂直行军方向的横向离散度） ---
	var lateral_spread := 0.0
	if positions.size() > 1:
		var lat_dir = Vector3(-_march_direction.z, 0.0, _march_direction.x)
		var lat_vals: Array = []
		for p in positions:
			lat_vals.append(Vector3(p.x, 0.0, p.z).dot(lat_dir))
		var lat_mean := 0.0
		for v in lat_vals:
			lat_mean += v
		lat_mean /= float(lat_vals.size())
		var lat_var := 0.0
		for v in lat_vals:
			lat_var += (v - lat_mean) * (v - lat_mean)
		lateral_spread = sqrt(lat_var / float(lat_vals.size()))

	## --- velocity_coherence（速度方向一致性） ---
	## 只统计速度 > 5 units/s 的士兵（已在 velocities 收集时过滤）。
	## 若移动中的士兵数 < 总数 30%，视为"整体静止"，coherence = 1.0（消除静止假阳性）。
	var velocity_coherence := 1.0  ## 默认 1.0：静止/慢速期视为完全一致
	var moving_threshold = int(float(total) * 0.3)
	if velocities.size() > moving_threshold:
		var vel_mean := Vector3.ZERO
		for v in velocities:
			vel_mean += v
		if vel_mean.length_squared() > 0.01:
			var ref_dir = vel_mean.normalized()
			var cos_sum := 0.0
			var counted := 0
			for v in velocities:
				if v.length_squared() > 0.01:
					cos_sum += v.normalized().dot(ref_dir)
					counted += 1
			if counted > 0:
				velocity_coherence = cos_sum / float(counted)
		else:
			velocity_coherence = 0.0  ## 速度相互抵消（完全对立）

	var active_count = total - waiting
	var freeze_rate_val = snappedf(float(frozen) / float(total), 0.01)

	## 23C：收集 stuck_nudge_total 和 direction_change_rate
	var stuck_nudge_total := 0
	for i in range(total):
		var s = _dummy_soldiers[i]
		if not is_instance_valid(s):
			continue
		var nudge = s.get("_stuck_nudge_count")
		if nudge != null:
			stuck_nudge_total += int(nudge)

	## 23C：convergence_frames 计算 — 在 freeze_rate 首次达到 1.0 时锁定
	if _formation_state == "deployed" and _convergence_frames < 0:
		if freeze_rate_val >= 1.0 and _convergence_start_frame >= 0:
			_convergence_frames = _current_frame - _convergence_start_frame

	return {
		"formation_state": _formation_state,
		"path_buffer_size": _path_buffer.size(),
		"avg_slot_error": snappedf(sum_err / float(max(active_count, 1)), 0.1),
		"max_slot_error": snappedf(max_err, 0.1),
		"waiting_count": waiting,
		"pos_std_dev": snappedf(pos_std_dev, 0.1),
		"lateral_spread": snappedf(lateral_spread, 0.1),
		"velocity_coherence": snappedf(velocity_coherence, 0.01),
		"overshoot_count": overshoot,
		"freeze_rate": freeze_rate_val,
		"stuck_nudge_total": stuck_nudge_total,
		"convergence_frames": _convergence_frames,
		"direction_change_rate": 0.0,  ## 23C.2 预留，暂输出 0（逐帧追踪成本高，后续按需实现）
	}


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


## 23B：局部流场生成 — 每 flow_field_update_interval 帧从 path_buffer 重建流场
## 以 path_buffer 轨迹为中心线，两侧扩展 half_width 格，每格存前进方向。
## headless 模式跳过（flow_field 算法在 headless 不使用）。
func _update_flow_field() -> void:
	if _is_headless_mode():
		return
	_flow_field_timer += 1
	if _flow_field_timer < _flow_field_update_interval:
		return
	_flow_field_timer = 0

	_flow_field.clear()
	var n = _path_buffer.size()
	if n < 2:
		return

	var cell = _flow_field_cell_size
	for i in range(n - 1):
		var p0: Vector3 = _path_buffer[i]       ## 较新点（索引小 = 更近将领）
		var p1: Vector3 = _path_buffer[i + 1]   ## 较旧点
		## 前进方向 = 从旧到新（士兵跟随方向）
		var fwd = Vector3(p0.x - p1.x, 0.0, p0.z - p1.z)
		if fwd.length_squared() < 0.001:
			continue
		fwd = fwd.normalized()
		var lat = Vector3(-fwd.z, 0.0, fwd.x)   ## 横向方向

		## 以两点中点为锚，扩展 half_width 格
		var mid = Vector3((p0.x + p1.x) * 0.5, 0.0, (p0.z + p1.z) * 0.5)
		for w in range(-_flow_field_half_width, _flow_field_half_width + 1):
			var world_pos = mid + lat * w * cell
			var gx = int(floor(world_pos.x / cell))
			var gz = int(floor(world_pos.z / cell))
			var key = Vector2i(gx, gz)
			## 已有值则融合（取均值），让重叠格子方向更平滑
			if _flow_field.has(key):
				var existing: Vector3 = _flow_field[key]
				var blended = (existing + fwd).normalized()
				_flow_field[key] = blended
			else:
				_flow_field[key] = fwd


## 23B：查询指定世界坐标的流场方向
## 返回该格子的前进方向；若无数据则退回 _march_direction。
func get_flow_direction(pos: Vector3) -> Vector3:
	if _flow_field.is_empty():
		return _march_direction
	var cell = _flow_field_cell_size
	var key = Vector2i(int(floor(pos.x / cell)), int(floor(pos.z / cell)))
	if _flow_field.has(key):
		return _flow_field[key]
	## 找最近邻格子（搜索 2 格范围）
	var best_dir = _march_direction
	var best_dist := INF
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var k = Vector2i(key.x + dx, key.y + dz)
			if _flow_field.has(k):
				var d = float(dx * dx + dz * dz)
				if d < best_dist:
					best_dist = d
					best_dir = _flow_field[k]
	return best_dir


## 23B：辅助判断是否 headless（_ready 后可用）
func _is_headless_mode() -> bool:
	return DisplayServer.get_name() == "headless"


## 19：阵型状态检测 — 全员到位后才展开
## 将领停止不触发展开；而是等全体士兵 avg_slot_error < deploy_ready_threshold（全员到位）
## 且将领已停止，持续 deploy_trigger_frames 帧后才切换 DEPLOYED。
## 计时器从"全员到位"那一刻开始计，将领停下时不走。
func _detect_formation_state() -> void:
	## 分状态使用不同移动判定阈值：
	## - deployed 时用 3.0：防止 RigidBody3D 哑兵推挤将领的微移（1-3 units/frame）误触发复原
	## - marching 时用 1.0：将领行进速度约 3.3 units/frame，低阈值才能正确识别"在走"
	##   若 marching 时也用 3.0，将领近目标减速至 <3.0 时会被误判为"停止"，
	##   deploy_timer 提前开始计数导致 deployed 过早触发，哑兵不再跟随行进。
	var move_threshold = 3.0 if _formation_state == "deployed" else 1.0
	var moved = global_position.distance_to(_prev_position) > move_threshold
	if moved:
		_deploy_timer = 0
		_static_frames = 0
		_deploy_anchor = Vector3.ZERO
		if _formation_state == "deployed":
			_formation_state = "marching"
			_rebuild_slot_assignment("marching")
		return

	_static_frames += 1  ## 将领静止：每帧递增

	if _formation_state != "marching":
		return

	## 初始冷却：前 N 帧不触发展开，避免启动瞬间误判
	if _deploy_cooldown > 0:
		_deploy_cooldown -= 1
		return

	## 哑兵未注册时不检测
	if _dummy_soldiers.is_empty():
		return

	## 将领第一次静止时快照锚点：之后横阵槽位固定在此坐标，不随将领被推挤而漂移
	if _deploy_anchor == Vector3.ZERO:
		_deploy_anchor = global_position
		_convergence_start_frame = _current_frame  ## 23C：记录收敛计时起点

	## 将领已静止：检查全员是否到位
	## _deploy_timer：全员到位后才递增（触发展开的计时器）
	## _static_frames：将领静止就递增（兜底超时用）
	var total = _dummy_soldiers.size()
	var all_arrived = true
	var arrive_thr = float(_general_cfg.get("dummy_arrive_threshold", 15.0))
	var static_too_long = _static_frames >= 400

	if static_too_long:
		var summary = get_formation_summary()
		all_arrived = summary.get("avg_slot_error", 999.0) < _deploy_ready_threshold
	else:
		for i in range(total):
			var s = _dummy_soldiers[i]
			if not is_instance_valid(s):
				continue
			if s.get("_waiting") == true:
				all_arrived = false
				break
			var slot = get_formation_slot(i, total, s.global_position)
			if s.global_position.distance_to(slot) > arrive_thr * 2.0:
				all_arrived = false
				break

	if all_arrived:
		_deploy_timer += 1
		if _deploy_timer >= _deploy_trigger_frames:
			_formation_state = "deployed"
			## 23C：记录收敛开始帧（将领停止时 _convergence_start_frame 已在 _detect_formation_state 中设置）
			if _convergence_start_frame < 0:
				_convergence_start_frame = _current_frame
			_convergence_frames = -1  ## 重置，等待 freeze_rate=1.0 时完成
			## 19E：切入 deployed 时做最近邻槽位重分配，每个士兵去最近横阵槽位
			_rebuild_slot_assignment("deployed")
			## 诊断日志：打印重分配结果
			var diag = "[DEPLOY-ASSIGN] anchor=(%.0f,%.0f) assignments: " % [_deploy_anchor.x, _deploy_anchor.z]
			for si in range(_dummy_soldiers.size()):
				var assigned = _slot_assignment.get(si, si)
				diag += "%d→%d " % [si, assigned]
			print(diag)
	else:
		_deploy_timer = 0


## 19：纵队行军槽位计算 — 路径跟随风格
## 每排跟随 path_buffer 中不同深度的历史点，越后排延迟越大，产生蛇形拖尾感。
## path_buffer[0] 为最新点（最近将领走过），索引越大越旧（越远）。
## 19G：path_buffer 不足时统一返回 current_pos（原地等待），产生真正的多米诺效果：
##   前排路径点先积累到，前排先动；后排依次解锁，一个接一个跟上将领。
##   deployed→marching 后哑兵已分散在横阵各位置，原地等待不会挤团。
func _get_march_slot(index: int, current_pos: Vector3 = Vector3.ZERO) -> Vector3:
	var row = index / _march_column_width
	var col_slot = index % _march_column_width
	var col_offset = float(col_slot) - float(_march_column_width - 1) * 0.5
	var lateral_dir = Vector3(-_march_direction.z, 0.0, _march_direction.x)

	var path_idx = _march_lead_offset + row * _march_row_path_step
	if _path_buffer.size() > path_idx:
		var anchor = _path_buffer[path_idx]
		return anchor + lateral_dir * _deploy_col_spacing * col_offset
	else:
		## path_buffer 不足：原地等待，直到将领走够距离该排才解锁（多米诺效果）
		return current_pos


## 16：横阵列阵槽位计算
## 使用 _deploy_anchor（将领静止时的快照坐标）而非 global_position，
## 避免 RigidBody3D 哑兵推挤将领导致槽位抖动、哑兵追着跑永远到不了位。
func _get_deploy_slot(index: int) -> Vector3:
	var row = index / _deploy_columns
	var col = index % _deploy_columns
	var col_offset = float(col) - float(_deploy_columns - 1) * 0.5
	var lateral_dir = Vector3(-_march_direction.z, 0.0, _march_direction.x)
	var anchor = _deploy_anchor if _deploy_anchor != Vector3.ZERO else global_position

	return anchor \
		- _march_direction * _deploy_row_spacing * float(row + 1) \
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
