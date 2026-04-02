extends RefCounted

## FormatterEngine — 格式化引擎
## 将采集数据转为 AI 可读的文本输出。
## v2: adds interaction health and lifecycle health sections.
## v3: adds behavior semantics for worker movement direction analysis.

var _mode: String = "off"
var _sample_rate: int = 60
var _prev_positions: Dictionary = {}  # { entity_id: Vector2/Vector3 } for direction tracking
var _origin_distances: Dictionary = {}  # { entity_id: float } original dist to target at first observation
var _accum_distance: Dictionary = {}  # { entity_id: float } accumulated travel distance


func _to_flat(pos) -> Vector2:
	## 将位置投影到水平平面，兼容 2D（Vector2）和 3D（Vector3）。
	## 3D 俯视 RTS 中 Y 为高度，XZ 为地图平面，故取 pos.x / pos.z。
	if pos == null:
		return Vector2.ZERO
	if pos is Vector3:
		return Vector2(pos.x, pos.z)
	return Vector2(float(pos.x), float(pos.y))


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

	# Summary line: count alive by team (exclude HQ entities — no ai_state means non-unit)
	var red_count = 0
	var blue_count = 0
	for eid in entities:
		var data = entities[eid]
		var team = str(data.get("team_name", ""))
		# Only count units (have ai_state), not HQs
		if data.has("ai_state"):
			if team == "red":
				red_count += 1
			elif team == "blue":
				blue_count += 1
	var header = "[TICK %d] %d alive (%dR / %dB)" % [tick, red_count + blue_count, red_count, blue_count]

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

	# Economy: crystal + mine remaining
	var red_crystal = extra.get("red_crystal", -1)
	var blue_crystal = extra.get("blue_crystal", -1)
	var economy_parts: Array[String] = []
	if red_crystal >= 0:
		economy_parts.append("red_crystal=%d" % red_crystal)
	if blue_crystal >= 0:
		economy_parts.append("blue_crystal=%d" % blue_crystal)
	# Mine amounts from entities
	var mine_total: int = 0
	var mine_max: int = 0
	for eid in entities:
		if eid.begins_with("Mine_"):
			var data = entities[eid]
			var amt = data.get("amount")
			var mx = data.get("max_amount")
			if amt != null and mx != null:
				mine_total += int(amt)
				mine_max += int(mx)
	if mine_max > 0:
		economy_parts.append("mines=%d/%d" % [mine_total, mine_max])
	if not economy_parts.is_empty():
		lines.append("  economy: %s" % " ".join(economy_parts))

	# Production: HQ queue status
	var prod_parts: Array[String] = []
	for eid in entities:
		if eid.begins_with("HQ_"):
			var data = entities[eid]
			var team = str(data.get("team_name", ""))
			var qs_val = data.get("queue_size")
			var qs = int(qs_val) if qs_val != null else 0
			var producing_val = data.get("producing")
			var producing = str(producing_val) if producing_val != null and producing_val != "" else ""
			if qs > 0 or producing != "":
				prod_parts.append("%s(queue=%d producing=%s)" % [team, qs, producing])
	if not prod_parts.is_empty():
		lines.append("  production: %s" % " ".join(prod_parts))

	# AI opponent: blue team summary
	var blue_workers = 0
	var blue_fighters = 0
	for eid in entities:
		var data = entities[eid]
		if str(data.get("team_name", "")) == "blue":
			var utype = str(data.get("unit_type", ""))
			if utype == "worker":
				blue_workers += 1
			elif utype == "fighter":
				blue_fighters += 1
	if blue_workers > 0 or blue_fighters > 0:
		lines.append("  ai_opponent: blue w=%d f=%d" % [blue_workers, blue_fighters])

	# Interaction health (v2)
	var sim = extra.get("simulated_player", {})
	if sim is Dictionary and not sim.is_empty():
		var sel = sim.get("select", -1)
		var invalid = sim.get("invalid_refs", -1)
		var move = sim.get("move_commands", -1)
		var errors = sim.get("errors", -1)
		var sim_parts: Array[String] = []
		if sel >= 0:
			sim_parts.append("select=%d" % sel)
		if invalid >= 0:
			sim_parts.append("invalid=%d" % invalid)
		if move >= 0:
			sim_parts.append("move=%d" % move)
		if errors >= 0:
			sim_parts.append("errors=%d" % errors)
		if not sim_parts.is_empty():
			lines.append("  interaction: %s" % " ".join(sim_parts))

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

	# v3: Behavior semantics — worker movement direction & convergence
	var behavior_lines = _format_worker_behavior(entities, tick)
	if not behavior_lines.is_empty():
		lines.append("  behavior:")
		for bl in behavior_lines:
			lines.append("    " + bl)

	# v4: UX Observer data (window mode only)
	var ux_data = extra.get("ux", {})
	if ux_data is Dictionary and not ux_data.is_empty():
		var ux_lines = _format_ux(ux_data)
		if not ux_lines.is_empty():
			for ul in ux_lines:
				lines.append("  " + ul)

	return "\n".join(lines)


