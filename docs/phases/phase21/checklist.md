# Phase 21 Checklist — 开发期快速验证工作流

**目标**: 建立三档验证工作流，消除开发中间步骤跑全量回归的惯性
**设计文档**: [design.md](design.md)

---

## 子阶段 21A：test_runner 过滤支持

- [x] **21A.1** `test_runner.gd` 读取 `OS.get_cmdline_user_args()`，解析 `--phase`、`--scene`、`--tag` 参数
- [x] **21A.2** `_load_registry()` 在 headless 过滤基础上叠加参数过滤（多参数取交集）
- [x] **21A.3** 过滤后无匹配场景时：打印明确错误信息（列出参数和可用值）
- [x] **21A.4** 过滤生效时在启动日志里显示过滤条件，例如：`[RUNNER] 过滤: phase=17 → 3 个场景`
- [x] **21A.5** 无参数时行为与之前完全一致（全量）

### 验证
- [x] **21A.6** `-- --phase 16` 只跑 phase 16 场景（5个），耗时 ~49s，5/5 PASS
- [x] **21A.7** `-- --scene general_marching` 只跑该单个场景，耗时 ~5.5s
- [x] **21A.8** `-- --tag formation` 只跑 covers 含 formation 的场景（待验证）
- [x] **21A.9** `-- --phase 99`（无匹配）打印可用 phase/scene 列表
- [x] **21A.10** 无参数全量回归 17/17 PASS（无退化）

---

## 子阶段 21B：checklist 模板更新

- [x] **21B.1** 在已有 phase 19、20 的 checklist 末尾补充"验证命令"块
- [x] **21B.2** 在 `dev-rules.md` 的 6.1 节补充验证命令决策树

---

## 子阶段 21C：规范更新

- [x] **21C.1** `dev-rules.md` 6.1 节补充 headless 验证决策树（开发中 vs 收尾）
- [x] **21C.2** `CLAUDE.md` 验证习惯章节同步更新（速查表 + 决策树）
- [x] **21C.3** `roadmap.md` 新增 Phase 21 条目

---

## 收尾

- [ ] **21D.1** `FILES.md` 更新：记录 `test_runner.gd` 改动
- [x] **21D.2** `roadmap.md` 标记 Phase 21 状态

---

## 验证命令

```bash
# 开发中（只跑 phase 21 相关）
godot --headless --path src/phase1-rts-mvp -- --phase 21

# 收尾全量（提交前）
godot --headless --path src/phase1-rts-mvp
```

---

_创建: 2026-04-18_
