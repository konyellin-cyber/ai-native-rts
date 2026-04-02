extends Node2D

## Selection Manager — 管理选中单位，高亮显示，处理框选和移动命令
## Headless mode: no Label/highlight, preserves selection logic for SimulatedPlayer

signal units_selected(units: Array[CharacterBody2D])
signal move_command_issued(target: Vector2, units: Array[CharacterBody2D])

var selected_units: Array[CharacterBody2D] = []
var _all_units: Array[CharacterBody2D] = []
var _label: Label = null
var _left_click_pos: Variant = null
var _headless: bool = false

# Interaction metrics for Sensor Registry (headless testing)
var last_select_count: int = 0
var last_invalid_refs: int = 0
var last_move_commands: int = 0
var total_errors: int = 0


func set_headless(enabled: bool) -> void:
	_headless = enabled


func _ready() -> void:
	# Wait for bootstrap to finish spawning units
	await get_tree().physics_frame
	await get_tree().physics_frame
	_collect_units()

	if not _headless:
		# UI label for selection count (window mode only)
		_label = Label.new()
		_label.z_index = 200
		_label.position = Vector2(10, 10)
		_label.add_theme_font_size_override("font_size", 24)
		_label.add_theme_color_override("font_color", Color.WHITE)
		add_child(_label)


func setup(selection_box: Node) -> void:
	selection_box.selection_rect_drawn.connect(_on_selection_rect)


func _collect_units() -> void:
	_all_units.clear()
	for child in get_parent().get_children():
		if child is CharacterBody2D and child.has_method("get_unit_state"):
			_all_units.append(child)
	print("[SEL] Tracking %d units" % _all_units.size())


func get_all_units() -> Array:
	## Public: returns current unit list (for Sensor Registry ref_holder check)
	return _all_units.duplicate()


func simulate_right_click(target: Vector2) -> void:
	## Programmatic right-click (used by SimulatedPlayer in headless mode)
	if selected_units.size() > 0:
		move_command_issued.emit(target, selected_units)


func _input(event: InputEvent) -> void:
	if _headless:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if selected_units.size() > 0:
			var target = get_global_mouse_position()
			move_command_issued.emit(target, selected_units)
	# Left click (not drag) on empty space = deselect
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_left_click_pos = get_global_mouse_position()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _left_click_pos:
			var release_pos = get_global_mouse_position()
			if _left_click_pos.distance_to(release_pos) < 5.0:
				_deselect_all()
			_left_click_pos = null


func _on_selection_rect(rect: Rect2) -> void:
	_deselect_all()
	# Filter out dead/freed units before selection check
	var before_count = _all_units.size()
	_all_units = _all_units.filter(func(u): return is_instance_valid(u))
	last_invalid_refs = before_count - _all_units.size()
	for unit in _all_units:
		if rect.has_point(unit.global_position):
			_select_unit(unit)
	last_select_count = selected_units.size()
	if selected_units.size() > 0:
		units_selected.emit(selected_units)


func _select_unit(unit: CharacterBody2D) -> void:
	selected_units.append(unit)
	if not _headless:
		_highlight_unit(unit, true)


func _deselect_all() -> void:
	if not _headless:
		for unit in selected_units:
			_highlight_unit(unit, false)
	selected_units.clear()
	_update_label()


func _highlight_unit(unit: CharacterBody2D, active: bool) -> void:
	var visual = unit.get_node_or_null("Visual")
	if visual:
		var line = visual.get_node_or_null("Line2D")
		if line and line is Line2D:
			if active:
				line.default_color = Color(0.0, 1.0, 0.5)
				line.width = 3.0
			else:
				# Restore team color
				var team = unit.team_name
				line.default_color = Color.RED if team == "red" else Color.BLUE
				line.width = 2.0


func _update_label() -> void:
	if _label:
		if selected_units.size() > 0:
			_label.text = "Selected: %d units" % selected_units.size()
		else:
			_label.text = ""


func _process(_delta: float) -> void:
	if _label:
		_update_label()
