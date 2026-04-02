extends Node2D

## Phase 0.5 Bootstrap
## Reads config.json, creates map/obstacles/navigation/units.
## All via code, no editor needed.

const CONFIG_PATH = "res://config.json"

var config: Dictionary
var units: Array[CharacterBody2D] = []
var frame_count: int = 0
var total_frames: int = 600
var start_time_msec: int = 0
var is_headless: bool = false
var renderer: RefCounted  # AIRenderer instance
var _kill_log: Array[Dictionary] = []  # {tick, killer_id, killer_team, victim_id, victim_team}
var _red_alive: int = 0
var _blue_alive: int = 0


func _ready() -> void:
	config = _load_config()
	total_frames = config.physics.total_frames

	Engine.set_physics_ticks_per_second(config.physics.fps)
	Engine.set_max_fps(config.physics.fps)

	# Detect headless mode — DisplayServer returns "headless" when --headless flag used
	is_headless = DisplayServer.get_name() == "headless"

	# Init AI Renderer
	var AIRendererScript = load("res://tools/ai-renderer/ai_renderer.gd")
	renderer = AIRendererScript.new(config.get("renderer", {"mode": "off", "sample_rate": 60, "calibrate": false}))

	_create_map_walls()
	_create_obstacles()
	_create_navigation()
	_spawn_units()

	# Create interaction subsystem in all modes (needed for headless testing)
	_create_interaction()

	# Create visual components only in window mode
	if not is_headless:
		_create_visuals()

	# CLI mode: auto-quit after total_frames
	if is_headless:
		start_time_msec = Time.get_ticks_msec()
		print("[BOOT] Headless mode: %d frames" % total_frames)
		_setup_calibrator()


func _physics_process(_delta: float) -> void:
	_clean_dead_units()
	# Check win condition in all modes
	if _red_alive == 0 or _blue_alive == 0:
		if is_headless:
			print("[BATTLE] Over! Red: %d / Blue: %d" % [_red_alive, _blue_alive])
			renderer.print_results()
			_perf_report()
			get_tree().quit()
		return

	if is_headless:
		frame_count += 1
		# Tick SimulatedPlayer (executes scripted actions at specified frames)
		if _sim_player:
			_sim_player.tick(frame_count)
		# Build extra data including interaction metrics
		var extra_data = {
			"red_alive": _red_alive,
			"blue_alive": _blue_alive,
			"kill_count": _kill_log.size(),
		}
		if _sim_player:
			extra_data["simulated_player"] = {
				"select": _sim_player.last_select_count,
				"invalid_refs": _sim_player.last_invalid_refs,
				"move_commands": _sim_player.last_move_commands,
				"errors": _sim_player.last_errors,
			}
		renderer.set_extra(extra_data)
		renderer.tick()
		if frame_count >= total_frames:
			renderer.print_results()
			_perf_report()
			get_tree().quit()
	return


# ─── Config ──────────────────────────────────────────────────────

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


# ─── Map Boundary ────────────────────────────────────────────────

func _create_map_walls() -> void:
	var w = config.map.width
	var h = config.map.height
	var t = 40.0

	_add_wall(Vector2(w / 2, -t / 2), Vector2(w, t))
	_add_wall(Vector2(w / 2, h + t / 2), Vector2(w, t))
	_add_wall(Vector2(-t / 2, h / 2), Vector2(t, h))
	_add_wall(Vector2(w + t / 2, h / 2), Vector2(t, h))


func _add_wall(pos: Vector2, size: Vector2) -> void:
	var body = StaticBody2D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0

	var rect = RectangleShape2D.new()
	rect.size = size
	var col = CollisionShape2D.new()
	col.shape = rect
	body.add_child(col)

	# Visual: outline only in window mode
	if not is_headless:
		_add_rect_outline(body, size, Color.DARK_GRAY)

	add_child(body)


# ─── Obstacles ───────────────────────────────────────────────────

func _create_obstacles() -> void:
	for obs in config.obstacles:
		var body = StaticBody2D.new()
		body.position = Vector2(obs.x + obs.w / 2.0, obs.y + obs.h / 2.0)
		body.collision_layer = 1
		body.collision_mask = 0

		var rect = RectangleShape2D.new()
		rect.size = Vector2(obs.w, obs.h)
		var col = CollisionShape2D.new()
		col.shape = rect
		body.add_child(col)

		if not is_headless:
			_add_rect_outline(body, Vector2(obs.w, obs.h), Color(0.3, 0.3, 0.35))

		add_child(body)

	print("[BOOT] Created %d obstacles" % config.obstacles.size())


