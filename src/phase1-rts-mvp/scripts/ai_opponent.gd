extends Node

## AI Opponent — 控制蓝方的简单 AI
## 三阶段：经济（造工人）→ 军事（造战士）→ 战术（编队进攻/回防）

var _hq: Node  # Blue HQ
var _team: String = "blue"
var _decision_timer: float = 0.0
var _decision_interval: float = 2.0  # seconds between decisions
var _phase: String = "economy"  # economy / military / attack
var _max_workers: int = 5
var _attack_threshold: int = 5  # attack when fighter count >= this
var _is_headless: bool = false

# Config references
var _worker_cost: int = 50
var _fighter_cost: int = 100
var _worker_time: float = 3.0
var _fighter_time: float = 5.0

# Track produced units
var _worker_count: int = 0
var _fighter_count: int = 0
var _frame_count: int = 0


func setup(hq: Node, config: Dictionary, headless: bool) -> void:
	_hq = hq
	_team = "blue"
	_is_headless = headless
	_decision_interval = float(config.decision_interval) / 60.0  # frames to seconds
	_max_workers = int(config.max_workers)
	_attack_threshold = int(config.attack_threshold)
	# headless 下使用更短的战士生产时间，加快战斗触发
	if headless and config.has("headless_fighter_time"):
		_fighter_time = float(config.headless_fighter_time)
	name = "AIOpponent"
	print("[AI] Blue AI opponent initialized (interval=%.1fs, max_workers=%d, attack_at=%d fighters, fighter_time=%.1fs)" % [
		_decision_interval, _max_workers, _attack_threshold, _fighter_time])


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_hq):
		return
	_frame_count += 1

	# Decision loop
	_decision_timer += delta
	if _decision_timer >= _decision_interval:
		_decision_timer = 0.0
		_make_decision()

	# Auto-retreat fighters when HQ is under attack
	_check_hq_under_attack()


func _make_decision() -> void:
	if not is_instance_valid(_hq):
		return

	match _phase:
		"economy":
			_economy_phase()
		"military":
			_military_phase()
		"attack":
			_attack_phase()


func _economy_phase() -> void:
	## Build workers until max, then switch to military
	var units = get_tree().get_nodes_in_group("team_blue")
	var workers = _count_type(units, "worker")
	var fighters = _count_type(units, "fighter")

	# Produce worker if below cap and can afford
	if workers < _max_workers and _hq.crystal >= _worker_cost and _hq._queue.size() < 2:
		_hq.enqueue("worker", _worker_cost, _worker_time)
		print("[AI] Producing worker (%d/%d)" % [workers + 1, _max_workers])

	# Switch to military when economy is stable
	if workers >= _max_workers:
		_phase = "military"
		print("[AI] Phase: military")


func _military_phase() -> void:
	## Build fighters for attack
	var units = get_tree().get_nodes_in_group("team_blue")
	var fighters = _count_type(units, "fighter")

	if fighters < _attack_threshold and _hq.crystal >= _fighter_cost and _hq._queue.size() < 2:
		_hq.enqueue("fighter", _fighter_cost, _fighter_time)
		print("[AI] Producing fighter (%d/%d)" % [fighters + 1, _attack_threshold])

	if fighters >= _attack_threshold:
		_phase = "attack"
		print("[AI] Phase: attack — sending fighters!")


func _attack_phase() -> void:
	## Command fighters to push toward enemy territory.
	## 持续发命令直到 fighter 进入 chase/attack 状态（找到敌人），
	## 避免 fighter 到达目标后游荡回家。
	var fighters = _get_team_fighters()
	if fighters.size() == 0:
		_phase = "military"
		print("[AI] Phase: military (no fighters left)")
		return

	var red_hq = get_parent().get_node_or_null("HQ_red")
	if not is_instance_valid(red_hq):
		return

	for f in fighters:
		if not is_instance_valid(f) or not f.has_method("get"):
			continue
		var state = f.get("_state")
		# 只在 idle/wander 时推进，chase/attack 说明已发现敌人，不干扰
		if state in ["wander", "idle"]:
			f.move_to(red_hq.global_position)


func _check_hq_under_attack() -> void:
	## If HQ HP is dropping, recall fighters
	if not is_instance_valid(_hq):
		return
	# Simple heuristic: if HQ HP < max_hp, recall
	if _hq.hp < _hq.max_hp:
		var fighters = _get_team_fighters()
		for f in fighters:
			if is_instance_valid(f) and f.has_method("get"):
				var state = f.get("_state")
				if state in ["wander", "idle"]:
					# Move back to defend HQ
					f.move_to(_hq.global_position)


func _get_team_fighters() -> Array:
	var units = get_tree().get_nodes_in_group("team_blue")
	var result: Array = []
	for u in units:
		if is_instance_valid(u) and u.has_method("get"):
			if u.get("unit_type") == "fighter":
				result.append(u)
	return result


func _count_type(units: Array, type_str: String) -> int:
	var count = 0
	for u in units:
		if is_instance_valid(u) and u.has_method("get"):
			if u.get("unit_type") == type_str:
				count += 1
	return count
