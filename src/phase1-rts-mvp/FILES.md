# Phase 1 RTS MVP — File Index

## scripts/

### bootstrap.gd
- **职责**: 主序入口。读 config，按顺序创建子管理器（GameWorld / UnitLifecycleManager / FaultInjector / AssertionSetup），驱动每帧 tick 分发和信号路由
- **依赖**: 被 main.tscn 加载；依赖 game_world.gd / unit_lifecycle_manager.gd / assertion_setup.gd / fault_injector.gd
- **关键接口**: `_ready()`, `_physics_process()`
- **修改频率**: 低（5A–5F 重构后职责收窄，新功能应进对应子模块）
- **Phase 11 改动**: `_on_produce_requested()` 通用化（按 `unit_type+"_cost"/"_time"` 动态查 config）；`_update_ui()` 传入 `archer_cost`
- **注意**: 故障注入逻辑已迁移到 FaultInjector（5F），bootstrap 仅做条件挂载；Phase 9 起镜头为 45° 等距正交（rotation_degrees=(-45,-45,0)，position.z = map_h/2+1500，size=2000）

### game_world.gd
- **职责**: 游戏实体创建 + 场景树组装。按 config 创建 HQ / mineral / worker / fighter / AI 对手 / 交互组件 / UI
- **依赖**: 被 bootstrap.gd 创建；依赖所有游戏实体脚本和 ai_renderer
- **关键接口**: `setup(parent, config, is_headless, renderer)`, `build()`, `spawn_unit(team, unit_type)`
- **公开属性**: `hq_red`, `hq_blue`, `mineral_nodes`, `units`, `arrow_manager`, `selection_box`, `selection_manager`, `prod_panel`, `bottom_bar`, `game_over_ui`, `ux_observer`, `input_server`
- **信号**: `unit_died`, `unit_produced`, `hq_destroyed`, `hq_selected`, `selection_rect_drawn`, `units_selected`, `move_command_issued`, `produce_requested`
- **修改频率**: 低（新增实体类型时改）
- **Phase 11 改动**: `spawn_unit()` 增加 archer 分支，archer 调用 8 参数 setup（含 `arrow_manager`）
- **注意**: 不知道 Renderer tick、SimPlayer、断言的存在；实体信号通过冒泡让 bootstrap 处理

### unit_lifecycle_manager.gd
- **职责**: 单位生命周期管理。清理死亡单位引用、维护存活计数、kill_log、采集/交付状态追踪
- **依赖**: 被 bootstrap.gd 创建；持有对 game_world.units 和 hq_blue 的引用
- **关键接口**: `setup(units, hq_blue, frame_count_getter)`, `init_alive_counts(red, blue)`, `on_unit_died(id, team)`, `on_unit_produced(type, team)`, `tick()`, `clean_dead_units()`
- **只读属性**: `red_alive`, `blue_alive`, `kill_log`, `worker_harvesting_seen`, `blue_crystal_delivered`, `production_occurred`, `archer_produced`
- **Phase 11 改动**: 新增 `archer_produced: bool`，在 `on_unit_produced("archer","red")` 时置 true
- **修改频率**: 低

### assertion_setup.gd
- **职责**: 断言配置集中地。将所有 Calibrator 断言注册到 renderer，纯配置对象，无游戏逻辑
- **依赖**: 被 bootstrap.gd 创建；依赖 renderer / UnitLifecycleManager / sim_player；不依赖 world 节点
- **关键接口**: `setup(renderer, lifecycle, sim_player, fault_state, expected_mineral_count)`, `register_all()`
- **修改频率**: 低（新增断言时改）
- **Phase 11 改动**: 新增 `archer_produced` 断言（读 `lifecycle.archer_produced`）
- **注意**: 4 条断言（hq_exists / mineral_exists / worker_exists / economy_positive）改为读 snapshot 字典，彻底与 Formatter 文本格式解耦；fault_state 是 Dictionary 引用，由 bootstrap 的故障注入逻辑在运行时更新

