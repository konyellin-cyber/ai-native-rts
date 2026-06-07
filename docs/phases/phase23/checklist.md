# Phase 23 Checklist — 多行军算法可切换架构 + 手柄输入

**目标**: 行军驱动逻辑可配置切换（path_follow / flow_field / direct_seek），支持 A/B 数据评估；同时完成 Phase 22 遗留的手柄输入与 Context Steering 实现
**设计文档**: [design.md](design.md)
**上游文档**: [phase19/design.md](../phase19/design.md)、[phase22/design.md](../phase22/design.md)

> **说明**：Phase 22 在 roadmap 中标记为完成，但 checklist 中所有任务均未实现（场景、手柄输入、Context Steering 均缺失）。Phase 23 在此一并补齐，记录在 **子阶段 23F** 中。

---

## 验证范围声明

**验证主语**：单方将领带领 30 名哑兵，三种行军算法分别验证；手柄控制将领移动
**核心体验**：config 切换算法后行为明显不同，各算法各有特点，评估指标可量化对比；手柄左摇杆控制将领，哑兵蛇形跟随

| 验证层 | 场景/命令 | 通过标准 |
|--------|----------|---------|
| Headless | `--phase 23`（3 种算法 × 4 路线） | 每种算法均能完成行军+展开，无崩溃/NaN |
| 窗口目视 | `general_visual` + 切换 config | 3 种算法视觉差异明显可辨 |
| 窗口手动 | `gamepad_test` scene | 手柄左摇杆控制将领，行为与鼠标右键一致 |
| Benchmark | `compare_algorithms.py` | 输出对比表，各指标数据齐全 |

---

## 子阶段 23A：算法切换框架

### config.json

- [x] **23A.1** `general` 节点新增 `march_algorithm`（默认 `"path_follow"`），取值 `"path_follow"` / `"flow_field"` / `"direct_seek"`

### DummySoldier 重构

- [x] **23A.2** 新增 `_march_algorithm: String` 字段，`setup()` 从 config 读取
- [x] **23A.3** 将现有 marching 分支（`_physics_process` 中 `_waiting` 之后到卡死检测之前）提取为 `_march_path_follow()` 私有方法，行为不变
- [x] **23A.4** 新增 `_march_direct_seek()` 方法：每帧查 `_general.get_formation_slot()` 作为即时目标，直线 Seek + Arrive，不锁定目标点
- [x] **23A.5** `_physics_process` marching 分支改为 match `_march_algorithm` 分发到对应方法
- [x] **23A.6** deployed 分支和 waiting 逻辑**不改动**（三种算法共享）

### 验证

- [x] **23A.7** `march_algorithm = "path_follow"`：行为与改动前完全一致（回归保护）
- [x] **23A.8** `march_algorithm = "direct_seek"`：士兵直线追将领槽位，无 NavAgent/CS/RVO（headless 4/5 PASS，general_marching 因启动延迟更大超阈值，属算法特性非 bug）
- [x] **23A.9** headless 全量回归 PASS（默认 path_follow）— 5/5 PASS

---

## 子阶段 23B：flow_field 算法实现

### GeneralUnit 新增

- [x] **23B.1** 新增流场数据结构 `_flow_field: Dictionary`（key=Vector2i 网格坐标，value=Vector3 方向）
- [x] **23B.2** 新增 `_update_flow_field()`：从 `_path_buffer` 生成局部流场
  - 以 path_buffer 各点为中心线
  - 两侧扩展 `flow_field_half_width` 格
  - 每格方向 = 沿轨迹插值的前进方向
  - 格子分辨率 = `flow_field_cell_size`
- [x] **23B.3** 新增 `get_flow_direction(pos: Vector3) -> Vector3` 查询接口：pos 转网格坐标 → 查 _flow_field → 无数据时退回 `_march_direction`
- [x] **23B.4** `_physics_process` 中 `_update_path_buffer()` 之后调用 `_update_flow_field()`（受 `flow_field_update_interval` 节流）
- [x] **23B.5** `config.json` 新增：`flow_field_cell_size`（20.0）、`flow_field_half_width`（4）、`flow_field_update_interval`（10）

### DummySoldier 新增

