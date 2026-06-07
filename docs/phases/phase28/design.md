# Phase 28 设计文档 — Blender 枪兵低多边形建模

**所属项目**: AI Native RTS
**状态**: 🚧 进行中
**创建**: 2026-05-10
**上游文档**: [phase27/design.md](../phase27/design.md)
**代码根目录**: `src/phase1-rts-mvp/`
**3D 资产目录**: `src/phase1-rts-mvp/assets/characters/3d/`

---

## 一句话目标

> 用 Blender 5.1 命令行（`--background --python`）自动化建模流程，参照 Phase 27 的 2D 线稿基准，产出一个低多边形枪兵模型（mesh + 骨骼 + 4 组动作），并渲染 32 张等距静帧与 Phase 26 atlas 对比验证。

---

## 背景

Phase 26 的渲染层使用 `BattleSpriteRenderer`，士兵是 AI 生成的 2D sprite atlas（Phase 27 演练产出）。Phase 28 的定位是：

- 建立对应的 **3D 主资产**，作为未来渲染新 atlas 或替换为真 3D 实例化的源文件
- 验证 **Blender CLI 自动化流程**是否可以驱动建模/骨骼/动画/渲染管线
- Phase 28 **不改引擎代码**，不替换现有 Phase 26 sprite，纯美术资产交付

---

## 工具链：Blender CLI

### 调用方式

```bash
BLENDER=/Applications/Blender.app/Contents/MacOS/Blender

# 执行 Python 脚本（无 GUI）
$BLENDER --background --python scripts/build_pikeman.py

# 执行内联脚本
$BLENDER --background --python-expr "import bpy; ..."
```

### 能力边界

| 能力 | 可否 CLI | 说明 |
|---|---|---|
| 创建 mesh（add_primitive, bmesh） | ✅ | 完全支持 |
| 骨骼绑定（armature, weight_paint） | ✅ | bpy.ops.object 系列 |
| 关键帧动画（keyframe_insert） | ✅ | action + fcurve 全部可操作 |
| 等距正交摄像机 | ✅ | orthographic + rotation |
| 渲染静帧（render.render） | ✅ | Cycles / EEVEE 均可 |
| 导出 .glb（io_scene_gltf2） | ✅ | Blender 内置 |
| 导出 .blend | ✅ | bpy.ops.wm.save_as_mainfile |

### 局限

- 权重绘制（weight paint 笔刷）无法 CLI 操作 → 用脚本直接写 vertex_group weights 替代
- 复杂拓扑雕刻 → 不适合 CLI，但低多边形体块建模完全可行

---

## 技术设计

### 坐标约定

```
Blender 坐标系: Z-up, Y-forward
等距摄像机:
  rotation_euler = (radians(60), 0, radians(45))   ← 等距 45°
  type = 'ORTHO'
  ortho_scale = 3.0（覆盖 ~1.8m 高士兵）
```

士兵站立在世界原点，脚底在 Z=0，头顶约 Z=1.8m（头身比 1:4.5 约 0.4m 头 + 1.4m 身）。

### 比例规范（参照 Phase 27 线稿）

| 部位 | 尺寸（Blender 单位 ≈ 米） |
|---|---|
| 总高 | 1.8 |
| 头（含头盔） | 0.38 |
| 躯干（胸+腰） | 0.55 |
| 大腿 | 0.38 |
| 小腿+靴 | 0.49 |
| 肩宽 | 0.55 |
| 长枪长度 | 2.4 |

### 面数目标

| 部件 | 目标三角面 |
|---|---|
| 头盔（bowl helm） | 80 |
| 躯干（梯形板甲 + 腰裙） | 120 |
| 上臂 × 2 | 56 |
| 前臂 × 2 | 56 |
| 大腿 × 2 | 72 |
| 小腿 × 2 | 56 |
| 靴 × 2 | 48 |
| 手 × 2（握拳体块） | 32 |
| 长枪（圆柱 + 矛头） | 48 |
| **合计** | **≤ 600 三角面** |

### 骨骼结构（17 骨骼）

```
root
 └─ hips
     ├─ spine
     │    └─ chest
     │         ├─ neck → head
     │         ├─ shoulder_L → upper_arm_L → forearm_L → hand_L
     │         └─ shoulder_R → upper_arm_R → forearm_R → hand_R
     │                                                     └─ spear
     ├─ thigh_L → shin_L → foot_L
     └─ thigh_R → shin_R → foot_R
```

