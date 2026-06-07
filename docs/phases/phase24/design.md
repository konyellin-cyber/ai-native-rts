# Phase 24 设计文档 — 人海战场引擎（Mass Battle Engine）

**所属项目**: AI Native RTS
**状态**: 设计中
**创建**: 2026-04-24
**上游文档**: [phase23/design.md](../phase23/design.md)、[phase17/design.md](../phase17/design.md)

---

## 目标

为 500 人规模的人海战场设计专用引擎（Mass Battle Engine，以下简称 MBE），支撑以下三个核心体验：

1. **人山人海**：双方各 250 人（共 500 人）同时在场，视觉上密集覆盖战场
2. **推挤感**：密集区域士兵发生真实物理挤压与位移，前排被后排推着走
3. **打击感**：近战命中时目标被冲量击退，附带视觉粒子反馈

场景形式：**双将领固定脚本对冲**，两支军队从两端行军，正面相遇后混战直到一方全灭。

---

## 动机

Phase 23 的 DummySoldier 架构面向"将领跟随"体验设计（30 人精度），扩展到 500 人时存在根本性瓶颈：

| 问题 | Phase 23 原因 | 500 人后果 |
|------|--------------|-----------|
| NavAgent 查询 | 每兵每帧调用 `get_next_path_position()` | O(n) NavMesh 查询，500 次/帧 |
| RVO 求解 | 邻居交互 O(n²) | 125,000 次/帧，CPU 崩溃 |
| Context Steering | 8 方向 × n 人 | 4,000 射线检测/帧 |
| Draw Call | n 个 MeshInstance3D | 500 个 Draw Call，GPU 瓶颈 |
| GDScript 主线程 | `_physics_process` 逐人串行 | 500 次/帧 GDScript 循环 |

**核心结论**：无法通过参数调优解决，需要专用引擎替换关键路径。

---

## Mass Battle Engine 架构设计

### 总体架构

```
MassBattleEngine（单例节点）
 ├── SpatialHash            # 空间分区，O(1) 邻居查询
 ├── FlowFieldManager       # 多将领流场管理
 ├── CrowdSimulator         # 群体移动求解（纯数据，无节点）
 ├── CombatResolver         # 战斗判定（近战冲量 + 伤害）
 └── BattleRenderer         # MultiMesh 渲染层
```

### 数据分离原则

MBE 的核心设计原则：**逻辑与渲染完全分离**。

```
传统模式（Phase 23）：
  DummySoldier（RigidBody3D 节点）
    → 每帧 _physics_process 驱动逻辑
    → 自带 MeshInstance3D 渲染

MBE 模式（Phase 24）：
  MassBattleEngine（持有士兵数据数组）
    → _physics_process 批量更新所有士兵
    → BattleRenderer 从数据数组读 Transform 写入 MultiMesh
  士兵 = 纯数据结构（Dictionary / PackedArrays），无场景节点
```

---

## 模块详细设计

### 模块 A：SoldierData — 士兵纯数据结构

不使用 GDScript 类，用 PackedArrays 存储所有士兵状态，内存连续，批量读写高效：

```
每个士兵的状态字段：
  position: Vector3         # 当前位置
  velocity: Vector3         # 当前速度
  team: int                 # 0 = 红方，1 = 蓝方
  general_id: int           # 归属将领 ID
  slot_index: int           # 编队槽位编号
  hp: float                 # 生命值
  state: int                # MARCHING=0 / DEPLOYED=1 / DEAD=2
  stun_frames: int          # 受击硬直剩余帧数（>0 时无法施力）

实现方式：
  PackedVector3Array  positions    # n 个 Vector3，内存连续
  PackedVector3Array  velocities
  PackedFloat32Array  hps
  PackedInt32Array    teams
  PackedInt32Array    general_ids
  PackedInt32Array    states
  PackedInt32Array    stun_frames
```

优点：避免 GDScript Dictionary 的哈希开销，可整块传递给 MultiMesh。

---

### 模块 B：SpatialHash — 空间分区