# ─── Navigation ──────────────────────────────────────────────────

func _create_navigation() -> void:
	var nav_region = NavigationRegion2D.new()
	var nav_poly = NavigationPolygon.new()

	# Outer boundary: full map area
	var w = float(config.map.width)
	var h = float(config.map.height)
	nav_poly.add_outline(PackedVector2Array([
		Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)
	]))

	# Carve out obstacles as holes
	for obs in config.obstacles:
		nav_poly.add_outline(PackedVector2Array([
			Vector2(obs.x, obs.y),
			Vector2(obs.x + obs.w, obs.y),
			Vector2(obs.x + obs.w, obs.y + obs.h),
			Vector2(obs.x, obs.y + obs.h)
		]))

	nav_region.navigation_polygon = nav_poly
	add_child(nav_region)
	nav_region.bake_navigation_polygon(false)
	print("[BOOT] Navigation mesh baked")


# ─── Unit Spawning ───────────────────────────────────────────────

func _spawn_units() -> void:
	var unit_script = preload("res://scripts/unit.gd")
	var uc = config.units
	var id = 0

	# Red team
	for i in range(uc.red_count):
		var offset = Vector2(randf_range(-80, 80), randf_range(-80, 80))
		var pos = Vector2(uc.spawn_red.x, uc.spawn_red.y) + offset
		var unit = _make_unit(unit_script, id, "red", pos, uc)
		units.append(unit)
		add_child(unit)
		id += 1

	# Blue team
	for i in range(uc.blue_count):
		var offset = Vector2(randf_range(-80, 80), randf_range(-80, 80))
		var pos = Vector2(uc.spawn_blue.x, uc.spawn_blue.y) + offset
		var unit = _make_unit(unit_script, id, "blue", pos, uc)
		units.append(unit)
		add_child(unit)
		id += 1

	print("[BOOT] Spawned %d units (%d red + %d blue)" % [units.size(), uc.red_count, uc.blue_count])
	_red_alive = uc.red_count
	_blue_alive = uc.blue_count

	# Connect death signals & register to renderer
	var fields: Array[String] = ["unit_id", "team_name", "global_position", "hp", "max_hp", "ai_state"]
	for u in units:
		u.died.connect(_on_unit_died)
		renderer.register(u.name, u, fields)


func _make_unit(script: Script, id: int, team: String, pos: Vector2, uc: Dictionary) -> CharacterBody2D:
	var unit = CharacterBody2D.new()
	unit.set_script(script)
	unit.name = "Unit_%d" % id
	unit.position = pos
	unit.unit_id = id
	unit.team_name = team
	unit.move_speed = uc.speed
	unit.unit_radius = uc.radius
	unit.max_hp = uc.hp
	unit.hp = uc.hp
	unit.attack_damage = uc.attack_damage
	unit.attack_range = uc.attack_range
	unit.sight_range = uc.sight_range
	unit.attack_cooldown = uc.attack_cooldown
	# Collision: only hit walls/obstacles (layer 1)
	unit.collision_layer = 0
	unit.collision_mask = 1

	# Collision shape
	var circle = CircleShape2D.new()
	circle.radius = uc.radius
	var col = CollisionShape2D.new()
	col.shape = circle
	col.disabled = false
	unit.add_child(col)

	# Navigation agent
	var agent = NavigationAgent2D.new()
	agent.path_desired_distance = 20.0
	agent.target_desired_distance = 20.0
	agent.name = "NavAgent"
	unit.add_child(agent)

	# Visual
	if not is_headless:
		var color = Color.RED if team == "red" else Color.BLUE
		var visual = _make_circle_visual(uc.radius, color)
		visual.name = "Visual"
		unit.add_child(visual)

	return unit


# ─── Interaction (all modes, headless-compatible) ────────────────

var _sel_box: Node2D = null
var _sel_mgr: Node2D = null
var _sim_player: RefCounted = null  # SimulatedPlayer (headless testing)


