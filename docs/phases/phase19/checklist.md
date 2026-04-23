# Phase 19 Checklist — 路径跟随行军系统

**目标**: 行军纵队从整体平移改为路径跟随，产生蛇形队列感
**设计文档**: [design.md](design.md)
**上游文档**: [gameplay-vision.md](../../design/game/gameplay-vision.md)

---

## 验证范围声明

**验证主语**：单方将领带领哑兵（无战斗单位、无建造、无对手）
**核心体验**：将领移动时，哑兵沿路径历史点形成蛇形纵队跟随，有启动延迟的多米诺效果；将领停止且哑兵全员到位后自然展开横阵

| 验证层 | 场景/命令 | 通过标准 |
|--------|----------|---------|
| Headless（行军） | `--scene general_marching` | 行军期间质心跟随将领，avg_slot_error < 80 |
| Headless（部署） | `--scene general_deployed` | frame 800 时 avg_slot_error < 30（横阵收敛） |
| Headless（阵型切换） | `--scene formation_switch` | 完整经历"行军→横阵→行军→横阵"各阶段均收敛 |
| Headless（静止+移动） | `--scene general_idle_move` | 静止期漂移 < 100，移动后质心 X 位移 ≥ 150 |
| 窗口目视 | `general_visual`（单将领 + 哑兵） | 目视蛇形队列感，转弯时队列跟随曲线，无横向闪跳 |
| 游玩体验 | `-- --play`（主场景只观察红方将领） | 行军纵队流畅，多米诺启动感，停止后横阵自然收拢 |

**体验质量量化标准（19C 新增感知指标）**：

| 指标 | 阶段 | 通过标准 | 告警条件 |
|------|------|---------|---------|
| `pos_std_dev` | 行军中 | 50 ~ 300 | < 30（挤团）或 > 400（散兵）|
| `lateral_spread` | 行军中 | < 60（列宽×1.5） | > 120（队形崩溃）|
| `velocity_coherence` | 行军中 | > 0.5 | < 0.2（各奔东西）|
| `overshoot_count` | 展开过渡 | 0 | > 3（过冲 bug）|
| `freeze_rate` | 横阵稳定 | = 1.0 | < 0.9（有士兵未稳定）|

> 本 Phase 不验证对战逻辑、建造、经济；窗口场景 `general_visual` 仅有单方将领和哑兵，与验证主语完全一致。

---

## 子阶段 19A：_get_march_slot 重写为路径跟随

### GeneralUnit 修改

- [x] **19A.1** `config.json` 新增 `march_row_path_step`（默认 4）、`march_lead_offset`（默认 3）；`march_column_width` 改为 2
- [x] **19A.2** `_get_march_slot` 重写：
  - 计算 `path_idx = march_lead_offset + row × march_row_path_step`
  - `path_buffer` 长度 > `path_idx` → `anchor = path_buffer[path_idx]`
  - `path_buffer` 不足 → 返回 `current_pos`（士兵原地等待，多米诺启动）
  - 目标点 = `anchor + lateral_dir × deploy_col_spacing × col_offset`
  - `lateral_dir` 继续使用 `_march_direction` 旋转 90°
- [x] **19A.2b** 启动延迟：`path_buffer` 中无对应路径点时，返回士兵**当前位置**（原地等待），形成多米诺效果
- [x] **19A.3** 确认 `_update_path_buffer` 逻辑不变（`path_buffer[0]` 为最新点，`push_front` 方向正确）

### DummySoldier 修改（19A.2c — 稳定目标点）

- [x] **19A.2c** DummySoldier 内部维护 `_my_target: Vector3` 和 `_waiting: bool`：
  - `_waiting = true`（初始）：每帧向 general 查询，path_buffer 返回 `global_position` 时保持等待
  - path_buffer 有合法点时：锁定 `_my_target`，`_waiting = false`，开始移动
  - 到达 `_my_target`（dist < arrive_threshold）后：重新向 general 查询下一个目标点并锁定
  - 将领切换为 DEPLOYED 或 MARCHING 时：重置为 `_waiting = true`
- [x] **19A.2d** Arrival Steering：驱动力随距离线性缩放（`speed_factor = clamp(dist / slow_radius, 0, 1)`），远时全力归队，近时平滑减速；新增 `dummy_slow_radius`（默认 120）

