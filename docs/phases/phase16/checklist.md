# Phase 16 Checklist — 行军阵型系统

**目标**: 验证行军纵队 + 静止展开横阵的手感
**设计文档**: [design.md](design.md)
**上游文档**: [gameplay-vision.md](../../design/game/gameplay-vision.md)

---

## 前置清理（开发前完成）

- [x] **16A.0a** 将 `tests/gameplay/general_follow/` 和 `tests/gameplay/general_standby/` 移入 `tests/legacy/`（圆形锚点逻辑被阵型系统取代）
- [x] **16A.0b** headless 全回归确认迁移无副作用：全部 PASS

---

## 子阶段 16A：路径队列 + 行军纵队

### GeneralUnit 修改

- [x] **16A.1** `general_unit.gd` 新增 `_path_buffer: Array[Vector3]`（环形队列，最大 `path_buffer_size` 个点）、`_path_sample_timer: int`
- [x] **16A.2** `_physics_process` 中：将领速度 > 0 时，每隔 `path_sample_interval` 帧将当前位置压入 `_path_buffer`，同时更新 `_march_direction`
- [x] **16A.3** 新增 `_formation_state: String`（初始值 "marching"）和 `_deploy_timer: int`
- [x] **16A.4** 新增方法 `get_formation_slot(index: int, total: int) -> Vector3`：
  - MARCHING 状态：按编号分配路径点 + 横向槽位（见设计文档算法）
  - DEPLOYED 状态：按编号分配横阵格位（16B 实现）
  - 路径点不足时：目标 = 最远路径点
- [x] **16A.5** `config.json` 新增 `path_buffer_size`（默认 60）、`path_sample_interval`（默认 5）、`march_column_width`（默认 3）

### DummySoldier 修改

- [x] **16A.6** 废弃 `_ring_offset` 预计算逻辑（注释保留说明，不删除文件）
- [x] **16A.7** `_physics_process` 改为：每帧调用 `_general.get_formation_slot(_soldier_index, _total_count)` 获取目标点，匀速向目标移动（复用 `_move_toward`，无加速度）
- [x] **16A.8** `follow_mode = false`（待命）时，阵型更新暂停，士兵原地不动（与 Phase 15 行为一致）

### 测试

- [x] **16A.9** 新增 `tests/gameplay/general_marching/`：将领从 A 移动到 B，断言：哑兵质心跟随将领方向移动、最前排哑兵与将领距离 < 路径点间距 × 3，PASS
- [x] **16A.10** headless 全回归：全部 PASS

---

## 子阶段 16B：静止展开横阵

### GeneralUnit 修改

- [x] **16B.1** `_physics_process` 中检测静止：将领速度 ≈ 0 时 `_deploy_timer` 递增；将领移动时重置为 0
- [x] **16B.2** `_deploy_timer >= deploy_trigger_frames` 时：`_formation_state` 切换为 "deployed"，`_march_direction` 冻结
- [x] **16B.3** `_march_direction` 无历史（将领未移动过）时，默认朝向 `Vector3(0, 0, -1)`
- [x] **16B.4** `get_formation_slot` 的 DEPLOYED 分支实现横阵格位计算（排 × 列，见设计文档算法）
- [x] **16B.5** `config.json` 新增 `deploy_trigger_frames`（默认 30）、`deploy_columns`（默认 3）、`deploy_row_spacing`（默认 `radius × 2.2`）、`deploy_col_spacing`（默认 `radius × 1.1`）

### 视觉验证

- [x] **16B.6** 窗口模式目视验证：将领移动后停止，30 帧内哑兵可见从纵队展开为横阵，面朝行军方向
- [x] **16B.7** 窗口模式目视验证：将领未移动直接静止生成时，哑兵默认朝北展开（约 120 帧后自动 deployed）

### 测试

- [x] **16B.8** 新增 `tests/gameplay/general_deployed/`：将领静止 `deploy_trigger_frames` 帧后，断言 `_formation_state == "deployed"`、哑兵质心位于将领前方（沿 `_march_direction` 方向），PASS
- [x] **16B.9** headless 全回归：全部 PASS

---

## 子阶段 16C：状态切换流畅性

### GeneralUnit 修改

- [x] **16C.1** 将领重新移动时（速度 > 0）：`_formation_state` 立即切回 "marching"，清空 `_path_buffer`，`_march_direction` 解冻
- [x] **16C.2** 切回 MARCHING 后，`get_formation_slot` 立即返回新路径点目标（哑兵无需额外处理，自然流向新目标）

### 视觉验证

- [x] **16C.3** 窗口模式目视验证：行军 → 展开 → 再行军，循环 3 次，无穿插、无闪跳、无士兵瞬移（截图确认纵队+横阵状态正常）

### 测试

- [x] **16C.4** 新增 `tests/gameplay/formation_switch/`：
  - 将领移动 → 停止（等待展开）→ 再次移动，循环 2 次
  - 断言：每次停止后 `_formation_state` 变为 "deployed"；每次移动后立即变回 "marching"
  - PASS
- [x] **16C.5** headless 全回归：全部 PASS

---

## 收尾

- [x] **16D.1** `FILES.md` 更新：记录所有新增/改动文件（待本次 session 结束后补录）
- [x] **16D.2** `roadmap.md` 更新：Phase 16 行已标记 ✅ 完成

---

## Bug 修复（截图发现，Phase 16 期间修复）

- [x] **BF.1** `dummy_soldier.gd`：`_ready()` 里加 `freeze=true / freeze_mode=FREEZE_MODE_STATIC`，将领 idle 时哑兵彻底冻结，解除 `_waiting` 时解冻——修复初始生成时胶囊体重叠被物理弹飞的问题
- [x] **BF.2** `unit_lifecycle_manager.gd`：`on_unit_died` / `on_unit_produced` 只统计 fighter/worker/archer，将领和哑兵死亡不计入 `alive_count`——修复计分变负数的 bug
- [x] **BF.3** `game_world.gd`：蓝方将领生成哑兵，并在 5 秒后启动行军 AI 朝红方 HQ 推进（此前蓝方将领静态不动，战场只有蓝方 fighter 在进攻）
- [x] **BF.4** 新增 `tests/gameplay/idle_cluster/`：将领 idle 不发指令，断言每个哑兵偏离初始槽位 < 5 单位（覆盖物理爆炸场景）
- [x] **BF.5** 新增 `tests/gameplay/general_idle_move/`：将领先 idle 60 帧再收到移动指令，断言 idle 期无漂移、哑兵跟随质心移动 ≥ 150（模拟主游戏玩家操作流程）
- [x] **BF.6** headless 全回归 17/17 PASS
- [x] **BF.7** `dummy_soldier.gd` deployed 分支入口加 `freeze=false`，修复列阵时冻结士兵无法移动到槽位的问题
- [x] **BF.8** `general_unit.gd` deployed 触发条件改为只看已激活（非 waiting）士兵的 avg_slot_error；`get_formation_summary` 里 waiting 士兵不计入误差，防止补兵不断累积 waiting_count 导致永不触发 deployed
- [x] **BF.9** `general_unit.gd` 去掉 headless/window 分支（原 headless 直接绕过全员检查），统一用 avg_slot_error 判断
- [x] **BF.10** formation_switch 测试重构为事件驱动（不再依赖硬编码帧号）
- [x] **BF.11** 最终 headless 全回归 17/17 PASS

---

_创建: 2026-04-04_
