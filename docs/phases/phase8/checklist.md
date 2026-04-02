# Phase 8 Checklist：窗口验证完整化

> 设计文档：[design.md](design.md)
> 原则：能程序化就不截图；截图是过渡，断言是目标，headless 是终极目标。
> B 轴（感知层语义计算）已废弃——游戏局势理解靠现有 Formatter log 足够。
> B 轴重启（导航统一）：headless 直线移动分叉导致验证不可信，需删除分叉让两模式跑同一套 NavigationAgent3D 逻辑。

---

## A1：SimulatedPlayer 开放窗口模式

- [x] `bootstrap.gd`：将 `_setup_simulated_player()` 和 `_sim_player.tick()` 从 `is_headless` 限制中解放出来，窗口模式也执行
- [x] 确认窗口模式下 SimulatedPlayer 剧本可以正常触发信号（A3 接入后验证）

## A2：新建 WindowAssertionSetup

- [x] 新建 `scripts/window_assertion_setup.gd`
- [x] 实现以下断言（全部为结构/属性检查）：
  - [x] `camera_orthographic`：Camera3D.projection == PROJECTION_ORTHOGONAL
  - [x] `camera_covers_map`：Camera3D.size >= map_height * 0.8
  - [x] `camera_centered`：Camera3D.position 在地图中央 ±300 内
  - [x] `units_have_mesh`：至少一个单位节点有 MeshInstance3D 子节点
  - [x] `hq_has_mesh`：HQ_red 有 MeshInstance3D 子节点
  - [x] `no_initial_selection`：frame 10 后 selected_units 为空
  - [x] `prod_panel_hidden_at_start`：frame 10 后 prod_panel.visible_state == false
  - [x] `prod_panel_shows_on_hq_click`：hq_selected 信号后 panel.visible_state == true
  - [x] `bottom_bar_visible`：BottomBar 节点 visible == true

## A3：Bootstrap 窗口模式接入

- [x] `bootstrap.gd`：非 headless 时调用 `_setup_window_assertions()`
- [x] 窗口模式下 renderer 也在每帧 tick（已有，Calibrator 已开启）
- [x] 窗口模式结束时调用 `renderer.print_results()` 输出窗口断言结果

## A4：visual_check.json scenario 完善

- [x] 确认 `tests/scenarios/visual_check.json` 包含完整 `screenshot_on_signals`
- [x] config.json 的 `scenario_file` 已指向 `res://tests/scenarios/visual_check.json`

## A5：验证

- [x] 运行窗口模式，所有窗口断言 PASS（`9 passed, 0 failed`）
- [x] 验证事件截图生效：`tests/screenshots/` 中出现 `ux_auto_*` 事件截图
- [x] headless `run_scenarios.sh`：3/3 PASS，11/11 断言（A 轴改动无回归）
- [x] 更新 FILES.md 记录新增文件

## B1：修复 nav mesh 烘焙（map_generator.gd）

> 根因：`SOURCE_GEOMETRY_ROOT_NODE_CHILDREN` 依赖 owner，动态创建的节点 owner=null 导致扫不到地面/墙体，烘焙空网格。

- [x] geometry source 改为 `SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN`，group name = `"navigation_geometry"`
- [x] `_create_ground()`、`_add_wall()` 中给 `StaticBody3D` 加 `add_to_group("navigation_geometry")`
- [x] `bake_navigation_mesh(false)` 同步烘焙，消灭时序问题

## B2：删除单位移动分叉（fighter.gd + worker.gd）

> 根因：`_is_headless` 分叉让 headless 走直线，headless 验证的不是真实游戏逻辑。

- [x] 删除 `_nav_ready` 变量及所有相关代码
- [x] 用 `_nav_available`（运行时检测 `map_get_iteration_id > 0`）统一两模式
- [x] `_is_at_target()` 统一用距离判断（避免 `is_navigation_finished()` path 未计算时误报）
- [x] `_move_along_path()` nav 可用时走 NavigationAgent3D，path 未就绪时回退直线（一帧后自动切回）
- [x] fighter.gd 和 worker.gd 对称处理

## B3：补充 Renderer 注册字段

- [x] `game_world.gd` 注册 worker/fighter 时补充 `"velocity"` 字段
- [x] formatter_engine.gd 扩展 behavior 输出：fighters 可见、速度显示、nav 状态显示

## B4：验证导航统一

- [x] headless `godot --headless --path .`：10/10 PASS（visual_check 场景）
- [x] economy.json 场景：6/6 PASS（含 economy_positive）
- [x] visual_check.json 添加显式 assertions 列表（economy_positive 改在 economy.json 验）
- [x] 窗口模式：单位正常移动（workers 采矿/返回循环正常，fighters wander + nav=Y）

> 根因双层：① `collision_mask=0` 导致 move_and_slide() 扫不到任何静态体；② 地面与墙共用 layer=1，mask=1 会被地面 Box 侧壁卡死。

- [x] `map_generator.gd`：墙/障碍物 `collision_layer = 1 → 2`（与地面区分）
- [x] `worker.gd` + `fighter.gd`：`collision_mask = 0 → 2`（只与 layer=2 墙/障碍物碰撞）
- [x] `config.json`：矿物由地图中心改为对称布局（红方近家 x=700、中立 x=1280、蓝方近家 x=1900）
- [x] `assertion_setup.gd`：新增 `no_obstacle_penetration` 断言（检测单位是否落入障碍物 bbox）
- [x] `visual_check.json` assertions 列表加入 `no_obstacle_penetration`（共 11 个）
- [x] headless 回归全通过：economy/combat/interaction/production_test/fighter_move_test 各 6/6 PASS

## B6：修复建造面板（窗口模式截图对照设计规范发现）

> 截图对照 mvp.md 规范，发现两处实现偏差：进度条漏加 add_child、面板固定在屏幕右上角而非基地上方。

- [x] `prod_panel.gd`：补 `vbox.add_child(_progress_bar)`（漏加导致进度条不渲染）
- [x] `prod_panel.gd`：去掉 `PRESET_CENTER_TOP` 固定锚点，改为 `_reposition_panel()` 用 `Camera3D.unproject_position` 将基地 3D 坐标投影到屏幕，面板跟随基地上方 80px
- [x] `window_assertion_setup.gd`：新增 `prod_panel_has_progress_bar`（检查 ProgressBar 在场景树中）
- [x] `window_assertion_setup.gd`：新增 `prod_panel_position_near_hq`（面板中心与 HQ 屏幕坐标距离 ≤ 300px）
- [x] 窗口断言 11/11 PASS（含两个新增断言）

---

## 完成标准

- [x] 窗口断言 11/11 PASS（原 9 个 + 新增 prod_panel_has_progress_bar / prod_panel_position_near_hq）
- [x] 事件截图在关键信号时自动生成（tests/screenshots/ 目录）
- [x] headless 11 个断言保持 PASS（visual_check 场景含 no_obstacle_penetration）
- [x] headless 与窗口模式走同一套 NavigationAgent3D 移动逻辑，无 `_is_headless` 移动分叉
- [x] 更新 roadmap.md Phase 8 状态为 ✅ 完成
