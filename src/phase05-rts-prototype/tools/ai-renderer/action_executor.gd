extends RefCounted

## ActionExecutor — 单条 action 的执行逻辑
## 职责：接收一条 action 字典，操作 sel_box / sel_mgr / produce_callback，返回执行结果。
## 为什么单独拆出：执行逻辑与调度时序无关，可独立测试，也方便扩展新 action 类型。

var _sel_box: Node = null
var _sel_mgr: Node = null
var _map_width: float = 2000.0
var _map_height: float = 1500.0
var _produce_callback: Callable = Callable()
var _coord_mode: String = "2d"  # "2d" = Vector2，"xz" = Vector3(x,0,z)

# 供 SimulatedPlayer 读取（每次 execute 后刷新）
var last_select_count: int = 0
var last_invalid_refs: int = 0
var last_move_commands: int = 0
var last_errors: int = 0


func setup(sel_box: Node, sel_mgr: Node, map_w: float, map_h: float, produce_cb: Callable, coord_mode: String = "2d") -> void:
	_sel_box = sel_box
	_sel_mgr = sel_mgr
	_map_width = map_w
	_map_height = map_h
	_produce_callback = produce_cb
	_coord_mode = coord_mode


func execute(action: Dictionary, frame: int) -> Dictionary:
	## 执行一条 action，返回 {success, detail?, error?}
	var act = action.get("action", "")
	var params = action.get("params", {})
	var result = {"frame": frame, "action": act, "success": false}

	match act:
		"box_select":
			var rect = _resolve_rect(params.get("rect", "full_screen"))
			if _sel_box and _sel_box.has_method("simulate_drag"):
				_sel_box.simulate_drag(rect.position, rect.end)
				result["success"] = true
				if _sel_mgr:
					last_select_count = _sel_mgr.last_select_count
					last_invalid_refs = _sel_mgr.last_invalid_refs
		"right_click":
			var target = _resolve_target(params.get("target", "map_center"))
			if _sel_mgr and _sel_mgr.has_method("simulate_right_click"):
				_sel_mgr.simulate_right_click(target)
				result["success"] = true
				last_move_commands = _sel_mgr.last_select_count
		"deselect":
			if _sel_mgr:
				_sel_mgr._deselect_all()
				result["success"] = true
				last_select_count = 0
		"select_hq":
			var rect = _resolve_rect(params.get("rect", "red_hq_area"))
			if _sel_box and _sel_box.has_method("simulate_drag"):
				_sel_box.simulate_drag(rect.position, rect.end)
				result["success"] = true
				if _sel_mgr:
					last_select_count = _sel_mgr.last_select_count
					last_invalid_refs = _sel_mgr.last_invalid_refs
		"select_produce":
			var unit_type = params.get("unit_type", "worker")
			if _produce_callback.is_valid():
				_produce_callback.call(unit_type)
				result["success"] = true
		"wait_frames":
			## 时序由 SimulatedPlayer 处理，这里只标记成功
			result["success"] = true
			result["detail"] = "wait_frames(%d)" % int(params.get("n", 0))
		"wait_signal":
			## 等待由 SimulatedPlayer 处理，这里只标记成功
			result["success"] = true
			result["detail"] = "wait_signal('%s')" % params.get("signal", "")
		"click_button":
			var label = params.get("label", "")
			## 通过 produce_callback 路由已知生产单位类型；未来新增类型只需扩展此列表
			var known_units = ["Worker", "Fighter", "Archer"]
			if _produce_callback.is_valid() and known_units.has(label):
				_produce_callback.call(label.to_lower())
				result["success"] = true
				result["detail"] = "direct produce callback: %s" % label.to_lower()
			else:
				result["error"] = "click_button: unhandled label='%s' (headless, no UI)" % label
		"ui_find":
			result["success"] = true
			result["detail"] = "ui_find skipped in headless (no UI rendering)"
		_:
			result["error"] = "unknown action: %s" % act
			last_errors += 1

	return result


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
			"red_hq_area":
				var cx = _map_width * 0.2
				var cy = _map_height * 0.5
				return Rect2(Vector2(cx - 80, cy - 80), Vector2(160, 160))
			"blue_hq_area":
				var cx = _map_width * 0.8
				var cy = _map_height * 0.5
				return Rect2(Vector2(cx - 80, cy - 80), Vector2(160, 160))
	if rect_param is Dictionary:
		return Rect2(
			Vector2(rect_param.get("x", 0.0), rect_param.get("y", 0.0)),
			Vector2(rect_param.get("w", _map_width), rect_param.get("h", _map_height))
		)
	return Rect2(Vector2.ZERO, Vector2(_map_width, _map_height))


func _resolve_target(target_param: Variant) -> Variant:
	## "2d" 模式返回 Vector2，"xz" 模式返回 Vector3(x, 0, z)。
	var x: float
	var z: float
	if target_param is String:
		match target_param:
			"map_center":
				x = _map_width / 2.0
				z = _map_height / 2.0
			"red_spawn":
				x = _map_width * 0.2
				z = _map_height / 2.0
			"blue_spawn":
				x = _map_width * 0.8
				z = _map_height / 2.0
			_:
				x = _map_width / 2.0
				z = _map_height / 2.0
	elif target_param is Dictionary:
		x = float(target_param.get("x", 0.0))
		z = float(target_param.get("z", target_param.get("y", 0.0)))
	else:
		x = _map_width / 2.0
		z = _map_height / 2.0
	if _coord_mode == "xz":
		return Vector3(x, 0.0, z)
	return Vector2(x, z)
