# Phase 0.5 — RTS 技术验证 Checklist

## Phase 0.5：RTS 技术验证（1 周）

**目标**：验证 Godot 能否支撑 RTS 核心机制，确认继续还是换方向

**协作模式**：两人讨论设计 → 一人操作 AI 实现

**目录结构**：

```
src/phase05-rts-prototype/
├── project.godot
├── config.json              # 地图、单位、物理、renderer、测试剧本参数
├── main.tscn                # 最小场景（Camera2D + Bootstrap）
├── FILES.md                 # 文件索引（每个文件职责/依赖/接口）
├── scripts/
│   ├── bootstrap.gd         # 主控：读配置，动态创建地图+单位，管理 AI Renderer
│   ├── unit.gd              # 单位：寻路 + AI 状态机 + 战斗 + 死亡
│   ├── selection_box.gd     # 框选 UI：鼠标左键拖拽绘制矩形
│   └── selection_manager.gd # 选中管理：框选检测 + 高亮 + 移动命令转发
├── tools/
│   └── ai-renderer/         # AI Renderer（采集+格式化+校准+模拟玩家）
│       ├── ai_renderer.gd   # 入口：串联子模块
│       ├── sensor_registry.gd   # 采集注册表
│       ├── formatter_engine.gd  # 格式化引擎
│       └── calibrator.gd        # 校准器
└── tests/
    ├── test_ai_debug.sh          # Bug 注入测试
    ├── test_ai_understand.sh     # AI 理解验证
    └── output/                   # 测试日志输出
```

### 子阶段 A：导航寻路（纯 CLI，测性能天花板）

- [x] **0.5.1** 创建项目骨架：`project.godot`（零重力、60fps）+ `config.json`（地图 2000x1500、5 障碍物、25v25）+ `main.tscn`（最小场景）
- [x] **0.5.2** 实现 `bootstrap.gd`：读配置，代码生成 NavigationRegion2D（矩形障碍物 → 导航网格多边形）— 使用 `bake_navigation_polygon(false)` 同步烘焙
- [x] **0.5.3** 实现 `unit.gd`：CharacterBody2D + NavigationAgent2D，自动寻路移动，到达目标后随机选新目标 — 用 `map_changed` 信号等导航同步
- [x] **0.5.4** 50 单位随机寻路 CLI 测试，记录帧率（目标 ≥30fps）→ **50 单位 60.4fps ✅**
- [x] **0.5.5** 100 单位压力测试，找到性能拐点 → **100 单位 60.6fps，400 单位 60.5fps（headless 无渲染，瓶颈在窗口模式验证）**

### 子阶段 B：AI Renderer 基础设施 + 框选验证

- [x] **0.5.B2.1** 设计文档：`docs/design/ai-renderer.md`（架构、模块、接口、接入方式）
- [x] **0.5.B2.2** 实现 `sensor_registry.gd`：游戏对象注册 + 按配置频率采集状态
- [x] **0.5.B2.3** 实现 `formatter_engine.gd`：ai_debug 模式全量输出 / off 静默
- [x] **0.5.B2.4** 实现 `calibrator.gd`：断言注册 + 自动验证 + [PASS]/[FAIL] 输出
- [x] **0.5.B2.5** 实现 `ai_renderer.gd`：入口串联三模块，简洁 register/tick API
- [x] **0.5.B2.6** 接入 bootstrap.gd：注册单位、headless 下自动跑 Calibrator 断言
- [x] **0.5.B2.7** 验证：headless 运行，确认 [TICK] 输出 + [PASS]/[FAIL] 断言结果

#### 前置已完成（框选交互 + 移动命令代码）

- [x] **0.5.6** 实现 `selection_box.gd`：鼠标左键拖拽 → 半透明矩形覆盖
- [x] **0.5.7** 实现 `selection_manager.gd`：矩形区域检测重叠单位 → 选中高亮 + 底部显示选中数量
- [x] **0.5.8** 实现右键移动命令：选中单位 → 点击目标点 → NavigationAgent 设路径（含移动标记动画）
- [x] **0.5.9** 闭环验证：通过 AI Renderer 的 Calibrator 断言移动命令正确性 ✅ [PASS]

### 子阶段 C：战斗系统