```
设计：
  cell_size = 40.0 units
  格子映射：cell_key = Vector2i(floor(x/40), floor(z/40))
  数据结构：Dictionary<Vector2i, Array<int>>（格子 → 士兵索引列表）

每帧流程：
  1. clear()：清空所有格子
  2. for i in soldier_count: insert(positions[i], i)
  3. 查询邻居：get_neighbors(pos) → 返回 9 个相邻格子的索引列表

复杂度：
  插入 O(n)，查询 O(1) 均摊（9 格 × 平均密度）
  500 人 × 平均 10 邻居 = 5,000 次查询/帧，远优于 O(n²) = 125,000
```

---

### 模块 C：FlowFieldManager — 多将领流场管理

每个 GeneralUnit 维护一个独立流场，MBE 统一管理所有流场更新：

```
数据结构：
  _fields: Dictionary<int, Dictionary>
    key = general_id
    value = { cell: Vector2i → direction: Vector3 }

更新策略：
  每 15 帧更新一次（Phase 23 为 10 帧，加长节省计算）
  每帧最多更新 2 个将领的流场（分帧错开，避免单帧峰值）

查询接口：
  get_direction(general_id, pos: Vector3) → Vector3
    → 无数据时返回将领当前行进方向（fallback）
```

---

### 模块 D：CrowdSimulator — 群体移动求解

每帧在 `_physics_process` 中批量计算所有士兵的速度更新：

```
for i in soldier_count:
  if states[i] == DEAD: continue
  if stun_frames[i] > 0: stun_frames[i] -= 1; continue

  # 1. 流场方向（目标驱动力）
  flow_dir = flow_field_manager.get_direction(general_ids[i], positions[i])
  slot_offset = get_slot_lateral_offset(i)        # 编队横向偏移
  drive = (flow_dir + slot_offset).normalized() * drive_strength

  # 2. 邻居排斥力（Crowd Pressure）
  neighbors = spatial_hash.get_neighbors(positions[i])
  pressure = Vector3.ZERO
  for j in neighbors:
    if j == i: continue
    delta = positions[i] - positions[j]
    dist = delta.length()
    if dist < crowd_radius and dist > 0.01:
      pressure += delta.normalized() * pressure_curve(dist)

  # 3. 速度积分（半隐式 Euler，加阻尼）
  force = drive + pressure * crowd_weight
  velocities[i] = velocities[i] * (1.0 - damp) + force * delta_time
  velocities[i] = velocities[i].limit_length(max_speed)
  positions[i] += velocities[i] * delta_time
```

**pressure_curve 函数**：
```
# 近距离排斥力指数增长，制造"挤不进去"的感觉
func pressure_curve(dist: float) -> float:
  t = 1.0 - dist / crowd_radius          # t=1 紧贴，t=0 边缘
  return t * t * pressure_max_force      # 二次曲线，近距离剧烈
```

---

### 模块 E：CombatResolver — 战斗判定

> **已确认**：相遇即可近战，不需要等待 DEPLOYED 状态。MARCHING 途中碰到敌人就打。

```
近战攻击流程（每 N 帧触发一次）：
  for i in soldier_count:
    if state[i] == DEAD: continue        # 死亡跳过
    if stun_frames[i] > 0: continue      # 硬直中无法攻击
    neighbors = spatial_hash.get_neighbors(positions[i])
    for j in neighbors:
      if teams[j] == teams[i]: continue  # 不打自己人
      if states[j] == DEAD: continue     # 不打死人
      dist = (positions[i] - positions[j]).length()
      if dist < attack_range:
        # 造成伤害
        hps[j] -= damage_per_hit
        if hps[j] <= 0: states[j] = DEAD

        # 施加击退冲量（打击感核心）
        impulse_dir = (positions[j] - positions[i]).normalized()
        velocities[j] += impulse_dir * impulse_strength
        stun_frames[j] = stun_duration   # 受击硬直
        break                            # 每帧每人只攻击一个目标

攻击频率：每 30 帧（0.5 秒）判定一次（可由 config 控制）
```

击退冲量参数设计：
```
impulse_strength = 80~150 units/s（可调）
stun_duration    = 10 frames（约 0.17 秒硬直）
```
大规模战场中，连续被多人攻击的士兵会被持续推退，产生"被人群淹没"的压迫感。

