extends Node3D

## Arrow — 箭矢弹道节点（抛物线重力弹道）
## 由 ArrowManager.fire() 创建，每物理帧按速度向量飞行。
##
## 飞行规则：
##   - 初速度 = _velocity（由 archer 计算好的 3D 发射速度，含仰角）
##   - 每帧：_velocity.y -= gravity * delta（重力向下加速）
##   - 移动：position += _velocity * delta
##   - 落地（global_position.y < -10）→ 销毁
##   - 累计水平飞行距离超过 max_range → 销毁
##   - 命中单位 → take_damage，加入 _hit_targets（穿透）
##   - 窗口模式：arrow 节点旋转对齐速度方向，形成弧形弹道视觉

var damage: float = 15.0
var max_range: float = 160.0
var owner_team: String = "red"

var _velocity: Vector3 = Vector3.ZERO   ## 当前速度向量（每帧被重力修改）
var _gravity: float = 2400.0           ## 重力加速度（游戏单位/s²）
var _xz_traveled: float = 0.0         ## 水平飞行距离（用于 max_range 判定）
var _hit_targets: Array = []
var _obstacles: Array = []
var _arrow_radius: float = 5.0
var _enemy_group: String = ""
var _headless: bool = false

## 插身状态
var _stuck_to: Node = null      ## 命中后跟随的目标节点
var _stuck_offset: Vector3      ## 命中时相对目标的局部偏移
var _stuck_timer: float = 0.0   ## 插身后存活倒计时（秒）
const STUCK_DURATION = 3.0      ## 箭矢插身后保留时间


func setup(
	velocity: Vector3,
	dmg: float,
	range: float,
	team: String,
	obstacles: Array,
	headless: bool,
	gravity: float = 2400.0
) -> void:
	_velocity = velocity
	damage = dmg
	max_range = range
	owner_team = team
	_obstacles = obstacles
	_enemy_group = "team_blue" if team == "red" else "team_red"
	_headless = headless
	_gravity = gravity

	if not headless:
		_add_visual()


func _physics_process(delta: float) -> void:
	## ── 插身模式：跟随目标移动，倒计时后销毁 ──
	if _stuck_to != null:
		if not is_instance_valid(_stuck_to) or _stuck_to.get("_state") == "dead":
			## 目标死亡时停留原地再等一会儿
			_stuck_to = null
			_stuck_timer = min(_stuck_timer, 0.8)
			return
		global_position = _stuck_to.global_position + _stuck_offset
		_stuck_timer -= delta
		if _stuck_timer <= 0:
			queue_free()
		return

	## ── 飞行模式 ──
	_velocity.y -= _gravity * delta
	var move = _velocity * delta
	position += move
	_xz_traveled += Vector2(move.x, move.z).length()

	if global_position.y < -10.0:
		queue_free()
		return

	if _xz_traveled >= max_range:
		queue_free()
		return

	if _check_obstacle_hit():
		queue_free()
		return

	_check_unit_hits()

	if not _headless and _velocity.length_squared() > 0.01:
		var forward = _velocity.normalized()
		var up_hint = Vector3.UP if abs(forward.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
		transform.basis = Basis.looking_at(forward, up_hint)


func _check_obstacle_hit() -> bool:
	var px = global_position.x
	var pz = global_position.z
	for obs in _obstacles:
		var ox: float = float(obs.get("x", 0))
		var oz: float = float(obs.get("y", 0))
		var ow: float = float(obs.get("w", 0))
		var oh: float = float(obs.get("h", 0))
		if px >= ox and px <= ox + ow and pz >= oz and pz <= oz + oh:
			return true
	return false


func _check_unit_hits() -> void:
	var enemies = get_tree().get_nodes_in_group(_enemy_group)
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy in _hit_targets:
			continue
		if enemy.has_method("get") and enemy.get("_state") == "dead":
			continue
		## 重力弹道命中判定：用 XZ 水平距离 + Y 高度范围双重判断。
		## 箭矢在弧顶时 Y 值很高，若用 3D 距离会漏判；
		## 改为水平 XZ 距离 < 命中半径，且 Y 高度 < 单位高度上方即判命中。
		var ep = enemy.global_position
		var xz_dist = Vector2(global_position.x - ep.x, global_position.z - ep.z).length()
		var unit_r = float(enemy.get("unit_radius") if enemy.get("unit_radius") else 8.0)
		var unit_h = unit_r * 3.0   ## 单位高度（与 _add_visual 一致）
		if xz_dist <= _arrow_radius + unit_r and global_position.y <= ep.y + unit_h + 5.0:
			## 优先调用 take_damage_from（带击退），降级到普通 take_damage
			if enemy.has_method("take_damage_from"):
				enemy.take_damage_from(damage, global_position)
			else:
				enemy.take_damage(damage)
			_hit_targets.append(enemy)
			_stuck_to = enemy
			_stuck_offset = global_position - ep
			_stuck_timer = STUCK_DURATION
			if not _headless:
				_spawn_hit_flash(ep + Vector3(0.0, unit_h * 0.5, 0.0))


func _add_visual() -> void:
	## 窗口模式：细长胶囊体表示箭矢。
	## 默认沿 -Z 轴延伸（配合 Basis.looking_at 对齐速度方向）。
	## CapsuleMesh 默认沿 Y 轴，旋转 90° 使其沿 Z 轴。
	var mesh_inst = MeshInstance3D.new()
	var capsule = CapsuleMesh.new()
	capsule.radius = 3.0
	capsule.height = 22.0
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.75, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.6, 0.0)
	mat.emission_energy_multiplier = 0.5
	capsule.material = mat
	mesh_inst.mesh = capsule
	## 让胶囊长轴对齐 +Z（Basis.looking_at 让 -Z 指向速度方向，+Z 为尾部）
	mesh_inst.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	add_child(mesh_inst)


func _spawn_hit_flash(world_pos: Vector3) -> void:
	var flash = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 14.0
	sphere.height = 28.0
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.0)
	mat.emission_energy_multiplier = 2.0
	sphere.material = mat
	flash.mesh = sphere
	flash.global_position = world_pos
	var root = get_tree().root.get_child(get_tree().root.get_child_count() - 1)
	root.add_child(flash)
	get_tree().create_timer(0.12).timeout.connect(func(): if is_instance_valid(flash): flash.queue_free())
