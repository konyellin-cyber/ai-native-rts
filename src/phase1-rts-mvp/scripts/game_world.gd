extends RefCounted
class_name GameWorld

## Phase 1 GameWorld — 实体创建 + 场景树组装
## 职责：按 config 创建所有游戏实体并 add_child 到 parent。
## 不知道：Renderer、SimPlayer、断言的存在。
## bootstrap 通过访问本类的公开属性获取实体引用。

# ─── 公开实体引用（只读，bootstrap 通过这里拿引用）─────────────────
var hq_red: StaticBody3D
var hq_blue: StaticBody3D
var mineral_nodes: Array[Area3D] = []
var units: Array = []   # CharacterBody3D (workers + fighters)
var arrow_manager: Node = null  ## ArrowManager：箭矢生命周期管理，Archer 通过它发射

# 交互 / UI 组件引用（bootstrap 需要转发信号）
var selection_box: Node = null
var selection_manager: Node = null
var bottom_bar: Node = null
var prod_panel: Node = null
var game_over_ui: Node = null
var ux_observer: RefCounted = null
var input_server: Node = null

# ─── 内部状态 ───────────────────────────────────────────────────────
var _parent: Node
var _config: Dictionary
var _is_headless: bool
var _renderer: RefCounted   ## ai_renderer 引用，仅用于注册实体，不驱动 tick
var _next_unit_id: int = 0

# unit_died 信号向上冒泡给 UnitLifecycleManager
signal unit_died(victim_id: int, victim_team: String)
signal unit_produced(unit_type: String, team: String)
signal hq_destroyed(team: String)
signal hq_selected(hq: Node)
signal click_missed  ## 左键落空，用于关闭面板
signal selection_rect_drawn(rect: Rect2)
signal units_selected(selected: Array)
signal move_command_issued(target: Vector3, selected_units: Array)
signal produce_requested(unit_type: String)


func setup(parent: Node, config: Dictionary, is_headless: bool, renderer: RefCounted) -> void:
	_parent = parent
	_config = config
	_is_headless = is_headless
	_renderer = renderer


func build() -> void:
	## 按顺序创建所有游戏实体，调用一次。
	_create_map()
	_create_hqs()
	_create_minerals()
	_create_arrow_manager()
	_spawn_initial_workers()
	_spawn_generals()
	_create_ai_opponent()
	_setup_interaction()
	if not _is_headless:
		_setup_visuals()
		_setup_ux_observer()


# ─── Map ──────────────────────────────────────────────────────────

func _create_map() -> void:
	var map_script = load("res://scripts/map_generator.gd")
	var map_gen = Node3D.new()
	map_gen.set_script(map_script)
	map_gen.name = "MapGenerator"
	map_gen.setup(_config, _is_headless)
	_parent.add_child(map_gen)
	map_gen.generate(_config)


# ─── ArrowManager ─────────────────────────────────────────────────

func _create_arrow_manager() -> void:
	var am_script = load("res://scripts/arrow_manager.gd")
	arrow_manager = Node.new()
	arrow_manager.set_script(am_script)
	arrow_manager.name = "ArrowManager"
	_parent.add_child(arrow_manager)
	var obstacles = _config.get("obstacles", [])
	var arrow_speed = float(_config.get("archer", {}).get("arrow_speed", 600.0))
	arrow_manager.setup(obstacles, _is_headless, arrow_speed)


# ─── HQ ───────────────────────────────────────────────────────────

func _create_hqs() -> void:
	var hq_script = load("res://scripts/hq.gd")
	var hq_config = _config.hq

	hq_red = StaticBody3D.new()
	hq_red.set_script(hq_script)
	hq_red.setup("red", Vector3(float(hq_config.spawn_red.x), 0.0, float(hq_config.spawn_red.y)), {
		"hp": hq_config.hp, "radius": hq_config.radius, "initial_crystal": 200,
	}, _is_headless)
	hq_red.name = "HQ_red"
	_parent.add_child(hq_red)
	hq_red.hq_destroyed.connect(func(team): hq_destroyed.emit(team))
	hq_red.unit_produced.connect(func(t, tm): _on_hq_unit_produced(t, tm))

	hq_blue = StaticBody3D.new()
	hq_blue.set_script(hq_script)
	hq_blue.setup("blue", Vector3(float(hq_config.spawn_blue.x), 0.0, float(hq_config.spawn_blue.y)), {
		"hp": hq_config.hp, "radius": hq_config.radius, "initial_crystal": 200,
	}, _is_headless)
	hq_blue.name = "HQ_blue"
	_parent.add_child(hq_blue)
	hq_blue.hq_destroyed.connect(func(team): hq_destroyed.emit(team))
	hq_blue.unit_produced.connect(func(t, tm): _on_hq_unit_produced(t, tm))

	var hq_fields: Array[String] = ["team_name", "hp", "max_hp", "crystal", "queue_size", "producing"]
	_renderer.register("HQ_red", hq_red, hq_fields, "economy")
	_renderer.register("HQ_blue", hq_blue, hq_fields, "economy")

	print("[WORLD] HQs created: red at %s, blue at %s" % [str(hq_config.spawn_red), str(hq_config.spawn_blue)])


