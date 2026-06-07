extends Node3D

## Phase 24 — mass_battle bootstrap
## 固定脚本对冲场景：双将领直冲，相遇即近战，一方全灭结束。
## 支持 headless（输出 battle_result.json）和窗口模式（视觉演示）。

const _GeneralScript        = preload("res://scripts/general_unit.gd")
const _MBEScript            = preload("res://scripts/mass_battle_engine.gd")
const _FlowFieldMgrScript   = preload("res://scripts/flow_field_manager.gd")
const _BattleRendererScript = preload("res://scripts/battle_renderer.gd")
const _BattleSpriteRendererScript = preload("res://scripts/battle_sprite_renderer.gd")
const _ParticlePoolScript   = preload("res://scripts/impact_particle_pool.gd")

const _UXObserverScript = preload("res://tools/ai-renderer/ux_observer.gd")

## ── 节点引用 ──────────────────────────────────────────
var _red_general:   CharacterBody3D = null
var _blue_general:  CharacterBody3D = null
var _mbe:           Node = null
var _ffm:           Node = null
var _renderer:      Node = null
var _particles:     Node = null
var _ux_observer   = null   ## UXObserver 实例（窗口模式）

## ── 配置 / 状态 ───────────────────────────────────────
var _config:      Dictionary = {}
var _is_headless: bool = false
var _frame:       int  = 0
var _map_size:    Vector2 = Vector2(2560.0, 1664.0)

## 固定行军目标（将领直线冲向对方起点）
var _red_target:  Vector3 = Vector3.ZERO
var _blue_target: Vector3 = Vector3.ZERO

## 日志 / 结果
var _perf_log:       Array = []   ## Array[Dictionary]，每 60 帧一条
var _result_written: bool  = false

## 26H.4 阵线方差窗口（最近 10 条采样）
## 存储相邻帧 front_line_x 的逐差，衡量"平滑性"（推进不算跳变）
var _front_line_prev: float = 0.0
var _front_line_prev_valid: bool = false
var _front_line_delta_window: Array = []  ## Array[float]，最新 10 次 Δfront_x
## 26H.6 阵线推进位移追踪
var _front_line_x_initial: float = 0.0
var _front_line_initial_set: bool = false

## 截图控制
var _prev_alive_red:  int = 250
var _prev_alive_blue: int = 250
var _battle_started:  bool = false
var _screenshot_count: int = 0
var _screenshot_dir: String = "res://tests/screenshots/mass_battle/"

## Debug HUD
var _hud_label: Label = null
var _camera: Camera3D = null  ## 跟随摄像机引用


## ─────────────────────────────────────────────────────
## 初始化
## ─────────────────────────────────────────────────────

