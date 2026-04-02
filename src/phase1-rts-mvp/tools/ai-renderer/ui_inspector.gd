extends RefCounted

## UIInspector — UI 树查询工具
## 职责：查询 SceneTree 中的 Control 节点，序列化为 Dictionary，供 CommandRouter 使用。
## 为什么单独拆出：UI 查询逻辑是纯只读操作，与 TCP / 输入注入完全无关，单独测试更容易。


func get_root() -> Node:
	var loop = Engine.get_main_loop()
	if loop and loop is SceneTree:
		return loop.root
	return null


func collect_controls(parent: Node, visible_only: bool, depth: int = 0, max_depth: int = 10) -> Array:
	## 递归收集 parent 下所有 Control 节点
	if depth > max_depth:
		return []
	var result: Array = []
	for child in parent.get_children():
		if child is Control:
			if visible_only and not child.visible:
				continue
			result.append(child)
		if not child is CanvasItem or child.visible:
			result.append_array(collect_controls(child, visible_only, depth + 1, max_depth))
	return result


func serialize(ctrl: Control, include_children: bool = false) -> Dictionary:
	## 将 Control 节点序列化为 Dictionary
	var info: Dictionary = {
		"path": str(ctrl.get_path()),
		"type": ctrl.get_class(),
		"global_rect": {
			"position": [ctrl.global_position.x, ctrl.global_position.y],
			"size": [ctrl.size.x, ctrl.size.y],
		},
		"visible": ctrl.visible,
	}
	if ctrl is Button:
		info["disabled"] = ctrl.disabled
		info["text"] = ctrl.text
	elif ctrl is Label:
		info["text"] = ctrl.text
	elif ctrl is ProgressBar:
		info["value"] = ctrl.value
		info["max_value"] = ctrl.max_value
	if include_children:
		var children_info: Array = []
		for child in ctrl.get_children():
			if child is Control and child.visible:
				children_info.append(serialize(child, false))
		info["children"] = children_info
	return info


func do_ui_tree(visible_only: bool, frame: int) -> String:
	var root = get_root()
	if not root:
		return JSON.stringify({"ok": false, "error": "No SceneTree available"})
	var controls = collect_controls(root, visible_only)
	var nodes: Array = []
	for ctrl in controls:
		nodes.append(serialize(ctrl, false))
	return JSON.stringify({"ok": true, "frame": frame, "count": nodes.size(), "nodes": nodes})


func do_ui_info(path_str: String, frame: int) -> String:
	var root = get_root()
	if not root:
		return JSON.stringify({"ok": false, "error": "No SceneTree available"})
	var node = root.get_node_or_null(NodePath(path_str))
	if not node:
		return JSON.stringify({"ok": false, "error": "Node not found: %s" % path_str})
	if not node is Control:
		return JSON.stringify({"ok": false, "error": "Node is not a Control: %s (is %s)" % [path_str, node.get_class()]})
	var ctrl = node as Control
	var info = serialize(ctrl, true)
	info["position"] = [ctrl.position.x, ctrl.position.y]
	info["size"] = [ctrl.size.x, ctrl.size.y]
	info["global_position"] = [ctrl.global_position.x, ctrl.global_position.y]
	info["anchor_left"] = ctrl.anchor_left
	info["anchor_right"] = ctrl.anchor_right
	info["anchor_top"] = ctrl.anchor_top
	info["anchor_bottom"] = ctrl.anchor_bottom
	info["z_index"] = ctrl.z_index
	return JSON.stringify({"ok": true, "frame": frame, "node": info})


func do_ui_find(type_filter: String, visible_only: bool, frame: int) -> String:
	var root = get_root()
	if not root:
		return JSON.stringify({"ok": false, "error": "No SceneTree available"})
	var all_controls = collect_controls(root, visible_only)
	var matched: Array = []
	for ctrl in all_controls:
		if ctrl.get_class().to_lower() == type_filter.to_lower():
			matched.append(serialize(ctrl, false))
	return JSON.stringify({"ok": true, "frame": frame, "count": matched.size(), "nodes": matched})


func do_hovered(frame: int) -> String:
	var root = get_root()
	if not root:
		return JSON.stringify({"ok": false, "error": "No SceneTree available"})
	var viewport = root.get_viewport()
	var mouse_pos = viewport.get_mouse_position()
	var hovered = viewport.gui_get_hovered_control()
	var result: Dictionary = {
		"ok": true,
		"frame": frame,
		"mouse_position": [mouse_pos.x, mouse_pos.y],
		"viewport_size": [viewport.size.x, viewport.size.y],
	}
	if hovered:
		result["hovered_control"] = str(hovered.get_path())
		result["hovered_type"] = hovered.get_class()
		result["hovered_rect"] = {
			"position": [hovered.global_position.x, hovered.global_position.y],
			"size": [hovered.size.x, hovered.size.y],
		}
	else:
		result["hovered_control"] = null
	return JSON.stringify(result)


func find_and_click_button(label: String, handle_command_cb: Callable) -> Dictionary:
	## 找到标签匹配的 Button，调用 handle_command_cb 执行点击，返回 {success, detail}
	var root = get_root()
	if not root:
		return {"success": false, "detail": "no SceneTree"}
	var all_controls = collect_controls(root, true)
	for ctrl in all_controls:
		if ctrl is Button and ctrl.visible and not ctrl.disabled:
			if label != "" and ctrl.text.find(label) >= 0:
				var center = ctrl.global_position + ctrl.size / 2.0
				var click_cmd = {"cmd": "click", "pos": [center.x, center.y]}
				var click_result = handle_command_cb.call(JSON.stringify(click_cmd))
				var ok = JSON.parse_string(click_result).get("ok", false)
				return {
					"success": ok,
					"detail": "clicked '%s' at (%.0f, %.0f)" % [ctrl.text, center.x, center.y],
				}
	return {"success": false, "detail": "button with label '%s' not found" % label}
