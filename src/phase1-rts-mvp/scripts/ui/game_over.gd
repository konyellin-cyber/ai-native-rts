extends Control

## GameOver — 游戏结束画面
## 全屏遮罩 + 居中面板 + 战况统计

# Data state for Sensor Registry
var game_over_visible: bool = false
var winner: String = ""

var _is_headless: bool = false
var _overlay: ColorRect = null
var _panel: PanelContainer = null
var _title: Label = null
var _stats: Label = null
var _restart_btn: Button = null
var _quit_btn: Button = null


func setup(headless: bool) -> void:
	_is_headless = headless
	if not _is_headless:
		_build_ui()
	visible = false


func _build_ui() -> void:
	# Root control ignores mouse events (only children need to receive them)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.7)
	_overlay.visible = false
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(300, 200)

	var vbox = VBoxContainer.new()
	_panel.add_child(vbox)

	_title = Label.new()
	_title.text = ""
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(_title)

	_stats = Label.new()
	_stats.text = ""
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_stats)

	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_restart_btn = Button.new()
	_restart_btn.text = "Restart"
	_restart_btn.custom_minimum_size = Vector2(100, 0)
	_restart_btn.pressed.connect(func(): get_tree().reload_current_scene())
	btn_row.add_child(_restart_btn)
	_quit_btn = Button.new()
	_quit_btn.text = "Quit"
	_quit_btn.custom_minimum_size = Vector2(100, 0)
	_quit_btn.pressed.connect(func(): get_tree().quit())
	btn_row.add_child(_quit_btn)
	vbox.add_child(btn_row)

	add_child(_panel)


func show_game_over(win_team: String, stats: Dictionary) -> void:
	winner = win_team
	game_over_visible = true
	visible = true
	if not _is_headless:
		_title.text = "🎉 %s WINS!" % win_team.to_upper()
		_title.add_theme_color_override("font_color",
			Color(1, 0.3, 0.3) if win_team == "red" else Color(0.3, 0.3, 1))
		_stats.text = "Survived: %d\nKills: %d\nCrystals: %d" % [
			stats.get("survived", 0), stats.get("kills", 0), stats.get("crystal", 0)]
		_overlay.visible = true
