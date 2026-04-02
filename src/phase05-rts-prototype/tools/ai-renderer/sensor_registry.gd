extends RefCounted

## SensorRegistry — 采集注册表
## v3: 支持按 group 独立配置采样率。
##
## 设计：每个实体注册时指定 group（默认 "units"）。
## tick() 按各 group 的采样率刷新对应实体的缓存数据（_cached_data）。
## 任意 group 触发采样时，输出包含所有已缓存实体的完整 snapshot——
## 这样高频 group（units:10帧）输出时也能带上低频 group（economy:60帧）的最新数据。
## 旧 sample_rate 字段作为未配置 group 的默认采样率，向后兼容。

var _entries: Dictionary = {}       # { entity_id: { node, fields, group } }
var _ref_holders: Dictionary = {}   # { name: Callable -> Array }
var _sample_rate: int = 60          # 未配置 group 的默认采样率
var _group_rates: Dictionary = {}   # { group_name: rate }
var _frame_count: int = 0
var _cached_data: Dictionary = {}   # { entity_id: { field: value } }  最新采样值
var _last_snapshot: Dictionary = {}
var _last_health: Dictionary = {}


func configure(sample_rate: int) -> void:
	## 设置默认采样率（向后兼容，作为未配置 group 的 fallback）
	_sample_rate = sample_rate


func configure_groups(groups: Dictionary) -> void:
	## 设置各 group 的采样率。示例：{"economy": 60, "units": 10}
	_group_rates = groups.duplicate()


func register(entity_id: String, node: Node, fields: Array, group: String = "units") -> void:
	_entries[entity_id] = {"node": node, "fields": fields, "group": group}


func unregister(entity_id: String) -> void:
	_entries.erase(entity_id)
	_cached_data.erase(entity_id)


func register_ref_holder(name: String, getter: Callable) -> void:
	_ref_holders[name] = getter


func clear() -> void:
	_entries.clear()
	_ref_holders.clear()
	_cached_data.clear()


func tick() -> void:
	_frame_count += 1
	var any_fired = false
	var to_remove: Array = []

	for eid in _entries:
		var entry = _entries[eid]
		var group = entry.get("group", "units")
		var rate = int(_group_rates.get(group, _sample_rate))
		# 第一帧（rate=0 对任何整数取模都满足）或到达采样间隔时采集
		var is_first_sample = (_frame_count == 1)
		if not is_first_sample and _frame_count % rate != 0:
			continue
		var node = entry["node"]
		if not is_instance_valid(node):
			to_remove.append(eid)
			continue
		var data = {}
		for field in entry["fields"]:
			data[field] = node.get(field)
		_cached_data[eid] = data
		any_fired = true

	for eid in to_remove:
		_entries.erase(eid)
		_cached_data.erase(eid)

	if any_fired:
		_last_snapshot = _build_snapshot()
		_last_health = check_ref_holders()


func _build_snapshot() -> Dictionary:
	## 从 _cached_data 构建 snapshot，包含所有已采样过的实体
	var result = {"tick": _frame_count, "entities": {}}
	for eid in _cached_data:
		result["entities"][eid] = _cached_data[eid].duplicate()
	return result


func collect() -> Dictionary:
	## 立即对所有实体采样并返回（向后兼容，不写入 _last_snapshot）
	var result = {"tick": _frame_count, "entities": {}}
	var to_remove: Array = []
	for eid in _entries:
		var entry = _entries[eid]
		var node = entry["node"]
		if not is_instance_valid(node):
			to_remove.append(eid)
			continue
		var data = {}
		for field in entry["fields"]:
			data[field] = node.get(field)
		result["entities"][eid] = data
	for eid in to_remove:
		_entries.erase(eid)
		_cached_data.erase(eid)
	return result


func check_ref_holders() -> Dictionary:
	var result = {"holders": {}, "total_invalid": 0}
	for name in _ref_holders:
		var refs = _ref_holders[name].call()
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
