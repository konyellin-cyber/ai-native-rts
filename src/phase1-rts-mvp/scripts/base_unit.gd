class_name BaseUnit
extends CharacterBody3D

## 所有战斗单位的公共基类。
## 封装受击白闪、击退、伤害处理、死亡逻辑。
## 子类在 setup() 中设置 _idle_color、unit_id、team_name、hp、max_hp。

var unit_id: int = 0
var unit_type: String = ""
var team_name: String = "red"
var hp: float = 100.0
var max_hp: float = 100.0

var _state: String = "idle":
	set(v):
		_state = v
		ai_state = v
var ai_state: String = "idle"

var _hit_flash_timer: float = 0.0
var _body_mat: StandardMaterial3D = null
var _knockback: Vector3 = Vector3.ZERO
## 受击白闪结束后恢复的颜色，子类在 setup() 时按 team_name 赋值。
var _idle_color: Color = Color(1.0, 1.0, 1.0)

signal died(unit_id: int, team: String)


func take_damage(amount: float) -> void:
	if _state == "dead":
		return
	hp -= amount
	if _body_mat:
		_body_mat.albedo_color = Color(1.0, 1.0, 1.0)
		_hit_flash_timer = 0.1
	if hp <= 0:
		hp = 0
		_die()


func take_damage_from(amount: float, from_pos: Vector3) -> void:
	if _state == "dead":
		return
	var dir = (global_position - from_pos)
	dir.y = 0.0
	if dir.length_squared() > 0.01:
		_knockback = dir.normalized() * 400.0
	take_damage(amount)


func _die() -> void:
	_state = "dead"
	velocity = Vector3.ZERO
	died.emit(unit_id, team_name)
	queue_free.call_deferred()


## 处理受击白闪和击退，返回 true 表示本帧被击退消耗（调用方应跳过正常移动）。
func _process_combat_effects(delta: float) -> bool:
	if _hit_flash_timer > 0:
		_hit_flash_timer -= delta
		if _hit_flash_timer <= 0 and _body_mat:
			_body_mat.albedo_color = _idle_color
	if _knockback.length_squared() > 1.0:
		velocity = _knockback
		move_and_slide()
		_knockback = _knockback.lerp(Vector3.ZERO, 0.3)
		return true
	return false
