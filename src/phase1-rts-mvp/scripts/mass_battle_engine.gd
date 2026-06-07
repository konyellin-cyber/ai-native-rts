extends Node3D
class_name MassBattleEngine

## Phase 24 — Mass Battle Engine
## 专为 500 人规模设计的人海战场引擎。
## 士兵 = 纯 PackedArray 数据，无 Godot 物理节点。
## 模拟：FlowFieldManager 驱动 + CrowdSimulator 压力积分。
## 战斗：相遇即近战，冲量击退。
## 渲染：通过 BattleRenderer（MultiMesh）每帧写入 Transform。

## ── 常量 ──────────────────────────────────────────────
const STATE_MARCHING: int = 0
const STATE_DEPLOYED: int = 1
const STATE_DEAD:     int = 2

const TEAM_RED:  int = 0
const TEAM_BLUE: int = 1

## ── 士兵状态（PackedArrays，SoA 布局）────────────────
var _positions:    PackedVector3Array  ## 当前位置
var _velocities:   PackedVector3Array  ## 当前速度
var _hps:          PackedFloat32Array  ## 生命值
var _teams:        PackedInt32Array    ## TEAM_RED / TEAM_BLUE
var _general_ids:  PackedInt32Array    ## 归属将领索引（0=红，1=蓝）
var _states:       PackedInt32Array    ## STATE_*
var _stun_frames:  PackedInt32Array    ## 受击硬直剩余帧
var _slot_indices: PackedInt32Array    ## 编队槽位编号（用于横向偏移）

var _soldier_count: int = 0
var _alive_red:     int = 0
var _alive_blue:    int = 0

## ── SpatialHash（内嵌）────────────────────────────────
var _sh_cells:     Dictionary = {}   ## Vector2i → Array[int]
var _sh_cell_size: float = 40.0

## ── 将领引用 ──────────────────────────────────────────
var _generals: Array = []  ## [red_general, blue_general]

## ── 配置参数（从 config 读取）──────────────────────────
var _crowd_radius:        float = 24.0
var _crowd_weight:        float = 1.2
var _pressure_max_force:  float = 200.0
var _drive_strength:      float = 320.0
var _max_speed:           float = 140.0
var _damp:                float = 0.85
var _attack_range:        float = 20.0
var _damage_per_hit:      float = 10.0
var _impulse_strength:    float = 120.0
var _stun_duration:       int   = 10
var _attack_interval:     int   = 30
var _boundary_margin:     float = 60.0
var _boundary_force:      float = 300.0
var _hp_per_soldier:      float = 100.0
var _map_width:           float = 2560.0
var _map_height:          float = 1664.0

## 每侧兵数 / 横排布局
var _count_per_side:    int = 250
var _count_blue:        int = 250   ## 蓝方实际兵数（支持非对称）
var _cols_per_row:      int = 25   ## 每排多少人（横排）
var _soldier_spacing:   float = 28.0  ## 士兵间距

## 阵型跟随（将领带兵模式）
var _formation_initial_z: PackedFloat32Array   ## 每名士兵的初始 Z 槽位
var _formation_follow_weight:    float = 0.6   ## 阵型归位力权重（0=关闭，1=强归位）
var _formation_engage_distance:  float = 200.0 ## 与敌方距离小于此值时停止归位，进入混战

## ── 固定行军目标（由 bootstrap 在 setup 后注入）──────
var _red_march_target:  Vector3 = Vector3.ZERO
var _blue_march_target: Vector3 = Vector3.ZERO

## ── 每帧缓存的队伍质心 ────────────────────────────────
var _centroid_red:  Vector3 = Vector3.ZERO
var _centroid_blue: Vector3 = Vector3.ZERO

## ── 帧计数 ────────────────────────────────────────────
var _frame: int = 0
var _attack_timer: int = 0

## ── Phase 26 性能采样（µs）──────────────────────────
var _perf_crowd_us:   int = 0   ## 上一帧 simulate_crowd(_p26) 耗时
var _perf_combat_us:  int = 0   ## 上一帧 _resolve_combat 耗时

## ── Phase 26：阵线力学引擎 ────────────────────────────
var _phase26_enabled:    bool  = false
var _contact_factor:     PackedFloat32Array
var _nearest_enemy_dist: PackedFloat32Array
var _nearest_enemy_idx:  PackedInt32Array
var _p_pred:             PackedVector3Array
var _neighbors_enemy_short: Array = [] ## Array[PackedInt32Array]，hard separation 专用短邻居表
var _neighbors_friend:      Array = [] ## Array[PackedInt32Array]，friend pressure / support push 专用邻居表

var _front_line_x:       float = 0.0
var _front_line_valid:   bool  = false
var _front_count_red:    int   = 0
var _front_count_blue:   int   = 0

## Phase 26 配置参数
var _contact_near:       float = 20.0
var _contact_far:        float = 80.0
var _hard_radius:        float = 8.0
var _min_front_drive_ratio:  float = 0.2
var _min_front_speed_ratio:  float = 0.15
var _support_push_strength:  float = 80.0
var _lateral_jitter_strength: float = 3.0
var _min_front_count:    int   = 10
var _front_tolerance:    float = 15.0
var _front_advance_rate: float = 0.05
var _front_smooth_tau:   float = 0.15
var _hard_separation_iterations: int = 2
var _hard_margin:        float = 5.0
var _support_refresh_interval: int  = 8  ## support push 缓存刷新周期（帧）