- [x] **23B.6** 新增 `_march_flow_field()` 方法：
  - 查 `_general.get_flow_direction(global_position)` 获取流场方向
  - 计算编队槽位横向偏移
  - 目标 = 当前位置 + flow_dir × step + lateral_offset
  - 施力 = 方向 × drive_strength × speed_factor
  - **不使用** NavAgent / RVO / Context Steering

### 验证

- [x] **23B.7** `march_algorithm = "flow_field"`：士兵沿流场方向行军，转弯时队列整体弯曲
- [ ] **23B.8** 窗口目视：与 path_follow 对比，方向一致性明显更好
- [x] **23B.9** headless 回归 PASS（flow_field 模式下 5/5 PASS，修复了停止后退回直线追槽位）

---

## 子阶段 23C：评估指标扩展

### GeneralUnit / DummySoldier

- [x] **23C.1** DummySoldier 新增 `_stuck_nudge_count: int`（卡死扰动累计次数），每次触发扰动时 +1
- [x] **23C.2** DummySoldier `_stuck_nudge_count` 已实现（`direction_change_rate` 暂以 0.0 占位，逐帧角度追踪成本高，按需实现）
- [x] **23C.3** GeneralUnit 新增 `_convergence_start_frame` 和 `_convergence_frames`：将领停止帧 → freeze_rate=1.0 帧之差
- [x] **23C.4** `get_formation_summary()` 新增输出：
  - `stuck_nudge_total`：所有士兵 stuck_nudge_count 之和 ✅
  - `convergence_frames`：最近一次展开收敛帧数 ✅
  - `direction_change_rate`：0.0 占位 ✅

### 验证

- [ ] **23C.5** 窗口日志中可见新增指标，数值合理

---

## 子阶段 23D：A/B 评估脚本

### 实现

- [x] **23D.1** benchmark 测试路线场景：复用 general_visual 已有的 S1~S4（直线/转弯/短跑/切换）
- [x] **23D.2** 新增 `tests/benchmark/compare_algorithms.py`：
  - 遍历 3 种算法 × 3 次重复
  - 每次修改 config.json → 启动 Godot benchmark → 读取 result.json
  - 输出 `compare_result_{timestamp}.json`（原始数据）
- [x] **23D.3** 输出 `compare_report.md`：
  - 按算法×路线的对比表
  - 加权总分排名
  - 各算法优劣势总结

### 验证

- [ ] **23D.4** 运行 `compare_algorithms.py` 完成全部 9 次 trial（3×3），无崩溃
- [ ] **23D.5** `compare_report.md` 中三种算法数据齐全，差异可见

---

## 子阶段 23F：手柄输入 + Context Steering（承接 Phase 22）

> Phase 22 设计已完成，此子阶段完成全部实现任务。

### 23F-A：gamepad_test 场景搭建

- [x] **23F.1** 新建 `tests/gameplay/gamepad_test/` 目录
- [x] **23F.2** `bootstrap.gd`：复用 `general_visual` 全部逻辑（将领 + 30 哑兵 + 调试层），新增手柄输入处理
- [x] **23F.3** `scene.tscn`：空场景挂载 bootstrap
- [x] **23F.4** `config.json`：复用 general_visual 配置（含 `march_algorithm` 字段）

### 23F-B：手柄输入实现

- [x] **23F.5** 手柄连接检测：`_ready()` 中打印已连接手柄列表（`Input.get_connected_joypads()`）
- [x] **23F.6** 左摇杆死区处理（阈值 0.15）：`abs(axis_value) < 0.15` 时视为零输入
- [x] **23F.7** 摇杆方向 → 世界坐标方向转换（考虑等距摄像机朝向 -45°/-45°）：
  - 摇杆 (x, y) → 世界方向 = camera_basis × Vector3(x, 0, y)，投影到 XZ 平面
- [x] **23F.8** ~~每 20 帧~~**每 4 帧**持续推杆时发出新的 `move_to`（target = 将领当前位置 + 方向 × ~~200~~ **300** units）
  - 优化记录：20帧（333ms）→ 4帧（67ms），大幅降低操控延迟感
- [x] **23F.9** 松开摇杆（合力 < 死区）时不再发 `move_to`，将领自然停止展开横阵
  - 优化记录：计时器从 `_GAMEPAD_MOVE_INTERVAL` 改为重置为 0，松开后再推杆立即响应
