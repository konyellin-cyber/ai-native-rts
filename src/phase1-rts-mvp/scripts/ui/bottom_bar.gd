extends CanvasLayer

## BottomBar — 底部状态栏（资源/选中信息/战况）
## 三段式 HBoxContainer，headless 下只保留数据逻辑

# Data signals (always active)
signal data_updated(resources: Dictionary, selection: Dictionary, combat: Dictionary)

# Public state for Sensor Registry
var resource_crystal: int = 0
var selected_count: int = 0
var selected_types: String = ""
var red_alive_count: int = 0
var blue_alive_count: int = 0

var _is_headless: bool = false
var _container: HBoxContainer = null
var _resource_label: Label = null
var _selection_label: Label = null
var _combat_label: Label = null


func setup(headless: bool) -> void:
	_is_headless = headless
	if not _is_headless:
		_build_ui()


func _build_ui() -> void:
	_container = HBoxContainer.new()
	_container.anchor_left = 0.0
	_container.anchor_right = 1.0
	_container.anchor_top = 1.0
	_container.anchor_bottom = 1.0
	_container.offset_top = -40.0
	_container.add_theme_constant_override("separation", 40)
	_container.z_index = 100

	# Resource segment
	_resource_label = Label.new()
	_resource_label.text = "💎 Crystal: 0"
	_resource_label.add_theme_font_size_override("font_size", 20)
	_resource_label.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
	_container.add_child(_resource_label)

	# Selection segment
	_selection_label = Label.new()
	_selection_label.text = ""
	_selection_label.add_theme_font_size_override("font_size", 20)
	_selection_label.add_theme_color_override("font_color", Color.WHITE)
	_container.add_child(_selection_label)

	# Combat segment
	_combat_label = Label.new()
	_combat_label.text = ""
	_combat_label.add_theme_font_size_override("font_size", 20)
	_combat_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	_container.add_child(_combat_label)

	add_child(_container)


func update_data(hq: Node, selected_units: Array, red_alive: int, blue_alive: int) -> void:
	## Called from bootstrap each frame
	resource_crystal = hq.crystal if is_instance_valid(hq) else 0
	selected_count = selected_units.size()
	red_alive_count = red_alive
	blue_alive_count = blue_alive

	# Count types
	var type_counts: Dictionary = {}
	for u in selected_units:
		if not is_instance_valid(u):
			continue
		var t = u.get("unit_type") if u.has_method("get") else "unknown"
		if not type_counts.has(t):
			type_counts[t] = 0
		type_counts[t] += 1

	var parts: PackedStringArray = []
	for t in type_counts:
		parts.append("%d %s" % [type_counts[t], t])
	selected_types = ", ".join(parts)

	if not _is_headless:
		_update_labels()


func _update_labels() -> void:
	if _resource_label:
		_resource_label.text = "💎 Crystal: %d" % resource_crystal
	if _selection_label:
		_selection_label.text = "Selected: %s" % selected_types if selected_count > 0 else ""
	if _combat_label:
		_combat_label.text = "⚔ %d : %d" % [red_alive_count, blue_alive_count]
