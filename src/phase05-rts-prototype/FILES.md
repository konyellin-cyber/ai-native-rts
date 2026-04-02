# Phase 0.5 RTS 原型 — 文件说明

> **维护规范**：新增、删除、重命名文件时，必须同步更新本文件。每个文件条目包含：文件名、职责、依赖关系、关键接口。

## 目录结构

```
phase05-rts-prototype/
├── project.godot          # Godot 项目配置
├── config.json            # 运行时参数（地图/单位/物理/渲染器/测试剧本）
├── main.tscn              # 入口场景（Camera2D + Bootstrap 节点）
├── FILES.md               # 本文件 — 项目文件索引
├── scripts/               # 游戏逻辑脚本
│   ├── bootstrap.gd       # 主控脚本
│   ├── unit.gd            # 单位实体
│   ├── selection_box.gd   # 框选 UI
│   └── selection_manager.gd  # 选中管理
├── tools/                 # 开发工具（AI Renderer）
│   └── ai-renderer/
│       ├── ai_renderer.gd       # 入口
│       ├── sensor_registry.gd   # 采集
│       ├── formatter_engine.gd  # 格式化
│       ├── calibrator.gd        # 校准
│       └── simulated_player.gd  # 模拟玩家（v2）
└── tests/                 # 测试脚本和输出
    ├── test_ai_debug.sh        # Bug 注入测试
    ├── test_ai_understand.sh   # AI 理解验证
    └── output/                 # 测试日志输出目录
```

## 根目录文件

### `project.godot`
Godot 4 项目配置文件。定义渲染管线、物理参数、输入映射、自动加载等。
- **修改频率**：低（通常只在项目初始化时修改）

### `config.json`
运行时驱动配置。所有场景参数从此文件读取，不硬编码。
- **地图**：`map.width` / `map.height`
- **障碍物**：`obstacles[]` — `{x, y, w, h}`
- **单位**：`units` — 两队数量、出生点、半径、速度、HP、攻击参数
- **物理**：`physics.fps` / `physics.total_frames`
- **渲染器**：`renderer` — 模式 / 采样率 / 是否校准
- **测试剧本**：`test_actions[]` — SimulatedPlayer 操作序列（v2），每项 `{frame, action, params}`
- **修改频率**：高（调参、测试、Bug 注入时频繁修改）

### `main.tscn`
最小入口场景。仅包含 Bootstrap 节点作为脚本挂载点，所有游戏对象由 `bootstrap.gd` 代码动态创建。

## `scripts/` — 游戏逻辑

### `bootstrap.gd`
**职责**：项目主控。读 config → 创建地图/障碍物/导航/单位 → 管理交互子系统 + AI Renderer → headless 模式跑 Calibrator 断言 + SimulatedPlayer。

**依赖关系**：
- 读取 `config.json`
- 实例化 `scripts/unit.gd`
- 调用 `tools/ai-renderer/ai_renderer.gd`
- 实例化 `scripts/selection_box.gd` + `scripts/selection_manager.gd`（所有模式）
- 实例化 `tools/ai-renderer/simulated_player.gd`（headless 模式）

**关键状态**：
- `units: Array[CharacterBody2D]` — 所有存活单位（死亡后由 `_clean_dead_units()` 移除）
- `frame_count: int` — 当前帧号
- `_red_alive / _blue_alive: int` — 双方存活数
- `_kill_log: Array[Dictionary]` — 击杀记录
- `_sel_box / _sel_mgr` — 交互子系统引用
- `_sim_player` — SimulatedPlayer 引用（headless）

**关键接口**：
- `_physics_process()` — 所有模式清理死亡单位；headless 推进帧、tick SimulatedPlayer、触发 renderer.tick()
- `_on_unit_died()` — 死亡回调：更新存活数、注销 renderer、记录击杀
- `_create_interaction()` — 所有模式创建 SelectionBox + SelectionManager（headless 跳过视觉节点）
- `_create_visuals()` — 窗口模式创建 Camera
- `_setup_calibrator()` — 注册 9 个 Calibrator 断言函数（原 6 + v2 新增 3）
- `_on_move_command()` — 移动命令回调：is_instance_valid 检查后转发，窗口模式创建标记

**Calibrator 断言一览**：

| 断言名 | 类别 | 触发条件 | 检查内容 |
|--------|------|---------|---------|
| `team_groups` | 战斗 | 第 1 帧 | 红队 ∈ team_red，蓝队 ∈ team_blue |
| `chase_convergence` | 导航 | 180 帧 | 双方中心距离缩短 |
| `combat_kills` | 战斗 | 600 帧 | 至少 1 次击杀 |
| `battle_resolution` | 战斗 | 持续 | 一方被消灭或 ≥15 击杀 |
| `renderer_combat_data` | 数据 | 120 帧 | snapshot 包含 hp + team_name |
| `formatter_output` | 数据 | 65 帧 | 输出包含 kills= 和 alive |
| `node_lifecycle_integrity` | 生命周期（v2） | 持续 | ref_holder 中无无效引用 |
| `select_after_death` | 交互（v2） | 300 帧 | 战斗中框选数 == 存活数 |
| `move_cmd_integrity` | 交互（v2） | 持续 | 移动命令只发给有效单位 |

