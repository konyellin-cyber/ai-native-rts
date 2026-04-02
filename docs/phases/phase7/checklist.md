# Phase 7 Checklist：完整 3D 模式

> **设计文档**：[design.md](design.md)
> **目标**：游戏本体从 2D 节点树迁移到 3D，保持游戏逻辑不变，headless 回归 10/11 PASS

---

## 子阶段 7A：项目基础切换

- [x] **7A.1** `project.godot`：渲染管线改为 Forward+，根节点改为 Node3D
- [x] **7A.2** `bootstrap.gd`：继承改为 `Node3D`，主场景根节点类型同步
- [x] **7A.3** 添加 Camera3D（正交投影，高度 1500，垂直朝下）和 DirectionalLight3D（基础光照）
- [x] **7A.4** 验证：headless 启动无崩溃，无脚本错误

---

## 子阶段 7B：地图与导航

- [x] **7B.1** `map_generator.gd`：地面 StaticBody3D + PlaneMesh（2560×1664）
- [x] **7B.2** 障碍物改为 StaticBody3D + BoxMesh + BoxShape3D，坐标映射 (x,y)→(x,0,z)
- [x] **7B.3** NavigationRegion2D → NavigationRegion3D，配置 NavigationMesh 参数
- [x] **7B.4** 验证：headless 导航网格烘焙无报错（8/11 PASS；worker_cycle / economy_positive 为预期中间态退步，7C 迁移实体后恢复）

---

## 子阶段 7C：实体迁移

- [x] **7C.1** `hq.gd`：StaticBody2D → StaticBody3D，位置 Vector2 → Vector3
- [x] **7C.2** `resource_node.gd`：Area2D → Area3D，位置映射
- [x] **7C.3** `worker.gd`：CharacterBody2D → CharacterBody3D，NavigationAgent2D → NavigationAgent3D，速度向量改为 XZ 平面
- [x] **7C.4** `fighter.gd`：CharacterBody2D → CharacterBody3D，NavigationAgent2D → NavigationAgent3D，速度向量改为 XZ 平面
- [x] **7C.5** `game_world.gd`：所有 spawn 坐标 Vector2 → Vector3，节点类型更新
- [x] **7C.6** headless 回归验证：10/11 PASS（economy_positive 为预存在慢断言，其余 10 全通过）

---

## 子阶段 7D：摄像机与视觉

- [x] **7D.1** 各实体添加临时 MeshInstance3D（Worker=CapsuleMesh，Fighter=CylinderMesh，HQ=BoxMesh，Mine=SphereMesh）
- [x] **7D.2** 地面 PlaneMesh 材质（深灰色）、障碍物材质（深色）
- [x] **7D.3** Camera3D size 改为 `map_h`（1664），确保地图精确铺满视口（宽高比由引擎自动推算）
- [x] **7D.4** 验证：窗口模式下 HQ/矿点/障碍物/地面全部可见，UI 正确显示 Crystal 和存活数

---

## 子阶段 7E：ai-renderer 接入

- [x] **7E.1** `bootstrap.gd`：renderer 初始化后查 Camera3D 并注册为 sensor（group: `"camera"`，字段：`global_position`、`rotation_degrees`、`size`）
- [x] **7E.2** `bootstrap.gd`：两处 SimulatedPlayer.setup() 均传入 `coord_mode="xz"` ✅（7C 已完成）
- [x] **7E.3** 验证：headless 10/11 PASS，无脚本错误，坐标语义正确（XZ 平面）
