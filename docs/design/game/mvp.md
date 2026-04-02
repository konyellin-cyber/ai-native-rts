# 最小 RTS MVP 设计文档

> Phase 1 目标：完整游戏循环 demo（采集→造兵→打架→赢/输），人 vs 简单 AI 对手

## 1. 游戏定义

**核心循环**：
```
基地生产工人 → 工人采矿 → 资源回基地 → 基地消耗资源造兵
→ 战士战斗 → 摧毁对方基地 → 胜利/失败
```

**资源模型**（极简）：
- 1 种资源：晶体
- 矿点产出速率：固定，不需要矿场建筑
- 采集量：工人每次运送 10 晶体，运送时间 ~3 秒往返

**实体模型**：

| 实体 | 数量 | 职责 | 关键属性 |
|------|------|------|---------|
| 基地 (HQ) | 1/方 | 生产单位、接收资源、胜利条件 | HP、生产队列、资源存储 |
| 矿点 | 3-5 个 | 被采集、不可摧毁 | 剩余量（有限或无限） |
| 工人 (Worker) | 0→N | 采集 + 返回基地 | 采集速率、移动速度 |
| 战士 (Fighter) | 0→N | 移动 + 攻击 | HP、攻击力、攻击范围、索敌范围 |

**初始状态**：
- 每方：1 基地（HP 500）+ 3 工人 + 200 晶体
- 矿点分布在地图中央区域

**胜利条件**：摧毁对方基地

## 2. 模块架构

