extends Node3D

## Map Generator — 生成地面、边界墙、障碍物、NavigationMesh（3D）
## 从 config.json 读取布局，代码生成所有地图元素。
## 坐标约定：XZ 平面为地图平面，Y=0 为地面高度。

signal navigation_ready

var map_size: Vector2 = Vector2(2000, 1500)
var is_headless: bool = false


func setup(config: Dictionary, headless: bool) -> void:
	is_headless = headless
	map_size = Vector2(float(config.map.width), float(config.map.height))


func generate(config: Dictionary) -> void:
	_create_ground()
	_create_walls()
	_create_obstacles(config.get("obstacles", []))
	_create_navigation(config)
	navigation_ready.emit()
	print("[MAP] Generated: %dx%d, %d obstacles" % [int(map_size.x), int(map_size.y), config.get("obstacles", []).size()])


func _create_ground() -> void:
	## 创建地面静态体（XZ 平面，Y=0）
	var body = StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	body.collision_mask = 0

	var shape = BoxShape3D.new()
	shape.size = Vector3(map_size.x, 2.0, map_size.y)  # 厚度 2 避免穿透
	var col = CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	body.position = Vector3(map_size.x / 2.0, -1.0, map_size.y / 2.0)  # Y=-1 让顶面恰好在 Y=0

	if not is_headless:
		var mesh_inst = MeshInstance3D.new()
		var plane = PlaneMesh.new()
		plane.size = Vector2(map_size.x, map_size.y)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.18, 0.20, 0.18)
		plane.material = mat
		mesh_inst.mesh = plane
		mesh_inst.position = Vector3(0.0, 1.0, 0.0)  # 相对 body 抬到 Y=0
		body.add_child(mesh_inst)

	body.add_to_group("navigation_geometry")
	get_parent().add_child(body)


func _create_walls() -> void:
	var w = map_size.x
	var h = map_size.y
	var t = 40.0
	var wall_h = 200.0  # 墙高足够阻挡单位
	# 上下左右四面墙（XZ 平面上围住地图）
	_add_wall(Vector3(w / 2.0, wall_h / 2.0, -t / 2.0),       Vector3(w, wall_h, t))
	_add_wall(Vector3(w / 2.0, wall_h / 2.0, h + t / 2.0),    Vector3(w, wall_h, t))
	_add_wall(Vector3(-t / 2.0, wall_h / 2.0, h / 2.0),       Vector3(t, wall_h, h))
	_add_wall(Vector3(w + t / 2.0, wall_h / 2.0, h / 2.0),    Vector3(t, wall_h, h))


func _create_obstacles(obstacles: Array) -> void:
	for obs in obstacles:
		# config 坐标是 XY（2D），映射到 XZ（3D）
		var cx = float(obs.x) + float(obs.w) / 2.0
		var cz = float(obs.y) + float(obs.h) / 2.0
		var obs_h = 80.0
		_add_wall(Vector3(cx, obs_h / 2.0, cz), Vector3(float(obs.w), obs_h, float(obs.h)), Color(0.25, 0.25, 0.3))


func _add_wall(pos: Vector3, size: Vector3, color: Color = Color(0.3, 0.3, 0.35)) -> void:
	var body = StaticBody3D.new()
	body.position = pos
	body.collision_layer = 2  # layer=2：墙/障碍物专用，与 layer=1 地面区分
	body.collision_mask = 0

	var shape = BoxShape3D.new()
	shape.size = size
	var col = CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)

	if not is_headless:
		var mesh_inst = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = size
		var mat = StandardMaterial3D.new()
		mat.albedo_color = color
		box.material = mat
		mesh_inst.mesh = box
		body.add_child(mesh_inst)

	body.add_to_group("navigation_geometry")
	get_parent().add_child(body)


func _create_navigation(config: Dictionary) -> void:
	## 使用 NavigationRegion3D + NavigationMesh 替代 2D 的 NavigationPolygon。
	## NavigationMesh 用几何体烘焙：地面平面 + 障碍物作为阻挡。
	var nav_region = NavigationRegion3D.new()
	nav_region.name = "NavigationRegion3D"

	var nav_mesh = NavigationMesh.new()
	# 地图范围：XZ 平面 [0, map_w] × [0, map_h]，Y=0 地面
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nav_mesh.geometry_source_group_name = "navigation_geometry"
	nav_mesh.agent_height = 50.0
	nav_mesh.agent_radius = 10.0
	nav_mesh.agent_max_climb = 5.0
	nav_mesh.agent_max_slope = 30.0
	nav_mesh.cell_size = 8.0
	nav_mesh.cell_height = 4.0

	nav_region.navigation_mesh = nav_mesh
	get_parent().add_child(nav_region)

	# 运行时烘焙（异步，在主线程外完成）
	nav_region.bake_navigation_mesh(false)
	print("[MAP] NavigationMesh baking started")
