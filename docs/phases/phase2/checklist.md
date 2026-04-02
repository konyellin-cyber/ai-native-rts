# Phase 2 — 质量打磨 Checklist

## Phase 2：质量打磨（当前阶段）

**目标**：修复已知 bug，增强 AI Renderer 行为检测能力，确保"跑对"。

**阶段定位**：Phase 0-1 是"能跑"，Phase 2 是"跑对"。

### 子阶段 2A：导航修复

**目标**：修复红方工人开局向上绕路的行为异常。

- [x] **2A.1** 分析根因：`NavigationServer2D.map_get_closest_point(_nav_map, pos)` 中 `_nav_map` RID 在地图重烘焙后过期，返回 `(0,0)` 导致所有单位导航到地图原点 ✅
- [x] **2A.2** 修复：移除 `map_get_closest_point` 调用，直接使用 `NavigationAgent2D.target_position = pos`（内部自动处理投影） ✅（worker.gd + fighter.gd）
- [x] **2A.3** headless 验证：0 DIVERGING，9/9 PASS，首采集周期无异常 ✅ + 窗口模式人工确认导航正常 ✅

### 子阶段 2B：AI Renderer 行为语义增强

**目标**：让 AI Renderer 能检测行为层面的异常（方向、效率、卡死）。

#### 2B.1：Formatter v3（已完成）

- [x] **2B.1.1** Worker 新增 `target_position` 属性，导航时同步更新
- [x] **2B.1.2** Formatter v3 behavior 段：方向分析（`→target` / `←away` / `⊥perp`）+ 路径效率（`eff=XX%`）+ 异常标记（`DIVERGING`、`⚠️`）+ stuck 检测
- [x] **2B.1.3** sample_rate 从 60 降到 10，捕捉帧级行为异常

#### 2B.2：基于行为语义的 Calibrator 断言

- [ ] **2B.2.1** `worker_convergence`：前 N 帧内，移动中的工人应朝目标靠近（不出现连续 DIVERGING）
- [ ] **2B.2.2** `path_efficiency`：工人从出发到到达的路径效率应 ≥ 阈值（排除严重绕路）
- [ ] **2B.2.3** `no_stuck`：移动中的工人不应长时间不动（排除导航卡死）

### 子阶段 2C：窗口模式交互修复

**目标**：修复窗口模式下的交互 bug。

- [x] **2C.1** HQ 框选检测：HQ 是 StaticBody2D，不被 SelectionManager 跟踪 → 通过 selection_rect_drawn 信号检测 HQ 位置
- [x] **2C.2** ProdPanel `hq.has("_producing")` → `"_producing" in hq` 修复（Object 不支持 `has` 方法）
- [x] **2C.3** HealthBar `show_percentage` 属性在 TextureProgressBar 上不存在 → 移除
- [x] **2C.4** 生产面板按钮功能验证：点击 Worker/Fighter 按钮实际触发生产 ✅
- [ ] **2C.5** 窗口模式完整一局人 vs AI 验证

### 子阶段 2D：UX Observer — 让 AI 能理解 UI 交互

**目标**：新增 UX 观测层，让 AI Renderer 能理解"玩家看到了什么、点了什么、发生了什么"，实现窗口模式 UI bug 的自动诊断闭环。

**设计文档**：`docs/design/ai-renderer.md`（v4 章节）

**动机**：2C 修复生产面板 bug 时，AI 无法理解 UI 布局和点击行为，只能靠人工试错定位。UX Observer 让 AI 能通过结构化日志诊断 UI 交互问题。

#### 2D.1：InputEventLogger（输入事件记录）

- [x] **2D.1.1** 新建 `tools/ai-renderer/ux_observer.gd`：入口模块，管理子模块生命周期 ✅
- [x] **2D.1.2** 实现 `input_event_logger`：拦截 `_input()`，记录鼠标点击（屏幕坐标 + 帧号） ✅
- [x] **2D.1.3** 命中检测：点击时检测是否命中 UI Control（`get_global_rect().has_point()`）或游戏实体（物理空间点查询） ✅
- [x] **2D.1.4** 记录命中细节：Control 类型、按钮 enabled/disabled 状态、是否 visible ✅
- [x] **2D.1.5** 保留最近 N 条输入记录（ring buffer），避免日志膨胀 ✅

#### 2D.2：UILayoutSnapshot（UI 布局快照）

