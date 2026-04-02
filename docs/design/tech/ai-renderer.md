# AI Renderer 设计文档

> AI-Native RTS 项目的核心工具：将游戏内部状态转化为 AI 可读的结构化输出，并提供自动化验证。

## 1. 定位

**AI 的"眼睛"**：替代传统游戏的画面渲染，让 AI 通过结构化文本理解游戏过程。

**不做什么**：
- 不替代 Godot 的渲染管线（人类玩家仍需要画面）
- 不做 AI 决策（只负责观察和报告）
- 不绑定特定游戏类型（设计上通用，实现上先服务 RTS）

## 2. 架构（v2 — 含 SimulatedPlayer）

```
┌─────────────────────────────────────────────────────────────┐
│                      headless 模式                          │
│                                                             │
│  ┌──────────┐  ┌──────────────┐  ┌───────────────────┐     │
│  │ 游戏逻辑  │  │ 交互子系统    │  │  SimulatedPlayer  │     │
│  │ (unit,   │  │ (selection,  │  │  (操作剧本驱动)    │     │
│  │  combat) │  │  move_cmd)   │  │                   │     │
│  └────┬─────┘  └──────┬───────┘  └───────┬───────────┘     │
│       │               │                  │                  │
│       └───────────────┼──────────────────┘                  │
│                       ▼                                     │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                  AIRenderer (入口)                    │    │
│  │                                                     │    │
│  │  ┌─────────────┐  ┌──────────────┐  ┌───────────┐  │    │
│  │  │SensorRegistry│──▶FormatterEngine│  │Calibrator │  │    │
│  │  │  (采集)      │  │  (格式化)     │  │  (校准)   │  │    │
│  │  └─────────────┘  └──────┬───────┘  └───────────┘  │    │
│  │                           │                         │    │
│  └───────────────────────────┼─────────────────────────┘    │
│                              ▼                              │
│                     结构化文本输出                            │
└─────────────────────────────────────────────────────────────┘
```

**v1 → v2 的关键变化**：

| 维度 | v1（Phase 0.5 实现） | v2（SimulatedPlayer 扩展） |
|------|---------------------|--------------------------|
| 观测范围 | 仅游戏实体状态 | 游戏实体 + 交互行为 + 操作结果 |
| 测试模式 | headless 测战斗，窗口测交互 | headless 测一切（含交互链路） |
| Bug 发现 | 引用类 bug 需人工窗口测试 | 引用类 + 逻辑类 + 时序类全部自动化 |
| 扩展性 | 每加一个系统要写内联测试 | 数据驱动的操作剧本 + 通用断言 |

## 3. 模块详解

### 3.1 SensorRegistry（采集注册表）

- 游戏对象创建时注册：`renderer.register("unit_0", unit_node, ["position", "hp", "team", "state"])`
- 每帧（或每 N 帧）采集一次，产出 `Dictionary`
- 采集方式：通过节点的公开属性或 `get(field)` 方法
- 死亡节点自动清理：`collect()` 时检查 `is_instance_valid()`，无效节点自动移除
- 可采集的对象类型：
  - **游戏实体**：unit、building 等场景节点
  - **交互组件**：SelectionManager、SimulatedPlayer 等逻辑节点（暴露状态属性）
  - **引用持有者**（v2）：通过 `register_ref_holder()` 注册，自动检测无效引用

### 3.2 FormatterEngine（格式化引擎）

| 模式 | 触发 | 输出内容 | I/O 开销 |
|------|------|---------|---------|
| `ai_debug` | 每 sample_rate 帧 | 全量状态 + 事件日志 | 中（受 sample_rate 控制） |
| `off` | - | 静默 | 零 |

输出结构（ai_debug 模式）：
```
[TICK {N}] {alive} alive ({R}R / {B}B) kills={K}
  states: {state}:{count} {state}:{count} ...
  interaction: select={n}/{total}_valid move_cmd={n}_received errors={n}
  lifecycle: invalid_refs={n} dead_in_group={n}
```

后续扩展：
- `human_play`：事件驱动 + 每秒摘要（人类玩时减少 I/O）

### 3.3 Calibrator（校准器）

