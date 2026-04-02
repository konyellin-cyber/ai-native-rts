# CharacterBody2D API 参考

> 来源: Godot 4.6 官方文档 https://docs.godotengine.org/en/stable/classes/class_characterbody2d.html

## 属性

### 运动属性

| 属性名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| velocity | Vector2 | Vector2(0,0) | 当前速度（像素/秒），`move_and_slide()` 时使用和修改 |
| motion_mode | int | 0 | 运动模式：0=GROUNDED（平台游戏），1=FLOATING（俯视角） |
| up_direction | Vector2 | Vector2(0,-1) | 指向上方的向量 |

### 碰撞属性

| 属性名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| safe_margin | float | 0.08 | 碰撞恢复的额外边距，值越高越灵活，值越低越精确 |
| max_slides | int | 4 | 停止前可改变方向的最大次数 |
| floor_max_angle | float | 0.7853982 | 最大地板角度（弧度，默认 45 度） |
| floor_snap_length | float | 1.0 | 吸附距离，非 0 时身体会紧贴斜坡 |

### RTS 俯视角游戏关键设置

```gdscript
# 俯视角 RTS 必须设置！
motion_mode = CharacterBody2D.MOTION_MODE_FLOATING  # 无地板概念
```

## 方法

### 核心

| 方法 | 返回类型 | 说明 |
|------|----------|------|
| `move_and_slide()` | bool | **核心移动方法**。基于 velocity 移动，碰撞时滑动。在 `_physics_process` 中使用 |
| `get_real_velocity()` | Vector2 | 返回实际移动速度（考虑碰撞滑动后的） |
| `get_position_delta()` | Vector2 | 上次 move_and_slide 的实际位移 |

### 碰撞检测

| 方法 | 返回类型 | 说明 |
|------|----------|------|
| `get_last_slide_collision()` | KinematicCollision2D | 最近一次碰撞信息，无碰撞返回 null |
| `get_slide_collision(idx: int)` | KinematicCollision2D | 指定索引的碰撞信息 |
| `get_slide_collision_count()` | int | 上次碰撞并改变方向的次数 |
| `is_on_floor()` | bool | 是否在地板上 |
| `is_on_wall()` | bool | 是否在墙上 |
| `is_on_ceiling()` | bool | 是否在天花板上 |

## 重要注意事项

- **velocity 不乘 delta**: 直接设置速度值（像素/秒），`move_and_slide()` 自动处理帧时间
- **FLOATING 模式**: RTS 俯视角游戏必须用 `MOTION_MODE_FLOATING`，否则 `up_direction` 会影响碰撞行为
- **每帧调用**: `move_and_slide()` 必须在 `_physics_process()` 中每帧调用
