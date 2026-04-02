# 架构重构设计文档

> **适用阶段**：Phase 5（可维护性重构）
> **写于**：2026-03-27
> **背景**：基于 Phase 0–3 的完整演进，总结当前架构痛点并给出 Phase 5 的重构方向。Phase 3 完成前不动代码，Phase 3 结束后按本文档依次实施。

---

## 1. 动机

Phase 1–3 快速迭代后，以下几个问题已经成为继续扩展的主要阻力：

| 问题 | 症状 | 痛点等级 |
|------|------|---------|
| `bootstrap.gd` 上帝类 | 每个新功能都要改 bootstrap，合并冲突频繁 | P0 |
| 断言依赖文本格式 | Formatter 格式升级时断言容易静默失效 | P0 |
| AI Renderer 跨 Phase 复制 | Bug 修复不同步，phase05 与 phase1 已分叉 | P1 |
| SimPlayer/InputServer 职责膨胀 | 单文件超 10KB/20KB，难以独立测试 | P1 |
| 采样策略全局固定 | 经济过采、战斗欠采，截图 I/O 失控 | P2 |
| 故障注入嵌入生产代码 | 测试桩与业务逻辑混杂 | P2 |

---

## 2. 重构目标

1. **修改频率高的文件**，职责收窄到"一件事"
2. **断言逻辑**基于结构化数据，与输出格式解耦
3. **AI Renderer 工具**提升为共享层，Phase 间统一维护
4. **测试基础设施**（故障注入、SimPlayer）与生产代码物理隔离
5. **全程不破坏已有 11/11 headless 断言通过状态**

---

## 3. 子阶段概览

```
Phase 5
├── 5A  Bootstrap 拆分（上帝类 → 4 个聚焦管理器）
├── 5B  断言结构化（文本匹配 → snapshot 字典查询）
├── 5C  AI Renderer 共享化（复制 → shared/ 单一来源）
├── 5D  SimPlayer + InputServer 职责分离
├── 5E  采样策略分级（全局固定 → 模块级配置）
└── 5F  故障注入隔离（生产代码内联 → 独立 TestHarness 节点）
```

---

## 4. 子阶段详细设计

### 4A：Bootstrap 拆分

#### 问题诊断

当前 `bootstrap.gd` 承担 8 类职责：

```
读 config → 创建节点 → 生命周期管理 → 信号路由
→ 断言注册 → SimPlayer 管理 → 故障注入 → UI 事件路由
```

任何新功能都要在这里添加代码，且所有职责全部耦合，无法独立测试。

#### 目标架构

```
bootstrap.gd（主序）
    │  职责：读 config、按顺序创建子管理器、驱动 _physics_process 分发
    │
    ├── GameWorld.gd            ← 实体创建 + 场景树组装
    │    职责：按 config 创建 HQ / mineral / worker / fighter 节点
    │    不知道：Renderer、SimPlayer、断言的存在
    │
    ├── UnitLifecycleManager.gd ← 单位生命周期
    │    职责：_clean_dead_units、alive 计数维护、kill_log
    │    监听：unit.died 信号
    │    暴露：red_alive, blue_alive, kill_count（只读）
    │
    ├── AssertionSetup.gd       ← 断言配置集中地
    │    职责：注册所有 Calibrator 断言
    │    依赖：UnitLifecycleManager（读 alive/kill_count）
    │    不含：任何游戏逻辑
    │
    └── (FaultInjector — 见 5F)
```

#### 接口约定

- `GameWorld` 通过信号通知 bootstrap 实体创建完成（`world_ready`），不直接调用 bootstrap 方法
- `UnitLifecycleManager` 暴露只读属性：`red_alive: int`、`blue_alive: int`、`kill_log: Array`
- `AssertionSetup` 是纯配置对象，`setup(renderer, lifecycle_mgr, sim_player)` 注入依赖，无状态
- `bootstrap` 不再持有任何状态，除"当前 frame_count"和"is_headless"

#### 修改量评估

- 新增文件：3 个（`game_world.gd`、`unit_lifecycle_manager.gd`、`assertion_setup.gd`）
- 删除逻辑：从 bootstrap 抽出约 400 行
- bootstrap 预期行数：从 772 行 → ≤ 150 行
- headless 断言：不变（AssertionSetup 是搬迁，不是重写）

---

### 4B：断言结构化

#### 问题诊断

部分断言通过读 Formatter 输出文本进行匹配，例如：
- 检查是否存在 `"state=harvesting"` 字符串
- 检查 `"kills="` 后面的数字

Formatter 每次格式升级（v1→v6 已升级 6 次），都可能导致断言静默失效（仍返回 `pass` 但基于过时格式）。

#### 目标架构