## ── Support Push 缓存 ────────────────────────────────
var _nearest_front_friend_idx: PackedInt32Array  ## 每名士兵最近前排友军缓存（-1=无）
var _support_cache_frame:      int = 0           ## 上次刷新时的帧号

## ── 力学正确性指标（26H）────────────────────────────
var _stat_enemy_overlap_pairs: int = 0    ## 每帧敌对 hard_radius 穿透对数
var _stat_contact_switches:    int = 0    ## 每帧 contact_factor 跨 0.7 切换次数
var _prev_contact_above_07:    PackedInt32Array  ## 上帧 cf > 0.7 的 bit（0/1 存为 int）

## ── 命中回调（粒子池注入）─────────────────────────────
## 签名：func on_hit(pos: Vector3, team: int) -> void
var _hit_callback: Callable = Callable()

## ── 内部引用 ──────────────────────────────────────────
var _flow_field_mgr: Node = null   ## FlowFieldManager 实例（由 bootstrap 注入）
var _renderer: Node       = null   ## BattleRenderer 实例（由 bootstrap 注入）
var _is_headless: bool    = false


## ─────────────────────────────────────────────────────
## 初始化
## ─────────────────────────────────────────────────────

func setup(cfg: Dictionary, red_general: Node, blue_general: Node,
		map_size: Vector2, headless: bool) -> void:
	_is_headless = headless
	_map_width    = map_size.x
	_map_height   = map_size.y

	## 读取 mass_battle 配置块
	var mb: Dictionary = cfg.get("mass_battle", {})
	_count_per_side   = int(mb.get("soldier_count_per_side",  250))
	_count_blue       = int(mb.get("soldier_count_blue_override", _count_per_side))
	_crowd_radius     = float(mb.get("crowd_radius",          24.0))
	_crowd_weight     = float(mb.get("crowd_weight",          1.2))
	_pressure_max_force = float(mb.get("pressure_max_force",  200.0))
	_drive_strength   = float(mb.get("drive_strength",        320.0))
	_max_speed        = float(mb.get("max_speed",             140.0))
	_damp             = float(mb.get("damp",                  0.85))
	_attack_range     = float(mb.get("attack_range",          20.0))
	_damage_per_hit   = float(mb.get("damage_per_hit",        10.0))
	_impulse_strength = float(mb.get("impulse_strength",      120.0))
	_stun_duration    = int(mb.get("stun_duration",           10))
	_attack_interval  = int(mb.get("attack_interval_frames",  30))
	_sh_cell_size     = float(mb.get("spatial_hash_cell_size", 40.0))
	_hp_per_soldier   = float(mb.get("hp_per_soldier",        100.0))
	_soldier_spacing  = float(mb.get("soldier_spacing",       28.0))
	_cols_per_row     = int(mb.get("cols_per_row",            25))
	_formation_follow_weight   = float(mb.get("formation_follow_weight",   0.6))
	_formation_engage_distance = float(mb.get("formation_engage_distance", 200.0))

	## Phase 26 参数
	_phase26_enabled           = bool(mb.get("phase26_mechanics_enabled", false))
	_contact_near              = float(mb.get("contact_near",             20.0))
	_contact_far               = float(mb.get("contact_far",             80.0))
	_hard_radius               = float(mb.get("hard_radius",             8.0))
	_min_front_drive_ratio     = float(mb.get("min_front_drive_ratio",   0.2))
	_min_front_speed_ratio     = float(mb.get("min_front_speed_ratio",   0.15))
	_support_push_strength     = float(mb.get("support_push_strength",   80.0))
	_lateral_jitter_strength   = float(mb.get("lateral_jitter_strength", 3.0))
	_min_front_count           = int(mb.get("min_front_count",           10))
	_front_tolerance           = float(mb.get("front_tolerance",         15.0))
	_front_advance_rate        = float(mb.get("front_advance_rate",      0.05))
	_front_smooth_tau          = float(mb.get("front_smooth_tau",        0.15))
	_hard_separation_iterations = int(mb.get("hard_separation_iterations", 2))
	_hard_margin               = float(mb.get("hard_margin",            5.0))
	_support_refresh_interval  = int(mb.get("support_refresh_interval", 8))

	_generals = [red_general, blue_general]
	_init_soldiers()


