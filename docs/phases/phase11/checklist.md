# Phase 11 — 弓箭手接入主游戏 Checklist

**目标**：将 Phase 10 验证的 Archer 兵种接入完整主游戏流程，玩家可通过 HQ 生产面板生产弓箭手，并建立完整的程序化断言验证。

---

### 子阶段 11A：配置与核心逻辑

- [x] **11A.1** `config.json`：`production` 段添加 `archer_cost: 125`、`archer_time: 4`
- [x] **11A.2** `scripts/bootstrap.gd`：`_on_produce_requested()` 通用化，改为按 `unit_type + "_cost"` / `"_time"` 动态查 config，支持任意新单位类型无需改动 bootstrap
- [x] **11A.3** `scripts/bootstrap.gd`：`_update_ui()` 更新 `prod_panel.update_state()` 调用，传入 `archer_cost`
- [x] **11A.4** `scripts/game_world.gd`：`spawn_unit()` 增加 archer 分支，对 archer 调用 8 参数 setup（含 `arrow_manager` 引用）

---

### 子阶段 11B：UI 更新

- [x] **11B.1** `scripts/ui/prod_panel.gd`：添加 `_archer_btn`、`_archer_info` 成员变量 + `can_produce_archer` 状态
- [x] **11B.2** `_build_ui()`：在 Fighter 行后添加 Archer 行（「🏹 Archer」按钮 + 「💎 125  ⏱ 4s」标签）
- [x] **11B.3** `update_state()` 签名扩展：增加 `archer_cost: int = 125` 参数，更新 `can_produce_archer` 状态
- [x] **11B.4** `_update_visuals()`：更新 `_archer_btn.disabled`、`_archer_info.text` 显示

---

### 子阶段 11C：断言验证体系

- [x] **11C.1** `scripts/unit_lifecycle_manager.gd`：新增 `archer_produced: bool` 只读属性，在 `on_unit_produced("archer","red")` 时置 true
- [x] **11C.2** `scripts/assertion_setup.gd`：注册 `archer_produced` headless 断言
- [x] **11C.3** `tools/ai-renderer/action_executor.gd`：`click_button` 分支改为通用列表匹配（`known_units = ["Worker","Fighter","Archer"]`），支持 Archer 按钮模拟点击
- [x] **11C.4** `tests/scenarios/interaction.json`：剧本增加 Archer 生产动作（等 Worker 产完后再点 Archer 按钮）；断言列表添加 `archer_produced`
- [x] **11C.5** `scripts/window_assertion_setup.gd`：注册 `prod_panel_has_archer_button` 窗口断言（检查 prod_panel 含"Archer"文本的 Button）

---

### 子阶段 11D：集成验证

- [x] **11D.1** headless 全回归：7/7 PASS，interaction 从 pass=2 → pass=3（含 `archer_produced`），耗时约 88 秒
- [ ] **11D.2** 窗口模式目视验证（待完成）：
  - 生产面板显示三个按钮（Worker / Fighter / Archer）
  - 点击「🏹 Archer」，扣 125 晶体，4 秒后 Archer 单位出现
  - Archer 正常执行 wander/chase/shoot/kite 状态机
- [x] **11D.3** `FILES.md` 更新：记录所有改动文件
- [x] **11D.4** `roadmap.md` 更新：Phase 11 行已添加

---

### 遗留 / 下阶段

- [ ] AI 对手生产 Archer → Phase 12
- [ ] `base_unit.gd` 抽取公共逻辑（fighter / archer 共有的 `_knockback`、`take_damage_from`、`_hit_flash` 等）→ Phase 12 前完成

---

_创建：2026-03-29 | 最后更新：2026-03-30_
