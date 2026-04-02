extends Node

## ArrowManager — 箭矢生命周期管理器
## 由 bootstrap/game_world 创建并挂到场景树，Archer 通过它发射箭矢。

const _ArrowScript = preload("res://scripts/arrow.gd")

var _obstacles: Array = []
var _headless: bool = false
var _gravity: float = 2400.0
const MAX_ARROWS = 40  ## 全场活跃箭矢上限，超出时销毁最旧的一支


func setup(obstacles: Array, headless: bool, arrow_speed: float = 600.0) -> void:
	_obstacles = obstacles
	_headless = headless
	## gravity 与 arrow_speed 无关，这里保留 arrow_speed 参数兼容旧调用签名
	## archer.gd 自行计算发射速度，不通过这里传入 speed


func fire(
	origin: Vector3,
	velocity: Vector3,
	damage: float,
	max_range: float,
	owner_team: String
) -> void:
	## 超出上限时销毁最旧那支（get_child(0) 是最早加入的）
	if get_child_count() >= MAX_ARROWS:
		var oldest = get_child(0)
		if is_instance_valid(oldest):
			oldest.queue_free()

	var arrow = Node3D.new()
	arrow.set_script(_ArrowScript)
	arrow.position = origin
	add_child(arrow)
	arrow.setup(velocity, damage, max_range, owner_team, _obstacles, _headless, _gravity)


func get_active_count() -> int:
	return get_child_count()