## 按横排初始化双方士兵位置
## 红方：战场左侧横排，蓝方：战场右侧横排
func _init_soldiers() -> void:
	## renderer 按 count_per_side × 2 分配 instance，所以总长度保持对齐
	var n = _count_per_side * 2
	_positions    = PackedVector3Array(); _positions.resize(n)
	_velocities   = PackedVector3Array(); _velocities.resize(n)
	_hps          = PackedFloat32Array(); _hps.resize(n)
	_teams        = PackedInt32Array();   _teams.resize(n)
	_general_ids  = PackedInt32Array();   _general_ids.resize(n)
	_states       = PackedInt32Array();   _states.resize(n)
	_stun_frames  = PackedInt32Array();   _stun_frames.resize(n)
	_slot_indices = PackedInt32Array();   _slot_indices.resize(n)
	_formation_initial_z = PackedFloat32Array(); _formation_initial_z.resize(n)

	## 先把所有 slot 标记为 DEAD（覆盖默认 0=MARCHING）
	for i in range(n):
		_states[i] = STATE_DEAD
		_positions[i] = Vector3(0, -1000, 0)

	## 初始摆放：横排，以各将领为中心前方排布
	for team in [TEAM_RED, TEAM_BLUE]:
		var team_count: int = _count_per_side if team == TEAM_RED else _count_blue
		var base_offset: int = 0 if team == TEAM_RED else _count_per_side
		var general: Node = _generals[team]
		var base_pos: Vector3 = general.global_position if is_instance_valid(general) \
			else Vector3(_map_width * (0.2 if team == TEAM_RED else 0.8), 0.0, _map_height * 0.5)

		## 行进方向：红方向右（+X），蓝方向左（-X）
		var forward := Vector3(1.0, 0.0, 0.0) if team == TEAM_RED else Vector3(-1.0, 0.0, 0.0)
		var lateral := Vector3(0.0, 0.0, 1.0)

		var cols = _cols_per_row
		var rows = int(ceil(float(team_count) / float(cols)))

		for i in range(team_count):
			var global_idx: int = base_offset + i
			var col: int = i % cols
			var row: int = i / cols

			## 横向居中：以将领为中心，向两侧展开
			var cx = (float(col) - float(cols - 1) * 0.5) * _soldier_spacing
			## 纵向：将领后方排列（略后于将领）
			var cz = float(row + 1) * _soldier_spacing

			var pos = base_pos + lateral * cx - forward * cz
			pos.y = 0.0

			_positions[global_idx]    = pos
			_velocities[global_idx]   = Vector3.ZERO
			_hps[global_idx]          = _hp_per_soldier
			_teams[global_idx]        = team
			_general_ids[global_idx]  = team
			_states[global_idx]       = STATE_MARCHING
			_stun_frames[global_idx]  = 0
			_slot_indices[global_idx] = i
			_formation_initial_z[global_idx] = pos.z  ## 记录槽位 Z，用于将领带兵归位

	_soldier_count = n
	_alive_red     = _count_per_side
	_alive_blue    = _count_blue

	## Phase 26 字段初始化
	if _phase26_enabled:
		_contact_factor     = PackedFloat32Array(); _contact_factor.resize(n)
		_nearest_enemy_dist = PackedFloat32Array(); _nearest_enemy_dist.resize(n)
		_nearest_enemy_idx  = PackedInt32Array();   _nearest_enemy_idx.resize(n)
		_p_pred             = PackedVector3Array();  _p_pred.resize(n)
		_neighbors_enemy_short.resize(n)
		_neighbors_friend.resize(n)
		for idx in range(n):
			_neighbors_enemy_short[idx] = PackedInt32Array()
			_neighbors_friend[idx] = PackedInt32Array()
		_front_line_x = (_positions[0].x + _positions[n - 1].x) * 0.5
		## Support Push 缓存
		_nearest_front_friend_idx = PackedInt32Array()
		_nearest_front_friend_idx.resize(n)
		_nearest_front_friend_idx.fill(-1)
		## 力学正确性指标
		_prev_contact_above_07 = PackedInt32Array()
		_prev_contact_above_07.resize(n)
		_prev_contact_above_07.fill(0)

	print("[MBE] init_soldiers: total=%d  red=%d  blue=%d  phase26=%s" % [n, _count_per_side, _count_blue, str(_phase26_enabled)])


## ─────────────────────────────────────────────────────
## 注入依赖
## ─────────────────────────────────────────────────────

func set_flow_field_manager(ffm: Node) -> void:
	_flow_field_mgr = ffm

func set_renderer(r: Node) -> void:
	_renderer = r

func set_hit_callback(cb: Callable) -> void:
	_hit_callback = cb

## 注入双方行军目标（直接目标驱动，不依赖将领实时位置）
func set_march_targets(red_target: Vector3, blue_target: Vector3) -> void:
	_red_march_target  = red_target
	_blue_march_target = blue_target
	print("[MBE] march_targets — red→(%.0f,%.0f)  blue→(%.0f,%.0f)" % [
		red_target.x, red_target.z, blue_target.x, blue_target.z])


## ─────────────────────────────────────────────────────
## 主循环
## ─────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	_frame += 1

	## 1. 重建 SpatialHash
	_sh_rebuild()

	## 1.5 更新质心缓存（每帧一次，O(n)，供 _get_flow_dir 查询）
	_update_centroids()

	## 2. CrowdSimulator：移动积分
	var t0: int = Time.get_ticks_usec()
	if _phase26_enabled:
		_simulate_crowd_p26(delta)
	else:
		_simulate_crowd(delta)
	_perf_crowd_us = Time.get_ticks_usec() - t0

	## 3. CombatResolver：战斗判定（每 attack_interval 帧执行一次）
	_attack_timer += 1
	if _attack_timer >= _attack_interval:
		_attack_timer = 0
		var tc: int = Time.get_ticks_usec()
		_resolve_combat()
		_perf_combat_us = Time.get_ticks_usec() - tc

	## 4. 通知渲染层更新
	if _renderer != null and is_instance_valid(_renderer):
		_renderer.update(_positions, _velocities, _states, _teams, _count_per_side, _stun_frames)

	## 5. 定期打印状态日志
	if _frame % 60 == 0:
		print("[MBE] frame=%d  alive_red=%d  alive_blue=%d" % [_frame, _alive_red, _alive_blue])


## ─────────────────────────────────────────────────────
## SpatialHash
## ─────────────────────────────────────────────────────

func _sh_rebuild() -> void:
	_sh_cells.clear()
	for i in range(_soldier_count):
		if _states[i] == STATE_DEAD:
			continue
		var pos: Vector3 = _positions[i]
		var key := Vector2i(int(floor(pos.x / _sh_cell_size)),
							int(floor(pos.z / _sh_cell_size)))
		if not _sh_cells.has(key):
			_sh_cells[key] = []
		_sh_cells[key].append(i)


