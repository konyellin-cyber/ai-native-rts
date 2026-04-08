extends "res://scripts/bootstrap.gd"
## economy bootstrap — 继承主游戏 Bootstrap
## 自动注入本地 scenario.json，覆盖 config_overrides 并绑定 SimulatedPlayer actions。
## 不修改 test_runner.gd（13C 任务）；scene.tscn 与 main.tscn 结构一致。

const _SCENARIO_PATH = "res://tests/legacy/economy/scenario.json"


func _load_config() -> Dictionary:
	## 覆盖父类 _load_config：先加载 res://config.json，再将本地 scenario.json
	## 的 config_overrides 浅合并进去，并注入 scenario_file 供 SimulatedPlayer 和
	## 断言筛选使用。
	var file = FileAccess.open("res://config.json", FileAccess.READ)
	if file == null:
		push_error("[ECONOMY] Cannot open res://config.json")
		return {}
	var cfg: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	if not cfg is Dictionary:
		return {}

	var sf = FileAccess.open(_SCENARIO_PATH, FileAccess.READ)
	if sf == null:
		push_error("[ECONOMY] Cannot open scenario.json: %s" % _SCENARIO_PATH)
		return cfg
	var scenario: Dictionary = JSON.parse_string(sf.get_as_text())
	sf.close()

	if scenario is Dictionary:
		if scenario.has("config_overrides"):
			for key in scenario["config_overrides"]:
				if cfg.has(key) and cfg[key] is Dictionary:
					cfg[key].merge(scenario["config_overrides"][key], true)
				else:
					cfg[key] = scenario["config_overrides"][key]
			print("[ECONOMY] Applied config_overrides: %s" % str(scenario["config_overrides"].keys()))
		## 注入 scenario_file，bootstrap 父类的 _setup_simulated_player 和
		## _setup_assertions 均依赖此字段
		cfg["scenario_file"] = _SCENARIO_PATH

	return cfg
