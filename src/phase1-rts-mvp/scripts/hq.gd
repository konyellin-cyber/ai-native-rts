extends StaticBody3D

## HQ (Headquarters) — 基地建筑（3D）
## 职责：资源存储、生产队列、胜利条件、单位出生点
## 坐标约定：XZ 平面为地图平面，Y=0 为地面

signal hq_destroyed(team_name: String)
signal unit_produced(unit_type: String, team_name: String)
signal resource_changed(crystal: int)

var team_name: String = ""
var crystal: int = 0
var max_hp: int = 500
var hp: int = 500
var hq_radius: float = 40.0

# Production queue
var _queue: Array[Dictionary] = []  # [{type: String, time_left: float}]
var _producing: String = ""
var _production_timer: float = 0.0
var _is_headless: bool = false


func setup(team: String, pos: Vector3, config: Dictionary, headless: bool) -> void:
	team_name = team
	position = pos
	max_hp = config.hp
	hp = config.hp
	crystal = config.get("initial_crystal", 200)
	hq_radius = float(config.radius)
	_is_headless = headless
	name = "HQ_%s" % team

	collision_layer = 1
	collision_mask = 0

	var box = BoxShape3D.new()
	box.size = Vector3(hq_radius * 2.0, 20.0, hq_radius * 2.0)
	var col = CollisionShape3D.new()
	col.shape = box
	add_child(col)

	if not _is_headless:
		_add_visual()


func get_unit_state() -> Dictionary:
	return {
		"team_name": team_name,
		"hp": hp,
		"max_hp": max_hp,
		"crystal": crystal,
		"queue_size": _queue.size(),
		"producing": _producing,
	}


func enqueue(unit_type: String, cost: int, time: float) -> bool:
	if crystal < cost:
		return false
	crystal -= cost
	_queue.append({"type": unit_type, "time_left": time})
	resource_changed.emit(crystal)
	return true


func take_damage(amount: int) -> void:
	hp -= amount
	if hp <= 0:
		hp = 0
		hq_destroyed.emit(team_name)
		print("[HQ] %s destroyed!" % team_name)


func _physics_process(delta: float) -> void:
	if _queue.is_empty():
		return

	_production_timer += delta
	if _production_timer >= _queue[0].time_left:
		var item = _queue.pop_front()
		_production_timer = 0.0
		_producing = item.type
		_spawn_unit(item.type)
		_producing = ""
	elif _producing != _queue[0].type:
		_producing = _queue[0].type


func _spawn_unit(unit_type: String) -> void:
	unit_produced.emit(unit_type, team_name)
	print("[HQ] %s produced %s (queue: %d remaining)" % [team_name, unit_type, _queue.size()])


func _add_visual() -> void:
	var mesh_inst = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(hq_radius * 2.0, 20.0, hq_radius * 2.0)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.RED if team_name == "red" else Color.BLUE
	box.material = mat
	mesh_inst.mesh = box
	mesh_inst.position = Vector3(0.0, 10.0, 0.0)  # 顶面在 Y=20，底面在 Y=0
	add_child(mesh_inst)
