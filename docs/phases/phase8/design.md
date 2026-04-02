# Phase 8 设计文档：窗口验证完整化

**定位**：让窗口模式具备与 headless 对等的自动化验证能力，专门覆盖"只有窗口才能初始化"的内容（Camera3D、Mesh、UI）。

> B 轴（感知层语义计算）已废弃。游戏局势理解通过现有 Formatter 语义 log 即可满足，不需要额外的 SituationAnalyzer。

---

## 1. 问题定义

Phase 7 完成后，窗口模式的验证缺口：

| 维度 | 现状 | 缺口 |
|------|------|------|
| 验证层（headless） | 11 个断言，3 个 scenario，全自动 PASS/FAIL | ✅ 已完整 |
| 验证层（窗口） | 只有定时截图（每 5 秒），无自动剧本 | 无法自动判断视觉/UI 正确性 |
| 事件截图 | 无 | 关键时刻无截图留证 |

---

## 2. 方案

### 新增组件

```
bootstrap（窗口模式）
  ├─ SimulatedPlayer（去掉 is_headless 限制，窗口也自动走剧本）
  ├─ WindowAssertionSetup（新建，注册窗口专属断言）
  └─ UXObserver（已有，补全事件驱动截图）
```

### 窗口断言清单（全部为结构/属性检查）

| 断言名 | 检查方式 | 可转 headless？ |
|--------|---------|----------------|
| `camera_orthographic` | `Camera3D.projection == PROJECTION_ORTHOGONAL` | ✅ 可（不依赖渲染） |
| `camera_covers_map` | `Camera3D.size >= map_height * 0.8` | ✅ 可 |
| `camera_centered` | `Camera3D.position` 在地图中央 ±300 内 | ✅ 可 |
| `units_have_mesh` | 至少一个单位有 `MeshInstance3D` 子节点 | ✅ 可（结构检查，visual 代码只在窗口跑） |
| `hq_has_mesh` | HQ_red 有 `MeshInstance3D` 子节点 | ✅ 可 |
| `no_initial_selection` | frame > 10 后 `selected_units` 为空 | ✅ 可 |
| `prod_panel_hidden_at_start` | frame > 10 后 `prod_panel.visible == false` | ✅ 可 |
| `prod_panel_shows_on_hq_click` | `hq_selected` 信号触发后 `panel.visible == true` | ✅ 可 |
| `bottom_bar_visible` | BottomBar 节点 `visible == true` | ✅ 可 |

> 所有断言均不依赖渲染画面，Phase 9 可评估迁移至 headless。

### 事件截图（过渡手段）

| 信号 | 截图目的 | 能否转断言 |
|------|---------|-----------|
| `prod_panel_shown` | 面板布局是否正确 | 部分可（visible 属性），视觉布局不行 |
| `selection_rect_drawn` | 框选视觉反馈 | ❌ 视觉高亮无法程序化，长期保留 |
| `battle_first_kill` | 战场位置和战斗效果 | 位置可，特效不行 |
| `game_over` | 结束画面 | 结束 UI visible 可程序化 |

---

## 3. 实现计划

| 子任务 | 影响文件 |
|--------|---------|
| A1：SimulatedPlayer 开放窗口模式 | `scripts/bootstrap.gd` |
| A2：新建 WindowAssertionSetup | `scripts/window_assertion_setup.gd`（新建） |
| A3：Bootstrap 窗口模式接入断言 | `scripts/bootstrap.gd` |
| A4：visual_check.json 完善 | `tests/scenarios/visual_check.json` |
| A5：验证 | 运行窗口模式 |

---

## 4. 完成标准

- [ ] 窗口模式有自动剧本（SimulatedPlayer）+ 程序化断言，输出 PASS/FAIL
- [ ] 9 个窗口断言全部 PASS
- [ ] 事件截图在关键信号时自动生成（screenshots/ 出现 `ux_prod_panel_shown_*` 等）
- [ ] headless 原有 11 个断言保持 PASS（改动不破坏现有验证）
- [ ] 所有截图有对应断言或标注"何时可转"

---

## 5. 不做的事（边界）

- ❌ 不做 SituationAnalyzer / snapshot v2 / 语义层计算（游戏局势理解靠现有 Formatter log）
- ❌ 不做多模态模型集成
- ❌ 不做 Phase 4 游戏功能
