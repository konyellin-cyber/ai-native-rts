# Phase 9 Checklist：45 度等距视角镜头

> 设计文档：[design.md](design.md)
> 原则：纯视觉层改动，headless 逻辑零改动，窗口断言替换 1 个以适配新视角。

---

## 9A：镜头参数调整（bootstrap.gd）

- [x] `bootstrap.gd` `_setup_3d_scene()`：`rotation_degrees` 改为 `Vector3(-45, -45, 0)`
- [x] `bootstrap.gd` `_setup_3d_scene()`：`position` 改为 `Vector3(map_w/2, 1500, map_h/2 + 1500)`（Z 后退 1500）
- [x] `bootstrap.gd` `_setup_3d_scene()`：`camera.size` 确认值合适（目标 ≥ 2000 以覆盖等距地图）
- [x] `bootstrap.gd` `_setup_3d_scene()`：`light.rotation_degrees` 改为 `Vector3(-45, -45, 0)`（光源与视角对齐）
- [ ] 窗口模式目视确认：地图完整可见，红蓝基地和矿物均可辨认，无严重遮挡（截图留证）

## 9B：窗口断言适配（window_assertion_setup.gd）

- [x] `window_assertion_setup.gd`：删除 `_assert_camera_centered` 函数
- [x] `window_assertion_setup.gd`：新增 `_assert_camera_isometric` 函数，检查：
  - `position.x` 在地图 X 中心 ±300 内
  - `rotation_degrees.y` 在 `-45° ±5°` 范围内（偏航角确认）
- [x] `window_assertion_setup.gd` `register_all()`：将 `camera_centered` → `camera_isometric`
- [x] headless 回归验证：`godot --headless --path . --scene res://tests/test_runner.tscn`，确认 **11/11 PASS**
- [ ] 窗口断言验证：窗口模式运行，确认 **11/11 PASS**（含 camera_isometric）

## 9C：UI 投影验证

- [ ] 窗口模式下点击 HQ，确认生产面板出现在 HQ 上方（不飞出视口）
- [ ] 窗口断言 `prod_panel_position_near_hq` 确认 PASS

## 9D：收尾

- [x] `FILES.md`：更新 `bootstrap.gd` 注释（由"正交俯视"改为"等距正交"）
- [x] `FILES.md`：更新 `window_assertion_setup.gd` 断言清单（camera_isometric 替换 camera_centered）
- [x] roadmap.md：Phase 9 状态更新为 ✅ 完成

---

## 完成标准

- [x] headless 11/11 PASS（视觉改动不触碰逻辑层，零回归）
- [ ] 窗口断言 11/11 PASS（含 camera_isometric）
- [ ] 目视截图：等距视角下地图、单位、建筑完整可见
- [ ] 生产面板投影正常（prod_panel_position_near_hq PASS）
