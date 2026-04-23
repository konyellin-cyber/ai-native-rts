extends "res://tests/gameplay_bootstrap.gd"

## general_idle_move bootstrap
## 模拟主游戏实际流程：将领先 idle 一段时间（模拟游戏刚启动），
## 然后收到玩家移动指令，断言将领移动且哑兵跟随质心也随之移动。
##
## 断言：
##   1. 将领移动距离 >= 200 单位
##   2. 哑兵质心 x 坐标增加 >= 150 单位（跟随将领）
##   3. idle 期间哑兵没有相对初始槽位漂移 > MAX_DRIFT（无物理爆炸）

var _general: CharacterBody3D = null
var _dummy_soldiers: Array = []
var _initial_positions: Array = []  ## 记录哑兵生成时的初始槽位

## 先 idle 60 帧，再发移动指令（模拟玩家操作延迟）
const _MOVE_ISSUE_FRAME = 60
const _MOVE_TARGET = Vector3(700.0, 0.0, 1100.0)
const _MIN_GENERAL_MOVE = 200.0
const _MIN_CENTROID_MOVE_X = 150.0
## 允许的最大初始漂移（物理爆炸会到数百~数千，正常微小位移 < 100）
const _MAX_IDLE_DRIFT = 100.0

var _move_issued: bool = false
var _initial_centroid_x: float = 0.0
var _idle_drift_ok: bool = true
var _idle_drift_detail: String = ""


func _post_spawn() -> void:
	if _units.size() > 0:
		_general = _units[0]
		_collect_dummy_soldiers()
		## 故意不立刻发 move_to()，在 _physics_process 里延迟发
		print("[IDLE_MOVE] general start=%s, dummies=%d, move will issue at frame %d" % [
			str(_general.global_position), _dummy_soldiers.size(), _MOVE_ISSUE_FRAME
		])
		## 记录初始质心 x（生成时的位置）
		_initial_centroid_x = _get_centroid_x()


func _register_assertions() -> void:
	_renderer.add_assertion("idle_then_move_works", _assert_idle_move)
	_renderer.get_calibrator().set_run_only(["idle_then_move_works"])


func _physics_process(delta: float) -> void:
	## idle 期间每帧检测漂移（帧 1~MOVE_ISSUE_FRAME）
	if _frame_count < _MOVE_ISSUE_FRAME and _idle_drift_ok:
		for i in range(_dummy_soldiers.size()):
			var s = _dummy_soldiers[i]
			if not is_instance_valid(s) or i >= _initial_positions.size():
				continue
			var drift = s.global_position.distance_to(_initial_positions[i])
			if drift > _MAX_IDLE_DRIFT:
				_idle_drift_ok = false
				_idle_drift_detail = "Dummy_%d drifted %.1f at frame %d (physics explosion)" % [
					i, drift, _frame_count
				]
				break

	## 延迟发出移动指令，模拟玩家操作
	if _frame_count == _MOVE_ISSUE_FRAME and not _move_issued:
		_move_issued = true
		if is_instance_valid(_general):
			_general.move_to(_MOVE_TARGET)
			print("[IDLE_MOVE] frame %d: move_to issued → %s" % [_frame_count, str(_MOVE_TARGET)])
	super._physics_process(delta)


func _collect_dummy_soldiers() -> void:
	for child in get_children():
		if child.has_method("freeze_at_current"):
			_dummy_soldiers.append(child)
	_initial_positions.clear()
	for s in _dummy_soldiers:
		if is_instance_valid(s):
			_initial_positions.append(s.global_position)
		else:
			_initial_positions.append(Vector3.ZERO)


func _get_centroid_x() -> float:
	var sum_x: float = 0.0
	var count: int = 0
	for s in _dummy_soldiers:
		if is_instance_valid(s):
			sum_x += s.global_position.x
			count += 1
	return sum_x / float(count) if count > 0 else 0.0


func _assert_idle_move() -> Dictionary:
	if _general == null or not is_instance_valid(_general):
		return {"status": "fail", "detail": "general invalid"}
	if _dummy_soldiers.is_empty():
		return {"status": "fail", "detail": "no dummy soldiers found"}

	## 断言0：idle 期间无物理爆炸漂移
	if not _idle_drift_ok:
		return {"status": "fail", "detail": _idle_drift_detail}

	## 等待将领走到目标附近，且之后再等 200 帧让哑兵跟上
	var gen_dist_to_target = _general.global_position.distance_to(_MOVE_TARGET)
	if gen_dist_to_target > 30.0 and _frame_count < 500:
		return {"status": "pending", "detail": "general still moving, dist_to_target=%.1f frame=%d" % [
			gen_dist_to_target, _frame_count
		]}
	## 将领已到达，再给哑兵 200 帧跟上
	if _frame_count < 500:
		return {"status": "pending", "detail": "waiting for dummies to follow, frame=%d" % _frame_count}

	## 断言1：将领实际移动了
	var gen_moved = _general.global_position.distance_to(Vector3(200.0, 0.0, 500.0))
	if gen_moved < _MIN_GENERAL_MOVE:
		return {"status": "fail", "detail": "general barely moved: %.1f < %.1f" % [gen_moved, _MIN_GENERAL_MOVE]}

	## 断言2：哑兵质心跟随
	var centroid_move_x = _get_centroid_x() - _initial_centroid_x
	if centroid_move_x < _MIN_CENTROID_MOVE_X:
		return {"status": "fail", "detail": "centroid barely moved: x_delta=%.1f < %.1f" % [
			centroid_move_x, _MIN_CENTROID_MOVE_X
		]}

	return {"status": "pass", "detail": "gen_moved=%.1f centroid_x_delta=%.1f idle_drift=ok" % [
		gen_moved, centroid_move_x
	]}