func _format_worker_behavior(entities: Dictionary, tick: int) -> Array[String]:
	## Generate behavioral summaries for all units (workers + fighters), showing direction
	## relative to their target and whether they are converging or diverging.
	## v3: tracks cumulative path efficiency (accumulated distance vs. straight line).
	var lines: Array[String] = []
	var anomalies: int = 0

	for eid in entities:
		var data = entities[eid]
		var utype = str(data.get("unit_type", ""))
		if utype != "worker" and utype != "fighter":
			continue

		var team = str(data.get("team_name", ""))
		var uid = int(data.get("unit_id", 0))
		var state = str(data.get("ai_state", "?"))
		var pos = data.get("global_position")
		var tgt = data.get("target_position")

		if pos == null:
			continue

		# Short label: team + type prefix + id
		var type_prefix = "w" if utype == "worker" else "f"
		var label = "%s_%s%d" % [team, type_prefix, uid]

		# For non-moving states, just report briefly
		if state == "idle" and tgt == null:
			var prev = _prev_positions.get(eid)
			if prev != null and pos.distance_to(prev) < 1.0 and tick > 120:
				lines.append("%s: idle (stuck %d ticks) ⚠️" % [label, tick])
				anomalies += 1
			else:
				lines.append("%s: idle" % label)
			_prev_positions[eid] = pos
			_reset_tracking(eid)
			continue

		if state == "harvesting":
			# Report path efficiency when arriving at destination
			var eff = _get_path_efficiency(eid)
			if eff >= 0 and eff < 0.5:
				lines.append("%s: harvesting (path_eff=%.0f%% ⚠️ inefficient route)" % [label, eff * 100])
				anomalies += 1
			else:
				lines.append("%s: harvesting" % label)
			_prev_positions[eid] = pos
			_reset_tracking(eid)
			continue

		if state == "delivering":
			var eff = _get_path_efficiency(eid)
			if eff >= 0 and eff < 0.5:
				lines.append("%s: delivering (path_eff=%.0f%% ⚠️)" % [label, eff * 100])
			else:
				lines.append("%s: delivering" % label)
			_prev_positions[eid] = pos
			_reset_tracking(eid)
			continue

		# Moving states: compute direction to target and actual movement direction
		if tgt == null:
			_prev_positions[eid] = pos
			continue

		var pos_v = _to_flat(pos)
		var tgt_v = _to_flat(tgt)
		var dist_to_target = pos_v.distance_to(tgt_v)
		var dir_to_target = pos_v.direction_to(tgt_v)

		# Track path efficiency: record original distance and accumulate travel
		if not _origin_distances.has(eid):
			_origin_distances[eid] = dist_to_target
			_accum_distance[eid] = 0.0
		if not _accum_distance.has(eid):
			_accum_distance[eid] = 0.0

		var prev = _prev_positions.get(eid)
		var moving_toward: bool = true
		var actual_dir_label: String = ""
		var divergence: bool = false

		if prev != null:
			var prev_v = _to_flat(prev)
			var movement = pos_v - prev_v
			var move_dist = movement.length()
			_accum_distance[eid] += move_dist

			if move_dist < 0.5:
				actual_dir_label = "not moving"
				if state.begins_with("move"):
					divergence = true  # Should be moving but isn't
			else:
				var actual_dir = movement.normalized()
				var dot = actual_dir.dot(dir_to_target)
				moving_toward = dot > 0.3  # Allow ~73° deviation
				divergence = dot < -0.1  # Moving away from target
				if dot > 0.7:
					actual_dir_label = "→target"
				elif dot > 0.3:
					actual_dir_label = "→near"
				elif dot > -0.1:
					actual_dir_label = "⊥perp"
				else:
					actual_dir_label = "←away"

		_prev_positions[eid] = pos

		# State description
		var state_desc = state
		if state == "move_to_mine":
			state_desc = "→mine"
		elif state == "returning":
			state_desc = "→hq"
		elif state == "chase":
			state_desc = "→enemy"
		elif state == "wander" and data.get("has_command", false):
			state_desc = "→cmd"

		# Path efficiency so far
		var eff = _get_path_efficiency(eid)
		var eff_str = ""
		if eff >= 0:
			eff_str = " eff=%.0f%%" % (eff * 100)
			if eff < 0.5:
				eff_str += " ⚠️"
				anomalies += 1

		# Build the line
		var vel = data.get("velocity")
		var speed_str = ""
		if vel != null:
			var spd = Vector3(vel.x, 0, vel.z).length()
			speed_str = " spd=%.0f" % spd
		var nav_avail = data.get("_nav_available")
		var nav_str = ""
		if nav_avail != null:
			nav_str = " nav=%s" % ("Y" if nav_avail else "N")
		var line = "%s: %s dist=%.0f dir=%s%s%s%s" % [label, state_desc, dist_to_target, actual_dir_label, eff_str, speed_str, nav_str]
		if divergence:
			line += " DIVERGING"
			anomalies += 1
		elif not moving_toward and actual_dir_label != "":
			line += " ~indirect"
		lines.append(line)

	return lines