- [x] **0.5.10** CollisionLayer 分队：红队 layer=2 / 蓝队 layer=3，互相碰撞检测
  - Calibrator 断言 `team_groups`：红队 ∈ team_red，蓝队 ∈ team_blue ✅ [PASS]
  - 修复 bug：`_enemy_group` 初始值错误（指向自己而非敌方）
- [x] **0.5.11** 索敌追击：每帧检测 sight_range 内最近敌方 → chase 状态 → 追击
  - Calibrator 断言 `chase_convergence`：180 帧后双方中心距离缩短 ✅ [PASS]（1200→120）
- [x] **0.5.12** 攻击+死亡：到达 attack_range → CD 扣血 → HP=0 → dead 状态 → queue_free
  - Calibrator 断言 `combat_kills`：600 帧内有击杀 ✅ [PASS]（22 kills）
  - Calibrator 断言 `battle_resolution`：一方被消灭 ✅ [PASS]（Red wins 17:0, 32 kills, 1358 frames）
- [x] **0.5.13** Renderer 战斗事件输出：Formatter 摘要包含击杀数、双方存活数、胜利方判定
  - Calibrator 断言 `renderer_combat_data`：snapshot 包含 hp + team_name 字段 ✅ [PASS]
- [x] **0.5.14** 窗口模式手感验证：25v25 自动对垒 + 框选指挥参战
  - 验证项：启动窗口模式 → 观察两军自动开战 → 框选己方单位 → 右键点击敌方方向 → 观察选中单位加入战斗 ✅ 手感流畅
  - 发现 bug：死亡单位导致框选失效（`selection_manager._all_units` 持有已释放节点引用）→ 已修复

### 子阶段 D：集成 + AI 验证

- [x] **0.5.15** 整合 demo：25 vs 25 两军对垒 + 框选指挥 + 战斗（headless 自动化断言）
  - 6 个 Calibrator 断言全部通过：`team_groups` `formatter_output` `renderer_combat_data` `chase_convergence` `combat_kills` `battle_resolution`
  - Formatter 增强输出单位状态分布（`states: wander:N chase:N attack:N`）
- [x] **0.5.16** AI debug 验证：引入 bug → Calibrator 检测 + AI 通过 Renderer 数据定位
  - Bug A（sight_range=0）：`combat_kills` [FAIL]，`states: wander:50`（所有单位闲逛）
  - Bug B（attack_damage=0）：`combat_kills` [FAIL]，`states: attack:49`（追到后在攻击但无效）
  - Bug C（speed=0）：`chase_convergence` [FAIL] 距离不变，`states: wander:50`（无法移动）
  - AI 可通过状态分布区分不同 bug 根因 ✅
  - 测试脚本：`tests/test_ai_debug.sh [sight_range_zero|attack_damage_zero|speed_zero]`
- [x] **0.5.17** AI 理解验证：导出战斗日志 → AI 能描述战况
  - 日志示例：Red 14:0 胜 Blue，战斗 ~420 帧开始（首次 death），~1264 帧结束
  - TICK 数据显示伤亡趋势：480帧 42存活 → 660帧 26存活 → 900帧 18存活
  - AI 能从 Renderer 输出还原完整战况 ✅
  - 测试脚本：`tests/test_ai_understand.sh`

**通过条件**：50 单位 ≥30fps ✅ 60.1fps + 框选手感流畅 ✅ + 战斗逻辑正确 ✅ + AI 能 debug ✅
**退出条件**：50 单位 <15fps / 框选体验极差 / 不感兴趣 → 换方向

### 子阶段 E：AI Renderer v2 升级 — SimulatedPlayer（headless 交互测试）

**目标**：升级 AI Renderer，使其能在 headless 模式下自动测试交互链路（框选、移动命令），消除"交互系统 bug 只能靠人工窗口测试"的盲区。

**设计文档**：`docs/design/ai-renderer.md`（v2 章节）

**动机**：Phase 0.5 发现的"死亡单位导致框选失效"bug 暴露了架构盲区——headless 模式不创建交互子系统，导致 AI Renderer 无法观测交互系统的引用一致性问题。

#### E.1：分离交互逻辑与视觉