- 断言注册：`renderer.add_assertion("name", check_fn)`
- 断言类型：位置变化、数值范围、事件顺序、交互结果、节点生命周期
- 断言返回格式：`{status: "pass"|"fail"|"pending", detail: String}`
- 每帧 tick 推进，`pending` 的断言持续检查，`pass`/`fail` 终态锁定
- 输出格式：`[CALIBRATE] [PASS] name: detail` 或 `[CALIBRATE] [FAIL] name: detail`

断言分类：

| 类别 | 示例 | 覆盖范围 |
|------|------|---------|
| 战斗断言 | `combat_kills`, `battle_resolution` | 游戏逻辑正确性 |
| 导航断言 | `chase_convergence` | 寻路和移动 |
| 数据断言 | `renderer_combat_data`, `formatter_output` | Renderer 管线完整性 |
| 交互断言 | `select_after_death`, `move_cmd_integrity` | 交互链路正确性（v2） |
| 生命周期断言 | `node_lifecycle_integrity` | 节点引用一致性（v2） |

### 3.4 SimulatedPlayer（模拟玩家，v2 新增）

**定位**：在 headless 模式下模拟玩家操作，让 AI Renderer 的观测范围从"游戏状态"扩展到"交互行为"。

**设计原则**：
- 操作序列是**数据驱动**的（JSON 剧本），不硬编码
- 操作结果注册到 Sensor Registry，与游戏实体统一被观测
- 不模拟显示，只模拟交互逻辑（框选、点击、命令）

**操作类型**：

| 动作 | 参数 | 语义 |
|------|------|------|
| `box_select` | `rect: {x, y, w, h}` 或预设如 `full_screen` | 模拟框选 |
| `right_click` | `target: {x, y}` 或预设如 `map_center` | 模拟移动命令 |
| `deselect` | 无 | 取消选择 |
| `cast_skill` | `skill_id, target` | 模拟技能释放（Phase 1+） |

**操作剧本（config.json 中的 `test_actions`）**：
```json
{
  "test_actions": [
    { "frame": 60, "action": "box_select", "params": { "rect": "full_screen" } },
    { "frame": 62, "action": "right_click", "params": { "target": "map_center" } },
    { "frame": 300, "action": "box_select", "params": { "rect": "full_screen" } }
  ]
}
```

**可扩展性**：新增交互系统时，只需添加操作类型 + 对应断言，不需要改框架。

### 3.5 AIRenderer（入口）

- 创建时传入 config，初始化各子模块
- 提供简洁 API：`register()` / `unregister()` / `tick()` / `print_results()`
- v2 新增：`register_ref_holder()` / `add_assertion()` / `get_snapshot()`
- 游戏代码只与入口交互，不知道子模块实现

## 4. 配置

```json
{
  "renderer": {
    "mode": "ai_debug",
    "sample_rate": 60,
    "calibrate": true
  },
  "test_actions": [
    { "frame": 60, "action": "box_select", "params": { "rect": "full_screen" } }
  ]
}
```

- `renderer.mode`：`ai_debug` / `off`
- `renderer.sample_rate`：采集间隔帧数
- `renderer.calibrate`：是否启用 Calibrator 断言
- `test_actions`：SimulatedPlayer 操作剧本（v2，可选）

## 5. 接入方式

```gdscript
# bootstrap.gd — 初始化
renderer = AIRenderer.new(config.get("renderer", {}))

# 游戏实体注册
renderer.register("Unit_%d" % id, unit, ["unit_id", "team_name", "hp", "ai_state"])

# 引用持有者注册（v2，可选）
renderer.register_ref_holder("SelectionManager", selection_mgr.get_all_units.bind())

# SimulatedPlayer 注册（v2，可选）
var sim = SimulatedPlayer.new(config.get("test_actions", []))
renderer.register("SimulatedPlayer", sim, ["last_select_count", "last_invalid_refs", "last_errors"])

# 断言注册
renderer.add_assertion("combat_kills", _assert_combat_kills)

# 每帧
func _physics_process(delta):
    renderer.set_extra({"red_alive": _red_alive, "blue_alive": _blue_alive, "kill_count": _kill_log.size()})
    renderer.tick()

# headless 结束时
func _exit_tree():
    renderer.print_results()
```

## 6. 设计原则