func _sh_get_neighbors(pos: Vector3) -> Array:
	var cx := int(floor(pos.x / _sh_cell_size))
	var cz := int(floor(pos.z / _sh_cell_size))
	var result: Array = []
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var key := Vector2i(cx + dx, cz + dz)
			if _sh_cells.has(key):
				result.append_array(_sh_cells[key])
	return result


## ─────────────────────────────────────────────────────
## CrowdSimulator
## ─────────────────────────────────────────────────────

func _simulate_crowd(delta: float) -> void:
	for i in range(_soldier_count):
		if _states[i] == STATE_DEAD:
			continue
		if _stun_frames[i] > 0:
			_stun_frames[i] -= 1
			## 硬直中仍做阻尼衰减，避免被击退后滑行太远
			_velocities[i] = _velocities[i] * (1.0 - _damp * delta * 10.0)
			_positions[i] += _velocities[i] * delta
			_clamp_to_boundary(i)
			continue

		## 1. 流场驱动力（纯方向，不加 lateral offset — Crowd Pressure 自然维持间距）
		var flow_dir := _get_flow_dir(i)
		var drive := flow_dir.normalized() * _drive_strength

		## 2. Crowd Pressure（邻居排斥力）
		var pressure := Vector3.ZERO
		var neighbors := _sh_get_neighbors(_positions[i])
		for j in neighbors:
			if j == i or _states[j] == STATE_DEAD:
				continue
			var delta_pos: Vector3 = _positions[i] - _positions[j]
			var dist: float = delta_pos.length()
			if dist < _crowd_radius and dist > 0.01:
				var t := 1.0 - dist / _crowd_radius
				pressure += delta_pos.normalized() * (t * t * _pressure_max_force)

		## 3. 边界斥力
		var boundary := _boundary_repulsion(i)

		## 4. 速度半隐式 Euler 积分
		var force := drive + pressure * _crowd_weight + boundary
		var vel: Vector3 = _velocities[i]
		vel = vel * (1.0 - _damp * delta * 8.0) + force * delta
		vel = vel.limit_length(_max_speed)
		_velocities[i] = vel
		_positions[i] += vel * delta
		_clamp_to_boundary(i)


func _get_flow_dir(idx: int) -> Vector3:
	## 优先：流场查询（将领已建立路径后）
	if _flow_field_mgr != null and is_instance_valid(_flow_field_mgr):
		var dir: Vector3 = _flow_field_mgr.get_direction(_general_ids[idx], _positions[idx])
		if dir.length_squared() > 0.1:
			## 流场有效时：叠加 Z 槽位归位力，保持横排展开
			## 仅在行军阶段（与敌距离 > engage_distance）启用归位
			var enemy_team: int = 1 - _teams[idx]
			var enemy_center := _get_team_centroid(enemy_team)
			var dist_to_enemy := (_positions[idx] - enemy_center).length() if enemy_center != Vector3.ZERO else INF
			if dist_to_enemy > _formation_engage_distance and _formation_follow_weight > 0.0:
				var slot_z: float = _formation_initial_z[idx]
				var cur_z:  float = _positions[idx].z
				var z_err:  float = slot_z - cur_z
				var z_pull := Vector3(0.0, 0.0, z_err * _formation_follow_weight * 0.1)
				return (dir + z_pull).normalized()
			return dir

	## fallback：将领带兵模式 —— 跟随己方将领位置 + Z槽位归位
	## 行军阶段让兵跟着将领一起水平推进，维持横排队形
	var general: Node = _generals[_general_ids[idx]] if _general_ids[idx] < _generals.size() else null
	var enemy_team: int = 1 - _teams[idx]
	var enemy_center := _get_team_centroid(enemy_team)
	var dist_to_enemy := (_positions[idx] - enemy_center).length() if enemy_center != Vector3.ZERO else INF

	if dist_to_enemy > _formation_engage_distance and general != null and is_instance_valid(general):
		## 行军阶段：朝将领方向前进（X轴驱动）+ Z轴归位至槽位
		var gen_pos: Vector3 = general.global_position
		var my_pos:  Vector3 = _positions[idx]
		## X 方向：跟随将领（纯水平直冲）
		var fwd_dir := Vector3(1.0 if _teams[idx] == TEAM_RED else -1.0, 0.0, 0.0)
		## Z 方向：归位到初始槽位
		var slot_z: float = _formation_initial_z[idx]
		var z_err: float  = slot_z - my_pos.z
		var z_pull := Vector3(0.0, 0.0, z_err * _formation_follow_weight)
		return (fwd_dir + z_pull).normalized()

	## 交战阶段：追对方质心（进入混战乱斗）
	if enemy_center != Vector3.ZERO:
		var diff: Vector3 = enemy_center - _positions[idx]
		diff.y = 0.0
		if diff.length_squared() > 1.0:
			return diff.normalized()

	## 最终 fallback：固定前进方向
	var target: Vector3 = _red_march_target if _teams[idx] == TEAM_RED else _blue_march_target
	if target != Vector3.ZERO:
		var diff: Vector3 = target - _positions[idx]
		diff.y = 0.0
		if diff.length_squared() > 0.01:
			return diff.normalized()
	return Vector3(1.0 if _teams[idx] == TEAM_RED else -1.0, 0.0, 0.0)


