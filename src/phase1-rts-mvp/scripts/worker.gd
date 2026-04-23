extends CharacterBody3D

## Phase 1 Worker — 采集单位（3D）
## States: idle → move_to_mine → harvesting → returning → delivering → idle
## 坐标约定：XZ 平面为地图平面，Y=0 为地面，velocity.y 恒为 0

var unit_id: int = 0
var unit_type: String = "worker"
var team_name: String = "red"
var move_speed: float = 120.0
var unit_radius: float = 6.0
var max_hp: float = 30.0
var hp: float = 30.0
var collision_count: int = 0

# Worker params (from config)
var carry_capacity: int = 10
var harvest_time: float = 1.5

var _agent: NavigationAgent3D
var _map_width: float = 2000.0
var _map_height: float = 1500.0
## nav_available: 运行时检测 NavigationServer3D 是否可用（headless 下为 false）。
## 为什么不用 _is_headless：两者语义不同，未来若 headless 导航修复可自动升级，不改代码。
var _nav_available: bool = false

# Worker state
var _state: String = "idle":
	set(v):
		_state = v
		ai_state = v
var ai_state: String = "idle"
var target_position: Vector3 = Vector3.ZERO  ## Current navigation target for AI Renderer
var carrying: float = 0.0
var _target_mine: Node = null
var _home_hq: Node = null
var _harvest_timer: float = 0.0
var _player_moving: bool = false

signal died(unit_id: int, team: String)


func setup(id: int, team: String, pos: Vector3, cfg: Dictionary, headless: bool, map_size: Vector2, home: Node) -> void:
	unit_id = id
	team_name = team
	position = pos
	unit_type = "worker"
	move_speed = float(cfg.speed)
	unit_radius = float(cfg.radius)
	max_hp = float(cfg.hp)
	hp = max_hp
	carry_capacity = int(cfg.carry_capacity)
	harvest_time = float(cfg.harvest_time)
	_map_width = map_size.x
	_map_height = map_size.y
	_home_hq = home
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
	agent.path_desired_distance = 15.0
	agent.target_desired_distance = 15.0
	agent.name = "NavAgent"
	add_child(agent)

	if not headless:
		_add_visual()


func _ready() -> void:
	_agent = $NavAgent
	add_to_group("team_%s" % team_name)
	add_to_group("units")
	_detect_nav_and_start.call_deferred()


func _detect_nav_and_start() -> void:
	## 检测 NavigationServer3D 是否可用，设置 _nav_available，然后启动采矿循环。
	## headless 下 iteration_id 永远为 0，nav 不可用，走直线 fallback。
	## window 下同步烘焙完成后 iteration_id > 0，nav 可用，走 NavigationAgent3D。
	var nav_map = get_world_3d().get_navigation_map()
	_nav_available = NavigationServer3D.map_get_iteration_id(nav_map) > 0
	_start_harvest_cycle()


func _physics_process(delta: float) -> void:
	if _state == "dead":
		return
	match _state:
		"idle":
			if not _player_moving:
				_start_harvest_cycle()
			else:
				if _is_at_target():
					_player_moving = false
				else:
					_move_along_path()
		"move_to_mine":
			_physics_move_to_mine()
		"harvesting":
			_physics_harvesting(delta)
		"returning":
			_physics_returning()
		"delivering":
			_deliver()


func _start_harvest_cycle() -> void:
	if _state == "dead":
		return
	_target_mine = _find_nearest_mine()
	if _target_mine == null:
		_state = "idle"
		return
	_state = "move_to_mine"
	_set_agent_target(_target_mine.global_position)


func _physics_move_to_mine() -> void:
	if not is_instance_valid(_target_mine) or _target_mine.amount <= 0:
		_target_mine = null
		_start_harvest_cycle()
		return
	if _is_at_target():
		_state = "harvesting"
		_harvest_timer = 0.0
		_target_mine.harvesters_count += 1
		return
	_move_along_path()


func _physics_harvesting(delta: float) -> void:
	if not is_instance_valid(_target_mine):
		_state = "returning"
		return

	if _target_mine.amount <= 0 or carrying >= carry_capacity:
		_target_mine.harvesters_count = maxi(0, _target_mine.harvesters_count - 1)
		_target_mine = null
		_state = "returning"
		if is_instance_valid(_home_hq):
			_set_agent_target(_home_hq.global_position)
		return

	_harvest_timer += delta
	var harvested = _target_mine.harvest(delta, harvest_time, carry_capacity, carrying)
	carrying += harvested
	if carrying >= carry_capacity:
		_target_mine.harvesters_count = maxi(0, _target_mine.harvesters_count - 1)
		_target_mine = null
		_state = "returning"
		if is_instance_valid(_home_hq):
			_set_agent_target(_home_hq.global_position)


func _physics_returning() -> void:
	if _is_at_target():
		_state = "delivering"
		return
	_move_along_path()


func _deliver() -> void:
	if not is_instance_valid(_home_hq):
		_state = "idle"
		return
	_home_hq.crystal += int(carrying)
	_home_hq.resource_changed.emit(_home_hq.crystal)
	carrying = 0.0
	_state = "idle"
	_start_harvest_cycle()


func _find_nearest_mine() -> Node:
	var mines = get_tree().get_nodes_in_group("minerals")
	var best: Node = null
	var best_dist: float = INF
	for m in mines:
		if not is_instance_valid(m) or m.amount <= 0:
			continue
		var d = global_position.distance_to(m.global_position)
		if d < best_dist:
			best_dist = d
			best = m
	return best


func take_damage(amount: float) -> void:
	if _state == "dead":
		return
	hp -= amount
	if hp <= 0:
		hp = 0
		_die()


func _die() -> void:
	if _state == "harvesting" and is_instance_valid(_target_mine):
		_target_mine.harvesters_count = maxi(0, _target_mine.harvesters_count - 1)
	_state = "dead"
	velocity = Vector3.ZERO
	died.emit(unit_id, team_name)
	queue_free.call_deferred()


func move_to(target_pos: Vector3) -> void:
	if _state == "harvesting" and is_instance_valid(_target_mine):
		_target_mine.harvesters_count = maxi(0, _target_mine.harvesters_count - 1)
		_target_mine = null
	_state = "idle"
	_player_moving = true
	_set_agent_target(target_pos)


func _set_agent_target(pos: Vector3) -> void:
	target_position = pos
	_agent.target_position = pos


func _is_at_target() -> bool:
	## 统一用距离判断到达，避免 nav path 尚未计算时 is_navigation_finished() 误报 true。
	return global_position.distance_to(target_position) < 15.0


func _move_along_path() -> void:
	## nav 可用时走 NavigationAgent3D 路径（绕障碍）；
	## path 尚未计算时（get_next_path_position 返回当前位置）回退直线，下帧自动切回。
	var dist = global_position.distance_to(target_position)
	if dist < 15.0:
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
		"carrying": carrying,
	}


func get_ai_state() -> String:
	return _state


func _add_visual() -> void:
	var mesh_inst = MeshInstance3D.new()
	var capsule = CapsuleMesh.new()
	capsule.radius = unit_radius
	capsule.height = unit_radius * 4.0
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.5, 0.2) if team_name == "red" else Color(0.2, 0.5, 0.8)
	capsule.material = mat
	mesh_inst.mesh = capsule
	mesh_inst.position = Vector3(0.0, unit_radius * 2.0, 0.0)
	add_child(mesh_inst)