1. **零侵入**：游戏逻辑不知道 Renderer 的存在
2. **渐进接入**：先接 unit，后接 building/event/interaction
3. **格式可进化**：AI 读懂一种格式后，可调优下一种
4. **信任积累**：校准通过越多，越可以跳过截图验证
5. **headless 优先**：所有测试都应在 headless 模式可运行（v2 新增）
6. **数据驱动**：操作剧本、断言规则都是数据，不硬编码逻辑（v2 新增）

## 7. 版本演进

### Phase 0.5 实现范围（v1）

- SensorRegistry：注册游戏实体，按频率采集
- FormatterEngine：ai_debug + off 两个模式
- Calibrator：6 个战斗/数据断言
- 不做：SimulatedPlayer、交互断言、引用持有者检查

### v2 扩展（SimulatedPlayer）

- headless 模式也创建交互子系统（SelectionManager 等）
- 新增 SimulatedPlayer：数据驱动的操作剧本执行
- 新增交互断言：`select_after_death`、`move_cmd_integrity`
- 新增生命周期断言：`node_lifecycle_integrity`
- Formatter 增加交互健康度和引用健康度段落
- 引用持有者注册机制：`register_ref_holder()`

### v3 扩展（行为语义）

- Formatter 新增 behavior 段：方向分析（`→target`/`←away`/`⊥perp`）、路径效率（`eff=XX%`）、异常标记（`DIVERGING`/`⚠️`）、stuck 检测
- Worker 新增 `target_position` 属性供 Sensor 采集
- `sample_rate` 从 60 降到 10，捕捉帧级行为异常

### v4 扩展（UX Observer + 交互闭环）

窗口模式下新增 UX Observer 观测层，让 AI 能通过结构化日志诊断 UI 交互问题：

- **UX Observer**（`ux_observer.gd`）：输入事件日志、UI 布局快照、视口状态追踪、自动截图
- **MCP Screenshot Server**（`mcp_screenshot_server/`）：Node.js stdio MCP Server，返回截图 base64 供多模态模型分析
- **SimulatedPlayer 交互链路追踪**：操作执行记录 + 信号接收记录，支持 headless 下验证交互链路完整性
- **故障注入框架**（`config.fault_injection`）：数据驱动的导航故障注入/恢复，用于行为 bug 回归测试
- **新增断言**：`interaction_chain`（交互操作全部成功）、`behavior_health`（故障注入后恢复成功）

**关键设计决策**：
- SimulatedPlayer 操作时同步记录到 `_signal_chain`，不依赖窗口模式的 `_input()` 拦截
- 故障注入通过 `freeze_nav` / `restore_all` 两种原语，冻结 = 设 `move_speed=0` + `target_position=自身位置`
- Formatter behavior 段已有的 stuck/效率检测可自然捕获冻结后的异常行为

### v5 扩展（窗口模式自主操作闭环）

> **背景**：v4 的 UX Observer 让 AI 能"看到"窗口模式，但窗口操作仍依赖人工中转（AI 说"请框选 HQ"→ 用户操作 → AI 截图）。v5 新增输入注入能力，实现 AI 自主操作窗口的完整闭环。

- **InputServer**（`input_server.gd`）：Godot 内置 TCP 服务器，监听 `localhost:5555`，接受 JSON 命令并通过 `Input.parse_input_event()` 注入 InputEvent
- **MCP game-control tool**：扩展 MCP server（复用 `game-screenshot` server），新增 `game_control(cmd, params)` 和 `wait_frames(n)` 两个 tool
- **SimulatedPlayer 窗口复用**：同一份操作剧本在 headless 和窗口模式下通用，headless 验证行为逻辑，窗口验证视觉效果

**支持的操作命令**：

| 命令 | 参数 | 语义 |
|------|------|------|
| `click` | `{"pos": [x, y]}` | 在游戏窗口坐标(x,y)发送左键单击 |
| `drag` | `{"from": [x1,y1], "to": [x2,y2]}` | 拖拽选框（模拟框选操作） |
| `right_click` | `{"pos": [x, y]}` | 右键单击（移动命令） |
| `wait_frames` | `{"n": N}` | 等待 N 帧后返回 |

