extends Node2D

## HealthBar — 单位血条组件（内嵌到单位节点）
## 受伤显示，满血隐藏，3 秒后自动隐藏

var _bar: TextureProgressBar = null
var _is_headless: bool = false
var _visible_timer: float = 0.0
var _parent_unit: CharacterBody2D = null
var _width: float = 24.0
var _max_hp_ref: float = 100.0


func setup(unit: CharacterBody2D, max_hp: float, headless: bool, radius: float) -> void:
	_parent_unit = unit
	_max_hp_ref = max_hp
	_width = radius * 3.0
	_is_headless = headless
	name = "HealthBar"

	if not _is_headless:
		_build_bar()


func _build_bar() -> void:
	_bar = TextureProgressBar.new()
	_bar.max_value = _max_hp_ref
	_bar.value = _max_hp_ref
	# show_percentage only exists on ProgressBar, not TextureProgressBar
	_bar.custom_minimum_size = Vector2(_width, 4)
	_bar.position = Vector2(-_width / 2, -20)
	_bar.z_index = 50

	# Style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.2)
	_bar.add_theme_stylebox_override("background", style)

	var fill = StyleBoxFlat.new()
	fill.bg_color = Color(0, 1, 0)
	_bar.add_theme_stylebox_override("fill", fill)

	_bar.visible = false
	add_child(_bar)


func update_hp(hp: float) -> void:
	if _is_headless:
		return
	if _bar == null:
		return
	_bar.value = hp
	if hp >= _max_hp_ref:
		_bar.visible = false
		_visible_timer = 0.0
		return

	_bar.visible = true
	_visible_timer = 3.0

	# Color based on HP percentage
	var pct = hp / _max_hp_ref
	var fill_style = _bar.get_theme_stylebox("fill")
	if fill_style is StyleBoxFlat:
		if pct > 0.6:
			fill_style.bg_color = Color(0, 1, 0)
		elif pct > 0.3:
			fill_style.bg_color = Color(1, 1, 0)
		else:
			fill_style.bg_color = Color(1, 0, 0)


func _process(delta: float) -> void:
	if _visible_timer > 0:
		_visible_timer -= delta
		if _visible_timer <= 0 and _bar:
			_bar.visible = false
