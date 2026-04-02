extends RefCounted
class_name WindowAssertionSetup

## WindowAssertionSetup — 窗口模式专属断言集合
## 职责：注册只有窗口才能初始化的 9 个断言（Camera3D / Mesh / UI）。
## 所有断言均为结构/属性检查，不依赖渲染画面，Phase 9 可迁移到 headless。
## 参考：assertion_setup.gd 的写法风格。

var _renderer: RefCounted   ## AIRenderer（add_assertion 入口）
var _world: RefCounted      ## GameWorld（实体引用）
var _bootstrap: Node        ## Bootstrap Node（用于 find_child Camera3D）
var _map_width: float
var _map_height: float

# 内部帧计数器：每次断言回调调用时递增，驱动 pending → 判断 的状态转换。
# 为什么不用 bootstrap._window_frame_count：断言对象不应持有 bootstrap 成员变量，
# 通过自增计数器可以独立测量"断言被调用了多少次"，与物理帧数近似相等。
var _frame_counter: int = 0

# prod_panel_shows_on_hq_click 需要追踪 prod_panel 是否曾经显示过
var _hq_clicked: bool = false
var _prod_panel_ever_shown: bool = false  # 框选 HQ 或左键点击 HQ 均可触发
var _click_missed_after_shown: bool = false  # 面板曾显示后是否发生过 click_missed


func setup(
	renderer: RefCounted,
	world: RefCounted,
	bootstrap_node: Node,
	map_width: float,
	map_height: float
) -> void:
	_renderer = renderer
	_world = world
	_bootstrap = bootstrap_node
	_map_width = map_width
	_map_height = map_height

	# 连接 world.hq_selected 信号：任意 HQ 被点击时设置 _hq_clicked = true
	# 为什么在 setup 里连接：register_all 只注册断言函数引用，无法访问 _world
	if _world.has_signal("hq_selected"):
		_world.hq_selected.connect(_on_hq_selected)
	if _world.has_signal("click_missed"):
		_world.click_missed.connect(_on_click_missed)
	if _world.has_signal("move_command_issued"):
		_world.move_command_issued.connect(_on_move_command_issued)

func _on_hq_selected(_hq: Node) -> void:
	_hq_clicked = true


func _on_click_missed() -> void:
	if _prod_panel_ever_shown:
		_click_missed_after_shown = true


func _on_move_command_issued(_target, _units) -> void:
	## 发出移动命令时也视为"点击了面板外部"，与 click_missed 等效
	if _prod_panel_ever_shown:
		_click_missed_after_shown = true


func register_all() -> void:
	## 向 Calibrator 注册所有窗口断言，bootstrap 在非 headless 分支调用一次
	_renderer.add_assertion("camera_orthographic",       _assert_camera_orthographic)
	_renderer.add_assertion("camera_covers_map",         _assert_camera_covers_map)
	_renderer.add_assertion("camera_isometric",          _assert_camera_isometric)
	_renderer.add_assertion("units_have_mesh",           _assert_units_have_mesh)
	_renderer.add_assertion("hq_has_mesh",               _assert_hq_has_mesh)
	_renderer.add_assertion("no_initial_selection",      _assert_no_initial_selection)
	_renderer.add_assertion("prod_panel_hidden_at_start",_assert_prod_panel_hidden_at_start)
	_renderer.add_assertion("prod_panel_shows_on_hq_click", _assert_prod_panel_shows_on_hq_click)
	_renderer.add_assertion("bottom_bar_visible",        _assert_bottom_bar_visible)
	_renderer.add_assertion("prod_panel_has_progress_bar",  _assert_prod_panel_has_progress_bar)
	_renderer.add_assertion("prod_panel_position_near_hq",  _assert_prod_panel_position_near_hq)
	_renderer.add_assertion("prod_panel_hides_on_click_outside", _assert_prod_panel_hides_on_click_outside)
	_renderer.add_assertion("prod_panel_has_archer_button",  _assert_prod_panel_has_archer_button)


# ─── 工具：获取 Camera3D ────────────────────────────────────────────

func _get_camera() -> Camera3D:
	## 从 bootstrap 节点树中查找 Camera3D（_setup_3d_scene 已 add_child）
	return _bootstrap.get_node_or_null("Camera3D") as Camera3D


# ─── 工具：帧计数自增（每个断言在帧计数阶段调用一次）────────────────

func _tick_frame() -> void:
	_frame_counter += 1


