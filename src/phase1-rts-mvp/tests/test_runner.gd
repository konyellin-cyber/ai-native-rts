extends Node

## TestRunner — 单次 Godot 启动顺序跑完所有场景
## 用法：godot --headless --path . --scene res://tests/test_runner.tscn
##
## 过滤参数（通过 -- 传入，多参数取交集）：
##   --phase N        只跑 phase == N 的场景（开发中间步骤用，速度快）
##   --scene 名称     只跑 name == 名称 的场景，支持逗号分隔多个
##   --tag 标签       只跑 covers 包含该标签的场景
##   无参数           全量运行（收尾确认用）
##
## 示例：
##   godot --headless --path . --scene res://tests/test_runner.tscn -- --phase 17
##   godot --headless --path . --scene res://tests/test_runner.tscn -- --scene general_marching
##
## 场景登记表：res://tests/scene_registry.json（唯一权威登记表）
## 新增场景时在 scene_registry.json 中追加条目，不直接修改本文件。
##
## 为什么不并行：单进程内多个物理世界会互相干扰 NavigationServer；
##   并行需求请用 run_scenarios_parallel.sh（多进程）。

const REGISTRY_PATH = "res://tests/scene_registry.json"

## 从 scene_registry.json 加载的场景列表（运行时填充）
var _scenario_files: Array[String] = []
## 所有场景的元信息（name, window_mode, phase 等）
var _registry: Array = []

## 过滤参数（从命令行解析）
var _filter_phase: int = -1        # --phase N，-1 表示不过滤
var _filter_scenes: Array = []     # --scene a,b,c
var _filter_tag: String = ""       # --tag formation

var _results: Array = []   # [{ name, passed, failed, detail_lines, window_mode }]
var _current_idx: int = -1
var _game_node: Node = null
var _start_msec: int = 0


func _ready() -> void:
	## 为什么在 _ready 中挂 name：bootstrap 通过 get_tree().root.get_node_or_null("TestRunner")
	## 查找本节点，name 必须在 bootstrap._ready() 运行前已设置。
	name = "TestRunner"
	_start_msec = Time.get_ticks_msec()

	_parse_args()
	_load_registry()

	## 过滤后无匹配时直接退出（_load_registry 已打印错误信息）
	if _scenario_files.is_empty():
		get_tree().quit(1)
		return

	var filter_desc = _build_filter_desc()
	print("")
	print("[RUNNER] ════════════════════════════════════════")
	if filter_desc != "":
		print("[RUNNER]  TEST RUNNER — %d 个场景  过滤: %s" % [_scenario_files.size(), filter_desc])
	else:
		print("[RUNNER]  TEST RUNNER — %d headless scenarios" % _scenario_files.size())
	print("[RUNNER] ════════════════════════════════════════")

	## 为什么用 call_deferred：_ready 期间场景树 busy，直接 add_child 会报错。
	## deferred 确保 _ready 完成、场景树空闲后再执行第一次 _run_next。
	_run_next.call_deferred()


## 解析 -- 之后的用户参数（OS.get_cmdline_user_args）
func _parse_args() -> void:
	var args = OS.get_cmdline_user_args()
	var i = 0
	while i < args.size():
		var a = args[i]
		match a:
			"--phase":
				if i + 1 < args.size():
					_filter_phase = int(args[i + 1])
					i += 2
				else:
					push_error("[RUNNER] --phase 需要一个数字参数")
					get_tree().quit.call_deferred(1)
			"--scene":
				if i + 1 < args.size():
					_filter_scenes = args[i + 1].split(",", false)
					i += 2
				else:
					push_error("[RUNNER] --scene 需要一个场景名参数")
					get_tree().quit.call_deferred(1)
			"--tag":
				if i + 1 < args.size():
					_filter_tag = args[i + 1]
					i += 2
				else:
					push_error("[RUNNER] --tag 需要一个标签参数")
					get_tree().quit.call_deferred(1)
			_:
				i += 1


func _build_filter_desc() -> String:
	var parts: Array[String] = []
	if _filter_phase >= 0:
		parts.append("phase=%d" % _filter_phase)
	if not _filter_scenes.is_empty():
		parts.append("scene=%s" % ",".join(_filter_scenes))
	if _filter_tag != "":
		parts.append("tag=%s" % _filter_tag)
	return " ".join(parts)


