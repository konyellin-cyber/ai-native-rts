# Phase 17 Checklist — 单位物理碰撞系统

**目标**: 哑兵升级为 RigidBody3D，实现真实弹性推挤，消除穿透堆叠
**设计文档**: [design.md](design.md)
**上游文档**: [gameplay-vision.md](../../design/game/gameplay-vision.md)

---

## 验证范围声明

**验证主语**：单个将领带领 6 名哑兵（RigidBody3D）
**核心体验**：将领静止时哑兵保持阵型不漂移；将领移动时哑兵跟随行军纵队；到达目的地后切换为横阵部署，士兵之间无穿透堆叠，推挤感真实

| 验证层 | 场景/命令 | 通过标准 |
|--------|----------|---------|
| Headless（静止） | `--scene idle_cluster` | 所有哑兵距将领 < 1000 units，无爆飞 |
| Headless（行军） | `--scene general_marching` | 行军期间 avg_slot_error < 80，全程无 NaN |
| Headless（部署） | `--scene general_deployed` | frame 800 时 avg_slot_error < 30（横阵收敛） |
| Headless（阵型切换） | `--scene formation_switch` | 经历"行军→横阵→行军→横阵"完整流程，各阶段均收敛 |
| Headless（静止+移动） | `--scene general_idle_move` | 静止期漂移 < 100，移动后质心 X 位移 ≥ 150 |
| 游玩体验 | `-- --play` 地图 + 单将领带 6 哑兵 | 目视无穿透，推挤感自然，阵型跟随流畅 |

> 注：当前无独立的窗口断言场景（general_visual 为目视辅助）。如后续新增窗口断言，必须保持验证主语一致：单个将领 + 哑兵物理行为。

---

## 子阶段 17A：DummySoldier 升级为 RigidBody3D

### DummySoldier 修改

- [x] **17A.1** 继承改为 `extends RigidBody3D`，初始化时设置：
  - `freeze_rotation = true`（锁定旋转）
  - `axis_lock_linear_y = true`（锁定 Y 轴位移，只在 XZ 平面运动）
  - `linear_damp`、`mass` 从 config 读取
  - `collision_layer = 4`（哑兵层），`collision_mask = 1 | 2 | 4`（碰地形、主战、互推）
- [x] **17A.2** 新增 `CollisionShape3D`（CapsuleShape3D），半径 = `radius × collision_radius_factor`
- [x] **17A.3** `_physics_process` 改为力驱动：
  - 距槽位 > `arrive_threshold` → `apply_central_force(方向 × drive_strength)`
  - 距槽位 ≤ `arrive_threshold` → 不施力（自然减速，防抖）
- [x] **17A.4** 移除 `_move_toward()` 方法（或保留注释说明已废弃）
- [x] **17A.5** `follow_mode = false` 时：`linear_velocity = Vector3.ZERO` 锁定速度，不施力
- [x] **17A.6** 初始放置位置改为：`global_position = get_formation_slot(...)` + 立即执行（RigidBody3D 需在 `_ready` 后设置）

### config.json 修改

- [x] **17A.7** `general` 节点下新增（drive_strength=1600 对应稳态速度 ≈ 200 units/s，与将领速度匹配）：
  ```json
  "dummy_mass": 1.0,
  "dummy_linear_damp": 8.0,
  "dummy_drive_strength": 1600.0,
  "dummy_arrive_threshold": 15.0,
  "dummy_collision_radius_factor": 0.55
  ```

### 视觉验证

- [x] **17A.8** 窗口模式目视验证：将领静止，30 名哑兵自然分散，无穿透堆叠
- [x] **17A.9** 窗口模式目视验证：行军纵队中士兵保持间距，不挤成一团，推挤感真实，无明显抖动

### 测试

- [x] **17A.10** headless 全回归：`general_marching`、`general_deployed`、`formation_switch` 全部 PASS（接口不变）
- [x] **17A.11** headless 全回归：全部 15 个场景 PASS

---

## 子阶段 17B：碰撞层统一（可选）

- [x] **17B.1** 确认并对齐实际运行的碰撞层编号（与 design.md 理想方案有差异，以实际为准）：
  - 主战单位（Fighter/Archer/Worker/General）：`collision_layer = 1`，`collision_mask = 2 | 4`
    - layer 2 = 墙/障碍物，layer 4 = 哑兵（主战推哑兵，实现单向碰撞）
  - DummySoldier：`collision_layer = 4`，`collision_mask = 1 | 2 | 4`（哑兵互推 + 被主战推）
  - HQ / 地面：`collision_layer = 1`，`collision_mask = 0`（不主动感知碰撞）
- [x] **17B.2** headless 全量回归 17/17 PASS

---

## 收尾

- [x] **17C.1** `FILES.md` 更新：记录 DummySoldier 节点类型变更
- [x] **17C.2** `roadmap.md` 更新：Phase 17 行新增并标记状态

---

_创建: 2026-04-05_

---

## 验证命令

```bash
# 开发中（只跑 phase 16/17 相关场景，~50s）
godot --headless --path src/phase1-rts-mvp -- --phase 16

# 单场景调试
godot --headless --path src/phase1-rts-mvp -- --scene general_marching

# 收尾全量（提交前）
godot --headless --path src/phase1-rts-mvp
```
