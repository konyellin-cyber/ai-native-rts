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
	_formatter.configure(_mode, sample_rate)

	if not do_calibrate:
		_calibrator = null


func register(entity_id: String, node: Node, fields: Array) -> void:
	_registry.register(entity_id, node, fields)


func unregister(entity_id: String) -> void:
	_registry.unregister(entity_id)


func register_ref_holder(name: String, getter: Callable) -> void:
	_registry.register_ref_holder(name, getter)


func add_assertion(name: String, check_fn: Callable) -> void:
	if _calibrator:
		_calibrator.add_assertion(name, check_fn)


func tick() -> void:
	_registry.tick()
	if _calibrator:
		_calibrator.tick()
	if _mode != "off":
		var snapshot = _registry.get_snapshot()
		if not snapshot.is_empty():
			# Inject health data into extra for formatter
			var enriched_extra = _extra.duplicate()
			var health = _registry.get_health()
			if not health.is_empty():
				enriched_extra["ref_health"] = health
			var output = _formatter.format(snapshot, enriched_extra)
			if output != "":
				last_output = output
				print(output)
			# Clear snapshot after formatting to avoid duplicate output
			_registry.clear_snapshot()


func print_results() -> void:
	if _calibrator:
		_calibrator.check()
		_calibrator.print_results()


func get_snapshot() -> Dictionary:
	return _registry.get_snapshot()


func get_health() -> Dictionary:
	return _registry.get_health()
