extends Node2D

## Selection Manager — 管理选中单位，高亮显示，处理框选和移动命令
## Headless mode: no Label/highlight, preserves selection logic for SimulatedPlayer
## 3D: CharacterBody2D/StaticBody2D → Node 类型检测，坐标 Vector2 → Vector3

signal units_selected(units: Array)
signal move_command_issued(target: Vector3, units: Array)
signal hq_selected(hq: Node)
signal click_missed  ## 左键单击落空（未命中任何单位或 HQ），用于关闭生产面板等

var selected_units: Array = []
var last_selection_rect: Rect2 = Rect2()
var _all_units: Array = []
var _all_hqs: Array = []
var _label: Label = null
var _left_click_pos: Variant = null
var _headless: bool = false

# Interaction metrics for Sensor Registry (headless testing)
var last_select_count: int = 0
var last_invalid_refs: int = 0
var last_move_commands: int = 0
var total_errors: int = 0


func set_headless(enabled: bool) -> void:
	_headless = enabled


func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_collect_units()

	if not _headless:
		_label = Label.new()
		_label.z_index = 200
		_label.position = Vector2(10, 10)
		_label.add_theme_font_size_override("font_size", 24)
		_label.add_theme_color_override("font_color", Color.WHITE)
		add_child(_label)


func setup(selection_box: Node) -> void:
	selection_box.selection_rect_drawn.connect(_on_selection_rect)


func _collect_units() -> void:
	_all_units = _all_units.filter(func(u): return is_instance_valid(u))
	_all_hqs = _all_hqs.filter(func(h): return is_instance_valid(h))
	for child in get_parent().get_children():
		if child is CharacterBody3D and child.has_method("get_unit_state") and not _all_units.has(child):
			_all_units.append(child)
		if child is StaticBody3D and child.has_method("get_unit_state") and not _all_hqs.has(child):
			_all_hqs.append(child)
	print("[SEL] Tracking %d units, %d HQs" % [_all_units.size(), _all_hqs.size()])


func get_all_units() -> Array:
	return _all_units.duplicate()


func simulate_right_click(target: Vector3) -> void:
	## Programmatic right-click — 接受 Vector3 世界坐标
	if selected_units.size() > 0:
		last_move_commands += 1
		move_command_issued.emit(target, selected_units)


func _unhandled_input(event: InputEvent) -> void:
	## 使用 _unhandled_input 而非 _input：
	## 当 ProdPanel._input 调用 set_input_as_handled() 后，
	## _unhandled_input 不再接收该事件，从而避免面板内点击触发 click_missed 导致面板关闭。
	## _input 无论是否 handled 都会触发，是 bug 根因。
	## headless 模式下不会产生 InputEventMouseButton，无需 guard 分支。
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if selected_units.size() > 0:
			## 窗口模式：屏幕坐标通过 Camera3D raycast 转世界坐标（暂用 XZ 平面近似）
			var screen_pos = get_viewport().get_mouse_position()
			var camera = get_viewport().get_camera_3d()
			var target := Vector3.ZERO
			if camera:
				var from = camera.project_ray_origin(screen_pos)
				var dir = camera.project_ray_normal(screen_pos)
				## XZ 平面（Y=0）求交点
				if abs(dir.y) > 0.001:
					var t_val = -from.y / dir.y
					target = from + dir * t_val
					target.y = 0.0
			move_command_issued.emit(target, selected_units)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_left_click_pos = get_viewport().get_mouse_position()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _left_click_pos:
			var release_pos = get_viewport().get_mouse_position()
			if _left_click_pos.distance_to(release_pos) < 5.0:
				_try_select_unit_at_screen(release_pos)
			_left_click_pos = null


func _try_select_unit_at_screen(screen_pos: Vector2) -> void:
	## 单击选择：通过 Camera3D 射线与单位 XZ 平面位置作距离检测
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
	var from = camera.project_ray_origin(screen_pos)
	var dir = camera.project_ray_normal(screen_pos)
	var world_pos := Vector3.ZERO
	if abs(dir.y) > 0.001:
		var t_val = -from.y / dir.y
		world_pos = from + dir * t_val
		world_pos.y = 0.0

	_all_units = _all_units.filter(func(u): return is_instance_valid(u))
	_all_hqs = _all_hqs.filter(func(h): return is_instance_valid(h))

	var closest_unit: Node = null
	var closest_dist: float = 40.0
	var closest_hq: Node = null
	var closest_hq_dist: float = 60.0

	for unit in _all_units:
		if unit.get("team_name") != "red":
			continue
		var d = Vector2(unit.global_position.x, unit.global_position.z).distance_to(Vector2(world_pos.x, world_pos.z))
		if d < closest_dist:
			closest_dist = d
			closest_unit = unit
	for hq in _all_hqs:
		if hq.get("team_name") != "red":
			continue
		var d = Vector2(hq.global_position.x, hq.global_position.z).distance_to(Vector2(world_pos.x, world_pos.z))
		if d < closest_hq_dist:
			closest_hq_dist = d
			closest_hq = hq

	_deselect_all()
	if closest_unit and closest_dist <= closest_hq_dist:
		_select_unit(closest_unit)
		last_select_count = 1
		units_selected.emit([closest_unit])
	elif closest_hq:
		_select_hq(closest_hq)
		last_select_count = 1
		hq_selected.emit(closest_hq)
	elif closest_unit:
		_select_unit(closest_unit)
		last_select_count = 1
		units_selected.emit([closest_unit])
	else:
		## 点击落空：通知外部关闭面板等
		click_missed.emit()