### window_assertion_setup.gd
- **职责**: 窗口模式专属断言集合（Phase 8A 新增）。注册 13 个不依赖渲染画面的结构/属性断言
- **依赖**: 被 bootstrap.gd 在非 headless 分支创建；依赖 renderer / GameWorld / Bootstrap Node
- **关键接口**: `setup(renderer, world, bootstrap_node, map_width, map_height)`, `register_all()`
- **断言清单**: `camera_orthographic`, `camera_covers_map`, `camera_isometric`, `units_have_mesh`, `hq_has_mesh`, `no_initial_selection`, `prod_panel_hidden_at_start`, `prod_panel_shows_on_hq_click`, `bottom_bar_visible`, `prod_panel_has_progress_bar`, `prod_panel_position_near_hq`, `prod_panel_hides_on_click_outside`, `prod_panel_has_archer_button`
- **Phase 11 改动**: 新增 `prod_panel_has_archer_button`（检查 prod_panel 含"Archer"文本的 Button）
- **Phase 9 改动**: `camera_centered` → `camera_isometric`（检查 position.x 居中 ±300 + rotation_degrees.y 在 -45°±5°）
- **注意**: `prod_panel_shows_on_hq_click` 通过连接 `world.hq_selected` 信号追踪点击事件；`prod_panel` 的面板可见性用 `visible_state` 属性（非 `.visible`）

### worker.gd
- **职责**: 工人单位状态机（idle → move_to_mine → harvesting → returning → delivering）
- **依赖**: 被 bootstrap.gd spawn_unit() 创建；依赖 NavigationAgent2D + resource_node.gd + hq.gd
- **关键接口**: `setup(id, team, pos, cfg, headless, map_size, home_hq)`, 信号 `died(victim_id, victim_team)`, `move_to(target)`
- **修改频率**: 低
- **注意**: `carrying` 必须是 `float`（非 int），否则采集量永远为 0；`collision_mask = 0`

### fighter.gd
- **职责**: 战士单位状态机（idle → wander → chase → attack → dead），跨队战斗
- **依赖**: 被 bootstrap.gd / combat_bootstrap.gd spawn 创建；依赖 NavigationAgent3D
- **关键接口**: `setup(id, team, pos, cfg, headless, map_size, home_hq)`，`take_damage(amount)`，`take_damage_from(amount, from_pos)`（含击退冲量）
- **修改频率**: 低
- **注意**: 受击白闪（`_body_mat` 变白 0.1s）；击退（`_knockback` 向量每帧衰减）；`collision_mask = 2`

### archer.gd（Phase 10 新增）
- **职责**: 弓箭手单位状态机（idle → wander → chase → shoot → kite → dead），纯远程攻击
- **依赖**: 被 game_world.gd（Phase 11+）/ combat_bootstrap.gd 创建；依赖 NavigationAgent3D + ArrowManager
- **关键接口**: `setup(id, team, pos, cfg, headless, map_size, home_hq, arrow_manager)`，`take_damage(amount)`，`take_damage_from(amount, from_pos)`
- **参数**: shoot_range=160，flee_range=80，sight_range=220，attack_cooldown=1.2，arrow_speed=600
- **kite 逻辑**: 每帧直接设 velocity（不依赖目标点），边界处反弹 flee_dir，边跑边射
- **注意**: kite hysteresis：进入 dist<flee_range，退出 dist>=flee_range*1.5

### arrow.gd（Phase 10 新增）
- **职责**: 箭矢弹道节点。抛物线飞行、XZ+Y 命中检测、插身锁定、命中爆点
- **依赖**: 被 ArrowManager.fire() 创建；挂在 ArrowManager 下
- **关键接口**: `setup(velocity, damage, range, team, obstacles, headless, gravity)`
- **飞行**: 每帧 `_velocity.y -= gravity * delta`，移动 `position += _velocity * delta`
- **命中判定**: XZ 水平距离 + Y 高度范围双重判断（防弧顶误判）；优先调用 `take_damage_from`（击退）
- **插身**: 命中后 `_stuck_to` 锁定目标，`_stuck_offset` 跟随移动，3 秒后消失
- **注意**: headless 下不创建 MeshInstance3D，`_spawn_hit_flash` 和旋转对齐均在窗口模式才执行