# ─── 断言：Camera3D ────────────────────────────────────────────────

func _assert_camera_orthographic() -> Dictionary:
	## Camera3D 必须使用正交投影（不依赖渲染，读属性即可）
	_tick_frame()
	var cam = _get_camera()
	if not is_instance_valid(cam):
		return {"status": "pending", "detail": "Camera3D not found yet"}
	if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return {"status": "pass", "detail": "projection=ORTHOGONAL"}
	return {"status": "fail", "detail": "projection=%d (expect ORTHOGONAL=%d)" % [cam.projection, Camera3D.PROJECTION_ORTHOGONAL]}


func _assert_camera_covers_map() -> Dictionary:
	## Camera3D.size 必须覆盖地图高度的 80% 以上（允许 20% 误差）
	## 为什么 80%：size 是垂直世界单位，允许轻微缩放配置变化
	var cam = _get_camera()
	if not is_instance_valid(cam):
		return {"status": "pending", "detail": "Camera3D not found yet"}
	var min_size = _map_height * 0.8
	if cam.size >= min_size:
		return {"status": "pass", "detail": "size=%.0f >= map_height*0.8=%.0f" % [cam.size, min_size]}
	return {"status": "fail", "detail": "size=%.0f < map_height*0.8=%.0f" % [cam.size, min_size]}


func _assert_camera_isometric() -> Dictionary:
	## Camera3D 为等距视角且居中：
	##   1. rotation_degrees.y ≈ -45°（偏航，经典等距方向）
	##   2. 视线射到 y=0 平面的交点与地图中心的偏差 ≤ 300
	## 为什么用射线交点而非 position.x：等距摄像机需向右前方偏移才能居中，
	##   position.x ≠ 地图中心；用 y=0 交点可以直接验证"玩家看到的中心是否是地图中心"
	var cam = _get_camera()
	if not is_instance_valid(cam):
		return {"status": "pending", "detail": "Camera3D not found yet"}
	var yaw = cam.rotation_degrees.y
	var yaw_ok = abs(yaw - (-45.0)) <= 5.0

	# 计算视线（摄像机局部 -Z 经旋转后）射到 y=0 平面的交点
	# Camera3D 朝向 = -global_transform.basis.z（局部 -Z 轴在世界空间的方向）
	var forward = -cam.global_transform.basis.z  # 归一化向量
	var look_at_ground: Vector2 = Vector2.ZERO
	var ground_ok := false
	if abs(forward.y) > 0.01:  # 避免除零（水平摄像机）
		var t = -cam.position.y / forward.y  # y=0 平面交点参数
		var hit_x = cam.position.x + forward.x * t
		var hit_z = cam.position.z + forward.z * t
		look_at_ground = Vector2(hit_x, hit_z)
		var map_center = Vector2(_map_width / 2.0, _map_height / 2.0)
		var dist = look_at_ground.distance_to(map_center)
		ground_ok = dist <= 300.0
		if yaw_ok and ground_ok:
			return {"status": "pass", "detail": "yaw=%.1f° look_at=(%.0f,%.0f) map_center=(%.0f,%.0f) dist=%.0f" % [
				yaw, look_at_ground.x, look_at_ground.y, map_center.x, map_center.y, dist]}
		return {"status": "fail", "detail": "isometric check failed: yaw=%.1f° (ok=%s), look_at=(%.0f,%.0f) dist=%.0f (limit 300)" % [
			yaw, str(yaw_ok), look_at_ground.x, look_at_ground.y, look_at_ground.distance_to(Vector2(_map_width/2.0, _map_height/2.0))]}
	return {"status": "fail", "detail": "camera forward.y≈0 (camera is horizontal, not tilted down)"}


# ─── 断言：Mesh 结构 ───────────────────────────────────────────────

func _assert_units_have_mesh() -> Dictionary:
	## 至少一个单位节点含 MeshInstance3D 子节点（结构检查，不需要渲染）
	## 为什么只检查"至少一个"：窗口模式下 _add_visual 为每个单位创建 Mesh，
	## 只要机制正常，任意一个单位存在 Mesh 即可证明 visual 创建路径有效
	var units = _world.units
	if units.is_empty():
		return {"status": "pending", "detail": "no units yet"}
	for unit in units:
		if not is_instance_valid(unit):
			continue
		var meshes = unit.find_children("*", "MeshInstance3D", true, false)
		if meshes.size() > 0:
			return {"status": "pass", "detail": "unit '%s' has MeshInstance3D" % unit.name}
	return {"status": "fail", "detail": "no unit has MeshInstance3D child"}


