extends RefCounted
class_name AssertionSetup

## Phase 1 AssertionSetup — 断言配置集中地
## 职责：将所有 Calibrator 断言注册到 renderer。
## 纯配置对象，无游戏逻辑，无节点引用。
## 5B 重构：原来依赖 _world 节点引用的 4 条断言改为读 snapshot 字典，
##   彻底与具体节点对象解耦——改 Formatter 格式不影响断言，改断言不影响输出格式。
## 5F 重构：_fault_state 字典改为持有 FaultInjector 引用，断言直接读其只读属性。

var _renderer: RefCounted        ## AIRenderer（用于 get_snapshot 和 add_assertion）
var _lifecycle: RefCounted        ## UnitLifecycleManager（只读属性）
var _sim_player: RefCounted       ## 可为 null
var _fault_injector: Node         ## FaultInjector，可为 null（未配置故障注入时）
var _expected_mineral_count: int  ## setup 时从 world.mineral_nodes.size() 传入
var _red_crystal_max: int = 0     ## 历史最大红方 crystal（跨快照追踪，避免采样窗口遗漏）
var _obstacles: Array = []        ## 障碍物列表，来自 config.obstacles，用于穿越检测


func setup(
	renderer: RefCounted,
	lifecycle: RefCounted,
	sim_player: RefCounted,
	fault_injector: Node,
	expected_mineral_count: int,
	obstacles: Array = []
) -> void:
	_renderer = renderer
	_lifecycle = lifecycle
	_sim_player = sim_player
	_fault_injector = fault_injector
	_expected_mineral_count = expected_mineral_count
	_obstacles = obstacles


func register_all() -> void:
	## 注册所有断言到 Calibrator，由 bootstrap 在 headless 模式下调用一次
	_renderer.add_assertion("hq_exists",         _assert_hq_exists)
	_renderer.add_assertion("mineral_exists",    _assert_mineral_exists)
	_renderer.add_assertion("worker_exists",     _assert_worker_exists)
	_renderer.add_assertion("worker_cycle",      _assert_worker_cycle)
	_renderer.add_assertion("production_flow",   _assert_production_flow)
	_renderer.add_assertion("economy_positive",  _assert_economy_positive)
	_renderer.add_assertion("ai_economy",        _assert_ai_economy)
	_renderer.add_assertion("ai_produces",       _assert_ai_produces)
	_renderer.add_assertion("battle_resolution", _assert_battle_resolution)
	_renderer.add_assertion("no_obstacle_penetration", _assert_no_obstacle_penetration)
	_renderer.add_assertion("archer_produced",   _assert_archer_produced)
	if _sim_player:
		_renderer.add_assertion("interaction_chain", _assert_interaction_chain)
	if _fault_injector and not _fault_injector.get_injections().is_empty():
		_renderer.add_assertion("behavior_health", _assert_behavior_health)


# ─── 工具：获取快照实体表 ──────────────────────────────────────────
# snapshot 只在 sample_rate 帧更新，其他帧为 {}，返回 null 表示"等下次采样"

func _entities() -> Variant:
	## 返回 snapshot 的 entities 字典；快照为空时返回 null（调用方返回 pending）
	var snap = _renderer.get_snapshot()
	if snap.is_empty():
		return null
	return snap.get("entities", {})


# ─── 断言：基于 snapshot 字典（不依赖节点引用）──────────────────────

func _assert_hq_exists() -> Dictionary:
	## 通过 snapshot 确认 HQ_red / HQ_blue 均已注册且有数据
	## 为什么用 snapshot：避免直接持有节点引用，Formatter 格式变化不影响本断言
	var ents = _entities()
	if ents == null:
		return {"status": "pending", "detail": "waiting for snapshot"}
	var has_red = ents.has("HQ_red")
	var has_blue = ents.has("HQ_blue")
	if has_red and has_blue:
		return {"status": "pass", "detail": "both HQs exist"}
	var missing = []
	if not has_red: missing.append("HQ_red")
	if not has_blue: missing.append("HQ_blue")
	return {"status": "fail", "detail": "HQ missing: %s" % ", ".join(missing)}


func _assert_mineral_exists() -> Dictionary:
	## 通过 snapshot 统计 Mine_ 前缀条目数量，与初始矿点数比较
	## 为什么用 snapshot：矿点是静态实体，注册后不应消失
	var ents = _entities()
	if ents == null:
		return {"status": "pending", "detail": "waiting for snapshot"}
	var count = 0
	for key in ents:
		if key.begins_with("Mine_"):
			count += 1
	if count >= _expected_mineral_count:
		return {"status": "pass", "detail": "%d minerals in snapshot" % count}
	return {"status": "fail", "detail": "%d/%d minerals in snapshot" % [count, _expected_mineral_count]}


func _assert_worker_exists() -> Dictionary:
	## 通过 snapshot 统计有 ai_state 字段的实体（工人/战士），应 >= 6
	## 为什么用 snapshot：实体必须注册到 Sensor 才能被 AI Renderer 观测
	var ents = _entities()
	if ents == null:
		return {"status": "pending", "detail": "waiting for snapshot"}
	var alive = 0
	for key in ents:
		if ents[key].has("ai_state"):
			alive += 1
	if alive >= 6:
		return {"status": "pass", "detail": "%d units in snapshot" % alive}
	return {"status": "fail", "detail": "only %d units in snapshot (expect >=6)" % alive}