### arrow_manager.gd（Phase 10 新增）
- **职责**: 箭矢生命周期管理。统一 add_child / queue_free，持有 obstacles 配置
- **依赖**: 被 bootstrap.gd / combat_bootstrap.gd 创建并 add_child 到场景树
- **关键接口**: `setup(obstacles, headless, arrow_speed)`, `fire(origin, velocity, damage, max_range, owner_team)`
- **数量上限**: MAX_ARROWS=40，超出时 `queue_free` 最旧（`get_child(0)`）

### hq.gd
- **职责**: 基地建筑。资源存储、生产队列、HP、胜利条件
- **依赖**: 被 bootstrap.gd 创建；信号连接到 bootstrap
- **关键接口**: `setup(team, pos, config, headless)`, `enqueue(unit_type, cost, time)`, 信号 `unit_produced(unit_type, team_name)`, `hq_destroyed(team_name)`, `resource_changed(crystal)`
- **修改频率**: 低
- **注意**: `producing` 字段仅在生产倒计时期间非空，采样间隔 60 帧几乎采不到

### resource_node.gd
- **职责**: 矿物节点。可采集量管理 + 采集交互
- **依赖**: 被 bootstrap.gd 创建；被 worker.gd 采集
- **关键接口**: `setup(name, pos, amount, headless)`, `harvest(delta, harvest_time, capacity, current_carrying) -> float`
- **修改频率**: 低
- **注意**: `harvest()` 返回 float，必须用 `minf()` 而非 `mini()`（GDScript 4.x 类型截断 bug）

### ai_opponent.gd
- **职责**: 蓝方 AI 对手。三阶段策略（经济→军事→战术）
- **依赖**: 被 bootstrap.gd 创建；控制 hq_blue 生产队列
- **关键接口**: `setup(hq, config, headless)`
- **修改频率**: 中（调优 AI 策略时）
- **注意**: 决策间隔 120 帧（2s），max_workers=5

### selection_box.gd
- **职责**: 框选 UI（窗口模式）/ 框选信号发射（headless 模式）
- **依赖**: 被 bootstrap.gd 创建；被 selection_manager.gd 监听
- **关键接口**: `set_headless()`, `simulate_drag(start, end)`, 信号 `selection_rect_drawn(rect)`
- **修改频率**: 低
- **注意**: headless 模式下不创建视觉节点

### selection_manager.gd
- **职责**: 选中管理。框选检测 + 高亮 + 移动命令转发
- **依赖**: 被 bootstrap.gd 创建；连接 selection_box 信号
- **关键接口**: `set_headless()`, `setup(selection_box)`, `get_all_units()`, `simulate_right_click(target)`, 指标 `last_select_count`/`last_invalid_refs`/`last_move_commands`
- **修改频率**: 低
- **注意**: `_on_selection_rect()` 中会自动过滤无效引用（freed 节点）

### map_generator.gd
- **职责**: 地图生成。创建导航网格 + 障碍物
- **依赖**: 被 bootstrap.gd 创建
- **关键接口**: `setup(config, headless)`, `generate(config)`
- **修改频率**: 低

## scripts/ui/

### bottom_bar.gd
- **职责**: 底部状态栏（资源/选中/战况）
- **依赖**: 被 bootstrap.gd 创建（仅窗口模式）
- **关键接口**: `setup(headless)`, `update_data(hq, selected, red_alive, blue_alive)`

### prod_panel.gd
- **职责**: 生产面板（选中 HQ 后弹出）
- **依赖**: 被 bootstrap.gd 创建（仅窗口模式）
- **关键接口**: `setup(headless)`, `show_panel(hq)`, `hide_panel()`, `update_state(hq, worker_cost, fighter_cost, archer_cost)`, 信号 `produce_requested(unit_type)`
- **Phase 11 改动**: 新增 Archer 按钮（「🏹 Archer」，💎125 ⏱4s）；`update_state` 增加 `archer_cost` 参数（默认 125）；`can_produce_archer` 状态

