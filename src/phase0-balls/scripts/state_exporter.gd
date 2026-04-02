extends Node

## Phase 0 State Exporter
## Reads all ball states each physics frame and exports to JSON files.
## Designed for AI debug: structured data == AI's eyes into the game.

var export_dir: String = "res://frames/"
var export_interval: int = 1
var _frame_count: int = 0
var _balls: Array = []


func _ready() -> void:
	# Defer ball collection to ensure all balls are added
	await get_tree().process_frame
	_collect_balls()


func _collect_balls() -> void:
	var parent = get_parent()
	for child in parent.get_children():
		if child is RigidBody2D and child.has_method("get_ball_state"):
			_balls.append(child)
	print("[EXPORTER] Tracking %d balls" % _balls.size())


func _physics_process(_delta: float) -> void:
	_frame_count += 1

	if _frame_count % export_interval != 0:
		return

	var data = _build_frame_data()
	_write_frame(data)


func _build_frame_data() -> Dictionary:
	var ball_states = []
	for ball in _balls:
		if is_instance_valid(ball) and ball.has_method("get_ball_state"):
			ball_states.append(ball.get_ball_state())

	return {
		"tick": _frame_count,
		"timestamp": Time.get_ticks_usec(),
		"balls": ball_states
	}


func _write_frame(data: Dictionary) -> void:
	var abs_dir = ProjectSettings.globalize_path(export_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)

	var filename = "frame_%06d.json" % data.tick
	var filepath = abs_dir.path_join(filename)

	var file = FileAccess.open(filepath, FileAccess.WRITE)
	if file == null:
		push_error("[EXPORTER] Failed to write: %s" % filepath)
		return

	var json_string = JSON.stringify(data, "\t")
	file.store_string(json_string)
	file.close()


## Public: get current frame count (for external use)
func get_frame_count() -> int:
	return _frame_count
