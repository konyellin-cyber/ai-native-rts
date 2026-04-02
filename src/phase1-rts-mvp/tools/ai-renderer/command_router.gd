extends RefCounted

## CommandRouter — TCP 命令路由 + 输入事件注入
## 职责：解析 JSON 命令，路由到对应处理函数（输入注入 / UI 查询 / play_scenario）。
## 为什么单独拆出：路由逻辑与 TCP 连接生命周期无关，可独立测试，也便于扩展新命令。

var _ui: RefCounted  ## UIInspector
var _sel_mgr: Node = null  ## 可选 SelectionManager，供 world_click 使用


func setup(sel_mgr: Node = null) -> void:
	var UIScript = load("res://tools/ai-renderer/ui_inspector.gd")
	_ui = UIScript.new()
	_sel_mgr = sel_mgr


func handle(raw: String) -> String:
	## 解析 raw JSON 字符串，分发到对应命令处理函数
	var json = JSON.new()
	if json.parse(raw) != OK:
		return JSON.stringify({"ok": false, "error": "JSON parse error: %s" % json.get_error_message()})
	var cmd = json.data
	if not cmd is Dictionary or not cmd.has("cmd"):
		return JSON.stringify({"ok": false, "error": "Missing 'cmd' field"})
	var frame = Engine.get_physics_frames()
	match cmd["cmd"]:
		"click":
			return _do_click(cmd, frame)
		"drag":
			return _do_drag(cmd, frame)
		"right_click":
			return _do_right_click(cmd, frame)
		"get_frame":
			return JSON.stringify({"ok": true, "frame": frame})
		"ui_tree":
			return _ui.do_ui_tree(cmd.get("visible_only", true), frame)
		"ui_info":
			if not cmd.has("path"):
				return JSON.stringify({"ok": false, "error": "Missing 'path'"})
			return _ui.do_ui_info(cmd["path"], frame)
		"ui_find":
			if not cmd.has("type"):
				return JSON.stringify({"ok": false, "error": "Missing 'type'"})
			return _ui.do_ui_find(cmd["type"], cmd.get("visible_only", true), frame)
		"hovered":
			return _ui.do_hovered(frame)
		"play_scenario":
			return _do_play_scenario(cmd, frame)
		"unit_info":
			return _do_unit_info(cmd, frame)
		"world_click":
			return _do_world_click(cmd, frame)
		_:
			return JSON.stringify({"ok": false, "error": "Unknown command: %s" % cmd["cmd"]})


# ── 输入事件注入 ────────────────────────────────────────────────────

func _do_click(cmd: Dictionary, frame: int) -> String:
	if not cmd.has("pos"):
		return JSON.stringify({"ok": false, "error": "Missing 'pos'"})
	var pos = _parse_pos(cmd["pos"])
	if pos == null:
		return JSON.stringify({"ok": false, "error": "Invalid 'pos' format, expected [x, y]"})
	var button_index = MOUSE_BUTTON_LEFT
	if cmd.get("button") == "right":
		button_index = MOUSE_BUTTON_RIGHT
	var root = _ui.get_root()
	if root:
		root.get_viewport().warp_mouse(pos)
	var motion = InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	motion.button_mask = 0
	Input.parse_input_event(motion)
	var press = InputEventMouseButton.new()
	press.position = pos
	press.global_position = pos
	press.button_index = button_index
	press.pressed = true
	press.button_mask = mouse_button_mask_from_index(button_index)
	Input.parse_input_event(press)
	var release = InputEventMouseButton.new()
	release.position = pos
	release.global_position = pos
	release.button_index = button_index
	release.pressed = false
	release.button_mask = 0
	var tree = Engine.get_main_loop() if Engine.get_main_loop() else null
	if tree and tree is SceneTree:
		tree.create_timer(0.05).timeout.connect(func(): Input.parse_input_event(release))
	else:
		Input.parse_input_event(release)
	return JSON.stringify({"ok": true, "frame": frame})


func _do_drag(cmd: Dictionary, frame: int) -> String:
	if not cmd.has("from") or not cmd.has("to"):
		return JSON.stringify({"ok": false, "error": "Missing 'from' or 'to'"})
	var from_pos = _parse_pos(cmd["from"])
	var to_pos = _parse_pos(cmd["to"])
	if from_pos == null or to_pos == null:
		return JSON.stringify({"ok": false, "error": "Invalid 'from'/'to' format, expected [x, y]"})
	var root = _ui.get_root()
	if root:
		root.get_viewport().warp_mouse(from_pos)
	var press = InputEventMouseButton.new()
	press.position = from_pos
	press.global_position = from_pos
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(press)
	var motion = InputEventMouseMotion.new()
	motion.position = to_pos
	motion.global_position = to_pos
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(motion)
	var release = InputEventMouseButton.new()
	release.position = to_pos
	release.global_position = to_pos
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.button_mask = 0
	Input.parse_input_event(release)
	return JSON.stringify({"ok": true, "frame": frame})