### GeneralUnit 修改（19A.3 — 全员到位才展开）

- [x] **19A.3** MARCHING → DEPLOYED 切换条件升级：
  - 计时器从"全员到位"（`avg_slot_error < deploy_ready_threshold`）那一刻开始计，而非从将领停止开始
  - 将领停止但士兵还在赶路时，`_deploy_timer` 重置为 0，不展开
  - 全员到位后持续 `deploy_trigger_frames` 帧才切换 DEPLOYED
  - 新增 config 参数：`deploy_ready_threshold`（默认 45）

### DummySoldier 修改（19A.4 — NavMesh + RVO 寻路）

- [x] **19A.4** 每个 DummySoldier 添加 `NavigationAgent3D`：
  - `avoidance_enabled = true`，`radius = _collision_radius`
  - `neighbor_distance`、`max_neighbors` 从 config 读取
  - `_physics_process` 改为：`agent.target_position = _my_target` → 取 `get_next_path_position()` 作为施力方向
  - RVO 回调 `velocity_computed` 中用修正速度方向替换原始方向
  - headless 模式跳过 NavAgent（避免无 NavMesh 报错），保留原 Seek Force 逻辑
- [x] **19A.5** `config.json` 新增：`dummy_nav_path_distance`（15）、`dummy_nav_target_distance`（15）、`dummy_nav_neighbor_distance`（60）、`dummy_nav_max_neighbors`（10）
- [ ] **19A.5** 窗口模式目视验证：将领转弯时，队列跟随曲线，无横向闪跳（待游玩验证）
- [ ] **19A.6** 窗口模式目视验证：将领停止后，士兵沿各自轨迹自然走到位，收拢后展开横阵（待游玩验证）

### 测试

- [x] **19A.7** `general_marching` headless 回归：哑兵质心跟随将领方向移动断言 PASS
- [x] **19A.8** headless 全回归：`general_marching`、`general_deployed`、`formation_switch` 全部 PASS
- [ ] **19A.9** headless 全量回归：全部场景 PASS（收尾时执行）

---

## 子阶段 19B：阵型感知 + 可视化调试

### GeneralUnit 修改

- [x] **19B.1** 新增 `get_formation_summary() -> Dictionary`，暴露以下字段供 Sensor 采集：
  - `formation_state`、`path_buffer_size`、`avg_slot_error`、`max_slot_error`、`waiting_count`

### general_visual bootstrap 修改

- [x] **19B.2** 初始化 AIRenderer（mode=ai_debug，sample_rate=30），注册 GeneralUnit 的 `get_formation_summary` 方法，每 30 帧输出一次阵型整齐度数据到 `window_debug.log`
- [x] **19B.3** 新增可视化调试层，每帧绘制：
  - 绿线：士兵当前位置 → 理想槽位
  - 红色球：`_waiting=true` 的士兵（原地等待）
  - 黄点：path_buffer 各历史点位置（最多 20 个）

### 视觉验证

- [x] **19B.4** 窗口模式：调试层可见，绿线长度直观反映队形误差；等待中的士兵有红色标记
- [ ] **19B.5** `window_debug.log` 中可见 `avg_slot_error` / `waiting_count` 数据（Formatter extra 字段输出待确认）

---

## 子阶段 19C：体验质量感知指标

### GeneralUnit 修改

- [x] **19C.1** `get_formation_summary()` 新增以下指标：
  - `pos_std_dev`：所有士兵 XZ 位置相对质心的标准差
  - `lateral_spread`：垂直于 `_march_direction` 方向的横向离散度
  - `velocity_coherence`：速度方向余弦相似度均值（通过 `get("linear_velocity")` 读取各士兵速度）
  - `overshoot_count`：上帧已满足 `dist < arrive_threshold` 但本帧 dist 反而增大的士兵数（需上帧距离缓存）
  - `freeze_rate`：已 freeze 士兵占总数的比例

### general_visual bootstrap 修改

- [x] **19C.2** 每 10 帧日志新增新指标输出：
  ```
  [DBG f=N] state=X std=Y lat=Z coh=W overshoot=V freeze=U%
  ```
