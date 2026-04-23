extends RefCounted

## UX Observer — AI Renderer 的 UI/UX 观测层
## 让 AI 能理解"玩家看到了什么、点了什么、发生了什么"
## 仅窗口模式启用，headless 模式跳过

var _enabled: bool = false
var _viewport: Viewport = null
var _camera: Camera2D = null
var _frame_count: int = 0
var _screenshot_interval: float = 5.0  # seconds between auto-screenshots
var _last_screenshot_time: float = 0.0
var _screenshot_dir: String = "res://tests/screenshots/"
var _root_node: Node = null

# Input event log (ring buffer)
var _input_log: Array[Dictionary] = []
var _max_input_log: int = 20

# UI layout cache (updated on demand)
var _ui_snapshot: Dictionary = {}
var _ui_dirty: bool = true
var _ui_has_output_once: bool = false  # Track if we've output UI layout at least once

# Signal tracking: record signal emissions with frame numbers
var _signal_log: Array[Dictionary] = []
var _max_signal_log: int = 20

# Event-driven screenshot: signals that trigger a screenshot when fired
var _screenshot_signals: Array = []

# Screenshot log (ring buffer) — written back on every successful save, output via get_ux_data()
# 截图成功后写入，下帧随 get_ux_data() 进日志，实现截图与日志的双向索引
var _screenshot_log: Array[Dictionary] = []
var _max_screenshot_log: int = 10


func setup(root: Node, viewport: Viewport, camera: Camera2D, config: Dictionary = {}) -> void:
	_root_node = root
	_viewport = viewport
	_camera = camera
	_frame_count = 0
	_enabled = true

	if config.has("screenshot_interval"):
		_screenshot_interval = float(config.get("screenshot_interval", 5.0))
	if config.has("screenshot_dir"):
		_screenshot_dir = str(config.get("screenshot_dir", "res://tests/screenshots/"))

	# Ensure screenshot directory exists
	DirAccess.make_dir_recursive_absolute(_screenshot_dir.replace("res://", ProjectSettings.globalize_path("res://")))

	print("[UX] Observer initialized (screenshot every %.1fs)" % _screenshot_interval)


func is_enabled() -> bool:
	return _enabled


## Called from bootstrap._input() — intercepts all input events
func on_input(event: InputEvent) -> void:
	if not _enabled:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_record_click(event.position, "left")
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_record_click(event.position, "right")


## Set which signals trigger an event-driven screenshot
func set_screenshot_signals(signals: Array) -> void:
	_screenshot_signals = signals
	print("[UX] Event screenshots enabled for: %s" % str(signals))


## Record a signal emission for tracking
func on_signal(signal_name: String, args: Array = []) -> void:
	if not _enabled:
		return
	_signal_log.append({
		"frame": _frame_count,
		"signal": signal_name,
		"args": args,
	})
	if _signal_log.size() > _max_signal_log:
		_signal_log.pop_front()
	# Event-driven screenshot: fire immediately if this signal is whitelisted
	if signal_name in _screenshot_signals:
		take_screenshot(signal_name)


## Mark UI layout as dirty (call when panel shows/hides)
func mark_ui_dirty() -> void:
	_ui_dirty = true
	_ui_has_output_once = false


## Called every physics frame
func tick(frame: int, delta: float) -> void:
	if not _enabled:
		return
	_frame_count = frame

	# Auto-screenshot
	_last_screenshot_time += delta
	if _last_screenshot_time >= _screenshot_interval:
		_last_screenshot_time = 0.0
		take_screenshot("auto")


## Generate structured UX data for Formatter
func get_ux_data() -> Dictionary:
	if not _enabled:
		return {}

	var data: Dictionary = {}

	# Viewport state
	data["viewport"] = _get_viewport_info()

	# UI layout (only output on first time or when dirty)
	if _ui_dirty:
		_ui_snapshot = _capture_ui_layout()
		_ui_dirty = false
		data["ui"] = _ui_snapshot
	elif _ui_has_output_once:
		# Don't include unchanged UI data — keeps output clean
		pass
	else:
		# First time: capture even if not explicitly dirty
		_ui_snapshot = _capture_ui_layout()
		data["ui"] = _ui_snapshot
		_ui_has_output_once = true

	# Input log
	if not _input_log.is_empty():
		data["input_log"] = _input_log.duplicate(true)

	# Signal log
	if not _signal_log.is_empty():
		data["signal_log"] = _signal_log.duplicate(true)

	# Screenshot log — written by take_screenshot(), consumed here for log anchoring
	if not _screenshot_log.is_empty():
		data["screenshot_log"] = _screenshot_log.duplicate(true)

	return data


## Take a screenshot and return the filename
func take_screenshot(reason: String = "manual") -> String:
	if not _enabled or _viewport == null:
		return ""
	var img = _viewport.get_texture().get_image()
	if img.is_empty():
		return ""

	var time_str = Time.get_time_string_from_system().replace(":", "")
	var filename = "ux_%s_f%d.png" % [reason, _frame_count]
	var full_path = _screenshot_dir + filename

	# Convert res:// to absolute path for saving
	var abs_dir = ProjectSettings.globalize_path("res://tests/screenshots/")
	if DirAccess.make_dir_recursive_absolute(abs_dir) == OK:
		var abs_path = abs_dir + filename
		img.save_png(abs_path)
		print("[UX] 📸 Screenshot saved: %s" % filename)
		# Write log anchor so every screenshot has a matching entry in window_debug.log
		_screenshot_log.append({"frame": _frame_count, "filename": filename, "reason": reason})
		if _screenshot_log.size() > _max_screenshot_log:
			_screenshot_log.pop_front()
		return filename
	return ""


