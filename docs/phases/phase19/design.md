# Phase 19 设计文档 — 路径跟随行军系统

**所属项目**: AI Native RTS
**状态**: 实现中
**创建**: 2026-04-11
**上游文档**: [gameplay-vision.md](../../design/game/gameplay-vision.md)、[phase16/design.md](../phase16/design.md)、[phase17/design.md](../phase17/design.md)

---

## 目标

将行军纵队从"整体平移"改为**路径跟随**：每个士兵沿前一个士兵走过的历史轨迹行进，产生真实的"排队出发、逐渐跟上"的蛇形队列感。

类比：AoE2 的行军是整体平移；本 Phase 目标更接近真实行军——队头先动，后排士兵一个接一个沿同一条路跟上。

**本 Phase 只修改行军目标点的计算逻辑（`_get_march_slot`），不改变物理驱动、槽位接口、列阵状态机**。

---

## 核心机制对比

| 维度 | Phase 16/17（整体平移） | Phase 19（路径跟随） |
|------|----------------------|-------------------|
| 行军目标点来源 | 将领当前位置 - 方向 × 排距 | 将领历史轨迹中第 N 个点 |
| 队尾响应时机 | 与将领同时响应 | 延迟响应（轨迹点尚未到达时等在最远点） |
| 视觉感受 | 一块整体移动的方块 | 蛇形拖尾，队头先出发，队尾慢慢跟上 |
| path_buffer | 记录但不使用 | 核心输入 |

---

## 算法设计

### path_buffer 结构

将领在 MARCHING 状态下，每隔 `path_sample_interval` 帧将当前位置压入 `_path_buffer`（已有实现，Phase 16 写入但未用于槽位计算）。

```
_path_buffer 索引：
  [0] = 最新位置（最近将领走过的点）
  [1] = 次新位置
  ...
  [N] = 最旧位置（最远的历史点）
```

### 纵队槽位计算（_get_march_slot 重写）

```
士兵编号 → 排编号 row = index / march_column_width
         → 列编号 col_slot = index % march_column_width
         → 列偏移 col_offset = col_slot - (march_column_width - 1) / 2

路径点索引 path_idx = row × march_row_path_step

若 path_buffer 长度 > path_idx：
    anchor = path_buffer[path_idx]
否则（路径点不足，队伍还没走那么远）：
    anchor = path_buffer 最后一个点（队尾原地等待）

横向方向 lateral_dir = 队头前进方向旋转 90°（用 path_buffer[0] 与将领当前位置推算，或保持 _march_direction）

目标点 = anchor + lateral_dir × deploy_col_spacing × col_offset
```

### 关键参数

| 参数 | 含义 | 建议默认值 |
|------|------|-----------|
| `march_column_width` | 纵队列数 | 3（从 6 改小） |
| `march_row_path_step` | 每排间隔几个历史路径点 | 4 |
| `path_sample_interval` | 每几帧采一个历史点（已有） | 5 |
| `path_buffer_size` | 最大历史点数（已有） | 60 |

**排间物理距离推算**：  
`march_row_path_step × path_sample_interval × 将领速度/fps`  
= `4 × 5 × (180/60)` = `4 × 5 × 3` = `60 units/排`（与现有 row_spacing 接近）

### 横向方向计算

MARCHING 状态下用 `_march_direction`（已有，每帧实时更新），不需要从 path_buffer 重新推算。转弯时 `_march_direction` 先更新，横向方向随之修正，列间不会扭曲。

### path_buffer 不足时的回退行为

将领刚开始移动，path_buffer 还没攒够点时：
- 第 0 排（最前）：`path_buffer[0]`（将领当前位置附近）
- 第 N 排（无对应点）：取 `path_buffer` 最后一个点，士兵在队尾聚集等待，随着路径逐渐拉长自然展开

这产生"队伍从后方逐渐解开"的视觉效果。

---

## 状态机影响

DEPLOYED 状态（横阵展开）**不受影响**，`_get_deploy_slot` 逻辑不变。

### MARCHING → DEPLOYED 切换条件（修改）

Phase 16 原始条件：将领静止超过 `deploy_trigger_frames` 帧即展开。

