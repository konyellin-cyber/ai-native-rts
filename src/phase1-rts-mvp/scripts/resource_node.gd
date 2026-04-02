extends Area3D

## Resource Node — 矿点（3D）
## 职责：提供可采集资源，被 Worker 消耗
## 坐标约定：XZ 平面为地图平面，Y=0 为地面

signal depleted(node_id: String)

var node_id: String = ""
var amount: float = 5000
var max_amount: float = 5000
var harvesters_count: int = 0
var _is_headless: bool = false


func setup(id: String, pos: Vector3, amt: int, headless: bool) -> void:
	node_id = id
	position = pos
	amount = amt
	max_amount = amt
	_is_headless = headless
	name = node_id
	add_to_group("minerals")

	var sphere = SphereShape3D.new()
	sphere.radius = 30.0
	var col = CollisionShape3D.new()
	col.shape = sphere
	add_child(col)

	if not _is_headless:
		_add_visual()


func harvest(delta: float, harvest_time: float, capacity: int, current_carrying: float) -> float:
	if amount <= 0:
		return 0.0
	var rate = float(capacity) / harvest_time
	var to_harvest = minf(rate * delta, float(amount))
	to_harvest = minf(to_harvest, float(capacity) - current_carrying)
	if to_harvest <= 0:
		return 0.0
	amount -= to_harvest
	if amount <= 0:
		amount = 0
		depleted.emit(node_id)
		print("[MINE] %s depleted!" % node_id)
	return to_harvest


func get_unit_state() -> Dictionary:
	return {
		"amount": amount,
		"max_amount": max_amount,
		"harvesters": harvesters_count,
	}


func _add_visual() -> void:
	var mesh_inst = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 18.0
	sphere.height = 36.0
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 0.6)
	sphere.material = mat
	mesh_inst.mesh = sphere
	mesh_inst.position = Vector3(0.0, 18.0, 0.0)
	add_child(mesh_inst)
