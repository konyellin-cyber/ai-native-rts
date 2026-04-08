extends "res://scripts/bootstrap.gd"
## combat bootstrap — 继承主游戏 Bootstrap
## 自动注入本地 scenario.json，覆盖 config_overrides（AI 进攻参数）。
## 无 actions（蓝方 AI 自主决策）。

const _SCENARIO_PATH = "res://tests/legacy/combat/scenario.json"


func _load_config() -> Dictionary:
	## 覆盖父类 _load_config：先加载 res://config.json，再将本地 scenario.json
	## 的 config_overrides 浅合并进去，并注入 scenario_file 供断言筛选使用。
	var file = FileAccess.open("res://config.json", FileAccess.READ)
	if file == null:
		push_error("[COMBAT_V2] Cannot open res://config.json")
		return {}
	var cfg: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	if not cfg is Dictionary:
		return {}

	var sf = FileAccess.open(_SCENARIO_PATH, FileAccess.READ)
	if sf == null:
		push_error("[COMBAT_V2] Cannot open scenario.json: %s" % _SCENARIO_PATH)
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
			print("[COMBAT_V2] Applied config_overrides: %s" % str(scenario["config_overrides"].keys()))
		cfg["scenario_file"] = _SCENARIO_PATH

	return cfg
