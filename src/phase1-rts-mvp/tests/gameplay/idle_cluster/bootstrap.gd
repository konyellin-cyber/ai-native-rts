extends "res://tests/gameplay_bootstrap.gd"

## idle_cluster bootstrap
## 场景：将领不发任何移动指令，静止 N 帧。
## 断言：所有哑兵都在将领纵队初始范围内（距离将领 < 将领停止后预期的最大队列长度），
## 验证 idle 时不发生物理爆炸大范围散布。
## （不用绝对初始位置比较，因为 NavigationServer 会对静止 RigidBody3D 做微小修正）

var _general: CharacterBody3D = null
var _dummy_soldiers: Array = []

const _CHECK_FRAME = 200
## 30个哑兵纵队理论最大长度：15排 × 26.4间距 × 2 = 约800（加宽裕量到 1000）
const _MAX_DIST_FROM_GENERAL = 1000.0
## 真正物理爆炸会把哑兵弹到数千单位外，所以 1000 是安全上限
## 正常纵队最长约 720 单位，1000 有足够宽裕


func _post_spawn() -> void:
	if _units.size() > 0:
		_general = _units[0]
		_collect_dummy_soldiers()
		print("[IDLE_CLUSTER] general pos=%s, dummies=%d, NO move issued" % [
			str(_general.global_position), _dummy_soldiers.size()
		])


func _register_assertions() -> void:
	_renderer.add_assertion("dummies_stay_at_initial_slot_when_idle", _assert_no_explosion)
	_renderer.get_calibrator().set_run_only(["dummies_stay_at_initial_slot_when_idle"])


func _collect_dummy_soldiers() -> void:
	for child in get_children():
		if child.has_method("freeze_at_current"):
			_dummy_soldiers.append(child)


func _assert_no_explosion() -> Dictionary:
	if _general == null or not is_instance_valid(_general):
		return {"status": "fail", "detail": "general invalid"}
	if _dummy_soldiers.is_empty():
		return {"status": "fail", "detail": "no dummy soldiers found"}

	if _frame_count < _CHECK_FRAME:
		return {"status": "pending", "detail": "waiting frame %d (now %d)" % [_CHECK_FRAME, _frame_count]}

	var gen_pos = _general.global_position
	var max_dist: float = 0.0
	var worst_idx: int = -1

	for i in range(_dummy_soldiers.size()):
		var s = _dummy_soldiers[i]
		if not is_instance_valid(s):
			continue
		var d = s.global_position.distance_to(gen_pos)
		if d > max_dist:
			max_dist = d
			worst_idx = i

	if max_dist > _MAX_DIST_FROM_GENERAL:
		return {"status": "fail", "detail": "Dummy_%d flew %.1f > %.1f from general (physics explosion)" % [
			worst_idx, max_dist, _MAX_DIST_FROM_GENERAL
		]}

	return {"status": "pass", "detail": "max_dist_from_general=%.1f (all %d dummies within %.0f)" % [
		max_dist, _dummy_soldiers.size(), _MAX_DIST_FROM_GENERAL
	]}
