# Phase 23 设计文档 — 多行军算法可切换架构 + 手柄输入

**所属项目**: AI Native RTS
**状态**: 实现中
**创建**: 2026-04-21
**上游文档**: [phase19/design.md](../phase19/design.md)、[phase22/design.md](../phase22/design.md)

> **Phase 22 承接说明**：Phase 22 的设计文档已完成（手柄输入方案、Context Steering 算法），但全部实现任务未执行。Phase 23 在多行军算法框架基础上，一并完成 Phase 22 的遗留实现。

---

## 目标

将行军驱动逻辑从硬编码的单一方案（Phase 19 path_follow）改为**可配置多算法切换**，支持通过 config 一键切换行军算法，配合已有的 19C 感知指标体系做数据化 A/B 对比评估。

---

## 动机

Phase 19 实现了路径跟随行军，但窗口模式下士兵行进体验"卡"：

1. **四重避让冲突**：NavAgent + RVO + Context Steering + 物理碰撞同时生效，方向互相干扰
2. **目标点跳变**：path_buffer 每帧 push_front 导致同一 slot 坐标帧间漂移，Arrival Steering 反复加减速
3. **queue 边缘挣扎**：30 人 ÷ 2 列 = 15 排，队尾 path_idx=115 接近 buffer_size=120，频繁落入等待-解锁循环

不确定哪种替代方案实际效果最好，因此采用**多算法并存 + 数据评估**的方式，用数据选最优。

---

## 候选算法

### A: path_follow（现有 Phase 19 方案）

- **思路**：士兵锁定 path_buffer 历史点作为目标，到位后查下一个点
- **避让**：窗口模式 NavAgent + RVO + Context Steering，headless 直线 Seek
- **力源**：4 重（NavAgent 方向 / RVO 修正 / Context Steering / 物理碰撞）
- **优点**：蛇形拖尾感、多米诺启动
- **缺点**：方向冲突、目标跳变、卡死频繁

### B: flow_field（局部流场方案）

- **思路**：将领路径生成局部流场，士兵查脚下流场方向 + 编队槽位偏移
- **避让**：仅物理碰撞（RigidBody3D 自然推挤）
- **力源**：2 重（流场方向 + 物理碰撞）
- **参考**：Game AI Pro Ch.23 *"Crowd Pathfinding and Steering Using Flow Field Tiles"*; Supreme Commander 2

**流场生成算法**：

```
输入：将领 path_buffer（历史轨迹点序列）
输出：局部方向场 Dictionary<Vector2i, Vector3>

1. 以 path_buffer 为中心线，两侧各扩展 field_half_width 格
2. 每个格子的方向 = 沿轨迹前进方向插值
3. 格子分辨率 = field_cell_size（默认 20 units）
4. 只覆盖将领走过的路径周围，不做全图

查询：
  cell = floor(soldier_pos / field_cell_size)
  flow_dir = field.get(cell, _march_direction)  # 无数据时退回行军方向
  target = soldier_pos + flow_dir * step_size + lateral_offset
```

**优点**：
- 所有士兵方向天然一致（同一流场）→ velocity_coherence 高
- 转弯时流场自动弯曲 → 无横向闪跳
- 去掉 NavAgent/RVO/CS → 力源简化，无方向冲突

**缺点**：
- 需要实现流场生成和查询（约 100 行代码）
- 流场更新频率需要调节（太快浪费、太慢滞后）

### C: direct_seek（极简基线）

- **思路**：每帧直接查 `_get_march_slot` 作为即时目标（不锁定），Seek + Arrive
- **避让**：仅物理碰撞
- **力源**：2 重（直线 Seek + 物理碰撞）

**优点**：最简单，无任何中间层，0 额外状态
**缺点**：无蛇形感、转弯时可能路径交叉、密集区依赖物理推挤

---

## 配置接口

```json
{
  "general": {
    "march_algorithm": "path_follow",
    // ... 各算法共享参数
    "flow_field_cell_size": 20.0,
    "flow_field_half_width": 4,
    "flow_field_update_interval": 10
  }
}
```

`march_algorithm` 取值：`"path_follow"` | `"flow_field"` | `"direct_seek"`

默认 `"path_follow"`，向后兼容。

---

## 代码架构

### DummySoldier 改动

```
_physics_process() 的 marching 分支：

match _march_algorithm:
    "path_follow":
        _march_path_follow()    # 现有逻辑原封不动搬入
    "flow_field":
        _march_flow_field()     # 新增
    "direct_seek":
        _march_direct_seek()    # 新增
```

每个方法独立计算 `force_dir`，最终统一走 `apply_central_force(force_dir.normalized() * _drive_strength * speed_factor)`。

deployed 状态逻辑**不受影响**（横阵展开与行军算法无关）。

### GeneralUnit 改动