func _create_interaction() -> void:
	# Selection box — headless mode skips visual nodes
	var sel_box_script = preload("res://scripts/selection_box.gd")
	_sel_box = Node2D.new()
	_sel_box.set_script(sel_box_script)
	_sel_box.name = "SelectionBox"
	if is_headless:
		_sel_box.set_headless(true)
	add_child(_sel_box)

	# Selection manager — headless mode skips Label, preserves logic
	var sel_mgr_script = preload("res://scripts/selection_manager.gd")
	_sel_mgr = Node2D.new()
	_sel_mgr.set_script(sel_mgr_script)
	_sel_mgr.name = "SelectionManager"
	if is_headless:
		_sel_mgr.set_headless(true)
	add_child(_sel_mgr)
	_sel_mgr.setup(_sel_box)
	_sel_mgr.move_command_issued.connect(_on_move_command)

	# Register SelectionManager as ref_holder (for lifecycle integrity checks)
	renderer.register_ref_holder("SelectionManager", _sel_mgr.get_all_units)

	# Set up SimulatedPlayer in headless mode (test interaction via scripted actions)
	if is_headless:
		var SimScript = load("res://tools/ai-renderer/simulated_player.gd")
		_sim_player = SimScript.new()
		var test_actions = config.get("test_actions", [])
		_sim_player.setup(test_actions, _sel_box, _sel_mgr, float(config.map.width), float(config.map.height))
		print("[BOOT] SimulatedPlayer: %d test actions loaded" % test_actions.size())


# ─── Visuals (window mode only) ─────────────────────────────────

func _create_visuals() -> void:
	# Camera2D centered on map
	var camera = Camera2D.new()
	camera.position = Vector2(config.map.width / 2.0, config.map.height / 2.0)
	camera.zoom = Vector2(0.5, 0.5)
	add_child(camera)


# ─── Visuals ─────────────────────────────────────────────────────

func _add_rect_outline(parent: Node, size: Vector2, color: Color) -> void:
	var line = Line2D.new()
	var half = size / 2.0
	line.add_point(Vector2(-half.x, -half.y))
	line.add_point(Vector2(half.x, -half.y))
	line.add_point(Vector2(half.x, half.y))
	line.add_point(Vector2(-half.x, half.y))
	line.add_point(Vector2(-half.x, -half.y))
	line.default_color = color
	line.width = 2.0
	parent.add_child(line)


func _make_circle_visual(radius: float, color: Color) -> Node2D:
	var node = Node2D.new()
	var line = Line2D.new()
	var pts = 20
	for i in range(pts + 1):
		var angle = (float(i) / float(pts)) * TAU
		line.add_point(Vector2(cos(angle) * radius, sin(angle) * radius))
	line.default_color = color
	line.width = 2.0
	node.add_child(line)
	return node


func _on_move_command(target: Vector2, selected: Array[CharacterBody2D]) -> void:
	for unit in selected:
		if is_instance_valid(unit) and unit.has_method("move_to"):
			unit.move_to(target)
	# Spawn a visual marker at target position (window mode only)
	if not is_headless:
		_add_move_marker(target)


func _add_move_marker(pos: Vector2) -> void:
	var marker = Node2D.new()
	marker.position = pos
	marker.name = "MoveMarker"
	var line = Line2D.new()
	var r = 10
	var pts = 20
	for i in range(pts + 1):
		var angle = (float(i) / float(pts)) * TAU
		line.add_point(Vector2(cos(angle) * r, sin(angle) * r))
	line.default_color = Color(0.0, 1.0, 0.3)
	line.width = 2.0
	marker.add_child(line)
	add_child(marker)
	# Fade out after 1 second
	var tween = create_tween()
	tween.tween_property(marker, "modulate", Color.TRANSPARENT, 1.0)
	tween.tween_callback(marker.queue_free)


# ─── Unit Lifecycle ─────────────────────────────────────────────────

func _on_unit_died(victim_id: int, victim_team: String) -> void:
	if victim_team == "red":
		_red_alive -= 1
	else:
		_blue_alive -= 1
	_kill_log.append({"tick": frame_count, "victim_id": victim_id, "victim_team": victim_team})
	var key = "Unit_%d" % victim_id
	renderer.unregister(key)
	print("[DEATH] %s (team=%s) red=%d blue=%d" % [key, victim_team, _red_alive, _blue_alive])


func _clean_dead_units() -> void:
	var i = units.size() - 1
	while i >= 0:
		if not is_instance_valid(units[i]) or units[i]._state == "dead":
			units.remove_at(i)
		i -= 1

var _cal_state: Dictionary = {}

func _setup_calibrator() -> void:
	_cal_state = {"init_dist": -1.0}
	# Original 6 assertions
	renderer.add_assertion("team_groups", _assert_team_groups)
	renderer.add_assertion("chase_convergence", _assert_chase_convergence)
	renderer.add_assertion("combat_kills", _assert_combat_kills)
	renderer.add_assertion("battle_resolution", _assert_battle_resolution)
	renderer.add_assertion("renderer_combat_data", _assert_renderer_combat_data)
	renderer.add_assertion("formatter_output", _assert_formatter_output)
	# v2: interaction + lifecycle assertions
	renderer.add_assertion("node_lifecycle_integrity", _assert_node_lifecycle)
	renderer.add_assertion("select_after_death", _assert_select_after_death)
	renderer.add_assertion("move_cmd_integrity", _assert_move_cmd_integrity)


