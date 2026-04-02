extends RefCounted

## AIRenderer — 入口
## 管理采集、格式化、校准三个子模块。游戏代码只需调 register() 和 tick()。
## v2: supports ref_holder registration and health data pass-through.

var _registry: RefCounted  # SensorRegistry instance
var _formatter: RefCounted  # FormatterEngine instance
var _calibrator: RefCounted  # Calibrator instance
var _mode: String = "off"
var _extra: Dictionary = {}
var last_output: String = ""
var _log_file_path: String = ""
var _log_max_lines: int = 500  # Ring buffer size
var _log_write_count: int = 0


func set_extra(data: Dictionary) -> void:
	_extra = data


const _RegistryScript = preload("res://tools/ai-renderer/sensor_registry.gd")
const _FormatterScript = preload("res://tools/ai-renderer/formatter_engine.gd")
const _CalibratorScript = preload("res://tools/ai-renderer/calibrator.gd")


func _init(config: Dictionary) -> void:
	_registry = _RegistryScript.new()
	_formatter = _FormatterScript.new()
	_calibrator = _CalibratorScript.new()

	_mode = config.get("mode", "off")
	var sample_rate = config.get("sample_rate", 60)
	var do_calibrate = config.get("calibrate", false)

	_registry.configure(sample_rate)
	# 5E: 按 group 独立采样率；旧 sample_rate 作为未配置 group 的默认值
	var sensors_config = config.get("sensors", {})
	if not sensors_config.is_empty():
		_registry.configure_groups(sensors_config)
	_formatter.configure(_mode, sample_rate)

	if not do_calibrate:
		_calibrator = null

	# Enable log file for window mode AI debug
	if _mode != "off":
		var log_dir = ProjectSettings.globalize_path("res://tests/logs/")
		DirAccess.make_dir_recursive_absolute(log_dir)
		_log_file_path = log_dir + "window_debug.log"
		# Truncate on startup
		var f = FileAccess.open(_log_file_path, FileAccess.WRITE)
		if f:
			f.store_string("# AI Renderer log — " + Time.get_datetime_string_from_system() + "\n")
			f.close()
		_log_write_count = 0


func register(entity_id: String, node: Node, fields: Array, group: String = "units") -> void:
	_registry.register(entity_id, node, fields, group)


func unregister(entity_id: String) -> void:
	_registry.unregister(entity_id)


func register_ref_holder(name: String, getter: Callable) -> void:
	_registry.register_ref_holder(name, getter)


func add_assertion(name: String, check_fn: Callable) -> void:
	if _calibrator:
		_calibrator.add_assertion(name, check_fn)


func get_calibrator() -> RefCounted:
	return _calibrator


func tick() -> bool:
	## 推进采样、格式化、断言。
	## 返回 true 表示所有断言已完成（可 early exit），false 表示仍有 pending。
	_registry.tick()
	var all_done := false
	if _calibrator:
		all_done = _calibrator.tick()
	if _mode != "off":
		var snapshot = _registry.get_snapshot()
		if not snapshot.is_empty():
			var enriched_extra = _extra.duplicate()
			var health = _registry.get_health()
			if not health.is_empty():
				enriched_extra["ref_health"] = health
			var output = _formatter.format(snapshot, enriched_extra)
			if output != "":
				last_output = output
				print(output)
				_append_log(output)
			_registry.clear_snapshot()
	return all_done


func print_results() -> void:
	if _calibrator:
		_calibrator.check()
		_calibrator.print_results()


func get_snapshot() -> Dictionary:
	return _registry.get_snapshot()


func get_health() -> Dictionary:
	return _registry.get_health()


func _append_log(text: String) -> void:
	if _log_file_path == "":
		return
	var f = FileAccess.open(_log_file_path, FileAccess.READ_WRITE)
	if not f:
		return
	_log_write_count += 1
	# Append to file
	f.seek_end()
	f.store_string(text + "\n")
	f.close()
	# Periodic trim: every 100 writes, trim to last _log_max_lines
	if _log_write_count % 100 == 0:
		_trim_log()


func _trim_log() -> void:
	var f = FileAccess.open(_log_file_path, FileAccess.READ_WRITE)
	if not f:
		return
	var content = f.get_as_text()
	var lines = content.split("\n")
	if lines.size() > _log_max_lines:
		f.seek(0)
		f.resize(0)
		var start = lines.size() - _log_max_lines
		for i in range(start, lines.size()):
			f.store_line(lines[i])
	f.close()
