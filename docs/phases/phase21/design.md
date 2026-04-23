# Phase 21 设计文档 — 开发期快速验证工作流

**所属项目**: AI Native RTS
**状态**: 草案
**创建**: 2026-04-18
**上游文档**: [test-architecture.md](../../design/tech/test-architecture.md)

---

## 目标

消除开发中间步骤时"跑全量回归（158s）"的惯性，建立三档验证工作流并通过规范和工具链强制执行。

---

## 问题分析

当前 `test_runner.gd` 只有一种运行模式：全量跑登记表中所有 headless 场景。开发某个 phase 的中间步骤时，每次验证都要等 150s+ 的无关场景，导致：

1. **开发循环慢**：改一行参数验证需要 158s
2. **窗口场景入口不清晰**：`general_visual` 等窗口场景路径靠记忆，容易误启动主游戏
3. **规范无法强制执行**：文档里有规定但没有工具支撑，AI 和人都容易跳过

---

## 技术方案

### 21A：test_runner 支持 `--phase` / `--scene` / `--tag` 过滤

`test_runner.gd` 在 `_load_registry()` 中读取 `OS.get_cmdline_user_args()`，支持以下参数：

| 参数 | 效果 |
|------|------|
| `--phase N` | 只跑 registry 中 `phase == N` 的 headless 场景 |
| `--scene 名称` | 只跑 `name == 名称` 的场景（支持逗号分隔多个） |
| `--tag 标签` | 只跑 `covers` 包含该标签的场景 |
| 无参数 | 全量（现有行为不变） |

多个参数取**交集**。过滤后无匹配场景时报错退出，不静默成功。

命令示例：
```bash
# 只跑 phase 17 相关场景（~15s）
godot --headless --path src/phase1-rts-mvp -- --phase 17

# 只跑单个场景（~5s）
godot --headless --path src/phase1-rts-mvp -- --scene general_marching

# 只跑 formation 相关场景
godot --headless --path src/phase1-rts-mvp -- --tag formation
```

### 21B：checklist 模板内嵌验证命令块

每个新 phase 的 checklist 末尾固定包含"验证命令"块，开发时直接复制，不需要查文档：

```markdown
## 验证命令

# 开发中（只跑本 phase，快速）
godot --headless --path src/phase1-rts-mvp -- --phase N

# 收尾全量（提交前跑一次）
godot --headless --path src/phase1-rts-mvp
```

创建 checklist 时自动带入，N 替换为实际 phase 号。

### 21C：规范更新

`CLAUDE.md` 和 `dev-rules.md` 补充 headless 验证决策树：

- 开发中间步骤 → 默认 `--phase N`
- checklist 标注"收尾全量回归"步骤 → 无参数全量
- AI 执行 headless 验证时遵守同样的决策树

---

## 验收标准

- `godot --headless ... -- --phase 17` 只跑 phase 17 的场景，耗时 < 30s
- `godot --headless ... -- --scene general_marching` 只跑该单个场景
- 过滤后无匹配场景时报错退出（不静默）
- 无参数时行为与之前完全一致（全量 17/17 PASS）
- 现有 Phase 19、20 的 checklist 补充验证命令块

---

_创建: 2026-04-18_