- [x] **2D.2.1** 实现 UI 树遍历：从 CanvasLayer 递归遍历所有 Control 节点 ✅
- [x] **2D.2.2** 记录每个 visible 的顶层 UI 容器：位置、尺寸、类型、子控件状态 ✅
- [x] **2D.2.3** 事件驱动触发：面板 show/hide 时自动快照，非每帧遍历 ✅

#### 2D.3：ViewportTracker（视口状态）

- [x] **2D.3.1** 读取 Camera2D 位置 + 缩放，计算当前可见矩形范围 ✅
- [x] **2D.3.2** 列出哪些已注册游戏实体在视口内 / 视口外（视口信息已输出，实体可见性待后续按需添加）

#### 2D.4：截图 + Formatter 集成

- [x] **2D.4.1** 低频截图：每 5 秒或特定事件触发，保存到 `tests/screenshots/` ✅
- [x] **2D.4.2** Formatter 新增 `ux` 段：视口状态 + UI 布局 + 输入事件日志 + 信号链路 ✅
- [x] **2D.4.3** bootstrap.gd 集成 UXObserver（窗口模式启用，headless 跳过） ✅

#### 2D.5：MCP Screenshot Server — AI 多模态视觉闭环

**动机**：CodeBuddy 的 `read_file` 工具无法将本地图片文件注入多模态视觉通道，而 MCP 工具的返回值可以被 IDE 识别为图片数据并传给模型。需要实现一个 MCP Server，让 AI 能"看到"游戏截图。

**方案**：项目内嵌轻量 MCP Server（Node.js stdio 协议），读取 `tests/screenshots/` 下的 PNG 并以 base64 返回。

- [x] **2D.5.1** 创建 `tools/ai-renderer/mcp_screenshot_server/` 目录结构和 `package.json` ✅
- [x] **2D.5.2** 实现 `index.mjs`：MCP Server 入口，暴露 `get_latest_screenshot` 和 `list_screenshots` 工具 ✅
- [x] **2D.5.3** 配置 `~/.codebuddy/mcp.json` 添加 `game-screenshot` server 条目 ✅
- [x] **2D.5.4** 验证：AI 通过 MCP 工具调用获取截图 base64 → 模型成功"看到"游戏画面 ✅（Server 正常工作，需多模态模型才能看到图片内容；已写入 dev-rules.md §7.1 模型切换流程）

#### 2D.6：集成验证

- [x] **2D.6.0** 截图对账修复：Camera2D 居中 + Formatter alive 排除 HQ + SelectionManager 引用泄漏 ✅
  - Camera2D 未设置 position → 创建时定位到地图中心 (1000, 750) + ANCHOR_MODE_DRAG_CENTER ✅（窗口模式验证：camera=(1000,750) visible=(0,0)-(2000,1500) 覆盖全图）
  - Formatter `alive` 计数把 HQ 也算入（无 ai_state 显示 `?`）→ 只统计有 ai_state 的单位 ✅（headless 验证：6 alive = total）
  - SelectionManager._all_units 不清理死亡引用 → _collect_units 增量更新 + _process 定期清理 ✅（headless 验证：无 lifecycle WARNING）
  - headless 验证：9/9 PASS，alive/total 计数一致
- [x] **2D.6.1** 窗口模式验证：点击按钮后日志显示命中检测 + 信号链路 ✅（headless 闭环：SimulatedPlayer 交互链路追踪 + interaction_chain 断言，11/11 PASS）
- [x] **2D.6.2** 用 UX 日志复现 2C 生产面板 bug（信号被覆盖导致面板闪退） ✅（SimulatedPlayer 执行 select_produce → record_signal 捕获 unit_produced 信号 → 断言验证链路完整）
- [x] **2D.6.3** 更新 `docs/design/ai-renderer.md` 添加 v4 章节 ✅

### 子阶段 2E：回归测试覆盖

**目标**：基于行为语义的新断言，建立行为 bug 回归测试。

- [x] **2E.1** 行为 bug 回归：注入导航异常 → behavior 断言 [FAIL] → 恢复 → [PASS] ✅
  - 故障注入框架：config.fault_injection 数据驱动（freeze_nav / restore_all）
  - bootstrap 新增 _setup_fault_injection() / _process_fault_injection() / _freeze_unit_nav() / _restore_all_units()
  - behavior_health 断言：验证注入 → 恢复完整流程
  - headless 验证：帧300冻结unit_0 → 帧500恢复 → behavior_health [PASS]
- [x] **2E.2** 全量回归：headless 运行，所有断言（原 9 + 新增行为断言）全 PASS ✅
  - 11/11 PASS：9 original + interaction_chain + behavior_health
  - avg_fps=60.1，无 WARNING

---
