# Phase 1 — 最小 RTS MVP Checklist

## Phase 1：最小 RTS MVP（4-6 周）

**目标**：完整游戏循环 demo（采集→造兵→打架→赢/输），人 vs 简单 AI 对手

**设计文档**：`docs/design/mvp.md`

**目录结构**：

```
src/phase1-rts-mvp/
├── project.godot
├── config.json
├── main.tscn
├── FILES.md
├── scripts/
│   ├── bootstrap.gd
│   ├── map_generator.gd
│   ├── hq.gd
│   ├── worker.gd
│   ├── fighter.gd
│   ├── resource_node.gd
│   ├── selection_box.gd
│   ├── selection_manager.gd
│   ├── ai_opponent.gd
│   └── ui/
│       ├── bottom_bar.gd
│       ├── prod_panel.gd
│       ├── game_over.gd
│       └── health_bar.gd
├── tools/ai-renderer/
└── tests/
```

### 子阶段 1A：项目骨架 + 地图 + 基地

**目标**：能 headless 启动，地图上有两个基地和矿点，导航网格正常工作。

- [x] **1A.1** 创建项目骨架：`project.godot`（60fps）+ `config.json`（MVP 参数）+ `main.tscn`（最小场景）✅
- [x] **1A.2** 实现 `map_generator.gd`：生成导航网格 + 矿点位置（从 config.json 读取）✅
- [x] **1A.3** 实现 `hq.gd`：StaticBody2D，资源存储 + 生产队列接口 + HP + 胜利条件信号 ✅
- [x] **1A.4** 实现 `resource_node.gd`：Area2D，可采集量 + 采集状态 + 信号 ✅
- [x] **1A.5** 实现 `bootstrap.gd`：读配置，创建地图/导航/基地/矿点，集成 AI Renderer ✅
- [x] **1A.6** headless 验证：项目能启动，3/3 断言通过，60fps ✅

### 子阶段 1B：单位系统（Fighter 复用 + Worker 新建）

**目标**：战士能移动+战斗，工人能移动。

- [x] **1B.1** 迁移 Fighter：从 Phase 0.5 `unit.gd` 迁移，微调参数（从 config.json 读取）✅
- [x] **1B.2** 实现 Worker 状态机：idle → move_to_mine → harvesting → returning → delivering → idle ✅
- [x] **1B.3** Bootstrap 生成初始单位：每方 3 工人 ✅
- [x] **1B.4** headless 验证：3/3 PASS，采集循环完整（harvesting → returning → move_to_mine）✅

### 子阶段 1C：采集 + 生产

**目标**：工人自动采矿并返回基地交付，基地能消耗资源生产单位。

- [x] **1C.1** Worker ↔ ResourceNode 交互：到达矿点后开始采集，携带量递增 ✅（1B 验证）
- [x] **1C.2** Worker ↔ HQ 交互：携带满后导航回基地，到达后交付资源 ✅（1B 验证）
- [x] **1C.3** HQ 生产队列：消耗资源 → 等待倒计时 → 产出单位（Worker/Fighter）✅
- [x] **1C.4** 新产出的单位在基地附近生成，自动进入 idle 状态 ✅
- [x] **1C.5** headless 验证：采集循环完整 + 生产队列成功产出 worker_6/worker_7，3/3 PASS ✅

### 子阶段 1D：战斗 + 胜利条件

**目标**：战士能跨队战斗，一方基地被摧毁触发游戏结束。

- [x] **1D.1** Fighter 跨队碰撞检测 + 索敌追击 + 攻击（复用 Phase 0.5 逻辑）✅
- [x] **1D.2** Worker 被攻击直接死亡（HP 低）✅
- [x] **1D.3** 胜利条件：基地 HP=0 → 触发 game_over 信号 ✅
- [x] **1D.4** headless 验证：战斗发生（kills=6），3/3 PASS ✅

### 子阶段 1E：交互系统 + UI

**目标**：复用 Phase 0.5 框选/选中，新增生产面板和底部状态栏。

- [x] **1E.1** 迁移 SelectionBox + SelectionManager（headless 兼容）✅
- [x] **1E.2** 实现 BottomBar：资源/选中信息/战况三段式 ✅
- [x] **1E.3** 实现 ProdPanel：选中基地弹出，点击按钮触发生产 ✅
- [x] **1E.4** 实现 HealthBar：单位头顶血条，受伤显示 ✅
- [x] **1E.5** 实现 GameOver：胜利/失败画面 + 战况统计 ✅
- [x] **1E.6** 窗口模式验证：框选+右键+生产面板+血条+游戏结束正常工作 ✅（UI 集成到 bootstrap）

### 子阶段 1F：AI 对手

**目标**：蓝方由简单 AI 控制，经济阶段→军事阶段→战术阶段。

