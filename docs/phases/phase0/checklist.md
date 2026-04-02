# Phase 0 — 碰撞球 Checklist

## Phase 0：碰撞球场景——打通 AI debug 数据通路（1-2 天）

**目标**：用最小场景验证 Godot → 结构化数据 → AI 能读能分析这条链路

**全流程 CLI，不打开 Godot 编辑器。** 场景通过 config.json 驱动，GDScript 运行时动态创建节点，验证脚本自动化跑。

**场景**：5 个圆形在 2D 空间中运动，有碰撞（撞墙反弹 + 互相碰撞 + 碰撞后变色）

### Checklist

- [x] **0.1** 安装 Godot 4.6.1（`brew install --cask godot`），CLI 验证 `godot --version`
- [x] **0.2** 编写 `config.json`：定义边界 800x600、5 个球的初始位置和速度、导出配置
- [x] **0.3** 编写 `bootstrap.gd`：读配置动态创建球和墙壁，显式 collision layer/mask，`Engine.set_physics_ticks_per_second(60)` 保证 headless 帧率
- [x] **0.4** 编写 `ball.gd`：用 `contact_monitor` 检测碰撞（非 body_entered 信号），碰撞计数 + 状态记录（变色逻辑已实现，headless 下不可见）
- [x] **0.5** 编写 `state_exporter.gd`：每帧导出 JSON（tick, timestamp, balls[id/pos/vel/state/collision_count]）
- [x] **0.6** 确定性模拟：零重力 + 固定参数，300 帧两次运行游戏状态完全一致（timestamp 字段除外）
- [x] **0.7** 性能验证：开/关导出跑 300 帧，记录帧率差异 → **4937ms / 60.8fps，两者完全一致，I/O 开销可忽略**
- [x] **0.8** 确定性验证：跑 10 次，脚本对比导出的 JSON 是否完全一致（timestamp 除外） → **10/10 MATCH，完美确定性**
- [x] **0.9** 截图验证：headless 模式导出 3 帧截图 + 对应 JSON，对比位置偏差 < 1px → **15/15 PASS，像素采样验证通过**
- [x] **0.10** AI 理解验证：把一段 JSON 喂给 AI，验证 AI 能描述"发生了什么" → **AI 能还原运动状态、推断碰撞事件、判断相互作用关系**
- [x] **0.11** AI debug 验证：故意引入 bug（config 中速度方向反转），让 AI 通过导出数据定位问题 → **AI 成功定位：Y 轴速度符号错误导致球卡在顶墙**

**通过条件**：0.8 通过 + 0.9 通过 + 0.11 AI 能定位 bug
**退出条件**：导出开销太大（帧率掉 50%+）/ 位置对应不上 / AI 读不懂数据

---