```
┌─────────────────────────────────────────────────────────────┐
│                        MVP 模块图                           │
│                                                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │ 地图系统  │  │ 资源系统  │  │ 生产系统  │  │ AI 对手  │  │
│  │ (Map)    │  │(Economy) │  │(Production)│  │(AI Opp)  │  │
│  └────┬─────┘  └────┬─────┘  └────┬──────┘  └────┬─────┘  │
│       │              │              │              │         │
│  ┌────┴──────────────┴──────────────┴──────────────┴─────┐ │
│  │                    单位系统 (Units)                      │ │
│  │           Worker（采集状态机）+ Fighter（战斗状态机）      │ │
│  └─────────────────────────┬─────────────────────────────┘ │
│                            │                                │
│  ┌─────────────────────────┴─────────────────────────────┐ │
│  │              交互系统 (Interaction)                      │ │
│  │    框选 (SelectionBox) + 选中管理 (SelectionManager)    │ │
│  │    建造面板 (BuildPanel) + 生产面板 (ProdPanel)          │ │
│  └─────────────────────────┬─────────────────────────────┘ │
│                            │                                │
│  ┌─────────────────────────┴─────────────────────────────┐ │
│  │              AI Renderer（基础设施）                     │ │
│  │    SensorRegistry + FormatterEngine + Calibrator        │ │
│  │    + SimulatedPlayer（headless 自动测试）                │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## 3. 模块与 AI Renderer 的关系

AI Renderer（`docs/design/ai-renderer.md`）是项目的**基础设施层**，为所有游戏模块提供可观测性和自动化验证。以下描述每个模块如何接入 AI Renderer。

### 3.1 地图系统 (Map) — 新建

**职责**：生成地图布局（基地位置、矿点位置、障碍物、导航网格）

**与 AI Renderer 的关系**：
- **注册方式**：地图本身不注册到 Sensor Registry（静态数据，不变）
- **角色**：为其他模块提供导航网格（NavigationRegion2D），让单位系统正常工作
- **Calibrator 断言**：地图布局正确性（矿点数量、基地位置在合法区域内）
- **复用 Phase 0.5**：导航网格生成逻辑直接迁移，不需要改动

### 3.2 资源系统 (Economy) — 新建

**职责**：管理每方资源存储、采集流水线、资源变化日志

**与 AI Renderer 的关系**：

| 接入点 | 说明 |
|--------|------|
| `register("economy_red", economy_node, ["crystal", "income_rate", "total_harvested"])` | 每方一个经济实体 |
| `set_extra({"economy": {"red_crystal": ..., "blue_crystal": ...}})` | 每 tick 传入资源快照 |
| Formatter 段落 | 新增 `economy: red={n} blue={n} income={n}/s` |
| Calibrator 断言 | `economy_positive`：资源总量持续增长（未消耗时）；`harvest_flow`：采集流程正常运转 |

**SimulatedPlayer 操作**：
- 无需新增操作类型（资源系统由 AI 对手和工人自动运行）

### 3.3 生产系统 (Production) — 新建

**职责**：基地生产队列管理（选择单位类型 → 消耗资源 → 等待倒计时 → 产出单位）

**与 AI Renderer 的关系**：

| 接入点 | 说明 |
|--------|------|
| `register("hq_red", hq_node, ["queue_size", "producing", "crystal"])` | 每方基地注册 |
| `set_extra({"production": {"red_queue": ..., "blue_queue": ...}})` | 生产队列状态 |
| Formatter 段落 | 新增 `production: red_q={n} blue_q={n} producing={type}` |
| Calibrator 断言 | `production_flow`：队列中单位能正常产出；`resource_check`：资源不足时不进入队列 |

**SimulatedPlayer 操作**：
- `select_produce(unit_type)`：模拟点击生产按钮（headless 测试生产流程）

### 3.4 单位系统 (Units) — 复用 + 扩展 Phase 0.5

**职责**：工人和战士的行为控制（状态机、移动、战斗、采集）

**Phase 0.5 已有**：
- `unit.gd`：CharacterBody2D + NavigationAgent2D，wander/chase/attack/dead 状态机
- `move_to()` 公共接口
- `get_unit_state()` 数据导出
- 战斗逻辑（索敌、追击、攻击、死亡）

**MVP 新增**：

| 新增内容 | 说明 |
|---------|------|
| `worker.gd` | 继承 unit 逻辑，新增 idle→move_to_mine→harvest→return→deliver 状态机 |
| `fighter.gd` | 基本等于 Phase 0.5 的 unit.gd，可能微调参数 |
| 采集状态 | `harvesting`（在矿点采集中）、`returning`（运送回基地） |
| 建造能力 | 工人可以建造建筑（Phase 1+，MVP 不需要） |

**与 AI Renderer 的关系**：

| 接入点 | 复用/新增 |
|--------|----------|
| `register("Unit_%d", unit, fields)` | 复用，fields 增加 `"unit_type"`, `"carrying"` |
| Calibrator 断言 | 复用 `team_groups`、`chase_convergence`、`combat_kills`、`battle_resolution` |
| Calibrator 新增断言 | `worker_cycle`：工人完成至少一次采集往返；`unit_types`：单位类型分布正确 |
| SimulatedPlayer | 复用 `box_select`、`right_click`，新增 `select_produce`（通过生产面板） |

### 3.5 交互系统 (Interaction) — 复用 Phase 0.5 + 新增面板

**Phase 0.5 已有**：
- `selection_box.gd`：框选（headless 兼容 + simulate_drag）
- `selection_manager.gd`：选中管理 + move_command 信号（headless 兼容 + simulate_right_click）

**MVP 新增**：

| 新增组件 | 职责 | 与 AI Renderer 关系 |
|---------|------|-------------------|
| BuildPanel | 选择建造类型（Phase 1+） | 注册到 Sensor Registry |
| ProdPanel | 选择生产单位类型 | SimulatedPlayer 操作目标 |

**与 AI Renderer 的关系**：
- 复用所有 Phase 0.5 的交互断言：`select_after_death`、`move_cmd_integrity`
- 复用生命周期断言：`node_lifecycle_integrity`
- 新增：生产面板操作的断言覆盖

### 3.6 AI 对手 (AI Opponent) — 新建

**职责**：控制蓝方的决策逻辑（经济策略 + 生产策略 + 战术指挥）

**与 AI Renderer 的关系**：

| 接入点 | 说明 |
|--------|------|
| `register("ai_opponent", ai_node, ["strategy", "crystal", "idle_workers"])` | AI 对手状态 |
| `set_extra({"ai_opponent": {"phase": ..., "next_action_frame": ...}})` | 决策日志 |
| Formatter 段落 | 新增 `ai_opp: phase={name} workers_idle={n}` |
| Calibrator 断言 | `ai_economy`：AI 对手经济不崩溃（资源 > 0）；`ai_produces`：AI 对手持续产出单位 |

**设计原则**：
- AI 对手代码**不知道** AI Renderer 的存在（零侵入）
- AI Renderer 只**观察** AI 对手的决策结果，不参与决策

## 4. 文件结构（Phase 1 MVP）

```
src/phase1-rts-mvp/
├── project.godot
├── config.json                # 全局参数（地图、单位、AI 对手策略、renderer 配置）
├── main.tscn                  # 最小场景
├── FILES.md
├── scripts/
│   ├── bootstrap.gd           # 主控：创建地图/矿点/基地/初始单位，管理 AI Renderer
│   ├── map_generator.gd       # 地图生成（矿点位置、障碍物、导航网格）
│   ├── hq.gd                  # 基地：生产队列 + 资源存储 + 胜利条件
│   ├── worker.gd              # 工人：采集状态机 + 移动
│   ├── fighter.gd             # 战士：战斗状态机 + 移动（复用 phase0.5 unit.gd）
│   ├── resource_node.gd       # 矿点：可采集量 + 被采集动画
│   ├── selection_box.gd       # 框选（复用 phase0.5）
│   ├── selection_manager.gd   # 选中管理（复用 phase0.5）
│   ├── ai_opponent.gd         # AI 对手：策略决策
│   └── ui/
│       ├── bottom_bar.gd      # 底部状态栏（资源/选中/战况）
│       ├── prod_panel.gd      # 生产面板（选中基地时弹出）
│       ├── game_over.gd       # 游戏结束画面
│       └── health_bar.gd      # 单位血条组件
├── tools/
│   └── ai-renderer/           # AI Renderer（从 phase0.5 复制 + 扩展）
│       ├── ai_renderer.gd
│       ├── sensor_registry.gd
│       ├── formatter_engine.gd
│       ├── calibrator.gd
│       └── simulated_player.gd
└── tests/
    ├── test_ai_debug.sh
    └── output/