func _ready() -> void:
	_is_headless = DisplayServer.get_name() == "headless"
	_config       = _load_config()
	if _config.is_empty():
		push_error("[MassBattle] 配置加载失败")
		_quit(1)
		return

	## 从场景路径派生截图和结果输出目录
	var scene_dir_name: String = get_scene_file_path().get_base_dir().get_file()
	if scene_dir_name == "":
		scene_dir_name = "mass_battle"
	_screenshot_dir = "res://tests/screenshots/%s/" % scene_dir_name

	_map_size = Vector2(
		float(_config.get("map", {}).get("width",  2560.0)),
		float(_config.get("map", {}).get("height", 1664.0))
	)
	var mb: Dictionary = _config.get("mass_battle", {})

	## ── 创建将领 ──
	var gen_cfg: Dictionary = _load_global_unit_config("general")
	## 合并 mass_battle 场景 config 里的 general 覆盖项
	var local_gen: Dictionary = _config.get("general", {})
	for k in local_gen:
		gen_cfg[k] = local_gen[k]

	## 红方：左侧 20%
	var red_pos  := Vector3(_map_size.x * 0.20, 0.0, _map_size.y * 0.5)
	## 蓝方：右侧 80%
	var blue_pos := Vector3(_map_size.x * 0.80, 0.0, _map_size.y * 0.5)

	## 将领目标：沿X轴水平直冲，Z保持不变（将领带兵维持横排阵型）
	_red_target  = Vector3(_map_size.x * 0.80, 0.0, red_pos.z)   ## 红方冲向右侧同Z点
	_blue_target = Vector3(_map_size.x * 0.20, 0.0, blue_pos.z)  ## 蓝方冲向左侧同Z点

	_red_general  = _make_general(0, "red",  red_pos,  gen_cfg)
	_blue_general = _make_general(1, "blue", blue_pos, gen_cfg)
	add_child(_red_general)
	add_child(_blue_general)
	## mass_battle 场景将领只作逻辑节点，不渲染大模型（避免遮挡战场视野）
	if not _is_headless:
		_red_general.visible  = false
		_blue_general.visible = false

	## ── FlowFieldManager ──
	_ffm = _FlowFieldMgrScript.new()
	_ffm.setup(_config)
	_ffm.register_general(0, _red_general)
	_ffm.register_general(1, _blue_general)
	add_child(_ffm)

	## ── MassBattleEngine ──
	_mbe = _MBEScript.new()
	_mbe.setup(_config, _red_general, _blue_general, _map_size, _is_headless)
	_mbe.set_flow_field_manager(_ffm)
	_mbe.set_march_targets(_red_target, _blue_target)  ## 固定目标，headless 下保证士兵移动
	add_child(_mbe)

	## ── BattleRenderer ──
	var renderer_mode: String = String(mb.get("renderer_mode", "3d_model"))
	_renderer = _BattleSpriteRendererScript.new() if renderer_mode == "sprite2d" else _BattleRendererScript.new()
	var count_per_side: int = int(mb.get("soldier_count_per_side", 250))
	_renderer.init(count_per_side, _config, _is_headless)
	add_child(_renderer)
	_mbe.set_renderer(_renderer)

	## ── 受击粒子池 ──
	_particles = _ParticlePoolScript.new()
	_particles.init(_is_headless, mb)
	add_child(_particles)
	_mbe.set_hit_callback(Callable(_particles, "emit_at"))

	## ── 地面（窗口模式）──
	if not _is_headless:
		_setup_ground()
		_setup_camera()
		_setup_hud()
		## UX Observer（截图）
		_ux_observer = _UXObserverScript.new()
		_ux_observer.setup(self, get_viewport(), null, {
			"screenshot_interval": 999999.0,
			"screenshot_dir": _screenshot_dir,
		})

	print("[MassBattle] ready — headless=%s  soldiers_per_side=%d" % [
		str(_is_headless), count_per_side])


## ─────────────────────────────────────────────────────
## 主循环
## ─────────────────────────────────────────────────────

func _physics_process(_delta: float) -> void:
	_frame += 1

	## frame 1：发出行军指令（等 _ready 完成后第一帧）
	if _frame == 1:
		_red_general.move_to(_red_target)
		_blue_general.move_to(_blue_target)
		print("[MassBattle] 行军指令发出 — red→(%.0f,%.0f)  blue→(%.0f,%.0f)" % [
			_red_target.x, _red_target.z, _blue_target.x, _blue_target.z])

	## FlowFieldManager 每帧 tick
	if _ffm != null:
		_ffm.tick()

	## 窗口模式：事件驱动截图 + HUD + 摄像机跟随
	if not _is_headless:
		if _ux_observer != null:
			_take_event_screenshots()
		_update_hud()
		_follow_camera()

	## 每 60 帧：性能日志 + 胜负检查
	if _frame % 60 == 0:
		_log_perf()
		_check_battle_end()

	## 性能基准：到达 perf_test_max_frames 后强制结束（优化前后对比用）
	var max_frames: int = int(_config.get("mass_battle", {}).get("perf_test_max_frames", 0))
	if max_frames > 0 and _frame >= max_frames and not _result_written:
		print("[MassBattle] 到达 perf_test_max_frames=%d，强制结束并写入结果" % max_frames)
		var alive_r: int = _mbe.get_alive_count(0)
		var alive_b: int = _mbe.get_alive_count(1)
		_write_result("timeout", alive_r, alive_b)
		_result_written = true
		if _is_headless:
			_quit(0)
		else:
			## 窗口模式：写完结果仍保持场景，便于目视残局
			pass


## ─────────────────────────────────────────────────────
## 辅助
## ─────────────────────────────────────────────────────

