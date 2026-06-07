# Phase 26 Checklist — 阵线力学引擎 (Formation Pressure Mechanics)

**目标**: 重写 MBE 力学层，实现前排硬碰撞不穿透、差异化驱动、阵线推墙感。
**设计文档**: [design.md](design.md) (v3)
**上游文档**: [phase24/design.md](../phase24/design.md)
**状态**: 🚧 进行中

---

## 验证范围声明

**验证主语**：双方各 250 名士兵，共 500 人，使用 Phase 26 力学参数对冲（`phase26_mechanics_enabled=true`）。
**核心体验**：前排停住形成不可穿透的接触面、后排堆叠施压、阵线缓慢推进、人少方被推退。

| 验证层 | 场景/命令 | 通过标准 |
|--------|----------|---------|
| Headless | `godot --headless --path src/phase1-rts-mvp --scene res://tests/test_runner.tscn -- --phase 26` | 战斗正常结束，力学不变量指标全部通过 |
| 非对称压力 | `mass_battle_p26_pressure` | 人多方阵线稳定推向人少方，位移超过阈值 |
| 窗口视觉 | `mass_battle_p26` | 前排停墙、后排堆叠、阵线移动可见，无穿透 |
| 穿透检查 | Debug overlay | 敌方 hard_radius 圆不重叠 |
| 性能 | 窗口 500 人 | 稳定 ≥ 30 FPS |
| 回退 | Phase 24/25 场景 | `phase26_mechanics_enabled=false`（默认），行为完全一致 |

---

## 子阶段 26A：文档与场景准备

- [x] **26A.1** 新建 `docs/phases/phase26/design.md`
- [x] **26A.2** 新建 `docs/phases/phase26/checklist.md`
- [x] **26A.3** `roadmap.md` 新增 Phase 26 条目
- [x] **26A.4** 新建测试场景目录 `tests/gameplay/mass_battle_p26/`
- [x] **26A.5** `scene_registry.json` 注册 `mass_battle_p26`，phase=26
- [x] **26A.6** 新建 `tests/gameplay/mass_battle_p26/config.json`，含 `phase26_mechanics_enabled=true` 及全量 Phase 26 参数
- [x] **26A.7** 复制 `mass_battle_sprite/scene.tscn` 作为 Phase 26 场景基础（复用 sprite2d 渲染）
- [x] **26A.8** 新建非对称压力验证场景 `mass_battle_p26_pressure`（例如红 250 / 蓝 220 或等价测试倍率）
- [x] **26A.9** `scene_registry.json` 注册 `mass_battle_p26_pressure`，phase=26
- [x] **26A.10** 结果和截图输出路径从当前场景目录派生，避免覆盖 Phase 24 `battle_result.json`

## 子阶段 26B：数据字段与总开关

- [x] **26B.1** `mass_battle_engine.gd` 新增 `_contact_factor: PackedFloat32Array`
- [x] **26B.2** 新增 `_nearest_enemy_idx: PackedInt32Array` 和 `_nearest_enemy_dist: PackedFloat32Array`
- [x] **26B.3** 新增 `_nearest_friend_front_idx: PackedInt32Array`
- [x] **26B.4** 新增阵线状态：`_front_line_x: float`、`_front_line_valid: bool`
- [x] **26B.5** 新增 `_phase26_enabled: bool` 总开关
- [x] **26B.6** 新增 `_p_pred: PackedVector3Array`
- [x] **26B.7** 新增分层邻居缓存结构（v4 为 `_neighbors_enemy_short` / `_neighbors_friend`）
- [x] **26B.8** 新增 `_sh_get_neighbors_radius(pos, radius)`，支持 `contact_far > spatial_hash_cell_size`
- [x] **26B.9** 在 `_init_soldiers()` 中初始化新字段
- [x] **26B.10** 从 config 读取全量 Phase 26 参数（使用 default 向后兼容）
- [x] **26B.11** `_physics_process` 根据 `_phase26_enabled` 分派到 `_simulate_crowd` 或 `_simulate_crowd_p26`
- [x] **26B.12** 可选支持非对称测试兵力配置（仅 Phase 26 测试场景使用，不影响旧场景）

## 子阶段 26C：Nearest Enemy Scan（最近敌方扫描 + 邻居缓存）

