extends RefCounted

## SensorRegistry — 采集注册表
## 游戏对象注册后，registry 按配置频率采集状态数据。
## v2: supports ref_holder tracking for lifecycle integrity checks.

var _entries: Dictionary = {}  # { entity_id: { node, fields } }
var _ref_holders: Dictionary = {}  # { name: Callable returning Array }
var _sample_rate: int = 60     # 采集间隔帧数
var _frame_count: int = 0
var _last_snapshot: Dictionary = {}
var _last_health: Dictionary = {}  # ref_holder health check results


func configure(sample_rate: int) -> void:
	_sample_rate = sample_rate


func register(entity_id: String, node: Node, fields: Array) -> void:
	_entries[entity_id] = {"node": node, "fields": fields}


func unregister(entity_id: String) -> void:
	_entries.erase(entity_id)


func register_ref_holder(name: String, getter: Callable) -> void:
	## Register a system that holds node references (for lifecycle integrity checks).
	## getter should return an Array of node references.
	_ref_holders[name] = getter


func clear() -> void:
	_entries.clear()
	_ref_holders.clear()


func tick() -> void:
	_frame_count += 1
	if _frame_count % _sample_rate != 0:
		return
	_last_snapshot = collect()
	_last_health = check_ref_holders()


func collect() -> Dictionary:
	var result = {"tick": _frame_count, "entities": {}}
	for eid in _entries:
		var entry = _entries[eid]
		var node = entry["node"]
		var fields = entry["fields"]
		if not is_instance_valid(node):
			_entries.erase(eid)
			continue
		var data = {}
		for field in fields:
			data[field] = node.get(field)
		result["entities"][eid] = data
	return result


func check_ref_holders() -> Dictionary:
	## Check all registered ref_holders for invalid (freed) node references.
	var result = {"holders": {}, "total_invalid": 0}
	for name in _ref_holders:
		var getter = _ref_holders[name]
		var refs = getter.call()
		var invalid_count = 0
		var total_count = 0
		if refs is Array:
			total_count = refs.size()
			for ref in refs:
				if not is_instance_valid(ref):
					invalid_count += 1
		result["holders"][name] = {"total": total_count, "invalid": invalid_count}
		result["total_invalid"] += invalid_count
	return result


func get_count() -> int:
	return _entries.size()


func get_snapshot() -> Dictionary:
	return _last_snapshot


func get_health() -> Dictionary:
	return _last_health


func clear_snapshot() -> void:
	_last_snapshot = {}
