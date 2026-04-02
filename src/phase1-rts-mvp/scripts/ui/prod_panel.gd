extends Control

## ProdPanel — 生产面板（选中基地时弹出）
## 逻辑层：信号 + 状态；渲染层：按钮/标签/进度条

signal produce_requested(unit_type: String)

# Public state for Sensor Registry
var visible_state: bool = false
var current_production: String = ""
var production_progress: float = 0.0
var can_produce_worker: bool = false
var can_produce_fighter: bool = false
var can_produce_archer: bool = false

var _is_headless: bool = false
var _panel: PanelContainer = null
var _title_label: Label = null
var _worker_btn: Button = null
var _fighter_btn: Button = null
var _archer_btn: Button = null
var _worker_info: Label = null
var _fighter_info: Label = null
var _archer_info: Label = null
var _progress_label: Label = null
var _progress_bar: ProgressBar = null
var _hq_ref: Node = null
var _camera: Camera3D = null  ## 窗口模式下用于将 HQ 3D 坐标投影到屏幕，驱动面板跟随


func setup(headless: bool) -> void:
	_is_headless = headless
	if not _is_headless:
		_build_ui()


func _build_ui() -> void:
	# Make ProdPanel fill the entire viewport so CENTER_TOP works correctly
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Root control ignores mouse events (only children need to receive them)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.z_index = 150
	# 不设 anchor preset，位置由 _reposition_panel() 每帧根据 HQ 世界坐标动态计算
	# Darken panel background
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.12, 0.92)
	panel_style.border_color = Color(0.4, 0.4, 0.5, 0.8)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(8)
	panel_style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", panel_style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "⚒ Base — Production"
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	vbox.add_child(_title_label)

	# Separator under title
	var title_sep = HSeparator.new()
	vbox.add_child(title_sep)

	# Worker row
	var worker_row = HBoxContainer.new()
	worker_row.add_theme_constant_override("separation", 10)
	_worker_btn = _make_styled_button("👷 Worker")
	_worker_btn.custom_minimum_size = Vector2(130, 36)
	_worker_btn.pressed.connect(func(): produce_requested.emit("worker"))
	worker_row.add_child(_worker_btn)
	_worker_info = Label.new()
	_worker_info.text = "💎 50  ⏱ 3s"
	_worker_info.add_theme_font_size_override("font_size", 16)
	_worker_info.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	worker_row.add_child(_worker_info)
	vbox.add_child(worker_row)

	# Fighter row
	var fighter_row = HBoxContainer.new()
	fighter_row.add_theme_constant_override("separation", 10)
	_fighter_btn = _make_styled_button("⚔ Fighter")
	_fighter_btn.custom_minimum_size = Vector2(130, 36)
	_fighter_btn.pressed.connect(func(): produce_requested.emit("fighter"))
	fighter_row.add_child(_fighter_btn)
	_fighter_info = Label.new()
	_fighter_info.text = "💎 100  ⏱ 5s"
	_fighter_info.add_theme_font_size_override("font_size", 16)
	_fighter_info.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	fighter_row.add_child(_fighter_info)
	vbox.add_child(fighter_row)

	# Archer row
	var archer_row = HBoxContainer.new()
	archer_row.add_theme_constant_override("separation", 10)
	_archer_btn = _make_styled_button("🏹 Archer")
	_archer_btn.custom_minimum_size = Vector2(130, 36)
	_archer_btn.pressed.connect(func(): produce_requested.emit("archer"))
	archer_row.add_child(_archer_btn)
	_archer_info = Label.new()
	_archer_info.text = "💎 125  ⏱ 4s"
	_archer_info.add_theme_font_size_override("font_size", 16)
	_archer_info.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	archer_row.add_child(_archer_info)
	vbox.add_child(archer_row)

	# Progress
	var hsep = HSeparator.new()
	vbox.add_child(hsep)
	_progress_label = Label.new()
	_progress_label.text = ""
	_progress_label.add_theme_font_size_override("font_size", 14)
	_progress_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(_progress_label)
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(200, 0)
	_progress_bar.max_value = 100.0
	_progress_bar.value = 0.0
	# Style progress bar
	var pb_style_bg = StyleBoxFlat.new()
	pb_style_bg.bg_color = Color(0.15, 0.15, 0.2)
	pb_style_bg.set_corner_radius_all(4)
	_progress_bar.add_theme_stylebox_override("background", pb_style_bg)
	var pb_style_fill = StyleBoxFlat.new()
	pb_style_fill.bg_color = Color(0.2, 0.7, 1.0)
	pb_style_fill.set_corner_radius_all(4)
	_progress_bar.add_theme_stylebox_override("fill", pb_style_fill)
	vbox.add_child(_progress_bar)  # 修复：之前漏掉此行导致进度条不显示

	add_child(_panel)


