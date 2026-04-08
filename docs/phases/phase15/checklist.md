# Phase 15 Checklist — 将领单位 + 兵团跟随

**目标**: 验证将领手感 + 兵团密集人墙跟随行为
**设计文档**: [design.md](design.md)
**上游文档**: [gameplay-vision.md](../../design/game/gameplay-vision.md)

---

## 子阶段 15A：将领单位

### 测试目录重组（策略 B，开发前完成）

- [x] **15A.0a** 新建 `tests/core/`、`tests/legacy/`、`tests/gameplay/` 目录
- [x] **15A.0b** 现有测试按规则迁移：战斗/死亡/弹道/框选 → `core/`；HQ 生产面板 → `legacy/`
- [x] **15A.0c** 更新场景登记表（`tests/test_registry.json` 或等效文件），反映新目录结构
- [x] **15A.0d** headless 全回归确认迁移无副作用：全部 PASS

### 将领节点

- [x] **15A.1** 新建 `scripts/general_unit.gd`：继承 `base_unit.gd`，`unit_type = "general"`，`team_name` 由外部传入
- [x] **15A.2** 将领移动速度常量（略快于 Fighter），在 `config.json` 中配置
- [x] **15A.3** 将领视觉区分：尺寸比士兵大 1.5 倍，颜色/标识可识别（具体视觉待 Phase 后期打磨）
- [x] **15A.4** 阵亡逻辑：HP 归零 → 发出信号 `general_died(team_name)` → 节点移除；复用 `base_unit._die()`

### 玩家控制

- [x] **15A.5** PC 模式：鼠标右键点击地面 → 将领移动到目标点（复用现有 `simulate_right_click` 路径或新增 `_unhandled_input` 监听）
- [x] **15A.6** 将领可被框选/点选（SelectionManager 正常识别 `unit_type = "general"`）

### 场景接入

- [x] **15A.7** 主场景（`main.tscn`）中，red 阵营生成一个玩家将领；blue 阵营生成一个 AI 将领（暂时静止，仅作视觉占位）
- [x] **15A.8** `UnitLifecycleManager` 或 `bootstrap.gd` 负责将领的生成，与普通士兵生成逻辑分离

### 测试

- [x] **15A.9** 新增 `tests/gameplay/general_movement/`：将领从 A 点移动到 B 点，断言位置变化 PASS
- [x] **15A.10** 新增 `tests/gameplay/general_death/`：将领 HP 归零，断言 `general_died` 信号触发、节点移除 PASS
- [x] **15A.11** headless 全回归：全部 PASS

---

## 子阶段 15B：兵团跟随

### 哑兵（Dummy Soldier）

- [x] **15B.1** 新建 `scripts/dummy_soldier.gd`：无 AI、无战斗，只有位置和锚点跟随逻辑
- [x] **15B.2** 主场景 red 将领出生时，周围生成 N 个哑兵（N 从 `config.json` 读，默认 30）

### 锚点聚集

- [x] **15B.3** `general_unit.gd` 暴露锚点接口：`get_anchor_position() -> Vector3`，默认为将领自身位置
- [x] **15B.4** `dummy_soldier.gd` 实现目标位置计算：以将领为圆心，按编号均匀分布在半径 R 内的圆形区域，间距 = 碰撞半径 × 1.1，加小量随机扰动（扰动值在 `config.json` 中配置）
- [x] **15B.5** `dummy_soldier.gd` 实现向目标位置移动：每帧平滑靠拢（速度与将领一致，避免掉队）

### 跟随 / 待命切换

- [x] **15B.6** `general_unit.gd` 新增状态：`follow_mode: bool`，默认 `true`（跟随）
- [x] **15B.7** PC 模式切换键：按 `Space`（可配置）切换 `follow_mode`；UI 有简单文字提示当前状态
- [x] **15B.8** `follow_mode = false`（待命）时，哑兵停在当前位置，不再更新目标位置
- [x] **15B.9** 待命时将领离开超过阈值距离（`config.json` 配置），哑兵目标间距逐渐扩大（松散效果）

### 视觉验证

- [x] **15B.10** 窗口模式目视验证：将领带队移动时，士兵形成密集人墙（无明显均匀间距感）
- [x] **15B.11** 窗口模式目视验证：切换待命后将领独走，士兵留在原地；将领回来后士兵重新靠拢
- [x] **15B.15** 新增 `tests/gameplay/general_visual/`：独立干净的目视演示场景，仅含将领+哑兵，支持鼠标右键移动 + Space 切换跟随/待命

### 测试

- [x] **15B.12** 新增 `tests/gameplay/general_follow/`：将领移动后，断言哑兵整体质心跟随将领方向移动 PASS
- [x] **15B.13** 新增 `tests/gameplay/general_standby/`：切换待命后将领移动，断言哑兵位置保持不变 PASS
- [x] **15B.14** headless 全回归：全部 PASS

---

## 子阶段 15C：自动补兵

- [x] **15C.1** `config.json` 新增 `replenish_interval`（补兵间隔帧数）、`replenish_count`（每次补充数量）
- [x] **15C.2** 双方将领每隔 `replenish_interval` 帧，向所属将领附近添加新哑兵（敌方将领补兵速度系数随时间增大，模拟集结期）
- [x] **15C.3** 新增 `tests/gameplay/replenish/`：断言 N 帧后兵力数量正确增长 PASS
- [x] **15C.4** headless 全回归：全部 PASS

---

## 收尾

- [x] **15D.1** `FILES.md` 更新：记录所有新增/改动文件
- [x] **15D.2** `roadmap.md` 更新：Phase 15 行标记 ✅ 完成

---

_创建: 2026-04-03_