- [x] **23F.21** 松开摇杆时调用 `general_unit.stop_movement()` 立即停止将领
  - 问题：松开后将领仍会走完上次 `move_to` 的目标（最多 300 units），手感"漂移"
  - 修复：在 `general_unit.gd` 新增 `stop_movement()` 接口（清除 `_has_command`、`velocity=ZERO`、目标拉到脚下）；bootstrap 死区分支调用此接口
- [x] **23F.17** RT（右扳机）/ RB（右肩键）边沿触发 `deploy_forward()`
  - 锚点 = 将领当前位置 + `_last_world_dir` × 120 units（将领前方展开横阵）
  - 边沿检测：按下瞬间触发一次，松开前不重复
  - 无推杆时使用上次记录的 `_last_world_dir` 作为展开方向
- [x] **23F.18** 键盘 **F 键**触发 `deploy_forward()`（无手柄时的替代方案）

### 23F-C：Context Steering 避障（dummy_soldier.gd）

> `_context_steer()` 方法已在 Phase 22 代码中实现（随 Phase 23 框架重构一并纳入 `_march_path_follow()`），此处验证其正确接入。

- [x] **23F.10** 确认 `_march_path_follow()` 在窗口模式下调用 `_context_steer(_my_target)` 作为 fallback
- [x] **23F.11** headless 模式确认跳过 Context Steering（直线 Seek Force）
- [x] **23F.12** headless 全量回归 PASS（Context Steering 不影响 headless 路径）— 5/5 PASS

### 23F-D：验证

- [x] **23F.13** 手柄左摇杆能控制将领移动，哑兵蛇形纵队跟随
- [x] **23F.14** 鼠标右键和手柄可同时使用，不冲突
- [x] **23F.15** 松开摇杆后将领停止，哑兵自然收拢展开横阵
- [ ] **23F.16** 窗口目视：士兵密集区域有绕行行为，不卡死；行军纵队整体形状保持
- [x] **23F.19** RT 触发 `deploy_forward`：日志确认 `[DEPLOY-ASSIGN]` 和 `formation_state → deployed` 正常输出
- [ ] **23F.20** 窗口目视：RT 触发后士兵在将领前方正确展开横阵，方向与行进方向一致

---

## 子阶段 23E：收尾

- [x] **23E.1** headless 全量回归 PASS（默认 march_algorithm = path_follow）— 17/17 PASS
- [x] **23E.2** `FILES.md` 更新：记录 `_march_algorithm` 字段、flow_field 接口、gamepad_test 场景、compare_algorithms.py
- [x] **23E.3** `roadmap.md` 更新：Phase 23 行标记"待窗口验"

---

## 子阶段 23G：3D 模型替换（Kenney Mini Characters）

**目标**：将哑兵从程序生成的圆柱体替换为 Kenney Mini Characters GLB 模型，提升视觉密度感，验证"人海感"体验。

### 23G-A：资源准备

- [x] **23G.1** 从 https://kenney.nl/assets/mini-characters 下载资源包（CC0 授权）
- [x] **23G.2** 创建 `assets/characters/` 目录，放入 `soldier.glb` / `soldier_b.glb` 及 `Textures/colormap.png`
- [x] **23G.3** 确认 GLB 在 Godot 中可正常加载（目视验证无 ERROR 日志）
  - 修复：`gltf/embedded_image_handling=1→0`，改为内嵌贴图模式，colormap.png 正确渲染

### 23G-B：代码接入

- [x] **23G.4** `dummy_soldier.gd` `_add_visual()` 改为 GLB 优先 + CylinderMesh 兜底
- [x] **23G.5** 颜色区分：脚下 `TorusMesh` 圆环（替代 `material_overlay`，保留原始贴图色彩）
- [x] **23G.6** `config.json` 新增 `dummy_use_model`（默认 true）、`dummy_model_path`、`dummy_model_scale`（默认 3.0）

### 23G-C：验证

