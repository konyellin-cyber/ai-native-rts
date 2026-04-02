# Phase 13 — 测试体系重构 Checklist

**目标**：统一测试单元规范，迁移并删除 JSON 注入模式，建立场景登记表硬约束，完成测试架构文档化。

**前置依赖**：
- Phase 12 全部完成（窗口断言 16/16 PASS）
- `base_unit.gd` 抽取公共逻辑（Phase 12 遗留项，必须先完成）

**设计参考**：[测试架构设计文档](../../design/tech/test-architecture.md)

---

### 子阶段 13A：前置清理（Phase 12 遗留）

- [ ] **13A.1** `scripts/base_unit.gd`：抽取 Fighter / Archer 共有逻辑（`_knockback`、`take_damage_from`、`_hit_flash`）到基类
- [ ] **13A.2** `scripts/fighter.gd`、`scripts/archer.gd`：改为继承 `BaseUnit`，删除重复代码
- [ ] **13A.3** headless 全回归：确认抽取后 11/11 PASS，无回归

---

### 子阶段 13B：迁移 JSON 注入场景

将现有三个 JSON 注入场景迁移为标准测试单元（`.tscn` + `scenario.json` 成对）。

- [ ] **13B.1** 新建 `tests/scenes/economy/`：创建 `scene.tscn`、`scenario.json`、`bootstrap.gd`，覆盖原 `economy.json` 的全部断言（6 个）
- [ ] **13B.2** 新建 `tests/scenes/combat/`：创建 `scene.tscn`、`scenario.json`、`bootstrap.gd`，覆盖原 `combat.json` 的全部断言，`scenario.json` 声明 `"covers": ["combat"]`
- [ ] **13B.3** 新建 `tests/scenes/interaction/`：创建 `scene.tscn`、`scenario.json`、`bootstrap.gd`，覆盖原 `interaction.json` 的全部断言，`scenario.json` 声明 `"covers": ["interaction"]`
- [ ] **13B.4** 三个新场景分别通过 headless 验证，断言全部 PASS

---

### 子阶段 13C：删除 JSON 注入模式

- [ ] **13C.1** `tests/test_runner.gd`：将 `SCENARIO_FILES` 中的三个 `.json` 条目替换为对应的新 `.tscn` 路径
- [ ] **13C.2** `tests/test_runner.gd`：删除 JSON 注入加载分支（`entry.ends_with(".json")` 的代码路径）
- [ ] **13C.3** 删除旧 JSON 文件：`tests/scenarios/economy.json`、`combat.json`、`interaction.json`
- [ ] **13C.4** 全量回归：确认所有场景 PASS，JSON 注入逻辑彻底退出

---

### 子阶段 13D：场景登记表机制强化

- [ ] **13D.1** `tests/test_runner.gd`：将 `SCENARIO_FILES` 硬编码列表提取为外部配置文件 `tests/scene_registry.json`，test_runner 从文件读取
- [ ] **13D.2** `scene_registry.json` 包含每个场景的元信息：`name`、`path`、`window_mode`、`phase`、`covers`（可选）
- [ ] **13D.3** `tests/test_runner.gd`：按 `window_mode` 字段自动分组，Headless 场景和 Window 场景分别输出汇总
- [ ] **13D.4** 全量回归验证登记表机制正常工作：Headless 全部 PASS，Window 场景标记正确

---

### 子阶段 13E：文档与规范收尾

- [ ] **13E.1** `docs/design/tech/test-architecture.md`：核对第 7 节「已登记场景清单」，与 `scene_registry.json` 保持一致
- [ ] **13E.2** `docs/rules/dev-rules.md`：确认 6.3 节测试单元规范与实际实现对齐，有偏差则更新
- [ ] **13E.3** `CLAUDE.md`（项目级）：更新 Headless 验证三档入口表格，补充 Window 场景运行入口
- [ ] **13E.4** `src/phase1-rts-mvp/FILES.md`：更新受影响文件条目（test_runner.gd、assertion_setup.gd 等）
- [ ] **13E.5** `docs/phases/roadmap.md`：Phase 13 行标记 ✅ 完成

---

### 验收标准

- 所有测试单元均为 `.tscn` + `scenario.json` 成对形式，不存在孤立 JSON
- `test_runner.gd` 中不存在 JSON 注入加载逻辑
- `scene_registry.json` 是唯一权威场景登记表
- 全量回归（Headless）全部 PASS
- 测试架构设计文档与代码实现一致

---

_创建：2026-04-02_