---

### 模块 E2：ImpactParticles — 受击粒子

> **已确认**：Phase 24 加受击粒子，GPUParticles3D，CPU 零负担。

```
设计：
  预先创建粒子池（ParticlePool），避免运行时实例化开销
  pool_size = 32（同时最多 32 个受击特效在播放）
  
  触发：CombatResolver 每次命中 → emit_at(position)
  粒子行为：
    向上 + 随机方向喷射（模拟尘土/血迹）
    lifetime = 0.4s
    one_shot = true，播完自动归还池
    
  Mesh：小球形粒子，红方受击 = 深红色，蓝方受击 = 深蓝色

  headless 模式：跳过粒子池初始化（DisplayServer headless 判断）
```

节点结构：
```
ImpactParticlePool（Node3D，挂载在 Bootstrap 场景根节点）
  └── GPUParticles3D × 32（预先创建，复用）
```

---

### 模块 F：BattleRenderer — MultiMesh 渲染

```
节点结构：
  BattleRenderer（Node3D）
    ├── MultiMeshInstance3D [红方]  # 250 实例
    └── MultiMeshInstance3D [蓝方]  # 250 实例

每帧更新（在 CrowdSimulator 完成后）：
  for i in red_count:
    transform = Transform3D(BASIS_DEFAULT, positions[red_indices[i]])
    red_multimesh.set_instance_transform(i, transform)
  # 蓝方同理

  # 已死亡单位：移到地图外（y = -1000）隐藏，不做 visible 切换（避免 MultiMesh 重建）

Mesh 选择（配置可切换）：
  - 高质量：GLB 模型（Kenney Mini Characters，Phase 23G 已准备）
  - 低质量 fallback：CapsuleMesh（无 GLB 时自动降级）

颜色区分：
  红方 MultiMesh：uniform color modulate = 红色调
  蓝方 MultiMesh：uniform color modulate = 蓝色调
```

---

### 模块 G：MassBattleBootstrap — 固定脚本对冲场景

> **已确认决策汇总**：
> - Q1 将领行为：直冲对方，无停止展开，持续行军施压
> - Q2 战斗触发：相遇即近战，不等 DEPLOYED 状态
> - Q3 初始排布：横排站好（两堵墙从两端对冲）
> - Q4 受击粒子：加 GPUParticles3D 粒子池

```
场景逻辑（无玩家操作，纯自动）：

初始布局：
  红方：战场左侧，250 人横排（25列 × 10排），将领在阵列中央前方
  蓝方：战场右侧，250 人横排（25列 × 10排），将领在阵列中央前方
  双方间距：800 units（足够展示行军过程）

行动脚本（帧计时驱动）：
  frame 0:    红将领 move_to → 蓝方阵营位置（直冲，不停）
  frame 0:    蓝将领 move_to → 红方阵营位置（直冲，不停）
  持续:       CrowdSimulator 驱动士兵跟随各自将领
  持续:       CombatResolver 每 30 帧检测接触范围内敌方，立即近战
  持续:       ImpactParticles 在命中点触发粒子
  终止条件:   某方 alive_count == 0 → 写入 battle_result.json → 退出

将领行为说明：
  将领持续行军不停止 → 士兵始终在 MARCHING 状态
  前排士兵接触敌方即开始近战（不依赖 DEPLOYED 状态切换）
  将领穿过敌阵后在对侧继续行军（不折返，自然在敌阵中穿行）

胜负判定：
  每 60 帧采样 alive_count
  结果写入 battle_result.json：
    { "winner": "red"/"blue"/"draw", "duration_frames": N,
      "red_survivors": N, "blue_survivors": N }
```

---

## 性能目标

| 规模 | 目标帧率 | 关键路径 |
|------|---------|---------|
| 100 人（验证） | ≥ 60 FPS | CrowdSimulator 基准测试 |
| 250 人/方（500 总） | ≥ 30 FPS | 主目标 |
| 500 人/方（1000 总） | ≥ 15 FPS | 未来扩展上限 |

性能预算分配（500 人，60Hz，目标 16ms/帧）：

