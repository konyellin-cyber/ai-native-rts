# Phase 26 设计文档 — 阵线力学引擎 (Formation Pressure Mechanics)

**所属项目**: AI Native RTS
**状态**: 🚧 进行中
**创建**: 2026-05-05
**修订**: 2026-05-05 (v3 — 实现风险评审后优化)
**上游文档**: [phase24/design.md](../phase24/design.md)、[phase25/design.md](../phase25/design.md)

---

## 目标

Phase 26 在 Phase 24 MassBattleEngine 的纯数据架构上，重写力学层的碰撞与移动逻辑，从根本上解决"两军接触时密度过大、没有阵型挤压感"的问题。

核心目标：

1. **前排不可穿透**：敌对单位之间引入硬碰撞分离（Position Correction），绝对不允许互相穿透。
2. **差异化力学**：根据士兵与最近敌方的距离连续调整 drive / max_speed，实现前排"顶住"、后排"推进"。
3. **阵线推墙感**：前排停住形成墙、后排堆叠施压、阵线缓慢移动、人少方被推退。
4. **保持 500 人性能**：所有改动在现有 SpatialHash + PackedArray 框架内完成，不引入节点。
5. **向后兼容**：通过总开关 `phase26_mechanics_enabled` 控制新力学，Phase 24/25 场景完全不受影响。

---

## 核心问题分析

当前 `_simulate_crowd()` 的力学缺陷：

| 问题 | 原因 | 结果 |
|------|------|------|
| 前排被推穿 | 所有士兵共用 `drive_strength`(320)，无接触减速 | 后排把前排顶进敌阵 |
| 无友敌区分 | crowd_pressure 对友军和敌军施加相同排斥力 | 力量抵消后前排穿透 |
| 力积分穿透 | 排斥力是软性的（force → velocity → position），力不够大时一帧就穿过 | 无"不可穿透"约束 |
| 无前后排分层 | 所有士兵行为一致 | 看不出阵型深度和压力传导 |

**量化**：`drive_strength`(320) vs 排斥力峰值 `pressure_max_force`(280) × `crowd_weight`(1.5) = 420。两者量级接近，在多帧积分中 drive 持续施加而排斥力仅在近距离生效，导致穿透不可避免。

---

## 评审结论（v3）

v2 的方向正确：用连续接触因子降低前排 drive，并用 PBD 式 position correction 保证敌对单位不穿透。但按 v2 直接实现仍有几个高风险点：

| 风险 | 影响 | v3 优化 |
|---|---|---|
| `contact_far=80` 大于当前 `spatial_hash_cell_size=40` 的 9 格查询有效半径 | 最近敌方扫描会漏掉 2 格外敌人，contact_factor 进入过晚 | 新增半径查询 `_sh_get_neighbors_radius(pos, radius)`，Step 1 用 `contact_far` 查询 |
| 单次 hard separation 不能保证密集多体约束收敛 | 500 人接触面仍可能残留重叠 | 改为 3 次迭代；阵线约束后再追加 1 次 hard separation 修复 |
| 阵线约束放在 hard separation 后会把单位重新压进敌方 | “不可穿透”约束被后续 X clamp 破坏 | 执行顺序改为 hard separation 迭代 → front constraint → final hard separation |
| `front_smooth_rate=0.1` 是帧率相关参数 | 物理 FPS 改变时阵线平滑表现变化 | 改为时间常数 `front_smooth_tau`，每帧计算 `alpha = 1 - exp(-delta / tau)` |
| `min_enemy_distance_p99` 口径错误 | p99 很容易掩盖少量穿透 | 改为 `enemy_overlap_pair_count == 0` + `nearest_enemy_distance_p01 >= 15.5` |
| 对称 250v250 却要求 `alive_diff_at_end >= 50` | 同步结算下可能合理地接近平局，不应作为力学不变量 | 拆成两类验证：对称场验证不穿透/不抖动；非对称压力场验证人多方推进 |
| Headless 命令和结果路径沿用 Phase 24 写法 | `--phase 26` 不经过 test runner 时不会过滤场景；共享 bootstrap 还可能覆盖 Phase 24 的 `battle_result.json` | headless 命令显式指定 `res://tests/test_runner.tscn`；结果/截图路径从当前场景目录派生 |

## 关键设计决策（v3 修订）

### D1：连续 vs 离散的接触状态