## 每帧更新双方质心缓存（O(n) 一次）
func _update_centroids() -> void:
	var sr := Vector3.ZERO; var cr: int = 0
	var sb := Vector3.ZERO; var cb: int = 0
	for i in range(_soldier_count):
		if _states[i] == STATE_DEAD:
			continue
		if _teams[i] == TEAM_RED:
			sr += _positions[i]; cr += 1
		else:
			sb += _positions[i]; cb += 1
	_centroid_red  = sr / float(cr) if cr > 0 else _red_march_target
	_centroid_blue = sb / float(cb) if cb > 0 else _blue_march_target


## 计算指定队伍的存活士兵质心（用于持续追击）
func _get_team_centroid(team: int) -> Vector3:
	return _centroid_red if team == TEAM_RED else _centroid_blue


func _slot_lateral_offset(idx: int) -> Vector3:
	## 根据槽位编号计算横向偏移方向，使士兵保持横排间距
	var slot: int = _slot_indices[idx]
	var col: int  = slot % _cols_per_row
	## 以排中心为 0，向两侧各取正负偏移
	var center := float(_cols_per_row - 1) * 0.5
	var offset_units := (float(col) - center) * _soldier_spacing
	## 横向轴：红方行进方向(+X)的侧向 = +Z；蓝方(-X)的侧向 = +Z 方向相同
	## 这里统一用 +Z 轴作为横向基准
	return Vector3(0.0, 0.0, offset_units * 0.01)  ## 归一化量级，作为方向权重


func _boundary_repulsion(idx: int) -> Vector3:
	var pos: Vector3 = _positions[idx]
	var force := Vector3.ZERO
	var m := _boundary_margin
	if pos.x < m:
		force.x += _boundary_force * (1.0 - pos.x / m)
	elif pos.x > _map_width - m:
		force.x -= _boundary_force * (1.0 - (_map_width - pos.x) / m)
	if pos.z < m:
		force.z += _boundary_force * (1.0 - pos.z / m)
	elif pos.z > _map_height - m:
		force.z -= _boundary_force * (1.0 - (_map_height - pos.z) / m)
	return force


func _clamp_to_boundary(idx: int) -> void:
	var pos: Vector3 = _positions[idx]
	pos.x = clamp(pos.x, 0.0, _map_width)
	pos.z = clamp(pos.z, 0.0, _map_height)
	pos.y = 0.0
	_positions[idx] = pos


## ─────────────────────────────────────────────────────
## CombatResolver
## ─────────────────────────────────────────────────────

func _resolve_combat() -> void:
	## 两阶段同步战斗：先收集所有攻击意图，再统一应用伤害
	## 目的：消除处理顺序偏差（红方索引 0-249 先执行会让蓝方总在同 tick 被打晕无法反击）
	## Phase 24 fix: simultaneous resolution ensures both teams attack in the same tick

	## ── Phase 1：收集攻击意图 ────────────────────────────
	var hit_list: Array = []   ## Array of [attacker_i, victim_j, impulse_dir: Vector3]

	for i in range(_soldier_count):
		if _states[i] == STATE_DEAD or _stun_frames[i] > 0:
			continue

		var neighbors := _sh_get_neighbors(_positions[i])
		var best_j:    int   = -1
		var best_dist: float = _attack_range

		for j in neighbors:
			if j == i or _states[j] == STATE_DEAD:
				continue
			if _teams[j] == _teams[i]:
				continue  ## 不打自己人
			var dist: float = (_positions[i] - _positions[j]).length()
			if dist < best_dist:
				best_dist = dist
				best_j    = j

		if best_j < 0:
			continue

		var impulse_dir: Vector3 = (_positions[best_j] - _positions[i])
		impulse_dir.y = 0.0
		if impulse_dir.length_squared() > 0.001:
			impulse_dir = impulse_dir.normalized()
		else:
			impulse_dir = Vector3(randf() - 0.5, 0.0, randf() - 0.5).normalized()
		hit_list.append([i, best_j, impulse_dir])

	## ── Phase 2：统一应用伤害（双方同时结算）────────────
	for hit in hit_list:
		var best_j:      int     = hit[1]
		var impulse_dir: Vector3 = hit[2]

		if _states[best_j] == STATE_DEAD:
			continue  ## 本 tick 已被别人击杀，跳过

		## 造成伤害
		_hps[best_j] -= _damage_per_hit
		if _hps[best_j] <= 0.0:
			_hps[best_j] = 0.0
			_states[best_j] = STATE_DEAD
			if _teams[best_j] == TEAM_RED:
				_alive_red  = max(0, _alive_red  - 1)
			else:
				_alive_blue = max(0, _alive_blue - 1)

		## 击退冲量
		_velocities[best_j] += impulse_dir * _impulse_strength

		## 受击硬直
		_stun_frames[best_j] = _stun_duration

		## 命中粒子回调
		if _hit_callback.is_valid():
			_hit_callback.call(_positions[best_j], _teams[best_j])


## ─────────────────────────────────────────────────────
## 公开查询接口
## ─────────────────────────────────────────────────────

func get_alive_count(team: int) -> int:
	return _alive_red if team == TEAM_RED else _alive_blue

func get_total_alive() -> int:
	return _alive_red + _alive_blue

func get_frame() -> int:
	return _frame

## 返回所有存活士兵的 x 轴质心（供摄像机跟随使用）
func get_battle_center_x() -> float:
	return (_centroid_red.x + _centroid_blue.x) * 0.5 if (_alive_red + _alive_blue) > 0 else 0.0

