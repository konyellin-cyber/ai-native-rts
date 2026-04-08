extends "res://tests/gameplay_bootstrap.gd"

## replenish bootstrap — 15C.3
## 场景：红方（固定间隔）和蓝方（加速间隔）将领各自带 30 个哑兵。
## 断言：
##   - 红方将领：600 帧内补兵 ≥ 12（4 轮 × 3 个，间隔 120 帧固定）
##   - 蓝方将领：640 帧内补兵 ≥ 15（5 轮，间隔逐渐加速）

var _general_red: Node = null
var _general_blue: Node = null
var _initial_count_red: int = 0
var _initial_count_blue: int = 0

## 期望补兵数（在 total_frames 结束前完成）
const _RED_EXPECTED_GAIN: int = 12   ## 4 轮 × 3 个
const _BLUE_EXPECTED_GAIN: int = 15  ## 5 轮（蓝方加速），× 3 个


func _post_spawn() -> void:
	for unit in _units:
		if unit.get("team_name") == "red" and unit.get("unit_type") == "general":
			_general_red = unit
		elif unit.get("team_name") == "blue" and unit.get("unit_type") == "general":
			_general_blue = unit

	if _general_red:
		_initial_count_red = _general_red.get_dummy_count()
	if _general_blue:
		_initial_count_blue = _general_blue.get_dummy_count()

	print("[REPLENISH] init: red=%d dummies, blue=%d dummies" % [
		_initial_count_red, _initial_count_blue
	])


func _register_assertions() -> void:
	_renderer.add_assertion("red_replenish", _assert_red_replenish)
	_renderer.add_assertion("blue_replenish", _assert_blue_replenish)
	_renderer.get_calibrator().set_run_only(["red_replenish", "blue_replenish"])


func _assert_red_replenish() -> Dictionary:
	if _general_red == null or not is_instance_valid(_general_red):
		return {"status": "fail", "detail": "red general invalid"}
	var current = _general_red.get_dummy_count()
	var gain = current - _initial_count_red
	if gain >= _RED_EXPECTED_GAIN:
		return {"status": "pass", "detail": "red gained %d (≥%d)" % [gain, _RED_EXPECTED_GAIN]}
	## 超时判断：600 帧后还没达到则报失败
	if _frame_count > 620:
		return {"status": "fail", "detail": "red gained %d after %d frames (expected ≥%d)" % [gain, _frame_count, _RED_EXPECTED_GAIN]}
	return {"status": "pending", "detail": "red gained %d/%d at frame %d" % [gain, _RED_EXPECTED_GAIN, _frame_count]}


func _assert_blue_replenish() -> Dictionary:
	if _general_blue == null or not is_instance_valid(_general_blue):
		return {"status": "fail", "detail": "blue general invalid"}
	var current = _general_blue.get_dummy_count()
	var gain = current - _initial_count_blue
	if gain >= _BLUE_EXPECTED_GAIN:
		return {"status": "pass", "detail": "blue gained %d (≥%d)" % [gain, _BLUE_EXPECTED_GAIN]}
	## 超时判断：660 帧后还没达到则报失败
	if _frame_count > 680:
		return {"status": "fail", "detail": "blue gained %d after %d frames (expected ≥%d)" % [gain, _frame_count, _BLUE_EXPECTED_GAIN]}
	return {"status": "pending", "detail": "blue gained %d/%d at frame %d" % [gain, _BLUE_EXPECTED_GAIN, _frame_count]}