**方案**：使用**连续的 `contact_factor ∈ [0, 1]`** 代替离散的 `contact_state`。

原因：离散状态在临界距离上会产生 drive 跳变，视觉上像"抽搐"。连续化后 drive 沿距离平滑过渡。

```
contact_factor = 1.0 - smoothstep(contact_near, contact_far, nearest_enemy_dist)
# contact_factor = 1: 完全接触（紧贴敌方）
# contact_factor = 0: 完全自由（远离敌方）
```

所有差异化行为都由 `contact_factor` 插值得到，不再需要显式状态枚举。

### D2：Position Correction 放在速度积分之前

**方案**：采用 **PBD 风格**（Position-Based Dynamics）—— 先预测下一帧位置，在预测位置上做硬碰撞修正，然后反推速度。硬分离不是单次 pass，而是小步迭代：

```
# 传统方式（会震荡）：
v += force * dt
p += v * dt
correct(p)  ← 每帧把 p 拉回来，下帧又被 v 推进去，震荡

# Phase 26 方式（稳定）：
v += force * dt                # 预测速度
p_next = p + v * dt            # 预测位置
p_next = hard_separation(p_next)  # 在预测位置上分离
v = (p_next - p) / dt          # 反推速度
p = p_next
```

原因：如果把 correction 放在积分之后，后排推力会持续让前排穿入、而修正只治标——形成弹簧振荡系统。PBD 方式保证每一帧结束时**位置约束尽量满足**。密集多体接触下，单次 pair correction 会互相影响；v4 性能优化后默认执行 `hard_separation_iterations=2`，阵线约束后再执行一次 front-only final pass。

### D3：前排 drive 不归零

**方案**：前排 drive 使用 `min_front_drive_ratio`(0.2) 作为底线，不完全归零。

原因：战斗中被击退（impulse=120）后，士兵会被弹到 attack_range 之外，如果 drive 完全为 0，前排永远打不到人。保留 20% drive 让前排能"补位贴上"。

```
drive_multiplier = lerp(1.0, min_front_drive_ratio, contact_factor)
# contact_factor=0: drive = 1.0
# contact_factor=1: drive = 0.2
```

### D4：迟滞与平滑

- **阵线位置**：`front_line_x` 使用时间常数平滑，避免物理 FPS 改变时行为漂移
- **前排人数阈值**：前排（contact_factor > 0.7）人数 < 10 时不启用阵线约束，避免小样本噪声
- **contact_factor**：本身就是连续量，天然避免抖动，不需要额外迟滞

```
alpha = 1.0 - exp(-delta / front_smooth_tau)
front_line_x = lerp(front_line_x, target_x, alpha)
```

### D5：总开关向后兼容

**方案**：`mass_battle.phase26_mechanics_enabled: bool`（默认 false）

- `false`（默认）：走 Phase 24 原逻辑，Phase 24/25 场景完全不受影响
- `true`：启用 Phase 26 的差异化驱动、硬分离、阵线约束

Phase 26 的新场景 `mass_battle_p26` 的 config 显式设为 `true`。

### D6：硬核半径与攻击范围的几何

**方案**：调整几何比例，保证"刺杀窗口"宽度合理

| 参数 | 旧值 | 新值 | 说明 |
|---|---|---|---|
| `hard_radius` | - | 8.0 | 敌对硬核（最小中心距 16） |
| `attack_range` | 22.0 | 22.0 | 保持 |
| `crowd_radius` | 24.0 | 28.0 | 友军 soft 半径稍增 |

刺杀窗口 = `[hard_radius × 2, attack_range]` = `[16, 22]`，共 6 单位的可攻击区间，足够在击退后快速重新进入交战。

---

## 技术架构

