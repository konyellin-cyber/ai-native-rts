# NavigationAgent2D API 参考

> 来源: Godot 4.6 官方文档 https://docs.godotengine.org/en/stable/classes/class_navigationagent2d.html

## 属性

| 属性名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| avoidance_enabled | bool | false | 是否启用避障 |
| path_desired_distance | float | 20.0 | 距离路径点多近视为到达该点 |
| target_desired_distance | float | 5.0 | 距离最终目标点多近视为完成 |
| path_max_distance | float | 5.0 | 允许偏离路径的最大距离 |
| navigation_layers | int | 1 | 使用的导航层 |
| radius | float | 10.0 | 避障半径 |
| max_speed | float | -1.0 | 最大速度（避障用，-1=无限制） |
| target_position | Vector2 | Vector2(0,0) | **寻路目标位置（世界坐标）**，设置后自动计算路径 |

## 方法

| 方法 | 返回类型 | 说明 |
|------|----------|------|
| `get_next_path_position()` | Vector2 | **获取路径中下一个路点** |
| `is_navigation_finished()` | bool | **是否已到达最终目标** |
| `set_velocity(velocity: Vector2)` | void | 将速度输入避障系统 |
| `get_current_navigation_path()` | PackedVector2Array | 获取完整路径点数组 |
| `get_current_navigation_path_index()` | int | 当前路径点索引 |
| `set_target_position(position: Vector2)` | void | 设置目标（等同修改 target_position 属性） |
| `get_distance_to_target()` | float | 到最终目标的直线距离 |

## 信号

| 信号 | 说明 |
|------|------|
| `velocity_computed(safe_velocity: Vector2)` | 避障系统计算完成后发出，携带修正后的安全速度 |
| `navigation_finished()` | 到达目标位置时发出 |
| `path_changed()` | 路径重新计算或改变时发出 |

## 典型用法（不带避障）

```gdscript
extends CharacterBody2D

@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
var movement_speed: float = 200.0

func _ready() -> void:
    # 关键：等待 NavigationServer 同步第一帧
    await get_tree().physics_frame
    navigation_agent.target_position = Vector2(100, 100)

func set_movement_target(target_position: Vector2):
    navigation_agent.target_position = target_position

func _physics_process(_delta):
    if navigation_agent.is_navigation_finished():
        return
    var next_pos = navigation_agent.get_next_path_position()
    velocity = global_position.direction_to(next_pos) * movement_speed
    move_and_slide()
```

## 典型用法（带避障）

```gdscript
extends CharacterBody2D

@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
var movement_speed: float = 200.0

func _ready() -> void:
    navigation_agent.velocity_computed.connect(_on_velocity_computed)
    navigation_agent.avoidance_enabled = true
    await get_tree().physics_frame
    set_movement_target(Vector2(100, 100))

func set_movement_target(target_position: Vector2):
    navigation_agent.target_position = target_position

func _physics_process(_delta):
    if navigation_agent.is_navigation_finished():
        return
    var next_pos = navigation_agent.get_next_path_position()
    var new_velocity = global_position.direction_to(next_pos) * movement_speed
    if navigation_agent.avoidance_enabled:
        navigation_agent.set_velocity(new_velocity)
    else:
        velocity = new_velocity
        move_and_slide()

func _on_velocity_computed(safe_velocity: Vector2):
    velocity = safe_velocity
    move_and_slide()
```

## 重要注意事项

- **初始化**: 必须等待 `await get_tree().physics_frame` 后才能设置 target_position，否则导航地图可能为空
- **velocity 不要乘 delta**: `move_and_slide()` 自动处理帧时间
- **路径点 vs 目标点**: `path_desired_distance` 控制到达路径中间点的精度，`target_desired_distance` 控制到达终点的精度
