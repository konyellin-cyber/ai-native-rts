extends RefCounted
class_name BenchmarkPlayer

## Phase 19 Benchmark 剧本执行器
## 执行 4 个固定场景，覆盖行军/展开/切换的主要体验路径。
## 每个场景结束时发出 scene_ended(scene_id, result_dict) 信号。
## 全部场景结束时发出 benchmark_done() 信号。

signal scene_started(scene_id: int, scene_name: String)
signal scene_ended(scene_id: int, scene_name: String, result: Dictionary)
signal benchmark_done()

## 场景定义
const SCENES = [
	{
		"id": 1,
		"name": "S1_straight_long",
		"desc": "直线长跑 300 units → 停 → 等待 deployed",
		"moves": [Vector3(300.0, 0.0, 0.0)],
		"timeout": 900,
	},
	{
		"id": 2,
		"name": "S2_turn",
		"desc": "转弯：前进 200 → 左转 90° → 再前进 200 → 停 → deployed",
		"moves": [Vector3(200.0, 0.0, 0.0), Vector3(200.0, 0.0, -200.0)],
		"timeout": 1200,
	},
	{
		"id": 3,
		"name": "S3_short",
		"desc": "短距离 80 units（path_buffer 不足时行为）",
		"moves": [Vector3(80.0, 0.0, 0.0)],
		"timeout": 600,
	},
	{
		"id": 4,
		"name": "S4_switch",
		"desc": "移动→deployed→再移动→再deployed（状态切换稳定性）",
		"moves": [Vector3(200.0, 0.0, 0.0), Vector3(0.0, 0.0, -200.0)],
		"timeout": 2400,
		"multi_deploy": true,  ## 需要经历 2 次 deployed
	},
]

const SCENE_START_DELAY: int = 60   ## 每个场景开始前等待 N 帧，让物理稳定
const MOVE_DELAY: int = 30          ## 发出移动指令前的等待帧

var _general: Node = null
var _frame: int = 0

## 状态机
var _current_scene_idx: int = 0
var _scene_state: String = "idle"   ## idle / waiting_start / moving / waiting_deploy / done
var _scene_frame: int = 0           ## 当前场景已运行帧数
var _move_idx: int = 0              ## 当前场景的移动步骤索引
var _deploy_count: int = 0          ## 当前场景已触发 deployed 次数
var _last_formation_state: String = ""
var _scene_start_pos: Vector3 = Vector3.ZERO

## 每帧由 bootstrap 调用
func tick(general: Node, frame: int) -> void:
	_general = general
	_frame = frame

	if _scene_state == "idle":
		if _current_scene_idx < SCENES.size():
			_start_scene(_current_scene_idx)
		return

	if _scene_state == "done":
		return

	_scene_frame += 1
	var scene = SCENES[_current_scene_idx]

	## 超时保护
	if _scene_frame > scene["timeout"]:
		print("[BENCH] ⚠️ 场景 %s 超时（%d帧），强制跳过" % [scene["name"], scene["timeout"]])
		_end_scene({"timeout": true})
		return

	## 追踪 formation_state 变化
	var cur_state: String = _general.get("_formation_state") if is_instance_valid(_general) else "marching"
	if cur_state != _last_formation_state:
		_last_formation_state = cur_state

	match _scene_state:
		"waiting_start":
			if _scene_frame >= SCENE_START_DELAY:
				_scene_state = "moving"
				_move_idx = 0
				_issue_next_move()

		"moving":
			## 等 MOVE_DELAY 帧后发下一条移动指令（如果有多段）
			## 检测是否该切换到等待 deployed
			if cur_state == "deployed":
				_deploy_count += 1
				var need_deploys = 2 if scene.get("multi_deploy", false) else 1
				if _deploy_count >= need_deploys:
					## 最后一次 deployed 进入等待稳定
					_scene_state = "waiting_deploy"
				else:
					## 还需要继续移动
					_move_idx += 1
					if _move_idx < (scene["moves"] as Array).size():
						await _general.get_tree().create_timer(0.5).timeout
						_issue_next_move()

		"waiting_deploy":
			## 等待 freeze_rate = 1.0 或超时
			var summary = _general.get_formation_summary() if _general.has_method("get_formation_summary") else {}
			var fr: float = summary.get("freeze_rate", 0.0)
			if fr >= 1.0:
				## 横阵完全稳定，再等 30 帧确认
				if not _scene_frame_stable_since > 0:
					_scene_frame_stable_since = _scene_frame
				if _scene_frame - _scene_frame_stable_since >= 30:
					_end_scene({"completed": true, "freeze_rate": fr})


var _scene_frame_stable_since: int = 0


func _start_scene(idx: int) -> void:
	var scene = SCENES[idx]
	print("[BENCH] ▶ 开始场景 %d/%d: %s" % [idx + 1, SCENES.size(), scene["desc"]])
	_scene_state = "waiting_start"
	_scene_frame = 0
	_deploy_count = 0
	_move_idx = 0
	_scene_frame_stable_since = 0
	_last_formation_state = _general.get("_formation_state") if is_instance_valid(_general) else "marching"
	_scene_start_pos = _general.global_position if is_instance_valid(_general) else Vector3.ZERO
	scene_started.emit(scene["id"], scene["name"])


func _issue_next_move() -> void:
	if not is_instance_valid(_general):
		return
	var scene = SCENES[_current_scene_idx]
	var moves = scene["moves"] as Array
	if _move_idx >= moves.size():
		return
	## 目标 = 场景起点 + 当前步及之前所有步偏移的累加（接续移动）
	var target = _scene_start_pos
	for i in range(_move_idx + 1):
		target += moves[i]
	_general.move_to(target)
	print("[BENCH]   → move_to (%.0f, 0, %.0f) [step %d/%d]" % [
		target.x, target.z, _move_idx + 1, moves.size()])


func _end_scene(result: Dictionary) -> void:
	var scene = SCENES[_current_scene_idx]
	result["scene_id"] = scene["id"]
	result["scene_name"] = scene["name"]
	result["frames"] = _scene_frame
	print("[BENCH] ■ 场景 %s 结束（%d帧）" % [scene["name"], _scene_frame])
	scene_ended.emit(scene["id"], scene["name"], result)

	_current_scene_idx += 1
	_scene_state = "idle"
	_scene_frame = 0

	if _current_scene_idx >= SCENES.size():
		print("[BENCH] ✅ 全部场景完成")
		_scene_state = "done"
		benchmark_done.emit()