```

## 5. 状态机设计

### 5.1 Worker 状态机

```
                ┌──────────┐
                │   idle   │ ◄── 初始状态 / 交付完成
                └────┬─────┘
                     │ AI 对手/玩家下达采集命令
                     ▼
              ┌──────────────┐
              │ move_to_mine │ → 导航到最近矿点
              └──────┬───────┘
                     │ 到达矿点
                     ▼
             ┌──────────────┐
             │  harvesting  │ → 停留采集，每 tick 增加携带量
             └──────┬───────┘
                    │ 携带满
                    ▼
             ┌──────────────┐
             │  returning   │ → 导航回基地
             └──────┬───────┘
                    │ 到达基地
                    ▼
             ┌──────────────┐
             │  delivering  │ → 卸载资源到基地 crystal 存储
             └──────┬───────┘
                    │
                    └──→ idle
```

**与战斗的关系**：Worker 没有攻击能力，被攻击时 `take_damage` → 直接死亡（HP 较低）。不索敌，不还击。

### 5.2 Fighter 状态机

复用 Phase 0.5 `unit.gd` 的状态机：`wander → chase → attack → dead`。

新增行为：
- 玩家框选后右键点击敌方 → override wander，执行移动命令
- 到达目标后恢复 wander

### 5.3 AI 对手决策循环

```
每 N 帧执行一次决策：
┌─────────────────────────────────┐
│ 1. 检查经济状态                   │
│    crystal >= 生产工人成本?      │
│    idle_workers > 0?            │
├─────────────────────────────────┤
│ 2. 经济阶段（前期）               │
│    优先生产工人（上限 5）          │
│    工人自动采矿                  │
├─────────────────────────────────┤
│ 3. 军事阶段（晶体 > 200）        │
│    开始生产战士                  │
│    战士编队进攻                  │
├─────────────────────────────────┤
│ 4. 战术阶段（战士 > 5）          │
│    集结进攻 / 攻击敌方矿点       │
│    基地被攻击时回防              │
└─────────────────────────────────┘
```

## 6. UI 设计

> UI 组件设计规范与交互定义已迁移至独立目录：
> **[docs/design/ui/INDEX.md](../ui/INDEX.md)**
>
> 包含：布局总览、底部状态栏、生产面板、框选交互、血条、游戏结束画面。
> **窗口断言以该目录文档为准。**

## 7. config.json 结构

```json
{
  "map": {
    "width": 2000,
    "height": 1500
  },
  "mineral_nodes": [
    { "x": 900, "y": 750, "amount": 5000 },
    { "x": 1000, "y": 600, "amount": 5000 },
    { "x": 1100, "y": 900, "amount": 5000 }
  ],
  "hq": {
    "hp": 500,
    "radius": 40
  },
  "worker": {
    "hp": 30,
    "speed": 120,
    "radius": 6,
    "carry_capacity": 10,
    "harvest_time": 1.5
  },
  "fighter": {
    "hp": 100,
    "speed": 150,
    "radius": 8,
    "attack_damage": 10,
    "attack_range": 30,
    "sight_range": 200,
    "attack_cooldown": 0.5
  },
  "production": {
    "worker_cost": 50,
    "fighter_cost": 100,
    "worker_time": 3.0,
    "fighter_time": 5.0
  },
  "ai_opponent": {
    "decision_interval": 120,
    "max_workers": 5,
    "attack_threshold": 5
  },
  "renderer": {
    "mode": "ai_debug",
    "sample_rate": 60,
    "calibrate": true
  },
  "test_actions": []
}
```

## 8. AI Renderer 扩展计划

### 7.1 新增 Formatter 段落

```
[TICK 300] 12 alive (7R / 5B) kills=3 total=(10R/10B)
  states: wander:2 chase:3 attack:4 harvest:2 return:1
  economy: red=350(+2/s) blue=280(+1/s)
  production: red_q=1(fighter) blue_q=0
  interaction: select=0 invalid=0 move=0 errors=0
  lifecycle: ok (SelectionManager:0/20)
  ai_opp: phase=military workers_idle=1/4
