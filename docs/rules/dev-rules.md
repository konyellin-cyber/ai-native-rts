# AI Native RTS 开发规范

## 1. 娱乐优先原则

- **快乐 > 进度**。任何时刻觉得不快乐，可以停下来，不需要理由。
- **可玩 > 完美**。先让它跑起来，再让它好看/好用。
- **完成 > 完善**。一个能玩的丑 demo 胜过一个完美的半成品。
- 每次开发结束前，确保项目处于"能跑"的状态（main 分支永远可运行）。

## 1.5. 开发流程

- **设计 → checklist → 代码**：非 trivial 改动（新模块、架构调整）必须先写设计文档到 `docs/design/`，更新 checklist，再编码
- **设计文档用抽象描述**：流程图、架构图、接口定义，不写代码/伪代码
- **trivial 改动可跳过设计**：bug 修复、小参数调整、格式修正直接改
- **checklist 是活的**：方案变更时同步更新描述，完成时立即勾选

## 2. 代码规范

### GDScript 风格
- 类名用 PascalCase：`BallController`、`StateExporter`
- 变量/函数用 snake_case：`frame_count`、`export_state()`
- 常量用 UPPER_SNAKE_CASE：`MAX_BALLS`、`EXPORT_INTERVAL`
- 信号用过去式：`ball_collided`、`state_changed`
- 每个脚本文件一个类，文件名 = 类名（小写）：`ball_controller.gd` → `class_name BallController`
- 函数超过 20 行必须拆分
- 不写注释解释"做了什么"，写注释解释"为什么这样做"

### 项目结构约定
- 配置文件用 JSON，不放硬编码
- GDScript 脚本放 `scripts/`，测试脚本放 `tests/`
- 运行时输出（frames/、screenshots/）永远不提交
- 每个 Phase 的代码独立目录，不互相引用

### 文件说明维护规则（FILES.md）

每个 Phase 目录下维护一个 `FILES.md`，作为项目的"可搜索索引"。

**必须包含的信息**：
- 每个文件的**职责**（一两句话说明"这个文件做什么"）
- **依赖关系**（这个文件依赖谁、被谁依赖）
- **关键接口**（对外暴露的公开函数/信号/属性）
- **修改频率**（低/中/高）和修改场景（什么时候会改这个文件）
- 已知问题或注意事项（如有）

**维护时机**：
- **新增文件** → 立即在 FILES.md 中添加条目（完成代码后、提交前）
- **删除/重命名文件** → 立即同步 FILES.md
- **新增公开接口/信号** → 更新对应文件的"关键接口"段落
- **修复 bug** → 在对应文件条目中记录问题和修复方式（帮助 AI 了解历史）

**不需要记录的**：
- 内部私有函数的实现细节
- 临时的调试代码
- 纯视觉效果相关的内容

**AI 协作收益**：
- AI 可以快速定位"哪个文件负责什么"，不需要全项目 grep
- 新对话开始时读 FILES.md 就能获得项目全貌
- 避免因不了解文件职责而改错文件

## 3. AI 协作模式

### 让 AI 自主 debug 的前提
- 所有 AI 需要调试的场景，必须有结构化数据导出（state_exporter）
- 描述 bug 时带上具体数据：帧号、位置、状态值，不要用模糊描述
- 给 AI 的上下文要包含：config.json + 相关 GDScript + 导出的 frame JSON

### AI 写代码的规则
- AI 生成的代码必须逐行 review，不盲信
- 不直接接受 AI 的"重构建议"，除非当前有明确的痛点
- AI 建议的第三方库/插件，先验证是否仍在维护、是否有 Godot 4 兼容版本

### 对话效率
- 一个对话只解决一个问题/一个 bug
- 复杂功能先在对话中讨论方案，确认后再让 AI 写代码
- AI 给出的代码有问题时，贴回完整上下文（不要只贴报错行）

## 4. Git 习惯

- **小步提交**：每个独立功能/修复一个 commit，不要攒大 commit
- **commit message 格式**：`类型: 简短描述`
  - 类型：`feat`（新功能）、`fix`（修复）、`refactor`（重构）、`test`（测试）、`chore`（杂项）
  - 示例：`feat: 添加碰撞后变色逻辑`、`fix: 修复导出 JSON 帧号不连续`
- **不提交运行时产物**：frames/、screenshots/、*.import
- **不提交 IDE 配置**：.godot/ 目录（Godot 编辑器缓存）
- **实验性代码放分支**：`try/xxx` 分支，验证通过再合入 main

## 5. Checklist 维护规则

- **完成即更新**：每完成一个 checklist 项，立即在 `docs/implementation-plan.md` 中勾选 `[x]`
- **遇阻即记录**：遇到问题导致某步无法继续，在对应项后追加说明，例如：
  - `[ ] **0.3** 编写 bootstrap.gd — ⚠️ Godot 4 的 RigidBody2D API 和 3 不兼容，需要查文档`