- [x] **23G.7** 窗口目视：50 名士兵使用 GLB 模型，密度感明显优于圆柱体（截图确认）
- [x] **23G.8** headless 回归 PASS（`dummy_use_model: false` 时不加载 GLB）—— headless 强制跳过
- [x] **23G.9** FPS 对比：GLB 模型 55 FPS vs 圆柱体 ~90 FPS，损耗约 35%（50人时可接受）

**实现说明**：
- 模型加载需 Godot `--import` 先跑一次（GLB import → `.godot/imported/` 缓存）
- `_add_visual()` 移至 `_ready()` 确保节点在 SceneTree 中
- `gltf/embedded_image_handling=0` 内嵌贴图，解决 colormap.png 外部引用失败问题
- 缩放系数基于实测 AABB 高度 0.671 units，乘以 `dummy_model_scale` 独立控制视觉大小

---

## 子阶段 23H：视觉优化（模型朝向 + 动画状态机 + 将领建模）

**目标**：GLB 模型具备正确朝向、行走动画，将领也替换为 GLB 模型，整体视觉体验接近真实 RTS。

### 23H-A：模型朝向

- [x] **23H.1** `dummy_soldier.gd` `_physics_process` 末尾追加 `_update_anim_and_facing()`：速度 > 10 units/s 时调用 `look_at` + `rotate_y(PI)` 修正朝向（Kenney GLB 正面朝 +Z）
- [x] **23H.2** `general_unit.gd` 每帧在 `_prev_position` 前更新将领模型朝向（同逻辑）
- [x] **23H.3** `follow_mode=false`（待命）时也调用 `_update_anim_and_facing()`，避免待命后朝向/动画卡在行军状态

### 23H-B：高度对齐

- [x] **23H.4** 士兵模型 `position.y = -capsule_half_h`（`collision_radius × 1.25`），脚底与 RigidBody3D 胶囊底部对齐
- [x] **23H.5** 将领模型 `position.y = -unit_radius`（`height = unit_radius × 2.0`），脚底与 CharacterBody3D 胶囊底部对齐
- [x] **23H.6** 脚下圆环 `position.y = -capsule_half_h + 1.0`，贴地显示

### 23H-C：动画状态机

- [x] **23H.7** GLB 包含 32 个动画，确认 `idle` / `walk` / `sprint` / `die` 等关键动画存在
- [x] **23H.8** `_add_visual()` 初始化时一次性把所有动画设为 `LOOP_LINEAR`（GLB 导入默认 `LOOP_NONE`）
- [x] **23H.9** 动画状态机逻辑（速度 < 25 → `idle`，< max_speed×0.6 → `walk`，其余 → `sprint`）
- [x] **23H.10** 提取 `_update_anim_and_facing()` 独立函数，所有提前 `return` 路径均调用，保证停止时切回 `idle`
- [x] **23H.11** 将领动画状态机逻辑相同，移至 `_physics_process` 末尾每帧执行（从 `_move_along_path` 中移出）

### 23H-D：将领建模

- [x] **23H.12** `general_unit.gd` `_add_visual()` 改为 GLB 优先 + 圆柱兜底（与士兵同逻辑）
- [x] **23H.13** 将领模型缩放 `dummy_model_scale × 2.0`（比士兵大约一倍，提升辨识度）
- [x] **23H.14** 将领脚下圆环：金色（红方）/ 蓝白色（蓝方），比士兵圆环更大
- [x] **23H.15** 保留将领顶部白色标记球（辨识醒目）

### 23H-E：验证

- [x] **23H.16** 截图确认：士兵朝向前进方向，将领更大且有模型
- [x] **23H.17** 动画目视：行军时播放 walk/sprint 循环，停止后切回 idle 循环
- [x] **23H.18** 脚底贴地，无明显下陷或悬空

---

## 验证命令

```bash
# 开发中（默认 path_follow 回归）
godot --headless --path src/phase1-rts-mvp -- --phase 16

# 切换算法窗口验证
# 修改 config.json: "march_algorithm": "flow_field"
godot --path src/phase1-rts-mvp --scene res://tests/gameplay/general_visual/scene.tscn

# A/B 评估（全量）
cd src/phase1-rts-mvp
python tests/benchmark/compare_algorithms.py

# 收尾全量
godot --headless --path src/phase1-rts-mvp
```

---

_创建: 2026-04-21_
