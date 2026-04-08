# Phase 14 Profile 数据

## 优化前基准（Phase 13 完成后，assertion_timeouts 未配置）

> 日期：2026-04-03
> 说明：此时 calibrator.gd 已支持 `tick(frame)` 签名，但尚无 `assertion_timeouts` 配置。
> 早退机制已工作，三个主游戏场景均在 total_frames 前自然退出。

### 各场景退出帧 & 耗时

| 场景 | 退出帧 | elapsed_ms | avg_fps | total_frames |
|------|--------|------------|---------|--------------|
| economy_v2 | 840 | 13,891 ms | 60.5 | 7200 |
| combat_v2 | 1,247 | 20,768 ms | 60.0 | 7200 |
| interaction_v2 | 1,816 | 30,233 ms | 60.1 | 7200 |
| smoke_test | (早退) | 6,619 ms | 60.1 | — |
| archer_vs_fighter | (早退) | 7,470 ms | 60.1 | — |
| archer_vs_archer | (早退) | 9,786 ms | 60.1 | — |
| kite_behavior | 12 | 185 ms | 64.9 | — |

**全量回归总耗时（wall-clock）**：约 89 秒（`time` 命令测量）

### 发现

- 三个主游戏场景已在 1000–2000 帧内触发早退，远早于 total_frames=7200
- 早退机制在 Phase 12/13 实现后就已经正常工作
- 断言超时（assertion_timeouts）作为**安全网**仍有价值：防止未来断言逻辑 bug 导致场景跑满 7200 帧

### 各断言实际通过帧（从日志推断）

economy_v2 断言完成帧 ≈ 840（最晚断言通过帧）：
- hq_exists / mineral_exists / worker_exists：极早（snapshot 采样后，~60 帧）
- worker_cycle：~300–500 帧（工人开始采矿）
- production_flow：~600–800 帧（生产一次单位）
- economy_positive：~840 帧（crystal 达到 210）

combat_v2 断言完成帧 ≈ 1247：
- ai_economy：~600 帧（蓝方 worker 完成第一次交付）
- ai_produces：~900 帧（蓝方生产 4+ 单位）
- battle_resolution：~1247 帧（发生击杀）

interaction_v2 断言完成帧 ≈ 1816：
- interaction_chain：~1575 帧（actions 序列完成：60+2+600+2+600+5+300+5 ≈ 1574 帧）
- behavior_health：pass（无 FaultInjector，立即 pass）
- archer_produced：~1816 帧（Archer 生产完成）

---

## assertion_timeouts 建议值（基于 Profile 数据，留 2× 余量）

| 场景 | 断言 | 实际完成帧 | 建议超时帧 | 余量倍数 |
|------|------|-----------|-----------|---------|
| economy_v2 | worker_cycle | ~500 | 1500 | 3× |
| economy_v2 | production_flow | ~800 | 2000 | 2.5× |
| economy_v2 | economy_positive | ~840 | 2000 | 2.4× |
| combat_v2 | ai_economy | ~600 | 2000 | 3.3× |
| combat_v2 | ai_produces | ~900 | 2500 | 2.8× |
| combat_v2 | battle_resolution | ~1247 | 4000 | 3.2× |
| interaction_v2 | interaction_chain | ~1575 | 3500 | 2.2× |
| interaction_v2 | archer_produced | ~1816 | 4000 | 2.2× |

留 2–3× 余量，确保随机性/帧率波动不会误触发超时 fail。

---

_记录：2026-04-03_