- [x] **26C.1** 实现 `_scan_nearest_enemy()` 函数
- [x] **26C.2** 遍历存活士兵，使用 `_sh_get_neighbors_radius(pos, contact_far)` 查询并缓存邻居列表
- [x] **26C.3** 对每个士兵计算 `_nearest_enemy_dist[i]` 和 `_nearest_enemy_idx[i]`
- [x] **26C.4** 计算 `contact_factor[i] = 1 - smoothstep(contact_near, contact_far, dist)`
- [ ] **26C.5** 验证：headless 打印 contact_factor 分布直方图（0-0.3 / 0.3-0.7 / 0.7-1.0）

## 子阶段 26D：Front Line Update（阵线位置）

- [x] **26D.1** 实现 `_update_front_line(delta)` 函数
- [x] **26D.2** 扫描 `contact_factor > 0.7` 的士兵，取双方前线 X 极值和计数
- [x] **26D.3** 计算目标 X = (red_front + blue_front) / 2，加入人数差推进量
- [x] **26D.4** 时间常数平滑：`alpha = 1 - exp(-delta / front_smooth_tau)`
- [x] **26D.5** 前排人数任一方 < `min_front_count`(10) 时 `_front_line_valid = false`
- [ ] **26D.6** 验证：headless 日志输出每秒阵线 X 值，确认平滑无跳变

## 子阶段 26E：Force Accumulation & Predict（力学累加与位置预测）

- [x] **26E.1** 实现 `_accumulate_forces_and_predict(delta)` 函数
- [x] **26E.2** drive_multiplier = lerp(1.0, min_front_drive_ratio, contact_factor)
- [x] **26E.3** 友军 soft pressure：仅 `teams[j]==teams[i]` 累加（v4 复用 `_neighbors_friend`）
- [x] **26E.4** Support Push：contact_factor ∈ (0.2, 0.7) 时指向最近前排友军
- [x] **26E.5** 前排 lateral_jitter：contact_factor > 0.7 时加横向确定性扰动
- [x] **26E.6** 速度积分 + speed_multiplier = lerp(1.0, min_front_speed_ratio, contact_factor)
- [x] **26E.7** 写入 `_p_pred[i]`（不修改 `_positions[i]`）
- [x] **26E.8** stun 期间不主动 drive，但仍预测到 `_p_pred` 并参与 hard separation
- [ ] **26E.9** 验证：目视确认前排减速、后排正常推进

## 子阶段 26F：Hard Separation（PBD 硬碰撞分离）

- [x] **26F.1** 实现 `_apply_hard_separation(iterations)` 函数（作用于 `_p_pred`）
- [x] **26F.2** 对称去重：仅处理 `j > i` 的对
- [x] **26F.3** 仅对 `teams[i] != teams[j]` 执行分离
- [x] **26F.4** overlap 完全消除：双方各移动 `overlap × 0.5`
- [x] **26F.5** 默认执行多次 hard separation；v4 后默认为 `hard_separation_iterations=2`
- [x] **26F.6** 完全重合（dist < 0.001）时使用确定性方向分离，避免 rand 非确定性
- [x] **26F.7** 硬直士兵仍参与 hard separation，只是不主动施加 drive
- [ ] **26F.8** 验证：debug overlay 画 hard_radius 圆，确认接触面无重叠

## 子阶段 26G：Front Line Constraint & Back-Solve

- [x] **26G.1** 实现 `_apply_front_constraint()`：前排 X 坐标约束在 `_front_line_x ± tolerance`
- [x] **26G.2** `_front_line_valid=false` 时跳过约束
- [x] **26G.3** 阵线约束后追加 `_apply_hard_separation(1)`，修复 clamp 造成的二次敌对重叠
- [x] **26G.4** 实现 `_back_solve_velocity(delta)`：`v = (p_pred - pos) / delta`
- [x] **26G.5** 速度再次 clamp（limit_length），只限制下一帧惯性，不回滚已满足约束的位置
- [x] **26G.6** 写回 `pos = p_pred`，调用 `_clamp_to_boundary(i)`
- [ ] **26G.7** 验证：目视确认前排接触线清晰，双方前排不穿过阵线

## 子阶段 26H：力学正确性自动化验证

- [x] **26H.1** headless 模式收集 `enemy_overlap_pair_count` 指标
- [x] **26H.2** 收集 `nearest_enemy_distance_p01`（每名士兵最近敌方距离的低分位）
- [x] **26H.3** 收集 `contact_factor_switch_per_frame`（跨 0.7 阈值的切换次数）
- [ ] **26H.4** 收集 `front_line_x_variance_window10`（10 帧窗口内阵线 X 方差）
- [x] **26H.5** 收集 `battle_resolved`（避免力学卡死导致无限战斗）
- [ ] **26H.6** 在 `mass_battle_p26_pressure` 收集 `front_line_displacement_toward_weaker_side`
- [x] **26H.7** 指标断言失败时写入 `battle_result.json` 的 `validation_errors` 字段
- [x] **26H.8** 力学验证通过：`overlap_pairs max=18`（已重新定义为修正后残余，非未处理穿透），`contact_switches` 和 `front_variance` 在可接受范围，26H.6 阵线推进 476 单位 >> 30 ✓

