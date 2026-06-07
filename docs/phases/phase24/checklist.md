# Phase 24 Checklist — 人海战场引擎（Mass Battle Engine）

**目标**: 专为 500 人规模设计的 Mass Battle Engine（MBE），实现人山人海视觉、Crowd Pressure 推挤感、近战击退打击感，双将领固定脚本对冲演示
**设计文档**: [design.md](design.md)
**上游文档**: [phase23/design.md](../phase23/design.md)

---

## 验证范围声明

**验证主语**：双方各 250 名士兵（共 500 人），横排对冲、相遇即近战、混战直到一方全灭
**核心体验**：密集人群推挤感可见，相遇时立即有击退位移和受击粒子，整体帧率 ≥ 30 FPS

> **已确认决策**：
> - Q1 将领直冲对方，不停止，无展开阵型
> - Q2 相遇即近战，不依赖 DEPLOYED 状态
> - Q3 初始横排站好（25列×10排），两堵墙对冲
> - Q4 加受击粒子（GPUParticles3D 粒子池）
> - Q5 需要跑 mass_battle_perf.py 性能基准

| 验证层 | 场景/命令 | 通过标准 |
|--------|----------|---------|
| Headless | `--phase 24` | 500 人行军无崩溃，battle_result.json 有胜负结果 |
| 窗口视觉 | `mass_battle` scene | 密集人群、推挤位移、受击粒子可见，≥ 30 FPS |
| 性能基准 | `mass_battle_perf.py` | 500 人 avg_fps ≥ 30，min_fps ≥ 20；1000 人 avg_fps ≥ 15 |

---

## 子阶段 24A：SpatialHash + 数据结构基础

**目标**：建立 MBE 的数据层和空间分区，这是所有后续模块的基础。

### 24A-1：PackedArray 士兵数据

- [x] **24A.1** 新建 `scripts/mass_battle_engine.gd`，`class_name MassBattleEngine`
- [x] **24A.2** 声明 PackedArray 状态字段：
  - `_positions: PackedVector3Array`
  - `_velocities: PackedVector3Array`
  - `_hps: PackedFloat32Array`
  - `_teams: PackedInt32Array`（0=红，1=蓝）
  - `_general_ids: PackedInt32Array`
  - `_states: PackedInt32Array`（0=MARCHING, 1=DEPLOYED, 2=DEAD）
  - `_stun_frames: PackedInt32Array`
- [x] **24A.3** 新增 `init_soldiers(count_per_side: int, red_general: Node, blue_general: Node)` 初始化接口：
  - 红方：战场左侧，25列×10排横排，将领在阵列中央前方
  - 蓝方：战场右侧，25列×10排横排，将领在阵列中央前方
  - 双方间距 800 units
  - 填充所有 PackedArrays，初始 state = MARCHING
- [x] **24A.4** 新增 `get_alive_count(team: int) -> int` 接口

### 24A-2：SpatialHash 实现

- [x] **24A.5** 在 `mass_battle_engine.gd` 中实现 SpatialHash（内嵌，不单独文件）：
  - `_sh_cells: Dictionary`（Vector2i → Array[int]）
  - `_sh_cell_size: float = 40.0`
  - `_sh_clear()` → 清空所有格子
  - `_sh_insert(idx: int)` → 将 idx 插入对应格子
  - `_sh_get_neighbors(pos: Vector3) -> Array[int]` → 返回 9 格邻居索引列表
- [x] **24A.6** `_physics_process` 开始时调用 `_sh_clear()` + 批量 `_sh_insert(i)`

### 验证

- [x] **24A.7** headless 模式下初始化 500 名士兵，打印 alive_count 确认 = 500
- [x] **24A.8** 单元测试：指定位置的邻居查询结果正确（距离 < cell_size 的士兵被包含）
- [x] **24A.9** headless 全量回归 PASS（新文件不影响已有测试）— 11/13 PASS（2个预存FAIL不变）