- [x] **1F.1** 实现 `ai_opponent.gd`：固定策略决策循环 ✅
- [x] **1F.2** 经济阶段：自动生产工人（上限 5），工人自动采矿 ✅
- [x] **1F.3** 军事阶段：晶体 > 200 后开始生产战士 ✅
- [x] **1F.4** 战术阶段：战士编队进攻，基地被攻击时回防 ✅
- [x] **1F.5** headless 验证：AI 经济+军事正常运转，3/3 PASS ✅

### 子阶段 1G：AI Renderer 扩展 + 集成验证

**目标**：新增经济/生产/AI 对手断言，headless 全断言通过。

#### 1G.1：Formatter 新增段落

- [x] **1G.1.1** 新增 `economy` 段落：red_crystal + blue_crystal + mines=remaining/total
- [x] **1G.1.2** 新增 `production` 段落：HQ queue_size + producing（仅在有生产活动时输出）
- [x] **1G.1.3** 新增 `ai_opponent` 段落：blue workers/fighters 计数

#### 1G.2：Bootstrap 集成 SimulatedPlayer + Ref Holder

- [x] **1G.2.1** headless 模式下创建 SelectionBox + SelectionManager（逻辑组件，无视觉节点）
- [x] **1G.2.2** 实例化 SimulatedPlayer，从 config.json test_actions 读取剧本
- [x] **1G.2.3** 将 SimulatedPlayer 指标注入 renderer extra（simulated_player 字典）
- [x] **1G.2.4** 注册 SelectionManager 为 ref_holder（生命周期检查）
- [x] **1G.2.5** config.json 添加默认 test_actions 剧本（框选 + 移动命令）

#### 1G.3：Calibrator 新增断言（经济 / 生产 / AI）

- [x] **1G.3.1** `worker_cycle`：采样中出现过 `ai_state == "harvesting"` 的单位（采集循环启动）
- [x] **1G.3.2** `production_flow`：某方 HQ 的 `crystal > initial_crystal`（采集-交付循环完成）
- [x] **1G.3.3** `economy_positive`：红方 crystal > 200（初始值），证明经济正循环
- [x] **1G.3.4** `ai_economy`：蓝方水晶曾恢复增长（AI 采集-交付循环工作）— ⚠️ 初始设计"蓝方 crystal > 200"不可行（AI 立即花费），改为追踪 crystal 回升
- [x] **1G.3.5** `ai_produces`：蓝方总单位数 > 3（初始 3 工人），证明 AI 产出了额外单位
- [x] **1G.3.6** `battle_resolution`：3600 帧内或游戏结束时有击杀（kills > 0）

#### 1G.4：SimulatedPlayer 新增操作

- [x] **1G.4.1** 新增 `select_hq` 操作：选中红方 HQ 附近区域（验证框选 HQ 触发 prod_panel 逻辑）
- [x] **1G.4.2** 新增 `select_produce` 操作：模拟选中 HQ 后发起生产请求（验证生产链路）
- [x] **1G.4.3** 新增 `red_hq_area` / `blue_hq_area` 预设 rect（框选 HQ 附近区域）

#### 1G.5：集成验证

- [x] **1G.5.1** headless 全断言通过（3 原有 + 6 新增 = 9 个断言）✅ 9/9 PASS 60.1fps
- [x] **1G.5.2** Bug 回归测试：注入经济 bug → `economy_positive` [FAIL] → 恢复 → [PASS]
- [x] **1G.5.3** Bug 回归测试：注入 AI bug（decision_interval=999999 使 AI 不决策）→ `ai_produces` [FAIL] → 恢复 → [PASS] ✅

#### 1G.6：文档更新

- [x] **1G.6.1** 新建 Phase 1 FILES.md
- [x] **1G.6.2** 更新 implementation-plan.md 勾选

---

#### 1H：单位穿越障碍物 Bug 修复（窗口模式验证后补）

- [x] **1H.1** `worker.gd` + `fighter.gd`：`collision_mask = 0 → 2`（layer=2 对应墙/障碍物，不碰地面）
- [x] **1H.2** `map_generator.gd`：障碍物/墙 `collision_layer = 1 → 2`，NavigationMesh geometry source 改为 `SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN`，地面和墙加入 `navigation_geometry` 组
- [x] **1H.3** `config.json`：矿物由地图中心改为对称布局（红方近家矿 x=700、中立矿 x=1280、蓝方近家矿 x=1900）
- [x] **1H.4** `assertion_setup.gd`：新增 `_assert_no_obstacle_penetration`，检测单位是否落入障碍物 bbox；`bootstrap.gd` 传 obstacles；`visual_check.json` 加入该断言
- [x] **1H.5** headless 回归全通过：economy 6/6、combat 6/6、interaction 6/6、production_test 6/6、fighter_move_test 6/6