## 从 scene_registry.json 读取登记表，填充 _scenario_files（仅 headless 场景 + 命令行过滤）
func _load_registry() -> void:
	var f = FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	if f == null:
		push_error("[RUNNER] Cannot read scene_registry.json")
		get_tree().quit(1)
		return
	var text = f.get_as_text()
	f.close()

	var json = JSON.new()
	if json.parse(text) != OK:
		push_error("[RUNNER] Invalid JSON in scene_registry.json")
		get_tree().quit(1)
		return

	_registry = json.data
	for entry in _registry:
		## 仅将 window_mode: false 的场景加入本次 headless 运行列表
		if entry.get("window_mode", false):
			continue
		## 命令行过滤（多参数取交集）
		if _filter_phase >= 0 and int(entry.get("phase", -1)) != _filter_phase:
			continue
		if not _filter_scenes.is_empty() and not (entry.get("name", "") in _filter_scenes):
			continue
		if _filter_tag != "" and not (entry.get("covers", []) as Array).has(_filter_tag):
			continue
		_scenario_files.append(entry["path"])

	## 过滤后无匹配时报错，列出可用值帮助排查
	if _scenario_files.is_empty():
		var filter_desc = _build_filter_desc()
		push_error("[RUNNER] 过滤条件 [%s] 无匹配场景，请检查参数" % filter_desc)
		var available_phases: Array[String] = []
		var available_names: Array[String] = []
		for entry in _registry:
			if entry.get("window_mode", false):
				continue
			var p = str(int(entry.get("phase", -1)))
			if not (p in available_phases):
				available_phases.append(p)
			available_names.append(entry.get("name", "?"))
		print("[RUNNER] 可用 phase: %s" % ", ".join(available_phases))
		print("[RUNNER] 可用 scene: %s" % ", ".join(available_names))
		## 不在这里 quit，由 _run_next 检查 is_empty() 后以 exit 1 退出


## 启动下一个场景（由 _ready 或 on_scenario_done 调用）
func _run_next() -> void:
	_current_idx += 1

	if _current_idx >= _scenario_files.size():
		_print_summary()
		var failed_count = _results.filter(func(r): return r.failed > 0).size()
		get_tree().quit(1 if failed_count > 0 else 0)
		return

	var entry = _scenario_files[_current_idx]
	print("")
	print("[RUNNER] ────────────────────────────────────────")
	print("[RUNNER] ▶ [%d/%d] %s" % [_current_idx + 1, _scenario_files.size(), entry])

	## 所有场景均为独立 .tscn 模式，直接 instantiate
	var packed = load(entry) as PackedScene
	if packed == null:
		push_error("[RUNNER] Cannot load .tscn: %s" % entry)
		get_tree().quit(1)
		return
	_game_node = packed.instantiate()
	get_tree().root.add_child(_game_node)


## bootstrap 在结束时（帧超限 / 断言全通过）调用此函数代替 get_tree().quit()
## 参数 results：Calibrator.get_results() 返回的 Dictionary
func on_scenario_done(results: Dictionary) -> void:
	var entry = _scenario_files[_current_idx]
	## 从路径末段提取场景名（取上一级目录名）
	var scenario_name: String = entry.get_base_dir().get_file()  # "res://tests/core/smoke_test/scene.tscn" → "smoke_test"
	var passed = 0
	var failed = 0
	var detail_lines: Array[String] = []

	for assertion_name in results:
		var r = results[assertion_name]
		if r.get("passed", false):
			passed += 1
			detail_lines.append("  ✅ %s" % assertion_name)
		else:
			failed += 1
			detail_lines.append("  ❌ %s: %s" % [assertion_name, r.get("detail", "unknown")])

	_results.append({
		"name": scenario_name,
		"passed": passed,
		"failed": failed,
		"detail_lines": detail_lines,
	})

	if failed == 0:
		print("[RUNNER] ✅ PASS: %s (%d assertions)" % [scenario_name, passed])
	else:
		print("[RUNNER] ❌ FAIL: %s (%d passed, %d failed)" % [scenario_name, passed, failed])
		for line in detail_lines:
			if "❌" in line:
				print("[RUNNER]%s" % line)

	# 释放本轮 game 节点，再开始下一轮
	if is_instance_valid(_game_node):
		_game_node.queue_free()
	_game_node = null

	# 等一帧确保 queue_free 生效，再加载下一个场景
	await get_tree().process_frame
	_run_next()


func _print_summary() -> void:
	var elapsed = Time.get_ticks_msec() - _start_msec
	var total_passed = 0
	var total_failed_scenarios = 0

	## 统计登记表中 window 场景数量（本次未运行，仅做提示）
	var window_count = 0
	for entry in _registry:
		if entry.get("window_mode", false):
			window_count += 1

	print("")
	print("[RUNNER] ════════════════════════════════════════")
	print("[RUNNER]  FINAL SUMMARY  (elapsed: %.1fs)" % (elapsed / 1000.0))
	print("[RUNNER] ════════════════════════════════════════")
	print("[RUNNER]  [Headless 场景]")

	for r in _results:
		var icon = "✅" if r.failed == 0 else "❌"
		print("[RUNNER]  %s %-22s  pass=%d  fail=%d" % [icon, r.name, r.passed, r.failed])
		if r.failed > 0:
			for line in r.detail_lines:
				if "❌" in line:
					print("[RUNNER]   %s" % line)
			total_failed_scenarios += 1
		total_passed += r.passed

	print("[RUNNER] ────────────────────────────────────────")
	var total = _results.size()
	print("[RUNNER]  Scenarios: %d/%d PASS | Failed scenarios: %d" % [
		total - total_failed_scenarios, total, total_failed_scenarios
	])
	if window_count > 0:
		print("[RUNNER]  [Window 场景] %d 个，需窗口模式单独运行（见 scene_registry.json）" % window_count)
	print("[RUNNER] ════════════════════════════════════════")