**完整闭环流程**：
```
AI: send_command("drag", {from:[x1,y1], to:[x2,y2]})  →  MCP → Godot TCP → InputEvent
AI: wait_frames(5)
AI: send_command("click", {pos:[x,y]})                 →  MCP → Godot TCP → InputEvent
AI: wait_frames(10)
AI: screenshot()                                        →  MCP screenshot server
AI: read_file("tests/logs/window_debug.log")            →  结构化日志
AI: 分析 → 下一轮操作/完成
```

**关键设计决策**：
- InputServer 是独立 `Node`（非 RefCounted），因为需要 `_process()` 驱动 TCP 轮询
- TCP 端口与 godot 进程同生命周期，随 bootstrap 创建/销毁
- 坐标系统使用 **viewport 坐标**（像素），与用户在窗口中的点击坐标一致
- 协议：一连接一请求，同步模式（client connect → send JSON → recv JSON → close）
- 命令响应包含触发后的帧号，便于与日志行对齐
- 不替代 SimulatedPlayer —— SimulatedPlayer 驱动 headless 行为，InputServer 驱动窗口操作，两者共享操作剧本格式

**TCP 协议细节**：

```
Client                          Godot (port 5555)
  │                                    │
  ├─ TCP connect ─────────────────────▶│
  ├─ {"cmd":"drag","from":[100,600],   │
  │   "to":[300,800]} + \n ───────────▶│
  │                                    │ _process() 检测可用字节
  │                                    │ 解析 JSON → 注入 InputEvent
  │                                    │   1. InputEventMouseButton(pressed=true, pos=from)
  │                                    │   2. InputEventMouseMotion(pos=to)
  │                                    │   3. InputEventMouseButton(pressed=false, pos=to)
  │◀─ {"ok":true,"frame":1234} + \n ─┤
  ├─ TCP close ──────────────────────▶│
  │                                    │
```

**请求格式**：

| cmd | 必需字段 | 可选字段 | 行为 |
|-----|---------|---------|------|
| `click` | `pos: [x, y]` | `button: "left"\|"right"` (默认 left) | 单击：motion → press → delayed release |
| `drag` | `from: [x1,y1]`, `to: [x2,y2]` | — | 拖拽：press(from) → motion(to) → release(to) |
| `right_click` | `pos: [x, y]` | — | 右键单击：motion → press → delayed release |
| `get_frame` | — | — | 返回当前物理帧号（用于等待/对齐） |
| `ui_tree` | — | `visible_only: true` (默认 true) | 列出所有 Control 节点及其属性 |
| `ui_info` | `path: "NodePath"` | — | 查询单个节点的详细 UI 属性 |
| `ui_find` | `type: "Button"` | `visible_only: true` | 按类型查找所有 Control 节点 |

**UI 查询命令详解**（v5.1 新增）：

> **动机**：AI 操作 UI 时需要知道按钮/面板的精确位置，但无法猜测坐标。UI 查询命令让 AI 能实时获取 Control 节点的布局属性（global_rect、size、visible、disabled 等），实现"查询 → 计算坐标 → 操作"的闭环。

`ui_tree` — 遍历 SceneTree 中所有 Control 子节点，返回扁平化列表：
- 每个节点包含：`path`（场景树路径）、`type`（类名）、`global_rect`（位置+尺寸）、`visible`、`disabled`（仅 Button）
- `visible_only=true` 时过滤不可见节点
- 仅遍历 CanvasLayer 下的 UI 子树（排除游戏实体 Node2D）

`ui_info` — 查询单个节点的详细属性：
- 返回：`position`、`size`、`global_position`、`global_rect`、`anchor_left/right/top/bottom`、`z_index`、`visible`、`disabled`、`text`（Label/Button）
- 子 Control 节点列表（递归一层）

`ui_find` — 按类型查找节点：
- `type` 支持 Godot 类名（Button、Label、PanelContainer 等），不区分大小写
- 返回匹配节点列表，格式同 `ui_tree`

**查询响应示例**：
```
请求: {"cmd":"ui_find","type":"Button"}
响应: {
  "ok": true,
  "frame": 500,
  "nodes": [
    {
      "path": "Root/ProdPanel/Panel/VBox/HBoxWorker/WorkerBtn",
      "type": "Button",
      "text": "👷 Worker",
      "global_rect": {"position": [12.0, 58.0], "size": [130.0, 39.0]},
      "visible": true,
      "disabled": false
    },
    ...
  ]
}
```