func _on_hq_unit_produced(unit_type: String, team: String) -> void:
	var new_unit = spawn_unit(team, unit_type)
	unit_produced.emit(unit_type, team)
	if new_unit == null:
		return


# ─── Minerals ─────────────────────────────────────────────────────

func _create_minerals() -> void:
	var mine_script = load("res://scripts/resource_node.gd")
	var id = 0
	for mn in _config.mineral_nodes:
		var node = Area3D.new()
		node.set_script(mine_script)
		node.setup("Mine_%d" % id, Vector3(float(mn.x), 0.0, float(mn.y)), mn.amount, _is_headless)
		_parent.add_child(node)
		mineral_nodes.append(node)
		node.add_to_group("minerals")
		_renderer.register("Mine_%d" % id, node, ["amount", "max_amount", "harvesters"], "economy")
		id += 1
	print("[WORLD] Created %d mineral nodes" % mineral_nodes.size())


# ─── Workers (initial spawn) ──────────────────────────────────────

func _spawn_initial_workers() -> void:
	var worker_config = _config.worker
	var hq_config = _config.hq
	var map_size = Vector2(float(_config.map.width), float(_config.map.height))

	for team in ["red", "blue"]:
		var spawn_pos = Vector3(float(hq_config.spawn_red.x), 0.0, float(hq_config.spawn_red.y)) if team == "red" \
			else Vector3(float(hq_config.spawn_blue.x), 0.0, float(hq_config.spawn_blue.y))
		var hq = hq_red if team == "red" else hq_blue
		for i in range(3):
			var offset = Vector3(randf_range(-50, 50), 0.0, randf_range(-50, 50))
			var worker = CharacterBody3D.new()
			var worker_script = load("res://scripts/worker.gd")
			worker.set_script(worker_script)
			worker.setup(_next_unit_id, team, spawn_pos + offset, worker_config, _is_headless, map_size, hq)
			_next_unit_id += 1
			units.append(worker)
			_parent.add_child(worker)
			_renderer.register(worker.name, worker, [
				"unit_id", "team_name", "unit_type", "global_position",
				"hp", "max_hp", "ai_state", "carrying", "target_position", "velocity",
			])
			worker.died.connect(func(vid, vteam): unit_died.emit(vid, vteam))

	print("[WORLD] Spawned 3 workers per team")


# ─── Generals ─────────────────────────────────────────────────────