**Phase 19 新条件**：计时器从"全员到位"那一刻开始计，而非从将领停止开始：

```
将领已停止
  且 avg_slot_error < deploy_ready_threshold（全员到位）
  → _deploy_timer 开始递增
  → _deploy_timer >= deploy_trigger_frames → 切换 DEPLOYED

若士兵仍在赶路（avg_slot_error >= threshold）：_deploy_timer 重置为 0，不计时
若将领重新移动：_deploy_timer 重置，切回 MARCHING
```

这确保队尾最后一个士兵走到位后，再等一小段确认帧（`deploy_trigger_frames`），才展开横阵。

`deploy_ready_threshold`：判定"全员到位"的误差阈值，建议默认 45（`arrive_threshold × 3`）。

### DEPLOYED → MARCHING 切换时

清空 `path_buffer`（已有逻辑），路径跟随从零开始重新积累。所有士兵 `_waiting` 重置为 `true`。

---

## Arrival Steering（归队加速）

原始 Seek Force 是恒定力，士兵距目标近时仍以全力冲过去，导致抖动和过头。

**Arrival Steering**：力随距离线性缩放：

```
speed_factor = clamp(dist / slow_radius, 0.0, 1.0)
force = dir × drive_strength × speed_factor
```

- 距目标 > `slow_radius`：全力追赶，快速归队
- 距目标 < `slow_radius`：线性减速，平滑到位
- 距目标 < `arrive_threshold`：停止施力，靠阻尼停下

| 参数 | 含义 | 建议默认值 |
|------|------|-----------|
| `dummy_slow_radius` | 开始减速的距离阈值 | 120 |
| `dummy_drive_strength` | 最大驱动力 | 1600 |

---

## 与现有代码的关系

| 改动范围 | 说明 |
|---------|------|
| `general_unit.gd` → `_get_march_slot()` | **重写**：从锚点平移改为路径点查找 |
| `general_unit.gd` → `_update_path_buffer()` | **不变**：已经在记录轨迹 |
| `general_unit.gd` → `get_formation_slot()` | 新增 `current_pos` 参数 |
| `general_unit.gd` → `_get_deploy_slot()` | **不变** |
| `general_unit.gd` → `_detect_formation_state()` | **重写**：全员到位才展开 |
| `general_unit.gd` → `get_formation_summary()` | **新增**：阵型整齐度摘要 |
| `dummy_soldier.gd` | **重写**：稳定目标点 + Arrival Steering + NavMesh + RVO |
| `config.json` | 新增多个参数（见关键参数表） |
| `general_visual/bootstrap.gd` | 新增 AIRenderer + 可视化调试层 |

---

## DummySoldier 寻路方案（NavMesh + RVO）

### 为什么需要寻路

当前 Seek Force 是直线冲向目标，士兵被前排堆挡时无法绕路，物理推挤解决拥堵效率低。

### 方案：NavigationAgent3D + avoidance_enabled

每个 DummySoldier 添加 `NavigationAgent3D`，复用将领已有的 NavMesh：

```
setup 时：
  agent.target_position = _my_target
  agent.avoidance_enabled = true      ← RVO 动态避让
  agent.radius = _collision_radius    ← 与碰撞体半径一致

_physics_process 每帧：
  next_pos = agent.get_next_path_position()   ← NavMesh 路径下一点
  final_vel = agent.get_final_velocity()       ← RVO 修正后速度（avoidance 回调）
  apply_central_force(final_vel.normalized() × drive_strength × speed_factor)
```

NavMesh 负责绕地形，RVO 负责动态避让其他士兵，两层结合产生流畅的群体运动。

### 关键参数（新增）

| 参数 | 含义 | 建议默认值 |
|------|------|-----------|
| `dummy_nav_path_distance` | NavAgent path_desired_distance | 15.0 |
| `dummy_nav_target_distance` | NavAgent target_desired_distance | 15.0 |
| `dummy_nav_neighbor_distance` | RVO 感知范围 | 60.0 |
| `dummy_nav_max_neighbors` | RVO 最大感知邻居数 | 10 |

---

## 验证标准

