# Phase 10 — 弓箭手兵种 + 独立测试场景 Checklist

**目标**：新增 Archer 兵种（真实弹道 + kite 行为），重构测试架构为独立场景模式

**设计文档**：`docs/phases/phase10/design.md`

---

### 子阶段 10A：测试架构重构（独立场景模式）

**目标**：建立可复用的独立场景测试框架，所有后续测试场景均采用此模式。

- [x] **10A.1** 设计独立场景接口规范：`CombatBootstrap` 作为战斗场景公共基类，职责：读 config.json → 生成单位 → 初始化 Calibrator → 帧驱动 → `_finish()` 回调
- [x] **10A.2** 实现 `tests/scenes/combat_bootstrap.gd`（支持 fighter / archer 类型，内置 ArrowManager，窗口模式自动建立等距相机+光照+地面）
- [x] **10A.3** `test_runner.gd`：新增 `.tscn` 加载分支（按路径后缀分发），场景名从路径末段提取
- [x] **10A.4** 创建 `tests/scenes/smoke_test/`（2 个 Fighter 互殴，断言 `battle_resolution`），跑通完整链路
- [x] **10A.5** 验证：3 个 .json 场景 + smoke_test 共 4 个全部 PASS

---

### 子阶段 10B：Arrow 弹道系统

**目标**：实现箭矢的抛物线飞行、穿透命中、障碍物阻挡、插身视觉。

- [x] **10B.1** 实现 `scripts/arrow.gd`：
  - 抛物线弹道（初速度含仰角，每帧叠加重力）
  - 穿透命中检测（XZ 水平距离 + Y 高度范围双重判定，`_hit_targets` 去重）
  - 障碍物 AABB 检测（`global_position` XZ 平面）
  - headless/窗口分离（只有 MeshInstance3D 有条件分支）
  - 命中插身：停止飞行，锁定到目标身上 3 秒后消失
  - 命中爆点：橙红色发光球体 0.12 秒
  - 最旧箭矢淘汰：`ArrowManager` 超过 40 支时 `queue_free` 最旧
- [x] **10B.2** 实现 `scripts/arrow_manager.gd`：统一管理生命周期，`fire(origin, velocity, damage, max_range, owner_team)` 接口
- [x] **10B.3** `game_world.gd`：`build()` 中初始化 ArrowManager，挂到场景树
- [x] **10B.4** 战斗场景验证（archer_vs_fighter 7/7 PASS）

---

### 子阶段 10C：Archer 兵种

**目标**：实现 Archer 状态机（wander / chase / shoot / kite / dead）。

- [x] **10C.1** 实现 `scripts/archer.gd`：
  - 状态机：idle → wander → chase → shoot → kite → dead
  - shoot：原地射击，冷却到期调用 `ArrowManager.fire()`，计算抛物线初速度（含仰角）
  - kite：每帧直接设 `velocity`（不依赖目标点，防止到达后停止），边界反弹，边跑边射
- [x] **10C.2** kite hysteresis：进入 kite 条件 `dist < flee_range`，退出条件 `dist >= flee_range * 1.5`
- [x] **10C.3** `config.json`：新增 `archer` 配置段（hp/speed/attack_damage/shoot_range/flee_range/sight_range/attack_cooldown/arrow_speed/radius）
- [x] **10C.4** `CombatBootstrap` 支持 `archer` 类型单位，注入 arrow_manager 引用
- [x] **10C.5** 受击反馈：受击白闪（`_body_mat` 瞬间变白）+ 击退冲量（`take_damage_from` 接口）

---

### 子阶段 10D：战斗专项测试场景

**目标**：三个独立战斗场景，分别验证不同战斗行为。

- [x] **10D.1** 创建 `tests/scenes/archer_vs_fighter/`：1 Archer(red) vs 1 Fighter(blue)，断言 `battle_resolution`
- [x] **10D.2** 创建 `tests/scenes/archer_vs_archer/`：1 Archer(red) vs 1 Archer(blue)，断言 `battle_resolution`
- [x] **10D.3** 创建 `tests/scenes/kite_behavior/`：1 Archer(red) vs 1 Fighter(blue) 近距放置，断言 `archer_kite`；子类 bootstrap 覆盖 `_register_assertions()`
- [x] **10D.4** `test_runner.gd` SCENARIO_FILES 新增三个场景路径（共 7 个场景）
- [x] **10D.5** 断言实现：`archer_kite`（Archer ai_state == "kite"），`battle_resolution`（has kills）

---

### 子阶段 10E：集成验证

- [x] **10E.1** headless 全回归：7/7 PASS（economy×6 / combat×3 / interaction×2 / smoke_test×1 / archer_vs_fighter×1 / archer_vs_archer×1 / kite_behavior×1），耗时约 62 秒
- [x] **10E.2** 窗口模式目视验证：
  - 箭矢抛物线飞行可见（明黄色胶囊体，方向随速度倾斜）
  - 命中橙红爆点、受击白闪、击退位移、箭插身 3 秒消失
  - 弓箭手 kite 后撤行为可观察
- [x] **10E.3** `FILES.md` 更新：新增文件条目
- [x] **10E.4** `roadmap.md` 更新：Phase 10 状态改为 ✅ 完成

---

### 遗留 / 下阶段

- [ ] `base_unit.gd` 抽取：将 fighter / archer / worker 公共逻辑（`_knockback`、`take_damage_from`、`_detect_nav`、`_move_along_path`、`_hit_flash`）抽到基类，减少重复（Phase 11 前完成）
- [ ] Archer 接入玩家生产系统（HQ 队列 + UI 按钮）→ Phase 11
- [ ] AI 对手生产 Archer → Phase 11

---

_创建：2026-03-29 | 最后更新：2026-03-29_
