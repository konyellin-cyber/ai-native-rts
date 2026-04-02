# Phase 5 可维护性重构 — Checklist

**目标**：清偿 Phase 1–3 快速迭代积累的架构债务，为 Phase 4 功能扩展建立干净的基础。
**设计文档**：`docs/design/arch-refactor.md`
**约束**：每个子阶段完成后必须 headless 回归，重构期间不改游戏逻辑。

---

## 5A：Bootstrap 拆分 ✅

**目标**：将 `bootstrap.gd`（772 行上帝类）拆分为 4 个聚焦模块，bootstrap 缩减到 ≤ 150 行。

- [x] **5A.1** 新建 `game_world.gd`：实体创建 + 场景树组装
- [x] **5A.2** 新建 `unit_lifecycle_manager.gd`：死亡清理、alive 计数、kill_log
- [x] **5A.3** 新建 `assertion_setup.gd`：断言注册集中管理
- [x] **5A.4** 精简 `bootstrap.gd`：只保留主序调度
- [x] **5A.5** headless 回归：10/11 PASS，avg_fps=60.1（battle_resolution 为预存在问题）
- [x] **5A.6** 更新 `FILES.md`

---

## 5B：断言结构化 ✅

**目标**：断言函数改为基于 `get_snapshot()` 字典查询，与 Formatter 文本格式彻底解耦。

- [x] **5B.1** 确认 `get_snapshot()` API 稳定
- [x] **5B.2** 迁移 4 条断言（hq_exists / mineral_exists / worker_exists / economy_positive）→ snapshot 字典查询
- [x] **5B.3** 删除字符串 parse 逻辑，添加"为什么改"注释
- [x] **5B.4** bootstrap 调用签名更新：移除 `_world` 引用，改传 `mineral_nodes.size()`
- [x] **5B.5** headless 回归：10/11 PASS
- [x] **5B.6** 更新 `FILES.md`、`implementation-plan.md`

---

## 5C：AI Renderer 共享化 ✅

**目标**：`src/shared/ai-renderer/` 作为单一来源，phase05 和 phase1 通过 symlink 引用。

- [x] **5C.1** 创建 `src/shared/ai-renderer/`，复制 phase1 v6 代码为 canonical 版本
- [x] **5C.2** 验证 symlink 在 Godot `res://` 路径下可 resolve
- [x] **5C.3** phase1 `tools/ai-renderer/` 替换为 symlink（`→ ../../shared/ai-renderer`）
- [x] **5C.4** headless 回归 phase1：10/11 PASS
- [x] **5C.5** phase05 旧版归档为 `tools/ai-renderer_legacy/`，替换为 symlink
- [x] **5C.6** headless 回归 phase05：9/9 PASS
- [x] **5C.7** 更新两个 Phase 的 FILES.md

---

## 5D：SimPlayer + InputServer 职责分离 ✅

**目标**：拆分 simulated_player（→3 文件）和 input_server（→3 文件），各文件 ≤ 200 行。

- [x] **5D.1** SimPlayer 拆分：`simulated_player.gd`（剧本调度）+ `action_executor.gd`（动作执行）+ `signal_tracer.gd`（信号追踪）
- [x] **5D.2** InputServer 拆分：`input_server.gd`（TCP 连接管理）+ `command_router.gd`（命令路由+输入注入）+ `ui_inspector.gd`（UI 查询）
- [x] **5D.3** 接口保持向后兼容，外部调用方（bootstrap）无需修改
- [x] **5D.4** headless 回归 phase1：10/11 PASS，avg_fps=60.1（battle_resolution 为预存在 FAIL）
- [x] **5D.5** headless 回归 phase05：9/9 PASS
- [x] **5D.6** 更新 FILES.md（shared/ai-renderer/）

---

## 5E：采样策略分级 ✅

**目标**：`SensorRegistry` 支持按 group 独立配置采样率。

- [x] **5E.1** `register()` 新增可选 `group: String` 参数（默认 `"units"`）
- [x] **5E.2** `tick()` 按 group 查表采样率；第一帧全量预热 `_cached_data`，确保低频实体在第一个 snapshot 中可见
- [x] **5E.3** `config.json` 新增 `renderer.sensors`（`{"units": 10, "economy": 60}`）
- [x] **5E.4** 旧 `sample_rate` 字段向后兼容（作为未配置 group 的默认值）
- [x] **5E.5** `game_world.gd`：HQ / Mine 注册为 `"economy"` group，units 保持 `"units"`（默认）
- [x] **5E.6** headless 回归 phase1：10/11 PASS；phase05：9/9 PASS

---

## 5F：故障注入隔离 ✅

**目标**：bootstrap 中的故障注入代码（~65行）迁移到独立 `FaultInjector` 节点，生产代码路径零测试桩。

- [x] **5F.1** 新建 `shared/ai-renderer/fault_injector.gd`（Node）：`setup(units_getter, fi_config)` + 只读属性 `injected / restored / frozen_units` + 信号 `fault_injected / fault_restored`
- [x] **5F.2** bootstrap 条件挂载：仅 `config.fault_injection` 非空时创建 FaultInjector 并 add_child
- [x] **5F.3** 从 bootstrap 彻底移除故障注入相关变量和 4 个函数（`_setup_fault_injection` / `_process_fault_injection` / `_freeze_unit_nav` / `_restore_all_units`）
- [x] **5F.4** `AssertionSetup.setup()` 签名：`fault_state: Dictionary` → `fault_injector: Node`；`_assert_behavior_health` 直接读 injector 只读属性
- [x] **5F.5** headless 回归：10/11 PASS，`behavior_health` PASS（故障注入 + 恢复路径验证正常）
- [x] **5F.6** 更新 FILES.md
