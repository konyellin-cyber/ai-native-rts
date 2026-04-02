# Phase 12 — 窗口测试自动化 Checklist

**目标**：用 `Input.parse_input_event()` 注入真实鼠标事件，断言验证框选/点选等鼠标交互，将窗口断言从「状态快照」扩展到「行为验证」。

---

### 子阶段 12A：基础设施

- [x] **12A.1** `tools/ai-renderer/action_executor.gd`：`setup()` 增加 `viewport: Viewport` 可选参数（默认 null）
- [x] **12A.2** `action_executor.gd`：实现坐标转换辅助函数 `_canvas_to_viewport(canvas_pos: Vector2) -> Vector2`，使用 `viewport.canvas_transform.origin`
- [x] **12A.3** `action_executor.gd`：实现 `real_drag` 动作：`warp_mouse` → 注入 LEFT press → 注入 MouseMotion（可选）→ 注入 LEFT release
- [x] **12A.4** `action_executor.gd`：实现 `real_click` 动作：`warp_mouse` → 注入 LEFT press → 注入 LEFT release

---

### 子阶段 12B：断言注册

- [x] **12B.1** `scripts/window_assertion_setup.gd`：注册 `real_drag_selects_units` 断言（`sel_mgr.selected_units.size() > 0`，等 2 帧后检查）
- [x] **12B.2** `scripts/window_assertion_setup.gd`：注册 `real_drag_selects_correct_count` 断言（`selected_units.size() == expected_count`，期望值从 config 读）
- [x] **12B.3** `scripts/window_assertion_setup.gd`：注册 `real_click_selects_unit` 断言（`selected_units.size() == 1`，等 2 帧后检查）

---

### 子阶段 12C：剧本配置

- [x] **12C.1** 新建 `tests/scenarios/window_interaction.json`：包含 wait → real_drag → wait → real_click → wait 动作序列
- [x] **12C.2** `scripts/bootstrap.gd`（或 renderer setup 处）：窗口模式加载 `window_interaction.json` 剧本，传 `viewport` 给 action_executor

---

### 子阶段 12D：集成验证

- [x] **12D.1** 验证 `Input.parse_input_event()` 更新 `get_global_mouse_position()` 行为（实验性探查，必要时改用 `warp_mouse` 预置坐标）— 结论：`action_executor._inject_drag/click` 已采用 `warp_mouse` 预置视口坐标方案；`selection_box._input()` 用 `get_global_mouse_position()` 读画布坐标，Godot 内部通过 `canvas_transform` 自动逆变换，路径正确，无需额外修改
- [x] **12D.2** headless 全回归：7/7 PASS，interaction 3/3 PASS（确保新改动无副作用）— 已验证 2026-04-02
- [x] **12D.3** 窗口断言扩展验证：16/16 PASS（原 13 条 + 新 3 条鼠标交互断言）— 已验证 2026-04-02
- [x] **12D.4** `FILES.md` 更新：记录所有改动文件
- [x] **12D.5** `roadmap.md` 更新：Phase 12 行标记 ✅ 完成 — 已更新 2026-04-02

---

### 遗留 / 下阶段

- [ ] AI 对手生产 Archer → Phase 13
- [ ] `base_unit.gd` 抽取公共逻辑（fighter / archer 共有的 `_knockback`、`take_damage_from`、`_hit_flash` 等）→ Phase 13 前完成

---

_创建：2026-04-02_
