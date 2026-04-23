extends "res://scripts/base_unit.gd"

## Phase 10 Archer — 纯远程单位（3D）
## States: idle → wander → chase → shoot → kite → dead
##
## 攻击流程：
##   sight_range 内发现敌方 → chase 靠近 shoot_range → shoot（向 ArrowManager 请求发射）→
##   敌方进入 flee_range → kite（后退同时继续攻击）
##
## kite 设计原则：
##   - 保持距离在 [flee_range, shoot_range] 区间
##   - 每次攻击后判断目标距离，过近则后退
##   - 后退方向：从目标到自身的方向
##
## 依赖：
##   - ArrowManager 节点（通过 setup() 传入引用）
##   - ArrowManager.fire(origin, direction, damage, max_range, owner_team)

var move_speed: float = 120.0
var unit_radius: float = 7.0

# Ranged combat params (from config)
var attack_damage: float = 15.0
var shoot_range: float = 160.0     ## 开始射击的距离
var flee_range: float = 80.0       ## 触发 kite 后退的距离（敌方过近）
var sight_range: float = 220.0     ## 视野范围
var attack_cooldown: float = 1.2   ## 两次射箭间隔（秒）
var arrow_speed: float = 600.0     ## 箭矢速度（传给 ArrowManager）

var _agent: NavigationAgent3D
var _map_width: float = 2000.0
var _map_height: float = 1500.0
var _nav_available: bool = false

## Combat state
var _target: Node = null
var _attack_timer: float = 0.0
var _enemy_group: String = ""
var _arrow_manager: Node = null    ## ArrowManager 引用，setup() 时注入

var target_position: Vector3 = Vector3.ZERO


func setup(
	id: int,
	team: String,
	pos: Vector3,
	cfg: Dictionary,
	headless: bool,
	map_size: Vector2,
	_home_hq: Node,    ## 战斗场景无基地，接受 null
	arrow_manager: Node
) -> void:
	unit_id = id
	team_name = team
	position = pos
	unit_type = "archer"
	move_speed = float(cfg.get("speed", 120.0))
	unit_radius = float(cfg.get("radius", 7.0))
	max_hp = float(cfg.get("hp", 60.0))
	hp = max_hp
	attack_damage = float(cfg.get("attack_damage", 15.0))
	shoot_range = float(cfg.get("shoot_range", 160.0))
	flee_range = float(cfg.get("flee_range", 80.0))
	sight_range = float(cfg.get("sight_range", 220.0))
	attack_cooldown = float(cfg.get("attack_cooldown", 1.2))
	arrow_speed = float(cfg.get("arrow_speed", 600.0))
	_map_width = map_size.x
	_map_height = map_size.y
	_arrow_manager = arrow_manager
	name = "Unit_%s_%d" % [team, id]

	collision_layer = 1
	collision_mask = 2 | 4  # layer=2 墙/障碍物，layer=4 哑兵（主战推哑兵）

	var capsule = CapsuleShape3D.new()
	capsule.radius = unit_radius
	capsule.height = unit_radius * 2.0
	var col = CollisionShape3D.new()
	col.shape = capsule
	add_child(col)

	var agent = NavigationAgent3D.new()
	agent.path_desired_distance = 20.0
	agent.target_desired_distance = 20.0
	agent.name = "NavAgent"
	add_child(agent)

	if not headless:
		_add_visual()

	_idle_color = Color(0.2, 0.7, 0.2) if team == "red" else Color(0.1, 0.9, 0.5)
	_enemy_group = "team_blue" if team_name == "red" else "team_red"


func _ready() -> void:
	_agent = $NavAgent
	add_to_group("team_%s" % team_name)
	add_to_group("units")
	_detect_nav.call_deferred()


func _detect_nav() -> void:
	var nav_map = get_world_3d().get_navigation_map()
	_nav_available = NavigationServer3D.map_get_iteration_id(nav_map) > 0


func _physics_process(delta: float) -> void:
	if _state == "dead":
		return
	if _process_combat_effects(delta):
		return
	if _attack_timer > 0:
		_attack_timer -= delta
	match _state:
		"idle":
			_state = "wander"
			_pick_wander_target()
		"wander":
			_physics_wander()
		"chase":
			_physics_chase()
		"shoot":
			_physics_shoot(delta)
		"kite":
			_physics_kite(delta)


func _physics_wander() -> void:
	var enemy = _find_closest_enemy()
	if enemy:
		_target = enemy
		_state = "chase"
		_set_agent_target(_target.global_position)
		return

	if _is_at_target():
		_pick_wander_target()
		return
	_move_along_path()


func _physics_chase() -> void:
	if not _target_alive():
		_target = null
		_state = "wander"
		_pick_wander_target()
		return

	var dist = global_position.distance_to(_target.global_position)

	if dist > sight_range * 1.5:
		## 目标跑出视野，放弃
		_target = null
		_state = "wander"
		_pick_wander_target()
		return

	if dist <= flee_range:
		## 目标过近，立即 kite
		_state = "kite"
		return

	if dist <= shoot_range:
		## 进入射程，切换到 shoot
		_state = "shoot"
		velocity = Vector3.ZERO
		return

	## 继续靠近
	_set_agent_target(_target.global_position)
	_move_along_path()