| 模块 | 预算 | 优化手段 |
|------|------|---------|
| SpatialHash 更新 | 1ms | PackedArray，避免 Dictionary |
| CrowdSimulator 主循环 | 6ms | GDScript 向量批处理 |
| CombatResolver | 2ms | 每 30 帧才运行一次（均摊 0.1ms） |
| FlowFieldManager | 1ms | 分帧错开，每帧只更新 2 个流场 |
| BattleRenderer | 3ms | MultiMesh，CPU→GPU 一次传输 |
| 其他 | 3ms | 将领 AI、UI、调试 |

---

## 与现有系统的关系

| 现有系统 | 关系 | 说明 |
|---------|------|------|
| DummySoldier | **共存，不替换** | Phase 23 的将领跟随场景继续使用；MBE 仅在 mass_battle 场景激活 |
| GeneralUnit | **复用** | 将领节点保留，MBE 读取其路径数据生成流场 |
| FlowField（Phase 23） | **参考实现** | Phase 23 的 `_update_flow_field` 逻辑迁移到 FlowFieldManager |
| RigidBody3D 物理 | **MBE 内不使用** | MBE 士兵是纯数据，无 Godot 物理节点；碰撞由 CrowdSimulator 模拟 |
| 测试体系 | **兼容** | mass_battle 场景注册到 scene_registry.json；headless 模式输出 battle_result.json |

---

## 配置接口（config.json 新增字段）

```json
{
  "mass_battle": {
    "soldier_count_per_side": 250,
    "crowd_radius": 24.0,
    "crowd_weight": 1.2,
    "pressure_max_force": 200.0,
    "drive_strength": 320.0,
    "max_speed": 140.0,
    "damp": 0.85,
    "attack_range": 20.0,
    "damage_per_hit": 10.0,
    "impulse_strength": 120.0,
    "stun_duration": 10,
    "attack_interval_frames": 30,
    "spatial_hash_cell_size": 40.0,
    "flow_field_update_interval": 15,
    "use_glb_model": true
  }
}
```

---

## 文件结构

```
新增文件：
  scripts/
    mass_battle_engine.gd        # MBE 主控制器（SpatialHash + CrowdSimulator + CombatResolver）
    flow_field_manager.gd        # 多将领流场管理（从 general_unit.gd 抽取扩展）
    battle_renderer.gd           # MultiMesh 渲染层
    impact_particle_pool.gd      # 受击粒子池（GPUParticles3D × 32，headless 自动跳过）

  tests/gameplay/mass_battle/
    scene.tscn                   # 空场景，挂载 bootstrap
    bootstrap.gd                 # 固定脚本对冲逻辑（横排初始化 + 双将领直冲 + 胜负判定）
    config.json                  # mass_battle 配置（覆盖全局 config）

  tests/benchmark/
    mass_battle_perf.py          # 性能基准脚本（100/250/500人三档，输出对比报告）

修改文件：
  scripts/general_unit.gd        # 新增 get_path_buffer() 公开接口（供 FlowFieldManager 读取）
  config.json                    # 新增 mass_battle 配置块
  tests/scene_registry.json      # 注册 mass_battle 场景
```

---

## 关键考虑

### 调试可视化

大规模模式下必须有专用调试工具：
- `mass_battle_engine.gd` 提供 `get_debug_stats()` → `alive_count / avg_speed / avg_pressure / fps`
- bootstrap 每 60 帧打印一次状态摘要（供 headless 日志分析）
- 窗口模式下叠加 SpatialHash 格子可视化（可用 DebugDraw3D 或手写 Immediate Geometry）

### 边界处理

- 士兵不能走出地图边界：CrowdSimulator 中加边界斥力（距边界 < 60 units 时施加向内反力）
- 死亡士兵：`state = DEAD`，CrowdSimulator 跳过，BattleRenderer 移到地图外隐藏

### 数值稳定性

- 速度必须有上限（`limit_length(max_speed)`），防止冲量叠加后爆炸
- 两个士兵重叠（dist < 0.01）时跳过排斥力计算，防止除以近零向量

---

_创建: 2026-04-24_
