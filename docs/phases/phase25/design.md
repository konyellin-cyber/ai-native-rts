# Phase 25 设计文档 — 2.5D 人海战场渲染层

**所属项目**: AI Native RTS
**状态**: 收尾 / 不再扩展 2D→3D 自然度目标
**创建**: 2026-05-04
**上游文档**: [phase24/design.md](../phase24/design.md)

---

## 目标

Phase 25 在不重写 Phase 24 Mass Battle Engine（MBE）逻辑的前提下，把人海战场的可视化从 3D GLB 小人升级为 **3D 引擎 + 2D 素材/动画** 的 2.5D 表现层。

核心目标：

1. **保留 500 人规模**：继续使用 PackedArray 数据和 MultiMesh 批量渲染，不回到每兵一个节点。
2. **强化中世纪战场观感**：士兵外观改为更易美术化的 2D 精灵/图集，适配 45 度正交镜头。
3. **强化群体冲锋打击感**：通过队形压缩、受击闪帧、击退位移、尘土/命中粒子，让玩家感知两堵人墙相撞。
4. **保留 Phase 24 对照路径**：旧 `BattleRenderer` 继续作为 `3d_model` 模式，Phase 25 新增 `sprite2d` 模式。

---

## 核心决策

### Q1：是否继续使用 3D 引擎？

继续使用 Godot 3D 场景、正交相机、3D 地面、3D 粒子和 3D 坐标系。

原因：

- Phase 24 的 MBE 数据、空间分区、战斗和相机都已经在 3D 坐标系内稳定运行。
- 45 度等距正交镜头下，2D 竖直面片可以稳定贴合画面。
- 后续仍可混用 3D 地形、投射物、粒子、UI 选框和调试工具。

### Q2：2D 素材如何渲染？

使用 `QuadMesh MultiMesh`：

```
BattleSpriteRenderer
 ├── MultiMeshInstance3D [红方精灵 Quad]
 ├── MultiMeshInstance3D [蓝方精灵 Quad]
 ├── MultiMeshInstance3D [红方尸体 Quad，低锚点 billboard]
 ├── MultiMeshInstance3D [蓝方尸体 Quad，低锚点 billboard]
 ├── MultiMeshInstance3D [红方地面圆环，可选]
 └── MultiMeshInstance3D [蓝方地面圆环，可选]
```

每名士兵仍然只是一个 MultiMesh instance。渲染层每帧读取 MBE 的 `positions / velocities / states / teams / stun_frames`，写入 transform 和 custom data。

### Q3：为什么不使用 AnimatedSprite3D？

不使用 `AnimatedSprite3D × 500`。

原因：

- 500 个节点会重新引入 Phase 23 的节点和脚本开销。
- 动画状态、排序和显隐需要逐节点维护，难以保持 MBE 的批处理优势。
- MultiMesh 更适合 Phase 24 已经确立的纯数据渲染模型。

---

## 渲染架构

### Renderer 模式切换

`mass_battle` 配置新增：

```
"renderer_mode": "3d_model" | "sprite2d"
```

Bootstrap 根据配置选择渲染器：

```
3d_model → scripts/battle_renderer.gd
sprite2d → scripts/battle_sprite_renderer.gd
```

Phase 24 场景继续使用 `3d_model`；Phase 25 场景 `mass_battle_sprite` 使用 `sprite2d`。

### Sprite 表现策略

第一版使用程序化 2D placeholder shader，先验证技术链路：

- 竖直 billboard quad 面向 45 度正交相机
- shader 画出头盔、躯干、盾牌、武器的硬边剪影
- 红蓝阵营使用不同材质色
- `INSTANCE_CUSTOM` 传入受击闪烁和动画相位

正式美术阶段再把程序化 shader 替换为图集采样：

```
src/phase1-rts-mvp/assets/characters/sprites/
  medieval_soldier_red.png
  medieval_soldier_blue.png
  medieval_soldier.json

run_0..run_7
attack_0..attack_5
hit_0..hit_2
death_0..death_5
```

图集视角要求：

- 必须是 Phase 9/24 的 45 度正交俯视 RTS 视角。
- 可以看到头盔顶部、肩背和脚下占位，而不是横版侧视角色。
- 红方长枪沿地面投影指向右上，蓝方长枪沿地面投影指向左下。
- 禁止使用横版动作游戏式的水平侧面长枪动画；这类素材只可放入 `assets/characters/sprites/rejected/` 作为废稿参考。

### 透明排序策略

2D 精灵在 3D 场景里的主要风险是透明排序。Phase 25 第一版采用硬边 alpha cutout：

- shader 内部 `discard` 透明区域
- 不使用大面积半透明羽化
- 活人精灵和地面圆环分开 MultiMesh

如果后续出现明显排序错误，再按队伍行或 Z bucket 拆成多个 MultiMesh 渲染层。

### 尸体渲染策略

死亡单位不能继续占用活人 billboard 渲染层，否则透明排序会让尸体压在活人上方。Phase 25 将活人与尸体拆分：

