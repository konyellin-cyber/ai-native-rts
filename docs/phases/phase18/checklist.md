# Phase 18 Checklist — 测试与工具链收敛

**目标**: 收敛回归入口、恢复 AI Renderer 单一来源、修复自动化接口漂移、清理仓库运行时产物
**设计文档**: [design.md](design.md)
**上游文档**: [phase5/design.md](../phase5/design.md)、[test-architecture.md](../../design/tech/test-architecture.md)

---

## 子阶段 18A：回归入口收敛

- [ ] **18A.1** 明确唯一 Headless 全量回归入口：`test_runner.tscn + scene_registry.json`
- [ ] **18A.2** `tests/run_scenarios.sh`：移除对已删除 `tests/scenarios/*.json` 的依赖，不再改写 `config.json`
- [ ] **18A.3** `tests/run_scenarios_parallel.sh`：改为从 `scene_registry.json` 读取所有 `window_mode=false` 场景，不再自带第二套场景列表
- [ ] **18A.4** `config.json`：移除或修正失效的默认 `scenario_file`，确保主项目默认启动不依赖不存在路径
- [ ] **18A.5** README / FILES：统一回归命令说明，只保留当前真实可用入口

---

## 子阶段 18B：AI Renderer 单一来源恢复

- [ ] **18B.1** 对比 `src/shared/ai-renderer/` 与 `src/phase1-rts-mvp/tools/ai-renderer/` 差异，确认当前真实运行代码缺口
- [ ] **18B.2** 将 `phase1` 中真实需要的变更回收进 `src/shared/ai-renderer/`
- [ ] **18B.3** 恢复 `phase1-rts-mvp/tools/ai-renderer/` → `../../shared/ai-renderer` 的单一来源引用方案
- [ ] **18B.4** 校验 `phase05-rts-prototype/tools/ai-renderer/` 与 Phase 5 约定一致；若不一致，同步收敛
- [ ] **18B.5** 增加一致性验证手段：至少一条命令或脚本能快速证明不存在 renderer 目录漂移
- [ ] **18B.6** 回归验证：phase1 / phase05 均能正常运行，不因目录收敛出现加载回归

---

## 子阶段 18C：自动化接口稳定化

- [ ] **18C.1** `bootstrap.gd`：暴露稳定 getter（至少 `get_config()`、`get_world()`、`get_lifecycle()` 或等价接口）
- [ ] **18C.2** `command_router.gd`：`unit_info` 改为通过稳定 getter 读取单位列表和存活统计，不再读 Bootstrap 私有字段
- [ ] **18C.3** `command_router.gd`：`_get_game_config()` 同时兼容 `Root` / `Bootstrap` 节点名，并只走公开接口
- [ ] **18C.4** `play_scenario` / 坐标解析逻辑改为使用真实地图宽高，不再静默退回过时默认值
- [ ] **18C.5** 为 `unit_info` / `play_scenario` / `world_click` 增加至少一轮可重复验证，证明当前主场景结构下命令可用

---

## 子阶段 18D：仓库卫生治理

- [ ] **18D.1** `.gitignore`：补充忽略 `.godot/`、`tests/screenshots/`、`tests/logs/` 及其他运行时产物
- [ ] **18D.2** 清理当前已跟踪的运行时截图/日志；若需保留样例，迁移为少量手工精选样本
- [ ] **18D.3** 确认测试脚本执行后不会留下配置回写或临时目录污染
- [ ] **18D.4** README / roadmap / FILES / Phase 5 文档中与“共享 renderer”“回归入口”“测试脚本”相关的描述与实现重新对齐

---

## 子阶段 18E：收尾

- [ ] **18E.1** Headless 全量回归：当前登记表中所有 `window_mode=false` 场景全部 PASS
- [ ] **18E.2** 选取一条窗口自动化链路做冒烟验证，确认 `command_router` 与窗口模式兼容
- [ ] **18E.3** `docs/phases/roadmap.md`：Phase 18 行状态更新
- [ ] **18E.4** `src/phase1-rts-mvp/FILES.md`：更新 `bootstrap.gd`、`command_router.gd`、回归脚本、ai-renderer 目录说明

---

## 验收标准

- `scene_registry.json` 重新成为唯一权威回归场景源
- AI Renderer 重新回到单一来源，不存在“shared 和实际运行代码漂移”
- 自动化命令基于稳定接口工作，不再依赖 Bootstrap 私有字段名
- 测试执行不会把运行时产物和配置回写带进 git

---

_创建: 2026-04-08_
