extends Node3D

## general_visual bootstrap — 15B.15 / 19B / 19C
## 独立干净的目视演示场景：将领 + 哑兵，无 HQ / 工人 / 矿点 / AI / UI。
##
## 操作（手动模式）：
##   右键点击地面 → 将领带队移动
##   Space         → 切换跟随/待命
##
## 自动断言模式（命令行含 --assert-deploy）：
##   自动发出移动指令 → 等待 formation_state==deployed → PASS/FAIL 后退出
##
## Benchmark 模式（命令行含 --benchmark）：
##   自动执行 S1~S4 固定剧本 → 逐帧采集指标 → 输出评分 JSON → 退出

const _GeneralScript = preload("res://scripts/general_unit.gd")
const _DummyScript   = preload("res://scripts/dummy_soldier.gd")
const _AIRendererScript = preload("res://tools/ai-renderer/ai_renderer.gd")
const _UXObserverScript = preload("res://tools/ai-renderer/ux_observer.gd")
const _BenchmarkPlayerScript = preload("res://tests/gameplay/general_visual/benchmark_player.gd")
const _MetricsRecorderScript = preload("res://tests/gameplay/general_visual/metrics_recorder.gd")

var _general: CharacterBody3D = null
var _camera: Camera3D = null
var _config: Dictionary = {}
var _is_headless: bool = false
var _ground_y: float = 0.0

## 19B：AI Renderer + 可视化调试
var _renderer = null
var _ux_observer = null
var _last_formation_state: String = ""
var _frame: int = 0
var _debug_lines: Array = []
var _debug_waiting: Array = []
var _debug_path_dots: Array = []

## deployed 收敛追踪
var _deployed_since_frame: int = -1
var _last_deploy_screenshot_frame: int = -1
const _DEPLOY_SCREENSHOT_INTERVAL: int = 60  ## deployed 期间每 60 帧截一张（约 1 秒）

## 窗口断言模式
var _assert_mode: bool = false
const _MOVE_FRAME: int = 30
const _ASSERT_TIMEOUT: int = 1800
const _MOVE_TARGET_OFFSET := Vector3(300.0, 0.0, 0.0)
var _assert_result: String = "pending"

## Benchmark 模式
var _benchmark_mode: bool = false
var _benchmark_player = null
var _metrics_recorder = null


func _ready() -> void:
	_is_headless = DisplayServer.get_name() == "headless"
	if _is_headless:
		push_warning("[VISUAL] Headless mode detected — scene intended for window mode only")
		get_tree().quit()
		return

	_assert_mode = "--assert-deploy" in OS.get_cmdline_user_args()
	_benchmark_mode = "--benchmark" in OS.get_cmdline_user_args()

	_config = _load_config()
	if _config.is_empty():
		push_error("[VISUAL] Failed to load config")
		return

	var map_size = Vector2(
		float(_config.get("map", {}).get("width", 1000.0)),
		float(_config.get("map", {}).get("height", 1000.0))
	)
	var general_cfg: Dictionary = _load_global_unit_config("general")

	_general = CharacterBody3D.new()
	_general.set_script(_GeneralScript)
	_general.setup(0, "red", Vector3(map_size.x / 2.0, 0.0, map_size.y / 2.0),
		general_cfg, false, map_size, null)
	add_child(_general)

	var count = int(general_cfg.get("dummy_soldier_count", 30))
	var soldiers: Array = []
	for i in range(count):
		var dummy = RigidBody3D.new()
		dummy.set_script(_DummyScript)
		dummy.setup(_general, i, count, general_cfg, false)
		add_child(dummy)
		soldiers.append(dummy)
	_general.register_dummy_soldiers(soldiers)

	_setup_visuals(map_size)

	_renderer = _AIRendererScript.new({"mode": "ai_debug", "sample_rate": 30, "calibrate": false})
	_renderer.register("Formation", _general, ["formation_state", "path_buffer_size"], "formation")

	_ux_observer = _UXObserverScript.new()
	_ux_observer.setup(self, get_viewport(), null, {
		"screenshot_interval": 999999.0,
		"screenshot_dir": "res://tests/screenshots/"
	})
	_last_formation_state = _general.get("_formation_state") if is_instance_valid(_general) else ""

	if _assert_mode:
		print("[VISUAL] 断言模式启动 — 将在第%d帧发出移动指令" % _MOVE_FRAME)
	elif _benchmark_mode:
		_setup_benchmark()
		print("[VISUAL] Benchmark 模式启动 — 将执行 %d 个场景" % _BenchmarkPlayerScript.SCENES.size())
	else:
		print("[VISUAL] Ready — dummies=%d  右键移动 Space切换待命" % count)


