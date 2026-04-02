extends RefCounted

## Calibrator — 校准器
## 注册断言函数，每帧 tick 推进状态机，最后输出结果。

var _assertions: Dictionary = {}  # { name: { check: Callable } }
var _results: Dictionary = {}     # { name: { passed: bool, detail: String } }
var _run_only: Array = []         # 若非空，只跑此列表中的断言；空=全跑


func add_assertion(name: String, check_fn: Callable) -> void:
	_assertions[name] = {"check": check_fn}


func set_run_only(names: Array) -> void:
	## 限定本次只验证指定断言，其余跳过。场景化测试用。
	_run_only = names


func tick() -> bool:
	## 推进所有断言状态机。
	## 返回 true 表示所有应跑的断言均已得到最终结果（pass 或 fail），可提前退出。
	## 返回 false 表示仍有断言处于 pending，需要继续等帧。
	for name in _assertions:
		if not _run_only.is_empty() and name not in _run_only:
			continue  # 场景未指定此断言，跳过
		if name in _results:
			continue  # Already has final result
		var result = _assertions[name]["check"].call()
		var status = result.get("status", "pending")
		if status == "pass":
			_results[name] = {"passed": true, "detail": result.get("detail", "")}
		elif status == "fail":
			_results[name] = {"passed": false, "detail": result.get("detail", "")}
		# "pending" → keep ticking

	# 检查是否所有应跑的断言都已有最终结果
	var active = _run_only if not _run_only.is_empty() else _assertions.keys()
	for name in active:
		if name not in _results:
			return false  # 仍有 pending
	return active.size() > 0  # 至少有一条断言才视为"全部完成"


func check() -> Dictionary:
	return _results


func print_results() -> void:
	if _results.is_empty():
		return
	print("[CALIBRATE] ═══════════════════════════════════════")
	var passed = 0
	var failed = 0
	for name in _results:
		var r = _results[name]
		if r.get("passed", false):
			passed += 1
			print("[CALIBRATE] [PASS] %s" % name)
		else:
			failed += 1
			print("[CALIBRATE] [FAIL] %s: %s" % [name, r.get("detail", "unknown")])
	# 只报告"应跑但未完成"的断言
	var active = _run_only if not _run_only.is_empty() else _assertions.keys()
	for name in active:
		if name not in _results:
			failed += 1
			print("[CALIBRATE] [FAIL] %s: assertion never completed" % name)
	print("[CALIBRATE] ═══════════════════════════════════════")
	print("[CALIBRATE] RESULT: %d passed, %d failed" % [passed, failed])


func get_results() -> Dictionary:
	return _results
