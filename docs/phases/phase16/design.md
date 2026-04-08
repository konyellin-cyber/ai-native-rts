# Phase 16 设计文档 — 行军阵型系统

**所属项目**: AI Native RTS
**状态**: 草案
**创建**: 2026-04-04
**上游文档**: [gameplay-vision.md](../../design/game/gameplay-vision.md)、[phase15/design.md](../phase15/design.md)

---

## 目标

验证核心手感：**行军时哑兵自然形成纵队，将领停止后自动展开横阵**。

类比帝国时代2的行军感——远途是细长纵队，到达目的地后展开列阵准备战斗。不涉及士气、溃败、敌方 AI——那些在 Phase 17+ 验证。

---

## 子阶段拆分

```
Phase 16A — 路径队列 + 行军纵队
  交付物：将领移动时，哑兵跟随路径历史点形成纵队
  验证点：纵队形态是否自然；转弯时是否跟随曲线

Phase 16B — 静止展开横阵
  交付物：将领停止后，纵队自动展开为横阵
  验证点：展开速度是否自然；横阵朝向是否正确（面朝行进方向）

Phase 16C — 状态切换流畅性
  交付物：行军 → 展开 → 再行军 循环无卡顿
  验证点：重新行军时横阵"收起"重新排队；无穿插/闪跳
```

---

## 核心状态机

哑兵的跟随目标由将领的**阵型状态**决定：

```
MARCHING（行军）              DEPLOYED（列阵）
  将领速度 > 阈值                将领静止超过 T 帧
       ↓                              ↓
  士兵目标 = 将领当前位置        士兵目标 = 将领前方横阵格位
           - 行军方向 × 排距              形成横阵
  形成纵队（整体平移）

  将领重新移动 ──────────────────────────→ 切回 MARCHING
```

状态存储在 `GeneralUnit._formation_state: String`（"marching" | "deployed"）。

---

## Phase 16A：路径队列 + 行军纵队

### 路径队列（Path Buffer）

`GeneralUnit` 在 MARCHING 状态下，每隔 `path_sample_interval` 帧采样一次自身位置，存入定长环形队列 `_path_buffer`（最多 `path_buffer_size` 个点）。

```
将领路径（从近到远）：
  [将领当前位置] → P0 → P1 → P2 → P3 → P4 → ···

路径采样间隔：每 5 帧一个点（可配置）
最大历史长度：60 个点（可配置）
```

### 纵队排列算法（AoE2 整体平移风格）

**核心原则**：纵队以将领**当前位置**为锚点实时计算，整体跟随将领平移，而非分布在历史路径轨迹上。

```
士兵编号 → 排编号 row = index / march_column_width
         → 列编号 col_slot = index % march_column_width
         → 列偏移 col_offset = col_slot - (march_column_width - 1) / 2
目标点   = 将领当前位置
         - _march_direction × deploy_row_spacing × (row + 1)
         + 横向方向 × deploy_col_spacing × col_offset
```

横向方向 = `_march_direction` 在 XZ 平面旋转 90°。
行军方向 `_march_direction` 每帧实时更新（将领移动时），不再等路径采样间隔。
发出新移动命令（`move_to`）时立即更新方向。

路径缓冲区 `_path_buffer` 仍然保留（供未来转弯平滑等功能使用），但不再用于纵队槽位计算。

### 对 GeneralUnit 的修改

新增字段：
- `_path_buffer: Array[Vector3]`：历史位置环形队列
- `_path_sample_timer: int`：采样帧计数
- `_march_direction: Vector3`：最后有效前进方向（展开横阵时用）
- `_deploy_timer: int`：静止帧计数
- `_formation_state: String`：当前阵型状态

新增方法：
- `get_formation_slot(index: int, total: int) -> Vector3`：士兵查询目标点的唯一接口
- `_update_path_buffer()`：每帧采样更新
- `_detect_formation_state()`：判断是否切换 MARCHING / DEPLOYED

废弃：
- `get_anchor_position()`（原 Phase 15 圆形聚集接口）由 `get_formation_slot()` 替代，保留向后兼容空实现

### 对 DummySoldier 的修改

- 废弃 `_ring_offset` 和预计算环形偏移
- 每帧调用 `_general.get_formation_slot(_soldier_index, _total_count)` 获取目标点
- 匀速向目标点移动（无加速度过渡，`_move_toward` 逻辑不变）

---

## Phase 16B：静止展开横阵

### 触发条件

将领速度接近零，持续 `deploy_trigger_frames`（默认 30 帧）→ 切换到 DEPLOYED。