func _take_event_screenshots() -> void:
	if _mbe == null:
		return
	var alive_red:  int = _mbe.get_alive_count(0)
	var alive_blue: int = _mbe.get_alive_count(1)

	## 定时截图：行军阶段每 200 帧一张（捕捉横排队形）
	if _frame == 200:
		_shot("01a_march_early_f%d" % _frame)
	if _frame == 400:
		_shot("01b_march_mid_f%d" % _frame)
	if _frame == 600:
		_shot("01c_march_late_f%d" % _frame)

	## 事件截图：首次交战
	if not _battle_started and (alive_red < _prev_alive_red or alive_blue < _prev_alive_blue):
		_battle_started = true
		_shot("02_collision_f%d" % _frame)

	## 30 帧后再截：捕捉碰撞冲击波
	if _battle_started and _frame == _get_battle_start_frame() + 30:
		_shot("03_shockwave_f%d" % _frame)

	## 蓝方损失里程碑
	if _prev_alive_blue > 200 and alive_blue <= 200:
		_shot("04a_blue200_f%d" % _frame)
	if _prev_alive_blue > 150 and alive_blue <= 150:
		_shot("04b_blue150_f%d" % _frame)
	if _prev_alive_blue > 100 and alive_blue <= 100:
		_shot("04c_blue100_f%d" % _frame)
	if _prev_alive_blue > 50 and alive_blue <= 50:
		_shot("05a_blue50_f%d" % _frame)
	if _prev_alive_blue > 10 and alive_blue <= 10:
		_shot("05b_blue10_f%d" % _frame)

	## 战斗结束
	if _result_written and _prev_alive_blue > 0 and alive_blue == 0:
		_shot("06_end_f%d" % _frame)

	_prev_alive_red  = alive_red
	_prev_alive_blue = alive_blue


var _battle_start_frame: int = -1

func _get_battle_start_frame() -> int:
	if _battle_start_frame < 0 and _battle_started:
		_battle_start_frame = _frame
	return _battle_start_frame


func _shot(name: String) -> void:
	if _ux_observer == null:
		return
	_screenshot_count += 1
	_ux_observer.take_screenshot("%02d_%s" % [_screenshot_count, name])


func _setup_hud() -> void:
	## Canvas Layer → Label，常驻左上角
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	_hud_label = Label.new()
	_hud_label.position = Vector2(12, 8)
	_hud_label.add_theme_font_size_override("font_size", 18)
	_hud_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_hud_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_hud_label.add_theme_constant_override("shadow_offset_x", 1)
	_hud_label.add_theme_constant_override("shadow_offset_y", 1)
	canvas.add_child(_hud_label)


func _update_hud() -> void:
	if _hud_label == null or _mbe == null:
		return
	var stats: Dictionary = _mbe.get_debug_stats()
	var alive_r: int = stats.get("alive_red", 0)
	var alive_b: int = stats.get("alive_blue", 0)
	var fps: float = Engine.get_frames_per_second()
	var phase: String = "MARCHING" if not _battle_started else ("BATTLE" if alive_b > 0 else "END")
	var crowd_us: int = stats.get("crowd_us", 0)
	var overlap: int  = stats.get("overlap_pairs", 0)

	_hud_label.text = (
		"FPS: %.0f  Frame: %d\n" % [fps, _frame] +
		"RED  %-3d  BLUE %-3d\n" % [alive_r, alive_b] +
		"Phase: %s\n" % phase +
		"crowd: %dµs  overlap: %d" % [crowd_us, overlap]
	)


func _make_general(id: int, team: String, pos: Vector3, cfg: Dictionary) -> CharacterBody3D:
	var g := CharacterBody3D.new()
	g.set_script(_GeneralScript)
	g.setup(id, team, pos, cfg, _is_headless, _map_size, null)
	return g


