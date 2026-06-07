"""
Phase 28 — 03_rig.py
为合并后的枪兵 mesh 创建 17 骨骼 Armature，并以脚本方式赋值 Vertex Group weights。

骨骼结构（design.md D3）:
  root → hips
    ├─ spine → chest → neck → head
    │              ├─ shoulder_L → upper_arm_L → forearm_L → hand_L
    │              └─ shoulder_R → upper_arm_R → forearm_R → hand_R
    │                                                          └─ spear
    ├─ thigh_L → shin_L → foot_L
    └─ thigh_R → shin_R → foot_R

输入: pikeman_clean.blend
输出: pikeman_rigged.blend
"""

import bpy, mathutils, math, sys, os

argv = sys.argv
assets_dir = "."
if "--" in argv:
    after = argv[argv.index("--") + 1:]
    for i, a in enumerate(after):
        if a == "--assets-dir" and i + 1 < len(after):
            assets_dir = after[i + 1]

INPUT  = os.path.join(assets_dir, "pikeman_clean.blend")
OUTPUT = os.path.join(assets_dir, "pikeman_rigged.blend")

R = math.radians

# ── 骨骼定义（head, tail 都是世界坐标，Z-up）─────────────────
# head = 骨骼根部，tail = 骨骼尖端
BONES = [
    # name              head (x,y,z)          tail (x,y,z)          parent
    ("root",            (0,   0,   0.0),       (0,   0,   0.10),     None),
    ("hips",            (0,   0,   0.85),      (0,   0,   0.96),     "root"),
    ("spine",           (0,   0,   0.96),      (0,   0,   1.18),     "hips"),
    ("chest",           (0,   0,   1.18),      (0,   0,   1.36),     "spine"),
    ("neck",            (0,   0,   1.36),      (0,   0,   1.48),     "chest"),
    ("head",            (0,   0,   1.48),      (0,   0,   1.86),     "neck"),

    ("shoulder_L",      (-0.20, 0, 1.30),      (-0.28, 0, 1.28),     "chest"),
    ("upper_arm_L",     (-0.28, 0, 1.28),      (-0.28, 0, 1.03),     "shoulder_L"),
    ("forearm_L",       (-0.28, 0, 1.03),      (-0.28, 0, 0.79),     "upper_arm_L"),
    ("hand_L",          (-0.28, 0, 0.79),      (-0.28, 0, 0.69),     "forearm_L"),

    ("shoulder_R",      ( 0.20, 0, 1.30),      ( 0.28, 0, 1.28),     "chest"),
    ("upper_arm_R",     ( 0.28, 0, 1.28),      ( 0.28, 0, 1.03),     "shoulder_R"),
    ("forearm_R",       ( 0.28, 0, 1.03),      ( 0.28, 0, 0.79),     "upper_arm_R"),
    ("hand_R",          ( 0.28, 0, 0.79),      ( 0.28, 0, 0.69),     "forearm_R"),
    ("spear",           ( 0.28, 0, 0.74),      (-0.50, 0, 0.30),     "hand_R"),

    ("thigh_L",         (-0.13, 0, 0.85),      (-0.13, 0, 0.51),     "hips"),
    ("shin_L",          (-0.13, 0, 0.51),      (-0.13, 0, 0.14),     "thigh_L"),
    ("foot_L",          (-0.13, 0, 0.14),      (-0.13, 0.15, 0.04),  "shin_L"),

    ("thigh_R",         ( 0.13, 0, 0.85),      ( 0.13, 0, 0.51),     "hips"),
    ("shin_R",          ( 0.13, 0, 0.51),      ( 0.13, 0, 0.14),     "thigh_R"),
    ("foot_R",          ( 0.13, 0, 0.14),      ( 0.13, 0.15, 0.04),  "shin_R"),
]

