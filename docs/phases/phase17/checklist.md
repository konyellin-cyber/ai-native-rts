# Phase 17 Checklist — 单位物理碰撞系统

**目标**: 哑兵升级为 RigidBody3D，实现真实弹性推挤，消除穿透堆叠
**设计文档**: [design.md](design.md)
**上游文档**: [gameplay-vision.md](../../design/game/gameplay-vision.md)

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

- [ ] **17A.8** 窗口模式目视验证：将领静止，30 名哑兵自然分散，无穿透堆叠
- [ ] **17A.9** 窗口模式目视验证：行军纵队中士兵保持间距，不挤成一团，推挤感真实，无明显抖动

### 测试

- [x] **17A.10** headless 全回归：`general_marching`、`general_deployed`、`formation_switch` 全部 PASS（接口不变）
- [x] **17A.11** headless 全回归：全部 15 个场景 PASS

---

## 子阶段 17B：碰撞层统一（可选）

- [ ] **17B.1** 确认 Fighter / Archer / Worker / General 的 `collision_layer` / `collision_mask` 与 Layer 架构对齐：
  - 主战单位：`collision_layer = 2`，`collision_mask = 1 | 2 | 4`
  - HQ / 建筑：`collision_layer = 16`，`collision_mask = 0`
- [ ] **17B.2** headless 全回归：全部 PASS

---

## 收尾

- [ ] **17C.1** `FILES.md` 更新：记录 DummySoldier 节点类型变更
- [ ] **17C.2** `roadmap.md` 更新：Phase 17 行新增并标记状态

---

_创建: 2026-04-05_
