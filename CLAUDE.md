# AI Native RTS 开发规范

> 本文件是项目级规则，CodeBuddy / Claude Code 进入本项目目录时自动加载。
> 完整规范原文：`docs/rules/dev-rules.md`

---

## 1. 开发流程（硬约束）

- **设计 → checklist → 代码**：非 trivial 改动（新模块、架构调整）必须先写设计文档到 `docs/design/`，更新 `docs/phases/roadmap.md` 对应 Phase 的 checklist，再编码
- **设计文档用抽象描述**：流程图、架构图、接口定义，不写代码/伪代码
- **trivial 改动可跳过设计**：bug 修复、小参数调整、格式修正直接改
- **完成即更新 checklist**：每完成一个步骤，立即在 `docs/phases/<phaseN>/checklist.md` 中勾选 `[x]`，不积攒
- **AI 生成的代码必须逐行 review**，不盲信；不接受 AI 重构建议，除非有明确痛点
- **一个对话只解决一个问题**；复杂功能先讨论方案确认后再实现

---

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

### FILES.md 维护规则
每个 Phase 目录下维护一个 `FILES.md`：
- **新增文件** → 立即在 FILES.md 中添加条目（完成代码后、提交前）
- **删除/重命名文件** → 立即同步 FILES.md
- **新增公开接口/信号** → 更新对应文件的"关键接口"段落
- **修复 bug** → 在对应文件条目中记录问题和修复方式

---

## 3. Git 习惯

- **小步提交**：每个独立功能/修复一个 commit，不要攒大 commit
- **commit message 格式**：`类型: 简短描述`（feat / fix / refactor / test / chore）
- **不提交运行时产物**：frames/、screenshots/、*.import
- **不提交 IDE 配置**：.godot/ 目录

---

## 4. 验证习惯（硬约束）

- **程序化验证为默认方式**：优先用 headless 自动化测试，不依赖截图
- **每次代码变更后必须跑 headless 回归**：`godot --headless --path ./src/phase1-rts-mvp`
- **全部 PASS 才算完成**，有 FAIL 必须修复，不得带 FAIL 进入下一步
- **headless 自动闭环**：验证结果可判定时直接运行（无需确认）→ 分析输出 → 有 FAIL 自动修复重验（最多 3 轮）→ 全部通过后汇报
- **窗口模式也要程序化**：窗口验证通过 SimulatedPlayer 自动走剧本 + WindowAssertionSetup 断言，输出 PASS/FAIL；不依赖手动操作
- **截图是过渡手段**：事件驱动截图只用于"暂时无法程序化"的视觉检查，每张截图背后需标注"何时可转为断言"；能程序化就不截图
- **验证分级**：能读属性得出 yes/no → 写断言；只能靠渲染结果判断 → 截图留证；最终目标是全部可程序化甚至迁移到 headless
- **截图日志锚点（硬约束）**：每张截图必须在 `window_debug.log` 中有对应的 `ux_screenshots:` 锚点行（含帧号 + reason 标记），不允许存在无日志对应的截图。从截图找日志：用文件名帧号搜 `[TICK N]`；从日志找截图：看 `ux_screenshots:` 块

### Headless 验证三档入口

| 入口 | 命令 | 适用场景 | 速度 |
|------|------|---------|------|
| 当前 phase（推荐） | `godot --headless --path . --scene res://tests/test_runner.tscn -- --phase N` | 开发中间步骤，只跑当前 phase | 快（15-50s） |
| 单场景 | `godot --headless --path . --scene res://tests/test_runner.tscn -- --scene 场景名` | 调试单个场景 | 最快（~5s） |
| 全量回归 | `godot --headless --path . --scene res://tests/test_runner.tscn` | 收尾确认，提交前跑一次 | 慢（~160s） |
| 并行多进程 | `bash tests/run_scenarios_parallel.sh` | CI / 场景间完全隔离时 | 快（N 进程并行） |

**决策树（AI 执行时遵守）**：
- 开发中间步骤 → 默认 `--phase N`
- checklist 标注"收尾全量回归" → 无参数全量
- 只有全量 17/17 PASS 才算完成

**Window 场景入口**（需有显示环境，路径从 scene_registry.json 的 window_mode:true 条目读取）：

```bash
godot --path . --scene res://tests/gameplay/general_visual/scene.tscn
godot --path . --scene res://tests/core/window_interaction/scene.tscn
```

**日常优先用 `--phase N`**；只有怀疑引入跨场景退化时才全量。

**AI 可自行执行（无需确认）**：headless 验证、测试脚本、项目目录内文件修改、checklist/知识库更新、**窗口测试自动化**（SimulatedPlayer 剧本 + WindowAssertionSetup 断言，自动退出，不依赖手动操作）

**需用户确认**：git commit/push、修改项目目录外文件、删除非临时文件、运行时间 > 60 秒的任务、需要人工交互的窗口操作

---

## 5. 子任务使用规范

子任务是**加速工具，不是默认模式**。按需使用，不强制。

**推荐使用的情形**：
- 3 个以上独立模块需要同时探索或修改（天然无依赖）
- 跑 headless 验证的同时继续其他开发（后台运行）
- 文档更新、checklist 更新等与主线代码无关的并行任务

**不推荐使用的情形**：
- 单文件改动（开销大于收益）
- 需要上下文连续推理的架构设计（信息断层风险）
- 依赖链超过 2 步的任务（协调复杂度上升）

**使用要点**：
- 子任务 prompt 必须写清楚背景，不继承对话上下文
- 优先用 `Explore` agent 做探索，`general-purpose` 做执行
- 独立文件修改可加 `isolation: "worktree"` 隔离风险

---

## 6. 知识库查阅规则（防 API 幻觉）

- **写 GDScript 前必须查阅本地知识库**：先读 `docs/knowledge-base/godot-api/` 下对应文件确认 API 签名
- **不确认就不写**：不确定时用 web_fetch 查 Godot 官方文档
- **遇坑即记录**：新踩的坑更新到 `docs/rules/pitfalls.md`

---

## 7. 验证三层一致性规则（硬约束）

每个 Phase 的验证必须满足**三层对齐**原则：

### 核心要求

**同一功能范围，三层必须聚焦同一场景**：
- **Headless 断言**：程序化自动验证，覆盖核心数值（位置误差、阵型收敛、状态转换）
- **窗口断言**：SimulatedPlayer 走剧本 + WindowAssertionSetup，程序化输出 PASS/FAIL
- **游玩体验**：`-- --play` 模式，人工/截图验证视觉效果，范围与上两层一致

**三层必须验证同一个主语**：不允许 headless 验"A功能"、窗口验"B功能"、游玩验"C场景"的分裂状态。

### Checklist 中的必填声明

每个 Phase 的 checklist **必须在顶部明确声明**：

```markdown
## 验证范围声明

**验证主语**：[用一句话描述，如"单个将领带领 N 名哑兵"]
**核心体验**：[用一句话描述玩家/测试者应观察到什么]

| 验证层 | 场景/命令 | 通过标准 |
|--------|----------|---------|
| Headless | `--scene xxx` | [具体数值条件] |
| 窗口断言 | `--scene xxx` (window_mode) | [具体 PASS 条件] |
| 游玩体验 | `-- --play` | [视觉/感受描述] |
```

### 执行规则

- **新建 Phase 时**：第一步写验证范围声明，再写其他子阶段
- **添加测试场景时**：检查是否与已声明的验证主语一致，不一致要先更新声明
- **收尾时**：确认三层全部 PASS，且验证的是同一个主语
- **范围变更时**：先修改声明，再修改测试代码，保持同步
