extends Node2D

## Selection Box — 左键拖拽绘制半透明矩形框选区域
## Headless mode: no visual nodes, only emits selection_rect_drawn signal

signal selection_rect_drawn(rect: Rect2)

var _drag_start: Vector2 = Vector2.ZERO
var _is_dragging: bool = false
var _headless: bool = false
var _line: Line2D = null


func set_headless(enabled: bool) -> void:
	_headless = enabled


func _ready() -> void:
	if _headless:
		return
	# Create visual line for selection rectangle (window mode only)
	_line = Line2D.new()
	_line.z_index = 100
	_line.width = 2.0
	_line.default_color = Color(0.2, 0.8, 1.0, 0.8)
	# Add self-drawn polygon for the semi-transparent fill
	var polygon = Polygon2D.new()
	polygon.color = Color(0.2, 0.8, 1.0, 0.15)
	polygon.name = "Fill"
	add_child(polygon)
	add_child(_line)


func simulate_drag(start: Vector2, end: Vector2) -> void:
	## Programmatic drag (used by SimulatedPlayer in headless mode)
	var rect = _make_rect(start, end)
	if rect.size.x > 5.0 and rect.size.y > 5.0:
		selection_rect_drawn.emit(rect)


func _input(event: InputEvent) -> void:
	if _headless:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_start = get_global_mouse_position()
			_is_dragging = true
			_show_rect(_drag_start, _drag_start)
		else:
			if _is_dragging:
				var drag_end = get_global_mouse_position()
				_hide_rect()
				_is_dragging = false
				var rect = _make_rect(_drag_start, drag_end)
				# Only emit if the drag has meaningful size (> 5px)
				if rect.size.x > 5.0 and rect.size.y > 5.0:
					selection_rect_drawn.emit(rect)
	elif event is InputEventMouseMotion:
		if _is_dragging:
			_show_rect(_drag_start, get_global_mouse_position())


func _show_rect(start: Vector2, end: Vector2) -> void:
	var rect = _make_rect(start, end)
	var polygon = $Fill as Polygon2D
	polygon.polygon = PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y),
		rect.end, Vector2(rect.position.x, rect.end.y)
	])
	_line.clear_points()
	_line.add_point(rect.position)
	_line.add_point(Vector2(rect.end.x, rect.position.y))
	_line.add_point(rect.end)
	_line.add_point(Vector2(rect.position.x, rect.end.y))
	_line.add_point(rect.position)


func _hide_rect() -> void:
	($Fill as Polygon2D).polygon = PackedVector2Array()
	_line.clear_points()


func _make_rect(a: Vector2, b: Vector2) -> Rect2:
	var pos = Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var end = Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	return Rect2(pos, end - pos)
