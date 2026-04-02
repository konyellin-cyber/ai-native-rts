extends "res://tests/scenes/combat_bootstrap.gd"
## kite_behavior bootstrap — 继承 CombatBootstrap，验证 kite 行为触发

func _register_assertions() -> void:
	## 基础战斗断言
	_renderer.add_assertion("battle_resolution", _assert_battle_resolution)

	## kite 专项断言：弓箭手在战斗过程中应进入 kite 状态
	_renderer.add_assertion("archer_kite", _assert_archer_kite)

	var assertions: Array = _config.get("assertions", [])
	if not assertions.is_empty():
		_renderer.get_calibrator().set_run_only(assertions)
		print("[COMBAT] run_only: %s" % str(assertions))


func _assert_archer_kite() -> Dictionary:
	## 检查是否有弓箭手正处于 kite 状态（flee_range 内有敌方且已触发后退）
	for unit in _units:
		if not is_instance_valid(unit):
			continue
		if unit.get("unit_type") == "archer" and unit.get("ai_state") == "kite":
			return {"status": "pass", "detail": "archer entered kite state"}
	return {"status": "pending", "detail": "no archer in kite yet"}
