# 测试架构设计文档

> **适用阶段**：Phase 10+
> **写于**：2026-04-02
> **背景**：本文档记录 AI Native RTS 自动化测试体系的完整设计，包含测试单元定义、分类体系、扩展规范和执行约束。是新 Phase 添加测试的权威参考。

---

## 1. 核心概念

### 1.1 测试单元

**一个完整的测试单元 = 一个 `.tscn`（世界结构）+ 一个 `scenario.json`（剧本 + 断言）**，两者必须成对存在，放在同一目录下。

```
tests/scenes/<场景名>/
  ├── scene.tscn          ← 游戏世界结构（地图、单位初始布局）
  ├── scenario.json       ← 剧本（操作序列 + 断言集合）
  ├── bootstrap.gd        ← 启动脚本（继承 CombatBootstrap 或独立）
  └── config.json         ← 场景专属参数覆盖（可选）
```

**不允许**多个 `scenario.json` 复用同一个 `.tscn`。如果需要测试同一个世界结构下的不同行为，建立两个场景目录，`.tscn` 可以是符号链接或内容相同的独立文件。

### 1.2 运行环境

测试单元有两种运行环境，由场景自身的 `scenario.json` 中 `window_mode` 字段声明：

| 运行环境 | `window_mode` | 适用测试类型 | 启动方式 |
|---------|--------------|------------|---------|
| **Headless** | `false`（默认） | 游戏逻辑验证（AI / 经济 / 战斗） | `godot --headless` |
| **Window** | `true` | 交互行为验证（框选 / 点击 / UI 响应） | `godot`（有渲染） |

**Window 不是独立维度**，而是交互测试必然需要的运行环境。非交互测试一律用 Headless。

---

## 2. 断言分层

断言按验证对象分为三个层次，决定它注册在哪个文件中：

| 层次 | 描述 | 注册位置 | 是否需要窗口 |
|-----|------|---------|------------|
| **L1 存在性** | 游戏世界基础结构是否正确搭建 | `assertion_setup.gd` | 否 |
| **L2 行为性** | 游戏逻辑是否按预期运转 | `assertion_setup.gd` | 否 |
| **L3 交互性** | 玩家操作是否被正确响应 | `window_assertion_setup.gd` | 是 |

**断言归属规则**：
- 能读属性得出 yes/no → L1 或 L2，放 `assertion_setup.gd`
- 依赖渲染结果或真实输入事件 → L3，放 `window_assertion_setup.gd`
- L3 断言只能在 `window_mode: true` 的场景中使用

---

## 3. 场景登记表

`tests/test_runner.gd` 中的 `SCENARIO_FILES` 列表是**唯一权威的场景登记表**。

```
约束（硬规则）：
  ✅ 新增场景 → 在 SCENARIO_FILES 中追加条目
  ✅ 升级场景 → 旧条目替换为新条目（需满足覆盖声明，见 3.1）
  ❌ 禁止从 SCENARIO_FILES 中删除条目（除非有覆盖声明）
  ❌ 禁止场景文件存在但不在 SCENARIO_FILES 中（孤儿场景）
```

登记表缺失或场景文件不存在时，下次回归会立即报错，不会静默通过。

### 3.1 场景升级规则

场景只能被「升级」，不能被「静默删除」。升级时，新场景的 `scenario.json` 需声明 `covers` 字段：

```json
{
  "name": "combat_v2",
  "covers": ["combat"],
  "assertions": ["..."]
}
```

`covers` 声明"新场景覆盖了哪些旧场景的测试逻辑"。有此声明才允许将旧场景从 `SCENARIO_FILES` 中移除，否则两者必须同时保留。

---

## 4. 全量回归定义

**全量回归 = 跑 `SCENARIO_FILES` 中当前登记的所有场景**。

没有"历史场景"的特殊保护——登记表中存在的场景才被保护，已通过覆盖声明升级并移除的旧场景不再参与回归。

```
全量回归通过标准：
  Headless 场景：全部 PASS
  Window 场景：全部 PASS（需有窗口环境）

  两类场景分开跑，均需全部通过才算完整回归
```

---

## 5. 场景类型选择指南

新建测试场景时，按以下流程选择类型：

```
这个测试需要验证：

  玩家操作 / 鼠标输入 / UI 响应？
    → Window 场景
    → 断言注册在 window_assertion_setup.gd
    → scenario.json 中 window_mode: true

  游戏逻辑 / AI 行为 / 经济 / 战斗？
    → Headless 场景
    → 断言注册在 assertion_setup.gd
    → scenario.json 中 window_mode: false（或不写）

  两者都有？
    → 拆成两个场景，分别处理
    → 交互部分放 Window，逻辑部分放 Headless
```

---

## 6. 新增场景步骤

```
1. 在 tests/scenes/<场景名>/ 下创建：
   - scene.tscn（世界结构）
   - scenario.json（剧本 + 断言）
   - bootstrap.gd（继承 CombatBootstrap 或独立）

2. 在 assertion_setup.gd 或 window_assertion_setup.gd 中
   注册新断言（如需要）

3. 在 test_runner.gd 的 SCENARIO_FILES 中追加条目

4. 运行全量回归验证新场景通过：
   godot --headless --path . --scene res://tests/test_runner.tscn

5. 更新当前 Phase 的 checklist
```

---

## 7. 已登记场景清单

> 以 `test_runner.gd` 的 `SCENARIO_FILES` 为准，此处仅作说明性索引。

| 场景名 | 类型 | 主要验证内容 | 所属 Phase |
|-------|------|------------|-----------|
| `smoke_test` | Headless | 2 Fighter 基础战斗 | Phase 1 |
| `economy` | Headless | 红方经济正循环 | Phase 2 |
| `combat` | Headless | AI 完整决策链路 + 击杀 | Phase 2 |
| `interaction` | Headless | 框选 / 移动 / 生产链路 | Phase 3 |
| `archer_vs_fighter` | Headless | Archer vs Fighter 战斗 | Phase 10 |
| `archer_vs_archer` | Headless | Archer vs Archer 战斗 | Phase 10 |
| `kite_behavior` | Headless | 弓箭手 Kite 战术 | Phase 10 |
| `window_interaction` | Window | 真实鼠标框选 / 点选 | Phase 12 |

---

## 8. 历史遗留：JSON 注入模式（已废弃）

Phase 13 之前，`economy` / `combat` / `interaction` 三个场景采用"JSON 注入模式"：复用 `main.tscn`，通过 `config_overrides` 覆盖参数。

**该模式已在 Phase 13 完成迁移并删除。**

废弃原因：
- 违反"测试单元 = .tscn + JSON 成对绑定"原则
- 多个 JSON 复用同一 .tscn 导致场景边界模糊
- `test_runner.gd` 需维护两套加载逻辑，增加复杂度

---

_创建：2026-04-02_
_最后更新：2026-04-02_