**完成标准**：
- 将领开始移动时，最前排士兵立即跟随，后排士兵依次延迟出发，视觉上呈蛇形拖尾
- 转弯时队列跟随曲线，不产生横向闪跳
- path_buffer 不足时（刚出发），后排士兵聚集在最远点，随路径拉长自然展开
- 将领停止后，士兵沿各自轨迹走到位，自然收拢，再展开横阵
- headless 全回归：`general_marching`、`general_deployed`、`formation_switch` 全部 PASS

---

## 体验质量规格（19C）

### 为什么需要体验质量规格

Phase 19A/19B 实现了机制正确性（到没到位），但缺乏**过程质量**的量化标准。
仅凭 `avg_slot_error` 无法发现：
- 行军途中挤成一团（挤团感知盲区）
- 展开瞬间出现物理爆炸（爆炸感知盲区）
- 士兵到达槽位后继续远离（overshoot 感知盲区）
- 士兵各自为战、方向混乱（队形感知盲区）

### 三阶段质量标准

#### 行军阶段（marching）

| 指标 | 含义 | 通过标准 | 告警条件 |
|------|------|---------|---------|
| `pos_std_dev` | 所有士兵位置的标准差（XZ平面） | 50 ~ 300 | < 30（挤团）或 > 400（散兵） |
| `lateral_spread` | 垂直于行军方向的横向离散度 | < 列宽 × 1.5 ≈ 60 | > 120（队形崩溃）|
| `velocity_coherence` | 速度方向余弦相似度均值（-1 ~ 1） | > 0.5 | < 0.2（各奔东西）|

#### 展开过渡阶段（marching → deployed，前 120 帧）

| 指标 | 含义 | 通过标准 | 告警条件 |
|------|------|---------|---------|
| `pos_std_dev` | 同上 | 不骤降 > 50%（单帧） | 单帧降幅 > 50%（爆炸 / 瞬移）|
| `overshoot_count` | 已到达但本帧距离反而变大的士兵数 | 0 | > 3（过冲 bug）|
| `convergence_speed` | 每帧 arrived_count 增速 | 稳定上升 | 持续 60 帧不增加（卡死）|

#### 横阵稳定阶段（deployed，freeze 后）

| 指标 | 含义 | 通过标准 | 告警条件 |
|------|------|---------|---------|
| `freeze_rate` | 已 freeze 士兵比例 | = 1.0（全员 freeze） | < 0.9（有士兵未稳定）|
| `avg_slot_error` | 均值槽位误差 | < 15（到达阈值内） | > 30（仍有人未到位）|

### 新增感知指标说明

**`pos_std_dev`**（位置标准差）
- 计算所有士兵 XZ 位置相对于质心的均方差
- 正常纵队（3列×10排）预期约 150-250 units
- 挤团时降至 < 30，散乱时升至 > 400
- 发出移动命令后前 120 帧内此值骤降 → 确认"挤团"bug

**`lateral_spread`**（横向离散度）
- 将所有士兵位置投影到 `_march_direction` 的垂直方向
- 标准差即横向离散度
- 正常纵队应 ≈ `deploy_col_spacing` × 1.0（列间距）
- 超过 2× 列间距说明横向队形已崩塌

**`overshoot_count`**（过冲士兵数）
- 在 `get_formation_summary()` 中与上一帧的各士兵距槽位误差对比
- 若某士兵已满足 `dist < arrive_threshold`，下一帧 dist 反而 > arrive_threshold → 计入 overshoot
- 用于检测"到了又跑远"的 bug

**`velocity_coherence`**（速度一致性）
- 仅 RigidBody3D 可访问 `linear_velocity`
- 通过 `get("linear_velocity")` 读取各士兵速度
- 所有速度方向与均值方向的余弦均值

### 感知系统数据流

```
每帧 get_formation_summary() 返回：
  行军阶段：pos_std_dev / lateral_spread / velocity_coherence
  过渡阶段：overshoot_count / convergence_speed
  稳定阶段：freeze_rate / avg_slot_error

bootstrap.gd 每 10 帧打印：
  [DBG] state / pos_std_dev / lateral_spread / overshoot / freeze_rate

告警阈值触发时立即打印 [WARN] + 截图
```

---

## 纵队轨迹重置（19F）

### 问题

