# UI 设计索引

> 本目录收录游戏所有 UI 组件的设计规范与交互定义。
> **断言以本目录文档为准**：窗口断言（`window_assertion_setup.gd`）实现须对照各组件文档的「断言验收」段落。

---

## 组件文档

| 文件 | 组件 | 实现脚本 | 状态 |
|------|------|---------|------|
| [layout.md](layout.md) | 整体布局与设计原则 | — | ✅ |
| [bottom-bar.md](bottom-bar.md) | 底部状态栏 (BottomBar) | `ui/bottom_bar.gd` | ✅ |
| [prod-panel.md](prod-panel.md) | 生产面板 (ProdPanel) | `ui/prod_panel.gd` | ✅ |
| [selection.md](selection.md) | 框选与选中高亮 | `selection_box.gd` / `selection_manager.gd` | ✅ |
| [health-bar.md](health-bar.md) | 单位血条 | `fighter.gd` / `worker.gd` 内联 | ✅ |
| [game-over.md](game-over.md) | 游戏结束画面 | `ui/game_over_ui.gd` | ✅ |

---

## 断言覆盖矩阵

| 断言名 | 文档来源 | 验收标准摘要 |
|--------|---------|------------|
| `bottom_bar_visible` | [bottom-bar.md](bottom-bar.md) | BottomBar 节点始终可见 |
| `no_initial_selection` | [selection.md](selection.md) | 游戏启动后 10 帧内无选中单位 |
| `prod_panel_hidden_at_start` | [prod-panel.md](prod-panel.md) | 启动时面板隐藏 |
| `prod_panel_shows_on_hq_click` | [prod-panel.md](prod-panel.md) | 选中 HQ 后面板弹出 |
| `prod_panel_hides_on_click_outside` | [prod-panel.md](prod-panel.md) | 点击面板外部（含移动命令）后面板关闭 |
| `prod_panel_has_progress_bar` | [prod-panel.md](prod-panel.md) | 面板节点树中存在 ProgressBar |
| `prod_panel_position_near_hq` | [prod-panel.md](prod-panel.md) | 面板中心距 HQ 屏幕坐标 ≤ 300px |
| `units_have_mesh` | [selection.md](selection.md) | 至少一个单位有 MeshInstance3D |
| `hq_has_mesh` | [bottom-bar.md](bottom-bar.md) | HQ_red 有 MeshInstance3D |

---

## 维护规则

- **新增 UI 组件** → 在本目录新建对应 `.md`，在 INDEX.md 表格中登记，在 `window_assertion_setup.gd` 补断言
- **修改交互行为** → 先改文档，再改代码，再补/改断言，保持三者同步
- **断言 FAIL** → 以本目录文档为准判断是代码 bug 还是设计变更
