# Phase 18 设计文档 — 测试与工具链收敛

**所属项目**: AI Native RTS
**状态**: 草案
**创建**: 2026-04-08
**上游文档**: [phase5/design.md](../phase5/design.md)、[test-architecture.md](../../design/tech/test-architecture.md)

---

## 目标

收敛当前项目在测试入口、AI 工具链、自动化接口和仓库产物管理上的工程债，使“文档描述的做法”和“仓库实际运行的做法”重新一致。

本 Phase 的核心目标不是新增玩法，而是恢复以下四个约束：

1. `scene_registry.json` 重新成为唯一权威回归入口
2. `src/shared/ai-renderer/` 重新成为真实单一来源
3. 自动化接口只依赖稳定公开接口，不再读取 Bootstrap 内部实现细节
4. 运行时产物不再污染仓库，文档与实现保持同步

---

## 问题分析

### 1. 回归入口分叉

当前仓库同时存在三套“看起来都能跑测试”的入口：

- `tests/test_runner.gd` + `scene_registry.json`
- `tests/run_scenarios.sh`
- `tests/run_scenarios_parallel.sh`

其中后两者仍依赖已删除的旧 `tests/scenarios/*.json` 路径，并且通过改写 `config.json` 驱动场景切换。这与 Phase 13 建立的“登记表唯一权威”规则冲突，也让测试脚本本身变成新的状态源。

### 2. AI Renderer 单一来源失效

Phase 5 的设计是：`src/shared/ai-renderer/` 作为 canonical 版本，phase 目录通过 symlink 引用。

但当前仓库中：

- `src/shared/ai-renderer/`
- `src/phase1-rts-mvp/tools/ai-renderer/`
- `src/phase05-rts-prototype/tools/ai-renderer/`

三者均为真实目录，且 `phase1` 已经和 `shared` 漂移。结果是“修 shared 未必修到实际运行代码”，文档声明与仓库结构不一致。

### 3. 自动化接口契约漂移

`command_router.gd` 中的 `unit_info`、`play_scenario`、`_get_game_config()` 仍按旧 Bootstrap 结构取数据，依赖：

- 节点名固定为 `Bootstrap`
- Bootstrap 暴露 `units`
- Bootstrap 暴露 `_red_alive` / `_blue_alive`

而当前主场景根节点名为 `Root`，运行时状态也已收进 `_world` 和 `_lifecycle`。这意味着自动化链路没有使用稳定接口，而是在读一次又一次变化的内部字段。

### 4. 仓库卫生退化

运行时截图、日志和缓存产物重新进入仓库：

- `tests/screenshots/`
- `tests/logs/`
- 其他临时输出

这违反了项目规范里“运行时输出永远不提交”的原则，也会拖慢仓库操作和 review。

---

## Phase 18 范围

### 包含

- 回归入口收敛
- AI Renderer 单一来源恢复
- 自动化接口稳定化
- 运行时产物清理和文档同步

### 不包含

- 新玩法
- 战斗平衡调整
- 新兵种 / 新 UI
- Phase 17 的物理碰撞逻辑本体
- 云 CI / GitHub Actions 接入

---

## 技术方案

### 18A：回归入口收敛

### 目标状态

Headless 全量回归只有一个正式入口：

```bash
godot --headless --path src/phase1-rts-mvp --scene res://tests/test_runner.tscn
```

`scene_registry.json` 是唯一权威场景列表；其他 shell 脚本若保留，只能作为这个入口的包装层，不能自带第二套场景源。

### 方案

- `run_scenarios.sh` 不再硬编码场景，也不再改写 `config.json`
- `run_scenarios_parallel.sh` 若保留，则从 `scene_registry.json` 读取 headless 场景列表
- `config.json` 不再依赖一个失效的默认 `scenario_file` 才能工作
- README 和 FILES 只保留一套正式回归命令描述

---

### 18B：AI Renderer 单一来源恢复

### 目标状态

`src/shared/ai-renderer/` 是唯一 canonical 源码目录，其他 phase 目录不再维护独立副本。

### 方案

优先恢复 Phase 5 原方案：

```text
src/shared/ai-renderer/                    canonical
src/phase1-rts-mvp/tools/ai-renderer/     symlink -> ../../shared/ai-renderer
src/phase05-rts-prototype/tools/ai-renderer/ symlink -> ../../shared/ai-renderer
```

若某一运行环境对 symlink 有硬限制，再退而求其次使用“生成镜像 + 一致性检查”，但必须把一致性检查脚本纳入仓库，不能回到人工复制。

### 合并顺序

1. 先比较 `phase1` 与 `shared` 差异
2. 将真实运行所需变更补回 `shared`
3. 再替换 phase 目录引用方式
4. 最后跑 phase1 / phase05 回归确认无退化

---

### 18C：自动化接口稳定化

### 目标状态

自动化层不直接读取 Bootstrap 私有字段，而是只走稳定公开接口。

### 方案

由 `bootstrap.gd` 暴露稳定 getter，例如：

- `get_config()`
- `get_world()`
- `get_lifecycle()`
- `get_units_for_debug()`

`command_router.gd` 改为：

- 先定位 `Root` 或 `Bootstrap`
- 再通过 getter 取配置、单位列表和统计信息
- `play_scenario` 使用真实地图宽高，不再静默退回过时默认值

### 原则

- CommandRouter 只能依赖“接口名”，不能依赖 `_world`、`_lifecycle`、`_red_alive` 这类内部字段名
- 文档中承诺可用的命令，必须能在当前主场景结构下工作

---

### 18D：仓库卫生与文档同步

### 目标状态

- 截图、日志、缓存不再默认进 git
- 文档描述与仓库实现一致
- review 发现的问题被转成可执行清单，不再只停留在对话里

### 方案

- 扩充 `.gitignore`
- 清理当前仓库中的运行时产物，若确需保留样例则迁移到专门样例目录
- 更新 README、FILES、roadmap、相关 design 文档
- 修正“symlink 已恢复”“旧脚本仍可用”“默认 scenario 仍有效”等失真描述

---

## 验收标准

### 功能层

- `test_runner.gd` + `scene_registry.json` 可完成 headless 全量回归
- shell 回归脚本不再改写 tracked config 文件
- `command_router.gd` 的 `unit_info` / `play_scenario` / `world_click` 在当前主场景下工作正常

### 结构层

- `src/shared/ai-renderer/` 与运行时实际代码不再漂移
- `phase1` 和 `phase05` 不再维护独立 ai-renderer 副本

### 仓库层

- 运行测试后 `git status` 不应因截图/日志/配置回写出现脏工作区
- 文档中的回归入口、目录结构和实际仓库一致

---

## 与 Phase 17 的关系

| 维度 | Phase 17 | Phase 18 |
|------|---------|---------|
| 关注点 | 游戏内物理行为 | 工具链与工程约束 |
| 主要对象 | DummySoldier / 碰撞层 | Test Runner / AI Renderer / 文档 / 仓库产物 |
| 风险类型 | 玩法与物理回归 | 回归失真、维护成本、工具不可用 |

Phase 18 不替代 Phase 17。两者可以并行存在，但职责必须分清：Phase 17 继续推进玩法相关视觉验证，Phase 18 专门清偿工程债。

---

_创建: 2026-04-08_
