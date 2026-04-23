extends "res://scripts/dummy_soldier.gd"
class_name ArcherSoldier

## Phase 20 弓箭手士兵 — 继承 DummySoldier 的全部行军逻辑
## 到达横阵槽位 freeze 后，切换为战斗状态：自动攻击射程内最近敌人

var _hp: float = 60.0
var _max_hp: float = 60.0
var _attack_damage: float = 15.0
var _shoot_range: float = 160.0
var _attack_cooldown: float = 1.2
var _arrow_speed: float = 600.0
var _enemy_group: String = ""
var _arrow_manager: Node = null
var _attack_timer: float = 0.0
var _is_dead: bool = false

## 覆盖 setup，额外读取弓箭手参数
func setup_archer(general: Node, index: int, total: int, cfg: Dictionary,
				  headless: bool, archer_cfg: Dictionary, arrow_manager: Node,
				  enemy_group: String) -> void:
	setup(general, index, total, cfg, headless)
	name = "Archer_%d" % index

	_hp = float(archer_cfg.get("hp", 60.0))
	_max_hp = _hp
	_attack_damage = float(archer_cfg.get("attack_damage", 15.0))
	_shoot_range = float(archer_cfg.get("shoot_range", 160.0))
	_attack_cooldown = float(archer_cfg.get("attack_cooldown", 1.2))
	_arrow_speed = float(archer_cfg.get("arrow_speed", 600.0))
	_arrow_manager = arrow_manager
	_enemy_group = enemy_group

	## 视觉颜色覆盖
	if not headless:
		_override_color()


func _override_color() -> void:
	## 找到 MeshInstance3D 子节点并修改颜色
	for child in get_children():
		if child is MeshInstance3D:
			var mat = StandardMaterial3D.new()
			var team = _general.get("team_name") if is_instance_valid(_general) else "red"
			## 弓箭手比哑兵颜色稍浅，以示区别
			if team == "red":
				mat.albedo_color = Color(0.9, 0.3, 0.1)
			else:
				mat.albedo_color = Color(0.1, 0.4, 0.9)
			if child.mesh:
				child.mesh.material = mat
			break


## 覆盖 _physics_process：行军逻辑完全继承，战斗逻辑独立运行（不依赖 freeze）
func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	## 继承行军逻辑
	super._physics_process(delta)

	## 战斗逻辑：行军中和横阵中均可攻击，不检查 freeze 状态
	if _arrow_manager == null or not is_instance_valid(_arrow_manager):
		return

	_attack_timer -= delta
	if _attack_timer > 0.0:
		return

	var target = _find_nearest_enemy()
	if target == null:
		return

	_attack_timer = _attack_cooldown
	_shoot_at(target)


func _find_nearest_enemy() -> Node:
	var best: Node = null
	var best_dist := INF
	for enemy in get_tree().get_nodes_in_group(_enemy_group):
		if not is_instance_valid(enemy):
			continue
		## 跳过已死亡（兼容 _is_dead 和 _state=="dead" 两种方式）
		if enemy.get("_is_dead") == true:
			continue
		if enemy.get("_state") == "dead":
			continue
		var d = global_position.distance_to(enemy.global_position)
		if d <= _shoot_range and d < best_dist:
			best_dist = d
			best = enemy
	return best


func _shoot_at(target: Node) -> void:
	## 抛物线弹道：复用 archer.gd 的计算方式
	## 已知水平距离 d、重力 g、水平速度 arrow_speed，
	## 飞行时间 t = d / arrow_speed，初始纵速 vy = g*t/2
	var gravity: float = 2400.0
	var origin = global_position + Vector3(0.0, _collision_radius * 1.5, 0.0)
	var target_pos = target.global_position
	var xz_diff = Vector2(target_pos.x - origin.x, target_pos.z - origin.z)
	var xz_dist = xz_diff.length()
	if xz_dist < 1.0:
		return
	var xz_dir = Vector3(xz_diff.x, 0.0, xz_diff.y).normalized()
	var t = xz_dist / _arrow_speed
	var vy = gravity * t / 2.0
	var vel = xz_dir * _arrow_speed + Vector3(0.0, vy, 0.0)

	var team = _general.get("team_name") if is_instance_valid(_general) else "red"
	_arrow_manager.fire(origin, vel, _attack_damage, _shoot_range, team)


func take_damage(amount: float) -> void:
	if _is_dead:
		return
	_hp -= amount
	if _hp <= 0.0:
		_die()


func _die() -> void:
	_is_dead = true
	linear_velocity = Vector3.ZERO
	freeze = true
	## 视觉标记死亡（变灰）
	for child in get_children():
		if child is MeshInstance3D:
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.3, 0.3, 0.3, 0.5)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			if child.mesh:
				child.mesh.material = mat
			break
	## 0.5 秒后移出场景
	await get_tree().create_timer(0.5).timeout
	if is_instance_valid(self):
		queue_free()
