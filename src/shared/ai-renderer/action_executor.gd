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
var _viewport: Viewport = null  # 窗口模式注入真实 InputEvent 时使用；headless 下为 null
var _pre_real_click_cb: Callable = Callable()  # 注入 real_click 前的回调（可选），供 window_assertion_setup 设置 _expecting_real_click flag

# 供 SimulatedPlayer 读取（每次 execute 后刷新）
var last_select_count: int = 0
var last_invalid_refs: int = 0
var last_move_commands: int = 0
var last_errors: int = 0


func setup(sel_box: Node, sel_mgr: Node, map_w: float, map_h: float, produce_cb: Callable, coord_mode: String = "2d", viewport: Viewport = null) -> void:
	_sel_box = sel_box
	_sel_mgr = sel_mgr
	_map_width = map_w
	_map_height = map_h
	_produce_callback = produce_cb
	_coord_mode = coord_mode
	_viewport = viewport


func set_pre_real_click_cb(cb: Callable) -> void:
	## 注册 real_click 前置回调（由 bootstrap 在 window_assertions 初始化后调用）
	## 用途：通知 window_assertion_setup._expecting_real_click = true，精确区分 box_select 触发的 units_selected
	_pre_real_click_cb = cb


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
		"real_drag":
			## 注入真实 InputEventMouseButton + MouseMotion，走完 _input() 链路。
			## 与 box_select（直接调 simulate_drag）不同，此路径测试真实输入管线。
			## 参数 from/to 为画布坐标（与 selection_box 使用的坐标系一致）。
			if _viewport == null:
				result["error"] = "real_drag requires viewport (only available in window mode)"
				last_errors += 1
			else:
				var from_canvas = _resolve_vec2(params.get("from", {}))
				var to_canvas   = _resolve_vec2(params.get("to", {}))
				_inject_drag(from_canvas, to_canvas)
				result["success"] = true
				result["detail"] = "real_drag from=(%.0f,%.0f) to=(%.0f,%.0f)" % [from_canvas.x, from_canvas.y, to_canvas.x, to_canvas.y]
		"real_click":
			## 注入真实左键 press+release，走完 _unhandled_input() → _try_select_unit_at_screen。
			## 参数 pos 为画布坐标；或指定 unit_type + team 自动查找第一个匹配单位的屏幕位置。
			if _viewport == null:
				result["error"] = "real_click requires viewport (only available in window mode)"
				last_errors += 1
			else:
				var pos_canvas: Vector2
				if params.has("unit_type") and _sel_mgr and _sel_mgr.has_method("get_all_units"):
					var team = params.get("team", "red")
					var utype = params.get("unit_type", "")
					pos_canvas = _find_unit_canvas_pos(utype, team)
				else:
					pos_canvas = _resolve_vec2(params.get("pos", {}))
				if pos_canvas == Vector2(-1, -1):
					result["error"] = "real_click: unit not found (type=%s team=%s)" % [params.get("unit_type", "?"), params.get("team", "?")]
					last_errors += 1
				else:
					# 在注入点击事件前通知断言层，确保 _expecting_real_click 在 units_selected 信号触发前已设置
					if _pre_real_click_cb.is_valid():
						_pre_real_click_cb.call()
					_inject_click(pos_canvas)
					result["success"] = true
					result["detail"] = "real_click at canvas=(%.0f,%.0f)" % [pos_canvas.x, pos_canvas.y]
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


func _resolve_vec2(param: Variant) -> Vector2:
	## 将 {"x": n, "y": n} 或 [x, y] 解析为 Vector2；
	## 若为空 Dictionary，返回地图中心。
	if param is Dictionary:
		if param.is_empty():
			return Vector2(_map_width / 2.0, _map_height / 2.0)
		return Vector2(float(param.get("x", 0.0)), float(param.get("y", 0.0)))
	if param is Array and param.size() >= 2:
		return Vector2(float(param[0]), float(param[1]))
	return Vector2(_map_width / 2.0, _map_height / 2.0)


func _canvas_to_viewport(canvas_pos: Vector2) -> Vector2:
	## 画布坐标 → 视口像素坐标（用于 Input.parse_input_event / warp_mouse）
	## 关系：viewport_pos = canvas_pos + canvas_transform.origin
	## 为什么每次实时读取 origin：窗口大小或相机布局变化时 origin 会变
	var origin = _viewport.canvas_transform.origin
	return canvas_pos + origin


func _inject_drag(from_canvas: Vector2, to_canvas: Vector2) -> void:
	## 注入完整拖拽事件序列（视口坐标）：
	##   1. warp_mouse 到起点（确保 get_global_mouse_position() 读到正确值）
	##   2. LEFT press
	##   3. MouseMotion（中间点，保证 _is_dragging 期间有运动记录）
	##   4. warp_mouse 到终点
	##   5. LEFT release
	var from_vp = _canvas_to_viewport(from_canvas)
	var to_vp   = _canvas_to_viewport(to_canvas)
	var mid_vp  = (from_vp + to_vp) / 2.0

	# 1. 预置鼠标位置，使 get_global_mouse_position() 在 press 时返回正确值
	_viewport.warp_mouse(from_vp)

	# 2. LEFT press
	var press = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from_vp
	press.global_position = from_vp
	_viewport.push_input(press)

	# 3. MouseMotion（中间点）
	_viewport.warp_mouse(mid_vp)
	var motion = InputEventMouseMotion.new()
	motion.position = mid_vp
	motion.global_position = mid_vp
	motion.relative = mid_vp - from_vp
	_viewport.push_input(motion)

	# 4. 预置终点鼠标位置
	_viewport.warp_mouse(to_vp)

	# 5. LEFT release
	var release = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = to_vp
	release.global_position = to_vp
	_viewport.push_input(release)


func _inject_click(canvas_pos: Vector2) -> void:
	## 注入左键点击：warp_mouse → press → release（同一位置，distance=0 满足 <5px 条件）
	var vp_pos = _canvas_to_viewport(canvas_pos)

	_viewport.warp_mouse(vp_pos)

	var press = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = vp_pos
	press.global_position = vp_pos
	_viewport.push_input(press)

	var release = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = vp_pos
	release.global_position = vp_pos
	_viewport.push_input(release)


func _find_unit_canvas_pos(unit_type: String, team: String) -> Vector2:
	## 在 sel_mgr 中找到第一个 unit_type+team 匹配的单位，
	## 通过 Camera3D 投影到视口坐标，再转换回画布坐标（反向）供 _inject_click 使用。
	## 找不到返回 Vector2(-1, -1)。
	var cam = _viewport.get_camera_3d()
	if not is_instance_valid(cam):
		return Vector2(-1, -1)
	var units = _sel_mgr.get_all_units()
	for unit in units:
		if not is_instance_valid(unit):
			continue
		if unit.get("unit_type") != unit_type:
			continue
		if unit.get("team_name") != team:
			continue
		# 投影到视口像素坐标，再转为画布坐标
		var vp_pos = cam.unproject_position(unit.global_position)
		var canvas_origin = _viewport.canvas_transform.origin
		return vp_pos - canvas_origin
	return Vector2(-1, -1)