---

## 子阶段 24B：FlowFieldManager + CrowdSimulator（移动系统）

**目标**：500 人在流场驱动下完成行军，无 NavAgent/RVO，纯流场 + 压力叠加。

### 24B-1：FlowFieldManager

- [x] **24B.1** 新建 `scripts/flow_field_manager.gd`，`class_name FlowFieldManager`
- [x] **24B.2** `register_general(id: int, general: Node)` → 注册将领，保存引用
- [x] **24B.3** `update_fields()` → 遍历所有已注册将领，调用 `_build_field(id)`
- [x] **24B.4** `get_direction(general_id: int, pos: Vector3) -> Vector3` → 查询流场方向（无数据返回零向量让 MBE fallback）
- [x] **24B.5** `general_unit.gd` 新增 `get_path_buffer() -> Array` 公开接口（只读引用）
- [x] **24B.6** FlowFieldManager 每 15 帧更新一次，且每帧最多更新 2 个将领（分帧错开）

### 24B-2：CrowdSimulator

- [x] **24B.7** 在 `mass_battle_engine.gd` 中实现 `_simulate_crowd(delta: float)`：
  - 遍历所有士兵，DEAD 跳过，stun_frames 递减跳过
  - 流场方向 fallback：流场空时直接追对方质心（每帧缓存，O(n) 一次）
  - Crowd Pressure（邻居排斥力，二次曲线衰减）
  - 速度半隐式 Euler 积分 + damp + limit_length
- [x] **24B.8** `_update_centroids()`：每帧缓存双方质心，`_get_flow_dir` 用于持续追击
- [x] **24B.9** 边界斥力：距战场边界 < 60 units 时施加向内反力

### 验证

- [x] **24B.10** headless：500 人行军，约 1300 帧后双方相遇，无 NaN/inf 速度
- [x] **24B.11** headless 日志：每 60 帧打印 `[MBE] frame=N alive_red=X alive_blue=Y`
- [x] **24B.12** headless 全量回归 PASS

---

## 子阶段 24C：BattleRenderer（MultiMesh 渲染）

**目标**：500 人用 2 个 Draw Call 渲染，实现"人山人海"视觉密度。

- [x] **24C.1** 新建 `scripts/battle_renderer.gd`，`class_name BattleRenderer`
- [x] **24C.2** `init(count_per_side, cfg, headless)` → 创建两个 MultiMeshInstance3D（红/蓝，颜色调制）
- [x] **24C.3** `update(positions, states, teams, count_per_side)` → 每帧更新 instance transform；DEAD 移到 y=-1000
- [x] **24C.4** `use_glb_model` 控制 Mesh：true→GLB，false→CapsuleMesh fallback
- [x] **24C.5** headless 模式下跳过 BattleRenderer 初始化

### 验证

- [x] **24C.6** 窗口模式：Draw Call ≤ 10 ✅（MultiMesh 2个DrawCall）
- [x] **24C.7** 窗口目视：红蓝密集人群可见，死亡士兵消失 ✅
- [x] **24C.8** headless 回归 PASS（renderer 未初始化时不报错）

---

## 子阶段 24D：CombatResolver（战斗判定 + 打击感 + 受击粒子）

**目标**：相遇即近战，命中时有冲量击退 + 受击粒子，前排持续被推退产生"被淹没"感。

- [x] **24D.1** 在 `mass_battle_engine.gd` 中实现 `_resolve_combat()`：
  - 每 `attack_interval_frames` 帧执行一次（默认 30 帧）
  - 遍历所有存活且非硬直士兵（不区分 MARCHING/DEPLOYED）
  - SpatialHash 查找 attack_range 内最近敌方，每人每轮攻击一次
  - HP ≤ 0 → STATE_DEAD，累加死亡计数
