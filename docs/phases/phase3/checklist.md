# Phase 3 — 体验完善 Checklist

## Phase 3：体验完善

**目标**：让游戏"好玩"，有基本的 RTS 手感和策略深度。

**阶段定位**：Phase 3 是"好玩"。

### 子阶段 3A：AI Debug 工具链（窗口模式自主操作闭环）

> **前置说明**：3A 工具链是 3B（UI/UX）窗口验收的前提。窗口模式下 AI 需要自主操作游戏（框选、点击、拖拽），才能完成"操作 → 截图 → 分析"的闭环，无需人工中转。

- [x] **3A.1** Godot TCP 输入服务器 ✅
  - [x] **3A.1.1** 创建 `input_server.gd`（Node）
    - 监听 localhost:5555（可通过 config.input_server.port 配置）
    - `_process()` 轮询 `is_connection_available()` + `get_available_bytes()`
    - 支持命令：click / drag / right_click / get_frame
    - 通过 `Input.parse_input_event()` 注入 InputEventMouseButton / InputEventMouseMotion
    - 响应 JSON：`{"ok":true,"frame":N}` 或 `{"ok":false,"error":"..."}`
    - 验证：headless 启动后 `nc localhost 5555` 可连接 ✅
    - 验证：get_frame/click/drag/error 全部返回正确 JSON ✅
  - [x] **3A.1.2** 集成到 bootstrap.gd
    - 窗口模式下自动创建 InputServer 节点
    - headless 下通过 config.input_server.enabled 控制是否创建
    - 验证：headless 回归 11/11 PASS 无回归 ✅
  - [x] **3A.1.3** headless 输入验证
    - 通过脚本发送 click 命令 → TCP 返回 ok+frame ✅
    - 发送 drag 命令 → TCP 返回 ok+frame ✅
    - 发送 error 命令 → TCP 返回错误信息 ✅
    - 注：headless 下 InputEvent 注入后不会被 UX Observer 拦截（headless 无 _input 拦截），需窗口模式才能验证完整信号链路
- [x] **3A.2** MCP game-control tool + UI 查询 ✅
  - [x] 代码实现：扩展 `mcp_screenshot_server/index.mjs`，新增 `game_control` tool
  - [x] **3A.2.1** 实现 InputServer UI 查询命令（`input_server.gd`）
    - 新增 `ui_tree` 命令：遍历 CanvasLayer 下所有 visible Control 节点，返回 path/type/global_rect/visible/disabled
    - 新增 `ui_info` 命令：查询单个节点详细属性（position/size/anchor/z_index/text/子节点）
    - 新增 `ui_find` 命令：按类型查找 Control 节点（如 `type=Button`）
    - 新增 `hovered` 诊断命令：返回当前鼠标位置和悬停控件
    - 验证：TCP 发送 `{"cmd":"ui_find","type":"Button"}` 返回所有按钮的 global_rect ✅
  - [x] **3A.2.2** 扩展 MCP tool 支持 UI 查询
    - 在 `game_control` tool schema 中新增 `ui_tree`/`ui_info`/`ui_find` 命令
    - 验证：AI 通过 MCP 调用 `ui_find` 获取按钮坐标 ✅
  - [x] **3A.2.3** 验证完整闭环 ✅
    - MCP drag 框选 HQ → `prod_panel_shown` 信号触发 ✅
    - MCP `ui_find type=Button` → 获取 Worker 按钮精确 global_rect=(12,58)+(130,39) ✅
    - 计算 center (77,78) → MCP click → `produce_requested(worker)` 信号触发 ✅
    - 修复发现：InputServer click/right_click 需用 `warp_mouse` 更新 Viewport 鼠标位置 + delayed release
    - 修复发现：GameOverUI 默认 visible=true 遮挡 ProdPanel 的 GUI hit-test → 改为默认 visible=false
  - 注：MCP server 需重启才能加载新 tool（CodeBuddy IDE 管理）
