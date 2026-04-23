# Phase 22 设计文档 — 手柄输入支持

**所属项目**: AI Native RTS
**状态**: 草案
**创建**: 2026-04-19
**上游文档**: [phase19/design.md](../phase19/design.md)

---

## 目标

为 Phase 19 单将领行军场景添加手柄（Gamepad）控制支持：
- 左摇杆：控制将领移动方向
- 右摇杆（可选）：镜头旋转
- 与鼠标右键控制并存，不互斥

---

## 场景定义

与 Phase 19 `general_visual` 完全一致：
- 单方将领 + 30 名哑兵
- 无战斗单位、无建造、无 AI 对手
- 地图 1000×1000

新建独立场景 `tests/gameplay/gamepad_test/`，复用 general_visual 的全部逻辑，
额外加入手柄输入处理。

---

## 手柄输入方案

### 将领移动

左摇杆输入映射到地面平面上的移动方向：

```
摇杆方向 → 世界坐标方向（考虑摄像机朝向）
摇杆偏移量 → 移动目标点距离（越推越远，最大 200 units）
持续推杆 → 每隔 N 帧重新发出 move_to，保持持续移动
松开摇杆 → 将领停止（不再发出新的 move_to）
```

### 摇杆死区

摇杆原点附近的微小漂移不触发移动，死区阈值 0.15。

### 摄像机适配

当前摄像机固定角度（-45°,-45°）正视角，摇杆"上"对应世界坐标斜前方。
需要根据摄像机朝向把摇杆输入转换为世界方向。

---

## 实现位置

`tests/gameplay/gamepad_test/bootstrap.gd` 新增：
- `_input(event)` 处理手柄连接/断开事件
- `_physics_process` 每帧读取摇杆轴值，转换为世界方向，定期发 `move_to`

---

## Context Steering 避障（22C）

### 为什么选 Context Steering

当前 RVO 只处理速度层面的避让，不感知静态障碍，对称情况下容易死锁。
Context Steering 直接替换施力方向的计算方式，天然处理动态障碍和静态障碍，
且与现有 RigidBody3D 物理驱动架构完全兼容。

Flow Field 不适合阵型场景（每个士兵目标不同，不能共享流场），
Context Steering 是当前架构下最合适的升级方向。

### 算法原理

把周围分成 N 个方向（默认 8 方向），每个方向打两类分数：

```
兴趣图（Interest Map）：方向越靠近目标，分数越高（cos 相似度）
危险图（Danger Map）：方向上有障碍/友军，分数为负（斥力）

最终方向 = Interest - Danger 中分数最高的方向
```

8 方向示意（目标在东偏北）：

```
NW(0.1)  N(0.5)  NE(0.9)
 W(-1.0)   ●    E(0.7)
SW(-0.5) S(0.1) SE(0.3)
         危险在西（障碍物）
```

### 实现位置

替换 `dummy_soldier.gd` 中 `_physics_process` 的施力方向计算：

```
当前：
  force_dir = (_my_target - global_position)  ← 直线，不感知障碍

替换为：
  force_dir = _context_steer(_my_target)  ← 8方向评分，绕障碍
```

### 感知范围

每个士兵感知半径 = `_collision_radius × 4`，扫描范围内：
- 友军士兵 → 危险图（避免重叠）
- 静态障碍 → 危险图（绕墙）
- 目标方向 → 兴趣图

### 参数

| 参数 | 含义 | 默认值 |
|------|------|--------|
| `cs_directions` | 方向数量 | 8 |
| `cs_sense_radius` | 感知半径 | collision_radius × 4 |
| `cs_danger_weight` | 危险权重 | 2.0 |

### 与 RVO 的关系

Context Steering 替换施力方向计算，RVO 继续负责速度修正（二者不互斥）：

```
Context Steering → 目标方向（感知障碍）
RVO             → 速度修正（动态避让）
物理碰撞         → 最终兜底
```

---

_创建: 2026-04-19；2026-04-19 — 新增 Context Steering 设计_