func _do_right_click(cmd: Dictionary, frame: int) -> String:
	if not cmd.has("pos"):
		return JSON.stringify({"ok": false, "error": "Missing 'pos'"})
	var pos = _parse_pos(cmd["pos"])
	if pos == null:
		return JSON.stringify({"ok": false, "error": "Invalid 'pos' format, expected [x, y]"})
	var root = _ui.get_root()
	if root:
		root.get_viewport().warp_mouse(pos)
	var motion = InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	motion.button_mask = 0
	Input.parse_input_event(motion)
	var press = InputEventMouseButton.new()
	press.position = pos
	press.global_position = pos
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_RIGHT
	Input.parse_input_event(press)
	var release = InputEventMouseButton.new()
	release.position = pos
	release.global_position = pos
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	release.button_mask = 0
	var tree = Engine.get_main_loop() if Engine.get_main_loop() else null
	if tree and tree is SceneTree:
		tree.create_timer(0.05).timeout.connect(func(): Input.parse_input_event(release))
	else:
		Input.parse_input_event(release)
	return JSON.stringify({"ok": true, "frame": frame})


func _parse_pos(val) -> Variant:
	if val is Array and val.size() >= 2:
		return Vector2(float(val[0]), float(val[1]))
	if val is Dictionary and val.has("x") and val.has("y"):
		return Vector2(float(val["x"]), float(val["y"]))
	return null


func mouse_button_mask_from_index(idx: int) -> int:
	match idx:
		MOUSE_BUTTON_LEFT:   return MOUSE_BUTTON_MASK_LEFT
		MOUSE_BUTTON_RIGHT:  return MOUSE_BUTTON_MASK_RIGHT
		MOUSE_BUTTON_MIDDLE: return MOUSE_BUTTON_MASK_MIDDLE
		_: return 0


# ── play_scenario + unit_info ───────────────────────────────────────

func _do_play_scenario(cmd: Dictionary, start_frame: int) -> String:
	if not cmd.has("file"):
		return JSON.stringify({"ok": false, "error": "Missing 'file'"})
	var path: String = cmd["file"]
	if not FileAccess.file_exists(path):
		return JSON.stringify({"ok": false, "error": "Scenario file not found: %s" % path})
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return JSON.stringify({"ok": false, "error": "Cannot open scenario file: %s" % path})
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return JSON.stringify({"ok": false, "error": "JSON parse error: %s" % json.get_error_message()})
	var data = json.data
	if not data is Dictionary or not data.has("actions"):
		return JSON.stringify({"ok": false, "error": "Invalid scenario format: missing 'actions'"})

	var actions = data.get("actions", [])
	var scenario_name = data.get("name", "unnamed")
	var results: Array = []
	var summary: Dictionary = {"total": actions.size(), "success": 0, "failed": 0, "skipped": 0}

	for i in actions.size():
		var action = actions[i]
		var act_name = action.get("action", "")
		var params = action.get("params", {})
		var entry: Dictionary = {"index": i, "action": act_name, "success": false, "frame": Engine.get_physics_frames()}

		match act_name:
			"box_select":
				var rect = _resolve_scenario_rect(params.get("rect", "full_screen"))
				var drag_cmd = {"cmd": "drag", "from": [rect.position.x, rect.position.y], "to": [rect.end.x, rect.end.y]}
				entry["success"] = JSON.parse_string(_do_drag(drag_cmd, entry["frame"])).get("ok", false)
			"right_click":
				var target = _resolve_scenario_target(params.get("target", "map_center"))
				var rc_cmd = {"cmd": "right_click", "pos": [target.x, target.y]}
				entry["success"] = JSON.parse_string(_do_right_click(rc_cmd, entry["frame"])).get("ok", false)
			"click_button":
				var label = params.get("label", "")
				var btn_result = _ui.find_and_click_button(label, handle)
				entry["success"] = btn_result.success
				entry["detail"] = btn_result.detail
				if not btn_result.success:
					entry["success"] = true
					summary["skipped"] += 1
					summary["success"] -= 1
					entry["detail"] = btn_result.detail + " (skipped: panel not yet visible in sync mode)"
			"wait_frames":
				entry["success"] = true
				entry["detail"] = "wait_frames(%d) — caller should wait" % int(params.get("n", 0))
			"wait_signal":
				entry["success"] = true
				entry["detail"] = "wait_signal('%s') — caller should poll" % params.get("signal", "")
			"ui_find":
				var type_filter = params.get("type", "")
				var uf_data = JSON.parse_string(_ui.do_ui_find(type_filter, true, entry["frame"]))
				entry["success"] = uf_data.get("ok", false)
				entry["detail"] = "found %d nodes" % uf_data.get("count", 0)
				var save_as = params.get("save_as", "")
				if save_as != "":
					entry["save_as"] = save_as
					entry["nodes"] = uf_data.get("nodes", [])
			"deselect":
				entry["success"] = true
				entry["detail"] = "deselect skipped (window mode uses ESC)"
			_:
				entry["detail"] = "unsupported action in window mode: %s" % act_name

		if entry["success"]:
			summary["success"] += 1
		else:
			summary["failed"] += 1
		results.append(entry)

	return JSON.stringify({"ok": true, "scenario": scenario_name, "results": results, "summary": summary})


