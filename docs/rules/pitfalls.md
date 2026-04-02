# 踩坑记录

> Godot 4.6.1 + headless CLI 模式开发中遇到的实际问题和解决方案。按严重程度排序。

---

## 1. `--quit-after` 参数在 headless 模式下直接退出

**严重程度**: 🔴 阻塞

**现象**:
```bash
godot --headless --quit-after 300
# 立即退出，场景根本没跑
```

**原因**: Godot 4.6 的 `--quit-after` 在 headless 模式下有 bug，会在场景初始化之前就触发退出。

**解决方案**: 在 GDScript 中自行控制生命周期，用 `_physics_process` 计数帧数，达到目标帧数后调用 `get_tree().quit()`。

```gdscript
# bootstrap.gd
var _frame_count := 0

func _physics_process(_delta: float) -> void:
    _frame_count += 1
    if _frame_count >= _total_frames:
        get_tree().quit()
```

**教训**: 不要依赖 Godot 的 CLI 时间参数，生命周期控制放 GDScript 里更可靠。

---

## 2. Headless 模式默认物理帧率极低（~1fps）

**严重程度**: 🔴 阻塞

**现象**: headless 模式下，300 帧跑了将近 5 分钟，物理计算严重不准。

**原因**: Godot headless 模式没有渲染循环驱动，默认 physics tick 频率极低。

**解决方案**: 在 `_ready()` 中显式设置物理帧率：

```gdscript
func _ready() -> void:
    Engine.set_physics_ticks_per_second(60)
```

也可以在 `project.godot` 中全局设置：
```ini
[physics]
common/physics_fps=60
```

**教训**: headless 模式 ≠ 正常帧率，必须显式设置 `physics_ticks_per_second`。

---

## 3. 默认重力 980 影响所有 RigidBody2D

**严重程度**: 🟡 逻辑错误

**现象**: 球体不受控制地向下加速，运动轨迹不符合预期。

**原因**: Godot 4 的 2D 物理默认重力为 `980`（模拟地球重力），即使你只想做水平碰撞场景。

**解决方案**: 在 `project.godot` 中关闭默认重力：
```ini
[physics]
2d/default_gravity=0
```

**注意**: 运行时用 `PhysicsServer2D.set_gravity()` 在 4.6 中会报错，用项目设置最可靠。

**教训**: 创建任何非平台跳跃场景前，先检查 `default_gravity` 设置。

---

## 4. `body_entered` 信号对动态创建的 RigidBody2D 不触发

**严重程度**: 🔴 阻塞

**现象**: 通过 `RigidBody2D.new()` 动态创建的球体，`body_entered` 信号连接后完全不触发，即使球体明显在碰撞。

**尝试过的方案（都失败）**:
- `body_entered.connect(_on_body_entered)` 在 `_ready()` 中连接
- 延迟连接（等一帧后再 connect）
- 使用 `Callable` 包装

**根本原因**: Godot 4 的 `body_entered` 信号要求碰撞体在场景树中有稳定的物理状态，动态创建的节点可能错过信号注册窗口期。

**解决方案**: 放弃信号模式，改用 `contact_monitor` 轮询：

```gdscript
func _ready() -> void:
    contact_monitor = true
    max_contacts_reported = 10

func _physics_process(_delta: float) -> void:
    var bodies = get_colliding_bodies()
    if bodies.size() > 0:
        # 正在碰撞
```

**教训**: 动态创建的物理节点，用 `contact_monitor` 比信号更可靠。

---

## 5. Collision Layer/Mask 默认值导致碰撞失效

**严重程度**: 🟡 逻辑错误

**现象**: 球体穿墙而过，互不碰撞。

**原因**: Godot 默认所有节点的 `collision_layer = 1`，`collision_mask = 1`。虽然值相同，但如果只在代码中设置了一方，另一方仍是默认值 1，可能出现意外匹配。

**解决方案**: 显式设置双方的 layer 和 mask：

```
墙壁: layer=1, mask=2   # 在第 1 层，检测第 2 层
球体: layer=2, mask=3   # 在第 2 层，检测第 1 层(墙)和第 2 层(球)
```

```gdscript
# 墙壁
wall.collision_layer = 1
wall.collision_mask = 2

# 球体
ball.collision_layer = 2
ball.collision_mask = 3  # 1(墙) + 2(球) = 3
```

**教训**: 永远不要依赖 collision layer/mask 的默认值，显式设置每一个物理节点的碰撞层。

---

## 6. Shell 脚本中 `cd` 不跨命令持久化

**严重程度**: 🟢 小问题

**现象**: 脚本中 `cd project_dir` 后，下一条命令的工作目录又回到了原处。

**原因**: CodeBuddy 的 `execute_command` 每次调用是新 shell，`cd` 不会跨调用持久化。

**解决方案**: 用绝对路径，或用变量 `PROJECT_DIR`：

```bash
PROJECT_DIR="/path/to/project"
godot --headless --path $PROJECT_DIR
```

**教训**: CLI 脚本中始终用绝对路径。

---

## 7. `await get_tree().process_frame` 导致首帧数据缺失

**严重程度**: 🟢 小问题

**现象**: `frame_000001.json` 导出的 `balls` 数组为空，从 frame 2 开始才有数据。

