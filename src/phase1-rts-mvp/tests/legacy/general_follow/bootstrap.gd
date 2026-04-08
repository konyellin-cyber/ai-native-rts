extends "res://tests/gameplay_bootstrap.gd"

## general_follow bootstrap — 15B.12
## 场景：将领从 x=200 带领 30 个哑兵移动到 x=700。
## 断言：900 帧内，哑兵整体质心跟将领方向移动（质心 x 坐标增加 ≥ 300 单位）。

var _general: CharacterBody3D = null
var _dummy_soldiers: Array = []
const _MOVE_TARGET = Vector3(700.0, 0.0, 500.0)
const _MIN_CENTROID_MOVE = 300.0   ## 质心至少在 x 方向移动 300 单位
var _initial_centroid_x: float = 0.0


func _post_spawn() -> void:
	if _units.size() > 0:
		_general = _units[0]
		## 收集哑兵列表（来自 Node3D children，类型为 DummySoldier）
		_collect_dummy_soldiers()
		## 延迟 1 帧记录初始质心（确保哑兵已完成 _ready）
		_initial_centroid_x = _compute_centroid_x()
		## 发出移动指令
		_general.move_to(_MOVE_TARGET)
		print("[FOLLOW] general start=%.1f, dummies=%d, initial_centroid_x=%.1f" % [
			_general.global_position.x, _dummy_soldiers.size(), _initial_centroid_x
		])


func _register_assertions() -> void:
	_renderer.add_assertion("centroid_follows_general", _assert_centroid_follows)
	_renderer.get_calibrator().set_run_only(["centroid_follows_general"])


func _collect_dummy_soldiers() -> void:
	for child in get_children():
		if child.has_method("freeze_at_current"):
			_dummy_soldiers.append(child)


func _compute_centroid_x() -> float:
	if _dummy_soldiers.is_empty():
		return 0.0
	var sum_x: float = 0.0
	var count: int = 0
	for s in _dummy_soldiers:
		if is_instance_valid(s):
			sum_x += s.global_position.x
			count += 1
	return sum_x / float(count) if count > 0 else 0.0


func _assert_centroid_follows() -> Dictionary:
	if _general == null or not is_instance_valid(_general):
		return {"status": "fail", "detail": "general invalid"}
	if _dummy_soldiers.is_empty():
		return {"status": "fail", "detail": "no dummy soldiers found"}
	var current_cx = _compute_centroid_x()
	var delta_cx = current_cx - _initial_centroid_x
	if delta_cx >= _MIN_CENTROID_MOVE:
		return {"status": "pass", "detail": "centroid moved +%.1f on x-axis" % delta_cx}
	return {"status": "pending", "detail": "centroid delta_x=%.1f / need %.1f" % [delta_cx, _MIN_CENTROID_MOVE]}