func get_debug_stats() -> Dictionary:
	return {
		"frame":              _frame,
		"alive_red":          _alive_red,
		"alive_blue":         _alive_blue,
		"total_soldiers":     _soldier_count,
		"crowd_us":           _perf_crowd_us,
		"combat_us":          _perf_combat_us,
		"overlap_pairs":      _stat_enemy_overlap_pairs,
		"contact_switches":   _stat_contact_switches,
		"front_line_x":       _front_line_x,
		"front_line_valid":   _front_line_valid,
	}


## 26C.5 contact_factor 分布直方图（仅 Phase 26 有效）
## 返回 {low: int, mid: int, high: int}
## low=[0,0.3)  mid=[0.3,0.7)  high=[0.7,1.0]
func get_contact_histogram() -> Dictionary:
	if not _phase26_enabled or _contact_factor.size() == 0:
		return {"low": 0, "mid": 0, "high": 0}
	var low: int = 0; var mid: int = 0; var high: int = 0
	for i in range(_soldier_count):
		if _states[i] == STATE_DEAD:
			continue
		var cf: float = _contact_factor[i]
		if cf < 0.3:
			low += 1
		elif cf < 0.7:
			mid += 1
		else:
			high += 1
	return {"low": low, "mid": mid, "high": high}


## ─────────────────────────────────────────────────────
## Phase 26：阵线力学引擎
## ─────────────────────────────────────────────────────

func _simulate_crowd_p26(delta: float) -> void:
	## Step 0: 指标重置
	_stat_enemy_overlap_pairs = 0
	_stat_contact_switches    = 0

	## Step 1: 最近敌方扫描 + 分层邻居缓存
	_p26_scan_nearest_enemy()

	## Step 1.5: 每 support_refresh_interval 帧刷新 support push 缓存
	if (_frame - _support_cache_frame) >= _support_refresh_interval or _support_cache_frame == 0:
		_p26_refresh_support_cache()
		_support_cache_frame = _frame

	## Step 2: 阵线位置更新
	_p26_update_front_line(delta)

	## Step 3+4: 力学累加 + 位置预测
	_p26_accumulate_and_predict(delta)

	## Step 5: 硬碰撞分离（PBD 迭代）
	for _iter in range(_hard_separation_iterations):
		_p26_apply_hard_separation(false)

	## Step 6: 阵线约束
	_p26_apply_front_constraint()

	## Step 7: 阵线约束后的最终硬分离（修复二次重叠）
	_p26_apply_hard_separation(true)

	## Step 7.5: 统计残余穿透（所有迭代完成后）
	_p26_count_residual_overlaps()

	## Step 8: 反推速度，写回位置
	_p26_back_solve_velocity(delta)


## ── Step 1: Nearest Enemy Scan ───────────────────────

func _p26_scan_nearest_enemy() -> void:
	## 扫描半径：确保覆盖 crowd_radius（友军）和 hard_separation 需要的所有敌人
	## v4 优化：enemy_short 使用同样的 scan_radius，保证 hard separation 不漏检
	var scan_radius: float = max(_crowd_radius, _hard_radius * 2.0 + _hard_margin)
	var scan_radius_sq: float = scan_radius * scan_radius
	var friend_radius_sq: float = _crowd_radius * _crowd_radius
	var effective_contact_far: float = min(_contact_far, scan_radius)

	for i in range(_soldier_count):
		if _states[i] == STATE_DEAD:
			_contact_factor[i] = 0.0
			_nearest_enemy_dist[i] = INF
			_nearest_enemy_idx[i] = -1
			var dead_enemy_short: PackedInt32Array = _neighbors_enemy_short[i]
			var dead_friends: PackedInt32Array = _neighbors_friend[i]
			dead_enemy_short.resize(0)
			dead_friends.resize(0)
			_neighbors_enemy_short[i] = dead_enemy_short
			_neighbors_friend[i] = dead_friends
			continue

		var min_dist: float = INF
		var min_dist_sq: float = INF
		var min_idx:  int   = -1
		var enemy_short: PackedInt32Array = _neighbors_enemy_short[i]
		var friends: PackedInt32Array = _neighbors_friend[i]
		enemy_short.resize(0)
		friends.resize(0)
		var pos_i: Vector3 = _positions[i]
		var cx: int = int(floor(pos_i.x / _sh_cell_size))
		var cz: int = int(floor(pos_i.z / _sh_cell_size))
		var cell_range: int = int(ceil(scan_radius / _sh_cell_size))

		for dx in range(-cell_range, cell_range + 1):
			for dz in range(-cell_range, cell_range + 1):
				var key := Vector2i(cx + dx, cz + dz)
				if not _sh_cells.has(key):
					continue
				var cell: Array = _sh_cells[key]
				for j in cell:
					if j == i or _states[j] == STATE_DEAD:
						continue
					var dp: Vector3 = pos_i - _positions[j]
					dp.y = 0.0
					var dist_sq: float = dp.length_squared()
					if dist_sq > scan_radius_sq:
						continue
					if _teams[j] == _teams[i]:
						if dist_sq <= friend_radius_sq:
							friends.append(j)
						continue
					if dist_sq < min_dist_sq:
						min_dist_sq = dist_sq
						min_idx = j
					## 所有在 scan_radius 内的敌人都加入短表（保证 hard separation 不漏检）
					enemy_short.append(j)

		min_dist = sqrt(min_dist_sq) if min_idx >= 0 else INF
		_nearest_enemy_dist[i] = min_dist
		_nearest_enemy_idx[i]  = min_idx
		_neighbors_enemy_short[i] = enemy_short
		_neighbors_friend[i] = friends

		## 连续 contact_factor：v4 为性能将远端影响截断到 scan_radius/crowd_radius
		if min_dist <= _contact_near:
			_contact_factor[i] = 1.0
		elif min_dist >= effective_contact_far:
			_contact_factor[i] = 0.0
		else:
			var t: float = (min_dist - _contact_near) / (effective_contact_far - _contact_near)
			## smoothstep: 3t² - 2t³
			_contact_factor[i] = 1.0 - (t * t * (3.0 - 2.0 * t))

		## 26H：contact_switches 统计（跨 0.7 切换次数）
		var above_now: int = 1 if _contact_factor[i] > 0.7 else 0
		if above_now != _prev_contact_above_07[i]:
			_stat_contact_switches += 1
		_prev_contact_above_07[i] = above_now