func _spawn_generals() -> void:
	## 15A.7/15A.8：主场景各阵营生成一名将领，与普通士兵生成逻辑分离。
	## 15B：红方将领生成后同时生成 N 个哑兵（N 由 config.general.dummy_soldier_count 决定）。
	## red 阵营：玩家控制的将领（可被框选/右键移动）
	## blue 阵营：AI 静态占位将领（暂时不移动，Phase 16 补充 AI 逻辑）
	var general_cfg = _config.get("general", null)
	if general_cfg == null:
		## general 配置段不存在时跳过（向后兼容旧测试场景）
		return

	var hq_config = _config.hq
	var map_size = Vector2(float(_config.map.width), float(_config.map.height))
	var GeneralScript = load("res://scripts/general_unit.gd")
	var DummyScript = load("res://scripts/dummy_soldier.gd")
	var dummy_count = int(general_cfg.get("dummy_soldier_count", 30))

	for team in ["red", "blue"]:
		var hq_pos_cfg = hq_config.spawn_red if team == "red" else hq_config.spawn_blue
		var spawn_pos = Vector3(float(hq_pos_cfg.x), 0.0, float(hq_pos_cfg.y))
		## 将领生成在 HQ 前方 80 单位，避免与 HQ 重叠
		var offset = Vector3(80.0, 0.0, 0.0) if team == "red" else Vector3(-80.0, 0.0, 0.0)

		var general = CharacterBody3D.new()
		general.set_script(GeneralScript)
		general.setup(_next_unit_id, team, spawn_pos + offset, general_cfg, _is_headless, map_size, null)
		_next_unit_id += 1
		units.append(general)
		_parent.add_child(general)

		_renderer.register(general.name, general, [
			"unit_id", "team_name", "unit_type", "global_position",
			"hp", "max_hp", "ai_state", "target_position", "has_command", "follow_mode",
		])
		general.died.connect(func(vid, vteam): unit_died.emit(vid, vteam))

		## 15B.2：红方将领生成后，周围生成 N 个哑兵
		if team == "red":
			var soldiers: Array = []
			for i in range(dummy_count):
				var dummy = RigidBody3D.new()
				dummy.set_script(DummyScript)
				dummy.setup(general, i, dummy_count, general_cfg, _is_headless)
				_parent.add_child(dummy)
				soldiers.append(dummy)
			general.register_dummy_soldiers(soldiers)
			print("[WORLD] Spawned %d dummy soldiers for red general" % dummy_count)

		## 蓝方将领：生成哑兵 + 启动简单行军 AI（向红方 HQ 方向推进）
		if team == "blue":
			var soldiers: Array = []
			for i in range(dummy_count):
				var dummy = RigidBody3D.new()
				dummy.set_script(DummyScript)
				dummy.setup(general, i, dummy_count, general_cfg, _is_headless)
				_parent.add_child(dummy)
				soldiers.append(dummy)
			general.register_dummy_soldiers(soldiers)
			print("[WORLD] Spawned %d dummy soldiers for blue general" % dummy_count)
			## 启动 AI：延迟 300 帧后开始向红方 HQ 推进（让双方先完成经济建设）
			var red_hq_pos = Vector3(float(_config.hq.spawn_red.x), 0.0, float(_config.hq.spawn_red.y))
			var gen_ref_blue = general
			_parent.get_tree().create_timer(5.0).timeout.connect(
				func(): _start_blue_general_ai(gen_ref_blue, red_hq_pos)
			)

		## 15C：双方将领均启用补兵，监听 replenish_requested 信号
		var gen_ref = general  ## 捕获引用，避免闭包问题
		general.replenish_requested.connect(func(g: Node): _on_replenish_requested(g, DummyScript))

	print("[WORLD] Generals spawned: red and blue")




func _start_blue_general_ai(general: Node, red_hq_pos: Vector3) -> void:
	## 蓝方将领简单行军 AI：朝红方 HQ 推进，到达后在附近徘徊
	## 每 8 秒重新发一次命令，确保将领持续压制（不会因到达目标后停在原地）
	if not is_instance_valid(general):
		return
	if general.get("_state") == "dead":
		return
	general.move_to(red_hq_pos)
	print("[WORLD] Blue general AI: marching to red HQ pos=%s" % str(red_hq_pos))
	## 持续循环：8 秒后再次检查并发命令
	_parent.get_tree().create_timer(8.0).timeout.connect(
		func(): _start_blue_general_ai(general, red_hq_pos)
	)


func _on_replenish_requested(general: Node, DummyScript: GDScript) -> void:	## 15C：收到补兵请求，为该将领生成 replenish_count 个新哑兵并注入
	if not is_instance_valid(general):
		return
	var cfg: Dictionary = general.get_general_cfg()
	var count: int = general.get_dummy_count()
	var add_count: int = int(cfg.get("replenish_count", 3))
	for i in range(add_count):
		var dummy = RigidBody3D.new()
		dummy.set_script(DummyScript)
		dummy.setup(general, count + i, count + add_count, cfg, _is_headless)
		_parent.add_child(dummy)
		general.add_dummy_soldier(dummy)
	print("[WORLD] Replenished %d soldiers for %s (total=%d)" % [
		add_count, general.name, general.get_dummy_count()
	])


func _create_ai_opponent() -> void:
	var ai_config = _config.get("ai_opponent", {})
	if not ai_config.get("enabled", true):
		return
	var ai_script = load("res://scripts/ai_opponent.gd")
	var ai = Node.new()
	ai.set_script(ai_script)
	ai.setup(hq_blue, ai_config, _is_headless)
	_parent.add_child(ai)


# ─── Spawn Unit (produced by HQ) ──────────────────────────────────