### game_over.gd
- **职责**: 游戏结束画面
- **依赖**: 被 bootstrap.gd 创建（仅窗口模式）
- **关键接口**: `setup(headless)`, `show_game_over(winner, stats)`

### health_bar.gd
- **职责**: 单位头顶血条
- **依赖**: 被 worker.gd / fighter.gd 内部创建

## tools/ai-renderer/

> **注意**：此目录为符号链接 → `../../shared/ai-renderer/`，源文件在 `src/shared/ai-renderer/`。
> 修改任何 ai-renderer 文件时，直接修改 shared 目录，所有 Phase 自动生效。

### ai_renderer.gd
- **职责**: AI Renderer 入口。串联 SensorRegistry + FormatterEngine + Calibrator
- **依赖**: 被 bootstrap.gd 实例化
- **关键接口**: `_init(config)`, `register(entity_id, node, fields)`, `unregister()`, `register_ref_holder()`, `add_assertion()`, `tick()`, `set_extra()`, `print_results()`
- **修改频率**: 低

### sensor_registry.gd
- **职责**: 采集注册表。按频率采集注册实体状态
- **依赖**: 被 ai_renderer.gd 使用
- **关键接口**: `configure(sample_rate)`, `register()`, `unregister()`, `register_ref_holder()`, `tick()`, `collect()`, `get_snapshot()`, `get_health()`
- **修改频率**: 低

### formatter_engine.gd
- **职责**: 格式化引擎。将采集数据转为 AI 可读文本
- **依赖**: 被 ai_renderer.gd 使用
- **关键接口**: `configure(mode, sample_rate)`, `format(snapshot, extra)`
- **输出段落**: header → states → economy → production → ai_opponent → interaction → lifecycle
- **修改频率**: 中（新增调试段落时）

### calibrator.gd
- **职责**: 校准器。注册断言函数，每帧推进状态机
- **依赖**: 被 ai_renderer.gd 使用
- **关键接口**: `add_assertion(name, check_fn)`, `tick()`, `print_results()`
- **断言状态**: pass / fail / pending / done（未完成自动标 fail）
- **修改频率**: 低

### simulated_player.gd
- **职责**: 剧本调度层。按帧推进 action 队列，维护 wait_frames / wait_signal 状态机
- **依赖**: 被 bootstrap.gd 创建；内部创建 ActionExecutor + SignalTracer
- **关键接口**: `setup(actions, sel_box, sel_mgr, map_w, map_h, produce_cb)`, `tick(frame)`, `record_signal(name, args)`, `get_interaction_summary()`
- **修改频率**: 低

### action_executor.gd
- **职责**: 单条 action 的执行逻辑。操作 sel_box / sel_mgr / produce_callback，返回执行结果
- **依赖**: 被 simulated_player.gd 内部创建
- **关键接口**: `setup(sel_box, sel_mgr, map_w, map_h, produce_cb)`, `execute(action, frame) -> Dictionary`
- **修改频率**: 低（新增 action 类型时改）
- **Phase 11 改动**: `click_button` 分支改为 `known_units` 列表匹配，支持 "Archer"（原来硬编码 Worker/Fighter）

### signal_tracer.gd
- **职责**: 信号接收历史记录。供 wait_signal 机制查询
- **依赖**: 被 simulated_player.gd 内部创建
- **关键接口**: `record(signal_name, frame, args)`, `get_chain() -> Array`
- **修改频率**: 低

### input_server.gd
- **职责**: TCP 连接管理层。监听端口，接受连接，转发给 CommandRouter
- **依赖**: 被 bootstrap.gd 条件挂载（窗口模式或 config.input_server.enabled）；内部创建 CommandRouter
- **关键接口**: `setup(config)`, `_process(delta)`
- **修改频率**: 低

### command_router.gd
- **职责**: TCP 命令路由 + 输入事件注入 + play_scenario 执行
- **依赖**: 被 input_server.gd 内部创建；内部创建 UIInspector
- **关键接口**: `setup()`, `handle(raw: String) -> String`
- **支持命令**: click / drag / right_click / get_frame / ui_tree / ui_info / ui_find / hovered / play_scenario / unit_info
- **修改频率**: 中（新增命令时改）