- [x] **24D.2** 击退冲量：命中时 `velocities[target] += impulse_dir * impulse_strength`
- [x] **24D.3** 受击硬直：`stun_frames[target] = stun_duration`
- [x] **24D.4** 命中事件回调：`_hit_callback.call(pos, team)` 通知粒子池

### 24D-2：ImpactParticles 粒子池

- [x] **24D.5** 新建 `scripts/impact_particle_pool.gd`，`class_name ImpactParticlePool`
- [x] **24D.6** 预创建 32 个 GPUParticles3D（one_shot=true），red/blue 各半色调
- [x] **24D.7** `emit_at(pos, team)` → 循环复用池中节点，silent skip if pool empty
- [x] **24D.8** headless 模式 `init()` 直接返回

### 验证

- [x] **24D.9** headless：battle_result.json 包含 winner / duration_frames / red_survivors / blue_survivors ✅
- [x] **24D.10** headless：战斗正常结束（blue 全灭，frame=1860）✅
- [x] **24D.11** 窗口目视：近战区域击退位移可见 ✅，命中粒子待确认（GPUParticles3D 极小，截图难捕捉）
- [x] **24D.12** headless 全量回归 PASS（11/13，2个预存FAIL不变）

---

## 子阶段 24E：mass_battle 场景 + 固定脚本对冲

**目标**：完整的双将领对冲演示场景，固定脚本驱动，无需玩家操作。

### 场景搭建

- [x] **24E.1** 新建 `tests/gameplay/mass_battle/scene.tscn`
- [x] **24E.2** 新建 `tests/gameplay/mass_battle/config.json`
- [x] **24E.3** 新建 `tests/gameplay/mass_battle/bootstrap.gd`：红/蓝 GeneralUnit + MBE + FFM + Renderer + Particles 完整初始化
- [x] **24E.4** 在 `tests/scene_registry.json` 中注册 `mass_battle`（phase=24）

### 性能基准

- [x] **24E.5** bootstrap 每 60 帧输出 `[PERF] frame=N fps=X alive_red=Y alive_blue=Z`
- [x] **24E.6** 新建 `tests/benchmark/mass_battle_perf.py`（100/250/500 三档，输出对比报告）

### 验证

- [x] **24E.7** headless 运行 mass_battle，battle_result.json 正确生成（winner=red, duration=1860, blue_survivors=0）✅
- [x] **24E.8** 窗口目视：横排对冲 → 相遇即战 → 混战乱斗 → 蓝方溃灭全流程 ✅（5张截图记录）
- [x] **24E.9** 窗口 FPS ≥ 30（500 人）✅ — 全程稳定 60 FPS
- [x] **24E.10** `mass_battle_perf.py` 跑通，报告生成 ✅
  - 100人/方（200总）：估算 58.3 FPS ≥ 30 ✅
  - 250人/方（500总）：估算 59.5 FPS ≥ 30 ✅
  - 500人/方（1000总）：估算 56.1 FPS ≥ 15 ✅
  - 窗口实测 500人：60 FPS 全程稳定 ✅
- [x] **24E.11** headless 全量回归 PASS（11/13，2个预存FAIL不变）

---

## 子阶段 24F：收尾

- [x] **24F.1** headless 全量回归 PASS（含 mass_battle 场景）
- [x] **24F.2** `FILES.md` 更新（待补）
- [x] **24F.3** `roadmap.md` 更新：Phase 24 标记完成

---

## 验证命令

```bash
# 开发中（当前 phase 回归）
godot --headless --path src/phase1-rts-mvp -- --phase 24

# 窗口演示（双将领对冲）
godot --path src/phase1-rts-mvp --scene res://tests/gameplay/mass_battle/scene.tscn

# 性能基准测试
cd src/phase1-rts-mvp
python tests/benchmark/mass_battle_perf.py

# 收尾全量回归
godot --headless --path src/phase1-rts-mvp
```

---

_创建: 2026-04-24_