### `unit.gd`
**职责**：单个单位的 AI 状态机 + 寻路 + 战斗。

**状态流转**：
```
wander ──发现敌人──▶ chase ──进入射程──▶ attack
  ▲                    │                     │
  └────丢失目标─────────┘                     │
  └────目标死亡───────────────────────────────┘
                         │
                      HP≤0 → dead → queue_free
```

**依赖关系**：
- `NavigationAgent2D`（子节点）— 寻路
- Godot Group：`team_red` / `team_blue` / `units` — 敌人索敌
- 信号 `died(unit_id, team)` — 通知 bootstrap

**关键属性**：
- `_state` / `ai_state` — AI 状态（wander/chase/attack/dead），通过 setter 同步
- `hp` / `max_hp` — 生命值
- `attack_damage` / `attack_range` / `sight_range` / `attack_cooldown` — 战斗参数
- `_target` — 当前追击/攻击的目标引用
- `_enemy_group` — 敌方 group 名（`team_blue` if red, else `team_red`）

**关键接口**：
- `_physics_process()` — 状态机驱动
- `take_damage(amount)` — 受伤入口
- `_die()` — 死亡处理：设状态 → 发信号 → `queue_free.call_deferred()`
- `move_to(target_pos)` — 玩家命令：中断当前状态，设导航目标
- `get_unit_state()` — 返回完整状态字典（供调试/AI 读取）
- `get_ai_state()` — 返回当前 AI 状态字符串

### `selection_box.gd`
**职责**：鼠标左键拖拽绘制半透明框选矩形。支持 headless 模式（跳过视觉，仅发射信号）。

**依赖关系**：
- 无外部依赖，纯输入处理
- 被 `bootstrap.gd` 实例化

**关键接口**：
- 信号 `selection_rect_drawn(rect: Rect2)` — 拖拽结束时发射框选区域
- `set_headless(enabled)` — 设置 headless 模式（跳过视觉节点创建和 _input）
- `simulate_drag(start, end)` — 程序化框选（供 SimulatedPlayer 调用）
- 最小拖拽阈值 5px，避免误触

### `selection_manager.gd`
**职责**：管理单位选中状态：框选检测、高亮显示、移动命令转发。支持 headless 模式（跳过 Label/高亮，保留选中逻辑）。

**依赖关系**：
- 信号输入：`SelectionBox.selection_rect_drawn`
- 信号输出：`units_selected(Array)` — 通知 bootstrap
- 信号输出：`move_command_issued(target, units)` — 通知 bootstrap
- 内部维护 `_all_units: Array[CharacterBody2D]` — 缓存所有单位引用

**关键接口**：
- `setup(selection_box)` — 连接框选信号
- `set_headless(enabled)` — 设置 headless 模式（跳过 Label/高亮创建）
- `get_all_units()` — 返回当前单位列表副本（供 ref_holder 检查）
- `simulate_right_click(target)` — 程序化右键移动命令（供 SimulatedPlayer 调用）
- `_on_selection_rect(rect)` — 框选回调：过滤无效引用 → 区域检测 → 高亮
- `_collect_units()` — `_ready()` 时扫描场景收集所有 CharacterBody2D

**交互指标**（供 Sensor Registry / SimulatedPlayer 采集）：
- `last_select_count` — 最近一次框选选中的单位数
- `last_invalid_refs` — 最近一次框选时过滤掉的无效引用数
- `last_move_commands` — 最近一次移动命令的目标单位数
- `total_errors` — 累计错误数

**已知问题（已修复）**：
- `_all_units` 在单位 `queue_free` 后仍持有无效引用 → 导致框选失效
- 修复：每次框选前调用 `_all_units.filter(func(u): return is_instance_valid(u))`

## `tools/ai-renderer/` — AI Renderer 管线

### `ai_renderer.gd`
**职责**：AI Renderer 入口。管理子模块生命周期，提供简洁的注册/采集/校准 API。v2 支持 ref_holder 注册和健康度数据传递。

**依赖关系**：
- 内部实例化 `sensor_registry.gd` / `formatter_engine.gd` / `calibrator.gd`
- 被 bootstrap.gd 调用

**关键接口**：
- `register(entity_id, node, fields)` — 注册观测对象
- `unregister(entity_id)` — 注销（单位死亡时调用）
- `register_ref_holder(name, getter)` — 注册引用持有者（v2），getter 返回 Array
- `add_assertion(name, check_fn)` — 添加 Calibrator 断言
- `set_extra(data)` — 设置额外数据（存活数、击杀数、交互指标等）
- `tick()` — 采集 + 健康度检查 + 格式化 + 校准
- `print_results()` — 输出 Calibrator 最终结果
- `get_snapshot()` — 获取最近一次采集快照
- `get_health()` — 获取最近一次 ref_holder 健康度检查结果
- `last_output: String` — 最近一次格式化输出

