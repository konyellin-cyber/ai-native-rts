# Phase 25 Checklist — 2.5D 人海战场渲染层

**目标**: 在 Phase 24 MBE 逻辑不变的前提下，新增 3D 引擎中的 2D 精灵人海渲染路径，强化中世纪人群冲锋和打击感。
**设计文档**: [design.md](design.md)
**上游文档**: [phase24/design.md](../phase24/design.md)
**状态**: 收尾，不再扩展 2D 图集自然度目标。

---

## 验证范围声明

**验证主语**：双方各 250 名士兵，共 500 人，使用 `sprite2d` renderer 在 45 度正交镜头下对冲。
**核心体验**：红蓝 2D 人群密集可读，接触面压缩和击退可见，受击闪烁/粒子能体现群体冲锋打击感。

| 验证层 | 场景/命令 | 通过标准 |
|--------|----------|---------|
| Headless | `godot --headless --path src/phase1-rts-mvp -- --phase 25` | 战斗正常结束并写出 battle_result.json |
| 窗口视觉 | `mass_battle_sprite` | 2D 精灵、地面圆环、冲锋接触面可见 |
| 回退验证 | `mass_battle` | Phase 24 GLB 渲染路径未被破坏 |

---

## 子阶段 25A：文档与场景切分

- [x] **25A.1** 新建 `docs/phases/phase25/design.md`
- [x] **25A.2** 新建 `docs/phases/phase25/checklist.md`
- [x] **25A.3** `roadmap.md` 新增 Phase 25
- [x] **25A.4** 新建 `tests/gameplay/mass_battle_sprite` 场景目录
- [x] **25A.5** `scene_registry.json` 注册 `mass_battle_sprite`，phase=25
- [x] **25A.6** 约定正式 2D 图集落点：`assets/characters/sprites/`
- [x] **25A.7** 明确 Phase 25 图集必须是 45 度正交俯视，不接入横版侧视长枪动画

## 子阶段 25B：Renderer 模式切换

- [x] **25B.1** `mass_battle/bootstrap.gd` 支持按当前场景目录读取 `config.json`
- [x] **25B.2** 配置新增 `mass_battle.renderer_mode`
- [x] **25B.3** `renderer_mode="3d_model"` 使用原 `BattleRenderer`
- [x] **25B.4** `renderer_mode="sprite2d"` 使用新 `BattleSpriteRenderer`
- [x] **25B.5** Phase 24 `mass_battle` 保持 `3d_model`
- [x] **25B.6** Phase 25 `mass_battle_sprite` 使用 `sprite2d`

## 子阶段 25C：BattleSpriteRenderer 原型

- [x] **25C.1** 新建 `scripts/battle_sprite_renderer.gd`，`class_name BattleSpriteRenderer`
- [x] **25C.2** 使用红/蓝各一个 `QuadMesh MultiMesh` 渲染士兵精灵
- [x] **25C.3** 竖直 quad 面向 45 度正交相机
- [x] **25C.4** 使用程序化 shader 绘制 2D 中世纪士兵 placeholder
- [x] **25C.5** 继续渲染红/蓝地面选择圆环
- [x] **25C.6** DEAD 士兵隐藏到 y=-1000

## 子阶段 25D：动画与受击反馈

- [x] **25D.1** 根据 velocity 添加错帧步行动画
- [x] **25D.2** MBE 将 `stun_frames` 传给 renderer
- [x] **25D.3** 受击单位短暂闪白/压扁，强化命中反馈
- [x] **25D.4** 保持 Phase 24 `ImpactParticlePool` 可用
- [x] **25D.5** sprite2d 模式默认关闭红/蓝地面圆环
- [x] **25D.6** 死亡士兵固定在倒地最后一帧，不循环播放死亡动画
- [x] **25D.7** sprite2d 模式命中粒子改为少量暗红血点，避免夸张冲击特效

## 子阶段 25F：尸体层与动画去同步

- [x] **25F.1** 活人和尸体拆成独立 MultiMesh，避免尸体透明排序压住活人
- [x] **25F.2** 死亡士兵从活人 MultiMesh 隐藏，尸体 MultiMesh 显示
- [x] **25F.3** 尸体使用独立低锚点 billboard 层，固定倒地最后一帧
- [x] **25F.4** 行军动画使用 per-soldier seed 做相位错开和帧率差异
- [x] **25F.5** 行军/挺枪分支按速度、接触状态和 seed 切换
- [x] **25F.6** 受击动画使用不同起始帧和轻微压扁差异
- [x] **25F.7** 加入轻微尺寸和锚点 jitter，避免 500 人完全整齐复制
- [x] **25F.8** 随机性全部由 soldier index 派生，保证回放稳定
- [x] **25F.9** 通过 `ux_07_04b_blue150` / `ux_10_05b_blue10` 事件截图确认：尸体可见，活人动画不整齐划一

## 子阶段 25G：收尾与转出

**结论**：Phase 25 不再继续细化距离驱动行走、攻击生命周期、状态锁、12×6 图集和 v4 素材。原因是这些改动会继续加深 2D 图集系统，但无法从根本上解决 “2D 动画表现 3D 战场不自然” 的问题。

- [x] **25G.1** 记录收尾判断：2D 图集可以验证 2.5D 批量渲染链路，但不应继续承担完整 3D 空间表现
- [x] **25G.2** 保留 v3 候选素材作为原型资产，不再追加 v4 / 12×6 图集目标
- [x] **25G.3** 保留 renderer 的配置化 atlas 支持，作为后续实验兼容层
- [x] **25G.4** 取消 Phase 25 内的距离驱动行走、攻击生命周期、动作状态锁和有组织随机性待办
- [x] **25G.5** 将自然度问题转出到后续混合/3D 表现阶段：3D 长枪、3D/decal 尸体、投影阴影、低模士兵或 sprite impostor LOD

取消项说明：

- `anim_distance` / 距离驱动步频：不在 Phase 25 做。
- MBE `attack_phase` / 攻击生命周期：不在 Phase 25 做。
- v4 `12×6` 完整图集：不在 Phase 25 做。
- 动作分支和状态锁：不在 Phase 25 做。
- 前后排有组织随机性：不在 Phase 25 做。

---

## 子阶段 25E：验证

- [x] **25E.1** headless `--phase 25` 跑通
- [x] **25E.2** 窗口打开 `mass_battle_sprite` 无报错
- [x] **25E.3** 目视确认 45 度镜头下 2D 人群方向、大小和密度合理
- [x] **25E.4** 目视确认接触面压缩、击退、受击闪烁/粒子可见
- [x] **25E.5** 确认 Phase 24 `mass_battle` 仍可切回 GLB 模式

---

## 验证命令

```bash
# Phase 25 headless
godot --headless --path src/phase1-rts-mvp -- --phase 25

# Phase 25 窗口演示
godot --path src/phase1-rts-mvp --scene res://tests/gameplay/mass_battle_sprite/scene.tscn

# Phase 24 回退对照
godot --path src/phase1-rts-mvp --scene res://tests/gameplay/mass_battle/scene.tscn
```

---

_创建: 2026-05-04_