### 横阵布局算法

横阵以将领为基点，朝 `_march_direction` 前方展开：

```
将领面朝方向（_march_direction）：→

横阵布局示意（march_column_width = 8，排数 = ceil(total / 8)）：

  第1排：□ □ □ □ □ □ □ □   （距将领 deploy_row_spacing × 1）
  第2排：□ □ □ □ □ □ □ □   （距将领 deploy_row_spacing × 2）
  第3排：□ □ □ □ □ □ ·····
  将领：  ★  （在横阵后方）
```

格位计算：
```
士兵编号 → 排编号 row = index / deploy_columns
         → 列编号 col = index % deploy_columns
目标点   = 将领位置
         + _march_direction × deploy_row_spacing × (row + 1)
         + 横向方向 × deploy_col_spacing × (col - deploy_columns/2 + 0.5)
```

`deploy_columns`（横阵列数）默认与 `march_column_width` 相同，可独立配置。

### 朝向冻结

将领进入 DEPLOYED 后，`_march_direction` 冻结不再更新。
若将领原地无移动历史（直接静止生成），`_march_direction` 默认为 `Vector3(0, 0, -1)`（朝北）。

---

## Phase 16C：状态切换流畅性

### DEPLOYED → MARCHING（将领重新移动）

- `_formation_state` 立即切回 "marching"
- `_path_buffer` 重新开始采样（清空旧历史，避免"跳回旧路径"）
- `_march_direction` 解冻，随将领移动实时更新
- 哑兵目标点从横阵格位切换回路径点——由于匀速移动，自然产生"收队"动画

### 防止穿插

路径点分配严格按编号固定，不做动态重排。同一格位只有一个士兵，不存在两个士兵争抢同一目标点的情况。

---

## 与 Phase 15 的关系

| 维度 | Phase 15 | Phase 16 |
|------|---------|---------|
| 排列形状 | 固定圆形（环形分布） | 纵队（行军）/ 横阵（列阵） |
| 目标点来源 | 预计算 `_ring_offset` | `get_formation_slot()` 实时计算 |
| DummySoldier 变化 | 预计算偏移，每帧靠拢 | 每帧查询接口，匀速移动 |
| 将领停止行为 | 哑兵向圆形锚点靠拢 | 哑兵展开为横阵 |
| 切换机制 | Space 键手动切换跟随/待命 | 自动检测将领速度状态 |

Phase 15 的 `follow_mode`（跟随/待命 Space 键）**保留**，在 Phase 16 仍然有效：
- `follow_mode = false`（待命）：哑兵锁定当前位置，阵型系统暂停
- `follow_mode = true`（跟随）：正常运行阵型系统

---

## 测试分层

测试放入 `tests/gameplay/`（阵型行为与玩法机制绑定）。

```
tests/gameplay/
  general_marching/    ← 将领移动时，哑兵形成纵队
  general_deployed/    ← 将领静止后，哑兵展开横阵
  formation_switch/    ← 行军→展开→行军循环，断言状态切换正确
```

---

## 关键参数（config.json）

| 参数 | 含义 | 建议默认值 |
|------|------|-----------|
| `path_buffer_size` | 路径历史点最大数量 | 60 |
| `path_sample_interval` | 每几帧采样一次路径点 | 5 |
| `march_column_width` | 纵队横向并列人数 | 6 |
| `deploy_trigger_frames` | 静止多少帧触发横阵展开 | 30 |
| `deploy_columns` | 横阵列数（默认同 march_column_width） | 8 |
| `deploy_row_spacing` | 横阵排距 | `radius × 2.2` |
| `deploy_col_spacing` | 横阵列距 | `radius × 1.1` |

---

## 验证标准

**16A 完成标准**：
- 将领移动时，哑兵以整体平移方式形成纵队（以将领当前位置为锚点实时计算，非路径拖尾）
- 纵队最前排与将领间距约等于 1 个 row_spacing
- headless 测试：`general_marching` PASS

**16B 完成标准**：
- 将领静止 30 帧后，哑兵目视可见形成横阵（面朝行军方向）
- 横阵朝向与最后行进方向一致（误差 < 15°）
- headless 测试：`general_deployed` PASS

**16C 完成标准**：
- 行军 → 展开 → 再行军循环 3 次，无穿插、无闪跳
- 重新行军时，横阵在 60 帧内完成收队并进入纵队形态
- headless 测试：`formation_switch` PASS

---

_创建: 2026-04-04_
