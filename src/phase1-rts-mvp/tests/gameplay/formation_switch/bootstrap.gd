extends "res://tests/gameplay_bootstrap.gd"

## formation_switch bootstrap — 16C.4（重构为事件驱动）
## 场景：将领完成行军→展开→再行军两次循环，断言状态切换正确。
##
## 状态机（事件驱动，不依赖硬编码帧号）：
##   MOVING_P1  → 等待 state==deployed（第一次）
##   DEPLOYED_1 → 立即发 move_to P2，等待 state==marching
##   MARCHING   → 等待 state==deployed（第二次）
##   DEPLOYED_2 → PASS

var _general: CharacterBody3D = null

const _P1 = Vector3(800.0, 0.0, 600.0)
const _P2 = Vector3(200.0, 0.0, 600.0)

var _stage: String = "moving_p1"  ## moving_p1 / deployed_1 / marching / deployed_2
var _stage_frame: int = 0         ## 进入当前阶段的帧号（用于超时检测）
var _move_to_p2_issued: bool = false

## 各阶段超时帧数（防止无限等待，两次 deployed 各需约 600 帧）
const _TIMEOUT_FRAMES = 1500


func _post_spawn() -> void:
	if _units.size() > 0:
		_general = _units[0]
		_general.move_to(_P1)
		_stage = "moving_p1"
		_stage_frame = 0
		print("[SWITCH] general start, move to P1=%s" % str(_P1))


func _register_assertions() -> void:
	_renderer.add_assertion("formation_switches_correctly", _assert_switch)
	_renderer.get_calibrator().set_run_only(["formation_switches_correctly"])


func _physics_process(delta: float) -> void:
	## 状态机推进：deployed_1 确认后立刻发 P2 命令
	if _stage == "deployed_1" and not _move_to_p2_issued:
		_move_to_p2_issued = true
		if is_instance_valid(_general):
			_general.move_to(_P2)
			print("[SWITCH] frame %d: deployed_1 confirmed → move to P2=%s" % [_frame_count, str(_P2)])
	super._physics_process(delta)


func _assert_switch() -> Dictionary:
	if _general == null or not is_instance_valid(_general):
		return {"status": "fail", "detail": "general invalid"}

	var state = _general.get_formation_state() if _general.has_method("get_formation_state") else "unknown"
	var elapsed = _frame_count - _stage_frame

	match _stage:
		"moving_p1":
			if state == "deployed":
				_stage = "deployed_1"
				_stage_frame = _frame_count
				print("[SWITCH] frame %d: deployed_1 ✓ (took %d frames)" % [_frame_count, elapsed])
			elif elapsed > _TIMEOUT_FRAMES:
				return {"status": "fail", "detail": "timeout waiting for deployed_1 at frame %d, state=%s" % [_frame_count, state]}
			return {"status": "pending", "detail": "waiting deployed_1, frame=%d state=%s" % [_frame_count, state]}

		"deployed_1":
			## 等将领开始移动后切回 marching
			if state == "marching":
				_stage = "marching"
				_stage_frame = _frame_count
				print("[SWITCH] frame %d: marching ✓" % _frame_count)
			elif elapsed > 30:
				return {"status": "fail", "detail": "state should be marching after move_to P2, got %s at frame %d" % [state, _frame_count]}
			return {"status": "pending", "detail": "waiting marching after P2 move, frame=%d state=%s" % [_frame_count, state]}

		"marching":
			if state == "deployed":
				_stage = "deployed_2"
				_stage_frame = _frame_count
				print("[SWITCH] frame %d: deployed_2 ✓ (took %d frames)" % [_frame_count, elapsed])
				return {"status": "pass", "detail": "all 3 phases passed: deployed_1→marching→deployed_2"}
			elif elapsed > _TIMEOUT_FRAMES:
				return {"status": "fail", "detail": "timeout waiting for deployed_2 at frame %d, state=%s" % [_frame_count, state]}
			return {"status": "pending", "detail": "waiting deployed_2, frame=%d state=%s" % [_frame_count, state]}

	return {"status": "pending", "detail": "stage=%s frame=%d" % [_stage, _frame_count]}

