extends RefCounted

## SimulatedPlayer — 数据驱动的操作剧本执行器（调度层）
## 职责：按帧推进剧本，维护 wait_frames / wait_signal 等待状态。
## 动作执行委托给 ActionExecutor，信号追踪委托给 SignalTracer。
## 支持从 config.json test_actions 或外部 scenario JSON 文件加载剧本。

var _actions: Array = []
var _current_index: int = 0
var _frame_count: int = 0
var _executed: Array[Dictionary] = []

# wait_frames support
var _wait_until_frame: int = -1

# wait_signal support
var _waiting_signal: String = ""
var _signal_timeout_frame: int = -1
var _signal_received: bool = false

# Scenario metadata
var scenario_name: String = ""
var scenario_description: String = ""

# 子模块（setup 时创建）
var _executor: RefCounted   ## ActionExecutor
var _tracer: RefCounted     ## SignalTracer

# 交互统计（兼容旧接口：外部读取 last_* 指标）
var last_select_count: int = 0
var last_invalid_refs: int = 0
var last_move_commands: int = 0
var last_errors: int = 0

var _interaction_summary: Dictionary = {
	"total_actions": 0,
	"successful": 0,
	"failed": 0,
	"skipped": 0,
	"signals_received": 0,
}


func setup(actions: Array, sel_box: Node, sel_mgr: Node, map_w: float, map_h: float, produce_cb: Callable = Callable(), coord_mode: String = "2d", viewport: Viewport = null) -> void:
	if not actions.is_empty():
		_actions = actions
		_actions.sort_custom(func(a, b): return a.get("frame", 0) < b.get("frame", 0))

	var ExecutorScript = load("res://tools/ai-renderer/action_executor.gd")
	_executor = ExecutorScript.new()
	_executor.setup(sel_box, sel_mgr, map_w, map_h, produce_cb, coord_mode, viewport)

	var TracerScript = load("res://tools/ai-renderer/signal_tracer.gd")
	_tracer = TracerScript.new()


func load_scenario(path: String) -> bool:
	## 从外部 scenario JSON 文件加载剧本；成功返回 true
	if not FileAccess.file_exists(path):
		push_error("[SIM] Scenario file not found: %s" % path)
		return false
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("[SIM] Cannot open scenario file: %s" % path)
		return false
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("[SIM] Failed to parse scenario JSON: %s" % json.get_error_message())
		return false
	var data = json.data
	if not data is Dictionary:
		push_error("[SIM] Scenario root must be a Dictionary")
		return false
	scenario_name = data.get("name", "")
	scenario_description = data.get("description", "")
	var scenario_actions = data.get("actions", [])
	# 空 actions 是合法的：scenario 只跑断言，不发玩家指令
	# 没有显式 frame 的 action 按顺序自动编号
	var auto_frame = 0
	for act in scenario_actions:
		if not act.has("frame"):
			act["frame"] = auto_frame
		if act.get("action") == "wait_frames":
			auto_frame = act["frame"] + int(act.get("params", {}).get("n", 0))
		else:
			auto_frame = act["frame"]
	_actions = scenario_actions
	print("[SIM] Loaded scenario '%s': %d actions" % [scenario_name, _actions.size()])
	return true


func tick(frame: int) -> void:
	_frame_count = frame

	# 等待帧计数
	if _wait_until_frame > 0 and frame < _wait_until_frame:
		return
	_wait_until_frame = -1

	# 等待信号
	if _waiting_signal != "":
		if _signal_received:
			_signal_received = false
			_waiting_signal = ""
		elif _signal_timeout_frame > 0 and frame >= _signal_timeout_frame:
			print("[SIM] wait_signal '%s' timed out at frame %d" % [_waiting_signal, frame])
			_interaction_summary["skipped"] += 1
			_waiting_signal = ""
			_signal_timeout_frame = -1
		else:
			return

	# 执行所有到期 action
	while _current_index < _actions.size():
		var action = _actions[_current_index]
		if action.get("frame", 0) <= frame:
			_dispatch(action)
			_current_index += 1
			if _wait_until_frame > 0 or _waiting_signal != "":
				break
		else:
			break


func _dispatch(action: Dictionary) -> void:
	## 先处理调度层关心的等待类 action，其余委托给 executor
	var act = action.get("action", "")
	var params = action.get("params", {})

	if act == "wait_frames":
		var n = int(params.get("n", 0))
		_wait_until_frame = _frame_count + n
		_record_result({"action": act, "success": true, "detail": "waiting until frame %d" % _wait_until_frame})
		return

	if act == "wait_signal":
		_waiting_signal = params.get("signal", "")
		var timeout = int(params.get("timeout", 60))
		_signal_timeout_frame = _frame_count + timeout
		_signal_received = false
		_record_result({"action": act, "success": true, "detail": "waiting for signal '%s'" % _waiting_signal})
		return

	var result = _executor.execute(action, _frame_count)
	# 同步 last_* 指标给外部读取
	last_select_count = _executor.last_select_count
	last_invalid_refs = _executor.last_invalid_refs
	last_move_commands = _executor.last_move_commands
	last_errors = _executor.last_errors
	_record_result(result)


func _record_result(result: Dictionary) -> void:
	_executed.append(result)
	_interaction_summary["total_actions"] += 1
	if result.get("success", false):
		_interaction_summary["successful"] += 1
	else:
		_interaction_summary["failed"] += 1
	print("[SIM] frame=%d action=%s success=%s" % [_frame_count, result.get("action", "?"), result.get("success", false)])


func record_signal(signal_name: String, args: Array = []) -> void:
	## 由 bootstrap 在信号触发时调用
	_tracer.record(signal_name, _frame_count, args)
	_interaction_summary["signals_received"] = _tracer.signals_received
	if _waiting_signal != "" and signal_name == _waiting_signal:
		_signal_received = true
		print("[SIM] wait_signal '%s' received at frame %d" % [signal_name, _frame_count])


func get_interaction_summary() -> Dictionary:
	return _interaction_summary.duplicate()


func get_execution_log() -> Array:
	return _executed.duplicate()


func get_signal_chain() -> Array:
	return _tracer.get_chain()


func is_finished() -> bool:
	return _current_index >= _actions.size() and _wait_until_frame < 0 and _waiting_signal == ""