- **方案变更即更新**：如果某步的实现方案和原计划不同，更新描述反映实际情况
- **不需要每次 git sync**：checklist 更新可以攒几次一起提交，但不应该超过一个开发session

## 6. 验证习惯

- **程序化验证为默认方式**：所有功能验证优先用 headless 自动化测试（模拟输入 → 检查状态断言 → 输出 `[PASS]`/`[FAIL]`）
- **断言通过 `get_unit_state()` 或直接读节点状态**，不依赖截图
- 每次改动后跑一遍 headless 确认没崩：`godot --headless --path ./src/phase05-rts-prototype`
- 改了数据导出格式，跑一次确定性验证确认输出没变
- 改了物理参数，同时更新 config.json 的注释说明为什么改
- 任何"应该没问题"的改动，都要跑验证脚本确认

### 6.1 Headless 自动闭环

当实现步骤可以通过 headless 运行闭环验证时，**直接运行，不询问用户确认**。

**验证命令决策树（硬约束）**：

```
当前处于某 phase 开发中间步骤？
  → 使用 --phase N（快速，只跑当前 phase 相关场景）

当前执行 checklist 中标注"收尾全量回归"的步骤？
  → 使用无参数全量命令

需要验证单个场景？
  → 使用 --scene 场景名
```

**三档命令速查**（在 `src/phase1-rts-mvp` 目录下执行）：

```bash
# 开发中：只跑当前 phase（快速，~15-50s）
godot --headless --path . --scene res://tests/test_runner.tscn -- --phase N

# 单场景（最快，~5s）
godot --headless --path . --scene res://tests/test_runner.tscn -- --scene 场景名

# 收尾全量（提交前，~160s）
godot --headless --path . --scene res://tests/test_runner.tscn
```

**窗口场景入口**（需要显示环境，从 scene_registry.json 的 window_mode:true 条目读路径）：

```bash
# 将领目视演示
godot --path . --scene res://tests/gameplay/general_visual/scene.tscn

# 窗口交互测试
godot --path . --scene res://tests/core/window_interaction/scene.tscn
```

**AI 执行规则**：
- 开发中间步骤默认用 `--phase N`，不主动跑全量
- 只有 checklist 明确标注"收尾全量回归"时才用无参数全量
- 全量回归结果是 17/17 PASS 才算完成

### 6.2 窗口验证规则

窗口模式有两层验证，均通过自动剧本（SimulatedPlayer）驱动，无需手动操作：

**层 1：程序化断言（WindowAssertionSetup）**
- 与 headless 断言平行，专门验证"只有窗口模式才初始化的东西"
- 输出同样的 PASS/FAIL，可以自动判定
- 典型检查：Camera3D 属性、MeshInstance3D 子节点存在、UI 可见状态、初始状态无意外选中
- 实现：`window_assertion_setup.gd`，由 bootstrap 在非 headless 模式下注册

**层 2：事件驱动截图（UXObserver）**
- 在"靠属性检查无法覆盖"的关键时刻自动截图，供人工 review
- 触发信号：`prod_panel_shown`、`selection_rect_drawn`、`battle_first_kill`、`game_over`
- 截图是**临时手段**，目标是将能转化的 A 类检查（截图留证）逐步转为 B 类程序化断言

**截图与日志的定位习惯（硬约束）**：

每张截图必须在 `window_debug.log` 中有一条对应的锚点行，格式为：

```
  ux_screenshots:
    #帧号 [event:信号名] → 文件名   ← 信号触发截图
    #帧号 [auto] → 文件名           ← 定时截图
```

使用方式：
1. **从截图找日志**：截图文件名包含帧号（如 `ux_prod_panel_shown_f423.png`），在日志中搜索 `[TICK 423]` 即可定位对应的游戏状态
2. **从日志找截图**：看到 `ux_screenshots:` 块，直接知道哪帧保存了什么截图、原因是什么，无需猜测
3. **每张截图都要有日志**：不允许有"没有日志对应行"的截图存在；若截图系统与日志系统解耦运行，截图写入后必须在下一帧日志中补写锚点

**验证分级原则（硬约束）**：
1. **能程序化就不截图**：凡是能读节点属性/状态得出 yes/no 的，必须写成断言，不截图了事
2. **截图只是过渡**：每张事件截图背后要标注"何时可以转为程序化断言"，不允许截图永久替代断言
3. **终极目标是 headless**：窗口断言如果只依赖节点属性而非渲染结果，应迁移到 headless 场景
4. **新增视觉检查时先问**：是否有对应的结构/属性可以程序化验证？先列举再决定是否截图

**流程**：
1. 启动窗口模式（SimulatedPlayer 自动走剧本）
2. WindowAssertionSetup 输出 PASS/FAIL
3. UXObserver 在关键信号触发时截图
4. 发现问题 → 记录到 checklist → 回到 headless 流程修复

