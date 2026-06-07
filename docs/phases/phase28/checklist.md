# Phase 28 Checklist — Blender 枪兵低多边形建模

**目标**: 用 Blender CLI 自动化建模，参照 Phase 27 线稿，产出低多边形枪兵 mesh + 骨骼 + 4 组动作，并渲染静帧验证。
**设计文档**: [design.md](design.md)
**上游**: [phase27/design.md](../phase27/design.md)
**状态**: 🚧 进行中

---

## 工具链验证

- [x] **T.1** Blender 5.1.1 安装确认（`/Applications/Blender.app/Contents/MacOS/Blender`）
- [x] **T.2** Blender CLI Python API 可用（`--background --python-expr "import bpy"` 通过）
- [x] **T.3** bpy bmesh 模块可用（`import bmesh; bmesh.new()` 通过）
- [x] **T.4** GLB 导出可用（`bpy.ops.export_scene.gltf` — Blender 5.1 中名称是 `gltf` 非 `gltf2`）
- [x] **T.5** 脚本目录 `src/phase1-rts-mvp/assets/characters/3d/scripts/` 已建立
- [x] **T.6** 渲染输出目录 `src/phase1-rts-mvp/assets/characters/3d/renders/` 已建立
- [x] **T.7** `run_all.sh` 已建立，串联全部脚本步骤

---

## 子阶段 28A：体块建模（01_build_mesh.py）

**目标**：程序化建出所有部件，面数 ≤ 600 三角面，比例对齐 Phase 27 线稿。

### 28A.1 坐标与摄像机

- [x] **28A.1.1** 建立等距正交摄像机：`rotation_euler=(54.74°, 0°, 45°)`, `type=ORTHO`, `ortho_scale=3.5`
- [x] **28A.1.2** 脚本可正常加载 Phase 27 参考图路径（作为摄像机视角验证基准）
- [ ] **28A.1.3** 手动确认：摄像机视角与 Phase 27 线稿 001 一致（渲染静帧对比）

### 28A.2 各部件建模（全部 bmesh API）

- [x] **28A.2.1** 头盔（bowl helm）：半球体 + 帽檐
- [x] **28A.2.2** 躯干：梯形胸甲 + 腰部分件
- [x] **28A.2.3** 上臂 × 2：六棱柱
- [x] **28A.2.4** 前臂 × 2：六棱柱（略细）
- [x] **28A.2.5** 大腿 × 2：八棱柱
- [x] **28A.2.6** 小腿 × 2：六棱柱
- [x] **28A.2.7** 靴 × 2：方盒
- [x] **28A.2.8** 手 × 2（握拳体块）：方盒
- [x] **28A.2.9** 长枪：圆柱（枪身）+ 锥体（矛头）

### 28A.3 验证

- [x] **28A.3.1** 渲染等距视角静帧（`28A_preview_iso.png`），形体可识别
- [x] **28A.3.2** 三角面总数: **556**（目标 ≤ 600 ✓）
- [x] **28A.3.3** 保存 `pikeman_mesh.blend`

---

## 子阶段 28B：体块合并与清理（02_join_and_clean.py）

- [x] **28B.1** 所有部件 join 为单一对象 `Pikeman`
- [x] **28B.2** 三角化 + 移除重复顶点（阈值 0.001）
- [x] **28B.3** 设置 Object origin 在脚底中心（世界原点）
- [x] **28B.4** 保存 `pikeman_clean.blend`，面数 556 ≤ 600 ✓

---

## 子阶段 28C：骨骼绑定（03_rig.py）

### 28C.1 Armature 创建

- [x] **28C.1.1** 创建 Armature，21 骨骼（含 root + 腿左右对称）
- [x] **28C.1.2** 骨骼命名规范：hips / spine / chest / neck / head / shoulder_L(R) / upper_arm_L(R) / forearm_L(R) / hand_L(R) / spear / thigh_L(R) / shin_L(R) / foot_L(R)
- [x] **28C.1.3** 各骨骼 head/tail 坐标对齐比例规范

### 28C.2 Weight Paint（脚本直接赋值）

