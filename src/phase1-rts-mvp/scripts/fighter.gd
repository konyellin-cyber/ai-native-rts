extends CharacterBody3D

## Phase 1 Fighter — 战斗单位（3D）
## States: idle → wander → chase → attack → dead
## 坐标约定：XZ 平面为地图平面，Y=0 为地面，velocity.y 恒为 0

var unit_id: int = 0
var unit_type: String = "fighter"
var team_name: String = "red"
var move_speed: float = 150.0
var unit_radius: float = 8.0
var max_hp: float = 100.0
var hp: float = 100.0
var collision_count: int = 0

var _hit_flash_timer: float = 0.0   ## 受击白闪倒计时（秒）
var _body_mat: StandardMaterial3D = null  ## 单位主体材质引用
var _knockback: Vector3 = Vector3.ZERO    ## 当前击退速度

# Combat params (from config)
var attack_damage: float = 10.0
var attack_range: float = 30.0
var sight_range: float = 200.0
var attack_cooldown: float = 0.5

var _agent: NavigationAgent3D
var _map_width: float = 2000.0
var _map_height: float = 1500.0
## nav_available: 运行时检测 NavigationServer3D 是否可用（headless 下为 false）。
var _nav_available: bool = false
var _has_command: bool = false
var _command_frame: int = 0

# Combat state
var _state: String = "idle":
	set(v):
		_state = v
		ai_state = v
var ai_state: String = "idle"
var _target: Node = null
var _attack_timer: float = 0.0
var _enemy_group: String = ""
var _home_hq: Node = null
var _patrol_radius: float = 150.0
var target_position: Vector3 = Vector3.ZERO  ## Current navigation target for AI Renderer
var has_command: bool = false  ## 镜像 _has_command，供 AI Renderer 采样

signal died(unit_id: int, team: String)


func setup(id: int, team: String, pos: Vector3, cfg: Dictionary, headless: bool, map_size: Vector2, home: Node) -> void:
	unit_id = id
	team_name = team
	position = pos
	unit_type = "fighter"
	move_speed = float(cfg.speed)
	unit_radius = float(cfg.radius)
	max_hp = float(cfg.hp)
	hp = max_hp
	attack_damage = float(cfg.attack_damage)
	attack_range = float(cfg.attack_range)
	sight_range = float(cfg.sight_range)
	attack_cooldown = float(cfg.attack_cooldown)
	_map_width = map_size.x
	_map_height = map_size.y
	_home_hq = home
	name = "Unit_%s_%d" % [team, id]

	collision_layer = 1
	collision_mask = 2  # 与 layer=2 的墙/障碍物碰撞，不碰 layer=1 地面

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

	_enemy_group = "team_blue" if team_name == "red" else "team_red"


func _ready() -> void:
	_agent = $NavAgent
	add_to_group("team_%s" % team_name)
	add_to_group("units")
	_detect_nav.call_deferred()


func _detect_nav() -> void:
	## 检测 NavigationServer3D 是否可用，设置 _nav_available。
	## headless 下 iteration_id 永远为 0，走直线 fallback。
	var nav_map = get_world_3d().get_navigation_map()
	_nav_available = NavigationServer3D.map_get_iteration_id(nav_map) > 0


func _physics_process(delta: float) -> void:
	if _state == "dead":
		return
	## 受击白闪恢复
	if _hit_flash_timer > 0:
		_hit_flash_timer -= delta
		if _hit_flash_timer <= 0 and _body_mat:
			_body_mat.albedo_color = Color(0.9, 0.3, 0.3) if team_name == "red" else Color(0.3, 0.3, 0.9)
	## 击退衰减
	if _knockback.length_squared() > 1.0:
		velocity = _knockback
		move_and_slide()
		_knockback = _knockback.lerp(Vector3.ZERO, 0.3)
		return
	if _attack_timer > 0:
		_attack_timer -= delta
	match _state:
		"idle":
			_state = "wander"
			_pick_new_target()
		"wander":
			_physics_wander()
		"chase":
			_physics_chase()
		"attack":
			_physics_attack()


func _physics_wander() -> void:
	var enemy = _find_closest_enemy()
	if enemy:
		_target = enemy
		_state = "chase"
		_set_agent_target(_target.global_position)
		return

	if _has_command:
		if _is_at_target():
			_has_command = false
			has_command = false
			_command_frame = 0
			_state = "idle"
			velocity = Vector3.ZERO
			return
		_move_along_path()
		_command_frame += 1
		return

	if _is_at_target():
		_pick_new_target()
		return
	_move_along_path()