### fault_injector.gd
- **职责**: 故障注入器。按 config.fault_injection 列表在指定帧对单位执行 freeze_nav / restore_all，发射信号
- **依赖**: 被 bootstrap.gd 条件挂载（仅 config.fault_injection 非空时）；通过 units_getter Callable 访问单位列表
- **关键接口**: `setup(units_getter: Callable, fi_config: Array)`, `tick(frame: int)`
- **只读属性**: `injected`, `restored`, `frozen_units`
- **信号**: `fault_injected(unit_id, frame)`, `fault_restored(frame)`
- **修改频率**: 低
- **注意**: 源文件在 `src/shared/ai-renderer/`（通过 symlink 引用）
- **职责**: UI 树查询工具。递归收集 Control 节点并序列化
- **依赖**: 被 command_router.gd 内部创建
- **关键接口**: `get_root()`, `collect_controls(parent, visible_only)`, `serialize(ctrl, include_children)`, `do_ui_tree / do_ui_info / do_ui_find / do_hovered / find_and_click_button`
- **修改频率**: 低

## tests/

### test_runner.gd + test_runner.tscn
- **职责**: 单次 Godot 启动顺序跑完所有 headless 场景，消除 N 次冷启动开销
- **入口**: `godot --headless --path . --scene res://tests/test_runner.tscn`
- **原理**: 挂在场景树根（name="TestRunner"），按序 instantiate 场景，等待 bootstrap 回调 `on_scenario_done()`，收集结果后 free 游戏节点，继续下一场景
- **关键接口**: `on_scenario_done(results: Dictionary)` — 由 bootstrap._finish() 调用
- **场景列表**: `SCENARIO_FILES` 常量，支持两种格式：`.json`（注入主游戏）和 `res://…/scene.tscn`（独立场景）
- **当前 7 个场景**: economy.json / combat.json / interaction.json / smoke_test / archer_vs_fighter / archer_vs_archer / kite_behavior

### tests/scenes/combat_bootstrap.gd（Phase 10 新增）
- **职责**: 独立战斗测试场景公共基类。读 config.json → 按 units 数组生成单位 → 初始化 Calibrator → 帧驱动 → `_finish()`
- **不含**: 地图生成、经济系统、AI 对手（单位直线移动 fallback）
- **关键接口**: `_register_assertions()`（子类可覆盖），`_finish()`，`_abort_scenario(reason)`
- **窗口模式**: 自动创建等距 45° 相机 + DirectionalLight3D + 地面平面（与主游戏视角一致）
- **支持单位类型**: `fighter`（无 arrow_manager 参数），`archer`（注入 arrow_manager）

### tests/scenes/smoke_test/（Phase 10A）
- 2 Fighter 互殴，断言 `battle_resolution`

### tests/scenes/archer_vs_fighter/（Phase 10D）
- 1 Archer(red,x=150) vs 1 Fighter(blue,x=350)，断言 `battle_resolution`

### tests/scenes/archer_vs_archer/（Phase 10D）
- 1 Archer(red) vs 1 Archer(blue)，断言 `battle_resolution`

### tests/scenes/kite_behavior/（Phase 10D）
- 1 Archer(red,x=200) vs 1 Fighter(blue,x=300) 近距，断言 `archer_kite`
- 子类 bootstrap 覆盖 `_register_assertions()`，新增 `_assert_archer_kite()`

### run_scenarios.sh
- **职责**: 串行运行所有场景（每场景一次 Godot 启动），兼容性强，慢
- **用法**: `bash tests/run_scenarios.sh`

### run_scenarios_parallel.sh
- **职责**: 并行运行所有场景（每场景一次 Godot 启动，并发），比串行快 ~N 倍
- **用法**: `bash tests/run_scenarios_parallel.sh`
- **原理**: 为每个场景创建临时项目目录（符号链接 + 独立 config），并行启动多个 Godot 进程
- **注意**: 需要足够内存（每个 Godot 进程约 200MB）

## config.json
- **职责**: 所有游戏参数（地图、单位、物理、渲染器、测试剧本）
- **修改频率**: 中（调参时）