- [x] **19C.3** 告警阈值触发时立即输出 `[WARN]` + 事件截图：
  - `pos_std_dev < 30`（挤团）
  - `pos_std_dev > 400`（散乱）
  - `lateral_spread > 120`（队形崩溃）
  - `velocity_coherence < 0.2`（各奔东西）
  - `overshoot_count > 3`（过冲 bug）
  - `freeze_rate < 0.9` 且已进入 deployed 60 帧以上（未完全稳定）

### 验证

- [ ] **19C.4** 打开窗口场景，右键移动，观察日志中新指标是否合理
- [ ] **19C.5** 通过日志确认 `pos_std_dev` 在行军中稳定、告警阈值能捕捉挤团现象

---

## 子阶段 19G：多米诺启动 — 移除虚拟锚点

### GeneralUnit 修改

- [ ] **19G.1** `_get_march_slot()` 中移除 `elif _has_command:` 虚拟锚点推算分支
- [ ] **19G.2** path_buffer 不足时统一返回 `current_pos`（原地等待）

### 验证

- [ ] **19G.3** headless 全量回归 5/5 PASS
- [ ] **19G.4** 窗口目视：deployed 后再移动，士兵从横阵原地等待，前排先动，后排依次跟上，呈蛇形多米诺效果

---

## 子阶段 19F：纵队轨迹重置

### GeneralUnit 修改

- [ ] **19F.1** `move_to()` 中，当 `_formation_state == "deployed"` 时清空 `_path_buffer` 并重置 `_path_sample_timer`
- [ ] **19F.2** 确认纯 marching 状态下反复发命令时不清空（只在 deployed→marching 切换时清空）

### 验证

- [ ] **19F.3** headless 全量回归 5/5 PASS
- [ ] **19F.4** 窗口目视：展开横阵后再移动，后排士兵沿新路径行进，不往旧方向跑

---

## 子阶段 19E：槽位最近邻分配

### GeneralUnit 修改

- [ ] **19E.1** 新增 `_slot_assignment: Dictionary` 变量
- [ ] **19E.2** 新增 `_rebuild_slot_assignment(state: String)` 函数：
  - 计算当前 state 下所有槽位坐标
  - 贪心最近邻匹配士兵位置与槽位
  - 写入 `_slot_assignment`
- [ ] **19E.3** `get_formation_slot()` 改为先查 `_slot_assignment`
- [ ] **19E.4** `_detect_formation_state()` 切换到 deployed 时调用 `_rebuild_slot_assignment`
- [ ] **19E.5** `move_to()` 调用时清空/重建 marching 槽位分配

### 验证

- [ ] **19E.6** headless 全量回归 5/5 PASS
- [ ] **19E.7** 窗口目视：阵型切换时无明显路径交叉，士兵走向最近槽位

---

## 子阶段 19D：参数自动优化（Optuna）

### 实现

- [ ] **19D.1** `tests/benchmark/optimize.py`：Optuna 优化主程序
  - 参数空间定义（9 个参数，见 design.md）
  - 每次 trial：写 config.json → 启动 Godot --benchmark → 读 result.json → 返回 score
  - SQLite 持久化（支持中断后 resume）
  - 每次 trial 后打印进度，best score 时保存 best_params.json
- [ ] **19D.2** `--apply-best` 模式：将 best_params.json 写回 config.json general 节点
- [ ] **19D.3** 运行 50 trials，记录最优参数

### 验证

- [ ] **19D.4** 应用最优参数后，overall_score ≥ 90
- [ ] **19D.5** headless 全量回归 5/5 PASS（最优参数不引入物理爆炸）
- [ ] **19D.6** 窗口目视验证：最优参数下手感自然，无明显抖动/卡顿

---

## 收尾（19H）

- [ ] **19H.1** `FILES.md` 更新：记录 `_get_march_slot`、`dummy_soldier`、`general_visual/bootstrap` 改动
- [ ] **19H.2** `roadmap.md` 更新：Phase 19 行新增并标记状态

---

_创建: 2026-04-11_

---

## 验证命令

```bash
# 开发中（只跑 phase 16/19 相关场景，~50s）
godot --headless --path src/phase1-rts-mvp -- --phase 16

# 窗口目视验证（单将领 + 哑兵，右键移动，Space 切待命）
godot --path src/phase1-rts-mvp --scene res://tests/gameplay/general_visual/scene.tscn

# 收尾全量（提交前）
godot --headless --path src/phase1-rts-mvp
```