- 活人：竖直 camera-facing billboard，播放行军/攻击/受击动画。
- 尸体：单独 corpse MultiMesh，固定倒地最后一帧。
- 活人死亡时从活人 MultiMesh 隐藏，尸体 MultiMesh 显示；尸体不再循环播放动画。
- 当前图集已经是 45 度正交预投影素材，尸体不能再把 quad 旋到世界 XZ 平面，否则会被二次压扁成细线。
- 尸体仍保持 camera-facing billboard，但使用更低锚点、更小尺寸、独立较低 render priority，并在活人层之前加入场景树，避免压住仍在战斗的前排长枪兵。
- 尸体必须保持等比缩放，不能为了贴地感做非等比纵向补偿；否则会和原图死亡帧相比出现拉伸/压扁变形。
- 尸体使用 soldier-index 派生的稳定抽样，减少残局时满屏尸体和长枪线干扰。

### 动画去同步策略

500 人同时播放相同图集时，如果只用全局帧，会显得像整齐复制。Phase 25 使用确定性 per-soldier seed 增加变化：

- 每个士兵拥有不同动画相位和帧率偏移。
- 行军状态有 `charge_run` 和 `brace_thrust` 分支，低速/接触区更容易进入挺枪。
- 受击状态有不同起始帧和轻微压扁强度差异。
- 每个 sprite 有轻微尺寸和锚点 jitter，但不改变 MBE 真实位置。
- 所有随机性必须由 soldier index 派生，保证回放稳定，不引入非确定性逻辑。

### Phase 25 收尾结论

Phase 25 的有效产出是：验证 Godot 3D 场景中可以用 `QuadMesh MultiMesh + 2D atlas` 批量渲染 500 人规模的 2.5D 人海，并保留 Phase 24 的 MBE 逻辑和 GLB 回退路径。

但 Phase 25 也暴露了 2D 图集表现 3D 战场的硬限制：

- 2D 角色帧已经包含相机投影，不能自然承受 3D 旋转、贴地、遮挡和尸体层级变化。
- 尸体、长枪、脚底接触、阴影和前后遮挡是空间问题，继续增加 2D 动画帧数只能局部缓解，不能从根上解决。
- 更复杂的攻击生命周期、状态锁、距离驱动步频和 12×6 图集会增加系统复杂度，但仍然无法让 2D sprite 在 3D 战场里变得真正自然。

因此 Phase 25 不再继续细化 “用 2D 图集解决 3D 自然度” 的目标。现有 v2/v3 图集保留为原型素材，`BattleSpriteRenderer` 保留为可切换的 2.5D 实验路径；后续自然度问题应进入新的混合或 3D 表现阶段处理。

后续方向建议：

- 活人士兵可以继续用 2D body 作为远景人群表现，但不要再让 2D 图集承担所有空间表现。
- 长枪、尸体、阴影、血点和尘土更适合用 3D mesh、decal 或粒子处理。
- 如果目标是自然的 3D 战场，应评估低模 3D 士兵、骨骼动画、toon/hand-painted 材质，以及远距离 sprite impostor 的 LOD 方案。

---

## 打击感设计

Phase 25 的冲锋打击感不能只靠单兵动画，必须是三层叠加：

### 1. 群体形变

继续依赖 Phase 24 逻辑层：

- Crowd Pressure 让接触面压缩
- CombatResolver 的 impulse 让前排被击退
- stun 让被打单位短暂停顿，形成局部拥堵

渲染层不伪造战斗结果，只把这些真实位移表现得更清楚。

### 2. 单兵反馈

Sprite renderer 根据状态表现：

- 行军：按士兵 seed 错帧、变速，并在冲锋/挺枪分支之间切换，避免整队同步。
- 受击：短暂压扁/后仰，轻微暗红染色，主要反馈来自小血点。
- 死亡：从活人层移入贴地尸体层，固定在倒地最后一帧，不继续循环播放死亡动画。
- 地面圆环：sprite2d 模式默认关闭，避免红/蓝圆环干扰中世纪长枪人海观感；需要调试时可用 `sprite_show_rings=true` 打开。

### 3. 接触面粒子

继续复用 Phase 24 `ImpactParticlePool`，但 Phase 25 sprite2d 模式使用更克制的 `blood` 风格：

- 少量暗红血点，短寿命，小尺寸。
- 不再使用大团白色/蓝色冲击粒子。
- 粒子只做命中反馈，不遮挡长枪阵线。

尘土带、地面血迹和更完整的接触面特效不再作为 Phase 25 扩展项；这些更适合在后续混合/3D 表现阶段与 3D/decal 系统一起处理。

Phase 25 只保留已有的少量暗红血点作为命中反馈。

---

## 验证标准

| 验证层 | 场景/命令 | 通过标准 |
|--------|----------|---------|
| Headless | `--phase 25` | 500 人对冲逻辑正常结束，battle_result.json 有胜负结果 |
| 窗口视觉 | `mass_battle_sprite` | 45 度正交镜头下能看到红蓝 2D 人群、地面圆环、接触面压缩与受击反馈 |
| 性能 | 窗口模式 | 500 人稳定 ≥ 30 FPS，不出现明显卡顿 |
| 回退 | `mass_battle` | Phase 24 的 `3d_model` 渲染路径仍可运行 |

---

## 非目标

- 不在 Phase 25 重写 MBE 移动、战斗和空间分区。
- 不引入每士兵节点。
- 不在第一版制作最终美术图集。
- 不解决完整 8 向动画系统，只先验证 45 度镜头下的 2.5D 渲染路径。
- 不继续尝试用更多 2D 图集帧、攻击状态机或动画锁解决 2D→3D 的自然度问题。
- 不在 Phase 25 内实现 3D 长枪、3D/decal 尸体、投影阴影或低模 3D 士兵；这些转入后续阶段评估。
