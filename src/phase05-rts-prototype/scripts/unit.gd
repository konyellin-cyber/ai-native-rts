extends CharacterBody2D

## Phase 0.5 Unit — with combat
## States: wander → chase → attack → dead

var unit_id: int = 0
var team_name: String = "red"
var move_speed: float = 150.0
var unit_radius: float = 8.0
var max_hp: float = 100.0
var hp: float = 100.0
var collision_count: int = 0

# Combat params (set from config)
var attack_damage: float = 10.0
var attack_range: float = 30.0
var sight_range: float = 200.0
var attack_cooldown: float = 0.5

var _agent: NavigationAgent2D
var _nav_map: RID
var _map_width: float = 2000.0
var _map_height: float = 1500.0
var _nav_ready: bool = false
var _has_command: bool = false
var _command_frame: int = 0

# Combat state
var _state: String = "wander":  # wander / chase / attack / dead
	set(v):
		_state = v
		ai_state = v
var ai_state: String = "wander"  # Mirror of _state for external read
var _target: CharacterBody2D = null  # Current enemy target
var _attack_timer: float = 0.0  # Cooldown timer
var _enemy_group: String = ""  # "team_red" or "team_blue"

signal died(unit_id: int, team: String)


func _ready() -> void:
	_agent = $NavAgent
	_agent.velocity_computed.connect(_on_velocity_computed)
	_nav_map = get_world_2d().get_navigation_map()
	_enemy_group = "team_blue" if team_name == "red" else "team_red"
	add_to_group("team_%s" % team_name)
	add_to_group("units")
	_setup.call_deferred()


func _setup() -> void:
	var iter_id = NavigationServer2D.map_get_iteration_id(_nav_map)
	if iter_id == 0:
		NavigationServer2D.map_changed.connect(_on_map_changed)
		return
	_nav_ready = true
	_pick_new_target()


func _on_map_changed(_map_rid: RID) -> void:
	if _nav_ready:
		return
	var iter_id = NavigationServer2D.map_get_iteration_id(_nav_map)
	if iter_id > 0:
		NavigationServer2D.map_changed.disconnect(_on_map_changed)
		_nav_ready = true
		if _state == "wander":
			_pick_new_target()


func _physics_process(delta: float) -> void:
	if not _nav_ready or _state == "dead":
		return

	# Update attack cooldown
	if _attack_timer > 0:
		_attack_timer -= delta

	match _state:
		"wander":
			_physics_wander()
		"chase":
			_physics_chase()
		"attack":
			_physics_attack()


# ─── State: wander ─────────────────────────────────────────────────

func _physics_wander() -> void:
	# Check for nearby enemies
	var enemy = _find_closest_enemy()
	if enemy:
		_target = enemy
		_state = "chase"
		_set_agent_target(_target.global_position)
		return

	# If player issued a command, follow it
	if _has_command:
		if _agent.is_navigation_finished():
			_has_command = false
			_command_frame = 0
			return
		_move_along_path()
		_command_frame += 1
		return

	# Auto wander
	if _agent.is_navigation_finished():
		_pick_new_target()
		return
	_move_along_path()


# ─── State: chase ──────────────────────────────────────────────────

func _physics_chase() -> void:
	# Validate target
	if not is_instance_valid(_target) or _target._state == "dead":
		_target = null
		_state = "wander"
		_pick_new_target()
		return

	var dist = global_position.distance_to(_target.global_position)

	# In attack range → switch to attack
	if dist <= attack_range:
		_state = "attack"
		velocity = Vector2.ZERO
		return

	# Out of sight → back to wander
	if dist > sight_range * 1.5:
		_target = null
		_state = "wander"
		_pick_new_target()
		return

	# Keep chasing — update path periodically
	if _agent.is_navigation_finished() or _command_frame % 30 == 0:
		_set_agent_target(_target.global_position)
	_move_along_path()
	_command_frame += 1


# ─── State: attack ─────────────────────────────────────────────────

func _physics_attack() -> void:
	if not is_instance_valid(_target) or _target._state == "dead":
		# Target died or invalid — find new or wander
		_target = null
		var enemy = _find_closest_enemy()
		if enemy:
			_target = enemy
			_state = "chase"
			_set_agent_target(_target.global_position)
		else:
			_state = "wander"
			_pick_new_target()
		return

	var dist = global_position.distance_to(_target.global_position)

	# Target moved out of range → chase again
	if dist > attack_range * 1.2:
		_state = "chase"
		_set_agent_target(_target.global_position)
		return

	velocity = Vector2.ZERO

	# Attack on cooldown
	if _attack_timer <= 0:
		_target.take_damage(attack_damage)
		_attack_timer = attack_cooldown


# ─── Combat helpers ────────────────────────────────────────────────

func _find_closest_enemy() -> CharacterBody2D:
	var enemies = get_tree().get_nodes_in_group(_enemy_group)
	var closest: CharacterBody2D = null
	var closest_dist: float = sight_range

	for e in enemies:
		if not is_instance_valid(e) or e._state == "dead":
			continue
		var d = global_position.distance_to(e.global_position)
		if d < closest_dist:
			closest_dist = d
			closest = e

	return closest


func take_damage(amount: float) -> void:
	if _state == "dead":
		return
	hp -= amount
	if hp <= 0:
		hp = 0
		_die()


func _die() -> void:
	_state = "dead"
	velocity = Vector2.ZERO
	died.emit(unit_id, team_name)
	# Delay removal to let signal propagate
	queue_free.call_deferred()


# ─── Movement helpers ──────────────────────────────────────────────

func _set_agent_target(pos: Vector2) -> void:
	var on_nav = NavigationServer2D.map_get_closest_point(_nav_map, pos)
	_agent.target_position = on_nav


func _move_along_path() -> void:
	if _agent.is_navigation_finished():
		return
	var next_pos = _agent.get_next_path_position()
	var direction = global_position.direction_to(next_pos)
	velocity = direction * move_speed
	move_and_slide()


func _pick_new_target() -> void:
	var random_pos = Vector2(
		randf_range(100, _map_width - 100),
		randf_range(100, _map_height - 100)
	)
	var on_nav = NavigationServer2D.map_get_closest_point(_nav_map, random_pos)
	_agent.target_position = on_nav


## Public: move to a specific world position (player command)
func move_to(target_pos: Vector2) -> void:
	if not _nav_ready:
		return
	_has_command = true
	_command_frame = 0
	_target = null
	# If in combat, switch back to wander with command
	if _state == "chase" or _state == "attack":
		_state = "wander"
	var on_nav = NavigationServer2D.map_get_closest_point(_nav_map, target_pos)
	_agent.target_position = on_nav


func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()


## Public: state data for AI Renderer
func get_unit_state() -> Dictionary:
	return {
		"id": unit_id,
		"team": team_name,
		"pos_x": roundf(position.x * 100.0) / 100.0,
		"pos_y": roundf(position.y * 100.0) / 100.0,
		"vel_x": roundf(velocity.x * 100.0) / 100.0,
		"vel_y": roundf(velocity.y * 100.0) / 100.0,
		"hp": hp,
		"max_hp": max_hp,
		"state": _state,
		"collision_count": collision_count
	}


## Public: AI state name for Renderer
func get_ai_state() -> String:
	return _state