## ── 半径 SpatialHash 查询 ────────────────────────────

func _sh_get_neighbors_radius(pos: Vector3, radius: float) -> PackedInt32Array:
	var cell_range: int = int(ceil(radius / _sh_cell_size))
	var cx: int = int(floor(pos.x / _sh_cell_size))
	var cz: int = int(floor(pos.z / _sh_cell_size))
	var result := PackedInt32Array()
	for dx in range(-cell_range, cell_range + 1):
		for dz in range(-cell_range, cell_range + 1):
			var key := Vector2i(cx + dx, cz + dz)
			if _sh_cells.has(key):
				result.append_array(_sh_cells[key])
	return result


## ── Step 2: Front Line Update ────────────────────────

func _p26_update_front_line(delta: float) -> void:
	var red_front_x:  float = -INF
	var blue_front_x: float = INF
	_front_count_red  = 0
	_front_count_blue = 0

	for i in range(_soldier_count):
		if _states[i] == STATE_DEAD or _contact_factor[i] < 0.7:
			continue
		if _teams[i] == TEAM_RED:
			if _positions[i].x > red_front_x:
				red_front_x = _positions[i].x
			_front_count_red += 1
		else:
			if _positions[i].x < blue_front_x:
				blue_front_x = _positions[i].x
			_front_count_blue += 1

	if _front_count_red >= _min_front_count and _front_count_blue >= _min_front_count:
		var target_x: float = (red_front_x + blue_front_x) * 0.5
		## 人多方推进
		target_x += float(_alive_red - _alive_blue) * _front_advance_rate * delta
		## 时间常数平滑（帧率无关）
		var alpha: float = 1.0 - exp(-delta / _front_smooth_tau)
		_front_line_x = lerpf(_front_line_x, target_x, alpha)
		_front_line_valid = true
	else:
		_front_line_valid = false


## ── Step 3+4: Force Accumulation + Predict ───────────

func _p26_accumulate_and_predict(delta: float) -> void:
	for i in range(_soldier_count):
		if _states[i] == STATE_DEAD:
			_p_pred[i] = _positions[i]
			continue

		## 硬直期间：不主动 drive，但仍预测位置参与硬分离
		if _stun_frames[i] > 0:
			_stun_frames[i] -= 1
			_velocities[i] = _velocities[i] * (1.0 - _damp * delta * 10.0)
			_p_pred[i] = _positions[i] + _velocities[i] * delta
			continue

		## 4a. 差异化 drive
		var flow_dir: Vector3 = _get_flow_dir(i)
		var cf: float = _contact_factor[i]
		var drive_mul: float = lerpf(1.0, _min_front_drive_ratio, cf)
		var drive: Vector3 = flow_dir.normalized() * _drive_strength * drive_mul

		## 4b. 友军 soft pressure（跳过敌军）
		var friend_pressure := Vector3.ZERO
		var friends: PackedInt32Array = _neighbors_friend[i]
		var crowd_radius_sq: float = _crowd_radius * _crowd_radius
		for j in friends:
			var dp: Vector3 = _positions[i] - _positions[j]
			dp.y = 0.0
			var dist_sq: float = dp.length_squared()
			if dist_sq < crowd_radius_sq and dist_sq > 0.0001:
				var dist: float = sqrt(dist_sq)
				var t: float = 1.0 - dist / _crowd_radius
				friend_pressure += (dp / dist) * (t * t * _pressure_max_force)

		## 4c. Support Push（后排推前排）—— 读缓存，每 support_refresh_interval 帧刷新一次
		var support := Vector3.ZERO
		if cf > 0.2 and cf < 0.7:
			var front_idx: int = _nearest_front_friend_idx[i]
			## 缓存失效检查（目标已死亡）
			if front_idx >= 0 and _states[front_idx] == STATE_DEAD:
				front_idx = _p26_find_nearest_front_friend(i, friends)
				_nearest_front_friend_idx[i] = front_idx
			if front_idx >= 0:
				var to_front: Vector3 = _positions[front_idx] - _positions[i]
				to_front.y = 0.0
				if to_front.length_squared() > 0.01:
					support = to_front.normalized() * _support_push_strength

		## 4d. 边界斥力
		var boundary: Vector3 = _boundary_repulsion(i)

		## 4e. 横向 jitter（仅前排）
		var jitter := Vector3.ZERO
		if cf > 0.7:
			var h: float = float((i * 31 + _frame) % 1000) / 1000.0 - 0.5
			jitter = Vector3(0.0, 0.0, h * _lateral_jitter_strength)

		## 4f. 速度积分 + 预测位置
		var force: Vector3 = drive + friend_pressure * _crowd_weight + support + boundary + jitter
		var v_pred: Vector3 = _velocities[i] * (1.0 - _damp * delta * 8.0) + force * delta
		var speed_mul: float = lerpf(1.0, _min_front_speed_ratio, cf)
		v_pred = v_pred.limit_length(_max_speed * speed_mul)
		_p_pred[i] = _positions[i] + v_pred * delta


