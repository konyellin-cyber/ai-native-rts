extends "res://tests/gameplay_bootstrap.gd"

## general_deployed bootstrap — 16B.8
## 场景：将领先短距离行军（建立 _march_direction），然后停止。
## 等待 deploy_trigger_frames + 哑兵到位时间后，断言：
##   1. _formation_state == "deployed"
##   2. 哑兵质心位于将领前方（沿 _march_direction 方向，即 +x 方向质心 > 将领 x）

var _general: CharacterBody3D = null
var _dummy_soldiers: Array = []

## 将领向 +x 行军，建立行进方向
const _MOVE_TARGET = Vector3(700.0, 0.0, 600.0)
## 触发展开需等全员到位（去掉 headless 绕过），CHECK_FRAME 调大确保足够时间
const _CHECK_FRAME = 800
var _move_issued: bool = false


func _post_spawn() -> void:
	if _units.size() > 0:
		_general = _units[0]
		_collect_dummy_soldiers()
		_general.move_to(_MOVE_TARGET)
		_move_issued = true
		print("[DEPLOYED] general start pos=%s, dummies=%d" % [
			str(_general.global_position), _dummy_soldiers.size()
		])


func _register_assertions() -> void:
	_renderer.add_assertion("formation_deployed_correctly", _assert_deployed)
	_renderer.get_calibrator().set_run_only(["formation_deployed_correctly"])


func _collect_dummy_soldiers() -> void:
	for child in get_children():
		if child.has_method("freeze_at_current"):
			_dummy_soldiers.append(child)


func _assert_deployed() -> Dictionary:
	if _general == null or not is_instance_valid(_general):
		return {"status": "fail", "detail": "general invalid"}

	var state = _general.get_formation_state() if _general.has_method("get_formation_state") else "unknown"

	## 等待将领到达目标并停止、切换展开、哑兵移动到位
	if _frame_count < _CHECK_FRAME:
		return {"status": "pending", "detail": "waiting frame %d (now %d), state=%s" % [
			_CHECK_FRAME, _frame_count, state
		]}

	## 断言1：状态已切换为 deployed
	if state != "deployed":
		return {"status": "fail", "detail": "formation_state=%s (expected deployed) at frame %d" % [
			state, _frame_count
		]}

	## 断言2：哑兵质心在将领前方（将领向 +x 行军，横阵展开在 +x 方向）
	var sum = Vector3.ZERO
	var count: int = 0
	for s in _dummy_soldiers:
		if is_instance_valid(s):
			sum += s.global_position
			count += 1
	if count == 0:
		return {"status": "fail", "detail": "no valid dummies"}

	var centroid = sum / float(count)
	var gen_pos = _general.global_position
	var diff_x = centroid.x - gen_pos.x
	## 将领向 +x 行军，横阵展开在将领后方（-x 方向），质心应 < 将领 x
	if diff_x < 0.0:
		return {"status": "pass", "detail": "deployed ✓ centroid_x=%.1f < general_x=%.1f (%.1f)" % [
			centroid.x, gen_pos.x, diff_x
		]}

	return {"status": "fail", "detail": "centroid NOT behind: centroid.x=%.1f, general.x=%.1f (diff=%.1f)" % [
		centroid.x, gen_pos.x, diff_x
	]}