**典型操作流程**：
```
1. drag 框选 HQ → prod_panel_shown 信号触发
2. ui_find type=Button → 得到 Worker 按钮的 global_rect
3. 计算 center = (x + w/2, y + h/2)
4. click pos=center → Button pressed 信号触发 → produce_requested
```

**响应格式**：`{"ok": true/false, "frame": N, "error": "..."}`

**集成方式**（bootstrap.gd）：
```gdscript
var _input_server: Node = null

func _ready():
    # ...existing init...
    if not is_headless or config.get("input_server", {}).get("enabled", false):
        var InputServerScript = load("res://tools/ai-renderer/input_server.gd")
        _input_server = Node.new()
        _input_server.set_script(InputServerScript)
        _input_server.setup(config.get("input_server", {}))
        add_child(_input_server)
```

### v6 扩展（操作剧本复用 — Scenario Player）

> **背景**：v5 的 InputServer 让 AI 能在窗口模式下自主操作，但 SimulatedPlayer（headless）和 InputServer（窗口）两套操作机制完全独立——同一个测试场景需要写两套操作描述，无法复用。v6 定义统一的剧本格式 + 双通道执行器。

**核心思路**：定义一份统一的 Scenario JSON 格式，SimulatedPlayer 和 InputServer 各自实现播放器来执行同一种抽象动作。

**数据流**：
```
Scenario JSON (tests/scenarios/xxx.json)
    ├── headless 模式 → SimulatedPlayer 播放（直接调用内部 API）
    └── 窗口模式   → InputServer 播放（TCP 命令，外部驱动或剧本模式）
```

**架构**：
```
┌───────────────────────────┐
│   Scenario JSON            │  ← 统一的操作描述
│   actions[] + metadata     │
└──────────┬────────────────┘
           │
      ┌────┴──────┐
      ▼           ▼
┌──────────┐ ┌────────────┐
│SimPlayer │ │InputServer │  ← 各自的执行通道
│(headless)│ │ (window)   │
│ 内部API  │ │ TCP/输入   │
└──────────┘ └────────────┘
```

**剧本文件格式**（`tests/scenarios/*.json`）：
```json
{
  "name": "production_test",
  "description": "验证框选 HQ → 生产 Worker 的完整链路",
  "actions": [
    {"action": "box_select", "params": {"rect": "full_screen"}, "wait_frames": 0},
    {"action": "right_click", "params": {"target": "map_center"}, "wait_frames": 0},
    {"action": "wait_frames", "params": {"n": 1200}},
    {"action": "box_select", "params": {"rect": "red_hq_area"}},
    {"action": "wait_signal", "params": {"signal": "prod_panel_shown", "timeout": 60}},
    {"action": "ui_find", "params": {"type": "Button"}, "save_as": "buttons"},
    {"action": "click_button", "params": {"label": "Worker", "from": "buttons"}},
    {"action": "wait_signal", "params": {"signal": "produce_requested", "timeout": 30}}
  ]
}
```

**新增动作类型**：

| 动作 | 参数 | headless 行为 | 窗口行为 |
|------|------|--------------|---------|
| `wait_frames` | `n: int` | SimPlayer 内部延迟 | 无（TCP 阻塞等待） |
| `wait_signal` | `signal, timeout` | SimPlayer 轮询 bootstrap 信号 | InputServer 轮询后返回 |
| `click_button` | `label, from` | 查找 + 直接调用 produce_cb | ui_find → 计算 center → click |
| `ui_find` | `type, save_as` | 内部 UI 树遍历（headless 无 UI 则跳过） | TCP ui_find 命令 |

**向后兼容**：`config.json` 的 `test_actions` 继续作为默认内嵌剧本。新增可选的 `scenario_file` 字段指向外部 JSON。

**InputServer 新增 `play_scenario` 命令**：
- 请求：`{"cmd": "play_scenario", "file": "res://tests/scenarios/xxx.json"}`
- 行为：加载剧本 → 逐条执行（同步阻塞，每条等待结果再执行下一条）
- 返回：`{"ok": true, "results": [{action, success, frame, detail}], "summary": {...}}`

**SimulatedPlayer 扩展**：
- `setup()` 新增 `scenario_path` 参数，从外部文件加载 actions
- 新增 `wait_frames` / `wait_signal` 动作处理（暂停后续动作执行）
- `click_button` 在 headless 下走 `ui_find` 逻辑（遍历 CanvasLayer Control）或直接调 produce_cb

