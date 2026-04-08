# Phase Roadmap

**项目**: [AI Native RTS](../../overview.md)

> 高层 Phase 规划。每个 Phase 的详细 checklist 在对应子目录中。

---

## 进度总览

| Phase | 名称 | 目标 | 状态 | Checklist |
|-------|------|------|------|-----------|
| 0 | 碰撞球 | 打通 AI debug 数据通路 | ✅ 完成 | [checklist](phase0/checklist.md) |
| 0.5 | RTS 技术验证 | 验证 Godot 能否支撑 RTS 核心机制 | ✅ 完成 | [checklist](phase05/checklist.md) |
| 1 | 最小 MVP | 完整游戏循环 demo | ✅ 完成 | [checklist](phase1/checklist.md) |
| 2 | 质量打磨 | 修复 bug，增强行为检测 | ✅ 完成 | [checklist](phase2/checklist.md) |
| 3 | 体验完善 | AI 工具链 + UI/UX 改进 | ✅ 完成 | [checklist](phase3/checklist.md) |
| 4 | 可扩展架构 | 科技树、多兵种、种族、地形 | ⏳ 未开始 | [checklist](phase4/checklist.md) |
| 5 | 可维护性重构 | 清偿架构债务，建立干净基础 | ✅ 完成 | [checklist](phase5/checklist.md) |
| 6 | 3D 适配 | AI Renderer 适配俯视 3D 渲染 | ✅ 完成 | [checklist](phase6/checklist.md) |
| 7 | 完整 3D 模式 | 游戏本体迁移到 3D 节点树 | ✅ 完成 | [checklist](phase7/checklist.md) |
| 8 | AI 感知完整化 | 验证层完整化 + 感知层重新设计 | ✅ 完成 | [checklist](phase8/checklist.md) |
| 9 | 等距视角镜头 | 从俯视 90° 切换到 45° 等距正交视角 | ✅ 完成 | [checklist](phase9/checklist.md) |
| 10 | 弓箭手 + 独立测试场景 | Archer 兵种（真实弹道 + kite）+ 测试架构重构 | ✅ 完成 | [checklist](phase10/checklist.md) |
| 11 | 弓箭手接入主游戏 | 玩家 HQ 生产面板支持生产 Archer | ✅ 完成 | [checklist](phase11/checklist.md) |
| 12 | 窗口测试自动化 | `Input.parse_input_event()` 注入真实鼠标事件，断言验证框选/点选等鼠标交互 | ✅ 完成 | [checklist](phase12/checklist.md) |
| 13 | 测试体系重构 | 统一测试单元规范（.tscn + JSON 成对）、迁移并删除 JSON 注入模式、建立场景登记表约束 | ✅ 完成 | [checklist](phase13/checklist.md) |
| 14 | 测试提速 | 事件驱动提前退出（断言全 PASS 即退出，不跑完全部帧数），缩短全量回归耗时 | ✅ 完成 | [checklist](phase14/checklist.md) |
| 15 | 将领单位 + 兵团跟随 | 将领节点 + 哑兵阵型跟随 + 待命切换 + 自动补兵 + 目视验证场景 | ✅ 完成 | [checklist](phase15/checklist.md) |
| 16 | 行军阵型系统 | 路径队列纵队行军 + 静止自动展开横阵 + 状态切换流畅性验证 | ✅ 完成 | [checklist](phase16/checklist.md) |
| 17 | 单位物理碰撞 | 哑兵升级 RigidBody3D，Seek Force 驱动，真实弹性推挤，消除穿透堆叠 | ⏳ 进行中（17A 代码完成，待视觉验证） | [checklist](phase17/checklist.md) |

---

## Phase 定位

```
Phase 0   → 验证链路可行性
Phase 0.5 → 验证技术可行性
Phase 1   → 能跑
Phase 2   → 跑对
Phase 3   → 好玩
Phase 4   → 能长
Phase 5   → 好维护（穿插在 Phase 3 后）
Phase 6   → 调试工具 3D 适配
Phase 7   → 游戏本体 3D 迁移
Phase 8   → AI 感知完整化（验证层 + 感知层）
Phase 9   → 等距视角镜头（45° isometric）
Phase 10  → 弓箭手兵种 + 独立测试场景
Phase 11  → 弓箭手接入主游戏（HQ 生产面板）
Phase 12  → 窗口测试自动化（真实鼠标事件注入）
Phase 13  → 测试体系重构（统一规范 + 清除历史债务）
Phase 14  → 测试提速（事件驱动提前退出，缩短全量回归耗时）
Phase 15  → 将领单位 + 兵团跟随（将领节点、哑兵阵型、待命切换、自动补兵）
Phase 16  → 行军阵型系统（路径队列纵队行军、静止展开横阵、状态自动切换）
Phase 17  → 单位物理碰撞（哑兵 RigidBody3D、Seek Force、弹性推挤）
```

---

## 设计文档索引

| 文档 | 适用 Phase | 说明 |
|------|-----------|------|
| [design/game/mvp.md](../design/game/mvp.md) | Phase 1+ | 玩法机制设计 |
| [design/game/INDEX.md](../design/game/INDEX.md) | Phase 1+ | 游戏设计文档索引 |
| [design/ui/INDEX.md](../design/ui/INDEX.md) | Phase 1+ | UI 组件设计规范与交互定义（断言以此为准） |
| [design/tech/ai-renderer.md](../design/tech/ai-renderer.md) | Phase 0.5+ | AI Renderer 架构（v1-v4） |
| [design/tech/test-architecture.md](../design/tech/test-architecture.md) | Phase 10+ | 自动化测试体系架构（测试单元规范、分类、登记表） |
| [phases/phase5/design.md](phase5/design.md) | Phase 5 | 架构重构设计 |
| [phases/phase6/design.md](phase6/design.md) | Phase 6 | AI Renderer 3D 适配设计 |
| [phases/phase8/design.md](phase8/design.md) | Phase 8 | AI 感知完整化设计 |
| [phases/phase9/design.md](phase9/design.md) | Phase 9 | 等距视角镜头设计 |
| [phases/phase10/design.md](phase10/design.md) | Phase 10 | 弓箭手兵种 + 独立测试场景设计 |
| [phases/phase11/checklist.md](phase11/checklist.md) | Phase 11 | 弓箭手接入主游戏 checklist |
| [phases/phase12/design.md](phase12/design.md) | Phase 12 | 窗口测试自动化设计 |
| [design/game/gameplay-vision.md](../design/game/gameplay-vision.md) | Phase 15+ | 玩法愿景：将领视角、人海阵型、士气溃败传染、信号协作 |
| [phases/phase15/design.md](phase15/design.md) | Phase 15 | 将领单位 + 兵团跟随设计（将领节点、哑兵阵型、补兵机制、目视验证场景） |
| [phases/phase16/design.md](phase16/design.md) | Phase 16 | 行军阵型系统设计（路径队列、纵队行军、横阵展开、状态切换） |
| [phases/phase17/design.md](phase17/design.md) | Phase 17 | 单位物理碰撞设计（RigidBody3D、Seek Force、碰撞层架构） |