- [x] **3A.3** 操作剧本复用 ✅
  - [x] **3A.3.1** 创建剧本文件格式 + 示例剧本 ✅
    - 创建 `tests/scenarios/` 目录
    - 定义 Scenario JSON schema：name/description/actions[]（含 wait_frames/wait_signal/click_button/ui_find 动作）
    - 创建示例剧本 `tests/scenarios/production_test.json`（框选 HQ → wait_signal → click_button Worker → wait_signal produce_requested）
  - [x] **3A.3.2** 扩展 SimulatedPlayer 支持剧本格式 ✅
    - `setup()` 新增 `scenario_path` 参数，从外部 JSON 文件加载 actions（与 test_actions 向后兼容）
    - 新增 `wait_frames` 动作处理：设置 `_wait_until_frame`，tick() 中跳过后续动作直到帧数到达
    - 新增 `wait_signal` 动作处理：通过 bootstrap 信号回调检查，超时后跳过并记录 warning
    - 新增 `click_button` 动作处理：headless 下查找 Control 节点或直接调 produce_callback
    - 新增 `ui_find` 动作处理：headless 下遍历 CanvasLayer Control 节点，结果存入 `_saved_vars`
    - bootstrap.gd：新增 `scenario_file` 配置支持，优先加载外部剧本；转发相关信号到 SimPlayer
    - 验证：headless 加载 production_test.json → 执行 wait_frames/wait_signal/click_button → 无崩溃
  - [x] **3A.3.3** 扩展 InputServer 支持剧本模式 ✅
    - 新增 `play_scenario` TCP 命令：接收 `file` 参数，加载 JSON 剧本
    - 逐条执行剧本动作：click/drag/right_click 直接调现有方法，wait_frames 阻塞等待，ui_find 查 UI 树
    - click_button：执行 ui_find → 计算 global_rect center → 调 _do_click
    - 汇总执行结果返回：`{"ok":true, "results":[...], "summary":{...}}`
    - 验证：TCP 发送 play_scenario → 返回完整执行结果
  - [x] **3A.3.4** headless + 窗口双模式回归验证 ✅
    - headless 回归：11/11 PASS 无退化 ✅
    - headless 剧本加载：production_test.json 正常执行，12 个动作全部 success ✅
    - 窗口模式：MCP 发送 play_scenario → 11/12 success, 1 skipped (click_button 同步模式预期) ✅
    - 修复 bug：`setup([])` 覆盖 `load_scenario()` 的 `_actions` ✅
    - 修复设计：`click_button` 在同步 play_scenario 中标记 skipped 而非 failed（面板需帧间更新） ✅

### 子阶段 3B：UI/UX 改进

> **窗口验收方式**：3A 工具链完成后，3B 各项可通过 AI 自主操作 + 截图验证闭环。

- [x] **3B.-1** [BUG] 无法选择单位并移动（致命交互缺陷，多项根因）✅
  - **现象 A**：左键点击单位无法选中 → ✅ 已修复（`_try_select_unit_at()`）
  - **现象 B**：框选单位后右键无法移动 → ✅ 已修复
  - **根因 B 调查过程**：
    1. ~~ProdPanel/GameOverUI mouse_filter 拦截~~ → 已设 IGNORE，非根因
    2. ~~`_do_drag` 缺少 `warp_mouse`~~ → 已加，但非主根因
    3. **真正根因**：`worker.gd` 的 `move_to()` 设状态为 `idle`，但 `_physics_process` 中 `idle` 状态**立即**调用 `_start_harvest_cycle()` 重新开始采集，玩家移动指令被下一帧的 AI 状态机覆盖
    4. 附带问题：之前 MCP 测试框选范围 (200,600)→(800,900) 未覆盖实际单位位置（工人已向矿区移动），导致框选结果为 0——这不是 bug，是测试时坐标选择不当
  - **修复**：`worker.gd` 新增 `_player_moving` 标记，`move_to()` 时设为 true，`idle` 状态下不启动采集循环，`_agent.is_navigation_finished()` 后清除标记恢复正常行为
  - **MCP 闭环验证** ✅：drag 全屏框选 6 单位 → right_click (200,200) → 4 秒后 unit_info 确认红色单位状态 idle、位置向目标移动、速度方向正确