func _get_path_efficiency(eid: String) -> float:
	## Returns ratio of remaining straight-line to accumulated travel (0.0-1.0).
	## Returns -1 if insufficient data.
	var orig = _origin_distances.get(eid, -1.0)
	var accum = _accum_distance.get(eid, -1.0)
	if orig < 0 or accum < 1.0:
		return -1.0
	# Efficiency: how much of the accumulated distance was productive
	# Best case: accum == orig (straight line) → eff = 1.0
	return clampf(orig / accum, 0.0, 1.0)


func _reset_tracking(eid: String) -> void:
	_origin_distances.erase(eid)
	_accum_distance.erase(eid)


func _format_ux(ux_data: Dictionary) -> Array[String]:
	## Format UX Observer data into human-readable lines (v4)
	var lines: Array[String] = []

	# Viewport
	var vp = ux_data.get("viewport", {})
	if not vp.is_empty():
		var cam = vp.get("camera", {})
		var zoom = vp.get("zoom", 1.0)
		var vr = vp.get("visible_rect", {})
		lines.append("ux_viewport: camera=(%.0f,%.0f) zoom=%.1f visible=(%.0f,%.0f)-(%.0f,%.0f)" % [
			cam.get("x", 0), cam.get("y", 0), zoom,
			vr.get("left", 0), vr.get("top", 0), vr.get("right", 0), vr.get("bottom", 0),
		])

	# UI layout
	var ui = ux_data.get("ui", {})
	var containers = ui.get("containers", [])
	if not containers.is_empty():
		lines.append("ux_ui:")
		for c in containers:
			var pos = c.get("pos", {})
			var sz = c.get("size", {})
			var desc = "  %s(%s) (%.0f,%.0f) %.0fx%.0f" % [
				c.get("name", "?"), c.get("class", "?"),
				pos.get("x", 0), pos.get("y", 0),
				sz.get("w", 0), sz.get("h", 0),
			]
			if c.has("text"):
				desc += " text=\"%s\"" % str(c.get("text", ""))
			if c.has("disabled"):
				desc += " %s" % ("enabled" if not c.get("disabled") else "DISABLED")
			if c.has("value"):
				desc += " val=%.0f/%.0f" % [c.get("value", 0), c.get("max", 0)]
			lines.append(desc)

	# Input log
	var input_log = ux_data.get("input_log", [])
	if not input_log.is_empty():
		lines.append("ux_input:")
		for entry in input_log:
			var frame = entry.get("frame", 0)
			var btn = entry.get("button", "?")
			var scr = entry.get("screen", {})
			var hit = entry.get("hit", {})
			var hit_type = hit.get("type", "?") if hit is Dictionary else "?"
			if hit_type == "ui":
				var hit_name = hit.get("node", "?")
				var enabled = hit.get("enabled", true)
				lines.append("  #%d %s_click(%.0f,%.0f) → hit=%s%s" % [
					frame, btn, scr.get("x", 0), scr.get("y", 0),
					hit_name, "" if enabled else " (DISABLED)",
				])
			elif hit_type == "entity":
				lines.append("  #%d %s_click(%.0f,%.0f) → hit=%s dist=%.0f" % [
					frame, btn, scr.get("x", 0), scr.get("y", 0),
					hit.get("node", "?"), hit.get("dist", 0),
				])
			else:
				lines.append("  #%d %s_click(%.0f,%.0f) → miss" % [
					frame, btn, scr.get("x", 0), scr.get("y", 0),
				])

	# Signal log
	var signal_log = ux_data.get("signal_log", [])
	if not signal_log.is_empty():
		lines.append("ux_signals:")
		for sig in signal_log:
			var frame = sig.get("frame", 0)
			var sig_name = sig.get("signal", "?")
			var args = sig.get("args", [])
			var args_str = ", ".join(args.map(func(a): return str(a)))
			lines.append("  #%d %s(%s)" % [frame, sig_name, args_str])

	return lines