**关键设计决策**：
- 剧本文件是**声明式**的（描述"做什么"），不绑定具体执行通道
- `wait_signal` 用信号名匹配，不关心是哪个对象发出的（由 bootstrap 统一转发到 SimPlayer）
- `click_button` 是高层抽象——窗口下运行时查找坐标再点击，headless 下直接回调
- 同一剧本可在两种模式下执行，但某些 UI 相关动作在 headless 下会降级或跳过

### 未来扩展（Phase 1+）

- `human_play` 模式：人类玩时低开销采集
- 多 SimulatedPlayer 并发：测试多人同步
- 断言库：常用断言模板化（位置收敛、数值范围、事件序列）
- **事件驱动截图**：UXObserver 按信号白名单在关键时刻自动拍照，文件名含事件语义（见 §8.6）
- **场景化截图配置**：场景 JSON 声明 `screenshot_on_signals`，不同测试场景拍不同关键时刻
- **3D 镜头语义描述**：`camera_3d` 段输出 pos/pitch/ortho_size/ground_view/units_in_view（见 Phase 7 设计文档 §7E）

## 9. 双模式 Debug 体系

### 9.1 两种模式的定位

| 维度 | Headless 闭环 | 窗口 AI Debug |
|------|--------------|---------------|
| **适用场景** | 行为正确性、逻辑回归、性能、资源泄漏 | 视觉 bug、UI 布局、动画效果、交互体验 |
| **触发条件** | 代码改完后自动执行 | headless 通过后 + 有视觉验证需求 / 用户反馈 |
| **验证手段** | 结构化断言（PASS/FAIL）、日志关键词 | 截图 → 多模态模型分析 + 结构化日志 |
| **模型需求** | 纯文本模型（低成本低 token） | 多模态模型（高成本） |
| **能验证** | 行为数据、信号链路、帧级异常 | 视觉外观、布局正确性、动画、对比度 |
| **不能验证** | 任何视觉问题 | 边界条件覆盖（不如 headless 系统化） |

### 9.2 协作流程

```
代码变更
  ↓
Headless 闭环（自动、低成本、必做）
  ├─ PASS → 是否有视觉验证需求？
  │         ├─ 否 → 完成
  │         └─ 是 → 窗口 AI Debug（手动触发、高成本、按需）
  │              ├─ 截图分析 → 有问题 → 记录 bug 描述到 checklist → 回到代码变更
  │              └─ 截图分析 → 没问题 → 完成
  └─ FAIL → 修复 → 重跑（最多 3 轮）
```

**核心原则**：
1. **Headless 是必经关卡**，每次变更都过
2. **窗口多模态是可选关卡**，只在有视觉需求时用
3. **先过 headless 再截图**，避免在行为有 bug 时浪费多模态成本
4. **窗口模式只发现问题**，不做开发 — 描述问题、记录 checklist，回到 headless 修复

### 9.3 窗口模式日志通道

窗口模式下 Formatter 输出到 stdout，AI 无法直接读取。为支持窗口 AI Debug 闭环，Formatter 同时将结构化输出追加到日志文件 `tests/logs/window_debug.log`（ring buffer，保留最近 N 行）。

AI 通过 `read_file` 或 MCP 日志工具读取该文件，获取与截图对应的结构化数据，实现"看画面 + 看数据"的完整诊断。

### 9.4 模型切换策略

| 阶段 | 推荐模型 | 原因 |
|------|---------|------|
| headless 闭环 | 默认文本模型（GLM/GPT-4o-mini） | 断言文本分析，低成本 |
| 窗口截图分析 | 多模态模型（Claude 4.5/GPT-4o） | 需要理解图像 |
| bug 修复编码 | 默认文本模型 | 修复编码不需要视觉能力 |
| 修复后 headless 回归 | 默认文本模型 | 确认修复无回归 |
| 最终视觉验收 | 多模态模型（可选） | 确认修复后视觉效果正确 |

## 8. 改进反思（Phase 2 实践总结）

基于 Phase 0.5 → Phase 1 的实际使用，以下是目前 AI Renderer 的主要不足和改进方向：

