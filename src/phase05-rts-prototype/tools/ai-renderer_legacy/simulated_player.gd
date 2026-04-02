extends RefCounted

## SimulatedPlayer — 数据驱动的操作剧本执行器
## 在 headless 模式下模拟玩家操作（框选、右键移动），让 AI Renderer 观测交互链路。

var _actions: Array = []  # [{frame, action, params}]
var _current_index: int = 0
var _frame_count: int = 0
var _executed: Array[Dictionary] = []  # execution log

# References to interaction components (set via setup)
var _sel_box: Node2D = null
var _sel_mgr: Node2D = null
var _map_width: float = 2000.0
var _map_height: float = 1500.0

# Metrics for Sensor Registry
var last_select_count: int = 0
var last_invalid_refs: int = 0
var last_move_commands: int = 0
var last_errors: int = 0


func setup(actions: Array, sel_box: Node2D, sel_mgr: Node2D, map_w: float, map_h: float) -> void:
	_actions = actions
	_sel_box = sel_box
	_sel_mgr = sel_mgr
	_map_width = map_w
	_map_height = map_h
	# Sort by frame to ensure correct execution order
	_actions.sort_custom(func(a, b): return a.get("frame", 0) < b.get("frame", 0))


func tick(frame: int) -> void:
	_frame_count = frame
	while _current_index < _actions.size():
		var action = _actions[_current_index]
		if action.get("frame", 0) <= frame:
			_execute_action(action)
			_current_index += 1
		else:
			break


func _execute_action(action: Dictionary) -> void:
	var act = action.get("action", "")
	var params = action.get("params", {})
	var log_entry = {"frame": _frame_count, "action": act, "success": false}

	match act:
		"box_select":
			var rect = _resolve_rect(params.get("rect", "full_screen"))
			if _sel_box and _sel_box.has_method("simulate_drag"):
				_sel_box.simulate_drag(rect.position, rect.end)
				log_entry["success"] = true
				# Read metrics from SelectionManager
				if _sel_mgr:
					last_select_count = _sel_mgr.last_select_count
					last_invalid_refs = _sel_mgr.last_invalid_refs
		"right_click":
			var target = _resolve_target(params.get("target", "map_center"))
			if _sel_mgr and _sel_mgr.has_method("simulate_right_click"):
				_sel_mgr.simulate_right_click(target)
				log_entry["success"] = true
				last_move_commands = _sel_mgr.last_select_count  # count of units that got the command
		"deselect":
			if _sel_mgr:
				_sel_mgr._deselect_all()
				log_entry["success"] = true
				last_select_count = 0
		_:
			log_entry["error"] = "unknown action: %s" % act
			last_errors += 1

	_executed.append(log_entry)
	print("[SIM] frame=%d action=%s success=%s" % [_frame_count, act, log_entry["success"]])


func _resolve_rect(rect_param: Variant) -> Rect2:
	if rect_param is String:
		match rect_param:
			"full_screen":
				return Rect2(Vector2.ZERO, Vector2(_map_width, _map_height))
			"top_left":
				return Rect2(Vector2.ZERO, Vector2(_map_width / 2.0, _map_height / 2.0))
			"top_right":
				return Rect2(Vector2(_map_width / 2.0, 0), Vector2(_map_width / 2.0, _map_height / 2.0))
			"bottom_left":
				return Rect2(Vector2(0, _map_height / 2.0), Vector2(_map_width / 2.0, _map_height / 2.0))
			"bottom_right":
				return Rect2(Vector2(_map_width / 2.0, _map_height / 2.0), Vector2(_map_width / 2.0, _map_height / 2.0))
	if rect_param is Dictionary:
		var x = rect_param.get("x", 0.0)
		var y = rect_param.get("y", 0.0)
		var w = rect_param.get("w", _map_width)
		var h = rect_param.get("h", _map_height)
		return Rect2(Vector2(x, y), Vector2(w, h))
	return Rect2(Vector2.ZERO, Vector2(_map_width, _map_height))


func _resolve_target(target_param: Variant) -> Vector2:
	if target_param is String:
		match target_param:
			"map_center":
				return Vector2(_map_width / 2.0, _map_height / 2.0)
			"red_spawn":
				return Vector2(_map_width * 0.2, _map_height / 2.0)
			"blue_spawn":
				return Vector2(_map_width * 0.8, _map_height / 2.0)
	if target_param is Dictionary:
		return Vector2(target_param.get("x", 0.0), target_param.get("y", 0.0))
	return Vector2(_map_width / 2.0, _map_height / 2.0)


func get_execution_log() -> Array:
	return _executed.duplicate()