func _on_selection_rect(rect: Rect2) -> void:
	last_selection_rect = rect
	_deselect_all()
	var before_count = _all_units.size()
	_all_units = _all_units.filter(func(u): return is_instance_valid(u))
	last_invalid_refs = before_count - _all_units.size()
	## 3D：将单位世界坐标投影到屏幕坐标再与拖拽矩形比对
	## 为什么改：rect 来自鼠标拖拽，是屏幕像素坐标（0~2560）；
	## 原先用 flat_pos = XZ 世界坐标（-50~+50），两套坐标系根本对不上。
	var camera = get_viewport().get_camera_3d()
	for unit in _all_units:
		var screen_pos: Vector2
		if camera:
			## 窗口模式：将单位3D世界坐标投影到视口像素坐标，与框选rect（画布坐标+canvas_transform偏移）对齐。
			## 注意：rect 来自 selection_box，使用 get_global_mouse_position()（画布坐标）；
			## camera.unproject_position() 返回视口物理像素坐标，需减去 canvas_transform.origin 对齐。
			var vp_pos = camera.unproject_position(unit.global_position)
			var canvas_origin = get_canvas_transform().origin
			screen_pos = vp_pos - canvas_origin
		else:
			screen_pos = Vector2(unit.global_position.x, unit.global_position.z)
		if rect.has_point(screen_pos):
			_select_unit(unit)
	last_select_count = selected_units.size()
	if selected_units.size() > 0:
		units_selected.emit(selected_units)


func _select_unit(unit: Node) -> void:
	selected_units.append(unit)
	if not _headless:
		_highlight_unit(unit, true)


func _select_hq(hq: Node) -> void:
	if not _headless:
		_highlight_hq(hq, true)


func _deselect_all() -> void:
	if not _headless:
		for unit in selected_units:
			if is_instance_valid(unit):
				_highlight_unit(unit, false)
		for hq in _all_hqs:
			if is_instance_valid(hq):
				_highlight_hq(hq, false)
	selected_units.clear()
	_update_label()


func _highlight_unit(unit: Node, active: bool) -> void:
	## 3D：通过 MeshInstance3D 材质颜色高亮
	var mesh_inst = unit.get_node_or_null("MeshInstance3D")
	if mesh_inst and mesh_inst.mesh and mesh_inst.mesh.surface_get_material(0):
		var mat = mesh_inst.mesh.surface_get_material(0) as StandardMaterial3D
		if mat:
			if active:
				mat.albedo_color = Color(0.0, 1.0, 0.5)
			else:
				var team = unit.get("team_name")
				if unit.get("unit_type") == "worker":
					mat.albedo_color = Color(0.8, 0.5, 0.2) if team == "red" else Color(0.2, 0.5, 0.8)
				else:
					mat.albedo_color = Color(0.9, 0.3, 0.3) if team == "red" else Color(0.3, 0.3, 0.9)


func _highlight_hq(hq: Node, active: bool) -> void:
	var mesh_inst = hq.get_node_or_null("MeshInstance3D")
	if mesh_inst and mesh_inst.mesh and mesh_inst.mesh.surface_get_material(0):
		var mat = mesh_inst.mesh.surface_get_material(0) as StandardMaterial3D
		if mat:
			if active:
				mat.albedo_color = Color(0.0, 1.0, 0.5)
			else:
				var team = hq.get("team_name")
				mat.albedo_color = Color.RED if team == "red" else Color.BLUE


func _update_label() -> void:
	if _label:
		if selected_units.size() > 0:
			_label.text = "Selected: %d units" % selected_units.size()
		else:
			_label.text = ""


func _process(_delta: float) -> void:
	if _label:
		_update_label()
	_all_units = _all_units.filter(func(u): return is_instance_valid(u))
	_all_hqs = _all_hqs.filter(func(h): return is_instance_valid(h))
	for child in get_parent().get_children():
		if child is CharacterBody3D and child.has_method("get_unit_state") and not _all_units.has(child):
			_all_units.append(child)
		if child is StaticBody3D and child.has_method("get_unit_state") and not _all_hqs.has(child):
			_all_hqs.append(child)
