# Phase 10 设计文档：弓箭手兵种 + 独立测试场景

> **适用阶段**：Phase 10
> **写于**：2026-03-29
> **背景**：Phase 9 完成等距视角后，游戏只有一种战斗单位（Fighter，近战）。Phase 10 引入第二种兵种——Archer（远程弓箭手），实现真实飞行弹道，并重构测试架构为「每个场景独立 .tscn + .gd」。

---

## 1. 目标

1. 新增 **Archer** 兵种：纯远程，真实飞行弹道，kite 行为（近身后撤）
2. 新增 **Arrow** 弹道节点：真实飞行，穿透，被障碍物阻挡
3. 重构测试架构：每个测试场景自成一体（独立 .tscn + bootstrap），不再复用主游戏 main.tscn
4. 新增战斗专项测试场景：最小地图上直接放置指定兵种，验证战斗逻辑

不在本次范围内：

- Archer 的视觉特效（弓、拉弦动画）——只做箭矢飞行 Mesh
- 多种 Archer 变种（暂只实现基础版）
- Archer 接入玩家生产系统（UI 按钮 + HQ 生产队列）——留 Phase 11；本阶段 Archer 只通过独立测试场景创建，不走主游戏生产流程
- AI 对手生产 Archer（AI 逻辑调整留 Phase 11）

---

## 2. Archer 兵种设计

### 2.1 核心参数

| 参数 | 值 | 说明 |
|------|----|------|
| `hp` | 70 | 比 Fighter(100) 脆，需保持距离 |
| `speed` | 130 | 比 Fighter(150) 慢，但 kite 时速度 +30% |
| `attack_damage` | 15 | 单发比近战(10)高，补偿射速慢 |
| `attack_range` | 160 | 最大射程，大于 preferred_range 留宽容带 |
| `preferred_range` | 150 | 理想射击距离，尽量维持在此距离 |
| `min_range` | 80 | 低于此距离触发后撤 |
| `sight_range` | 250 | 比 Fighter(200) 稍远，先发现先射 |
| `attack_cooldown` | 1.2 | 射速慢于近战(0.5)，节奏感更强 |
| `kite_speed_mult` | 1.3 | 后撤时速度乘数 |

### 2.2 状态机

Archer 在 Fighter 状态机（idle / wander / chase / attack / dead）基础上新增两个状态：

```
idle
  │ 自动
  ▼
wander ◄──────────────────────────────────────────────┐
  │ 发现敌人 dist <= sight_range                        │
  ▼                                                    │
chase ──► 进入理想射程(dist <= attack_range)            │
  │                                                    │
  ▼                                                    │
shoot ──► 冷却结束 → 发射 Arrow                        │
  │                                                    │
  │ 敌人太近 dist < min_range                          │
  ▼                                                    │
kite（后撤） ──► 拉开距离至 preferred_range 后回 shoot  │
  │                                                    │
  │ 敌人死亡 / 超出 sight_range * 1.5                  │
  └───────────────────────────────────────────────────►┘
```

**chase 与 Fighter 的区别**：
- Fighter 的 chase 目标是进入 `attack_range(30)` 贴身
- Archer 的 chase 目标是进入 `attack_range(160)` 但不低于 `min_range(80)`

**kite 逻辑**：
- 方向 = `global_position - target.global_position`（背向目标）
- 速度 = `speed * kite_speed_mult`
- 退到 `preferred_range` 后切回 shoot
- kite 时不绕路，直接直线后撤（忽略导航，避免 kite 时卡障碍物）

### 2.3 attack_range 说明

Archer 的 `attack_range` 是**最大射程**，不是贴身距离：

- `dist > attack_range` → chase（接近）
- `min_range <= dist <= attack_range` → shoot（射击）
- `dist < min_range` → kite（后撤）

---

## 3. Arrow 弹道设计

### 3.1 节点结构

```
Arrow (Node3D)
  ├── CollisionShape3D（细长胶囊，沿飞行方向对齐）
  └── MeshInstance3D（细长圆柱，窗口模式创建，headless 不创建）
```

Arrow 由 `ArrowManager`（bootstrap 持有的 Node）统一管理生命周期，不直接 add_child 到场景树根节点。

### 3.2 飞行逻辑

每物理帧：