```

### 7.2 新增 Calibrator 断言

| 断言名 | 类别 | 检查内容 |
|--------|------|---------|
| `worker_cycle` | 游戏逻辑 | 300 帧内至少一个工人完成一次采集往返 |
| `production_flow` | 游戏逻辑 | 生产队列中的单位能正常产出 |
| `economy_positive` | 经济 | 未消耗时资源总量持续增长 |
| `ai_economy` | AI 对手 | AI 对手资源不归零（经济不崩溃） |
| `ai_produces` | AI 对手 | AI 对手 300 帧内产出至少 1 个单位 |
| `hq_victory` | 胜利条件 | 一方基地被摧毁时正确触发结束 |
| 复用 | 战斗 | `team_groups`, `combat_kills`, `battle_resolution` |
| 复用 | 交互 | `select_after_death`, `move_cmd_integrity` |
| 复用 | 生命周期 | `node_lifecycle_integrity` |

### 7.3 SimulatedPlayer 新增操作

| 操作 | 参数 | 语义 |
|------|------|------|
| `select_produce` | `unit_type: "worker" / "fighter"` | 模拟点击生产按钮 |
| `select_hq` | 无 | 模拟点击己方基地（打开生产面板） |

## 8. 从 Phase 0.5 到 Phase 1 的迁移路径

| 模块 | 迁移方式 | 工作量 |
|------|---------|--------|
| AI Renderer 全套 | 直接复制 `tools/ai-renderer/` | 低 |
| SelectionBox/Manager | 直接复制，微调接口 | 低 |
| Fighter | 基于 unit.gd 微调 | 低 |
| Map 生成 | 提取 bootstrap 中的导航逻辑到 map_generator.gd | 低 |
| Worker | 新建，参照 Fighter 的移动框架 | 中 |
| HQ（基地） | 新建 | 中 |
| ResourceNode（矿点） | 新建 | 低 |
| AI Opponent | 新建，核心工作量 | 高 |
| ProdPanel（生产面板） | 新建 | 中 |
| Formatter 扩展 | 在现有基础上添加段落 | 低 |
| Calibrator 扩展 | 添加新断言 | 低 |

**估计总工作量**：4-6 周（每周 5-10 小时）

## 10. 风险与退出条件

| 风险 | 应对 |
|------|------|
| 采集 + 战斗 + AI 对手交互复杂度高 | 保持每个模块独立可测，不耦合 |
| 工人寻路到矿点的 UX | 复用 Phase 0.5 验证过的导航系统 |
| AI 对手太难调 | MVP 用固定策略，不追求智能 |
| 性能退化（更多实体 + 更多逻辑） | AI Renderer 分级采样控制 I/O 开销 |
| 过程不快乐 | 娱乐项目，随时可以停 |
