extends Node

## FaultInjector — 故障注入器
## 职责：按 config.fault_injection 列表，在指定帧对单位执行 freeze_nav / restore_all 操作。
## 为什么独立成 Node：将测试桩从生产代码路径中完全隔离，bootstrap 不配置时不挂载。

signal fault_injected(unit_id: int, frame: int)
signal fault_restored(frame: int)

## 只读状态（供 AssertionSetup 读取）
var injected: bool = false
var restored: bool = false
var frozen_units: Dictionary = {}  ## { unit_id: { original_speed, original_target } }

var _injections: Array = []        ## config.fault_injection 列表的副本（已排序）
var _units_getter: Callable        ## 返回 Array[Node] 的回调


func setup(units_getter: Callable, fi_config: Array) -> void:
	## units_getter: 每次调用返回当前存活单位列表（引用 game_world.units）
	_units_getter = units_getter
	_injections = fi_config.duplicate()
	_injections.sort_custom(func(a, b): return a.get("frame", 0) < b.get("frame", 0))
	print("[FAULT] Loaded %d fault injection events" % _injections.size())


func tick(frame: int) -> void:
	## 每帧由 bootstrap._physics_process 调用
	for fi in _injections:
		if int(fi.get("frame", 0)) > frame:
			break
		if fi.get("done", false):
			continue
		match fi.get("action", ""):
			"freeze_nav":
				var uid = int(fi.get("unit_id", 0))
				_freeze_unit_nav(uid)
				fi["done"] = true
				injected = true
				print("[FAULT] frame=%d Froze navigation for unit %d" % [frame, uid])
				fault_injected.emit(uid, frame)
			"restore_all":
				_restore_all_units()
				fi["done"] = true
				restored = true
				print("[FAULT] frame=%d Restored all frozen units" % frame)
				fault_restored.emit(frame)


func get_injections() -> Array:
	return _injections


# ── 故障操作 ────────────────────────────────────────────────────────

func _freeze_unit_nav(unit_id: int) -> void:
	var units = _units_getter.call()
	for u in units:
		if not is_instance_valid(u):
			continue
		if u.unit_id == unit_id:
			var agent = u.get_node_or_null("NavAgent")
			if agent:
				var orig_target = agent.target_position
				frozen_units[unit_id] = {
					"original_speed": u.move_speed,
					"original_target": orig_target,
				}
				agent.target_position = u.global_position
				u.move_speed = 0.0
			break


func _restore_all_units() -> void:
	var units = _units_getter.call()
	for uid in frozen_units:
		var saved = frozen_units[uid]
		for u in units:
			if not is_instance_valid(u):
				continue
			if u.unit_id == uid:
				u.move_speed = saved["original_speed"]
				var agent = u.get_node_or_null("NavAgent")
				if agent and saved["original_target"] != u.global_position:
					agent.target_position = saved["original_target"]
				break
	frozen_units.clear()
