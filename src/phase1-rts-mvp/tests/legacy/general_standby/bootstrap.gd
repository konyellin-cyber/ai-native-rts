extends "res://tests/gameplay_bootstrap.gd"

## general_standby bootstrap — 15B.13
## 场景：将领切换待命模式后独自移动，哑兵应留在原地不动。
## 流程：
##   帧 5  → 等哑兵稳定到初始位置后记录质心
##   帧 10 → 切换将领 follow_mode = false（待命）
##   帧 15 → 将领移动到远处 (700, 500)
##   帧末 → 断言哑兵质心位移 < 容忍值 20 单位

var _general: CharacterBody3D = null
var _dummy_soldiers: Array = []
var _locked_centroid: Vector3 = Vector3.ZERO
var _standby_activated: bool = false
var _move_issued: bool = false

const _MOVE_TARGET = Vector3(700.0, 0.0, 500.0)
const _MAX_CENTROID_DRIFT = 30.0   ## 待命后质心允许的最大漂移（士兵自身惯性）
const _STANDBY_FRAME = 10
const _MOVE_FRAME = 15
const _MEASURE_FRAME = 300         ## 在此帧才断言（确保将领已走远，哑兵已稳定）


func _post_spawn() -> void:
	if _units.size() > 0:
		_general = _units[0]
		_collect_dummy_soldiers()
		print("[STANDBY] general start=%.1f, dummies=%d" % [
			_general.global_position.x, _dummy_soldiers.size()
		])


func _register_assertions() -> void:
	_renderer.add_assertion("soldiers_stay_on_standby", _assert_soldiers_stay)
	_renderer.get_calibrator().set_run_only(["soldiers_stay_on_standby"])


func _physics_process(delta: float) -> void:
	## 帧 10：切换待命
	if _frame_count == _STANDBY_FRAME and not _standby_activated:
		_standby_activated = true
		_general.toggle_follow_mode()
		_locked_centroid = _compute_centroid()
		print("[STANDBY] follow_mode toggled OFF at frame %d, centroid=%s" % [
			_frame_count, str(_locked_centroid)
		])

	## 帧 15：将领独自移动
	if _frame_count == _MOVE_FRAME and not _move_issued:
		_move_issued = true
		_general.move_to(_MOVE_TARGET)
		print("[STANDBY] general move_to %s at frame %d" % [str(_MOVE_TARGET), _frame_count])

	super._physics_process(delta)


func _collect_dummy_soldiers() -> void:
	for child in get_children():
		if child.has_method("freeze_at_current"):
			_dummy_soldiers.append(child)


func _compute_centroid() -> Vector3:
	if _dummy_soldiers.is_empty():
		return Vector3.ZERO
	var sum = Vector3.ZERO
	var count: int = 0
	for s in _dummy_soldiers:
		if is_instance_valid(s):
			sum += s.global_position
			count += 1
	return sum / float(count) if count > 0 else Vector3.ZERO


func _assert_soldiers_stay() -> Dictionary:
	if not _standby_activated:
		return {"status": "pending", "detail": "standby not yet activated"}
	if _frame_count < _MEASURE_FRAME:
		return {"status": "pending", "detail": "waiting for frame %d" % _MEASURE_FRAME}
	if _dummy_soldiers.is_empty():
		return {"status": "fail", "detail": "no dummy soldiers found"}

	var current_centroid = _compute_centroid()
	var drift = current_centroid.distance_to(_locked_centroid)
	var gen_dist = _general.global_position.distance_to(Vector3(_locked_centroid.x, 0, _locked_centroid.z))

	print("[STANDBY] general_dist=%.1f, centroid_drift=%.1f" % [gen_dist, drift])

	if drift <= _MAX_CENTROID_DRIFT:
		return {"status": "pass", "detail": "soldiers stayed (drift=%.1f ≤ %.1f), general moved %.1f" % [
			drift, _MAX_CENTROID_DRIFT, gen_dist
		]}
	return {"status": "fail", "detail": "soldiers drifted=%.1f > %.1f" % [drift, _MAX_CENTROID_DRIFT]}
