extends RefCounted

## Calibrator — 校准器
## 注册断言函数，每帧 tick 推进状态机，最后输出结果。

var _assertions: Dictionary = {}  # { name: { check: Callable } }
var _results: Dictionary = {}     # { name: { passed: bool, detail: String } }


func add_assertion(name: String, check_fn: Callable) -> void:
	_assertions[name] = {"check": check_fn}


func tick() -> void:
	for name in _assertions:
		if name in _results:
			continue  # Already has final result
		var result = _assertions[name]["check"].call()
		var status = result.get("status", "pending")
		if status == "pass":
			_results[name] = {"passed": true, "detail": result.get("detail", "")}
		elif status == "fail":
			_results[name] = {"passed": false, "detail": result.get("detail", "")}
		# "pending" or "done" → keep ticking


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
	# Report assertions that never completed
	for name in _assertions:
		if name not in _results:
			failed += 1
			print("[CALIBRATE] [FAIL] %s: assertion never completed" % name)
	print("[CALIBRATE] ═══════════════════════════════════════")
	print("[CALIBRATE] RESULT: %d passed, %d failed" % [passed, failed])


func get_results() -> Dictionary:
	return _results