func _physics_chase() -> void:
	if not is_instance_valid(_target) or (_target.has_method("get") and _target.get("_state") == "dead"):
		_target = null
		_state = "wander"
		_pick_new_target()
		return

	var dist = global_position.distance_to(_target.global_position)

	if dist <= attack_range:
		_state = "attack"
		velocity = Vector3.ZERO
		return

	if dist > sight_range * 1.5:
		_target = null
		_state = "wander"
		_pick_new_target()
		return

	if _is_at_target() or _command_frame % 30 == 0:
		_set_agent_target(_target.global_position)
	_move_along_path()
	_command_frame += 1


func _physics_attack() -> void:
	if not is_instance_valid(_target) or (_target.has_method("get") and _target.get("_state") == "dead"):
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

	if dist > attack_range * 1.2:
		_state = "chase"
		_set_agent_target(_target.global_position)
		return

	velocity = Vector3.ZERO

	if _attack_timer <= 0:
		_target.take_damage(attack_damage)
		_attack_timer = attack_cooldown


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


func take_damage(amount: float) -> void:
	if _state == "dead":
		return
	hp -= amount
	## 受击白闪
	if _body_mat:
		_body_mat.albedo_color = Color(1.0, 1.0, 1.0)
		_hit_flash_timer = 0.1
	if hp <= 0:
		hp = 0
		_die()


func take_damage_from(amount: float, from_pos: Vector3) -> void:
	## 带来源方向的伤害接口，用于箭矢击退。
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


func _set_agent_target(pos: Vector3) -> void:
	target_position = pos
	_agent.target_position = pos


func _is_at_target() -> bool:
	## 统一用距离判断到达，避免 nav path 尚未计算时 is_navigation_finished() 误报 true。
	return global_position.distance_to(target_position) < 20.0


func _move_along_path() -> void:
	var dist = global_position.distance_to(target_position)
	if dist < 20.0:
		velocity = Vector3.ZERO
		return
	if _nav_available:
		var next_pos = _agent.get_next_path_position()
		## nav path 尚未计算时 get_next_path_position() 返回当前位置，方向为零向量；
		## 此时回退到直线移动，下一帧 path 就绪后自动切回 nav 路径。
		var nav_dir = global_position.direction_to(next_pos)
		if nav_dir.length_squared() < 0.01:
			nav_dir = global_position.direction_to(target_position)
		velocity = Vector3(nav_dir.x, 0.0, nav_dir.z) * move_speed
	else:
		var dir = global_position.direction_to(target_position)
		velocity = Vector3(dir.x, 0.0, dir.z) * move_speed
	move_and_slide()


func _pick_new_target() -> void:
	## 以当前位置为中心随机游荡，避免在 home HQ 附近循环。
	## 为什么不用 _home_hq：fighter 被命令推进后应就近游荡探索，
	## 否则命令完成后会飞回 home HQ 附近，永远遇不到敌方。
	var center = global_position
	var rx = randf_range(-_patrol_radius, _patrol_radius)
	var rz = randf_range(-_patrol_radius, _patrol_radius)
	var random_pos = Vector3(
		clampf(center.x + rx, 50.0, _map_width - 50.0),
		0.0,
		clampf(center.z + rz, 50.0, _map_height - 50.0)
	)
	_set_agent_target(random_pos)


func move_to(target_pos: Vector3) -> void:
	_has_command = true
	has_command = true
	_command_frame = 0
	_target = null
	_state = "wander"
	_set_agent_target(target_pos)


func get_unit_state() -> Dictionary:
	return {
		"id": unit_id,
		"team": team_name,
		"type": unit_type,
		"pos_x": roundf(position.x * 100.0) / 100.0,
		"pos_z": roundf(position.z * 100.0) / 100.0,
		"hp": hp,
		"max_hp": max_hp,
		"state": _state,
	}


func get_ai_state() -> String:
	return _state


func _add_visual() -> void:
	var mesh_inst = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = unit_radius
	cylinder.bottom_radius = unit_radius
	cylinder.height = unit_radius * 3.0
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.3, 0.3) if team_name == "red" else Color(0.3, 0.3, 0.9)
	cylinder.material = mat
	mesh_inst.mesh = cylinder
	mesh_inst.position = Vector3(0.0, unit_radius * 1.5, 0.0)
	_body_mat = mat  ## 保存引用用于受击白闪
	add_child(mesh_inst)
