# Phase 6 Checklist — AI Renderer 3D 适配（Route A）

**目标**：调试工具链适配俯视 3D 渲染，坐标语义正确，向后兼容 Phase 1 headless 回归。
**设计文档**：[design.md](design.md)
**通过条件**：所有步骤完成 + headless 回归不低于 10/11 PASS

---

- [x] **6.1** `formatter_engine.gd`：抽出 `_to_flat(pos) -> Vector2` 辅助函数，自动将 Vector3 投影到 XZ 平面；替换 `_format_worker_behavior` 中的硬编码 `Vector2(pos.x, pos.y)`
- [x] **6.2** `action_executor.gd`：`setup()` 新增 `coord_mode: String = "2d"` 参数；节点类型改为 `Node`；`_resolve_target()` 在 `"xz"` 模式下返回 `Vector3(x, 0, z)`
- [x] **6.3** `command_router.gd`：`setup()` 新增 `sel_mgr: Node = null` 参数；新增 `world_click` 命令和 `_parse_world_pos()` 辅助函数
- [x] **6.4** `game_world.gd`：注册 Camera3D 为 sensor（group: `"camera"`）；向 action_executor 传入 `coord_mode="xz"`；向 command_router 传入 `sel_mgr`
- [x] **6.5** headless 回归验证：`godot --headless --path ./src/phase1-rts-mvp`，确认不低于 10/11 PASS