### `sensor_registry.gd`
**职责**：采集注册表。管理观测对象和引用持有者，按配置频率采集数据。v2 支持 ref_holder 生命周期检查。

**依赖关系**：
- 被 ai_renderer.gd 调用
- 通过 `node.get(field)` 采集节点属性

**关键接口**：
- `register(entity_id, node, fields)` — 注册节点及采集字段
- `unregister(entity_id)` — 移除注册（单位死亡时）
- `register_ref_holder(name, getter)` — 注册引用持有者（v2），getter 返回 Array[Node]
- `tick()` — 每帧调用，按 sample_rate 频率执行 collect + check_ref_holders
- `collect()` — 遍历所有注册节点，采集指定字段，返回 `{tick, entities}`
- `check_ref_holders()` — 检查所有 ref_holder 的无效引用，返回 `{holders, total_invalid}`
- `get_snapshot()` — 获取最近一次采集结果
- `get_health()` — 获取最近一次健康度检查结果
- `get_count()` — 当前注册节点数

**内部机制**：
- `collect()` 中自动检查 `is_instance_valid(node)`，无效节点自动移除
- `check_ref_holders()` 对每个 ref_holder 返回的 Array 检查每个元素的 `is_instance_valid`

### `formatter_engine.gd`
**职责**：将采集数据转为 AI 可读的结构化文本。v2 增加交互健康度和引用健康度段落。

**依赖关系**：
- 被 ai_renderer.gd 调用，接收 snapshot + extra 数据

**输出格式**：
```
[TICK {N}] {alive} alive ({R}R / {B}B) kills={K} total=({RA}/{BA})
  states: {state}:{count} {state}:{count} ...
  interaction: select={n} invalid={n} move={n} errors={n}
  lifecycle: ok (SelectionManager:0/50)
```

**关键接口**：
- `configure(mode, sample_rate)` — 配置模式和采样率
- `format(snapshot, extra)` — 格式化输出，返回字符串

### `calibrator.gd`
**职责**：校准器。管理断言注册、执行、结果输出。

**依赖关系**：
- 被 ai_renderer.gd 调用
- 断言函数由 bootstrap.gd 定义并注册

**关键接口**：
- `add_assertion(name, check_fn)` — 注册断言（check_fn 返回 `{status, detail}`）
- `tick()` — 推进所有未完成的断言
- `print_results()` — 输出最终结果，格式：`[CALIBRATE] [PASS/FAIL] name: detail`
- `get_results()` — 返回结果字典

**内部机制**：
- `pending` 状态的断言每帧持续检查
- `pass` / `fail` 状态的断言锁定，不再重复执行
- 如果断言在整个测试期间一直是 pending，最终标记为 fail（"assertion never completed"）

### `simulated_player.gd`（v2 新增）
**职责**：数据驱动的操作剧本执行器。在 headless 模式下模拟玩家操作（框选、右键移动），让 AI Renderer 观测交互链路。

**依赖关系**：
- 被 bootstrap.gd 实例化（headless 模式）
- 调用 `selection_box.simulate_drag()` 和 `selection_manager.simulate_right_click()`
- 指标通过 bootstrap 的 `_extra` 传递给 FormatterEngine

**关键接口**：
- `setup(actions, sel_box, sel_mgr, map_w, map_h)` — 初始化（actions 从 config.json 读取）
- `tick(frame)` — 每帧调用，检查是否到触发帧并执行对应动作
- `get_execution_log()` — 返回操作执行记录

**支持的操作**：
- `box_select` — 模拟框选，参数 `rect` 支持 `full_screen` / `top_left` 等预设或 `{x,y,w,h}`
- `right_click` — 模拟右键移动，参数 `target` 支持 `map_center` / `red_spawn` 等预设或 `{x,y}`
- `deselect` — 取消选择

**指标**（通过 `_extra["simulated_player"]` 传递）：
- `last_select_count` — 最近框选选中的单位数
- `last_invalid_refs` — 最近框选时过滤掉的无效引用数
- `last_move_commands` — 最近移动命令的目标单位数
- `last_errors` — 累计错误数

## `tests/` — 测试脚本

### `test_ai_debug.sh`
Bug 注入测试脚本。修改 config 参数 → headless 运行 → 捕获输出 → 恢复 config。
- 用法：`./test_ai_debug.sh [sight_range_zero|attack_damage_zero|speed_zero]`
- 依赖：`jq`（JSON 处理）、Godot CLI
- 输出到 `tests/output/`

### `test_ai_understand.sh`
正常战斗日志采集脚本。用于 AI 理解验证（将日志喂给 AI，检查 AI 能否描述战况）。
- 输出到 `tests/output/battle_normal.log`

### `output/`
测试日志输出目录。包含：
- `battle_normal.log` — 正常战斗日志
- `debug_*.log` — 各 bug 注入场景的日志
- `config_backup.json` — Bug 注入测试时备份的原始配置
