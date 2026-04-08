# Phase 14 设计文档：测试提速

> **适用阶段**：Phase 14
> **写于**：2026-04-03
> **背景**：Phase 13 已完成测试体系规范化。Phase 14 目标是缩短全量回归耗时，核心手段是让所有场景在断言全部结束（pass 或 fail）后立即退出，不等跑完 `total_frames`。

---

## 1. 问题分析

### 1.1 现状

`bootstrap.gd` 和 `combat_bootstrap.gd` 中已有早退逻辑：

```
每帧：
  all_done = calibrator.tick()
  if all_done or frame_count >= total_frames:
      结束场景
```

`calibrator.tick()` 返回 `true` 的条件是：**所有活跃断言都已到达 `pass` 或 `fail` 最终态**（不再有 `pending`）。

### 1.2 为什么早退没有触发

当前所有耗时断言均采用「pending-until-pass」设计，**没有 `fail` 路径**：

| 断言 | 逻辑 | fail 路径 |
|------|------|-----------|
| `battle_resolution` | 等待 `kill_log.size() > 0` | ❌ 无，只有 pending 或 pass |
| `economy_positive` | 等待 `crystal_max >= 210` | ❌ 无 |
| `ai_produces` | 等待 `blue_alive > 3` | ❌ 无 |
| `ai_economy` | 等待 `blue_crystal_delivered` | ❌ 无 |
| `production_flow` | 等待 `production_occurred` | ❌ 无 |
| `worker_cycle` | 等待 `worker_harvesting_seen` | ❌ 无 |
| `archer_produced` | 等待 `lifecycle.archer_produced` | ❌ 无 |

结果：只要游戏世界正常运转，条件最终都会满足——但在满足之前，断言一直 `pending`，`calibrator.tick()` 一直返回 `false`，早退从不触发，场景跑满 `total_frames`（7200 帧）才结束。

### 1.3 量化影响

| 场景 | total_frames | 典型满足帧（估算） | 浪费帧数（估算） |
|------|-------------|-------------------|-----------------|
| economy_v2 | 7200 | ~600（最慢：economy_positive） | ~6600 |
| combat_v2 | 7200 | ~4000（最慢：battle_resolution） | ~3200 |
| interaction_v2 | 7200 | ~1900（action 序列 + archer 生产） | ~5300 |

**CombatBootstrap 场景无此问题**（smoke_test/archer_vs_fighter/archer_vs_archer/kite_behavior/archer_vs_archer），因为断言设计简洁，通常在 12–421 帧内就全部 pass，早退正常工作。

---

## 2. 解决方案

### 2.1 断言超时机制

在 `scenario.json` 中为每条断言声明**超时帧数**（`assertion_timeouts` 字段）。当某断言在指定帧数内仍为 `pending`，Calibrator 自动将其标记为 `fail`（附带超时原因）。

```
scenario.json 新字段（可选）：
{
  "assertion_timeouts": {
    "battle_resolution": 5000,
    "economy_positive": 1800,
    "ai_produces": 4000
  }
}
```

- **未声明超时的断言**：维持原有行为，pending 直到 total_frames
- **声明了超时的断言**：在 timeout_frame 时自动 fail，不再 pending
- **backward compatible**：无超时声明的旧场景行为不变

### 2.2 执行流程（更新后）

```
calibrator.tick(current_frame):
  for each assertion:
    if already has final result (pass/fail): skip
    call check_fn()
    if pass: mark pass
    elif fail: mark fail
    elif pending:
      if has timeout AND current_frame >= timeout_frame:
        mark fail (reason: "assertion timed out at frame N")

  return true if all active assertions have final results
```

### 2.3 各场景超时值建议（初始设计，可通过 Profile 调整）

| 场景 | 断言 | 建议 timeout_frame | 理由 |
|------|------|--------------------|------|
| economy_v2 | worker_cycle | 1200 | 工人应在 ~300 帧内开始采矿 |
| economy_v2 | production_flow | 2400 | 生产周期约 300 帧，含启动时间 |
| economy_v2 | economy_positive | 2400 | crystal_max >= 210 应在 2 个采矿周期内触发 |
| combat_v2 | ai_economy | 2400 | 蓝方经济应在 1800 帧内启动 |
| combat_v2 | ai_produces | 4000 | 生产 4+ 单位需要时间 |
| combat_v2 | battle_resolution | 6000 | 双方需要完成经济→军事→进攻→战斗 |
| interaction_v2 | interaction_chain | 2000 | action 序列 ~1600 帧内完成 |
| interaction_v2 | archer_produced | 2400 | Archer 生产在 action 序列后约 300 帧 |

### 2.4 behavior_health 特殊处理

`behavior_health` 断言在 interaction 场景中依赖 `FaultInjector`，而 interaction 场景未配置故障注入，因此该断言在 `assertion_setup.gd` 的 `register_all()` 中根本不注册（有 `if _fault_injector` 保护）。不在活跃集合中，不影响早退逻辑。

---

## 3. 不改的东西

以下内容**不在 Phase 14 范围内**，保持现状：

- `calibrator.gd` 的 `pass/fail` 状态机结构（只加 timeout 判断）
- `assertion_setup.gd` 中各断言的业务逻辑（不修改 check_fn 函数体）
- `scene_registry.json` 结构（不新增字段）
- `combat_bootstrap.gd`（CombatBootstrap 场景早退已正常工作）
- Window 场景（`window_interaction`）的超时行为（不在本 Phase 优化）

---

## 4. 预期收益

超时值设计合理后，三个主游戏场景的早退帧数从 7200 降至：

| 场景 | 预期早退帧 | 预期节省 |
|------|-----------|---------|
| economy_v2 | ~2400 | ~67% |
| combat_v2 | ~4000–6000 | ~17%–44% |
| interaction_v2 | ~2400 | ~67% |

**目标**：全量回归（Headless 7 场景）总耗时从当前基准降低 40% 以上。

---

## 5. 实现步骤概览

```
14A. 基础建设
  1. Calibrator 支持 timeout_frames 参数（per-assertion）
  2. Bootstrap 在加载 scenario.json 时读取 assertion_timeouts 并传入 Calibrator

14B. 场景配置
  1. 为 economy/combat/interaction 的 scenario.json 添加 assertion_timeouts
  2. 基于 Profile 数据校正超时值（先跑一次收集实际完成帧）

14C. 验证
  1. 确认三个场景均出现 "[BOOT] Early exit at frame X" 日志
  2. 全量回归 7/7 PASS，计算总耗时，与基准对比
  3. 确认没有"正确 pass 的断言被误判为 timeout fail"
```

---

_创建：2026-04-03_