## ── 刷新 Support Push 缓存 ──────────────────────────

func _p26_refresh_support_cache() -> void:
	for i in range(_soldier_count):
		if _states[i] == STATE_DEAD:
			_nearest_front_friend_idx[i] = -1
			continue
		if _contact_factor[i] <= 0.2 or _contact_factor[i] >= 0.7:
			## 不是"后排推进区"，不需要 support push
			_nearest_front_friend_idx[i] = -1
			continue
		var friends: PackedInt32Array = _neighbors_friend[i]
		_nearest_front_friend_idx[i] = _p26_find_nearest_front_friend(i, friends)


## ── 找最近的前排友军 ─────────────────────────────────

func _p26_find_nearest_front_friend(idx: int, neighbors: PackedInt32Array) -> int:
	var best_j: int = -1
	var best_dist: float = INF
	for j in neighbors:
		if j == idx or _states[j] == STATE_DEAD:
			continue
		if _teams[j] != _teams[idx]:
			continue
		if _contact_factor[j] < 0.7:
			continue
		var dist: float = (_positions[idx] - _positions[j]).length()
		if dist < best_dist:
			best_dist = dist
			best_j = j
	return best_j


## ── Step 5/7: Hard Separation (PBD) ─────────────────

func _p26_apply_hard_separation(front_only: bool = false) -> void:
	var min_dist_f: float = _hard_radius * 2.0
	var min_dist_sq: float = min_dist_f * min_dist_f

	for i in range(_soldier_count):
		if _states[i] == STATE_DEAD:
			continue
		if front_only and _contact_factor[i] <= 0.5:
			continue

		## 使用缓存的敌方邻居表（基于 positions 的 3×3 格查询，覆盖最大位移 2.4u/帧 的 p_pred 移动）
		var neighbors: PackedInt32Array = _neighbors_enemy_short[i]

		for j in neighbors:
			if j <= i:
				continue  ## 对称去重
			if _states[j] == STATE_DEAD:
				continue
			if front_only and _contact_factor[j] <= 0.5:
				continue
			var dp: Vector3 = _p_pred[i] - _p_pred[j]
			dp.y = 0.0
			var dist_sq: float = dp.length_squared()
			if dist_sq < min_dist_sq and dist_sq > 0.000001:
				var dist: float = sqrt(dist_sq)
				var overlap: float = min_dist_f - dist
				var correction: Vector3 = (dp / dist) * (overlap * 0.5)
				_p_pred[i] += correction
				_p_pred[j] -= correction
			elif dist_sq <= 0.000001:
				## 完全重合：确定性方向分离
				var angle: float = float((i * 73856093 + j * 19349663) & 1023) / 1024.0 * TAU
				var dir := Vector3(cos(angle), 0.0, sin(angle))
				_p_pred[i] += dir * _hard_radius
				_p_pred[j] -= dir * _hard_radius


## ── Step 7.5: Residual Overlap Count（统计修正后残余穿透）───────────────
## 使用缓存表（与 hard separation 同源），轻量、无额外 hash 查询

func _p26_count_residual_overlaps() -> void:
	var min_dist_sq: float = (_hard_radius * 2.0) * (_hard_radius * 2.0)
	for i in range(_soldier_count):
		if _states[i] == STATE_DEAD or _contact_factor[i] <= 0.0:
			continue
		var neighbors: PackedInt32Array = _neighbors_enemy_short[i]
		for j in neighbors:
			if j <= i or _states[j] == STATE_DEAD:
				continue
			## 注意：这里 teams 已经在 scan 时保证 enemy_short 只存敌人，无需再判断
			var dp: Vector3 = _p_pred[i] - _p_pred[j]
			dp.y = 0.0
			if dp.length_squared() < min_dist_sq:
				_stat_enemy_overlap_pairs += 1


## ── Step 6: Front Line Constraint ────────────────────

func _p26_apply_front_constraint() -> void:
	if not _front_line_valid:
		return
	for i in range(_soldier_count):
		if _states[i] == STATE_DEAD or _contact_factor[i] < 0.7:
			continue
		if _teams[i] == TEAM_RED:
			if _p_pred[i].x > _front_line_x + _front_tolerance:
				_p_pred[i].x = _front_line_x + _front_tolerance
		else:
			if _p_pred[i].x < _front_line_x - _front_tolerance:
				_p_pred[i].x = _front_line_x - _front_tolerance


## ── Step 8: Velocity Back-Solve ──────────────────────

func _p26_back_solve_velocity(delta: float) -> void:
	for i in range(_soldier_count):
		if _states[i] == STATE_DEAD:
			continue
		## 反推速度
		var new_v: Vector3 = (_p_pred[i] - _positions[i]) / delta
		var cf: float = _contact_factor[i]
		var speed_mul: float = lerpf(1.0, _min_front_speed_ratio, cf)
		_velocities[i] = new_v.limit_length(_max_speed * speed_mul)
		_positions[i] = _p_pred[i]
		_clamp_to_boundary(i)