### 8.1 Formatter 语义粒度不足

- v3 加了方向/效率，但输出仍是**逐 tick 独立快照**，缺少跨 tick 趋势聚合（如"worker_1 过去 5 秒效率持续下降"）
- stuck 检测阈值硬编码（`accum_distance < threshold`），需要经验值调参，不同移动速度的单位无法用同一阈值
- **改进方向**：引入滑动窗口统计（均值/方差/趋势线），让 Formatter 输出"行为摘要"而非"行为快照"

### 8.2 Calibrator 断言覆盖不足

- 目前 9 个断言偏"存在性"（某事件发生过），缺少"质量性"断言（路径效率、收敛性等 2B.2 规划的还没实现）
- 断言与 Formatter 输出格式耦合较紧——改 Formatter 格式可能破坏断言匹配
- **改进方向**：断言基于结构化数据（snapshot Dictionary）而非文本匹配；增加质量性断言模板

### 8.3 采样策略粗糙

- `sample_rate=10` 是全局固定值，不同阶段需要不同频率（战斗高频、经济巡检低频）
- 采样间隔固定，在帧率波动时可能导致时间间隔不均匀
- **改进方向**：支持按模块/按阶段配置采样率，或基于事件触发采样（如状态变化时额外采样）

### 8.4 调试链路效率低

- 导航 bug 发现用了 3 层排查：语义分析 → sample_rate 调整 → NAV_DEBUG 打印
- AI Renderer 缺少**自动异常归类**能力，无法从异常输出直接定位到根因模块
- **改进方向**：Formatter 输出异常时自动附带上下文（最近 N 帧的历史轨迹、目标位置、导航状态），减少人工逐层排查

### 8.5 缺少趋势可视化

- 纯文本日志难以快速发现长期趋势（经济增速变慢、战斗效率下降）
- 需要人工翻阅大量 tick 输出才能拼凑出完整趋势
- **改进方向**：增加周期性摘要输出（如每 10 秒输出一次趋势摘要），或生成时序数据供外部可视化工具使用

### 8.6 截图与验证目标脱节（窗口模式调试痛点）

**问题**：当前 UX Observer 只有两种截图触发方式：
- 定时自动（每 5 秒），文件名为 `ux_auto_f<帧>.png`
- MCP 手动调用 `take_screenshot`

截图时机与"想验证的事件"完全无关——断言通过、HQ 被摧毁、生产面板弹出，截图都不知道。AI 调试视觉问题时只能靠帧号猜哪张截图对应哪个事件，效率极低。

**根本矛盾**：

| 调试目标 | 现有机制 | 问题 |
|---------|---------|------|
| 逻辑验证 | Calibrator 断言 + headless | ✅ 足够，不需要截图 |
| 视觉验证 | 定时截图 + MCP 手动 | 时机盲目，AI 无法关联事件 |

**改进方向：事件驱动截图**

在 `UXObserver.on_signal()` 里加白名单判断，关键信号触发时自动拍照：

```
# 文件名包含事件语义，AI 直接知道看哪张
ux_battle_first_kill_f3240.png
ux_hq_selected_f1202.png
ux_prod_panel_shown_f1204.png
ux_game_over_red_wins_f5100.png
```

信号白名单（可配置）：

| 信号 | 触发条件 | 视觉验证目的 |
|------|---------|-------------|
| `hq_selected` | HQ 被框选 | 确认生产面板正确弹出 |
| `prod_panel_shown` | 生产面板出现 | 确认按钮可见、布局正确 |
| `unit_produced` | 新单位生产完成 | 确认单位在 HQ 附近生成 |
| `battle_first_kill` | 战斗首次击杀 | 确认战场位置和视觉效果 |
| `game_over` | 游戏结束 | 确认结束画面覆盖正确 |

**实现位置**：`UXObserver.on_signal()` 里增加白名单匹配，命中则调用 `take_screenshot(signal_name)`。白名单通过 config 配置，默认为空（不干扰现有行为）。

**与场景化测试的配合**：场景 JSON 中声明 `screenshot_on_signals` 列表，UXObserver 按场景目标定制截图触发点，不同场景拍不同的关键时刻。

```json
{
  "name": "combat",
  "screenshot_on_signals": ["battle_first_kill", "game_over"]
}
```