```
┌────────────────────────────────────────────────────────────────┐
│           MassBattleEngine._simulate_crowd() 重构                │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  Step 1: Nearest Enemy Scan（最近敌方距离扫描）                 │
│    输入：_positions, _teams, _states, SpatialHash              │
│    输出：_nearest_enemy_dist[i], _contact_factor[i]            │
│                                                                │
│  Step 2: Front Line Update（阵线位置更新）                      │
│    扫描 contact_factor > 0.7 的士兵，计算双方前线 X 极值        │
│    alpha = 1 - exp(-delta / front_smooth_tau)                  │
│                                                                │
│  Step 3: Force Accumulation（力学累加）                         │
│    drive = base_drive × lerp(1.0, min_ratio, contact_factor)   │
│    friend_pressure = sum over friends with teams[j]==teams[i]  │
│    support_push = (仅后排) 指向最近前排友军的力                 │
│    boundary = 边界排斥                                          │
│                                                                │
│  Step 4: Predict Position（预测位置）                           │
│    v_pred = v + force * dt                                     │
│    p_pred = p + v_pred * dt                                    │
│                                                                │
│  Step 5: Hard Separation（硬碰撞分离，在 p_pred 上）            │
│    仅敌对单位间执行 position correction                         │
│    迭代 3 次，逐步消除密集接触面重叠                            │
│                                                                │
│  Step 6: Front Line Constraint（阵线约束）                      │
│    contact_factor > 0.7 的士兵 X 坐标不超过 front_line_x ± tol │
│                                                                │
│  Step 7: Final Hard Separation（最终硬分离）                    │
│    修复阵线约束造成的二次敌对重叠                                │
│                                                                │
│  Step 8: Velocity Back-Solve（反推速度）                        │
│    v = (p_pred - p) / dt                                       │
│    v = v.limit_length(max_speed × speed_multiplier)            │
│    p = p_pred                                                  │
│    clamp_to_boundary()                                         │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

---

## 详细设计

### 1. 新增数据字段

```
var _contact_factor:     PackedFloat32Array  # [0,1] 与敌方接触度
var _nearest_enemy_idx:  PackedInt32Array    # 最近敌方索引（-1=无）
var _nearest_enemy_dist: PackedFloat32Array  # 最近敌方距离
var _nearest_friend_front_idx: PackedInt32Array  # 最近的前排友军（REAR_PUSH 用）
var _p_pred: PackedVector3Array          # PBD 预测/约束后位置
var _neighbors_enemy_short: Array        # hard separation 短邻居表
var _neighbors_friend: Array             # friend pressure/support 邻居表

var _front_line_x: float = 0.0           # 阵线 X 坐标（时间平滑）
var _front_line_valid: bool = false      # 本帧阵线是否有效（前排人数足够）
var _front_count_red: int = 0            # 红方前排人数（contact_factor > 0.7）
var _front_count_blue: int = 0           # 蓝方前排人数

var _phase26_enabled: bool = false       # 总开关
```

### 2. Nearest Enemy Scan（最近敌方距离扫描）

Phase 26 不能继续只用 9 格邻居查询。当前默认 `spatial_hash_cell_size=40`，而 `contact_far=80`，9 格查询在格子边界附近会漏掉 2 格外、但仍在接触影响范围内的敌人。

新增半径查询：

```
func _sh_get_neighbors_radius(pos: Vector3, radius: float) -> PackedInt32Array:
    cell_range = ceil(radius / _sh_cell_size)
    # 查询 [-cell_range, +cell_range] 的格子，再由调用者按真实距离过滤
```

查询半径约定：

| 用途 | 查询半径 |
|---|---|
| `nearest_enemy/contact_factor` | v4 后为 `scan_radius=max(crowd_radius, hard_radius*2+hard_margin)` |
| `friend_pressure` | `crowd_radius` |
| `hard_separation` | `hard_radius * 2 + hard_margin` |

对每个存活士兵 i：

```
neighbors = _scan_cells(pos[i], scan_radius)
min_enemy_dist = INF
min_enemy_idx = -1

for j in neighbors:
    if j == i or teams[j] == teams[i] or states[j] == DEAD: continue
    dist = distance(pos[i], pos[j])
    if dist < min_enemy_dist:
        min_enemy_dist = dist
        min_enemy_idx = j

_nearest_enemy_dist[i] = min_enemy_dist
_nearest_enemy_idx[i] = min_enemy_idx

# 连续接触因子：smoothstep 从 contact_far 到 contact_near
contact_factor[i] = 1.0 - smoothstep(contact_near, contact_far, min_enemy_dist)
```

**关键参数**：
- `contact_near = 20.0`：进入完全接触（= hard_radius × 2 + ε）
- `contact_far = 80.0`：脱离接触影响
- 中间区间 [20, 80] 让 drive_multiplier 从 1.0 平滑过渡到 0.2

**性能注意**：这次扫描查询了每个士兵的邻居，**结果（neighbor list）要缓存给 Step 5 复用**，避免重复 SpatialHash 查询。缓存数组必须复用并清空，避免每帧大量创建 Array 造成 GDScript GC 抖动。

### 3. Front Line Update（阵线更新）

```
red_front_x = -INF
blue_front_x = INF
red_front_count = 0
blue_front_count = 0

