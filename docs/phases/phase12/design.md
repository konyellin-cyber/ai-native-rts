# Phase 12 设计文档：窗口测试自动化

> **适用阶段**：Phase 12
> **写于**：2026-04-02
> **背景**：Phase 11 完成了 13/13 窗口断言的程序化验证，但这些断言均为「状态快照」型（读属性、检查节点结构）。鼠标操作（框选、点选单位）仍无法通过断言验证——`simulate_drag()` / `simulate_right_click()` 是直接调用内部方法，绕过了 Godot 输入管线，无法测试 `_input()` / `_unhandled_input()` 完整链路。
>
> Phase 12 目标：用 `Input.parse_input_event()` 注入**真实** InputEvent，驱动框选和点选走完完整输入管线，并通过窗口断言验证结果。

---

## 1. 目标

1. 实现 `real_drag` 动作类型：通过 `Input.parse_input_event()` 注入 `InputEventMouseButton` + `InputEventMouseMotion`，触发 `selection_box.gd` 的完整拖拽逻辑
2. 实现 `real_click` 动作类型：注入左键点击序列，触发 `selection_manager.gd` 的 `_try_select_unit_at_screen()`
3. 新增三条窗口断言：
   - `real_drag_selects_units`：真实拖拽后 `selection_manager.selected_units.size() > 0`
   - `real_drag_selects_correct_count`：拖拽范围内单位数与断言期望值匹配
   - `real_click_selects_unit`：真实单击后恰好选中 1 个单位
4. 原有 `simulate_drag` / `simulate_right_click` 路径**保留不动**，两套机制并存（旧路径用于 headless，新路径专属窗口断言）

不在本次范围内：

- 注入键盘事件
- 修改 headless 测试流程
- AI 对手逻辑（Phase 13）

---

## 2. 技术方案

### 2.1 核心机制：`Input.parse_input_event()`

Godot 4 提供 `Input.parse_input_event(event: InputEvent)` 方法，将任意 InputEvent 注入引擎输入管线，行为与真实硬件输入等价：

- 走完 `_input()` → `_unhandled_input()` 完整链路
- `set_input_as_handled()` 同样生效（面板内点击不会触发 click_missed）
- 与 `_InputEvent` autoload 系统兼容

### 2.2 坐标转换

`selection_box.gd` 和 `selection_manager.gd` 读取 `get_global_mouse_position()`（画布坐标），而 `Input.parse_input_event()` 注入的 `InputEventMouseButton.position` 应为**视口坐标（viewport 像素坐标）**：

```
视口坐标 = 画布坐标 + canvas_transform.origin
```

`action_executor.gd` 在注入前需执行此转换。`canvas_transform.origin` 通过 `get_viewport().canvas_transform.origin` 获取（需传入 `viewport` 引用，或在 `setup()` 时缓存）。

### 2.3 真实拖拽事件序列

一次完整框选需注入以下事件序列（均为视口坐标）：

```
1. InputEventMouseButton (button_index=LEFT, pressed=true,  position=start_vp)
2. InputEventMouseMotion (position=mid1_vp,  relative=mid1-start)
3. InputEventMouseMotion (position=mid2_vp,  relative=mid2-mid1)
   … (可选，增加运动平滑感)
4. InputEventMouseButton (button_index=LEFT, pressed=false, position=end_vp)
```

Motion 事件数量影响 `_is_dragging` 期间的视觉更新，但逻辑判断只依赖 press/release。

**风险点**：`get_global_mouse_position()` 从引擎内部鼠标状态读取，`Input.parse_input_event()` 是否更新该状态未确认。若不更新，`selection_box.gd` 的 `_drag_start = get_global_mouse_position()` 会读到错误值。

**预案**：先在 press 事件注入前调用 `get_viewport().warp_mouse(start_vp)`，强制更新引擎鼠标位置，再注入事件序列。

### 2.4 真实点击事件序列

```
1. InputEventMouseButton (button_index=LEFT, pressed=true,  position=pos_vp)
2. InputEventMouseButton (button_index=LEFT, pressed=false, position=pos_vp)
```

`selection_manager.gd` 的 `_unhandled_input()` 在 release 时检查 `_left_click_pos.distance_to(release_pos) < 5.0` 并调用 `_try_select_unit_at_screen()`。注入的两次事件 position 完全相同，distance=0，满足条件。

### 2.5 单位坐标到视口坐标转换

断言触发前需知道「单位在屏幕上的位置」以确定点击坐标。转换链：