```
新增（仅 flow_field 算法使用）：
  _flow_field: Dictionary = {}          # <Vector2i, Vector3>
  _flow_field_cell_size: float = 20.0
  _flow_field_half_width: int = 4
  _flow_field_update_interval: int = 10
  _flow_field_timer: int = 0

  _update_flow_field() → void           # 每 N 帧重建局部流场
  get_flow_direction(pos: Vector3) → Vector3  # 士兵查询接口
```

现有 path_buffer、slot 分配等逻辑**全部保留**（path_follow 和 flow_field 都用 path_buffer）。

### 新增评估指标

| 指标 | 含义 | 采集位置 |
|------|------|---------|
| `stuck_nudge_count` | 卡死扰动触发次数 | DummySoldier |
| `convergence_frames` | 横阵收敛帧数（从将领停止到 freeze_rate=1.0） | GeneralUnit |
| `direction_change_rate` | 每帧力方向变化角度均值 | DummySoldier |

这三个指标加入 `get_formation_summary()`，与现有指标一起输出。

---

## A/B 评估框架

### 评估路线

| 路线 | 描述 | 考察重点 |
|------|------|---------|
| 直线 | 将领直线走 500 units | 纵队整齐度、速度一致性 |
| L 形 | 直线 300 → 右转 90° → 直线 300 | 转弯队形保持 |
| S 形 | 连续两次反向转弯 | 频繁变向时的稳定性 |
| 静止展开 | 将领停止，等待横阵收敛 | 收敛速度、卡死次数 |

### benchmark 脚本

```
tests/benchmark/compare_algorithms.py

for algo in ["path_follow", "flow_field", "direct_seek"]:
    for route in ["straight", "l_turn", "s_turn", "deploy"]:
        for trial in range(3):
            修改 config.json → march_algorithm = algo
            启动 Godot --headless --benchmark --scene {route}
            读取 result.json
            记录各指标

输出：
  compare_result.json  — 原始数据
  compare_report.md    — 对比表 + 结论
```

### 评分公式

```
score = w1 × velocity_coherence
      + w2 × (1 - lateral_spread/120)
      + w3 × (1 - avg_slot_error/80)
      + w4 × (1 - stuck_nudge_count/20)
      + w5 × (1 - convergence_frames/300)

默认权重：w1=0.25, w2=0.2, w3=0.2, w4=0.2, w5=0.15
```

---

## 与现有系统的关系

| 模块 | 影响 |
|------|------|
| `dummy_soldier.gd` | marching 分支拆 3 个方法，新增 `_march_algorithm` 字段 |
| `general_unit.gd` | 新增流场生成/查询接口，现有逻辑不变 |
| `config.json` | 新增 `march_algorithm` + 流场参数 |
| `get_formation_summary()` | 新增 3 个评估指标 |
| headless 测试 | 不受影响（默认 path_follow） |
| benchmark | 新增 `compare_algorithms.py` |

---

---

## 手柄输入设计（23F — 承接 Phase 22）

### 场景定位

`tests/gameplay/gamepad_test/` — 单方将领 + 30 哑兵，无战斗单位，专为手柄交互验证。
复用 `general_visual` 全部逻辑（调试层、阵型感知日志），额外加手柄输入。

### 将领移动映射

```
左摇杆 (axis_x, axis_y)
  → 死区过滤：|magnitude| < 0.15 时忽略
  → 世界方向转换：
      cam_basis = 摄像机的 basis（去掉 Y 分量后归一化）
      world_dir = (cam_basis × Vector3(axis_x, 0, axis_y)).normalized()
  → 每 20 帧：move_to(将领当前位置 + world_dir × 200)
  → 松开（magnitude < 0.15）：停止发 move_to，将领减速停止
```

### 摄像机朝向适配

等距摄像机朝向约为水平旋转 -45°（右转），垂直俯角 -45°。
摇杆"向上"（axis_y = -1）应对应世界坐标斜前方（+X+Z 方向）。

转换方法：取摄像机节点的 `global_transform.basis`，提取 X 轴和 -Z 轴分别作为"右"和"前"方向，投影到 XZ 平面后归一化，再与摇杆分量组合。

### 与鼠标右键并存

`move_to()` 接口统一，手柄和鼠标都调用同一接口，互不干扰。
手柄输入在 `bootstrap.gd` 的 `_physics_process` 中读取，不占用 `_unhandled_input`（鼠标点击走 `_input`）。

### Context Steering 接入确认

`_context_steer()` 已随 Phase 23A 重构纳入 `_march_path_follow()` 的 fallback 分支。
手柄场景使用默认 `march_algorithm = "path_follow"`，Context Steering 自动生效。

---

_创建: 2026-04-21_
_更新: 2026-04-21 — 补充手柄输入章节（承接 Phase 22）_