for i in range(soldier_count):
    if states[i] == DEAD or contact_factor[i] < 0.7: continue
    if teams[i] == TEAM_RED:
        red_front_x = max(red_front_x, pos[i].x)
        red_front_count += 1
    else:
        blue_front_x = min(blue_front_x, pos[i].x)
        blue_front_count += 1

# 时间平滑，避免突变
if red_front_count >= MIN_FRONT_COUNT and blue_front_count >= MIN_FRONT_COUNT:
    target_x = (red_front_x + blue_front_x) * 0.5
    # 阵线推进：人多方推进
    net_push = (alive_red - alive_blue) * front_advance_rate * delta
    target_x += net_push  # 向人少方移动（red 多则 target_x 向 blue 方向增大）
    alpha = 1.0 - exp(-delta / front_smooth_tau)
    _front_line_x = lerp(_front_line_x, target_x, alpha)
    _front_line_valid = true
else:
    _front_line_valid = false  # 前排人数不足，禁用阵线约束
```

`MIN_FRONT_COUNT = 10`：前排人数 ≥ 10 才启用阵线。

### 4. Force Accumulation（力学累加）

```
for i in range(soldier_count):
    if states[i] == DEAD: continue
    if stun_frames[i] > 0:
        # 硬直期间不主动 drive，但仍预测位置并参与后续硬分离
        stun_frames[i] -= 1
        v[i] = v[i] * (1 - damp * dt * 10)
        p_pred[i] = pos[i] + v[i] * dt
        continue
    
    # --- 4a. 差异化 drive ---
    flow_dir = _get_flow_dir(i)
    drive_mul = lerp(1.0, min_front_drive_ratio, contact_factor[i])
    drive = flow_dir * drive_strength * drive_mul
    
    # --- 4b. 友军 soft pressure（跳过敌军）---
    friend_pressure = Vector3.ZERO
    friends = neighbors_friend[i]
    for j in friends:
        dp = pos[i] - pos[j]
        dist_sq = dp.length_squared()
        if dist_sq < crowd_radius * crowd_radius and dist_sq > 0.0001:
            dist = sqrt(dist_sq)
            t = 1.0 - dist / crowd_radius
            friend_pressure += (dp / dist) * (t * t * pressure_max_force)
    
    # --- 4c. Support Push（后排推前排）---
    # 仅在 0.2 < contact_factor < 0.7 的"后排推进"区间生效
    support = Vector3.ZERO
    if contact_factor[i] > 0.2 and contact_factor[i] < 0.7:
        front_idx = _find_nearest_front_friend(i, friends)  # contact_factor > 0.7 的友军
        if front_idx >= 0:
            to_front = pos[front_idx] - pos[i]
            to_front.y = 0
            if to_front.length() > 0.01:
                support = to_front.normalized() * support_push_strength
    
    # --- 4d. 边界斥力 ---
    boundary = _boundary_repulsion(i)
    
    # --- 4e. 横向 jitter（仅前排）---
    jitter = Vector3.ZERO
    if contact_factor[i] > 0.7:
        h = hash(i * 31 + _frame) % 1000 / 1000.0 - 0.5  # [-0.5, 0.5]
        jitter = Vector3(0, 0, h * lateral_jitter_strength)
    
    # --- 4f. 速度积分 ---
    force = drive + friend_pressure * crowd_weight + support + boundary + jitter
    v_pred = v[i] * (1 - damp * dt * 8) + force * dt
    
    # 速度上限按 contact_factor 调整
    speed_mul = lerp(1.0, min_front_speed_ratio, contact_factor[i])
    v_pred = v_pred.limit_length(max_speed * speed_mul)
    
    p_pred[i] = pos[i] + v_pred * dt
