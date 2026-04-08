extends "res://tests/gameplay_bootstrap.gd"

## formation_switch bootstrap — 16C.4
## 场景：将领完成行军→展开→再行军两次循环，断言状态切换正确。
##
## 时间轴：
##   帧   0 → 将领移动到 P1（行军）
##   帧 150 → 将领到达并停止，等 deployed
##   帧 200 → 断言 state==deployed（第一次）
##   帧 201 → 将领移动到 P2（切回 marching）
##   帧 210 → 断言 state==marching
##   帧 400 → 将领到达 P2 并停止，等 deployed
##   帧 480 → 断言 state==deployed（第二次）→ PASS

var _general: CharacterBody3D = null

const _P1 = Vector3(700.0, 0.0, 600.0)
const _P2 = Vector3(300.0, 0.0, 600.0)

## 记录各阶段是否通过
var _phase_results: Array = [false, false, false]  ## [deployed_1, marching, deployed_2]
var _move_to_p2_issued: bool = false

const _CHECK_DEPLOYED_1 = 200
const _CHECK_MARCHING = 220
const _ISSUE_P2_FRAME = 201
const _CHECK_DEPLOYED_2 = 480


func _post_spawn() -> void:
	if _units.size() > 0:
		_general = _units[0]
		_general.move_to(_P1)
		print("[SWITCH] general start, move to P1=%s" % str(_P1))


func _register_assertions() -> void:
	_renderer.add_assertion("formation_switches_correctly", _assert_switch)
	_renderer.get_calibrator().set_run_only(["formation_switches_correctly"])


func _physics_process(delta: float) -> void:
	## 帧 201：将领移动到 P2，触发 marching
	if _frame_count == _ISSUE_P2_FRAME and not _move_to_p2_issued:
		_move_to_p2_issued = true
		_general.move_to(_P2)
		print("[SWITCH] frame %d: move to P2=%s" % [_frame_count, str(_P2)])

	super._physics_process(delta)


func _assert_switch() -> Dictionary:
	if _general == null or not is_instance_valid(_general):
		return {"status": "fail", "detail": "general invalid"}

	var state = _general.get_formation_state() if _general.has_method("get_formation_state") else "unknown"

	## 阶段 1：deployed 第一次
	if _frame_count >= _CHECK_DEPLOYED_1 and not _phase_results[0]:
		if state == "deployed":
			_phase_results[0] = true
			print("[SWITCH] frame %d: deployed_1 ✓" % _frame_count)
		else:
			return {"status": "fail", "detail": "frame %d: expected deployed, got %s" % [_frame_count, state]}

	## 阶段 2：切回 marching
	if _frame_count >= _CHECK_MARCHING and _phase_results[0] and not _phase_results[1]:
		if state == "marching":
			_phase_results[1] = true
			print("[SWITCH] frame %d: marching ✓" % _frame_count)
		elif _frame_count > _CHECK_MARCHING + 10:
			return {"status": "fail", "detail": "frame %d: expected marching after re-move, got %s" % [_frame_count, state]}

	## 阶段 3：deployed 第二次
	if _frame_count >= _CHECK_DEPLOYED_2:
		if _phase_results[2] or state == "deployed":
			_phase_results[2] = true
			if _phase_results[0] and _phase_results[1]:
				return {"status": "pass", "detail": "all 3 phases passed: deployed→marching→deployed"}
			return {"status": "fail", "detail": "deployed_2 ok but earlier phases failed"}
		return {"status": "fail", "detail": "frame %d: expected deployed_2, got %s" % [_frame_count, state]}

	return {"status": "pending", "detail": "frame=%d state=%s phases=%s" % [
		_frame_count, state, str(_phase_results)
	]}
