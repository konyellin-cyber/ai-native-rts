# Phase 20 设计文档 — 弓箭手对战演示

**所属项目**: AI Native RTS
**状态**: 草案
**创建**: 2026-04-19
**上游文档**: [phase19/design.md](../phase19/design.md)

---

## 目标

在 Phase 19 行军系统基础上，把哑兵替换为弓箭手，实现双方将领带队对战的演示场景：
- 玩家（红方）右键控制将领移动，30 名弓箭手沿 Phase 19 蛇形纵队跟随
- AI（蓝方）将领静止，30 名弓箭手展开横阵待命
- 弓箭手到达横阵槽位 freeze 后自动攻击射程内的敌方单位
- 无 HQ / 工人 / 矿点 / 建造逻辑

---

## 核心机制

### 弓箭手单位（ArcherSoldier）

复用 Phase 19 DummySoldier 的全部行军逻辑（path_buffer 跟随、slot 分配、deployed freeze），
战斗状态机独立运行，**不依赖 freeze 状态**：

- **行军中攻击**：marching 途中如果射程内有敌人，冷却到期即发射（边走边射）
- **横阵中攻击**：deployed freeze 后持续攻击射程内最近敌人
- **弹道**：抛物线弹道（复用 archer.gd 的重力计算），有视觉弧度和插箭效果
- **生命值**：被箭矢命中后扣血，归零后死亡（变灰、0.5 秒后移除）
- **目标选择**：每次攻击选择射程内最近的存活敌人

### 弓箭手参数（复用 config.json archer 节点）

| 参数 | 含义 | 默认值 |
|------|------|--------|
| `shoot_range` | 攻击射程 | 160 |
| `attack_damage` | 每箭伤害 | 15 |
| `attack_cooldown` | 攻击间隔（秒） | 1.2 |
| `arrow_speed` | 箭矢飞行速度 | 600 |
| `hp` | 生命值 | 60 |

### AI 将领行为

静止不动，弓箭手自动展开横阵并攻击玩家方进入射程的单位。

---

## 场景结构

```
tests/gameplay/archer_battle/
  scene.tscn       ← 场景文件
  bootstrap.gd     ← 初始化：双方将领 + 弓箭手，复用 general_visual 的调试层
  config.json      ← 场景专用配置（地图尺寸、双方起始位置）
```

### 双方起始位置

```
地图尺寸：1500 × 1000
红方将领：(250, 0, 500)   ← 左侧中央
蓝方将领：(1250, 0, 500)  ← 右侧中央
```

---

## 与 Phase 19 的关系

| 模块 | 复用 / 新建 |
|------|-----------|
| `general_unit.gd` | **复用**：行军、path_buffer、槽位分配全部不变 |
| `dummy_soldier.gd` | **基础**：ArcherSoldier 继承其行军逻辑 |
| `archer_soldier.gd` | **新建**：在 DummySoldier 基础上加战斗状态机 |
| `arrow.gd` | **新建**：箭矢飞行物理（或直线插值） |
| `bootstrap.gd` | **新建**：双方初始化，复用 general_visual 调试层 |

---

### 攻击触发条件

```
每帧（_physics_process）：
  _attack_timer -= delta
  if _attack_timer <= 0:
    找射程内最近敌人
    if 找到：
      发射抛物线箭矢
      _attack_timer = attack_cooldown
```

不检查 freeze / formation_state，行军和横阵均可攻击。

### 攻击触发条件

```
每帧（_physics_process）：
  _attack_timer -= delta
  if _attack_timer <= 0:
    找射程内最近敌人
    if 找到：
      发射抛物线箭矢
      _attack_timer = attack_cooldown
```

不检查 freeze / formation_state，行军和横阵均可攻击。

_创建: 2026-04-19_