```

`min_front_drive_ratio = 0.2`、`min_front_speed_ratio = 0.15`、`support_push_strength = 80.0`。

### 5. Hard Separation（PBD 风格硬分离）

```
for iteration in range(hard_separation_iterations):
    # 注意：作用在 p_pred 上，不是 pos 上
    for i in range(soldier_count):
        if states[i] == DEAD: continue
        neighbors = neighbors_enemy_short[i]
        for j in neighbors:
            if j <= i: continue                  # 对称去重
            if states[j] == DEAD: continue
            
            dp = p_pred[i] - p_pred[j]
            dp.y = 0
            dist = dp.length()
            min_dist = hard_radius * 2.0
            
            if dist < min_dist and dist > 0.001:
                overlap = min_dist - dist
                # 完全分离（不是部分）
                correction = dp.normalized() * (overlap * 0.5)
                p_pred[i] += correction
                p_pred[j] -= correction
            elif dist <= 0.001:
                # 完全重合：确定性方向分离，避免非确定性 rand
                angle = float((i * 73856093 + j * 19349663) & 1023) / 1024.0 * TAU
                dir = Vector3(cos(angle), 0, sin(angle))
                p_pred[i] += dir * hard_radius
                p_pred[j] -= dir * hard_radius
```

**关键点**：
- 作用在 `p_pred` 上，不直接改 `pos`——避免下一帧积分时再被推回去
- `overlap * 0.5` 是每方各分担一半的修正量，两方加起来刚好消除重叠
- 速度修正在 Step 8 反推时自然完成，不需要显式处理
- 硬直士兵仍参与 hard separation；硬直只禁止主动 drive，不代表可以被敌人穿透

### 6. Front Line Constraint（阵线约束）

```
if not _front_line_valid:
    return  # 前排人数不足，不约束

for i in range(soldier_count):
    if states[i] == DEAD or contact_factor[i] < 0.7: continue
    if teams[i] == TEAM_RED:
        # 红方前排 X 不超过 front_line_x + tol
        if p_pred[i].x > _front_line_x + front_tolerance:
            p_pred[i].x = _front_line_x + front_tolerance
    else:
        # 蓝方前排 X 不低于 front_line_x - tol
        if p_pred[i].x < _front_line_x - front_tolerance:
            p_pred[i].x = _front_line_x - front_tolerance
```

阵线约束后必须再执行一次 `_apply_hard_separation(1)`，因为 X 方向 clamp 可能把前排重新推入敌方 hard radius。

### 7. Final Hard Separation（最终硬分离）

```
_apply_hard_separation(1)
```

这一步只处理阵线约束后产生的二次重叠，不重新计算 contact_factor 或 front_line_x。

### 8. Velocity Back-Solve（反推速度）

```
for i in range(soldier_count):
    if states[i] == DEAD: continue
    
    # 反推速度：从约束后的位置回算速度
    new_v = (p_pred[i] - pos[i]) / dt
    # 再次 clamp：限制下一帧惯性和渲染朝向，不回滚已满足约束的位置
    speed_mul = lerp(1.0, min_front_speed_ratio, contact_factor[i])
    v[i] = new_v.limit_length(max_speed * speed_mul)
    
    pos[i] = p_pred[i]
    _clamp_to_boundary(i)
```

**关键点**：位置约束优先于速度一致性。`p_pred` 一旦满足约束就写回位置；反推速度只作为下一帧惯性和渲染输入。若 separation 造成的瞬时位移超过速度上限，速度 clamp 不回滚位置，否则会重新引入穿透。

---

## 配置参数（全量）

```json
{
  "mass_battle": {
    "phase26_mechanics_enabled": true,
    
    "contact_near": 20.0,
    "contact_far": 80.0,
    
    "hard_radius": 8.0,
    "crowd_radius": 28.0,
    "pressure_max_force": 200.0,
    "crowd_weight": 1.2,
    
    "min_front_drive_ratio": 0.2,
    "min_front_speed_ratio": 0.15,
    "support_push_strength": 80.0,
    "lateral_jitter_strength": 3.0,
    
    "min_front_count": 10,
    "front_tolerance": 15.0,
    "front_advance_rate": 0.05,
    "front_smooth_tau": 0.15,
    "hard_separation_iterations": 2,
    "hard_margin": 5.0
  }
}
```

Phase 24/25 的 config 中**不出现** `phase26_mechanics_enabled`，默认为 false，走旧逻辑。

## 场景输出路径

Phase 26 复用 `tests/gameplay/mass_battle/bootstrap.gd` 时，不能继续把结果写死到 `res://tests/gameplay/mass_battle/battle_result.json`，否则 `mass_battle_p26` 和 `mass_battle_p26_pressure` 会覆盖 Phase 24 的结果。