## Assertion 1: units are in correct team groups (0.5.10)
func _assert_team_groups() -> Dictionary:
	var red_ok = false
	var blue_ok = false
	for u in units:
		if not is_instance_valid(u):
			continue
		if u.team_name == "red":
			red_ok = u.is_in_group("team_red")
		elif u.team_name == "blue":
			blue_ok = u.is_in_group("team_blue")
	if red_ok and blue_ok:
		return {"status": "pass", "detail": "red∈team_red, blue∈team_blue"}
	else:
		return {"status": "fail", "detail": "red=%s blue=%s" % [str(red_ok), str(blue_ok)]}


## Assertion 2: teams converge after 180 frames (0.5.11)
func _assert_chase_convergence() -> Dictionary:
	var frame = frame_count
	# Record initial distance at frame 60
	if frame <= 5 and _cal_state["init_dist"] < 0:
		_cal_state["init_dist"] = _team_center_distance()
	if _cal_state["init_dist"] < 0:
		return {"status": "pending", "detail": "waiting for init snapshot"}
	if frame < 180:
		return {"status": "pending", "detail": "waiting (frame %d/180)" % frame}
	var dist_now = _team_center_distance()
	if dist_now < _cal_state["init_dist"]:
		return {"status": "pass", "detail": "converging: %.0f → %.0f" % [_cal_state["init_dist"], dist_now]}
	else:
		return {"status": "fail", "detail": "not converging: %.0f → %.0f" % [_cal_state["init_dist"], dist_now]}


## Assertion 3: at least 1 kill within 600 frames (0.5.12)
func _assert_combat_kills() -> Dictionary:
	if frame_count < 600:
		return {"status": "pending", "detail": "kills=%d (frame %d/600)" % [_kill_log.size(), frame_count]}
	if _kill_log.size() > 0:
		return {"status": "pass", "detail": "%d kills in %d frames" % [_kill_log.size(), frame_count]}
	else:
		return {"status": "fail", "detail": "0 kills after %d frames" % frame_count}


## Assertion 4: one side eliminated or significant casualties (0.5.12)
func _assert_battle_resolution() -> Dictionary:
	var total_killed = _kill_log.size()
	if _red_alive == 0 or _blue_alive == 0:
		var winner = "red" if _blue_alive == 0 else "blue"
		return {"status": "pass", "detail": "%s wins! %d kills, %dR/%dB alive" % [winner, total_killed, _red_alive, _blue_alive]}
	if total_killed >= 15:
		return {"status": "pass", "detail": "significant combat: %d kills, %dR/%dB alive" % [total_killed, _red_alive, _blue_alive]}
	return {"status": "pending", "detail": "%d kills, %dR/%dB alive" % [total_killed, _red_alive, _blue_alive]}


## Assertion 5: renderer snapshot contains combat summary fields (0.5.13)
func _assert_renderer_combat_data() -> Dictionary:
	if frame_count < 120:
		return {"status": "pending", "detail": "waiting for combat data (frame %d/120)" % frame_count}
	var snapshot = renderer.get_snapshot()
	if snapshot.is_empty():
		return {"status": "pending", "detail": "no snapshot yet"}
	# Verify set_extra data was passed through (check formatter output indirectly via extra fields)
	# The formatter uses _extra which contains red_alive, blue_alive, kill_count
	# We verify the snapshot has entity data with hp/team_name fields
	var entities = snapshot.get("entities", {})
	if entities.is_empty():
		return {"status": "pending", "detail": "no entities in snapshot"}
	# Check that entity data includes combat-relevant fields
	var has_hp = false
	var has_team = false
	for eid in entities:
		var data = entities[eid]
		if "hp" in data:
			has_hp = true
		if "team_name" in data:
			has_team = true
	if has_hp and has_team:
		return {"status": "pass", "detail": "snapshot has hp+team_name fields, %d entities" % entities.size()}
	else:
		return {"status": "fail", "detail": "missing fields: hp=%s team=%s" % [str(has_hp), str(has_team)]}


