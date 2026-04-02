# Phase 7 设计文档：完整 3D 模式

> **适用阶段**：Phase 7
> **写于**：2026-03-28
> **背景**：Phase 6 已完成调试工具链的 3D 适配（Route A 工具层）。Phase 7 将完成游戏本体从 2D 到 3D 的迁移，实现完整的俯视 3D 渲染效果。
> **前置条件**：Phase 6 ✅ 完成（ai-renderer 已适配 3D 坐标）

---

## 1. 目标

将游戏本体从 Godot 2D 节点树迁移到 3D 节点树，实现：

- 单位、建筑、地图全部使用 3D 节点渲染
- 俯视 Camera3D（固定高度，垂直向下，可选正交/透视）
- 寻路系统切换到 NavigationMesh（3D）
- headless 回归维持 10/11 PASS，游戏逻辑不退步

**定位**：视觉升级，不改变核心游戏逻辑（移动、战斗、采矿、生产规则不变）。

---

## 2. 迁移策略（Route A）

保持俯视角，XZ 平面为地图，Y=0 为地面，Y 轴为高度。

```
2D 坐标 (x, y)  →  3D 坐标 (x, 0, z)
                         ↑ y 轴变 z 轴，Y=0 固定地面高度
```

所有游戏逻辑坐标在迁移时统一做此映射，不修改 config.json 中的数值。

---

## 3. 模块迁移范围

### 3.1 渲染设置

- 渲染管线改为 **Forward+**（project.godot）
- 物理引擎保持 **Jolt Physics**（已是 Godot 4.6 默认）
- 主场景根节点从 `Node2D` 改为 `Node3D`

### 3.2 摄像机（Camera）

| 属性 | 值 |
|------|----|
| 节点类型 | Camera3D |
| 投影模式 | Orthographic（正交，保留 RTS 俯视感）|
| 位置 | `(map_w/2, 1500, map_h/2)`（地图中央正上方）|
| 旋转 | `rotation_degrees = (-90, 0, 0)`，垂直朝下 |
| Size | 根据地图宽度调整 |

选择正交投影的原因：俯视 RTS 无透视失真，单位大小一致，视觉与原 2D 版本最接近。

### 3.3 地图与导航

| 组件 | 2D | 3D |
|------|----|----|
| 地面 | 无（背景色） | StaticBody3D + PlaneMesh（2560×1664） |
| 障碍物 | StaticBody2D + CollisionShape2D | StaticBody3D + BoxMesh + BoxShape3D |
| 导航网格 | NavigationPolygon | NavigationMesh（烘焙在地面 + 障碍物上）|
| 导航区域 | NavigationRegion2D | NavigationRegion3D |

导航网格烘焙流程：
```
创建 NavigationRegion3D
  → 附加地面 MeshInstance3D
  → 标记障碍物为导航阻塞体
  → 调用 bake_navigation_mesh()（运行时或编辑器预烘焙）
```

### 3.4 游戏实体

| 实体 | 2D 节点 | 3D 节点 | 碰撞形状 |
|------|---------|---------|---------|
| Worker | CharacterBody2D | CharacterBody3D | CapsuleShape3D（r=6, h=12）|
| Fighter | CharacterBody2D | CharacterBody3D | CapsuleShape3D（r=8, h=16）|
| HQ | StaticBody2D | StaticBody3D | BoxShape3D |
| 矿物节点 | Area2D | Area3D | SphereShape3D |
| 障碍物 | StaticBody2D | StaticBody3D | BoxShape3D |

碰撞层设置不变（2D/3D 机制完全一致，32 层）。

**视觉表现**（最简方案，可后续替换模型）：

| 实体 | 临时 Mesh |
|------|-----------|
| Worker | CapsuleMesh，红/蓝色材质 |
| Fighter | CylinderMesh，红/蓝色材质 |
| HQ | BoxMesh，红/蓝色材质 |
| 矿物节点 | SphereMesh，青绿色材质 |
| 地面 | PlaneMesh，深灰色材质 |
| 障碍物 | BoxMesh，深色材质 |

使用临时 Mesh 的原因：保证迁移后游戏功能完整可测试，模型美术可独立替换，不阻塞功能验证。

### 3.5 单位脚本迁移

移动逻辑核心变化：

