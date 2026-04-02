extends RefCounted

## FormatterEngine — 格式化引擎
## 将采集数据转为 AI 可读的文本输出。
## v2: adds interaction health and lifecycle health sections.

var _mode: String = "off"
var _sample_rate: int = 60


func configure(mode: String, sample_rate: int) -> void:
	_mode = mode
	_sample_rate = sample_rate


func format(snapshot: Dictionary, extra: Dictionary = {}) -> String:
	if _mode == "off" or snapshot.is_empty():
		return ""
	return _format_ai_debug(snapshot, extra)


func _format_ai_debug(snapshot: Dictionary, extra: Dictionary = {}) -> String:
	var lines: Array[String] = []
	var entities = snapshot.get("entities", {})
	var tick = snapshot.get("tick", 0)

	if entities.is_empty():
		return "[TICK %d] no entities registered" % tick

	# Summary line: count alive by team
	var red_count = 0
	var blue_count = 0
	for eid in entities:
		var data = entities[eid]
		var team = str(data.get("team_name", ""))
		if team == "red":
			red_count += 1
		elif team == "blue":
			blue_count += 1
	var header = "[TICK %d] %d alive (%dR / %dB)" % [tick, entities.size(), red_count, blue_count]

	# Append combat summary if available
	var red_alive = extra.get("red_alive", -1)
	var blue_alive = extra.get("blue_alive", -1)
	var kill_count = extra.get("kill_count", -1)
	if kill_count >= 0:
		header += " kills=%d" % kill_count
	if red_alive >= 0:
		header += " total=(%dR/%dB)" % [red_alive, blue_alive]
	lines.append(header)

	# State distribution: count units by state (wander/chase/attack/dead)
	var state_counts: Dictionary = {}
	for eid in entities:
		var data = entities[eid]
		var st = str(data.get("ai_state", "?"))
		state_counts[st] = state_counts.get(st, 0) + 1
	if not state_counts.is_empty():
		var parts: Array[String] = []
		for st in state_counts:
			parts.append("%s:%d" % [st, state_counts[st]])
		lines.append("  states: %s" % " ".join(parts))

	# Interaction health (v2)
	var sim = extra.get("simulated_player", {})
	if sim is Dictionary and not sim.is_empty():
		var sel = sim.get("select", -1)
		var invalid = sim.get("invalid_refs", -1)
		var move = sim.get("move_commands", -1)
		var errors = sim.get("errors", -1)
		var parts: Array[String] = []
		if sel >= 0:
			parts.append("select=%d" % sel)
		if invalid >= 0:
			parts.append("invalid=%d" % invalid)
		if move >= 0:
			parts.append("move=%d" % move)
		if errors >= 0:
			parts.append("errors=%d" % errors)
		if not parts.is_empty():
			lines.append("  interaction: %s" % " ".join(parts))

	# Lifecycle health (v2)
	var health = extra.get("ref_health", {})
	if health is Dictionary and not health.is_empty():
		var total_invalid = health.get("total_invalid", 0)
		var holder_parts: Array[String] = []
		var holders = health.get("holders", {})
		for hname in holders:
			var h = holders[hname]
			holder_parts.append("%s:%d/%d" % [hname, h.get("invalid", 0), h.get("total", 0)])
		if total_invalid > 0:
			lines.append("  lifecycle: WARNING invalid=%d holders=[%s]" % [total_invalid, ", ".join(holder_parts)])
		elif not holder_parts.is_empty():
			lines.append("  lifecycle: ok (%s)" % ", ".join(holder_parts))

	return "\n".join(lines)
