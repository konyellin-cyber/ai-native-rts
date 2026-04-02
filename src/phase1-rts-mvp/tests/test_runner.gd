extends Node

## TestRunner — 单次 Godot 启动顺序跑完所有场景
## 用法：godot --headless --path . --scene res://tests/test_runner.tscn
##
## 原理：
##   1. 以 "TestRunner" 名称挂在场景树根节点（bootstrap._finish() 会查找它）
##   2. 按顺序加载场景，等待 bootstrap 完成回调
##   3. 收集每轮结果后 free 掉 game 节点，加载下一个场景
##   4. 全部跑完后打印汇总并退出
##
## 场景列表支持两种格式：
##   - "economy.json"     → 走 .json 注入模式（主游戏 main.tscn + _inject_scenario）
##   - "res://tests/scenes/smoke_test/scene.tscn" → 走独立 .tscn 模式（直接 instantiate）
##
## 为什么不并行：单进程内多个物理世界会互相干扰 NavigationServer；
##   并行需求请用 run_scenarios_parallel.sh（多进程）。

const MAIN_SCENE = "res://main.tscn"
const SCENARIOS_DIR = "res://tests/scenarios/"

## 要运行的场景列表
## .json 文件名（相对 SCENARIOS_DIR）→ .json 注入模式
## res:// 绝对路径（.tscn）→ 独立场景模式
const SCENARIO_FILES: Array[String] = [
	"economy.json",
	"combat.json",
	"interaction.json",
	"res://tests/scenes/smoke_test/scene.tscn",
	"res://tests/scenes/archer_vs_fighter/scene.tscn",
	"res://tests/scenes/archer_vs_archer/scene.tscn",
	"res://tests/scenes/kite_behavior/scene.tscn",
]

var _results: Array = []   # [{ name, passed, failed, detail_lines }]
var _current_idx: int = -1
var _game_node: Node = null
var _start_msec: int = 0


func _ready() -> void:
	## 为什么在 _ready 中挂 name：bootstrap 通过 get_tree().root.get_node_or_null("TestRunner")
	## 查找本节点，name 必须在 bootstrap._ready() 运行前已设置。
	name = "TestRunner"
	_start_msec = Time.get_ticks_msec()

	print("")
	print("[RUNNER] ════════════════════════════════════════")
	print("[RUNNER]  TEST RUNNER — %d scenarios" % SCENARIO_FILES.size())
	print("[RUNNER] ════════════════════════════════════════")

	## 为什么用 call_deferred：_ready 期间场景树 busy，直接 add_child 会报错。
	## deferred 确保 _ready 完成、场景树空闲后再执行第一次 _run_next。
	_run_next.call_deferred()


## 启动下一个场景（由 _ready 或 on_scenario_done 调用）
func _run_next() -> void:
	_current_idx += 1

	if _current_idx >= SCENARIO_FILES.size():
		_print_summary()
		var failed_count = _results.filter(func(r): return r.failed > 0).size()
		get_tree().quit(1 if failed_count > 0 else 0)
		return

	var entry = SCENARIO_FILES[_current_idx]
	print("")
	print("[RUNNER] ────────────────────────────────────────")
	print("[RUNNER] ▶ [%d/%d] %s" % [_current_idx + 1, SCENARIO_FILES.size(), entry])

	if entry.ends_with(".tscn"):
		## 独立 .tscn 模式：直接 instantiate，场景自带专属 bootstrap
		var packed = load(entry) as PackedScene
		if packed == null:
			push_error("[RUNNER] Cannot load .tscn: %s" % entry)
			get_tree().quit(1)
			return
		_game_node = packed.instantiate()
		get_tree().root.add_child(_game_node)
	else:
		## .json 注入模式：写入 config.json，加载 main.tscn
		var scenario_file = SCENARIOS_DIR + entry
		_inject_scenario(scenario_file)
		var packed = load(MAIN_SCENE) as PackedScene
		if packed == null:
			push_error("[RUNNER] Cannot load %s" % MAIN_SCENE)
			get_tree().quit(1)
			return
		_game_node = packed.instantiate()
		get_tree().root.add_child(_game_node)


## bootstrap 在结束时（帧超限 / 断言全通过）调用此函数代替 get_tree().quit()
## 参数 results：Calibrator.get_results() 返回的 Dictionary
func on_scenario_done(results: Dictionary) -> void:
	var entry = SCENARIO_FILES[_current_idx]
	## 从路径末段提取场景名（兼容 .json 和 .tscn）
	var scenario_name: String
	if entry.ends_with(".tscn"):
		scenario_name = entry.get_base_dir().get_file()  # "res://tests/scenes/smoke_test/scene.tscn" → "smoke_test"
	else:
		scenario_name = entry.replace(".json", "")
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


## 将 scenario_file 写入 config（bootstrap._load_config 在 _ready 时读取）
## 为什么用 FileAccess 写 res:// 而非 user://：bootstrap 硬编码了 "res://config.json"
func _inject_scenario(scenario_path: String) -> void:
	var f = FileAccess.open("res://config.json", FileAccess.READ)
	if f == null:
		push_error("[RUNNER] Cannot read res://config.json")
		return
	var text = f.get_as_text()
	f.close()

	var json = JSON.new()
	if json.parse(text) != OK:
		push_error("[RUNNER] Invalid JSON in config.json")
		return
	var cfg: Dictionary = json.data
	cfg["scenario_file"] = scenario_path

	var wf = FileAccess.open("res://config.json", FileAccess.WRITE)
	if wf == null:
		push_error("[RUNNER] Cannot write res://config.json")
		return
	wf.store_string(JSON.stringify(cfg, "  "))
	wf.close()


func _print_summary() -> void:
	var elapsed = Time.get_ticks_msec() - _start_msec
	var total_passed = 0
	var total_failed_scenarios = 0

	print("")
	print("[RUNNER] ════════════════════════════════════════")
	print("[RUNNER]  FINAL SUMMARY  (elapsed: %.1fs)" % (elapsed / 1000.0))
	print("[RUNNER] ════════════════════════════════════════")

	for r in _results:
		var icon = "✅" if r.failed == 0 else "❌"
		print("[RUNNER]  %s %-20s  pass=%d  fail=%d" % [icon, r.name, r.passed, r.failed])
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
	print("[RUNNER] ════════════════════════════════════════")
