# 框选与选中高亮 (Selection)

> 索引：[UI INDEX](INDEX.md)
> 实现：`scripts/selection_box.gd` / `scripts/selection_manager.gd`

---

## 框选

- 左键拖拽 → 蓝色半透明矩形覆盖拖拽区域
- 松开后：矩形内所有**红方单位**进入选中状态
- 矩形内包含红方 HQ → 同时弹出生产面板

## 单击选中

- 左键单击单位附近（容差 40 世界单位）→ 选中该单位
- 左键单击 HQ 附近（容差 60 世界单位）→ 选中 HQ + 弹出生产面板
- 左键单击空白处（两者均未命中）→ 取消选中 + 关闭生产面板（`click_missed` 信号）

## 选中高亮

- 选中单位：描边变绿
- 框选时：蓝色半透明矩形实时跟随鼠标

## 移动命令

- 有选中单位时，右键单击地图 → 所有选中单位移动到目标位置
- 发出移动命令同时关闭生产面板

## 断言验收

| 断言 | 验收标准 |
|------|---------|
| `no_initial_selection` | 启动 10 帧后 `SelectionManager.selected_units` 为空 |
| `units_have_mesh` | 至少一个单位有 MeshInstance3D（视觉可见性前提） |