func _assert_economy_positive() -> Dictionary:
	## 验证红方经济启动（晶体历史最大值 >= 210 = 初始 200 + 一次完整交付 10）
	## 用历史最大值追踪，避免生产消费导致快照采样时 crystal 已下降的误判
	var ents = _entities()
	if ents == null:
		return {"status": "pending", "detail": "waiting for snapshot"}
	var hq_data = ents.get("HQ_red", {})
	if hq_data.is_empty():
		return {"status": "pending", "detail": "HQ_red not in snapshot yet"}
	var crystal = int(hq_data.get("crystal", 0))
	if crystal > _red_crystal_max:
		_red_crystal_max = crystal
	if _red_crystal_max >= 210:
		return {"status": "pass", "detail": "red crystal_max=%d (economy started)" % _red_crystal_max}
	return {"status": "pending", "detail": "red crystal=%d max=%d, waiting for first delivery" % [crystal, _red_crystal_max]}


# ─── 断言：基于 lifecycle 结构化数据（已是纯数据，无需改动）────────

func _assert_worker_cycle() -> Dictionary:
	if _lifecycle.worker_harvesting_seen:
		return {"status": "pass", "detail": "worker reached harvesting state"}
	return {"status": "pending", "detail": "waiting for worker to start harvesting"}


func _assert_production_flow() -> Dictionary:
	if _lifecycle.production_occurred:
		return {"status": "pass", "detail": "production queue produced units"}
	return {"status": "pending", "detail": "waiting for production"}


func _assert_ai_economy() -> Dictionary:
	if _lifecycle.blue_crystal_delivered:
		return {"status": "pass", "detail": "blue workers delivered resources"}
	return {"status": "pending", "detail": "waiting for blue worker delivery"}


func _assert_ai_produces() -> Dictionary:
	var blue_alive = _lifecycle.blue_alive
	if blue_alive > 3:
		return {"status": "pass", "detail": "blue alive=%d (>3)" % blue_alive}
	return {"status": "pending", "detail": "blue alive=%d, waiting for AI production" % blue_alive}


func _assert_battle_resolution() -> Dictionary:
	if _lifecycle.kill_log.size() > 0:
		return {"status": "pass", "detail": "kills=%d" % _lifecycle.kill_log.size()}
	return {"status": "pending", "detail": "no kills yet"}


# ─── 断言：SimulatedPlayer / FaultInjector ──────────────────────────

func _assert_interaction_chain() -> Dictionary:
	if not _sim_player:
		return {"status": "pass", "detail": "no SimulatedPlayer"}
	var summary = _sim_player.get_interaction_summary()
	var total = summary.get("total_actions", 0)
	if total == 0:
		return {"status": "pending", "detail": "no actions executed yet"}
	var successful = summary.get("successful", 0)
	var failed = summary.get("failed", 0)
	var signals = summary.get("signals_received", 0)
	if failed > 0:
		return {"status": "fail", "detail": "%d/%d actions failed, signals=%d" % [failed, total, signals]}
	if successful > 0:
		return {"status": "pass", "detail": "%d actions ok, signals=%d" % [successful, signals]}
	return {"status": "pending", "detail": "actions=%d signals=%d" % [total, signals]}


func _assert_behavior_health() -> Dictionary:
	## 直接读 FaultInjector 的只读属性，不再依赖 bootstrap 维护的 fault_state 字典
	if not _fault_injector:
		return {"status": "pass", "detail": "no fault injector"}
	if not _fault_injector.injected:
		return {"status": "pending", "detail": "waiting for fault injection"}
	if _fault_injector.restored and _fault_injector.frozen_units.is_empty():
		return {"status": "pass", "detail": "fault injected and restored successfully"}
	elif _fault_injector.restored:
		return {"status": "fail", "detail": "restore failed: %d units still frozen" % _fault_injector.frozen_units.size()}
	return {"status": "pending", "detail": "fault injected, waiting for restore"}


func _assert_no_obstacle_penetration() -> Dictionary:
	## 检查任意单位的位置是否落入某障碍物的 XZ bbox 内
	var ents = _entities()
	if ents == null:
		return {"status": "pending", "detail": "waiting for snapshot"}
	for eid in ents:
		var data = ents[eid]
		if not data.has("ai_state"):
			continue  # 只检查单位
		var pos = data.get("global_position")
		if pos == null:
			continue
		var px: float
		var pz: float
		if pos is Vector3:
			px = float(pos.x)
			pz = float(pos.z)
		else:
			px = float(pos.get("x", 0))
			pz = float(pos.get("y", 0))  # snapshot 字典中 z 可能用 "y" 键（2D 约定）
		for obs in _obstacles:
			var ox = float(obs.get("x", 0))
			var oz = float(obs.get("y", 0))  # config 用 y 表示 Z
			var ow = float(obs.get("w", 0))
			var oh = float(obs.get("h", 0))
			if px >= ox and px <= ox + ow and pz >= oz and pz <= oz + oh:
				return {"status": "fail",
					"detail": "%s at (%.0f,%.0f) inside obstacle (%.0f,%.0f)+(%.0f,%.0f)" % [
						eid, px, pz, ox, oz, ow, oh]}
	return {"status": "pass", "detail": "no units inside obstacle bboxes"}


func _assert_archer_produced() -> Dictionary:
	## 验证玩家（红方）HQ 生产队列曾生产出 archer 单位
	## 依赖：lifecycle.archer_produced 在 on_unit_produced("archer","red") 时置 true
	if _lifecycle.archer_produced:
		return {"status": "pass", "detail": "red archer produced"}
	return {"status": "pending", "detail": "waiting for red archer production"}
