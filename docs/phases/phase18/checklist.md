# Phase 18 Checklist — 测试与工具链收敛

**目标**: 收敛回归入口、恢复 AI Renderer 单一来源、修复已失效的自动化命令（unit_info/play_scenario）、清理仓库运行时产物
**设计文档**: [design.md](design.md)
**上游文档**: [phase5/design.md](../phase5/design.md)、[test-architecture.md](../../design/tech/test-architecture.md)

---

## 子阶段 18A：回归入口收敛

- [x] **18A.1** 明确唯一 Headless 全量回归入口：`test_runner.tscn + scene_registry.json`
- [x] **18A.2** `src/phase1-rts-mvp/tests/run_scenarios.sh`：重写为 `test_runner.tscn` 包装层，不再硬编码场景，不再改写 `config.json`
- [x] **18A.3** `src/phase1-rts-mvp/tests/run_scenarios_parallel.sh`：改为从 `scene_registry.json` 读取所有 `window_mode=false` 场景，不再自带第二套场景列表
- [x] **18A.4** `config.json`：移除失效的 `scenario_file`（原指向已删除的 `res://tests/scenarios/interaction.json`）
- [x] **18A.5** README / FILES：统一回归命令说明，只保留当前真实可用入口（FILES.md 已更新 run_scenarios.sh / run_scenarios_parallel.sh / config.json 条目）

---

## 子阶段 18B：AI Renderer 单一来源恢复

- [x] **18B.1** 对比 `src/shared/ai-renderer/` 与 `src/phase1-rts-mvp/tools/ai-renderer/` 差异：4 个文件漂移（action_executor / ai_renderer / calibrator / simulated_player），phase1 版本更新
- [x] **18B.2** 将 `phase1` 中真实需要的变更回收进 `src/shared/ai-renderer/`（viewport/real_click/timeout 功能）
- [x] **18B.3** 恢复 `phase1-rts-mvp/tools/ai-renderer/` → `../../shared/ai-renderer` 的单一来源引用方案（symlink）
- [x] **18B.4** 校验 `phase05-rts-prototype/tools/ai-renderer/`：同样改为 symlink → `../../shared/ai-renderer`
- [x] **18B.5** 增加一致性验证手段：`src/shared/tools/check_renderer_links.sh` 快速检测目录是否为 symlink
- [x] **18B.6** 回归验证：phase1 headless 15/15 PASS，symlink 切换无加载回归

---

## 子阶段 18C：自动化接口修复与稳定化

> **执行前置条件**：18B.6 已完成（ai-renderer 目录已收敛），再在最终路径上修改 `command_router.gd`。

- [x] **18C.1** `bootstrap.gd`：新增稳定 getter：`get_config() -> Dictionary`、`get_units_for_debug() -> Array`、`get_red_alive() -> int`、`get_blue_alive() -> int`
- [x] **18C.2** `command_router.gd`：`_do_unit_info()` 将 `bootstrap.get("units")` 替换为 `bootstrap.get_units_for_debug()`；将 `bootstrap.get("_red_alive/blue_alive")` 替换为 `bootstrap.get_red_alive() / get_blue_alive()`
- [x] **18C.3** `command_router.gd`：`_get_game_config()` 补充查找 `Root` 节点（先 `Root` 后 `Bootstrap`），与 `_do_unit_info()` 保持一致
- [x] **18C.4** `_resolve_scenario_rect()` / `_resolve_scenario_target()`：改为从 `config.map.width/height` 读取，不再静默退回硬编码 `2000×1500`
- [x] **18C.5** 回归验证：headless 15/15 PASS（接口修改未引入退化）

---

## 子阶段 18D：仓库卫生治理

- [x] **18D.1** `.gitignore`：补充忽略 `**/.godot/`、`src/phase1-rts-mvp/tests/screenshots/`、`src/phase1-rts-mvp/tests/logs/`、`*.log`
- [x] **18D.2** 清理当前已跟踪的运行时截图/日志：`git rm --cached` 移除 4006 个文件（screenshots/ + logs/）
- [x] **18D.3** 确认测试脚本执行后不会留下配置回写（run_scenarios.sh 重写后不再改写 config.json）
- [x] **18D.4** FILES.md 与实现重新对齐：bootstrap.gd / run_scenarios*.sh / config.json 条目已更新

---

## 子阶段 18E：收尾

- [x] **18E.1** Headless 全量回归：当前登记表中所有 15 个 `window_mode=false` 场景全部 PASS（验证两轮：18B.6 / 18C.5）
- [x] **18E.2** 选取一条窗口自动化链路做冒烟验证：`tests/legacy/interaction/scene.tscn` 16 assertions 全部 PASS，`command_router` 与窗口模式兼容
- [x] **18E.3** `docs/phases/roadmap.md`：Phase 18 行状态更新
- [x] **18E.4** `src/phase1-rts-mvp/FILES.md`：更新 `bootstrap.gd`、回归脚本、config.json 说明

---

## 验收标准

- `scene_registry.json` 重新成为唯一权威回归场景源 ✅
- AI Renderer 重新回到单一来源，不存在"shared 和实际运行代码漂移" ✅
- 自动化命令基于稳定接口工作，不再依赖 Bootstrap 私有字段名 ✅
- 测试执行不会把运行时产物和配置回写带进 git ✅

---

_创建: 2026-04-08_