func _log_perf() -> void:
	if _mbe == null:
		return
	var stats: Dictionary = _mbe.get_debug_stats()
	var fps_val: float = Engine.get_frames_per_second() if not _is_headless else 0.0

	## 26H.4 阵线方差（相邻差，衡量平滑性而非位移）
	var flx: float = float(stats.get("front_line_x", 0.0))
	var fl_valid: bool = bool(stats.get("front_line_valid", false))
	if fl_valid:
		if _front_line_prev_valid:
			var delta_fl: float = flx - _front_line_prev
			_front_line_delta_window.append(delta_fl)
			if _front_line_delta_window.size() > 10:
				_front_line_delta_window.pop_front()
		_front_line_prev = flx
		_front_line_prev_valid = true
		## 26H.6 初始阵线位置（首次有效时记录）
		if not _front_line_initial_set:
			_front_line_x_initial = flx
			_front_line_initial_set = true
	else:
		## 阵线无效时重置连续性，防止下次 valid 时计算跨越无效期的差值
		_front_line_prev_valid = false

	var front_variance: float = _calc_front_variance()

	## 26C.5 contact_factor 分布
	var histogram: Dictionary = _mbe.get_contact_histogram()

	var entry := {
		"frame":            _frame,
		"fps":              fps_val,
		"alive_red":        stats.get("alive_red",        0),
		"alive_blue":       stats.get("alive_blue",       0),
		"crowd_us":         stats.get("crowd_us",         0),
		"combat_us":        stats.get("combat_us",        0),
		"overlap_pairs":    stats.get("overlap_pairs",    0),
		"contact_switches": stats.get("contact_switches", 0),
		"front_line_x":     flx,
		"front_variance":   front_variance,
		"cf_low":           histogram.get("low",  0),
		"cf_mid":           histogram.get("mid",  0),
		"cf_high":          histogram.get("high", 0),
	}
	_perf_log.append(entry)

	if _is_headless:
		print("[PERF] frame=%d  crowd=%dµs  overlap=%d  switches=%d  front_x=%.1f  var=%.2f  cf=[%d/%d/%d]  red=%d  blue=%d" % [
			_frame, entry.crowd_us,
			entry.overlap_pairs, entry.contact_switches,
			flx, front_variance,
			entry.cf_low, entry.cf_mid, entry.cf_high,
			entry.alive_red, entry.alive_blue])
	else:
		print("[PERF] frame=%d  fps=%.1f  crowd=%dµs  overlap=%d  cf=[%d/%d/%d]  red=%d  blue=%d" % [
			_frame, fps_val, entry.crowd_us,
			entry.overlap_pairs,
			entry.cf_low, entry.cf_mid, entry.cf_high,
			entry.alive_red, entry.alive_blue])


func _calc_front_variance() -> float:
	## 计算相邻帧 front_line_x 差值的方差（衡量平滑性，推进时差值稳定，跳变时方差大）
	if _front_line_delta_window.size() < 2:
		return 0.0
	var sum: float = 0.0
	for v in _front_line_delta_window:
		sum += v
	var mean: float = sum / float(_front_line_delta_window.size())
	var sq_sum: float = 0.0
	for v in _front_line_delta_window:
		sq_sum += (v - mean) * (v - mean)
	return sq_sum / float(_front_line_delta_window.size())


func _check_battle_end() -> void:
	if _result_written or _mbe == null:
		return
	var alive_red:  int = _mbe.get_alive_count(0)
	var alive_blue: int = _mbe.get_alive_count(1)
	if alive_red > 0 and alive_blue > 0:
		return

	## 战斗结束
	var winner: String = "draw"
	if alive_red > 0 and alive_blue == 0:
		winner = "red"
	elif alive_blue > 0 and alive_red == 0:
		winner = "blue"

	print("[MassBattle] 战斗结束！winner=%s  red_survivors=%d  blue_survivors=%d  frames=%d" % [
		winner, alive_red, alive_blue, _frame])

	_write_result(winner, alive_red, alive_blue)
	_result_written = true

	## headless 自动退出；窗口模式保持运行供目视
	if _is_headless:
		_quit(0)


func _write_result(winner: String, red_surv: int, blue_surv: int) -> void:
	## 26H 力学正确性断言
	var validation_errors: Array = []
	var max_overlap: int = 0
	var max_switches: int = 0
	var max_variance: float = 0.0

	for entry in _perf_log:
		var ov: int = int(entry.get("overlap_pairs", 0))
		var sw: int = int(entry.get("contact_switches", 0))
		var va: float = float(entry.get("front_variance", 0.0))
		if ov > max_overlap:   max_overlap  = ov
		if sw > max_switches:  max_switches = sw
		if va > max_variance:  max_variance = va

	if max_overlap > 0:
		validation_errors.append("enemy_overlap_pairs max=%d (expected 0)" % max_overlap)
	if max_switches > 50:
		validation_errors.append("contact_switches max=%d (expected ≤50)" % max_switches)
	if max_variance > 6.0:
		validation_errors.append("front_line_delta_variance max=%.2f (expected ≤6.0, measures smoothness)" % max_variance)
	if winner == "timeout" and _perf_log.size() == 0:
		validation_errors.append("battle_resolved=false (no perf_log entries)")

	## 26H.6 非对称场景：阵线推进位移
	var front_displacement: float = 0.0
	var stats_final: Dictionary = _mbe.get_debug_stats() if _mbe != null else {}
	if _front_line_initial_set and bool(stats_final.get("front_line_valid", false)):
		front_displacement = float(stats_final.get("front_line_x", 0.0)) - _front_line_x_initial

	var result := {
		"winner":                winner,
		"duration_frames":       _frame,
		"red_survivors":         red_surv,
		"blue_survivors":        blue_surv,
		"perf_log":              _perf_log,
		"validation_errors":     validation_errors,
		"front_line_displacement": front_displacement,
	}

	if validation_errors.size() > 0:
		print("[MassBattle] ⚠ 力学验证失败：%s" % str(validation_errors))
	else:
		print("[MassBattle] ✓ 力学验证通过")

	var path := get_scene_file_path().get_base_dir() + "/battle_result.json"
	if path == "/battle_result.json":
		path = "res://tests/gameplay/mass_battle/battle_result.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(result, "\t"))
		f.close()
		print("[MassBattle] battle_result.json 写入完成: %s" % path)
	else:
		push_error("[MassBattle] 无法写入 battle_result.json")