```
【2D】
  velocity = Vector2(dir.x, dir.y) * speed
  move_and_slide()

【3D Route A（Y 锁定为 0）】
  velocity = Vector3(dir.x, 0, dir.z) * speed
  move_and_slide()
  # 不添加重力，单位始终贴地
```

NavigationAgent2D → NavigationAgent3D，接口一致：
- `target_position` 类型 Vector2 → Vector3
- `get_next_path_position()` 返回 Vector3
- 其他信号/方法名称不变

索敌逻辑（Fighter）：当前用 `get_nodes_in_group()` 遍历 + `distance_to()`，无需改动，只需把 `global_position` 当作 Vector3 处理。

### 3.6 UI 层（不迁移）

所有 UI 节点（CanvasLayer、Control、BottomBar、ProdPanel、GameOver）保持 2D，CanvasLayer 自动覆盖在 3D 视口上方，无需改动。

健康条（HealthBar）使用 Billboard 模式的 `Label3D` 或保持 2D CanvasLayer 方案（推荐保持 2D，简单稳定）。

### 3.7 调试工具（ai-renderer）

Phase 6 已完成适配，`coord_mode="xz"` 模式透传给 ActionExecutor，格式化输出自动投影 XZ 平面。Phase 7 只需在 `game_world.gd` 中：
- 注册 Camera3D 为 sensor（group: `"camera"`）
- 调用 `SimulatedPlayer.setup()` 时传入 `coord_mode="xz"`
- 调用 `input_server.setup()` 时传入 `selection_manager`（bootstrap 已做）

---

## 4. 架构图

```
Bootstrap (Node3D)
├── Camera3D               ← 正交俯视，固定高度
├── NavigationRegion3D     ← 烘焙导航网格
│   └── MeshInstance3D     ← 地面 PlaneMesh
├── StaticBody3D × N       ← 障碍物
├── StaticBody3D (HQ_red)
├── StaticBody3D (HQ_blue)
├── Area3D × 3             ← 矿物节点
├── CharacterBody3D × N    ← Worker / Fighter
├── CanvasLayer            ← UI（BottomBar / ProdPanel / GameOver）
└── [ai-renderer tools]    ← InputServer / SelectionBox 等
```

---

## 5. 迁移步骤规划

### 子阶段 7A：项目基础切换

- project.godot 渲染管线改为 Forward+
- 主场景根节点改为 Node3D
- 添加 Camera3D + DirectionalLight3D（基础光照）
- 验证：空场景能启动，不崩溃

### 子阶段 7B：地图与导航

- 创建地面 StaticBody3D
- 障碍物 StaticBody2D → StaticBody3D
- 配置 NavigationRegion3D，烘焙导航网格
- 验证：headless 下导航网格可烘焙（无报错）

### 子阶段 7C：实体迁移

- HQ：StaticBody2D → StaticBody3D
- 矿物节点：Area2D → Area3D
- Worker：CharacterBody2D → CharacterBody3D + NavigationAgent3D
- Fighter：CharacterBody2D → CharacterBody3D + NavigationAgent3D
- 验证：headless 回归 10/11 PASS

### 子阶段 7D：摄像机与视觉

- Camera3D 正交摄像机定位、尺寸调整
- 各实体添加临时 Mesh（CapsuleMesh / BoxMesh 等）
- DirectionalLight3D + 环境光调整
- 验证：窗口模式下视觉正常，UI 覆盖正确

### 子阶段 7E：ai-renderer 接入

- game_world.gd 传入 `coord_mode="xz"` 给 SimulatedPlayer
- 注册 Camera3D 为 sensor
- 验证：headless ai_debug 输出坐标语义正确

#### 镜头语义描述设计

**当前 2D 日志的问题**：
```
ux_viewport: camera=(1000,750) zoom=1.0 visible=(0,0)-(2000,1500)
```
在 3D 场景里，`(1000, 750)` 会被误读为地图 XZ 坐标，但 750 实际是摄像机高度（Y 轴），AI 无法得知镜头朝向和实际可见范围。

**3D 场景应输出的镜头段**：
```
camera_3d: pos=(1280,1500,832) pitch=-90° ortho_size=1664
           ground_view=(0,0)-(2560,1664)    ← frustum 与 Y=0 的交集矩形（XZ）
           units_in_view=8/13               ← 当前视野内/全场单位数
```

字段说明：