func _physics_process(_delta: float) -> void:
	_frame += 1

	if _assert_mode:
		_run_assert_flow()

	if _benchmark_mode and _benchmark_player != null:
		_benchmark_player.tick(_general, _frame)

	if _renderer and is_instance_valid(_general) and _general.has_method("get_formation_summary"):
		var summary = _general.get_formation_summary()
		_renderer.set_extra(summary)

		var cur_state = _general.get("_formation_state")

		## Benchmark 模式：逐帧记录指标
		if _benchmark_mode and _metrics_recorder != null:
			_metrics_recorder.record_frame(_frame, summary, cur_state)

		## 状态变化：截图 + 记录进入 deployed 的帧号
		if cur_state != _last_formation_state and _last_formation_state != "":
			print("[VISUAL] formation_state: %s → %s (frame=%d)" % [_last_formation_state, cur_state, _frame])
			if _ux_observer:
				_ux_observer.take_screenshot("state_%s_f%d" % [cur_state, _frame])
			if cur_state == "deployed":
				_deployed_since_frame = _frame
				_last_deploy_screenshot_frame = _frame
				print("[DEPLOY] 进入 deployed，开始追踪收敛")
				_print_deploy_distribution(0)
			else:
				_deployed_since_frame = -1
		_last_formation_state = cur_state

		## deployed 期间：每 60 帧截图 + 每 30 帧详细分布日志
		if cur_state == "deployed" and _deployed_since_frame >= 0:
			var t = _frame - _deployed_since_frame
			if _frame - _last_deploy_screenshot_frame >= _DEPLOY_SCREENSHOT_INTERVAL:
				_last_deploy_screenshot_frame = _frame
				if _ux_observer:
					_ux_observer.take_screenshot("deployed_%ds" % (t / 60))
			if t > 0 and t % 30 == 0:
				_print_deploy_distribution(t)

		## 每 10 帧基础日志（含新增体验质量指标）
		if _frame % 10 == 0:
			var avg_err = summary.get("avg_slot_error", -1)
			var waiting = summary.get("waiting_count", -1)
			var deploy_timer = _general.get("_deploy_timer")
			var std_dev = summary.get("pos_std_dev", -1)
			var lat_spread = summary.get("lateral_spread", -1)
			var coh = summary.get("velocity_coherence", -1)
			var overshoot = summary.get("overshoot_count", 0)
			var freeze_r = summary.get("freeze_rate", 0.0)
			print("[DBG f=%d] state=%s timer=%s avg_err=%.1f waiting=%d | std=%.0f lat=%.0f coh=%.2f overshoot=%d freeze=%.0f%%" % [
				_frame, cur_state, str(deploy_timer), avg_err, waiting,
				std_dev, lat_spread, coh, overshoot, freeze_r * 100.0
			])

		## 纵队槽位详细诊断：将领开始移动后，每5帧输出 path_buffer 和士兵waiting状态到文件
		if cur_state == "marching" and is_instance_valid(_general):
			var pb = _general.get("_path_buffer") if _general.get("_path_buffer") != null else []
			var gp = _general.global_position
			var has_cmd = _general.get("has_command") == true
			if has_cmd and _frame % 5 == 1:
				var pb_summary = ""
				for k in range(min(pb.size(), 6)):
					pb_summary += " [%d](%.0f,%.0f)" % [k, pb[k].x, pb[k].z]
				if pb_summary == "":
					pb_summary = " (空)"
				var log_line = "[SLOT-DIAG f=%d] general=(%.0f,%.0f) pb_size=%d path:%s\n" % [
					_frame, gp.x, gp.z, pb.size(), pb_summary]
				var soldiers = _general.get("_dummy_soldiers") if _general.get("_dummy_soldiers") != null else []
				var slot_assign = _general.get("_slot_assignment") if _general.get("_slot_assignment") != null else {}
				var far_list = []
				var normal_list = []
				var waiting_count = 0
				for i in range(soldiers.size()):
					var s = soldiers[i]
					if not is_instance_valid(s): continue
					var is_waiting = s.get("_waiting") == true
					if is_waiting:
						waiting_count += 1
						continue
					var slot = _general.get_formation_slot(i, soldiers.size(), s.global_position)
					var dist = s.global_position.distance_to(slot)
					var slot_idx = slot_assign.get(i, i)
					var row = slot_idx / 2
					var info = "s[%d]→sl[%d](row=%d) dist=%.0f pos=(%.0f,%.0f)→(%.0f,%.0f)" % [
						i, slot_idx, row, dist,
						s.global_position.x, s.global_position.z, slot.x, slot.z
					]
					if dist > 300.0:
						far_list.append(info)
					else:
						normal_list.append(info)
				log_line += "  waiting=%d far(>300)=%d normal=%d\n" % [waiting_count, far_list.size(), normal_list.size()]
				for entry in far_list:
					log_line += "  FAR: %s\n" % entry
				## 写到专用诊断文件
				var f = FileAccess.open("res://tests/logs/slot_diag.log", FileAccess.WRITE_READ if _frame > 10 else FileAccess.WRITE)
				if f == null:
					f = FileAccess.open("res://tests/logs/slot_diag.log", FileAccess.WRITE)
				if f:
					f.seek_end()
					f.store_string(log_line)
					f.close()

		## 19C：体验质量告警 + 截图
		_check_quality_warnings(summary, cur_state)

		_renderer.tick(_frame)

	_update_debug_visuals()