func _quit(code: int) -> void:
	await get_tree().process_frame
	get_tree().quit(code)


## ─────────────────────────────────────────────────────
## 配置加载（仿 general_visual 风格）
## ─────────────────────────────────────────────────────

func _load_config() -> Dictionary:
	## 先读全局 config.json
	var global_path := "res://config.json"
	var local_path  := _get_local_config_path()

	var global_cfg: Dictionary = _read_json(global_path)
	var local_cfg:  Dictionary = _read_json(local_path)

	## 深层合并：local 覆盖 global
	for key in local_cfg:
		global_cfg[key] = local_cfg[key]
	return global_cfg


func _get_local_config_path() -> String:
	var scene_path := get_scene_file_path()
	if scene_path != "":
		return scene_path.get_base_dir() + "/config.json"
	return "res://tests/gameplay/mass_battle/config.json"


func _load_global_unit_config(unit_type: String) -> Dictionary:
	var cfg := _load_config()
	return cfg.get(unit_type, {})


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return {}
	var text: String = f.get_as_text()
	f.close()
	var result = JSON.parse_string(text)
	if result is Dictionary:
		return result
	return {}


## ─────────────────────────────────────────────────────
## 场景可视化辅助（窗口模式）
## ─────────────────────────────────────────────────────

func _setup_ground() -> void:
	var map_w := _map_size.x
	var map_h := _map_size.y
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(map_w, map_h)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.26, 0.20)   ## Phase23 同款地面色
	plane.material = mat
	ground.mesh = plane
	ground.position = Vector3(map_w * 0.5, -1.0, map_h * 0.5)
	add_child(ground)

	## 平行光（Phase23 同款）
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -45.0, 0.0)
	light.light_energy = 1.2
	add_child(light)


func _setup_camera() -> void:
	var map_w := _map_size.x
	var map_h := _map_size.y

	## 完全复用 Phase23 general_visual 的等距摄像机公式
	var cam_height := map_h * 1.2
	var lateral    := cam_height / sqrt(2.0)
	var map_diag   := sqrt(map_w * map_w + map_h * map_h)

	_camera = Camera3D.new()
	_camera.name              = "MainCamera"
	_camera.projection        = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size              = map_diag * 0.55    ## Phase23 同款
	_camera.rotation_degrees  = Vector3(-45.0, -45.0, 0.0)
	_camera.near              = 1.0
	_camera.far               = cam_height * 4.0
	_camera.position          = Vector3(map_w * 0.5 - lateral, cam_height, map_h * 0.5 + lateral)
	add_child(_camera)

	## 环境光（只创建一次，不在 _follow_camera 里每帧重建）
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.08, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.ambient_light_energy = 1.2   ## Phase23 同款，确保模型正面可见
	world_env.environment = env
	add_child(world_env)


func _follow_camera() -> void:
	if _camera == null or _mbe == null:
		return

	## 战斗后动态拉近（缩小 size 聚焦混战区域）
	var map_diag := sqrt(_map_size.x * _map_size.x + _map_size.y * _map_size.y)
	var target_size: float = map_diag * 0.55 if not _battle_started else map_diag * 0.30
	_camera.size = lerp(_camera.size, target_size, 0.02)

	## x 轴跟随战场质心
	var cx: float = _mbe.get_battle_center_x()
	if cx <= 0.0:
		return
	var cam_height := _map_size.y * 1.2
	var lateral    := cam_height / sqrt(2.0)
	var target_x   := cx - lateral
	var cur        := _camera.position
	_camera.position = Vector3(
		lerp(cur.x, target_x, 0.03),
		cur.y,
		cur.z
	)
