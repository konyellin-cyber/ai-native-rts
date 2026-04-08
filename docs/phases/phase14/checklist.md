# Phase 14 — 测试提速 Checklist

**目标**：给主游戏场景（economy / combat / interaction）的断言加超时机制，让 Calibrator 在所有断言结束（pass 或 timeout-fail）后立即退出，缩短全量回归耗时。

**前置依赖**：
- Phase 13 全部完成（`scene_registry.json` 权威登记表已建立）
- 全量回归基准：Headless 7/7 PASS，记录当前总耗时（作为对比基线）

**设计参考**：[测试提速设计文档](design.md)

---

### 子阶段 14A：Calibrator 超时支持

- [x] **14A.1** `tools/ai-renderer/calibrator.gd`：`tick()` 接收 `current_frame: int` 参数；对声明了 `_timeout_frames[name]` 的断言，若 `current_frame >= timeout_frame` 且仍为 pending，自动标记为 fail（detail 包含超时帧信息）
- [x] **14A.2** `calibrator.gd`：新增 `set_assertion_timeouts(timeouts: Dictionary)` 方法，接受 `{ assertion_name: timeout_frame }` 字典
- [x] **14A.3** `scripts/bootstrap.gd`：加载 `scenario.json` 后，读取 `assertion_timeouts` 字段（若有），调用 `calibrator.set_assertion_timeouts()`；更新每帧 `renderer.tick()` 调用为 `renderer.tick(frame_count)`（传递当前帧号）
- [x] **14A.4** `tools/ai-renderer/ai_renderer.gd`：`tick()` 签名增加 `frame: int = 0` 参数，转发给 `_calibrator.tick(frame)`
- [x] **14A.5** 验证：全量回归 7/7 PASS，`[BOOT] Calibrator assertion_timeouts` 日志确认超时参数正确加载

---

### 子阶段 14B：场景配置

- [x] **14B.1** 跑一次全量回归，从 `[PERF]` 和 `[CALIBRATE]` 日志中提取三个场景各断言的实际退出帧，记录到 `docs/phases/phase14/profile.md`
- [x] **14B.2** `tests/scenes/economy/scenario.json`：添加 `assertion_timeouts`（worker_cycle: 1500, production_flow: 2000, economy_positive: 2000）
- [x] **14B.3** `tests/scenes/combat/scenario.json`：添加 `assertion_timeouts`（ai_economy: 2000, ai_produces: 2500, battle_resolution: 4000）
- [x] **14B.4** `tests/scenes/interaction/scenario.json`：添加 `assertion_timeouts`（interaction_chain: 3500, archer_produced: 4000）

---

### 子阶段 14C：验证收尾

- [x] **14C.1** 全量回归（Headless）：确认三个主游戏场景日志中出现 `[BOOT] Early exit at frame X (all assertions resolved)`（economy: 860, combat: 1223, interaction: 1816）
- [x] **14C.2** 全量回归：7/7 PASS，无断言因超时值设置过小而误判为 fail
- [x] **14C.3** 耗时与基准对比：三个主游戏场景均在 2000 帧内退出（总帧数上限 7200），早退机制正常工作
- [x] **14C.4** `docs/phases/phase14/profile.md`：记录优化前基准数据及 assertion_timeouts 配置
- [x] **14C.5** `src/phase1-rts-mvp/FILES.md`：更新 `calibrator.gd`、`bootstrap.gd`、`ai_renderer.gd` 条目，记录 Phase 14 变更
- [x] **14C.6** `docs/phases/roadmap.md`：Phase 14 行标记 ✅ 完成

---

### 验收标准

- `calibrator.gd` 支持 per-assertion 超时，timeout 触发时标记为 fail 并打印超时帧信息
- economy / combat / interaction 三个场景均在 `total_frames` 前触发早退
- 全量回归（Headless）7/7 PASS
- `assertion_timeouts` 不声明时，旧行为完全兼容（无 timeout = 无限等待）

---

_创建：2026-04-03_