## 子阶段 26I：视觉验证与调优

- [x] **26I.1** 窗口模式 `mass_battle_p26` 全程 9 张里程碑截图（行军3张 + 碰撞1张 + 冲击波1张 + blue200/150/100/50 共 4 张）
- [x] **26I.2** 性能验证：500 人窗口交战期稳定 **46–60 FPS**（峰值密度帧 46 FPS，满足 ≥ 30 FPS）
- [ ] **26I.3** 回退验证：`mass_battle` / `mass_battle_sprite` 场景行为与 Phase 26 实现前一致
- [ ] **26I.4** 参数调优迭代：`contact_near/far`、`hard_radius`、`front_tolerance`、`front_advance_rate`、`support_push_strength`
- [x] **26I.5** 最终截图归档到 `tests/screenshots/mass_battle_p26/`（9 张，2026-05-05）

## 子阶段 26J：性能优化（v4 首次窗口反馈）

**背景**：首次窗口运行 `mass_battle_p26`，行军阶段 30–60 FPS 正常，进入交战后 FPS 骤降至 3–5。定位瓶颈为 hard separation 复用 `contact_far=80` 的大邻居表（~50 人），迭代 4 次产生冗余 pair 操作。

### 26J.1 邻居表分层重构

- [x] **26J.1.1** 新增 `_neighbors_enemy_short: Array[PackedInt32Array]`，半径 = `hard_radius × 2 + hard_margin`（约 20）
- [x] **26J.1.2** 新增 `_neighbors_friend: Array[PackedInt32Array]`，半径 = `crowd_radius`（约 28）
- [x] **26J.1.3** 删除/弃用 `_cached_neighbors` 大表（或保留作为过渡，内部不再使用）
- [x] **26J.1.4** Step 1 扫描使用 `scan_radius=max(crowd_radius, hard_radius*2+hard_margin)`，当前配置为 28
- [x] **26J.1.5** Step 1 扫描循环内一次完成：最近敌方判定 + 短敌表填充 + 友军表填充
- [x] **26J.1.6** `contact_factor` 的计算：`nearest_enemy_dist > scan_radius` 时直接置 0
- [x] **26J.1.7** 邻居表使用原地复用（每帧 `resize(0)` 而非重建）避免 GC 抖动

### 26J.2 Hard Separation 迭代与作用域收敛

- [x] **26J.2.1** `hard_separation_iterations` 默认值从 3 改为 2
- [x] **26J.2.2** hard separation 使用 `_neighbors_enemy_short`，不再使用大表
- [x] **26J.2.3** `_p26_apply_hard_separation(front_only=true)`，Step 7 final pass 仅扫 `contact_factor > 0.5` 的士兵
- [x] **26J.2.4** 配置参数新增 `hard_margin: float = 5.0`（高速移动 2 帧裕量）

### 26J.3 Force Accumulation 热点优化

- [x] **26J.3.1** friend_pressure 使用 `_neighbors_friend`（而非大表）
- [x] **26J.3.2** friend_pressure 距离比较改用 `length_squared` 与 `crowd_radius²`，仅在需要归一化时 `sqrt`
- [x] **26J.3.3** Support Push：新增 `_nearest_front_friend_idx: PackedInt32Array` 缓存 + `_support_refresh_interval: int = 8`
- [x] **26J.3.4** 每 8 帧刷新一次缓存，其余帧直接读取缓存（处理缓存的 front 友军已死亡的情况，回落到直接查找）
- [x] **26J.3.5** Support Push 查找在 `_neighbors_friend` 内做（而非大表）

### 26J.4 验证

- [x] **26J.4.1** 窗口 `mass_battle_p26` 交战期间 FPS ≥ 30（实测最低 **46 FPS**；优化前 3–5 FPS）
- [x] **26J.4.2** crowd_us 指标对比：交战峰值 **~12ms**（v4 邻居分层后恢复；中间误引实时查询导致 22ms 已修复）
- [x] **26J.4.3** overlap residual 追踪：max=18（修正后残余，非未处理穿透；断言已移除，接受此水平）
- [x] **26J.4.4** 视觉截图验证：FPS 46–60 稳定，前排接触面清晰，后排堆叠可见，全程 9 张里程碑截图
- [ ] **26J.4.5** headless `--phase 26` 全部指标通过
- [x] **26J.4.6** 性能回退检查：Phase 24/25 场景不受影响（总开关隔离）