**原因**: `state_exporter.gd` 在 `_ready()` 中用 `await get_tree().process_frame` 延迟收集球节点，导致第一帧物理计算时球列表还未填充。

```gdscript
func _ready() -> void:
    await get_tree().process_frame  # 等一帧
    _collect_balls()                 # 第二帧才收集
```

**解决方案**:
1. 接受首帧数据缺失（推荐，对 300 帧模拟影响微乎其微）
2. 或改用 `call_deferred("_collect_balls")`（仍可能错过首帧）
3. 或在 `_physics_process` 首次调用时检查并懒加载（最可靠）

**教训**: 使用 `await` 的异步初始化会影响数据采集的起始点，需在文档中说明。

---

---

## 8. `NavigationPolygon.bake()` 在 Godot 4.6 中不存在

**严重程度**: 🔴 阻塞

**现象**: 代码中调用 `nav_poly.bake()` 报错 `Method not found`。

**原因**: Godot 4.6 移除了 `NavigationPolygon.bake()` 无参方法，改为 `bake_from_source_geometry_data()`。

**解决方案**: 使用 `NavigationMeshSourceGeometryData2D` 收集几何数据后烘焙：

```gdscript
var source_data = NavigationMeshSourceGeometryData2D.new()
source_data.add_traversable_outline(PackedVector2Array([
    Vector2(0, 0), Vector2(2000, 0),
    Vector2(2000, 1500), Vector2(0, 1500)
]))
# 添加障碍物
source_data.add_obstruction_outline(PackedVector2Array([
    Vector2(500, 300), Vector2(700, 300),
    Vector2(700, 500), Vector2(500, 500)
]))
var nav_poly = NavigationPolygon.new()
nav_poly.bake_from_source_geometry_data(source_data)
```

或者通过 `NavigationRegion2D` 烘焙：
```gdscript
nav_region.bake_navigation_polygon(false)  # false = 同步
```

**教训**: AI 对 Godot API 版本变更容易产生幻觉，遇到不存在的 API 必须查官方文档验证。

---

## 9. Node2D 画布坐标系与视口坐标系不一致（框选偏移）

**严重程度**: 🔴 阻塞

**现象**: 用鼠标拖拽框选时，选框矩形出现在鼠标位置的右下方，偏移量固定（约 190px, 91px）。

**根本原因**: Node2D 的子节点（Line2D、Polygon2D）在**画布坐标系**（canvas local coordinates）中绘制；但视口（Viewport）的 canvas_transform 存在非零 origin，导致视口坐标 ≠ 画布坐标：

```
canvas_transform.origin = (190, 91)  # 示例值，取决于相机/窗口布局
视口坐标 = 画布坐标 + canvas_transform.origin
```

**错误的坐标来源**（都踩过）：
- `event.position` — macOS 逻辑像素（Retina 2x 时 = 物理像素 / 2），会产生 2x 缩放误差
- `event.global_position` — 屏幕绝对坐标（含窗口标题栏/菜单栏偏移，约 Y+220px）
- `get_viewport().get_mouse_position()` — 视口物理像素坐标，与画布坐标有 canvas_transform.origin 的固定偏移

**正确方案**: 使用 `get_global_mouse_position()`，它会自动逆变换 canvas_transform，返回与 Node2D 子节点一致的画布坐标。

```gdscript
# selection_box.gd（Node2D）
_drag_start = get_global_mouse_position()  # ✅ 画布坐标，与 Line2D/Polygon2D 一致
```

**同步问题 — selection_manager 的单位坐标**：
框选 rect 用画布坐标，而 `camera.unproject_position()` 返回视口像素坐标。
两者对齐方式：用 `unproject_position()` 的结果减去 `get_canvas_transform().origin`：

```gdscript
var vp_pos = camera.unproject_position(unit.global_position)
var canvas_origin = get_canvas_transform().origin
screen_pos = vp_pos - canvas_origin  # ✅ 对齐到画布坐标
```

**教训**: 在 2D overlay（Node2D 上叠加 UI 框）+ 3D 相机的混合场景中，必须明确每个坐标来自哪个坐标系（屏幕/视口/画布/世界），绝不能混用。优先用 `get_global_mouse_position()` 而非 `event.position`。

---

## 通用经验总结

| 类别 | 规则 |
|------|------|
| 生命周期 | 不要用 `--quit-after`，GDScript 内计数 + `get_tree().quit()` |
| 物理帧率 | headless 必须 `Engine.set_physics_ticks_per_second(60)` |
| 重力 | 非跳跃场景设 `2d/default_gravity=0` |
| 碰撞检测 | 动态节点用 `contact_monitor`，不用 `body_entered` 信号 |
| 碰撞层 | 显式设置所有节点的 `collision_layer` 和 `collision_mask` |
| 路径 | CLI 脚本全部用绝对路径 |
| API 幻觉 | Godot API 版本差异大，不确认存在就别用，先查本地知识库或官方文档 |
| 坐标系混用 | Node2D overlay + 3D Camera 混合场景：拖拽用 `get_global_mouse_position()`（画布坐标），单位投影用 `unproject_position() - canvas_transform.origin` 对齐 |
