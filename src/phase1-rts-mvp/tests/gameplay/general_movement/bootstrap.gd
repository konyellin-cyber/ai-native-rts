extends "res://tests/gameplay_bootstrap.gd"

## general_movement bootstrap
## 场景：将领从 x=100 → move_to(x=400)，断言位移 PASS

var _general: CharacterBody3D = null
var _start_pos: Vector3 = Vector3.ZERO
const _MOVE_TARGET = Vector3(400.0, 0.0, 250.0)
const _MIN_MOVE_DIST = 100.0  ## 至少移动 100 单位视为通过


func _post_spawn() -> void:
	if _units.size() > 0:
		_general = _units[0]
		_start_pos = _general.global_position
		## 发出移动指令
		_general.move_to(_MOVE_TARGET)
		print("[MOVEMENT] General start=%s, target=%s" % [str(_start_pos), str(_MOVE_TARGET)])


func _register_assertions() -> void:
	_renderer.add_assertion("general_moved", _assert_general_moved)
	_renderer.get_calibrator().set_run_only(["general_moved"])


func _assert_general_moved() -> Dictionary:
	if _general == null or not is_instance_valid(_general):
		return {"status": "pending", "detail": "general not ready"}
	var dist = _general.global_position.distance_to(_start_pos)
	if dist >= _MIN_MOVE_DIST:
		return {"status": "pass", "detail": "moved=%.1f units" % dist}
	return {"status": "pending", "detail": "moved=%.1f / need %.1f" % [dist, _MIN_MOVE_DIST]}
