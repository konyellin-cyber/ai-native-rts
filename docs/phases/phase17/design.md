# Phase 17 设计文档 — 单位物理碰撞系统

**所属项目**: AI Native RTS
**状态**: 草案
**创建**: 2026-04-05
**上游文档**: [gameplay-vision.md](../../design/game/gameplay-vision.md)、[phase16/design.md](../phase16/design.md)

---

## 目标

将 DummySoldier 升级为真实物理单位（RigidBody3D），使士兵之间产生真实弹性推挤，不再穿透堆叠。同时为后续弓箭击退、投石机溅射等效果预留统一的物理接口。

本 Phase 只实现 **哑兵物理碰撞**，弓箭/投石机物理化在后续 Phase 处理。

---

## 核心技术方案：RigidBody3D + Seek Force

### 为什么不用 CharacterBody3D

CharacterBody3D 的 `move_and_slide()` 处理碰撞的方式是"速度截断"——碰到障碍就停在碰撞面上，推挤感像撞墙，无法产生弹性效果。

### Seek Force 原理

将"走到目标槽位"转化为每帧施加物理力：

```
驱动力 = (槽位 - 当前位置).normalized() × drive_strength
阻尼力 = -当前线速度 × linear_damp（由 RigidBody3D 参数处理）

合力 → RigidBody3D.apply_central_force(驱动力)
```

单位之间的碰撞由物理引擎自动处理——无需手写分离力。

### 关键参数

```
freeze_rotation = true        锁定旋转轴，防止单位翻倒
lock_rotation_x/y/z = true    同上，确保只在 XZ 平面运动
linear_damp = 8.0             高阻尼，防止滑行过头
mass = 1.0                    统一质量，对等推挤
drive_strength = 400.0        驱动力强度（需调参）
arrive_threshold = 8.0        距槽位多近时切换为纯阻尼（防抖）
```

### 抖动防治

当单位距槽位 < `arrive_threshold` 时，停止施加驱动力，只靠阻尼减速停下——避免多个单位争抢同一槽位时的高频震颤。

```
if dist < arrive_threshold:
    不施加驱动力（自然减速）
else:
    施加驱动力
```

---

## 碰撞层架构

Godot 4 碰撞层（1-based）：

```
Layer 1 — 地形 / 障碍（静态）
Layer 2 — 主战单位（Fighter / Archer / Worker / General）
Layer 3 — 哑兵（DummySoldier）
Layer 4 — 抛射物（Arrow，预留）
Layer 5 — HQ / 建筑
```

碰撞矩阵：

| | 地形(1) | 主战(2) | 哑兵(3) | 抛射物(4) |
|---|---|---|---|---|
| 主战(2) | ✅ | ✅ | ✅ 哑兵被推 | ✅ 受击 |
| 哑兵(3) | ✅ | ✅ 被推 | ✅ 互推 | ✅ 受击（预留）|
| 抛射物(4) | ✅ | ✅ 命中 | ✅ 命中（预留）| ❌ |

哑兵与主战单位双向碰撞（互相推挤），与 Phase 16 的"哑兵无碰撞"形成对比。

---

## Phase 17A：DummySoldier 升级为 RigidBody3D

### 节点结构变更

```
旧：Node3D
      └── MeshInstance3D（可选）

新：RigidBody3D
      ├── CollisionShape3D（CapsuleShape3D）
      └── MeshInstance3D（可选）
```

### DummySoldier 修改

- 继承改为 `extends RigidBody3D`
- `_physics_process` 改为每帧调用 `apply_central_force()`
- 初始化时设置：`freeze_rotation = true`、`linear_damp`、`mass`、`lock_rotation`
- 移除 `_move_toward()`，改为力驱动
- `follow_mode = false` 时：不施力，同时调用 `linear_velocity = Vector3.ZERO` 锁定位置

### GeneralUnit 修改

- `_dummy_soldiers` 注册逻辑不变（只是列表，无需关心子类型）
- `get_formation_slot()` 接口不变
- 初始放置哑兵时改为直接设置 `global_position`（RigidBody3D 支持）

### config.json 新增参数

```json
"dummy_physics": {
  "mass": 1.0,
  "linear_damp": 8.0,
  "drive_strength": 400.0,
  "arrive_threshold": 8.0,
  "collision_radius": 0.55
}
```

`collision_radius` 为 `radius` 的倍数（默认 0.55，略小于单位视觉半径，避免过于拥挤）。

---

## Phase 17B：主战单位碰撞层补全（可选）

现有 Fighter / Archer / Worker / General 已经是 CharacterBody3D，碰撞层目前设置较随意。本子阶段统一重新设置碰撞层编号，确保与 Layer 架构对齐。

---

## 与 Phase 16 的关系

| 维度 | Phase 16 | Phase 17 |
|------|---------|---------|
| DummySoldier 基类 | Node3D | RigidBody3D |
| 移动方式 | `global_position +=`（直接位移） | `apply_central_force()`（力驱动） |
| 单位间碰撞 | ❌ 穿透 | ✅ 真实弹性推挤 |
| 槽位接口 | `get_formation_slot()` | 不变（同接口） |
| follow_mode | 不动 | 不动（锁速度） |

Phase 16 的阵型状态机、槽位计算算法**完全不变**，只是驱动方式从直接位移改为物理力。

---

## 验证标准

**17A 完成标准**：
- 30 名哑兵静止时自然分散，无穿透堆叠
- 行军纵队中士兵保持间距，不挤成一团
- headless 测试：原有 `general_marching`、`general_deployed`、`formation_switch` 全部 PASS（接口不变）
- 目视验证：窗口模式下推挤感真实，无明显抖动

---

## 抛射物预留接口（不在本 Phase 实现）

```
未来 Arrow 物理化方案：Area3D，检测 Layer 2/3 命中
未来 Catapult 弹丸方案：RigidBody3D，重力 + 初速度，溅射伤害
```

---

_创建: 2026-04-05_