deployed→marching 切换时，path_buffer 保留着上一次行军的历史轨迹：
- 将领从 A 走到 B，展开横阵
- 再次移动时，path_buffer 里还有 A→B 的旧点
- 后排士兵（row 3~9）的槽位对应 path_buffer 深处的旧点（A 方向）
- 士兵往 A 方向跑，与将领新移动方向完全相反

### 正确逻辑

**deployed 是轨迹的天然消费终点**：横阵展开意味着这段路程已经走完，路径历史已被"消费"，不应再被后续行军复用。

切换时机：`move_to()` 被调用且当前 `_formation_state == "deployed"` 时，**清空 path_buffer**，让新行军从将领当前位置重新积累轨迹点。

```
将领从 A→B（deployed）
    ↓ move_to(C) 发出
    ↓ path_buffer.clear()   ← 旧轨迹清除
    ↓ 将领开始移动到 C
    ↓ path_buffer 从 B 开始重新积累 B→C 的新点
    ↓ slot 1 = B 附近第一个点
    ↓ slot 2 = 第二个点...
    ↓ 士兵沿 B→C 路径形成蛇形纵队  ✅
```

### 与"不清空防散兵"注释的关系

旧注释说"不清空 path_buffer 防止散兵"——那是针对**纯 marching 状态下反复发命令**的情况（没有经过 deployed），此时清空会导致哑兵短暂失去目标点。

**经过 deployed 再出发**是不同情况：所有哑兵已在横阵槽位 freeze，不存在"失去目标点"问题，可以安全清空。

### 实现

`move_to()` 中：
```
if _formation_state == "deployed":
    _path_buffer.clear()   ← 新增
    _path_sample_timer = 0
    _formation_state = "marching"
    _rebuild_slot_assignment("marching")
```

### 延伸问题：虚拟锚点导致全员同时出发

path_buffer 清空后将领刚开始移动，buffer 只有少量新点。虚拟锚点推算逻辑会为
所有 path_buffer 不足的排生成"沿行军反方向的估算点"，导致 15 排士兵同时冲向
将领后方很小的区域，产生"全员同时出发"的混乱感。

**根本修复（19G）**：移除虚拟锚点推算，path_buffer 不足时一律返回 `current_pos`
（原地等待）。deployed 后哑兵已分散在横阵各位置，原地等待不会产生挤团，
可以安全地产生真正的多米诺启动效果：前排路径点先到，前排先动，后排依次解锁。

---

## 多米诺启动 — 移除虚拟锚点（19G）

### 问题

`_get_march_slot` 中，当 path_buffer 不足时使用虚拟锚点（沿 `_march_direction` 反向推算），
导致所有后排士兵同时获得有效目标点并立即出发，失去多米诺效果。

### 解法

移除虚拟锚点推算，path_buffer 不足时返回 `current_pos`（原地等待）：

```
if _path_buffer.size() > path_idx:
    anchor = _path_buffer[path_idx]
elif _has_command:
    ## 旧逻辑：虚拟锚点推算 ← 删除
    return current_pos  ← 新逻辑：原地等待
else:
    return current_pos
```

### 效果

- 将领开始移动，path_buffer 逐渐积累
- row 0 对应 path_buffer[lead_offset]，路径点最快到达，最先解锁
- row 1 对应更深的索引，稍后解锁
- 后排依次解锁，产生真正的蛇形多米诺启动感
- deployed→marching 后哑兵已分散在横阵，原地等待不会挤团

### 前提条件

需要 19F（deployed 时清空 path_buffer）已实现：
- 若不清空，后排路径点用的是旧轨迹的深处点，哑兵会往旧方向跑
- 清空后重新积累，所有路径点都属于当前这段行军，方向正确

---

## 槽位最近邻分配（19E）

### 问题

阵型切换时（marching↔deployed），士兵的槽位由 `index` 固定绑定：
- soldier 0 → slot 0，soldier 15 → slot 15
- 切换时右侧士兵可能被分配到左侧槽，左侧士兵被分配到右侧槽
- 大量士兵路径交叉对跑，看起来混乱且低效

### 解法：切换时做一次最近邻贪心重新分配