| 字段 | 含义 | 为什么需要 |
|------|------|-----------|
| `pos=(x,y,z)` | 摄像机世界坐标，y 为高度 | AI 能区分高度与地图纵向坐标 |
| `pitch` | 俯视角（-90°= 垂直朝下） | 反映画面倾斜感；偏离 -90° 说明配置异常 |
| `ortho_size` | 正交模式可见高度（世界单位） | 等效于 2D 的 zoom，决定缩放感 |
| `ground_view` | frustum 投影到 Y=0 的矩形（XZ 坐标） | AI 能直接对比"地图范围"与"当前可见范围" |
| `units_in_view` | 视野内单位数/总单位数 | 快速判断镜头是否覆盖战场关键区域 |

**ground_view 计算方式**（正交模式）：
```
half_h = ortho_size / 2
half_w = ortho_size * (viewport_width / viewport_height) / 2
ground_view = Rect2(
    cam.x - half_w, cam.z - half_h,
    half_w * 2, half_h * 2
)
```

透视模式（若后续切换）需改为 frustum 与 Y=0 平面的射线相交计算，复杂度更高，Phase 7 暂用正交。

**实现位置**：`formatter_engine.gd` 新增 `_format_camera_3d(snapshot)` 函数，替换现有 `_format_ux` 中的 `ux_viewport` 段；sensor 注册时额外采集 `size`（ortho_size）、`rotation`（pitch）字段。

#### 事件驱动截图设计

**当前问题**：UX Observer 只有定时截图（每 5 秒），截图时机与验证目标完全无关。AI 调试视觉问题时只能靠帧号猜图，详见设计文档 `docs/design/tech/ai-renderer.md §8.6`。

**方案**：在 `UXObserver.on_signal()` 里加白名单匹配，命中关键信号时自动触发截图，文件名包含事件语义。

```
ux_hq_selected_f1202.png
ux_prod_panel_shown_f1204.png
ux_battle_first_kill_f3240.png
ux_game_over_f5100.png
```

**场景 JSON 配置**：在 `screenshot_on_signals` 字段声明本场景关心的信号，UX Observer 只在这些信号触发时拍照：

```json
{
  "name": "combat",
  "screenshot_on_signals": ["battle_first_kill", "game_over"]
}
```

**信号白名单**（默认）：

| 信号 | 视觉验证目的 |
|------|------------|
| `hq_selected` | 确认生产面板正确弹出 |
| `prod_panel_shown` | 确认按钮可见、布局正确 |
| `unit_produced` | 确认单位在 HQ 附近生成 |
| `game_over` | 确认结束画面覆盖正确 |

`battle_first_kill` 需要在 `UnitLifecycleManager` 首次记录 kill 时通过 bootstrap 转发给 UXObserver，其余信号已有对应的 `on_signal()` 调用点。

**实现位置**：
- `ux_observer.gd`：`on_signal()` 里增加白名单匹配 + 触发 `take_screenshot(signal_name)`
- `bootstrap.gd`：读取 scenario 的 `screenshot_on_signals`，传给 `UXObserver.set_screenshot_signals()`
- `unit_lifecycle_manager.gd`：首次 kill 时发出信号，bootstrap 转发给 UX Observer

---

## 6. 风险与对策

| 风险 | 可能性 | 对策 |
|------|--------|------|
| NavigationMesh 烘焙在 headless 下失败 | 中 | 改为编辑器预烘焙并保存到 .tres，运行时直接加载 |
| NavigationAgent3D 路径质量差（绕路） | 中 | 调整 NavigationMesh cell_size / cell_height 参数 |
| 大量单位性能下降 | 低 | 当前单位数 < 20，Jolt 可轻松处理；后续用 MultiMesh |
| 着色器首次编译卡顿 | 低 | 临时 Mesh 用基础材质，首帧卡顿可接受 |

---

## 7. 验收标准

- headless 回归 scenario 测试全部 PASS（`bash tests/run_scenarios.sh`）
- 窗口模式可正常游玩：单位移动、采矿、战斗、生产流程全部正常
- Camera3D 正交俯视，地图完整显示在屏幕内
- UI（资源显示、生产面板、游戏结束画面）正常覆盖在 3D 视口上
- ai_debug 日志输出 `camera_3d` 段：`pitch=-90°`，`ground_view` 覆盖完整地图范围，`units_in_view` 计数与实际一致
- 窗口模式运行 combat 场景后，`tests/screenshots/` 目录下存在 `ux_battle_first_kill_*.png` 和 `ux_game_over_*.png`，画面内容与事件语义一致