# ── Vertex Group 赋值规则 ─────────────────────────────────────
# 按顶点 Z 坐标和 X 坐标范围分配骨骼权重
# (bone_name, z_min, z_max, x_min, x_max, weight)
VG_RULES = [
    # 头部 (Z > 1.46)
    ("head",        1.46, 2.0,  -1.0,  1.0, 1.0),
    # 脖子
    ("neck",        1.36, 1.46, -0.15, 0.15, 1.0),
    # 胸部
    ("chest",       1.10, 1.36, -0.35, 0.35, 1.0),
    # 腰部
    ("spine",       0.95, 1.10, -0.30, 0.30, 1.0),
    # hips
    ("hips",        0.80, 0.95, -0.30, 0.30, 1.0),

    # 左肩（X < -0.18, Z > 1.22）
    ("shoulder_L",  1.22, 1.36, -1.0, -0.18, 1.0),
    # 左上臂
    ("upper_arm_L", 1.00, 1.22, -1.0, -0.18, 1.0),
    # 左前臂
    ("forearm_L",   0.77, 1.00, -1.0, -0.18, 1.0),
    # 左手
    ("hand_L",      0.65, 0.77, -1.0, -0.18, 1.0),

    # 右肩（X > 0.18, Z > 1.22）
    ("shoulder_R",  1.22, 1.36,  0.18, 1.0, 1.0),
    # 右上臂
    ("upper_arm_R", 1.00, 1.22,  0.18, 1.0, 1.0),
    # 右前臂
    ("forearm_R",   0.77, 1.00,  0.18, 1.0, 1.0),
    # 右手
    ("hand_R",      0.65, 0.77,  0.18, 1.0, 1.0),

    # 左大腿（X < 0）
    ("thigh_L",     0.50, 0.85, -1.0, 0.0, 1.0),
    # 左小腿
    ("shin_L",      0.12, 0.50, -1.0, 0.0, 1.0),
    # 左脚
    ("foot_L",      0.0,  0.12, -1.0, 0.0, 1.0),

    # 右大腿（X > 0）
    ("thigh_R",     0.50, 0.85,  0.0, 1.0, 1.0),
    # 右小腿
    ("shin_R",      0.12, 0.50,  0.0, 1.0, 1.0),
    # 右脚
    ("foot_R",      0.0,  0.12,  0.0, 1.0, 1.0),

    # 长枪（Z 范围广，在 X < 0.35 且不在人体内的部分，简单用 Y > 0 来区分枪杆）
    # 通过枪对象命名方式赋值，这里用 spear 骨骼
    ("spear",       0.0,  2.0,  -3.0, 3.0, 1.0),
]


def main():
    print("[28C] 开始骨骼绑定...")

    bpy.ops.wm.open_mainfile(filepath=INPUT)

    # 找到 mesh 对象
    mesh_obj = next((o for o in bpy.context.scene.objects if o.type == 'MESH'), None)
    if mesh_obj is None:
        print("[28C] 错误：找不到 Mesh 对象")
        return
    print(f"[28C] 绑定对象: {mesh_obj.name}")

    # ── 创建 Armature ────────────────────────────────────
    arm_data = bpy.data.armatures.new("PikemanArmature")
    arm_obj  = bpy.data.objects.new("PikemanArmature", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj

    # 进入 Edit 模式添加骨骼
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm_data.edit_bones

    bone_map = {}
    for name, head, tail, parent_name in BONES:
        bone = eb.new(name)
        bone.head = mathutils.Vector(head)
        bone.tail = mathutils.Vector(tail)
        bone_map[name] = bone

    # 建立父子关系
    for name, head, tail, parent_name in BONES:
        if parent_name is not None:
            bone_map[name].parent = bone_map[parent_name]
            bone_map[name].use_connect = False

    bpy.ops.object.mode_set(mode='OBJECT')
    print(f"[28C] 创建骨骼: {len(BONES)} 根")

    # ── Vertex Groups + Armature 修改器 ──────────────────
    bpy.context.view_layer.objects.active = mesh_obj

    # 先删除旧的 vertex groups
    mesh_obj.vertex_groups.clear()

    # 为每个骨骼创建 vertex group
    for name, _h, _t, _p in BONES:
        mesh_obj.vertex_groups.new(name=name)

    # 按规则赋 weight（先全清 spear，再覆盖）
    mesh = mesh_obj.data
    # 收集每个顶点位置
    for vert in mesh.vertices:
        x, y, z = vert.co.x, vert.co.y, vert.co.z

        assigned = False
        for bone_name, z_min, z_max, x_min, x_max, w in VG_RULES:
            if z_min <= z <= z_max and x_min <= x <= x_max:
                vg = mesh_obj.vertex_groups.get(bone_name)
                if vg:
                    vg.add([vert.index], w, 'REPLACE')
                    assigned = True
                    break  # 每个顶点只分配给一个骨骼（简化）

        if not assigned:
            # fallback: 分配给 hips
            vg = mesh_obj.vertex_groups.get("hips")
            if vg:
                vg.add([vert.index], 1.0, 'REPLACE')

    print("[28C] Vertex Group 赋值完成")

    # ── 添加 Armature 修改器 ─────────────────────────────
    mod = mesh_obj.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm_obj

    # ── Parent Mesh 到 Armature ──────────────────────────
    mesh_obj.parent = arm_obj

    # ── 保存 ─────────────────────────────────────────────
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT)
    print(f"[28C] 保存: {OUTPUT}")
    print("[28C] 完成 ✓")


main()