1. 沿 `direction * speed * delta` 移动
2. 飞行距离累计超过 `max_range`（= Archer 的 `attack_range`）→ 销毁
3. **障碍物检测**：对 config 中的 obstacles AABB 做射线-矩形检测，命中则销毁
4. **单位检测**：对敌方单位做距离检测（半径 = 单位 radius），命中则：
   - 调用 `unit.take_damage(damage)`
   - 将命中单位加入 `_hit_targets`（同一箭不重复打同一目标）
   - **穿透**：继续飞行，不销毁

### 3.3 参数

| 参数 | 值 | 说明 |
|------|----|------|
| `arrow_speed` | 600 | 约 4 倍 Archer 移动速度，飞行时间感知明显 |
| `max_range` | 与发射者 `attack_range` 相同 | 超出则消失 |
| `arrow_radius` | 5 | 命中检测半径（比单位 radius 小，需要比较准才命中） |

### 3.4 headless 处理

Arrow 的飞行逻辑在 headless 和窗口模式下**完全一致**——弹道计算和碰撞检测始终运行。只有 `MeshInstance3D` 的创建有条件分支：

```gdscript
func setup(headless: bool, ...) -> void:
    ...
    if not headless:
        _add_visual()
```

这是唯一的 headless 分支，符合「逻辑与渲染分离」原则。

---

## 4. 测试架构重构

### 4.1 现有问题

现有所有 headless 场景共用 `main.tscn` + `bootstrap.gd`，通过 `config.json` 的 `scenario_file` 字段注入场景参数。随着战斗逻辑变复杂（弹道、多兵种），bootstrap 会越来越臃肿，且「两个战士互殴」这种最小化测试需要创建完整的地图/经济/AI 对手，成本过高。

### 4.2 新架构定位

**独立场景模式是后续所有测试的标准模式**。从 Phase 10 起，新增测试场景均采用独立 .tscn + 专属 bootstrap，不再向主游戏 bootstrap.gd 堆砌分支。

现有 .json 场景（economy / combat / interaction）保留不变，作为全游戏集成回归测试。两种模式并存：

| 模式 | 适用场景 | 路径 |
|------|---------|------|
| .json 注入模式（现有）| 全游戏集成回归 | `tests/scenarios/*.json` → `main.tscn` |
| 独立 .tscn 模式（新）| 单一机制专项验证 | `tests/scenes/*/scene.tscn` → 专属 bootstrap |

**长期目标：现有 .json 场景也逐步迁移**

现有的 economy / combat / interaction 三个 .json 场景目前跑在完整的主游戏 bootstrap 上，验证的是集成行为。长期来看，每一个断言背后的机制都应该有对应的独立专项场景来覆盖：

| 现有断言 | 对应独立场景（待建） |
|---------|-----------------|
| `worker_cycle` / `economy_positive` | `economy_worker_cycle/` |
| `ai_economy` / `ai_produces` | `economy_ai_cycle/` |
| `battle_resolution` | `combat_fighter_vs_fighter/` （smoke_test） |
| `interaction_chain` | `interaction_select_move/` |
| `behavior_health` | 合并到各专项场景 |

迁移节奏：**不强制一次性迁移**，随功能扩展逐步补充。.json 集成场景继续保留作为最终回归兜底。

每个测试场景自成一体：

```
tests/
  scenes/
    combat_archer_vs_fighter/      ← 弓箭手 vs 近战
      scene.tscn                   ← 只挂 TestBootstrap 脚本
      bootstrap.gd                 ← 场景专属 bootstrap
      config.json                  ← 单位配置 + 断言配置
    combat_archer_vs_archer/       ← 弓箭手镜像对战
      ...
    combat_kite_behavior/          ← 验证 kite 后撤行为
      ...
```

**场景专属 bootstrap 职责**：
- 读取本场景 `config.json`（相对路径）
- 按配置创建指定单位（无地图、无经济、无 AI 对手）
- 初始化 Calibrator + 帧驱动
- early exit 或超时后退出，回调 TestRunner

**最小地图**：战斗测试场景使用固定的 500×500 平坦地图，无障碍物，无矿点，无导航网格（单位直线移动）。

### 4.3 场景配置格式

```json
{
  "name": "combat_archer_vs_fighter",
  "description": "1 Archer(red) vs 1 Fighter(blue)，验证弓箭手远程击杀近战单位",
  "map": { "width": 500, "height": 500 },
  "units": [
    { "type": "archer", "team": "red", "x": 100, "z": 250 },
    { "type": "fighter", "team": "blue", "x": 400, "z": 250 }
  ],
  "assertions": ["battle_resolution", "archer_kite"],
  "physics": { "fps": 60, "total_frames": 7200 }
}
```