```
断言函数
    │
    ├── 从 SensorRegistry.get_snapshot() 读取结构化字典
    │       例：snap["worker_0"]["ai_state"] == "harvesting"
    │
    └── 从 UnitLifecycleManager 读取计数属性
            例：lifecycle_mgr.kill_count > 0
```

Formatter 文本输出与断言逻辑完全隔离：改 Formatter 不影响断言，改断言不影响输出格式。

#### 接口约定

- `SensorRegistry` 新增 `get_snapshot() -> Dictionary` 公开接口（已存在，确认 API 稳定）
- 断言函数签名不变：`() -> {status: String, detail: String}`
- 断言函数内部改为查询字典路径，不解析任何字符串

#### 迁移策略

- 逐条迁移，每迁移一条立即跑 headless 确认 PASS
- 基于文本的旧断言删除前保留注释说明"为什么改"
- 新断言优先使用 `snapshot.get(key, default)` 防御式访问

---

### 4C：AI Renderer 共享化

#### 问题诊断

```
src/
  phase05-rts-prototype/tools/ai-renderer/   ← v1-v2 代码
  phase1-rts-mvp/tools/ai-renderer/          ← v1-v6 代码（已分叉）
```

两套代码逻辑相同但已分叉，bug 修复无法同步，Phase 3+ 扩展时会产生第三个拷贝。

#### 目标架构

```
src/
  shared/
    ai-renderer/                 ← 单一来源，含版本标注
      ai_renderer.gd             (v6+)
      sensor_registry.gd
      formatter_engine.gd
      calibrator.gd
      simulated_player.gd        (v6+，见 5D 拆分后)
      input_server.gd            (v5+，见 5D 拆分后)
      ux_observer.gd             (v4+)
      mcp_screenshot_server/
  phase05-rts-prototype/
    tools/ai-renderer/           ← 替换为 symlink 或相对路径引用 shared/
  phase1-rts-mvp/
    tools/ai-renderer/           ← 替换为 symlink 或相对路径引用 shared/
  phase2-.../
    tools/ai-renderer/           ← 直接引用 shared/，不再复制
```

#### Godot 路径处理

Godot 4 的 `res://` 路径不支持 symlink 跨目录，需要选择以下方案之一：

| 方案 | 实现 | 代价 |
|------|------|------|
| **A：工具目录软链接**（推荐） | `phase1/tools/ai-renderer` → `../../shared/ai-renderer` 的符号链接 | macOS/Linux 原生支持，Godot 可正常 resolve |
| B：相对路径 preload | 每个 Phase 内部使用 `preload("../../shared/ai-renderer/xxx.gd")` | 路径字符串需逐文件修改 |
| C：Godot addons 机制 | 将 ai-renderer 作为 plugin 安装 | 成本最高，不适合当前规模 |

推荐方案 A，先在 phase1 验证符号链接可行后再推 phase05。

#### 迁移顺序

1. 创建 `src/shared/ai-renderer/`，将 phase1 的当前代码复制进去（作为 canonical 版本）
2. phase1 的 `tools/ai-renderer/` 替换为 symlink
3. headless 验证 phase1 11/11 PASS
4. phase05 的旧版本归档（加 `_legacy` 后缀）后替换为 symlink
5. headless 验证 phase05 的 9 个断言 PASS

---

### 4D：SimPlayer + InputServer 职责分离

#### 问题诊断

`simulated_player.gd`（10KB）当前职责：
- 剧本调度（按帧派发动作）
- 动作执行（框选/移动/生产）
- UI 查询（遍历 CanvasLayer）
- 信号链路追踪
- 外部剧本文件加载

`input_server.gd`（20KB）当前职责：
- TCP 服务器（连接管理 + 协议解析）
- 命令路由（game_control / ui_query / scenario）
- UI 节点查询
- 剧本播放器（play_scenario 命令）
- 诊断命令处理

#### 目标架构

```
SimulatedPlayer 拆分
├── simulated_player.gd    ← 只做剧本调度：加载 JSON、按帧 tick 派发动作类型
├── action_executor.gd     ← 只做动作执行：框选/移动/生产的具体实现，无状态
└── signal_tracer.gd       ← 只做信号追踪：记录 record_signal，供断言读取

InputServer 拆分
├── tcp_server.gd          ← 只做 TCP：连接管理、JSON 解析/序列化、帧号附加
├── command_router.gd      ← 只做路由：cmd 字段 → 对应处理函数的分发表
└── ui_inspector.gd        ← 只做 UI 查询：ui_tree/ui_find/ui_info 三个命令实现
```

#### 接口约定

- `SimulatedPlayer` 依赖注入 `ActionExecutor` 和 `SignalTracer`，不直接操作 UI
- `TcpServer` 只知道"收到一个 Dictionary，返回一个 Dictionary"，不知道命令语义
- `CommandRouter` 持有对 `UiInspector` 和 `ActionExecutor` 的引用
- 拆分后各文件目标 ≤ 200 行