func spawn_unit(team: String, unit_type_str: String) -> CharacterBody3D:
	var hq = hq_red if team == "red" else hq_blue
	var cfg = _config[unit_type_str] if _config.has(unit_type_str) else _config.worker
	var map_size = Vector2(float(_config.map.width), float(_config.map.height))
	var offset = Vector3(randf_range(-30, 30), 0.0, randf_range(-30, 30))

	var unit = CharacterBody3D.new()
	var unit_script = load("res://scripts/%s.gd" % unit_type_str)
	unit.set_script(unit_script)
	if unit_type_str == "archer":
		unit.setup(_next_unit_id, team, hq.global_position + offset, cfg, _is_headless, map_size, hq, arrow_manager)
	else:
		unit.setup(_next_unit_id, team, hq.global_position + offset, cfg, _is_headless, map_size, hq)
	_next_unit_id += 1
	units.append(unit)
	_parent.add_child(unit)
	_renderer.register(unit.name, unit, [
		"unit_id", "team_name", "unit_type", "global_position",
		"hp", "max_hp", "ai_state", "velocity",
		"target_position", "has_command", "_nav_available",
	])
	unit.died.connect(func(vid, vteam): unit_died.emit(vid, vteam))
	print("[WORLD] %s spawned %s_%d" % [team, unit_type_str, unit.unit_id])
	return unit


# ─── Interaction Setup (all modes) ────────────────────────────────

func _setup_interaction() -> void:
	var sb_script = load("res://scripts/selection_box.gd")
	selection_box = Node2D.new()
	selection_box.set_script(sb_script)
	selection_box.name = "SelectionBox"
	_parent.add_child(selection_box)

	var sm_script = load("res://scripts/selection_manager.gd")
	selection_manager = Node2D.new()
	selection_manager.set_script(sm_script)
	selection_manager.name = "SelectionManager"
	_parent.add_child(selection_manager)
	selection_manager.setup(selection_box)
	selection_box.set_headless(_is_headless)
	selection_manager.set_headless(_is_headless)

	selection_manager.move_command_issued.connect(func(t, su): move_command_issued.emit(t, su))
	selection_manager.units_selected.connect(func(sel): units_selected.emit(sel))
	selection_manager.hq_selected.connect(func(hq): hq_selected.emit(hq))
	selection_manager.click_missed.connect(func(): click_missed.emit())
	selection_box.selection_rect_drawn.connect(func(rect): selection_rect_drawn.emit(rect))


# ─── Visual UI (window mode only) ─────────────────────────────────

func _setup_visuals() -> void:
	var bb_script = load("res://scripts/ui/bottom_bar.gd")
	bottom_bar = CanvasLayer.new()
	bottom_bar.set_script(bb_script)
	bottom_bar.name = "BottomBar"
	bottom_bar.setup(false)
	_parent.add_child(bottom_bar)

	var pp_script = load("res://scripts/ui/prod_panel.gd")
	prod_panel = Control.new()
	prod_panel.set_script(pp_script)
	prod_panel.name = "ProdPanel"
	prod_panel.setup(false)
	_parent.add_child(prod_panel)
	prod_panel.produce_requested.connect(func(t): produce_requested.emit(t))

	var go_script = load("res://scripts/ui/game_over.gd")
	game_over_ui = Control.new()
	game_over_ui.set_script(go_script)
	game_over_ui.name = "GameOverUI"
	game_over_ui.setup(false)
	_parent.add_child(game_over_ui)


# ─── UX Observer (window mode only) ──────────────────────────────

func _setup_ux_observer() -> void:
	var UXScript = load("res://tools/ai-renderer/ux_observer.gd")
	ux_observer = UXScript.new()

	var camera = _parent.get_viewport().get_camera_2d()
	if camera == null:
		for child in _parent.get_children():
			if child is Camera2D:
				camera = child
				break
	if camera == null:
		camera = Camera2D.new()
		camera.name = "Camera2D"
		camera.position = Vector2(float(_config.map.width) / 2.0, float(_config.map.height) / 2.0)
		camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
		_parent.add_child(camera)

	ux_observer.setup(_parent, _parent.get_viewport(), camera, {"screenshot_interval": 5.0})
	print("[WORLD] UX Observer initialized (window mode)")


# ─── Visual helper ────────────────────────────────────────────────

func make_circle_visual(radius: float, color: Color) -> Node2D:
	var node = Node2D.new()
	var line = Line2D.new()
	var pts = 20
	for i in range(pts + 1):
		var angle = (float(i) / float(pts)) * TAU
		line.add_point(Vector2(cos(angle) * radius, sin(angle) * radius))
	line.default_color = color
	line.width = 2.0
	node.add_child(line)
	return node