输出路径必须从当前场景目录派生：

```
result_path = get_scene_file_path().get_base_dir() + "/battle_result.json"
screenshot_dir = "res://tests/screenshots/" + get_scene_file_path().get_base_dir().get_file() + "/"
```

这属于测试/验证层改造，不改变 MBE 的力学接口。

---

## 力学正确性验证指标

headless 模式下自动收集以下指标并断言：

| 指标 | 期望 | 含义 |
|---|---|---|
| `enemy_overlap_pair_count` | 0 | 不允许任何敌对 hard_radius 重叠残留 |
| `nearest_enemy_distance_p01` | ≥ 15.5 (< hard_radius × 2 的容差 3%) | 少量数值误差允许，但低分位不能系统性穿透 |
| `contact_factor_switch_per_frame` | < 5 | contact_factor 在 0.7 附近切换频率低（连续化效果） |
| `front_line_x_variance_window10` | < 5.0 | 阵线平滑无剧烈跳变 |
| `battle_resolved` | true | 500 人对冲能正常结束，不无限卡死 |

另增一个非对称压力验证场景（例如红方 250、蓝方 220，或等价的测试用兵力倍率），只验证一件事：`front_line_displacement_toward_weaker_side > 30.0`。不要把“人多方推进”混进完全对称 250v250 的不变量里。

失败时写入 `battle_result.json` 的 `validation_errors` 字段。

---

## 执行顺序总览

```
_physics_process(delta):
  _frame += 1
  _sh_rebuild()
  _update_centroids()
  
  if phase26_enabled:
    _simulate_crowd_p26(delta)   # 新逻辑
  else:
    _simulate_crowd(delta)        # 原 Phase 24 逻辑（保留不改）
  
  _attack_timer += 1
  if _attack_timer >= _attack_interval:
    _resolve_combat()
  
  _renderer.update(...)
```

`_simulate_crowd_p26()` 内部：
```
1. _scan_nearest_enemy()       → 更新 contact_factor、nearest_enemy_dist、短敌表和友军表
2. _update_front_line(delta)   → 更新 _front_line_x
3. _accumulate_forces_and_predict(delta)  → 计算 force、v_pred、p_pred
4. _apply_hard_separation()    → 修正 p_pred（敌对单位不重叠）
5. _apply_front_constraint()   → 修正 p_pred（前排不越阵线）
6. _apply_hard_separation(front_only=true) → 阵线约束后的最终硬分离
7. _back_solve_velocity(delta) → 反推速度，写回 pos 和 v
```

---

## v4 性能优化要点

首次窗口运行 `mass_battle_p26` 时，交战后 FPS 从 30–60 掉到 3–5。原因不是 PBD 思路本身，而是实现把 `contact_far=80` 的大邻居表复用于所有步骤：

- 每名士兵查询 25 个 SpatialHash cell。
- hard separation 对同一张大表执行 3 次迭代 + 1 次 final pass。
- friend pressure 和 support push 也扫同一张大表，虽然真正需要的半径只有 `crowd_radius≈28`。

v4 将邻居表拆成两层：

| 邻居表 | 半径 | 用途 |
|---|---:|---|
| `_neighbors_enemy_short` | `hard_radius * 2 + hard_margin`，默认 21 | hard separation |
| `_neighbors_friend` | `crowd_radius`，默认 28 | friend pressure / support push |

同时将 `contact_factor` 远端影响截断到 `scan_radius=max(crowd_radius, hard_radius*2+hard_margin)`。这会牺牲 28–80 范围内的轻微预减速，但换来交战期 pair 扫描量的大幅下降。

实测 headless 1200 帧对比：

| 阶段 | 优化前 `crowd_us` | 优化后 `crowd_us` |
|---|---:|---:|
| 行军期 | 约 13–15ms | 约 5–6ms |
| 交战峰值 | 约 37–40ms | 约 11–13ms |

窗口模式验证结果（`godot --path src/phase1-rts-mvp --scene res://tests/gameplay/mass_battle_p26/scene.tscn`）：