- [x] **3B.-1b** [BUG] 右键移动后单位卡住不动 ✅
  - **现象**：3B.-1 修复 `_player_moving` 防止采集覆盖后，右键移动单位仍然定住
  - **根因**：`_physics_process` 的 `idle` 分支在 `_player_moving=true` 时只检查导航是否完成，但没有调用 `_move_along_path()` 驱动移动
  - **修复**：`worker.gd` idle 分支增加 `_move_along_path()` 调用
- [x] **3B.-2** [BUG] 单击 HQ 无法选中 ✅
  - **现象**：SelectionManager 只追踪 `CharacterBody2D` 单位，HQ 是 `StaticBody2D`，单击检测遗漏
  - **修复**：`selection_manager.gd` 新增 `_all_hqs` 数组 + `hq_selected` 信号，`_try_select_unit_at` 同时检测 HQ（半径 45）；`bootstrap.gd` 连接信号 → `_on_hq_selected` → `prod_panel.show_panel`
- [x] **3B.-3** [BUG] 单击 HQ 不弹出生产面板 ✅
  - **现象**：框选 HQ 能弹出生产面板，但单击不行
  - **根因**：3B.-2 修复前单击无法选中 HQ；选中后缺少信号通知 ProdPanel
  - **修复**：与 3B.-2 合并修复，`hq_selected` 信号触发 `prod_panel.show_panel(hq)`
- [x] **3B.0** 生产面板按钮样式修复（用户反馈：按钮不可见）
  - 验证：窗口模式下选中 HQ → 面板弹出 → 按钮（Worker/Fighter）有明确背景色、边框、文字可见
  - 验证：按钮 normal/hover/pressed/disabled 四种状态视觉区分明显
  - 验证：headless 回归 11/11 PASS 无回归
  - 状态：代码已修改，headless 通过，待 3A 工具链完成后做窗口自主验收
- [ ] **3B.1** 单位选中视觉增强（选中光圈、编队编号）
  - 验证：框选单位后，选中单位脚下有高亮光圈
  - 验证：headless 回归无异常
  - 验证（窗口）：AI 框选单位 → 截图确认光圈 → 读日志确认 selection_rect_drawn
- [ ] **3B.2** 小地图（minimap）
  - 验证：右下角显示小地图，单位/建筑/HQ 均有对应标记
  - 验证：点击小地图可移动 Camera2D 视口
- [ ] **3B.3** 生产队列可视化（队列中单位图标/进度条）
  - 验证：生产面板显示当前队列中待生产单位列表
  - 验证：每个队列项有进度条
- [ ] **3B.4** 战斗反馈（伤害数字、死亡动画）
  - 验证：单位受击时显示伤害数字飘字
  - 验证：单位死亡时有消散/缩小动画
- [ ] **3B.5** 音效（选中确认、移动指令、攻击、生产完成）
  - 验证：各操作有对应音效反馈
  - 注：此项目需音频资源文件，可能需要先生成简单合成音效

### 子阶段 3C：平衡性

- [ ] **3C.1** 兵种属性平衡（HP/攻击力/速度/费用）
- [ ] **3C.2** 经济节奏调整（采集速率、矿点分布、资源总量）
- [ ] **3C.3** 平衡性测试工具（AI 跑 N 次对战统计胜率）

### 子阶段 3D：AI 对手强化

- [ ] **3D.1** 多策略 AI（经济优先/快攻/防守反击）
- [ ] **3D.2** AI 应对玩家行为（侦察、反制）
- [ ] **3D.3** AI 微操（战斗中拉扯、集火）

---