**时机**：`_formation_state` 发生切换的那一帧（marching→deployed 或 deployed→marching）

**算法**：
```
输入：N 个士兵当前位置，N 个目标槽位坐标
输出：soldier_i → slot_j 的一一映射

贪心最近邻：
  while 未分配的（士兵, 槽位）对 > 0：
    找所有未分配对中距离最小的 (i, j)
    将 soldier_i 分配到 slot_j
    移出 i 和 j
```

复杂度 O(N²)，N=30 时单帧计算量可忽略不计。

**实现位置**：`general_unit.gd`
- 新增 `_slot_assignment: Dictionary`（key=soldier_index, value=slot_index）
- 新增 `_rebuild_slot_assignment(formation_state: String)`：在状态切换时调用
- `get_formation_slot(index, total, current_pos)` 改为先查 `_slot_assignment`，无记录时退回原 index

**何时重新分配**：
- `_detect_formation_state()` 确认切换到 "deployed" 时
- `move_to()` 被调用时（deployed→marching）

### 效果

- 每个士兵走最短路径到最近可用槽位
- 无路径交叉，整体收敛更快
- 体验上：阵型切换看起来"就地折叠/展开"，而不是交叉乱跑

---

## 参数自动优化（19D）

### 为什么需要参数优化

Phase 19C 建立了 benchmark 量化评分体系，但参数调整仍靠人工猜测。
`config.json` 中有十几个相互影响的物理参数（drive_strength、linear_damp、slow_radius 等），
手工调参效率低、容易陷入局部最优。

### 方案：贝叶斯优化（Optuna）

外层 Python 优化循环，benchmark score 作为目标函数：

```
循环：
  1. Optuna 采样一组参数 → 写入 config.json general 节点
  2. 启动 Godot --benchmark 模式，等待退出（~90s/次）
  3. 读取最新 result_*.json，取 overall_score
  4. Optuna 记录结果，决定下一组参数
  5. 保存历史最优参数到 best_params.json

终止条件：手动中止 或 达到最大 trial 数（默认 50）
```

### 优化参数空间

| 参数 | 含义 | 搜索范围 |
|------|------|---------|
| `dummy_drive_strength` | 最大驱动力 | 400 ~ 3200 |
| `dummy_linear_damp` | 行军阻尼 | 4 ~ 16 |
| `dummy_slow_radius` | 减速开始距离 | 60 ~ 300 |
| `dummy_arrive_threshold` | 到位判定距离 | 8 ~ 30 |
| `march_column_width` | 纵队列数 | 2 ~ 4（整数）|
| `march_row_path_step` | 排间路径步数 | 2 ~ 8（整数）|
| `march_lead_offset` | 队首路径偏移 | 1 ~ 6（整数）|
| `deploy_trigger_frames` | 展开确认帧数 | 10 ~ 60（整数）|
| `deploy_ready_threshold` | 展开误差阈值 | 20 ~ 80 |

### 文件结构

```
tests/benchmark/
  optimize.py          ← Optuna 优化主程序
  best_params.json     ← 历史最优参数（每次更新）
  optuna_study.db      ← Optuna SQLite 存储（可 resume）
  result_*.json        ← 每次 benchmark 结果
  run_benchmark.sh     ← 已有，复用
```

### 使用方式

```bash
# 安装依赖
pip install optuna

# 启动优化（默认 50 trials，可中断后 resume）
cd src/phase1-rts-mvp
python tests/benchmark/optimize.py

# 查看当前最优参数
cat tests/benchmark/best_params.json

# 把最优参数应用到 config.json
python tests/benchmark/optimize.py --apply-best
```

### 与手工调参的关系

优化器负责探索大范围参数空间，找到"数值上最优"的参数组合。
人工负责验证体验是否符合直觉（数值好不代表手感好），
以及在体验不满意时调整评分权重或新增惩罚项。

---

_创建: 2026-04-11_
_更新: 2026-04-18 — 补充体验质量规格（19C）；2026-04-18 — 新增参数自动优化方案（19D）；2026-04-18 — 新增槽位最近邻分配方案（19E）；2026-04-18 — 纵队轨迹重置（19F）；2026-04-18 — 多米诺启动/移除虚拟锚点（19G）_