**输出物**：checklist 新增项，格式为 `[ ] **xA.x** 问题描述（发现方式：窗口程序化 / 窗口截图）`

### 6.3 测试单元规范（硬约束）

**完整测试单元 = 一个 `.tscn`（世界结构）+ 一个 `scenario.json`（剧本 + 断言）**，两者必须成对，放在同一目录下。详见 [测试架构设计文档](../design/tech/test-architecture.md)。

**场景登记表**：`scene_registry.json` 是唯一权威场景登记表，`test_runner.gd` 在启动时从该文件读取场景列表。

```
硬规则：
  ✅ 新增场景 → 在 scene_registry.json 中追加条目
  ✅ 升级场景 → 新 scenario.json 声明 covers 字段后，才允许替换旧条目
  ❌ 禁止从 scene_registry.json 中删除条目（无覆盖声明时）
  ❌ 禁止 Agent 同时删除场景文件 + 从登记表中移除条目（需用户确认）
```

**两种运行环境**：
- Headless 场景：验证游戏逻辑（AI / 经济 / 战斗），`scenario.json` 中 `window_mode: false`
- Window 场景：验证交互行为（框选 / 点击 / UI），`scenario.json` 中 `window_mode: true`

**全量回归 = 跑登记表中当前所有场景**，随 Phase 演进动态更新，不存在"永久保留的历史场景"概念。

### 6.3 AI 执行权限边界

**AI 可自行执行（无需确认）**：
- headless 验证：`godot --headless --path ...`
- 测试脚本：`tests/*.sh`
- 文件/代码修改（项目目录内）
- checklist 更新
- 本地知识库更新

**需用户确认**：
- 窗口模式运行（GUI 操作）
- git commit / push（对外仓库）
- 修改项目目录外文件
- 删除非临时文件
- 长时间运行任务（> 60 秒）

## 7. 模型切换规则

- **截图验证降级为可选**：不强制切换多模态模型，程序化验证能覆盖的就不截图
- **视觉验证仅在必要时使用**：当需要验证 UI 渲染效果（如颜色、动画、布局）且无法程序化验证时，才截图 + 切换多模态模型
- **切回默认模型继续编码**：截图验证完成后，立即切回默认模型继续开发

### 7.1 MCP Screenshot Server（AI 多模态视觉闭环）

截图能力属于 Phase1，截图数据在 `src/phase1-rts-mvp/tests/screenshots/`。
通过 MCP Server（`game-screenshot`）读取截图并以 base64 返回，绕过 `read_file` 的多模态限制。

**使用流程**：
1. 需要截图验证时，AI 调用 `game-screenshot` MCP 工具获取截图 base64
2. **当前模型不支持图片时**，AI 应停下来提醒用户切换到多模态模型（如 Claude Sonnet 4）
3. 用户切换模型后，重新调用 MCP 工具获取截图，模型即可"看到"游戏画面
4. 对账截图与 AI debug 日志，完成视觉验证后切回默认模型继续开发

**注意事项**：
- Phase5 及后续 phase 可能没有截图能力（纯 headless），此时只能用程序化验证
- 截图文件名格式为 `ux_auto_f{帧号}.png`，可通过 `filename` 参数指定帧号获取

## 8. 知识库查阅规则（防 API 幻觉）

- **写 GDScript 前必须查阅本地知识库**：涉及 Godot API 时，先读 `docs/knowledge-base/godot-api/` 下对应文件确认 API 签名是否存在、参数是否正确
- **不确认就不写**：对 API 的用法不确定时，用 `web_fetch` 查 Godot 官方文档验证（https://docs.godotengine.org/en/stable/classes/）
- **遇坑即记录**：新踩的坑更新到 `docs/pitfalls.md`，新查到的 API 更新到 `docs/knowledge-base/godot-api/`
- **知识库按需扩充**：遇到新 API 需求时，从官方文档提取关键信息保存到本地，避免重复查询

**知识库目录结构**：
```
docs/knowledge-base/
├── godot-api/                    # Godot API 参考（从官方文档提取）
│   ├── navigation-agent2d.md     # 寻路代理
│   ├── navigation-region2d.md    # 导航区域
│   ├── navigation-polygon.md     # 导航多边形
│   ├── navigation-mesh-source-geometry-data-2d.md
│   ├── characterbody2d.md        # 2D 角色体
│   ├── input-and-mouse.md        # 输入与鼠标事件
│   └── navigation-2d-overview.md # 导航系统概览
└── pitfalls.md                   # 踩坑记录（符号链接至 docs/pitfalls.md）
```

## 9. 两人协作（plancklin + 竹晓）

- 协作模式：两人讨论设计 → 一人操作 AI 实现
- 讨论结果用结构化模板记录，确保 AI 拿到完整上下文
- 不做"沉默的修改"——改了什么、为什么改，在对话或 commit message 里说清楚
- 遇到分歧：先做最小验证，用结果说话，不靠讨论说服
