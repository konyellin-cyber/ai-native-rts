# Phase 18 设计文档 — 测试与工具链收敛

**所属项目**: AI Native RTS
**状态**: 草案
**创建**: 2026-04-08
**上游文档**: [phase5/design.md](../phase5/design.md)、[test-architecture.md](../../design/tech/test-architecture.md)

---

## 目标

收敛当前项目在测试入口、AI 工具链、自动化接口和仓库产物管理上的工程债，使"文档描述的做法"和"仓库实际运行的做法"重新一致。

本 Phase 的核心目标不是新增玩法，而是恢复以下四个约束：

1. `scene_registry.json` 重新成为唯一权威回归入口
2. `src/shared/ai-renderer/` 重新成为真实单一来源
3. 自动化接口只依赖稳定公开接口，不再读取 Bootstrap 内部实现细节
4. 运行时产物不再污染仓库，文档与实现保持同步

---

## 问题分析

### 1. 回归入口分叉

当前仓库同时存在三套"看起来都能跑测试"的入口：

- `src/phase1-rts-mvp/tests/test_runner.gd` + `scene_registry.json`
- `src/phase1-rts-mvp/tests/run_scenarios.sh`
- `src/phase1-rts-mvp/tests/run_scenarios_parallel.sh`

其中后两者仍依赖已删除的旧 `tests/scenarios/*.json` 路径，并且通过改写 `config.json` 驱动场景切换。这与 Phase 13 建立的"登记表唯一权威"规则冲突，也让测试脚本本身变成新的状态源。

### 2. AI Renderer 单一来源失效

Phase 5 的设计是：`src/shared/ai-renderer/` 作为 canonical 版本，phase 目录通过 symlink 引用。

但当前仓库中：

- `src/shared/ai-renderer/`
- `src/phase1-rts-mvp/tools/ai-renderer/`
- `src/phase05-rts-prototype/tools/ai-renderer/`

三者均为真实目录，且 `phase1` 已经和 `shared` 漂移。结果是"修 shared 未必修到实际运行代码"，文档声明与仓库结构不一致。

### 3. 自动化接口命令失效

`command_router.gd` 中的 `unit_info`、`play_scenario` 当前**已经不工作**，而非仅仅"耦合不良"。失效原因如下：

**`unit_info` 失效（双重原因）**

- `bootstrap.get("units")` 永远返回 `null`：`units` 不是 Bootstrap 的属性，而是住在 Bootstrap 内部的 `_world`（GameWorld）上，即 `_world.units`
- `bootstrap.get("_red_alive")` / `bootstrap.get("_blue_alive")` 同样永远返回 `null`：这两个值住在 `_lifecycle`（UnitLifecycleManager）上，即 `_lifecycle.red_alive` / `_lifecycle.blue_alive`

结果：`unit_info` 永远返回 0 个单位、0 存活数。

**`play_scenario` 坐标退回硬编码默认值**

`_get_game_config()` 只查找节点名 `Bootstrap`，但当前主场景（`main.tscn`）的根节点名为 `Root`，导致查找永远失败、返回空 `{}`。`_resolve_scenario_rect()` 和 `_resolve_scenario_target()` 取不到真实地图宽高，静默退回硬编码的 `width=2000, height=1500`。

**根节点名查找不一致**

`_do_unit_info()` 已实现双层 fallback（先找 `Root` 再找 `Bootstrap`），但 `_get_game_config()` 只找 `Bootstrap`。同一文件内两处逻辑不一致，是前期修补不完整的结果。

### 4. 仓库卫生退化

运行时截图、日志和缓存产物重新进入仓库：

- `tests/screenshots/`
- `tests/logs/`
- 其他临时输出

这违反了项目规范里"运行时输出永远不提交"的原则，也会拖慢仓库操作和 review。

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

若某一运行环境对 symlink 有硬限制，再退而求其次使用"生成镜像 + 一致性检查"，但必须把一致性检查脚本纳入仓库，不能回到人工复制。

**判定 symlink 是否可用的方法**：在完成 18B.3 后，立即运行 phase1 headless 回归（`godot --headless --path src/phase1-rts-mvp --scene res://tests/test_runner.tscn`）。若所有场景 PASS 则 symlink 可用；若出现 `null` 脚本或加载失败错误，则切换为镜像方案。

### 合并顺序

1. 先比较 `phase1` 与 `shared` 差异
2. 将真实运行所需变更补回 `shared`
3. 再替换 phase 目录引用方式
4. 最后跑 phase1 / phase05 回归确认无退化

---

### 18C：自动化接口修复与稳定化

> **注意**：本节修复的是当前已失效的命令（见问题分析第 3 节），不是单纯重构。

### 目标状态

`unit_info` 和 `play_scenario` 恢复可用，且自动化层只依赖 Bootstrap 的稳定公开接口。

### 当前架构说明

`bootstrap.gd` 自身的字段：

- `config: Dictionary` — 已公开，可直接读
- `_world: RefCounted`（GameWorld）— 私有，`units` 住在这里：`_world.units`
- `_lifecycle: RefCounted`（UnitLifecycleManager）— 私有，存活数住在这里：`_lifecycle.red_alive` / `_lifecycle.blue_alive`

### 方案

在 `bootstrap.gd` 暴露以下稳定 getter：

| getter | 返回类型 | 数据来源 |
|--------|---------|---------|
| `get_config() -> Dictionary` | Dictionary | `config`（已有，补显式方法即可） |
| `get_units_for_debug() -> Array` | Array[Node] | `_world.units` |
| `get_red_alive() -> int` | int | `_lifecycle.red_alive` |
| `get_blue_alive() -> int` | int | `_lifecycle.blue_alive` |

`command_router.gd` 改动：

- `_get_game_config()`：补充查找 `Root` 节点，与 `_do_unit_info()` 保持一致（先 `Root` 后 `Bootstrap`）
- `_do_unit_info()`：将 `bootstrap.get("units")` 替换为 `bootstrap.get_units_for_debug()`；将 `bootstrap.get("_red_alive/blue_alive")` 替换为 `bootstrap.get_red_alive() / get_blue_alive()`
- `_resolve_scenario_rect()` / `_resolve_scenario_target()`：地图宽高从 `_get_game_config()` 的修复结果中读取，不再静默退回 `2000×1500`

### 执行顺序

18C **依赖 18B 完成后**再执行，因为 `command_router.gd` 住在 `ai-renderer/` 目录中。若 18B 切换 symlink 或合并内容后文件位置变动，18C 的修改应在新位置进行，不要在旧位置修改后再合并。

### 原则

- CommandRouter 只能依赖 Bootstrap 的公开方法，不能直接读 `_world`、`_lifecycle` 等私有字段
- 文档中承诺可用的命令，必须能在当前主场景结构下实测通过

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
- 修正"symlink 已恢复""旧脚本仍可用""默认 scenario 仍有效"等失真描述

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
