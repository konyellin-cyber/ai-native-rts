extends RigidBody2D

## Phase 0 Ball
## Bouncing ball with collision detection and color-change feedback.
## State: "normal" or "colliding"
## Uses contact_monitor instead of body_entered signal for reliable detection.

signal ball_collided(ball_id: int, other_id: int, pos: Vector2)

var ball_id: int = 0
var default_radius: float = 20.0
var current_state: String = "normal"
var collision_count: int = 0
var _collision_flash_timer: float = 0.0
var _flash_duration: float = 0.15
var _prev_contact_count: int = 0


func _ready() -> void:
	# Enable contact monitoring for collision detection
	contact_monitor = true
	max_contacts_reported = 10


func _physics_process(delta: float) -> void:
	# Detect new collisions via contact count change
	var current_contacts = get_contact_count()
	if current_contacts > 0 and _prev_contact_count == 0:
		_flash_blue()
		collision_count += 1
	_prev_contact_count = current_contacts

	# Count down flash timer
	if _collision_flash_timer > 0:
		_collision_flash_timer -= delta
		if _collision_flash_timer <= 0:
			current_state = "normal"
			_set_visual_color(Color.RED)


func _flash_blue() -> void:
	current_state = "colliding"
	_collision_flash_timer = _flash_duration
	_set_visual_color(Color.BLUE)


func _set_visual_color(color: Color) -> void:
	# CircleVisual is a child Node2D, which contains a Line2D child
	var visual_container = get_node_or_null("CircleVisual")
	if visual_container:
		for child in visual_container.get_children():
			if child is Line2D:
				child.default_color = color
				return


func get_ball_state() -> Dictionary:
	return {
		"id": ball_id,
		"pos_x": roundf(position.x * 1000.0) / 1000.0,
		"pos_y": roundf(position.y * 1000.0) / 1000.0,
		"vel_x": roundf(linear_velocity.x * 1000.0) / 1000.0,
		"vel_y": roundf(linear_velocity.y * 1000.0) / 1000.0,
		"state": current_state,
		"collision_count": collision_count
	}