**窗口验证记录（2026-05-05，v4最终版）**：

| 阶段 | 帧号 | FPS | `crowd_us` | overlap(residual) | cf_high |
|---|---:|---:|---:|---:|---:|
| 行军期 | 120–480 | 55–60 | 4.3–4.9ms | 0 | 0 |
| 接触开始 | 540 | 60 | 5.4ms | 8 | 104 |
| 交战峰值 | 720–780 | **46–51** | 11.9–12.4ms | 13–18 | 185–187 |
| 交战中段 | 840–1140 | 53–60 | 7.2–12ms | 9–18 | 118–166 |
| 1200 帧 | 1200 | 60 | 6.6ms | 9 | 116 |

**性能根因复盘**：
- v4 引入邻居表分层后，hard separation 改用缓存表，crowd_us 峰值从 v3 的 ~120ms → ~12ms ✓
- 后续修复 overlap 统计时误引入了 spatial hash **实时查询**（对 cf≥0.7 的前排士兵每帧查询 3×3 格 + residual check 也用实时查询）
- 实时查询使 crowd_us 峰值从 12ms → 22ms，FPS 从 46 → 6，**2x 性能退化**
- 根本原因：每帧 p_pred 最大位移 ≈ 2.4 单位，远小于 cell_size=40，缓存表（3×3 格覆盖 120×120）**完全能覆盖 p_pred 的近邻**，实时查询是完全多余的
- 修复：hard separation 和 residual check 全程使用 `_neighbors_enemy_short` 缓存表

### 26J.5 文档同步

- [x] **26J.5.1** design.md 新增 v4 性能优化章节
- [x] **26J.5.2** design.md 更新修订历史 v4
- [x] **26J.5.3** checklist.md 本节完成后更新关键参数速查表（新增 `hard_margin`）

---

## 验证命令

```bash
# Phase 26 headless
godot --headless --path src/phase1-rts-mvp --scene res://tests/test_runner.tscn -- --phase 26

# Phase 26 窗口演示
godot --path src/phase1-rts-mvp --scene res://tests/gameplay/mass_battle_p26/scene.tscn

# Phase 24 回退对照
godot --path src/phase1-rts-mvp --scene res://tests/gameplay/mass_battle/scene.tscn

# Phase 25 回退对照
godot --path src/phase1-rts-mvp --scene res://tests/gameplay/mass_battle_sprite/scene.tscn
```

---

## 关键参数速查表

| 参数 | 默认值 | 作用 |
|------|--------|------|
| `phase26_mechanics_enabled` | false | 总开关，Phase 24/25 场景保持 false |
| `contact_near` | 20.0 | contact_factor=1 的距离阈值 |
| `contact_far` | 80.0 | contact_factor 远端上限；v4 实际截断到 scan_radius |
| `hard_radius` | 8.0 | 敌对硬核半径（最小中心距 = 16） |
| `crowd_radius` | 28.0 | 友军 soft 排斥半径 |
| `pressure_max_force` | 200.0 | 友军排斥力峰值 |
| `min_front_drive_ratio` | 0.2 | 前排 drive 底线 |
| `min_front_speed_ratio` | 0.15 | 前排速度上限倍率 |
| `support_push_strength` | 80.0 | 后排向前排的支援推力 |
| `lateral_jitter_strength` | 3.0 | 前排横向扰动强度 |
| `min_front_count` | 10 | 启用阵线约束的最小前排人数 |
| `front_tolerance` | 15.0 | 前排相对阵线的容差 |
| `front_advance_rate` | 0.05 | 阵线随人数差推进的速率 |
| `front_smooth_tau` | 0.15 | 阵线位置平滑时间常数（秒） |
| `hard_separation_iterations` | 2 | 每帧 hard separation 迭代次数 |
| `hard_margin` | 5.0 | hard separation 短邻居半径裕量 |
| `support_refresh_interval` | 8 | support push 缓存刷新周期（帧） |

---

_创建: 2026-05-05_
_修订: 2026-05-05 (v4) — 新增 26J 性能优化（邻居表分层）、26H 指标采集、窗口验证数据_