## deployed 期间输出每个士兵距槽位的距离分布
func _print_deploy_distribution(frames_in_deploy: int) -> void:
	if not is_instance_valid(_general):
		return
	var soldiers = _general.get("_dummy_soldiers") if _general.get("_dummy_soldiers") != null else []
	var total = soldiers.size()
	if total == 0:
		return

	var buckets = {"arrived(<15)": 0, "close(15-50)": 0, "mid(50-150)": 0, "far(>150)": 0}
	var max_err := 0.0
	var frozen_count := 0
	var waiting_count := 0
	var details: Array = []

	for i in range(total):
		var s = soldiers[i]
		if not is_instance_valid(s):
			continue
		var slot = _general.get_formation_slot(i, total, s.global_position)
		var dist = s.global_position.distance_to(slot)
		if s.freeze:
			frozen_count += 1
		if s.get("_waiting"):
			waiting_count += 1
		if dist > max_err:
			max_err = dist
		if dist < 15:
			buckets["arrived(<15)"] += 1
		elif dist < 50:
			buckets["close(15-50)"] += 1
		elif dist < 150:
			buckets["mid(50-150)"] += 1
		else:
			buckets["far(>150)"] += 1
			details.append("  s[%d] dist=%.0f frozen=%s waiting=%s" % [
				i, dist, str(s.freeze), str(s.get("_waiting"))
			])

	var anchor = _general.get("_deploy_anchor")
	print("[DEPLOY t+%df] arrived=%d close=%d mid=%d far=%d | max_err=%.0f frozen=%d waiting=%d | anchor=%s" % [
		frames_in_deploy,
		buckets["arrived(<15)"], buckets["close(15-50)"],
		buckets["mid(50-150)"], buckets["far(>150)"],
		max_err, frozen_count, waiting_count,
		str(anchor)
	])
	for d in details:
		print(d)


func _setup_benchmark() -> void:
	_benchmark_player = _BenchmarkPlayerScript.new()
	_metrics_recorder = _MetricsRecorderScript.new()
	_metrics_recorder.setup(_general)

	## 连接剧本信号
	_benchmark_player.scene_started.connect(func(sid, sname):
		_metrics_recorder.on_scene_started(sid, sname)
	)
	_benchmark_player.scene_ended.connect(func(sid, sname, result):
		_metrics_recorder.on_scene_ended(sid, sname, result)
	)
	_benchmark_player.benchmark_done.connect(func():
		_metrics_recorder.finalize()
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()
	)