- [x] **0.5.E1.1** 重构 `bootstrap.gd`：将交互子系统（SelectionManager）的创建从 `if not is_headless` 中提取出来，headless 也创建逻辑组件
  - 区分 `_create_visuals()`（Camera、渲染组件，仅窗口模式）和 `_create_interaction()`（SelectionBox、SelectionManager，所有模式）
  - headless 模式下 SelectionManager 不创建 Visual 子节点（Label），但保留框选和命令逻辑 ✅
- [x] **0.5.E1.2** 修改 `selection_box.gd`：headless 模式下不创建 Line2D / Polygon2D 视觉节点，但保留 `selection_rect_drawn` 信号发射逻辑 ✅
  - 新增 `set_headless()` 和 `simulate_drag()` 接口
- [x] **0.5.E1.3** 修改 `selection_manager.gd`：headless 模式下不创建 Label，但保留 `_collect_units()`、`_on_selection_rect()`、`move_command_issued` 信号 ✅
  - 新增 `set_headless()`、`get_all_units()`、`simulate_right_click()` 接口
  - 暴露交互指标：`last_select_count` / `last_invalid_refs` / `last_move_commands` / `total_errors`

#### E.2：实现 SimulatedPlayer

- [x] **0.5.E2.1** 新建 `tools/ai-renderer/simulated_player.gd`：数据驱动的操作剧本执行器 ✅
  - 从 config.json 的 `test_actions` 数组读取操作序列
  - 每帧检查是否到触发帧，执行对应动作
  - 支持 `box_select(rect)` / `right_click(target)` / `deselect` 三种操作
  - rect 预设：full_screen / top_left / top_right / bottom_left / bottom_right
  - target 预设：map_center / red_spawn / blue_spawn
  - 操作结果记录到公开属性，通过 bootstrap._extra 传递给 FormatterEngine
- [x] **0.5.E2.2** 在 `config.json` 中添加默认 `test_actions` 剧本 ✅
  - 帧 60：全屏框选（验证初始状态，预期选中 = 全部单位）
  - 帧 62：右键点击地图中心（验证移动命令）
  - 帧 300：全屏框选（战斗中期，验证有死亡后选中数 = 存活数）
  - 帧 302：右键点击敌方出生点（验证移动命令只发给存活单位）

#### E.3：新增 Calibrator 断言

- [x] **0.5.E3.1** 实现生命周期断言 `node_lifecycle_integrity` ✅
  - 通过 renderer.get_health() 检查所有 ref_holder 的无效引用
- [x] **0.5.E3.2** 实现交互断言 `select_after_death` ✅
  - 检查 SimulatedPlayer 第二次 box_select 的 select_count == alive_count
- [x] **0.5.E3.3** 实现交互断言 `move_cmd_integrity` ✅
  - 检查 SimulatedPlayer right_click 后的 invalid_refs == 0

#### E.4：Formatter 增强

- [x] **0.5.E4.1** `formatter_engine.gd` 增加交互健康度段落 ✅
  - `interaction: select={n} invalid={n} move={n} errors={n}`
- [x] **0.5.E4.2** `formatter_engine.gd` 增加引用健康度段落 ✅
  - `lifecycle: ok (SelectionManager:0/50)` 或 `lifecycle: WARNING invalid=3 holders=[...]`

#### E.5：集成验证

- [x] **0.5.E5.1** bootstrap.gd 集成 SimulatedPlayer（通过 _extra 传递指标，不直接注册到 Sensor Registry） ✅
- [x] **0.5.E5.2** 注册所有新断言到 Calibrator（9 个断言） ✅
- [x] **0.5.E5.3** headless 运行，确认 9 个断言（原 6 + 新 3）全部通过 ✅（修复了 simulated_player.gd 类型错误 + sensor_registry.gd freed instance crash + _assert_node_lifecycle 早判问题）
- [x] **0.5.E5.4** Bug 回归测试：注入"SelectionManager 不过滤无效引用"bug，确认 `node_lifecycle_integrity` 断言 [FAIL] ✅（检测到 12 invalid refs）
- [x] **0.5.E5.5** 更新 `FILES.md`：添加 simulated_player.gd 条目，更新所有 v2 变更的文件条目 ✅
- [x] **0.5.E5.6** 更新 `tests/test_ai_debug.sh`：增加 `no_ref_filter` 交互系统 Bug 注入场景 ✅

**子阶段 E 通过条件**：headless 模式下 9 个断言全通过 + 旧 bug（死亡单位引用）被自动检测到 [FAIL]

---
