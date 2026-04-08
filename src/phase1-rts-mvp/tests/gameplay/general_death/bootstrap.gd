extends "res://tests/gameplay_bootstrap.gd"

## general_death bootstrap
## 场景：将领 HP=1，第一帧 take_damage(999) → HP 归零
## 断言：general_died 信号触发 + 节点从场景树移除

var _general: CharacterBody3D = null
var _signal_received: bool = false
var _signal_team: String = ""
const _DAMAGE_FRAME = 2  ## 第 2 帧造成伤害，确保 _ready 已执行


func _post_spawn() -> void:
	if _units.size() > 0:
		_general = _units[0]
		## 监听 general_died 信号
		_general.general_died.connect(func(team_name: String):
			_signal_received = true
			_signal_team = team_name
			print("[DEATH] general_died signal received, team=%s" % team_name)
		)


func _register_assertions() -> void:
	_renderer.add_assertion("general_died_signal", _assert_signal_received)
	_renderer.add_assertion("general_node_removed", _assert_node_removed)
	_renderer.get_calibrator().set_run_only(["general_died_signal", "general_node_removed"])


func _physics_process(delta: float) -> void:
	## 在第 _DAMAGE_FRAME 帧对将领造成致命伤害
	if _frame_count == _DAMAGE_FRAME and _general != null and is_instance_valid(_general):
		print("[DEATH] Dealing fatal damage at frame %d" % _frame_count)
		_general.take_damage(9999.0)
	super._physics_process(delta)


func _assert_signal_received() -> Dictionary:
	if _signal_received:
		return {"status": "pass", "detail": "general_died emitted, team=%s" % _signal_team}
	return {"status": "pending", "detail": "signal not yet received"}


func _assert_node_removed() -> Dictionary:
	if _signal_received and (not is_instance_valid(_general) or _general == null):
		return {"status": "pass", "detail": "general node removed from scene"}
	if not _signal_received:
		return {"status": "pending", "detail": "waiting for death signal first"}
	return {"status": "pending", "detail": "node still valid (queue_free pending)"}