## Assertion 6: formatter text output contains combat summary (0.5.13/0.5.15)
func _assert_formatter_output() -> Dictionary:
	if frame_count < 65:
		return {"status": "pending", "detail": "waiting for first formatter tick (frame %d/65)" % frame_count}
	var output = renderer.last_output
	if output.is_empty():
		return {"status": "pending", "detail": "no formatter output yet"}
	# Verify output contains expected combat summary fields
	var has_alive = "alive" in output
	var has_kills = "kills=" in output
	if has_alive and has_kills:
		return {"status": "pass", "detail": "formatter output has kills+alive: %s" % output}
	elif has_alive and not has_kills:
		return {"status": "pending", "detail": "has alive but no kills yet: %s" % output}
	else:
		return {"status": "fail", "detail": "missing fields in: %s" % output}


## Assertion 7: no invalid refs in ref_holders (v2 lifecycle check)
func _assert_node_lifecycle() -> Dictionary:
	if frame_count < 300:
		return {"status": "pending", "detail": "waiting for combat (frame %d/300)" % frame_count}
	var health = renderer.get_health()
	if health.is_empty():
		return {"status": "pending", "detail": "no health data yet"}
	var total_invalid = health.get("total_invalid", 0)
	if total_invalid > 0:
		var details: Array[String] = []
		var holders = health.get("holders", {})
		for hname in holders:
			var h = holders[hname]
			if h.get("invalid", 0) > 0:
				details.append("%s:%d/%d" % [hname, h.get("invalid", 0), h.get("total", 0)])
		return {"status": "fail", "detail": "%d invalid refs: %s" % [total_invalid, ", ".join(details)]}
	return {"status": "pass", "detail": "all ref_holders clean"}


## Assertion 8: simulated box_select after deaths returns correct count (v2 interaction)
func _assert_select_after_death() -> Dictionary:
	if not _sim_player:
		return {"status": "pass", "detail": "no SimulatedPlayer configured"}
	var log = _sim_player.get_execution_log()
	# Find the second box_select (frame 300, after combat has started)
	var second_select: Dictionary = {}
	for entry in log:
		if entry.get("action") == "box_select":
			if not second_select.is_empty():
				# This is the second one
				second_select = entry
				break
			second_select = entry
	if second_select.is_empty():
		return {"status": "pending", "detail": "waiting for second box_select (frame 300)"}
	if second_select.get("success", false):
		# Verify: select count should equal alive count (red + blue)
		var alive = _red_alive + _blue_alive
		var sel_count = _sim_player.last_select_count
		if sel_count == alive:
			return {"status": "pass", "detail": "select=%d alive=%d (frame %d)" % [sel_count, alive, second_select.get("frame", 0)]}
		else:
			return {"status": "fail", "detail": "select=%d alive=%d mismatch" % [sel_count, alive]}
	else:
		return {"status": "fail", "detail": "second box_select failed"}


## Assertion 9: simulated right_click sends commands to valid units only (v2 interaction)
func _assert_move_cmd_integrity() -> Dictionary:
	if not _sim_player:
		return {"status": "pass", "detail": "no SimulatedPlayer configured"}
	var log = _sim_player.get_execution_log()
	# Find any right_click action
	var last_rc: Dictionary = {}
	for entry in log:
		if entry.get("action") == "right_click":
			last_rc = entry
	if last_rc.is_empty():
		return {"status": "pending", "detail": "waiting for right_click action"}
	if last_rc.get("success", false):
		var invalid = _sim_player.last_invalid_refs
		if invalid == 0:
			return {"status": "pass", "detail": "move_cmd ok, 0 invalid refs (frame %d)" % last_rc.get("frame", 0)}
		else:
			return {"status": "fail", "detail": "%d invalid refs in move targets" % invalid}
	else:
		return {"status": "fail", "detail": "right_click failed"}


func _team_center_distance() -> float:
	var red_center = Vector2.ZERO
	var blue_center = Vector2.ZERO
	var red_n = 0
	var blue_n = 0
	for u in units:
		if not is_instance_valid(u):
			continue
		if u.team_name == "red":
			red_center += u.global_position
			red_n += 1
		else:
			blue_center += u.global_position
			blue_n += 1
	if red_n == 0 or blue_n == 0:
		return 0.0
	red_center /= red_n
	blue_center /= blue_n
	return red_center.distance_to(blue_center)


# ─── Performance Report ──────────────────────────────────────────

func _perf_report() -> void:
	var elapsed = Time.get_ticks_msec() - start_time_msec
	var fps = float(frame_count) / (elapsed / 1000.0)
	print("[PERF] frames=%d units=%d elapsed_ms=%d avg_fps=%.1f" % [frame_count, units.size(), elapsed, fps])