```
单位 global_position (Vector3, 世界坐标)
  → camera.unproject_position(global_position)  → 视口像素坐标 (Vector2)
```

`warp_mouse()` 使用视口像素坐标；`parse_input_event()` 注入的 position 也用视口像素坐标。

---

## 3. 架构变更

### 3.1 `tools/ai-renderer/action_executor.gd`

新增两个动作类型：

| 动作 | 参数 | 行为 |
|------|------|------|
| `real_drag` | `from: Vector2`, `to: Vector2`（画布坐标） | 转换为视口坐标 → `warp_mouse` → 注入 press + motion + release |
| `real_click` | `pos: Vector2`（画布坐标，或 `unit_type` + `team` 自动查找） | 转换 → `warp_mouse` → 注入 press + release |

`setup()` 新增 `viewport: Viewport` 参数，用于获取 `canvas_transform.origin` 和调用 `warp_mouse()`。

### 3.2 `scripts/window_assertion_setup.gd`

新增三条断言注册（使用 `AsserterRegistry.register_window_assertion()`）：

| 断言 ID | 检查逻辑 | 触发时机 |
|---------|---------|---------|
| `real_drag_selects_units` | `sel_mgr.selected_units.size() > 0` | real_drag 动作执行后等 2 帧 |
| `real_drag_selects_correct_count` | `sel_mgr.selected_units.size() == expected_count`（从 config 读） | 同上 |
| `real_click_selects_unit` | `sel_mgr.selected_units.size() == 1` | real_click 动作执行后等 2 帧 |

断言等待帧数通过 `_check_after_frames` 机制实现（与现有 `prod_panel_shows_on_hq_click` 等延迟断言相同模式）。

### 3.3 `tests/scenarios/window_interaction.json`（新文件）

专为窗口断言设计的交互剧本，区别于 `interaction.json`（headless）：

```
动作序列：
1. wait 60 帧（等游戏初始化稳定）
2. real_drag（从地图左上区域拖到右下，覆盖已知单位生成区域）
3. wait 5 帧
4. 验证 real_drag_selects_units（PASS）
5. real_click（点选 red 队 Fighter 的屏幕投影坐标）
6. wait 5 帧
7. 验证 real_click_selects_unit（PASS）
```

---

## 4. 文件变更清单

| 文件 | 类型 | 变更说明 |
|------|------|---------|
| `tools/ai-renderer/action_executor.gd` | 修改 | 新增 `real_drag` / `real_click` 动作，`setup()` 增加 `viewport` 参数 |
| `scripts/window_assertion_setup.gd` | 修改 | 注册 3 条新断言 |
| `tests/scenarios/window_interaction.json` | 新增 | 窗口专属交互剧本 |
| `scripts/bootstrap.gd` | 可能修改 | 若需传 `viewport` 给 `action_executor`，在 `_setup_renderer()` 处补充 |
| `docs/phases/phase12/design.md` | 新增 | 本文件 |
| `docs/phases/phase12/checklist.md` | 新增 | Phase 12 执行 checklist |

---

## 5. 暗坑预警

| 风险 | 等级 | 预案 |
|------|------|------|
| `Input.parse_input_event()` 不更新 `get_global_mouse_position()` | 🔴 阻塞 | 每次注入前调用 `get_viewport().warp_mouse(pos_vp)` 强制同步 |
| 窗口模式 canvas_transform.origin 值随窗口尺寸变化 | 🟡 逻辑错误 | 每次使用时实时读取，不在 setup() 时缓存 |
| `InputEventMouseMotion.relative` 计算错误导致拖拽路径异常 | 🟡 逻辑错误 | 只注入 press + release，motion 事件可选；selection_box 只依赖 release 位置 |
| 注入事件顺序与引擎帧处理时序不同步 | 🟡 逻辑错误 | 在同一个 `_physics_process` 帧内顺序注入所有事件（不跨帧），或使用 `call_deferred` 逐帧注入 |
| `_headless = false` 但无渲染窗口时 `get_global_mouse_position()` 返回零 | 🟢 小问题 | Phase 12 仅在窗口模式运行，此场景不适用 |

---

## 6. 验证标准

- **headless 回归不受影响**：7/7 PASS，interaction 3/3 PASS
- **窗口断言扩展**：原 13/13 → 16/16 PASS（新增 3 条鼠标交互断言）
- **早退行为正确**：所有断言通过后立即退出，不等待 total_frames

---

_创建：2026-04-02_
