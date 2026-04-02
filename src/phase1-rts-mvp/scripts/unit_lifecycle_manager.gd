extends RefCounted
class_name UnitLifecycleManager

## Phase 1 UnitLifecycleManager — 单位生命周期管理
## 职责：清理死亡单位、维护存活计数、kill_log、状态追踪。
## bootstrap 通过 tick() 驱动，通过只读属性读取状态。

# ─── 只读状态（断言/bootstrap 读取）────────────────────────────────
var red_alive: int = 0
var blue_alive: int = 0
var kill_log: Array[Dictionary] = []
var worker_harvesting_seen: bool = false
var blue_crystal_delivered: bool = false
var production_occurred: bool = false
var archer_produced: bool = false  ## 玩家生产队列曾生产出 archer 单位

# ─── 内部依赖────────────────────────────────────────────────────────
var _units: Array       ## 引用 game_world.units（共享数组）
var _hq_blue: Node      ## StaticBody2D (hq_blue)
var _frame_count_ref: Callable  ## 返回当前帧号的回调
var _first_kill_cb: Callable    ## 首次击杀时回调一次（供 bootstrap 转发给 ux_observer）


func setup(units: Array, hq_blue: Node, frame_count_getter: Callable, first_kill_cb: Callable = Callable()) -> void:
	_units = units
	_hq_blue = hq_blue
	_frame_count_ref = frame_count_getter
	_first_kill_cb = first_kill_cb


func init_alive_counts(red: int, blue: int) -> void:
	## bootstrap 在初始单位生成后调用一次
	red_alive = red
	blue_alive = blue


func on_unit_died(victim_id: int, victim_team: String) -> void:
	## 由 bootstrap 连接 game_world.unit_died 信号后转发过来
	if victim_team == "red":
		red_alive -= 1
	else:
		blue_alive -= 1
	var is_first_kill = kill_log.is_empty()
	kill_log.append({
		"tick": _frame_count_ref.call(),
		"victim_id": victim_id,
		"victim_team": victim_team,
	})
	# 首次击杀：通知外部（bootstrap 转发给 ux_observer 截图）
	if is_first_kill and _first_kill_cb.is_valid():
		_first_kill_cb.call()


func on_unit_produced(unit_type: String, team: String) -> void:
	## 由 bootstrap 连接 game_world.unit_produced 信号后转发过来
	production_occurred = true
	if unit_type == "archer" and team == "red":
		archer_produced = true
	if team == "red":
		red_alive += 1
	else:
		blue_alive += 1


func tick() -> void:
	## 每帧由 bootstrap._physics_process 调用（headless 模式）
	clean_dead_units()
	_check_worker_states()
	_check_blue_economy()


func clean_dead_units() -> void:
	## 清理 _units 数组中已释放的节点引用（窗口/headless 共用）
	var i = _units.size() - 1
	while i >= 0:
		if not is_instance_valid(_units[i]):
			_units.remove_at(i)
		i -= 1


func _check_worker_states() -> void:
	## 检查是否有工人进入过 harvesting 状态
	if worker_harvesting_seen:
		return
	for u in _units:
		if is_instance_valid(u) and u.unit_type == "worker":
			var state = str(u.ai_state)
			if state == "harvesting" or state == "returning" or state == "delivering":
				worker_harvesting_seen = true
				return


func _check_blue_economy() -> void:
	## 检测蓝方是否完成过至少一次采集交付循环
	if blue_crystal_delivered or not is_instance_valid(_hq_blue):
		return
	if _hq_blue.crystal > 50:
		# 水晶回升 = 蓝方工人完成了交付
		blue_crystal_delivered = true
