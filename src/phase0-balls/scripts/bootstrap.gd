extends Node2D

## Phase 0 Bootstrap
## Reads config.json, dynamically creates bouncing balls and walls,
## attaches state exporter. All via code, no editor needed.

const CONFIG_PATH = "res://config.json"

var config: Dictionary
var balls: Array[Node2D] = []
var frame_count: int = 0
var total_frames: int = 300
var export_enabled: bool = true
var export_interval: int = 1
var output_dir: String = "res://frames/"
var start_time_msec: int = 0
var screenshot_frames: Array = []  # frames at which to capture screenshots
var _screenshot_dir: String = "res://screenshots/"
var _pending_screenshots: Array = []  # queued by _physics_process, taken in _process


func _ready() -> void:
	config = _load_config()
	total_frames = config.physics.total_frames
	export_enabled = config.export.enabled
	export_interval = config.export.interval_frames
	output_dir = config.export.output_dir

	# Screenshot config
	if config.has("screenshots"):
		for f in config.screenshots.at_frames:
			screenshot_frames.append(int(f))
		_screenshot_dir = config.screenshots.output_dir
		var abs_dir = ProjectSettings.globalize_path(_screenshot_dir)
		DirAccess.make_dir_recursive_absolute(abs_dir)

	# Force high physics FPS for headless mode
	Engine.set_physics_ticks_per_second(config.physics.fps)
	Engine.set_max_fps(config.physics.fps)

	if export_enabled:
		var abs_dir = ProjectSettings.globalize_path(output_dir)
		DirAccess.make_dir_recursive_absolute(abs_dir)

	_create_walls()
	_create_balls()
	start_time_msec = Time.get_ticks_msec()


func _process(_delta: float) -> void:
	# Take any pending screenshots (deferred from _physics_process)
	while _pending_screenshots.size() > 0:
		var frame_num = _pending_screenshots.pop_front()
		_take_screenshot(frame_num)


func _physics_process(_delta: float) -> void:
	frame_count += 1

	# Queue screenshot at specified frames
	if screenshot_frames.has(frame_count):
		_pending_screenshots.append(frame_count)

	if frame_count >= total_frames:
		_perf_report()
		# Defer quit to let _process finish pending screenshots
		_deferred_quit()
		return


func _deferred_quit() -> void:
	# Wait for pending _process screenshots, then quit
	call_deferred("_do_quit")

func _do_quit() -> void:
	get_tree().quit()


func _take_screenshot(frame: int) -> void:
	var image = get_viewport().get_texture().get_image()
	var abs_dir = ProjectSettings.globalize_path(_screenshot_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var path = abs_dir.path_join("frame_%06d.png" % frame)
	image.save_png(path)
	print("[SCREENSHOT] Saved %s" % path)


func _deferred_screenshot(frame: int) -> void:
	# Wait one render frame so the viewport texture is up to date
	await get_tree().process_frame
	var image = get_viewport().get_texture().get_image()
	var abs_dir = ProjectSettings.globalize_path(_screenshot_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var path = abs_dir.path_join("frame_%06d.png" % frame)
	image.save_png(path)
	print("[SCREENSHOT] Saved %s" % path)


func _load_config() -> Dictionary:
	var file = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("Failed to open config: %s" % CONFIG_PATH)
		return {}
	var json_text = file.get_as_text()
	file.close()
	var json = JSON.new()
	var err = json.parse(json_text)
	if err != OK:
		push_error("JSON parse error: %s" % json.get_error_message())
		return {}
	return json.data


func _create_walls() -> void:
	var w = config.bounds.width
	var h = config.bounds.height
	var thickness = 20.0

	_add_wall(Vector2(w / 2, -thickness / 2), Vector2(w, thickness))
	_add_wall(Vector2(w / 2, h + thickness / 2), Vector2(w, thickness))
	_add_wall(Vector2(-thickness / 2, h / 2), Vector2(thickness, h))
	_add_wall(Vector2(w + thickness / 2, h / 2), Vector2(thickness, h))


func _add_wall(pos: Vector2, size: Vector2) -> void:
	var body = StaticBody2D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 2

	var rect = RectangleShape2D.new()
	rect.size = size

	var col = CollisionShape2D.new()
	col.shape = rect
	body.add_child(col)

	var visual = Line2D.new()
	var half = size / 2
	visual.add_point(Vector2(-half.x, -half.y))
	visual.add_point(Vector2(half.x, -half.y))
	visual.add_point(Vector2(half.x, half.y))
	visual.add_point(Vector2(-half.x, half.y))
	visual.add_point(Vector2(-half.x, -half.y))
	visual.default_color = Color.GRAY
	visual.width = 2.0
	body.add_child(visual)

	add_child(body)


func _create_balls() -> void:
	var ball_script = preload("res://scripts/ball.gd")
	var exporter_script = preload("res://scripts/state_exporter.gd")

	var exporter = Node.new()
	exporter.set_script(exporter_script)
	exporter.name = "StateExporter"
	exporter.export_dir = output_dir
	exporter.export_interval = export_interval
	add_child(exporter)

	for ball_data in config.balls:
		var ball = RigidBody2D.new()
		ball.set_script(ball_script)
		ball.name = "Ball_%d" % ball_data.id
		ball.position = Vector2(ball_data.pos[0], ball_data.pos[1])
		ball.linear_velocity = Vector2(ball_data.vel[0], ball_data.vel[1])
		ball.ball_id = ball_data.id
		ball.default_radius = ball_data.radius
		ball.collision_layer = 2
		ball.collision_mask = 3

		var shape = CircleShape2D.new()
		shape.radius = ball_data.radius
		var col = CollisionShape2D.new()
		col.shape = shape
		ball.add_child(col)

		var visual = _create_circle_visual(ball_data.radius, Color.RED)
		ball.add_child(visual)

		balls.append(ball)
		add_child(ball)


func _create_circle_visual(radius: float, color: Color) -> Node2D:
	var node = Node2D.new()
	node.name = "CircleVisual"
	var line = Line2D.new()
	var points = 32
	for i in range(points + 1):
		var angle = (float(i) / float(points)) * TAU
		line.add_point(Vector2(cos(angle) * radius, sin(angle) * radius))
	line.default_color = color
	line.width = 2.0
	node.add_child(line)
	return node


func _perf_report() -> void:
	var elapsed = Time.get_ticks_msec() - start_time_msec
	var fps = float(frame_count) / (elapsed / 1000.0)
	print("[PERF] frames=%d elapsed_ms=%d avg_fps=%.1f" % [frame_count, elapsed, fps])