---

### 4E：采样策略分级

#### 问题诊断

`config.json` 的 `renderer.sample_rate: 10` 对所有传感器统一生效：
- 经济状态（crystal 变化）：每帧变化 < 1%，10 帧采样 → 90% 冗余输出
- 战斗状态（HP 变化）：每帧都可能有关键变化，10 帧采样 → 可能漏报击杀时刻
- 截图：1080 张累积，I/O 压力明显

#### 目标配置结构

```json
{
  "renderer": {
    "sensors": {
      "economy": { "sample_rate": 60, "priority": "low" },
      "combat":  { "sample_rate": 3,  "priority": "high" },
      "units":   { "sample_rate": 10, "priority": "medium" },
      "ui":      { "sample_rate": 0,  "priority": "event" }
    },
    "event_triggers": ["unit_died", "hq_destroyed", "battle_started", "produce_requested"],
    "screenshot_interval": 15.0
  }
}
```

#### SensorRegistry 扩展

- `register()` 新增可选 `sample_group: String` 参数（默认 `"units"`）
- `collect()` 按 group 查表获取采样率，不再全量同频采集
- `event_triggers` 触发时立即采集一次，不受 sample_rate 限制

#### 向后兼容

旧的 `sample_rate: 10` 字段继续有效，作为所有 group 的默认值，新 `sensors` 字段覆盖特定 group。

---

### 4F：故障注入隔离

#### 问题诊断

当前故障注入代码（`_setup_fault_injection`、`_process_fault_injection`、`_freeze_unit_nav`、`_restore_all_units`）直接写在 `bootstrap.gd` 中，通过 `config.fault_injection` 条件激活。生产代码路径中存在测试桩。

#### 目标架构

```
FaultInjector.gd（独立 Node）
    │  只在测试场景下挂载，生产场景树中不存在
    │
    ├── setup(units_getter: Callable, config: Dictionary)
    │       → units_getter 是一个返回当前 units 列表的回调，延迟绑定
    │
    ├── _process()
    │       → 独立驱动，不依赖 bootstrap._physics_process
    │
    └── 信号：fault_injected(frame, action)，fault_restored(frame)
            → AssertionSetup 通过信号判断 behavior_health 断言状态
```

#### 接入方式

- bootstrap 中完全移除故障注入相关代码
- 测试脚本（`tests/test_ai_debug.sh`）在启动 Godot 时通过 `--headless` + 特定 config 触发，config 中保留 `fault_injection` 字段
- Godot 启动后，由 `main.tscn` 的条件节点（根据 `config.fault_injection` 是否非空）决定是否挂载 `FaultInjector` 节点

---

## 5. 实施顺序与依赖关系

```
5A（bootstrap 拆分）
    │ ← 必须最先做：所有其他子阶段都受益于 bootstrap 瘦身
    ▼
5B（断言结构化）
    │ ← 依赖 5A 的 AssertionSetup 已分离
    ▼
5C（AI Renderer 共享化）
    │ ← 可以与 5B 并行，但建议在 5A 之后，避免迁移时代码还在动
    ▼
5D（SimPlayer/InputServer 拆分）
    │ ← 依赖 5C 完成（在 shared/ 中拆分，不在 phase1/ 中拆分）
    ▼
5E（采样分级）
    │ ← 可以独立做，config 改动向后兼容
    ▼
5F（故障注入隔离）
        ← 可以独立做，改动范围最小
```

---

## 6. 验证策略

每个子阶段完成后，必须满足：

1. **headless 回归**：`godot --headless --path ./src/phase1-rts-mvp` → 11/11 PASS
2. **无性能回归**：avg_fps ≥ 58（当前 60.1fps，允许 3% 误差）
3. **FILES.md 同步**：新增/删除/重命名的文件立即更新

不做：
- 不在重构期间同时修改游戏逻辑（单一变量原则）
- 不跳过任何子阶段的 headless 验证直接进入下一个

---

## 7. 风险记录

| 风险 | 概率 | 影响 | 缓解方案 |
|------|------|------|---------|
| Godot symlink 跨目录 resolve 失败 | 中 | 5C 被阻塞 | 先小范围测试；失败则退回方案 B |
| bootstrap 拆分后 _physics_process 时序改变 | 低 | 11 个断言失效 | 每次提取一个子模块后立即 headless 回归 |
| AssertionSetup 迁移时遗漏状态变量 | 中 | 断言静默 fail | 逐条迁移 + 对比旧断言输出 |
| 5E 采样分级导致某些断言窗口不足 | 低 | 断言超时 pending → fail | 先在单测中验证采样率，再修改 config |