func _run_assert_flow() -> void:
	if _assert_result != "pending":
		return
	if _frame == _MOVE_FRAME:
		if is_instance_valid(_general):
			var target = _general.global_position + _MOVE_TARGET_OFFSET
			_general.move_to(target)
			print("[ASSERT] frame=%d 发出移动指令 → (%.0f, 0, %.0f)" % [_frame, target.x, target.z])
		return
	if _frame < _MOVE_FRAME:
		return
	if _frame >= _MOVE_FRAME + _ASSERT_TIMEOUT:
		_assert_result = "fail"
		print("[ASSERT FAIL] 超时%d帧未切换到deployed" % _ASSERT_TIMEOUT)
		get_tree().quit()
		return
	if is_instance_valid(_general) and _general.get("_formation_state") == "deployed":
		_assert_result = "pass"
		var elapsed = _frame - _MOVE_FRAME
		print("[ASSERT PASS] deployed 在第%d帧触发（移动后%d帧，%.1fs）" % [_frame, elapsed, elapsed / 60.0])
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()


func _update_debug_visuals() -> void:
	if not is_instance_valid(_general):
		return
	for node in _debug_lines + _debug_waiting + _debug_path_dots:
		if is_instance_valid(node):
			node.queue_free()
	_debug_lines.clear()
	_debug_waiting.clear()
	_debug_path_dots.clear()

	var soldiers = _general.get("_dummy_soldiers") if _general.get("_dummy_soldiers") != null else []
	var total = soldiers.size()
	for i in range(total):
		var s = soldiers[i]
		if not is_instance_valid(s):
			continue
		var ideal = _general.get_formation_slot(i, total, s.global_position)
		var err = s.global_position.distance_to(ideal)
		var is_waiting = err < 1.0 and _general.get_formation_state() == "marching"
		if is_waiting:
			var marker = _make_sphere(s.global_position + Vector3(0, 15, 0), 5.0, Color(1, 0.1, 0.1))
			add_child(marker)
			_debug_waiting.append(marker)
		else:
			_make_line(s.global_position + Vector3(0, 5, 0), ideal + Vector3(0, 5, 0), Color(0.1, 0.9, 0.2))

	var pb = _general.get("_path_buffer") if _general.get("_path_buffer") != null else []
	for j in range(min(pb.size(), 20)):
		var dot = _make_sphere(pb[j] + Vector3(0, 3, 0), 3.0, Color(1.0, 0.9, 0.1))
		add_child(dot)
		_debug_path_dots.append(dot)


func _make_sphere(pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var inst = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = mat
	inst.mesh = sphere
	inst.position = pos
	return inst


func _make_line(from: Vector3, to: Vector3, color: Color) -> void:
	var diff = to - from
	var length = diff.length()
	if length < 1.0:
		return
	var inst = MeshInstance3D.new()
	var capsule = CapsuleMesh.new()
	capsule.radius = 1.5
	capsule.height = length
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	capsule.material = mat
	inst.mesh = capsule
	inst.position = (from + to) * 0.5
	if diff.length_squared() > 0.001:
		inst.basis = Basis.looking_at(diff.normalized(), Vector3.UP).rotated(
			Basis.looking_at(diff.normalized(), Vector3.UP).x, PI * 0.5)
	add_child(inst)
	_debug_lines.append(inst)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
	   and event.button_index == MOUSE_BUTTON_RIGHT \
	   and event.pressed:
		if _general == null or not is_instance_valid(_general):
			return
		var target = _raycast_ground(event.position)
		if target != Vector3.ZERO:
			_general.move_to(target)
			print("[VISUAL] move_to (%.0f, 0, %.0f)" % [target.x, target.z])
			if _ux_observer:
				_ux_observer.take_screenshot("move_cmd_f%d" % _frame)


func _raycast_ground(screen_pos: Vector2) -> Vector3:
	if _camera == null:
		return Vector3.ZERO
	var from = _camera.project_ray_origin(screen_pos)
	var dir  = _camera.project_ray_normal(screen_pos)
	if abs(dir.y) < 0.0001:
		return Vector3.ZERO
	var t = (_ground_y - from.y) / dir.y
	if t < 0.0:
		return Vector3.ZERO
	return from + dir * t


func _setup_visuals(map_size: Vector2) -> void:
	var map_w = map_size.x
	var map_h = map_size.y
	var cam_height = map_h * 1.2
	var lateral = cam_height / sqrt(2.0)
	var map_diag = sqrt(map_w * map_w + map_h * map_h)
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = map_diag * 0.55
	_camera.position = Vector3(map_w / 2.0 - lateral, cam_height, map_h / 2.0 + lateral)
	_camera.rotation_degrees = Vector3(-45.0, -45.0, 0.0)
	_camera.near = 1.0
	_camera.far = cam_height * 4.0
	add_child(_camera)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -45.0, 0.0)
	light.light_energy = 1.2
	add_child(light)
	var ground = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(map_w, map_h)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.26, 0.20)
	plane.material = mat
	ground.mesh = plane
	ground.position = Vector3(map_w / 2.0, -1.0, map_h / 2.0)
	add_child(ground)