func _physics_shoot(_delta: float) -> void:
	if not _target_alive():
		_target = null
		_state = "wander"
		_pick_wander_target()
		return

	var dist = global_position.distance_to(_target.global_position)

	if dist <= flee_range:
		## 目标进入 kite 触发距离
		_state = "kite"
		return

	if dist > shoot_range * 1.1:
		## 目标跑远了，重新 chase
		_state = "chase"
		_set_agent_target(_target.global_position)
		return

	velocity = Vector3.ZERO

	if _attack_timer <= 0:
		_fire_at(_target)
		_attack_timer = attack_cooldown


func _physics_kite(_delta: float) -> void:
	if not _target_alive():
		_target = null
		_state = "wander"
		_pick_wander_target()
		return

	var dist = global_position.distance_to(_target.global_position)

	## 已经保持了安全距离，回到 shoot
	if dist >= flee_range * 1.5:
		_state = "shoot"
		velocity = Vector3.ZERO
		return

	## 后退：每帧直接设置 velocity，不依赖目标点（避免到达目标后停止）
	## kite 速度比 move_speed 略高，保证能逃开追击速度等于自身的敌人
	var flee_dir = (global_position - _target.global_position)
	flee_dir.y = 0.0
	if flee_dir.length_squared() < 0.01:
		flee_dir = Vector3(1.0, 0.0, 0.0)  ## 重叠时随机一个方向
	flee_dir = flee_dir.normalized()

	var next_pos = global_position + flee_dir * move_speed * _delta * 10.0
	## 到达地图边界时转向：反转 X 或 Z 分量绕开边界
	if next_pos.x < 50.0 or next_pos.x > _map_width - 50.0:
		flee_dir.x *= -1.0
	if next_pos.z < 50.0 or next_pos.z > _map_height - 50.0:
		flee_dir.z *= -1.0

	velocity = flee_dir * move_speed
	move_and_slide()

	## kite 时也可以射击（边跑边射）
	if _attack_timer <= 0 and dist <= shoot_range:
		_fire_at(_target)
		_attack_timer = attack_cooldown


func _fire_at(target: Node) -> void:
	if _arrow_manager == null or not is_instance_valid(_arrow_manager):
		return

	## 计算抛物线发射速度：
	## 已知水平距离 d、重力 g、水平速度 vx（= arrow_speed），
	## 飞行时间 t = d / vx，
	## 要使箭矢在 t 时刻落回 Y=0（目标高度），
	## 需要初始纵速 vy = g*t/2（使弧顶在 t/2，落点在 t）
	var gravity: float = 2400.0
	var origin = global_position + Vector3(0.0, 10.0, 0.0)  ## 弓箭手手部高度
	var target_pos = target.global_position
	var xz_diff = Vector2(target_pos.x - origin.x, target_pos.z - origin.z)
	var xz_dist = xz_diff.length()

	if xz_dist < 1.0:
		return  ## 目标太近，不射

	var xz_dir = Vector3(xz_diff.x, 0.0, xz_diff.y).normalized()
	var t = xz_dist / arrow_speed         ## 水平飞行时间
	var vy = gravity * t / 2.0            ## 使弹道在飞行时间内落回同一高度的初始纵速

	var velocity = xz_dir * arrow_speed + Vector3(0.0, vy, 0.0)
	_arrow_manager.fire(origin, velocity, attack_damage, shoot_range, team_name)


func _find_closest_enemy() -> Node:
	var enemies = get_tree().get_nodes_in_group(_enemy_group)
	var closest: Node = null
	var closest_dist: float = sight_range

	for e in enemies:
		if not is_instance_valid(e):
			continue
		if e.has_method("get") and e.get("_state") == "dead":
			continue
		var d = global_position.distance_to(e.global_position)
		if d < closest_dist:
			closest_dist = d
			closest = e
	return closest


func _target_alive() -> bool:
	if not is_instance_valid(_target):
		return false
	if _target.has_method("get") and _target.get("_state") == "dead":
		return false
	return true


func _set_agent_target(pos: Vector3) -> void:
	target_position = pos
	_agent.target_position = pos


func _is_at_target() -> bool:
	return global_position.distance_to(target_position) < 25.0


func _move_along_path() -> void:
	var dist = global_position.distance_to(target_position)
	if dist < 25.0:
		velocity = Vector3.ZERO
		return
	if _nav_available:
		var next_pos = _agent.get_next_path_position()
		var nav_dir = global_position.direction_to(next_pos)
		if nav_dir.length_squared() < 0.01:
			nav_dir = global_position.direction_to(target_position)
		velocity = Vector3(nav_dir.x, 0.0, nav_dir.z) * move_speed
	else:
		var dir = global_position.direction_to(target_position)
		velocity = Vector3(dir.x, 0.0, dir.z) * move_speed
	move_and_slide()


func _pick_wander_target() -> void:
	var rx = randf_range(-150.0, 150.0)
	var rz = randf_range(-150.0, 150.0)
	var pos = Vector3(
		clampf(global_position.x + rx, 50.0, _map_width - 50.0),
		0.0,
		clampf(global_position.z + rz, 50.0, _map_height - 50.0)
	)
	_set_agent_target(pos)


func _add_visual() -> void:
	var mesh_inst = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = unit_radius
	cylinder.bottom_radius = unit_radius
	cylinder.height = unit_radius * 3.0
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.7, 0.2) if team_name == "red" else Color(0.1, 0.9, 0.5)
	cylinder.material = mat
	mesh_inst.mesh = cylinder
	mesh_inst.position = Vector3(0.0, unit_radius * 1.5, 0.0)
	_body_mat = mat  ## 保存引用用于受击白闪
	add_child(mesh_inst)