# ─── Private ──────────────────────────────────────────────────


func _record_click(screen_pos: Vector2, button: String) -> void:
	var entry: Dictionary = {
		"frame": _frame_count,
		"button": button,
		"screen": {"x": screen_pos.x, "y": screen_pos.y},
		"hit": null,
	}

	# Hit detection: check UI Controls first (top layer)
	var hit_ui = _hit_test_ui(screen_pos)
	if hit_ui != null:
		entry["hit"] = hit_ui
	else:
		# No UI hit — check game entities via physics space query
		var hit_entity = _hit_test_world(screen_pos)
		if hit_entity != null:
			entry["hit"] = hit_entity
		else:
			entry["hit"] = {"type": "none", "detail": "miss"}

	_input_log.append(entry)
	if _input_log.size() > _max_input_log:
		_input_log.pop_front()


func _hit_test_ui(screen_pos: Vector2) -> Variant:
	## Test if screen_pos hits any visible Control node
	if _root_node == null:
		return null

	# Walk CanvasLayer children to find UI controls
	for child in _root_node.get_children():
		if child is CanvasLayer:
			var result = _find_control_at(child, screen_pos)
			if result != null:
				return result
	return null


func _find_control_at(node: Node, screen_pos: Vector2) -> Variant:
	## Recursively find the deepest visible Control containing screen_pos
	# Check children first (topmost/last drawn child has priority)
	var child_count = node.get_child_count()
	for i in range(child_count - 1, -1, -1):
		var child = node.get_child(i)
		var result = _find_control_at(child, screen_pos)
		if result != null:
			return result

	if node is Control:
		var ctrl = node as Control
		if not ctrl.visible:
			return null
		var rect = ctrl.get_global_rect()
		if rect.has_point(screen_pos):
			var info: Dictionary = {
				"type": "ui",
				"node": ctrl.name,
				"class": ctrl.get_class(),
				"rect": {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y},
				"visible": ctrl.visible,
			}
			if ctrl is Button:
				info["enabled"] = ctrl.disabled == false
				info["text"] = ctrl.text
			elif ctrl is Label:
				info["text"] = ctrl.text
			return info
	return null


func _hit_test_world(screen_pos: Vector2) -> Variant:
	## Test if screen_pos hits any game entity via viewport camera transform
	if _camera == null or _root_node == null:
		return null

	var world_pos = _camera.get_global_mouse_position()
	# Direct position match is impractical for small entities,
	# so we check proximity to known entity positions
	var closest_name = ""
	var closest_dist = 50.0  # max click radius in world units

	for child in _root_node.get_children():
		if child is CharacterBody2D or child is StaticBody2D:
			var dist = child.global_position.distance_to(world_pos)
			if dist < closest_dist:
				closest_dist = dist
				closest_name = child.name

	if not closest_name.is_empty():
		return {
			"type": "entity",
			"node": closest_name,
			"world_pos": {"x": world_pos.x, "y": world_pos.y},
			"dist": closest_dist,
		}
	return null


func _get_viewport_info() -> Dictionary:
	if _camera == null:
		return {}
	var pos = _camera.position
	var zoom = _camera.zoom
	var screen_size = _viewport.get_visible_rect().size if _viewport else Vector2.ZERO

	# Calculate visible world rectangle
	var half_ext = screen_size / (zoom.x * 2.0) if zoom.x != 0 else screen_size
	var visible_rect = {
		"left": pos.x - half_ext.x,
		"top": pos.y - half_ext.y,
		"right": pos.x + half_ext.x,
		"bottom": pos.y + half_ext.y,
	}

	return {
		"camera": {"x": pos.x, "y": pos.y},
		"zoom": zoom.x,
		"screen": {"w": screen_size.x, "h": screen_size.y},
		"visible_rect": visible_rect,
	}


func _capture_ui_layout() -> Dictionary:
	## Walk UI tree and capture layout of visible top-level containers
	if _root_node == null:
		return {}

	var layout: Array[Dictionary] = []
	for child in _root_node.get_children():
		if child is CanvasLayer:
			_capture_controls(child, layout, 0)

	return {"containers": layout}


func _capture_controls(node: Node, result: Array, depth: int) -> void:
	## Recursively capture Control nodes up to a reasonable depth
	if depth > 3:  # Don't go too deep
		return

	if node is Control:
		var ctrl = node as Control
		if not ctrl.visible:
			return

		var rect = ctrl.get_global_rect()
		var entry: Dictionary = {
			"name": ctrl.name,
			"class": ctrl.get_class(),
			"pos": {"x": rect.position.x, "y": rect.position.y},
			"size": {"w": rect.size.x, "h": rect.size.y},
		}

		if ctrl is Button:
			entry["text"] = ctrl.text
			entry["disabled"] = ctrl.disabled
		elif ctrl is Label:
			if ctrl.text != "":
				entry["text"] = ctrl.text
		elif ctrl is ProgressBar:
			entry["value"] = ctrl.value
			entry["max"] = ctrl.max_value

		result.append(entry)

	# Recurse into children
	for child in node.get_children():
		_capture_controls(child, result, depth + 1)