### 4.4 TestRunner 扩展

`test_runner.gd` 新增对独立 `.tscn` 场景的支持：

```gdscript
## 混合场景列表：支持 .json（现有模式）和独立 .tscn（新模式）
const SCENARIO_FILES: Array[String] = [
    "economy.json",
    "combat.json",
    "interaction.json",
    # Phase 10 新增
    "res://tests/scenes/combat_archer_vs_fighter/scene.tscn",
    "res://tests/scenes/combat_archer_vs_archer/scene.tscn",
    "res://tests/scenes/combat_kite_behavior/scene.tscn",
]
```

加载逻辑按路径后缀分发：`.json` 走现有的 `_inject_scenario()` 路径，`.tscn` 直接 instantiate。

---

## 5. 新增断言

| 断言名 | 验收标准 | 所在场景 |
|--------|---------|---------|
| `archer_kite` | 战斗中 Archer 的 ai_state 出现过 `"kite"`（后撤行为触发） | combat_kite_behavior |
| `arrow_hits_target` | 战斗结束时敌方单位受到了伤害（HP < max_hp） | combat_archer_vs_fighter |
| `archer_wins_ranged` | Archer 在未进入 min_range 的情况下击败 Fighter（kite 成功） | combat_archer_vs_fighter |
| `battle_resolution` | 复用：有击杀事件 | 所有战斗场景 |

---

## 6. 文件变更清单

### 新增文件

| 文件 | 说明 |
|------|------|
| `scripts/archer.gd` | Archer 兵种（继承 CharacterBody3D，复用 Fighter 移动框架） |
| `scripts/arrow.gd` | Arrow 弹道节点 |
| `scripts/arrow_manager.gd` | Arrow 生命周期管理（统一 add/remove，避免散落场景树） |
| `tests/scenes/combat_archer_vs_fighter/` | 战斗专项场景（scene.tscn + bootstrap.gd + config.json） |
| `tests/scenes/combat_archer_vs_archer/` | 镜像对战场景 |
| `tests/scenes/combat_kite_behavior/` | kite 行为专项场景 |
| `docs/phases/phase10/checklist.md` | 本阶段 checklist |

### 修改文件

| 文件 | 改动 |
|------|------|
| `scripts/bootstrap.gd` | 新增 ArrowManager 初始化；新增 archer 配置读取 |
| `config.json` | 新增 `archer` 配置段 |
| `tests/test_runner.gd` | 支持 .tscn 场景加载 |
| `docs/phases/roadmap.md` | 新增 Phase 10 条目 |
| `FILES.md` | 新增文件条目 |

---

## 7. 暗坑预警

| 风险 | 表现 | 预防 |
|------|------|------|
| kite 时卡障碍物 | Archer 后撤遇到墙壁原地抖动 | kite 用直线后撤，不经过导航；到达边界时停止后撤改为原地射击 |
| Arrow 穿透后 hit_targets 膨胀 | 箭穿透大量单位后数组很大 | 命中即从 hit_targets 角度无需清理，Arrow 销毁后 GC 自动回收 |
| 场景专属 bootstrap 与 TestRunner 接口不匹配 | on_scenario_done 回调找不到 | bootstrap 复用相同的 `_finish()` 查找 TestRunner 的逻辑，接口保持一致 |
| 战斗测试无导航网格 | NavigationAgent3D 报警告 | 战斗专属 bootstrap 不创建 NavigationAgent3D，直线移动 fallback |
| Archer 在 preferred_range 附近反复进出 min_range | 状态机震荡（shoot ↔ kite 反复切换） | 加 hysteresis：进入 kite 需 dist < min_range，退出 kite 需 dist > preferred_range（不对称门槛） |

---

## 8. 验证标准

| 维度 | 通过条件 |
|------|---------|
| 现有 headless 回归 | 3/3 PASS（economy / combat / interaction 不受影响） |
| 战斗专项场景 | 3 个新场景各自 PASS |
| archer_kite 断言 | Archer 在战斗中触发过 kite 状态 |
| arrow_hits_target 断言 | Fighter 受到了箭矢伤害 |
| 窗口模式目视 | 箭矢飞行可见，Archer 后撤行为可观察 |

---

_创建：2026-03-29_
