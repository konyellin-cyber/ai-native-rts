extends "res://tests/gameplay_bootstrap.gd"

## general_marching bootstrap — 16A.9
## 场景：将领从 x=200 移动到 x=800（z=600 保持不变，纯横向行军）。
## 断言：
##   1. 哑兵质心 x 坐标增加 ≥ 300 单位（跟随将领行进方向）
##   2. 最前排哑兵（_soldier_index=0）与将领距离 < 路径点间距 × 5（未严重掉队）

var _general: CharacterBody3D = null
var _dummy_soldiers: Array = []

const _MOVE_TARGET = Vector3(800.0, 0.0, 600.0)
const _MIN_CENTROID_MOVE_X = 300.0
const _MAX_FRONT_DISTANCE = 320.0   ## 最前排哑兵允许的最大掉队距离（Phase 17：力驱动有启动延迟，放宽阈值）


func _post_spawn() -> void:
	if _units.size() > 0:
		_general = _units[0]
		_collect_dummy_soldiers()
		_general.move_to(_MOVE_TARGET)
		print("[MARCHING] general start=%.1f, dummies=%d" % [
			_general.global_position.x, _dummy_soldiers.size()
		])


func _register_assertions() -> void:
	_renderer.add_assertion("centroid_marches_with_general", _assert_centroid_marches)
	_renderer.get_calibrator().set_run_only(["centroid_marches_with_general"])


func _collect_dummy_soldiers() -> void:
	for child in get_children():
		if child.has_method("freeze_at_current"):
			_dummy_soldiers.append(child)


func _assert_centroid_marches() -> Dictionary:
	if _general == null or not is_instance_valid(_general):
		return {"status": "fail", "detail": "general invalid"}
	if _dummy_soldiers.is_empty():
		return {"status": "fail", "detail": "no dummy soldiers found"}

	## 计算哑兵质心 x
	var sum_x: float = 0.0
	var count: int = 0
	var front_soldier: Node = null
	for s in _dummy_soldiers:
		if is_instance_valid(s):
			sum_x += s.global_position.x
			count += 1
			## 找编号 0 的哑兵（最前排）
			if s.name == "Dummy_0":
				front_soldier = s

	if count == 0:
		return {"status": "fail", "detail": "all dummies invalid"}

	var centroid_x = sum_x / float(count)
	var gen_x = _general.global_position.x

	## 断言1：质心跟随将领方向
	if centroid_x - 200.0 < _MIN_CENTROID_MOVE_X:
		return {"status": "pending", "detail": "centroid_x=%.1f, need ≥ %.1f" % [
			centroid_x, 200.0 + _MIN_CENTROID_MOVE_X
		]}

	## 断言2：最前排不严重掉队
	if front_soldier != null:
		var front_dist = front_soldier.global_position.distance_to(_general.global_position)
		if front_dist > _MAX_FRONT_DISTANCE:
			return {"status": "fail", "detail": "front soldier lagging %.1f > %.1f" % [
				front_dist, _MAX_FRONT_DISTANCE
			]}

	return {"status": "pass", "detail": "centroid_x=%.1f, general_x=%.1f" % [centroid_x, gen_x]}
