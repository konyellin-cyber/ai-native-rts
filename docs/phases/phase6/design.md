# AI Renderer 3D 适配设计文档（Route A）

> **适用阶段**：Phase 6
> **写于**：2026-03-28
> **背景**：游戏视觉升级为俯视 3D 渲染（Camera3D 高处向下看，XZ 平面为地图，Y=0 为地面），调试工具链需同步适配。

---

## 1. 目标

让 `ai-renderer` 工具链在 3D 场景下继续正常工作：
- 传感器能采集 3D 单位的状态（位置、HP、AI 状态）
- 格式化输出对 AI 可读，坐标语义不产生歧义
- 模拟玩家（SimulatedPlayer）的移动指令能正确对应 3D 世界坐标
- TCP 命令层新增 `world_click` 命令，支持直接传入世界坐标

不在本次范围内：
- 3D 场景的实际创建（游戏实体 2D→3D 迁移）
- Camera3D 的 raycast 屏幕→世界坐标转换（鼠标输入仍走原有 InputEvent 注入）

---

## 2. 坐标约定

俯视 3D RTS 的坐标系：

```
Y 轴 = 高度（单位固定在 Y=0 地面）
X 轴 = 地图水平方向
Z 轴 = 地图纵向（对应 2D 的 Y 轴）

2D pos (x, y)  →  3D pos (x, 0, z)
                         ↑ z 对应原来的 y
```

AI 可读输出中，坐标显示为 `(x, z)` 二元组，省略固定的 y=0，保持与 2D 输出格式一致。

---

## 3. 模块改动范围

### 无需改动

| 模块 | 原因 |
|------|------|
| `sensor_registry.gd` | `node.get(field)` 对 Vector3 透明，无类型假设 |
| `calibrator.gd` | 纯断言状态机，与坐标无关 |
| `signal_tracer.gd` | 纯事件记录 |
| `input_server.gd` | TCP 层 |
| `ui_inspector.gd` | Control 节点永远 2D |

### 需要改动

#### 3.1 `formatter_engine.gd` — 坐标投影

**问题**：`_format_worker_behavior` 在第 238-239 行硬编码 `Vector2(pos.x, pos.y)`。3D 下 `global_position` 是 Vector3，`pos.y` 是高度（恒为 0），应取 `pos.z` 作为地图纵向坐标。

**改动**：提取辅助函数 `_to_flat(pos) -> Vector2`，将位置投影到 XZ 平面：
- 若 pos 有 z 属性（Vector3）→ 返回 `Vector2(pos.x, pos.z)`
- 否则（Vector2）→ 返回 `Vector2(pos.x, pos.y)`

调用处（两处 `Vector2(pos.x, pos.y)`、一处 `Vector2(prev.x, prev.y)` 及 target 同理）统一改用 `_to_flat()`。

格式化输出格式不变，AI 侧感知为零。

#### 3.2 `action_executor.gd` — 坐标模式参数化

**问题**：`setup()` 接受 `Node2D` 类型的 `sel_box`/`sel_mgr`；`_resolve_target()` 返回 Vector2；移动指令传给 `simulate_right_click(Vector2)`。3D 下单位的 `move_to()` 需要 Vector3。

**改动**：

- `setup()` 新增可选参数 `coord_mode: String = "2d"`（取值 `"2d"` 或 `"xz"`）
- `sel_box`/`sel_mgr` 类型改为 `Node`（Node2D 是 Node 子类，兼容不变）
- `_resolve_target()` 在 `"xz"` 模式下返回 `Vector3(x, 0, z)`，`"2d"` 模式保持返回 Vector2

返回类型声明改为 `Variant`（兼容两种模式）。`simulate_right_click` 收到 Vector3 后，由 `selection_manager.gd` 负责处理（3D 迁移时一并处理）。

默认值 `"2d"` 保证 Phase 1 不传参时行为完全不变。

#### 3.3 `command_router.gd` — 新增 world_click 命令

**问题**：现有 `right_click` 命令接受屏幕坐标，在 3D 下需要 raycast 才能转换为世界坐标，但 CommandRouter 没有 Camera3D 引用。

**改动**：新增 `world_click` 命令，接受世界坐标 `[x, z]`，直接构造 `Vector3(x, 0, z)` 并调用 selection_manager 的 `simulate_right_click()`，绕过屏幕坐标和 raycast。

命令格式：
```
{ "cmd": "world_click", "pos": [x, z] }
{ "cmd": "world_click", "pos": {"x": x, "z": z} }
```

新增 `_parse_world_pos()` 辅助函数，与现有 `_parse_pos()` 并列。CommandRouter 需持有 `_sel_mgr` 引用，通过 `setup()` 传入（当前 setup 无参数，需扩展）。

#### 3.4 `game_world.gd` — 注册 Camera 并传递 coord_mode

**问题**：3D 迁移后 Camera2D 不存在，需改为 Camera3D；`action_executor` 需知道当前 coord_mode。

**改动**：
- 注册 Camera3D 为 sensor（group: `"camera"`，字段：`global_position`、`rotation`）
- 调用 `action_executor.setup()` 时传入 `coord_mode: "xz"`
- 向 CommandRouter 传入 `sel_mgr` 引用（通过 `game_world` 暴露或 bootstrap 中转）

---

## 4. 数据流对比

```
【当前 2D】
  config.test_actions → SimulatedPlayer → ActionExecutor
    _resolve_target("blue_spawn") → Vector2(2048, 832)
    sel_mgr.simulate_right_click(Vector2) → unit.move_to(Vector2)

【Route A 3D】
  config.test_actions → SimulatedPlayer → ActionExecutor (coord_mode="xz")
    _resolve_target("blue_spawn") → Vector3(2048, 0, 832)
    sel_mgr.simulate_right_click(Vector3) → unit.move_to(Vector3)

【TCP world_click】
  {"cmd":"world_click","pos":[2048,832]}
    → CommandRouter._parse_world_pos → Vector3(2048, 0, 832)
    → sel_mgr.simulate_right_click(Vector3)
```

---

## 5. 接口变更汇总

| 文件 | 变更前 | 变更后 |
|------|--------|--------|
| `formatter_engine.gd` | `Vector2(pos.x, pos.y)` 硬编码 | `_to_flat(pos)` 自动投影 |
| `action_executor.gd` | `setup(sel_box: Node2D, ...) ` | `setup(sel_box: Node, ..., coord_mode: String = "2d")` |
| `action_executor.gd` | `_resolve_target() -> Vector2` | `_resolve_target() -> Variant` |
| `command_router.gd` | `setup()` 无参数 | `setup(sel_mgr: Node = null)` |
| `command_router.gd` | 无 world_click 命令 | 新增 world_click |
| `game_world.gd` | Camera2D 查找 | 注册 Camera3D sensor |

---

## 6. 向后兼容保证

- `action_executor` 默认 `coord_mode="2d"`，Phase 1 headless 测试不受影响
- `command_router.setup()` 的 `sel_mgr` 参数默认 null，无 sel_mgr 时 `world_click` 返回错误而非崩溃
- `formatter_engine._to_flat()` 对 Vector2 输入行为与原代码完全一致
- headless 回归 10/11 PASS 目标不退步

---

## 7. 文件清单

改动文件（均在 `src/shared/ai-renderer/`）：
- `formatter_engine.gd`
- `action_executor.gd`
- `command_router.gd`

改动文件（`src/phase1-rts-mvp/scripts/`）：
- `game_world.gd`

新增文件：无