func _make_styled_button(text: String) -> Button:
	var btn = Button.new()
	btn.text = text

	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(0.18, 0.30, 0.55, 0.95)
	normal.border_color = Color(0.4, 0.6, 0.9, 0.7)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", normal)

	var hover = StyleBoxFlat.new()
	hover.bg_color = Color(0.25, 0.42, 0.72, 0.95)
	hover.border_color = Color(0.5, 0.75, 1.0, 0.9)
	hover.set_border_width_all(1)
	hover.set_corner_radius_all(6)
	hover.set_content_margin_all(8)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed = StyleBoxFlat.new()
	pressed.bg_color = Color(0.12, 0.20, 0.40, 0.95)
	pressed.border_color = Color(0.3, 0.5, 0.8, 0.7)
	pressed.set_border_width_all(1)
	pressed.set_corner_radius_all(6)
	pressed.set_content_margin_all(8)
	btn.add_theme_stylebox_override("pressed", pressed)

	var disabled = StyleBoxFlat.new()
	disabled.bg_color = Color(0.12, 0.12, 0.15, 0.8)
	disabled.border_color = Color(0.25, 0.25, 0.3, 0.5)
	disabled.set_border_width_all(1)
	disabled.set_corner_radius_all(6)
	disabled.set_content_margin_all(8)
	btn.add_theme_stylebox_override("disabled", disabled)

	# Button text color
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color(0.85, 0.9, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(0.4, 0.4, 0.4))

	btn.add_theme_font_size_override("font_size", 16)
	return btn


func _input(event: InputEvent) -> void:
	## 面板可见时，吸收面板矩形内的左键点击，阻止穿透到 SelectionManager。
	## 为什么需要拦截：根 Control 的 MOUSE_FILTER_IGNORE 不阻止 Node._input()，
	##   按钮点击会同时到达 SelectionManager → 触发 click_missed → 关闭面板。
	## 为什么只拦截面板内部：面板外的点击应正常关闭面板（语义正确）。
	if not visible_state or not _panel or not _panel.visible:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos = get_viewport().get_mouse_position()
		var panel_rect = Rect2(_panel.position, _panel.size)
		if panel_rect.has_point(mouse_pos):
			get_viewport().set_input_as_handled()


func show_panel(hq: Node) -> void:
	_hq_ref = hq
	visible_state = true
	current_production = hq._producing if is_instance_valid(hq) else ""
	if not _is_headless and _panel:
		_panel.visible = true
		_reposition_panel()


func hide_panel() -> void:
	_hq_ref = null
	visible_state = false
	current_production = ""
	if not _is_headless and _panel:
		_panel.visible = false


func update_state(hq: Node, worker_cost: int, fighter_cost: int, archer_cost: int = 125) -> void:
	## Called each frame from bootstrap
	if not visible_state:
		return
	if not is_instance_valid(hq):
		hide_panel()
		return

	_hq_ref = hq
	current_production = hq._producing if "_producing" in hq else ""
	can_produce_worker = hq.crystal >= worker_cost
	can_produce_fighter = hq.crystal >= fighter_cost
	can_produce_archer = hq.crystal >= archer_cost
	production_progress = 0.0

	if not hq._queue.is_empty():
		var item = hq._queue[0]
		var total = item.time_left
		production_progress = hq._production_timer / total * 100.0 if total > 0 else 0.0

	if not _is_headless:
		_update_visuals(worker_cost, fighter_cost, archer_cost)


func _update_visuals(worker_cost: int, fighter_cost: int, archer_cost: int = 125) -> void:
	if _worker_btn:
		_worker_btn.disabled = not can_produce_worker
	if _fighter_btn:
		_fighter_btn.disabled = not can_produce_fighter
	if _archer_btn:
		_archer_btn.disabled = not can_produce_archer
	if _worker_info:
		_worker_info.text = "💎 %d  ⏱ 3s" % worker_cost
	if _fighter_info:
		_fighter_info.text = "💎 %d  ⏱ 5s" % fighter_cost
	if _archer_info:
		_archer_info.text = "💎 %d  ⏱ 4s" % archer_cost
	if _progress_label:
		if current_production != "":
			_progress_label.text = "Producing: %s (%.1fs)" % [current_production, production_progress]
		else:
			_progress_label.text = "Idle"
	if _progress_bar:
		_progress_bar.value = production_progress
	_reposition_panel()


func _reposition_panel() -> void:
	## 将面板定位在基地的屏幕坐标上方，实现"悬浮在基地上方"的效果。
	## 为什么用 unproject_position：正交相机下此接口将世界坐标精确映射到视口像素坐标。
	if not is_instance_valid(_hq_ref) or not _panel:
		return
	if not is_instance_valid(_camera):
		# 延迟查找 Camera3D（setup 时可能还未加入场景树）
		_camera = get_viewport().get_camera_3d() if get_viewport() else null
	if not is_instance_valid(_camera):
		return
	var screen_pos = _camera.unproject_position(_hq_ref.global_position)
	# 面板居中对齐基地 X，显示在基地上方 80px
	var panel_size = _panel.size
	var x = screen_pos.x - panel_size.x / 2.0
	var y = screen_pos.y - panel_size.y - 80.0
	# 防止面板超出视口边界
	var vp_size = get_viewport_rect().size
	x = clampf(x, 10.0, vp_size.x - panel_size.x - 10.0)
	y = clampf(y, 10.0, vp_size.y - panel_size.y - 10.0)
	_panel.position = Vector2(x, y)