无手指/脚趾骨骼，适合 RTS 小人尺度（500 实例下不可见）。

### 动作规范（对齐 Phase 26 atlas）

| Action 名 | 帧范围 | fps | impact/hold |
|---|---|---|---|
| `charge_run` | 1–8 | 12 | — |
| `spear_thrust` | 1–8 | 14 | impact: frame 4-5 |
| `hit_recoil` | 1–8 | 12 | — |
| `death_fall` | 1–8 | 8 | hold: frame 3–8 |

每个 Action 存为独立 NLA strip，`.blend` 文件中 4 个 Action 并存。

---

## 脚本架构

所有 Blender 操作封装为可复用的 Python 脚本，放在：

```
src/phase1-rts-mvp/assets/characters/3d/scripts/
  01_build_mesh.py        # 建体块 mesh（各部位独立 object）
  02_join_and_clean.py    # 合并 mesh，清理拓扑
  03_rig.py               # 创建 armature，自动 weight
  04_pose_and_animate.py  # 4 组 action 关键帧
  05_render_frames.py     # 等距摄像机渲染 32 帧
  06_export.py            # 导出 .glb
  run_all.sh              # 串联执行全部步骤
```

每个脚本独立可运行，便于单步调试：

```bash
BLENDER=/Applications/Blender.app/Contents/MacOS/Blender
$BLENDER --background --python scripts/01_build_mesh.py
```

---

## 执行顺序

```
28A: 建模（01_build_mesh.py + 02_join_and_clean.py）
  → 产出: pikeman_mesh.blend
  → 验证: 等距静帧与 Phase 27 线稿比例吻合，面数 ≤ 600

28B: 骨骼绑定（03_rig.py）
  → 产出: pikeman_rigged.blend
  → 验证: 6 个 Phase 27 关键姿态可在 Blender pose mode 中复现

28C: 动作制作（04_pose_and_animate.py）
  → 产出: pikeman_animated.blend（含 4 Action strips）
  → 验证: 动作逐帧与 Phase 26 atlas 形态对齐

28D: 渲染验证（05_render_frames.py）
  → 产出: renders/ 32 张 256x256 PNG
  → 验证: 拼成 2048x1024 atlas 与 Phase 26 线稿 atlas 逐帧对比

28E: 导出（06_export.py）
  → 产出: pikeman_v1.glb
  → 验证: Godot 可加载（目测，不接入场景）
```

---

## 交付物

| 文件 | 路径 | 说明 |
|---|---|---|
| `pikeman_animated.blend` | `assets/characters/3d/` | 主 Blender 文件，含 mesh + armature + 4 actions |
| `pikeman_v1.glb` | `assets/characters/3d/` | 引擎可用格式 |
| `renders/` | `assets/characters/3d/renders/` | 32 张等距静帧 |
| `scripts/` | `assets/characters/3d/scripts/` | 全部 Python 脚本 |

---

## 非目标

- 不做材质 / 贴图（UV unwrap 留给后续 Phase）
- 不接入 Godot 场景（不改 MBE / BattleSpriteRenderer）
- 不替换 Phase 26 现有 sprite atlas
- 不做面部细节 / LOD

---

## 关键设计决策

### D1：全命令行驱动，不依赖手工 GUI 操作

原因：可复现、可版本控制、便于迭代。所有体块通过 bmesh API 程序化生成，所有 weight 通过脚本直接赋值，不用 GUI 权重笔刷。

### D2：低多边形体块风格，不追求写实

原因：Phase 26 的 sprite 本身是低多边形等距风格，3D 模型保持一致。面数 ≤ 600 既与 2D 参考对齐，也为后续 500 人 MultiMesh 保留余量。

### D3：骨骼权重全脚本赋值

原因：CLI 无法操作 weight paint 笔刷，但可以通过 `vertex_groups[bone].add([vert_idx], weight, 'REPLACE')` 精确控制。对低多边形模型（每部位面数少），手工规划 vertex group 完全可行。

### D4：4 个 Action 严格对齐 Phase 26 帧契约

原因：Phase 28 是未来替换 atlas 的基础。帧数/fps/impact 帧必须与 `003-phase26-pikeman-atlas-lineart.json` 的定义完全一致，否则后续 Phase 接入时会有动画时机错误。

---

## 修订历史

- **v1 (2026-05-10)**: 初稿