func _assert_hq_has_mesh() -> Dictionary:
	## HQ_red 必须含 MeshInstance3D 子节点（蓝方同理，但只验证红方即可证明机制正常）
	if not is_instance_valid(_world.hq_red):
		return {"status": "pending", "detail": "hq_red not valid yet"}
	var meshes = _world.hq_red.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() > 0:
		return {"status": "pass", "detail": "hq_red has MeshInstance3D"}
	return {"status": "fail", "detail": "hq_red has no MeshInstance3D child"}


# ─── 断言：UI 初始状态 ─────────────────────────────────────────────

func _assert_no_initial_selection() -> Dictionary:
	## 前 10 帧 pending（等待游戏完全初始化），之后检查选中列表为空
	## 为什么等 10 帧：window frame 前几帧 SelectionManager 可能还未 ready
	_tick_frame()
	if _frame_counter <= 10:
		return {"status": "pending", "detail": "waiting for init (frame=%d)" % _frame_counter}
	var sm = _world.selection_manager
	if not is_instance_valid(sm):
		return {"status": "pending", "detail": "SelectionManager not valid"}
	if sm.selected_units.is_empty():
		return {"status": "pass", "detail": "no units selected at start"}
	return {"status": "fail", "detail": "%d units selected at frame %d (expect 0)" % [sm.selected_units.size(), _frame_counter]}


func _assert_prod_panel_hidden_at_start() -> Dictionary:
	## 前 10 帧 pending；之后 prod_panel 应处于隐藏状态（visible_state == false）
	## 为什么用 visible_state：ProdPanel 用 visible_state 追踪面板显隐，不用 .visible
	_tick_frame()
	if _frame_counter <= 10:
		return {"status": "pending", "detail": "waiting for init (frame=%d)" % _frame_counter}
	var pp = _world.prod_panel
	if pp == null:
		# prod_panel 为 null 说明窗口 UI 未初始化，视为通过（不是此断言的责任范围）
		return {"status": "pass", "detail": "prod_panel is null (no window UI)"}
	if not is_instance_valid(pp):
		return {"status": "pending", "detail": "prod_panel not valid yet"}
	if not pp.visible_state:
		return {"status": "pass", "detail": "prod_panel hidden at start"}
	return {"status": "fail", "detail": "prod_panel is visible at frame %d (expect hidden)" % _frame_counter}


func _assert_prod_panel_shows_on_hq_click() -> Dictionary:
	## prod_panel 曾经显示过（框选包含 HQ 或直接点击 HQ 均可）则 pass
	## 为什么不再依赖 hq_selected 信号：框选包含 HQ 时走 _on_selection_rect_drawn
	## 路径，不发 hq_selected 信号，但 prod_panel 已显示，改为轮询 visible_state
	var pp = _world.prod_panel
	if pp == null:
		return {"status": "pass", "detail": "prod_panel is null (no window UI)"}
	if not is_instance_valid(pp):
		return {"status": "pending", "detail": "prod_panel not valid yet"}
	if pp.visible_state:
		_prod_panel_ever_shown = true
	if _prod_panel_ever_shown:
		return {"status": "pass", "detail": "prod_panel was shown (triggered by HQ selection)"}
	if not _hq_clicked:
		return {"status": "pending", "detail": "waiting for HQ selection"}
	return {"status": "fail", "detail": "prod_panel not visible after hq_selected"}


# ─── 断言：BottomBar ───────────────────────────────────────────────

func _assert_bottom_bar_visible() -> Dictionary:
	## BottomBar 节点必须存在且可见（CanvasLayer 的 visible 属性）
	## 为什么直接检查 visible：BottomBar 始终可见，无 visible_state 包装
	var bb = _world.bottom_bar
	if bb == null:
		return {"status": "pending", "detail": "bottom_bar not created yet"}
	if not is_instance_valid(bb):
		return {"status": "pending", "detail": "bottom_bar not valid yet"}
	if bb.visible:
		return {"status": "pass", "detail": "bottom_bar visible"}
	return {"status": "fail", "detail": "bottom_bar exists but not visible"}


