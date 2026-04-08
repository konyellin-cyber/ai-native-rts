extends "res://tests/gameplay_bootstrap.gd"

## formation_debug — 临时调试脚本，分析 RigidBody3D 哑兵的位置偏差
## 将领行军后停止，等待 deployed 稳定，在第 300/450/600 帧各采样一次：
## 打印每个士兵的 实际位置 vs 槽位目标 vs 偏差距离 vs 速度大小

var _general: CharacterBody3D = null
var _dummy_soldiers: Array = []

const _MOVE_TARGET = Vector3(700.0, 0.0, 600.0)
var _sampled: Array = [false, false, false]
const _SAMPLE_FRAMES = [300, 450, 600]


func _post_spawn() -> void:
	if _units.size() > 0:
		_general = _units[0]
		_collect_dummy_soldiers()
		_general.move_to(_MOVE_TARGET)
		print("[DEBUG] general start=%s, dummies=%d" % [str(_general.global_position), _dummy_soldiers.size()])


func _register_assertions() -> void:
	_renderer.add_assertion("debug_sample", _assert_debug)
	_renderer.get_calibrator().set_run_only(["debug_sample"])


func _collect_dummy_soldiers() -> void:
	for child in get_children():
		if child.has_method("freeze_at_current"):
			_dummy_soldiers.append(child)


func _assert_debug() -> Dictionary:
	if _general == null or not is_instance_valid(_general):
		return {"status": "fail", "detail": "general invalid"}

	## 在指定帧采样并打印
	for i in range(_SAMPLE_FRAMES.size()):
		if not _sampled[i] and _frame_count >= _SAMPLE_FRAMES[i]:
			_sampled[i] = true
			_print_sample(_SAMPLE_FRAMES[i])

	if _frame_count < _SAMPLE_FRAMES[-1]:
		return {"status": "pending", "detail": "frame %d" % _frame_count}

	return {"status": "pass", "detail": "debug complete"}


func _print_sample(frame: int) -> void:
	var state = _general.get_formation_state() if _general.has_method("get_formation_state") else "?"
	var total = _dummy_soldiers.size()
	var gp = _general.global_position
	print("\n[DEBUG] ===== frame=%d  state=%s  general_pos=(%.1f,%.1f,%.1f) =====" % [
		frame, state, gp.x, gp.y, gp.z
	])

	var max_err: float = 0.0
	var sum_err: float = 0.0
	var count_moving: int = 0
	var err_list: Array = []

	for s in _dummy_soldiers:
		if not is_instance_valid(s):
			continue
		var idx = int(s.name.replace("Dummy_", ""))
		var actual: Vector3 = s.global_position
		var target: Vector3 = _general.get_formation_slot(idx, total)
		var err: float = actual.distance_to(target)
		var spd: float = s.linear_velocity.length() if s.has_method("get") else 0.0
		## linear_velocity 是 RigidBody3D 的属性
		spd = s.linear_velocity.length()
		sum_err += err
		if err > max_err:
			max_err = err
		if spd > 5.0:
			count_moving += 1
		err_list.append([idx, err, spd])

	## 按偏差从大到小排序，打印最差的 10 个
	err_list.sort_custom(func(a, b): return a[1] > b[1])
	print("[DEBUG] top-10 偏差 (idx, dist_to_slot, speed):")
	for j in range(min(10, err_list.size())):
		var e = err_list[j]
		print("  Dummy_%02d  偏差=%.1f  速度=%.1f" % [e[0], e[1], e[2]])

	print("[DEBUG] 统计: 平均偏差=%.1f  最大偏差=%.1f  仍在运动(spd>5)=%d/%d" % [
		sum_err / float(max(total, 1)), max_err, count_moving, total
	])