- [x] **28C.2.1** 为每个骨骼建立同名 vertex_group
- [x] **28C.2.2** 脚本按 Z / X 坐标范围规则赋 weight（每顶点分配给一个骨骼）
- [x] **28C.2.3** Armature 修改器绑定，mesh parent 到 armature

### 28C.3 绑定验证

- [ ] **28C.3.1** 在 Blender GUI 中手动确认 6 个关键姿态可复现（需 GUI 操作）
- [x] **28C.3.2** 保存 `pikeman_rigged.blend`

---

## 子阶段 28D：动作制作（04_pose_and_animate.py）

- [x] **28D.1** `charge_run`：8 帧 × fps=12，两腿交替跨步，枪平举 ✓
- [x] **28D.2** `spear_thrust`：8 帧 × fps=14，impact 在 frame 4-5 ✓
- [x] **28D.3** `hit_recoil`：8 帧 × fps=12，后仰复位 ✓
- [x] **28D.4** `death_fall`：8 帧 × fps=8，frame 3-8 hold（跪倒） ✓
- [x] **28D.5** 4 个 Action 存为独立数据块，加入 NLA strips ✓
- [x] **28D.6** 保存 `pikeman_animated.blend`

---

## 子阶段 28E：等距渲染验证（05_render_frames.py）

- [x] **28E.1** 渲染参数：EEVEE，256×256，透明背景（RGBA）
- [x] **28E.2** 32 张帧全部渲染完成（row0-3，f01-08）
- [x] **28E.3** Atlas 拼接完成（2048×1024）
- [ ] **28E.4** 视觉对比：3D 渲染 atlas vs Phase 26 线稿 atlas（手动截图对比存档）

---

## 子阶段 28F：GLB 导出（06_export.py）

- [x] **28F.1** 导出 `pikeman_v1.glb`，包含 mesh + armature + 4 animations
- [x] **28F.2** 文件大小：**103.3 KB**（目标 < 500 KB ✓）
- [ ] **28F.3** Godot 导入 `pikeman_v1.glb`，目测加载成功，动画列表正确（4 个）

---

## 子阶段 28G：文档与脚本整理

- [ ] **28G.1** 所有脚本加头部注释（描述步骤、输入、输出）
- [ ] **28G.2** `run_all.sh` 测试：从零开始执行全流程，无报错
- [ ] **28G.3** `design.md` 补充实际面数、骨骼坐标、渲染参数等实测数据
- [ ] **28G.4** `roadmap.md` 新增 Phase 28 条目
- [ ] **28G.5** 截图对比（Phase 26 线稿 atlas vs Phase 28 3D 渲染 atlas）归档到 `docs/phases/phase28/comparison/`

---

## 验证命令

```bash
BLENDER=/Applications/Blender.app/Contents/MacOS/Blender
ROOT=/Users/konyel/agents/ai-native-rts/src/phase1-rts-mvp/assets/characters/3d

# 单步执行
$BLENDER --background --python $ROOT/scripts/01_build_mesh.py
$BLENDER --background --python $ROOT/scripts/02_join_and_clean.py
$BLENDER --background --python $ROOT/scripts/03_rig.py
$BLENDER --background --python $ROOT/scripts/04_pose_and_animate.py
$BLENDER --background --python $ROOT/scripts/05_render_frames.py
$BLENDER --background --python $ROOT/scripts/06_export.py

# 一键全流程
bash $ROOT/scripts/run_all.sh
```

---

## 关键参数速查

| 参数 | 值 | 来源 |
|---|---|---|
| Blender 版本 | 5.1.1 | 本机 |
| 摄像机 rotation | `(60°, 0°, 45°)` | Phase 27 视角 |
| 摄像机类型 | ORTHO | 等距 RTS |
| ortho_scale | 3.0 | 覆盖 1.8m 士兵 |
| 总高 | 1.8 Blender 单位 | Phase 27 线稿 |
| 面数上限 | 600 三角面 | 设计约束 |
| 骨骼数 | 17 | 设计约束 |
| 渲染分辨率 | 256 × 256 | Phase 26 atlas 帧尺寸 |
| 渲染引擎 | EEVEE | 速度优先 |
| 动作帧率 | 12/14/12/8 fps | Phase 26 atlas JSON |

---

_创建: 2026-05-10_