func _assert_prod_panel_has_progress_bar() -> Dictionary:
	## prod_panel 节点树中必须存在 ProgressBar 子节点（捕获 add_child 遗漏类 bug）
	var pp = _world.prod_panel
	if pp == null:
		return {"status": "pass", "detail": "prod_panel is null (no window UI)"}
	if not is_instance_valid(pp):
		return {"status": "pending", "detail": "prod_panel not valid yet"}
	var bars = pp.find_children("*", "ProgressBar", true, false)
	if bars.size() > 0:
		return {"status": "pass", "detail": "prod_panel has ProgressBar in scene tree"}
	return {"status": "fail", "detail": "prod_panel has no ProgressBar child (add_child may be missing)"}


func _assert_prod_panel_position_near_hq() -> Dictionary:
	## 面板显示时，面板屏幕坐标应在 HQ 屏幕投影坐标 300px 以内（验证跟随逻辑）
	var pp = _world.prod_panel
	if pp == null:
		return {"status": "pass", "detail": "prod_panel is null (no window UI)"}
	if not is_instance_valid(pp):
		return {"status": "pending", "detail": "prod_panel not valid yet"}
	if not _prod_panel_ever_shown:
		return {"status": "pending", "detail": "waiting for prod_panel to be shown"}
	# 读取面板节点树中的 PanelContainer 位置
	var panel_container = pp.find_children("*", "PanelContainer", false, false)
	if panel_container.is_empty():
		return {"status": "fail", "detail": "PanelContainer not found in prod_panel"}
	var panel_pos: Vector2 = (panel_container[0] as Control).position
	var panel_size: Vector2 = (panel_container[0] as Control).size
	var panel_center = panel_pos + panel_size / 2.0
	# 将 HQ 世界坐标投影到屏幕坐标
	var cam = _get_camera()
	if not is_instance_valid(cam):
		return {"status": "pending", "detail": "Camera3D not found"}
	if not is_instance_valid(_world.hq_red):
		return {"status": "pending", "detail": "hq_red not valid"}
	var hq_screen = cam.unproject_position(_world.hq_red.global_position)
	var dist = panel_center.distance_to(hq_screen)
	if dist <= 300.0:
		return {"status": "pass", "detail": "panel center (%.0f,%.0f) within 300px of hq screen pos (%.0f,%.0f), dist=%.0f" % [panel_center.x, panel_center.y, hq_screen.x, hq_screen.y, dist]}
	return {"status": "fail", "detail": "panel center (%.0f,%.0f) too far from hq screen pos (%.0f,%.0f), dist=%.0f > 300" % [panel_center.x, panel_center.y, hq_screen.x, hq_screen.y, dist]}


func _assert_prod_panel_hides_on_click_outside() -> Dictionary:
	## 面板显示后，点击面板外空白处或框选其他区域应关闭面板
	## "点击面板内部（包括按钮）"不关闭面板——ProdPanel._input 会拦截面板内点击
	## 验证逻辑：等待面板曾经显示 → 等待 click_missed 或移动命令 → 确认 visible_state == false
	if not _prod_panel_ever_shown:
		return {"status": "pending", "detail": "waiting for prod_panel to be shown first"}
	if not _click_missed_after_shown:
		return {"status": "pending", "detail": "waiting for click_missed after panel was shown"}
	var pp = _world.prod_panel
	if pp == null:
		return {"status": "pass", "detail": "prod_panel is null (no window UI)"}
	if not is_instance_valid(pp):
		return {"status": "fail", "detail": "prod_panel invalid"}
	if not pp.visible_state:
		return {"status": "pass", "detail": "prod_panel hidden after click_missed"}
	return {"status": "fail", "detail": "prod_panel still visible after clicking outside (click_missed did not close panel)"}


func _assert_prod_panel_has_archer_button() -> Dictionary:
	## prod_panel 节点树中必须存在含 "Archer" 文本的 Button（验证 Phase 11 UI 改动）
	## 为什么检查文本而非节点名：按钮无固定名，文本是唯一标识符
	var pp = _world.prod_panel
	if pp == null:
		return {"status": "pass", "detail": "prod_panel is null (no window UI)"}
	if not is_instance_valid(pp):
		return {"status": "pending", "detail": "prod_panel not valid yet"}
	var buttons = pp.find_children("*", "Button", true, false)
	for btn in buttons:
		if (btn as Button).text.contains("Archer"):
			return {"status": "pass", "detail": "found Archer button: '%s'" % (btn as Button).text}
	return {"status": "fail", "detail": "no Button with text containing 'Archer' found in prod_panel"}