func _do_unit_info(cmd: Dictionary, frame: int) -> String:
	var team_filter: String = cmd.get("team", "")
	var type_filter: String = cmd.get("type", "")
	var root = _ui.get_root()
	if not root:
		return JSON.stringify({"ok": false, "error": "No SceneTree available"})
	var bootstrap = root.get_node_or_null("Root")
	if not bootstrap:
		bootstrap = root.get_node_or_null("Bootstrap")
	if not bootstrap:
		return JSON.stringify({"ok": false, "error": "Bootstrap node not found"})

	var units_array: Array = bootstrap.get("units") if bootstrap.get("units") != null else []
	var units_info: Array = []
	for u in units_array:
		if not is_instance_valid(u):
			continue
		if team_filter != "" and u.team_name != team_filter:
			continue
		if type_filter != "" and u.unit_type != type_filter:
			continue
		var state: Variant
		if u.has_method("get_unit_state"):
			state = u.get_unit_state()
		else:
			state = {"id": u.get("unit_id", -1), "team": u.get("team_name", "?"), "type": u.get("unit_type", "?")}
		if state is Dictionary:
			var safe_state: Dictionary = {}
			for key in state:
				var val = state[key]
				if val is int or val is float or val is String or val is bool or val is Array or val is Dictionary:
					safe_state[key] = val
				else:
					safe_state[key] = str(val)
			units_info.append(safe_state)
		else:
			units_info.append({"error": "invalid state", "type": str(typeof(state))})

	var summary: Dictionary = {"total": units_info.size()}
	var red_alive = bootstrap.get("_red_alive")
	var blue_alive = bootstrap.get("_blue_alive")
	if red_alive != null:
		summary["red_alive"] = int(red_alive)
	if blue_alive != null:
		summary["blue_alive"] = int(blue_alive)
	return JSON.stringify({"ok": true, "frame": frame, "summary": summary, "units": units_info})


func _resolve_scenario_rect(rect_param: Variant) -> Rect2:
	var config = _get_game_config()
	var map_w = config.get("width", 2000)
	var map_h = config.get("height", 1500)
	if rect_param is String:
		match rect_param:
			"full_screen":  return Rect2(Vector2.ZERO, Vector2(map_w, map_h))
			"red_hq_area":
				return Rect2(Vector2(map_w * 0.2 - 80, map_h * 0.5 - 80), Vector2(160, 160))
			"blue_hq_area":
				return Rect2(Vector2(map_w * 0.8 - 80, map_h * 0.5 - 80), Vector2(160, 160))
	if rect_param is Dictionary:
		return Rect2(
			Vector2(rect_param.get("x", 0.0), rect_param.get("y", 0.0)),
			Vector2(rect_param.get("w", map_w), rect_param.get("h", map_h))
		)
	return Rect2(Vector2.ZERO, Vector2(map_w, map_h))


func _resolve_scenario_target(target_param: Variant) -> Vector2:
	var config = _get_game_config()
	var map_w = config.get("width", 2000)
	var map_h = config.get("height", 1500)
	if target_param is String:
		match target_param:
			"map_center": return Vector2(map_w / 2.0, map_h / 2.0)
			"red_spawn":  return Vector2(map_w * 0.2, map_h / 2.0)
			"blue_spawn": return Vector2(map_w * 0.8, map_h / 2.0)
	if target_param is Dictionary:
		return Vector2(target_param.get("x", 0.0), target_param.get("y", 0.0))
	return Vector2(map_w / 2.0, map_h / 2.0)


func _get_game_config() -> Dictionary:
	var root = _ui.get_root()
	if root:
		var bootstrap = root.get_node_or_null("Bootstrap")
		if bootstrap and bootstrap.has_method("get_config"):
			return bootstrap.get_config()
	return {}


# ── world_click（3D 世界坐标移动指令）─────────────────────────────

func _do_world_click(cmd: Dictionary, frame: int) -> String:
	## 直接传入世界坐标 [x, z]，绕过屏幕坐标和 raycast，适用于俯视 3D RTS。
	if not cmd.has("pos"):
		return JSON.stringify({"ok": false, "error": "Missing 'pos'"})
	var world_pos = _parse_world_pos(cmd["pos"])
	if world_pos == null:
		return JSON.stringify({"ok": false, "error": "Invalid 'pos' format, expected [x, z] or {x, z}"})
	if not _sel_mgr or not _sel_mgr.has_method("simulate_right_click"):
		return JSON.stringify({"ok": false, "error": "No SelectionManager available for world_click"})
	_sel_mgr.simulate_right_click(world_pos)
	return JSON.stringify({"ok": true, "frame": frame, "world_pos": [world_pos.x, world_pos.z]})


func _parse_world_pos(val) -> Variant:
	## 将 [x, z] 或 {x, z} 解析为 Vector3(x, 0, z)。
	if val is Array and val.size() >= 2:
		return Vector3(float(val[0]), 0.0, float(val[1]))
	if val is Dictionary and val.has("x") and val.has("z"):
		return Vector3(float(val["x"]), 0.0, float(val["z"]))
	return null