| 阶段 | 帧号 | FPS | `crowd_us` | `combat_us` |
|---|---:|---:|---:|---:|
| 行军期 | 120–600 | 56–60 | 约 4.4–7.0ms | 约 1.9–3.4ms |
| 接触初期 | 660 | 55 | 9.3ms | 4.8ms |
| 交战峰值 | 720 | 49 | 10.9ms | 6.2ms |
| 交战峰值 | 780 | 54 | 12.1ms | 6.9ms |
| 交战中段 | 840–1140 | 52–60 | 约 6.6–10.6ms | 约 4.0–6.9ms |
| 1200 帧基准点 | 1200 | 55 | 6.2ms | 3.6ms |

结论：窗口最差观测 FPS 为 49，高于 30 FPS 目标；Phase 26 的 3–5 FPS 严重性能问题已解除。后续若继续优化，应优先看 `_resolve_combat()` 的交战期邻居扫描，而不是 PBD 主循环。

---

## 兼容性矩阵

| 组件 | Phase 26 影响 |
|---|---|
| **BattleRenderer / BattleSpriteRenderer** | 无需修改（读取接口不变） |
| **CombatResolver (_resolve_combat)** | 无需修改（依然按距离和 stun 判定） |
| **FlowFieldManager** | 无需修改（flow_dir 只是 drive 方向输入） |
| **config.json (Phase 24/25 场景)** | 无需修改（总开关默认 false） |
| **headless 测试框架** | 新增指标收集，老测试不受影响 |
| **ImpactParticlePool / 粒子** | 无需修改（命中回调不变） |

---

## 非目标

- 不引入每士兵节点或 Godot 物理引擎
- 不改动渲染层
- 不实现完整的动画状态机或攻击生命周期
- 不实现多兵种差异化力学
- 不实现士气 / 溃败 / 撤退机制
- 不支持斜角阵线（只支持 X 轴对冲的直阵线，斜角场景留后续 Phase）

---

## 验证标准

| 验证层 | 场景/命令 | 通过标准 |
|--------|----------|---------|
| Headless | `--scene res://tests/test_runner.tscn -- --phase 26` | 500 人对冲正常结束，所有力学不变量指标通过 |
| 非对称压力 | `mass_battle_p26_pressure` | 人多方阵线可测量地推向人少方 |
| 窗口视觉 | `mass_battle_p26` | 目视：前排停墙 / 后排堆叠 / 阵线缓慢移动 / 无穿透 |
| 穿透检查 | Debug overlay 画 hard_radius 圆 | 敌方圆不重叠 |
| 性能 | 窗口 500 人 | 稳定 ≥ 30 FPS |
| 回退 | Phase 24/25 场景 | 与 Phase 26 实现前完全一致 |

---

## 修订历史

- **v1 (2026-05-05)**: 初稿，离散 contact_state + 积分后 correction
- **v2 (2026-05-05)**: 评审后优化
  - 离散 contact_state → 连续 contact_factor（smoothstep）
  - 积分后 correction → PBD 风格（predict-correct-backsolve）
  - 前排 drive=0 → 保留 min_front_drive_ratio=0.2
  - 新增阵线时间平滑、最小前排人数阈值
  - 新增总开关 phase26_mechanics_enabled 保证向后兼容
  - 新增 support push、力学正确性自动化指标
  - 调整 hard_radius 10→8，保证刺杀窗口合理
  - 复用 cached_neighbors 避免重复 SpatialHash 查询
- **v3 (2026-05-05)**: 实现风险评审后优化
  - 新增半径 SpatialHash 查询，修复 contact_far 大于 cell_size 时的漏检
  - hard separation 改为多次迭代，并在阵线约束后追加 final pass
  - 阵线平滑从帧率相关 `front_smooth_rate` 改为时间常数 `front_smooth_tau`
  - 修正穿透验证指标：从 p99 改为 overlap pair count + p01
  - 将对称不变量验证和非对称“人多方推进”验证拆开
  - 修正 headless 命令入口，并要求 battle_result / screenshots 使用场景本地路径
- **v4 (2026-05-05)**: 性能优化
  - 大邻居表拆分为 `_neighbors_enemy_short` 和 `_neighbors_friend`
  - hard separation 默认迭代从 3 降为 2，final pass 改为 front-only
  - friend pressure 使用 `length_squared` 预过滤，减少 sqrt / normalized 调用
  - 新增 `hard_margin=5.0`
  - headless 交战峰值 `crowd_us` 从约 37–40ms 降到约 11–13ms
  - 窗口模式交战峰值最低观测 49 FPS，达到 ≥30 FPS 目标