func _load_config() -> Dictionary:
	var script_path: String = get_script().resource_path
	var path = script_path.get_base_dir() + "/config.json"
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text = f.get_as_text()
	f.close()
	var result = JSON.parse_string(text)
	return result if result is Dictionary else {}


func _load_global_unit_config(unit_type: String) -> Dictionary:
	var f = FileAccess.open("res://config.json", FileAccess.READ)
	if f == null:
		return {}
	var text = f.get_as_text()
	f.close()
	var cfg = JSON.parse_string(text)
	if cfg is Dictionary:
		return cfg.get(unit_type, {})
	return {}


## 19C：体验质量告警检查 — 阈值触发时输出 WARN + 事件截图
var _warn_cooldown: Dictionary = {}  ## 避免同类告警每帧刷屏：key=warn_id, value=剩余冷却帧数

func _check_quality_warnings(summary: Dictionary, cur_state: String) -> void:
	## 冷却计数递减
	for k in _warn_cooldown.keys():
		_warn_cooldown[k] -= 1
		if _warn_cooldown[k] <= 0:
			_warn_cooldown.erase(k)

	var std_dev: float = summary.get("pos_std_dev", -1.0)
	var lat: float = summary.get("lateral_spread", -1.0)
	var coh: float = summary.get("velocity_coherence", 1.0)
	var overshoot: int = summary.get("overshoot_count", 0)
	var freeze_r: float = summary.get("freeze_rate", 0.0)

	## 挤团（行军中）
	if cur_state == "marching" and std_dev >= 0 and std_dev < 30.0:
		_fire_warning("clump", "[WARN] 挤团！pos_std_dev=%.0f < 30" % std_dev)
	## 散乱
	if std_dev > 400.0:
		_fire_warning("scatter", "[WARN] 散乱！pos_std_dev=%.0f > 400" % std_dev)
	## 队形崩溃
	if cur_state == "marching" and lat >= 0 and lat > 120.0:
		_fire_warning("lat_collapse", "[WARN] 队形崩溃！lateral_spread=%.0f > 120" % lat)
	## 各奔东西
	if cur_state == "marching" and coh < 0.2:
		_fire_warning("incoherent", "[WARN] 方向混乱！velocity_coherence=%.2f < 0.2" % coh)
	## 过冲
	if overshoot > 3:
		_fire_warning("overshoot", "[WARN] 过冲！overshoot_count=%d > 3" % overshoot)
	## 横阵未稳定（deployed 超过 60 帧）
	if cur_state == "deployed" and _deployed_since_frame >= 0:
		var t_in_deploy = _frame - _deployed_since_frame
		if t_in_deploy > 60 and freeze_r < 0.9:
			_fire_warning("not_frozen", "[WARN] 横阵未稳定！freeze_rate=%.0f%% < 90%%" % (freeze_r * 100.0))


func _fire_warning(warn_id: String, msg: String) -> void:
	if _warn_cooldown.has(warn_id):
		return
	_warn_cooldown[warn_id] = 120  ## 120 帧冷却（约 2 秒）
	print(msg + " (f=%d)" % _frame)
	if _ux_observer:
		_ux_observer.take_screenshot("warn_%s_f%d" % [warn_id, _frame])
