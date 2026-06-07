"""
Phase 28 — 04_pose_and_animate.py
为绑骨后的枪兵创建 4 个 Action（charge_run, spear_thrust, hit_recoil, death_fall）。
每个 Action 8 帧，帧率对齐 Phase 26 atlas JSON 定义。

输入: pikeman_rigged.blend
输出: pikeman_animated.blend
"""

import bpy, math, sys, os

argv = sys.argv
assets_dir = "."
if "--" in argv:
    after = argv[argv.index("--") + 1:]
    for i, a in enumerate(after):
        if a == "--assets-dir" and i + 1 < len(after):
            assets_dir = after[i + 1]

INPUT  = os.path.join(assets_dir, "pikeman_rigged.blend")
OUTPUT = os.path.join(assets_dir, "pikeman_animated.blend")

R = math.radians


def get_armature():
    for obj in bpy.context.scene.objects:
        if obj.type == 'ARMATURE':
            return obj
    return None


def set_pose_bone_rotation(arm_obj, bone_name, euler_xyz):
    """设置 pose bone 的欧拉旋转。"""
    bone = arm_obj.pose.bones.get(bone_name)
    if bone is None:
        return
    bone.rotation_mode = 'XYZ'
    bone.rotation_euler = euler_xyz


def reset_pose(arm_obj):
    """重置所有 pose bone 到零旋转。"""
    for bone in arm_obj.pose.bones:
        bone.rotation_mode = 'XYZ'
        bone.rotation_euler = (0, 0, 0)
        bone.location = (0, 0, 0)


def insert_keyframe(arm_obj, frame):
    """为所有 pose bone 插入关键帧。"""
    bpy.context.scene.frame_set(frame)
    for bone in arm_obj.pose.bones:
        bone.keyframe_insert(data_path="rotation_euler", frame=frame)
        bone.keyframe_insert(data_path="location", frame=frame)


def create_action(arm_obj, action_name):
    """创建或清空一个 Action，并绑定到 armature。"""
    action = bpy.data.actions.new(name=action_name)
    arm_obj.animation_data_create()
    arm_obj.animation_data.action = action
    return action


# ── 4 个动作定义 ──────────────────────────────────────────────

def make_charge_run(arm_obj):
    """charge_run：跑步冲锋，8 帧循环，fps=12。
    参照 atlas row0：两腿交替跨步，枪平举前倾。
    """
    create_action(arm_obj, "charge_run")
    bpy.context.scene.render.fps = 12

    poses = {
        # frame: {bone: (rx, ry, rz) in degrees}
        1: {
            "hips":       (0, 0, 0),
            "thigh_L":    (-20, 0, 0),   # 左腿后摆
            "shin_L":     ( 15, 0, 0),   # 左膝弯曲
            "thigh_R":    ( 25, 0, 0),   # 右腿前摆
            "shin_R":     (-10, 0, 0),
            "upper_arm_L": ( 20, 0, 0),  # 左臂前摆（与右腿同步）
            "forearm_L":  (-15, 0, 0),
            "upper_arm_R": (-15, 0, 0),  # 右臂后摆
            "spine":      ( 10, 0, 0),   # 身体前倾
        },
        3: {
            "hips":       (0, 0, 0),
            "thigh_L":    ( 10, 0, 0),   # 左腿中间过渡
            "shin_L":     (  5, 0, 0),
            "thigh_R":    (  5, 0, 0),
            "shin_R":     ( -5, 0, 0),
            "upper_arm_L": (  5, 0, 0),
            "upper_arm_R": ( -5, 0, 0),
            "spine":      (  8, 0, 0),
        },
        5: {                              # 与 frame1 镜像（左右互换）
            "hips":       (0, 0, 0),
            "thigh_L":    ( 25, 0, 0),
            "shin_L":     (-10, 0, 0),
            "thigh_R":    (-20, 0, 0),
            "shin_R":     ( 15, 0, 0),
            "upper_arm_L": (-15, 0, 0),
            "upper_arm_R": ( 20, 0, 0),
            "forearm_R":  (-15, 0, 0),
            "spine":      ( 10, 0, 0),
        },
        7: {                              # 回到中间
            "hips":       (0, 0, 0),
            "thigh_L":    ( 5, 0, 0),
            "shin_L":     (-5, 0, 0),
            "thigh_R":    (10, 0, 0),
            "shin_R":     ( 5, 0, 0),
            "upper_arm_L": (-5, 0, 0),
            "upper_arm_R": ( 5, 0, 0),
            "spine":      ( 8, 0, 0),
        },
    }

    for frame, bone_rots in poses.items():
        reset_pose(arm_obj)
        for bone, rot in bone_rots.items():
            set_pose_bone_rotation(arm_obj, bone, (R(rot[0]), R(rot[1]), R(rot[2])))
        insert_keyframe(arm_obj, frame)

    print("[28D] charge_run 动作完成")


def make_spear_thrust(arm_obj):
    """spear_thrust：刺枪动作，8 帧，fps=14，impact 在 frame 4-5。
    参照 atlas row1：蓄力后引 → 前刺伸展 → 收枪。
    """
    create_action(arm_obj, "spear_thrust")
    bpy.context.scene.render.fps = 14

    poses = {
        1: {   # 蓄力，枪后引
            "spine":      (-5, 0, 5),
            "upper_arm_R": (-30, 0, 0),
            "forearm_R":  ( 15, 0, 0),
            "upper_arm_L": ( 20, 0, 0),
            "forearm_L":  (-10, 0, 0),
            "thigh_L":    (-15, 0, 0),
            "thigh_R":    ( 10, 0, 0),
        },
        2: {   # 继续蓄力
            "spine":      (-8, 0, 5),
            "upper_arm_R": (-35, 0, 0),
            "forearm_R":  ( 20, 0, 0),
        },
        3: {   # 开始前刺
            "spine":      ( 5, 0, -3),
            "upper_arm_R": (-10, 0, 0),
            "forearm_R":  (  5, 0, 0),
            "thigh_L":    (-20, 0, 0),
            "thigh_R":    ( 20, 0, 0),
        },
        4: {   # impact — 枪尖最远点
            "spine":      ( 15, 0, -5),
            "upper_arm_R": ( 20, 0, 0),
            "forearm_R":  (-10, 0, 0),
            "upper_arm_L": (-20, 0, 0),
            "thigh_L":    (-25, 0, 0),
            "thigh_R":    ( 25, 0, 0),
            "shin_R":     (-15, 0, 0),
        },
        5: {   # impact 保持（稍微维持最远点）
            "spine":      ( 14, 0, -5),
            "upper_arm_R": ( 18, 0, 0),
            "thigh_L":    (-25, 0, 0),
            "thigh_R":    ( 24, 0, 0),
        },
        6: {   # 开始收枪
            "spine":      (  8, 0, -2),
            "upper_arm_R": (  5, 0, 0),
            "forearm_R":  (  0, 0, 0),
        },
        8: {   # 回到基础姿态
            "spine":      (  0, 0, 0),
            "upper_arm_R": (-15, 0, 0),
            "thigh_L":    (-10, 0, 0),
            "thigh_R":    ( 10, 0, 0),
        },
    }

    for frame, bone_rots in poses.items():
        reset_pose(arm_obj)
        for bone, rot in bone_rots.items():
            set_pose_bone_rotation(arm_obj, bone, (R(rot[0]), R(rot[1]), R(rot[2])))
        insert_keyframe(arm_obj, frame)

    print("[28D] spear_thrust 动作完成")


def make_hit_recoil(arm_obj):
    """hit_recoil：受击后仰，8 帧，fps=12。
    参照 atlas row2：受击躯干后仰，臂膀抬起。
    """
    create_action(arm_obj, "hit_recoil")
    bpy.context.scene.render.fps = 12

    poses = {
        1: {   # 受击瞬间
            "spine":      (-15, 0, 8),
            "chest":      (-10, 0, 5),
            "upper_arm_L": ( 30, 0, 0),
            "upper_arm_R": ( 20, 0, 0),
            "forearm_L":  (-20, 0, 0),
            "thigh_L":    ( 10, 0, 0),
            "thigh_R":    (-10, 0, 0),
        },
        2: {   # 最大后仰
            "spine":      (-25, 0, 10),
            "chest":      (-15, 0,  5),
            "upper_arm_L": ( 45, 0,  0),
            "upper_arm_R": ( 30, 0,  0),
            "forearm_L":  (-30, 0,  0),
            "thigh_L":    ( 15, 0,  0),
            "thigh_R":    (-10, 0,  0),
        },
        3: {   # 最大后仰保持
            "spine":      (-25, 0, 10),
            "chest":      (-14, 0,  5),
            "upper_arm_L": ( 43, 0,  0),
            "upper_arm_R": ( 28, 0,  0),
        },
        5: {   # 缓慢复位中
            "spine":      (-15, 0,  5),
            "upper_arm_L": ( 25, 0,  0),
            "upper_arm_R": ( 15, 0,  0),
        },
        7: {   # 接近恢复
            "spine":      ( -5, 0,  2),
            "upper_arm_L": ( 10, 0,  0),
            "upper_arm_R": (  5, 0,  0),
        },
        8: {   # 复位完成
            "spine":      (  0, 0,  0),
            "upper_arm_L": (  0, 0,  0),
            "upper_arm_R": (-10, 0,  0),
        },
    }

    for frame, bone_rots in poses.items():
        reset_pose(arm_obj)
        for bone, rot in bone_rots.items():
            set_pose_bone_rotation(arm_obj, bone, (R(rot[0]), R(rot[1]), R(rot[2])))
        insert_keyframe(arm_obj, frame)

    print("[28D] hit_recoil 动作完成")


def make_death_fall(arm_obj):
    """death_fall：倒地死亡，8 帧，fps=8，frame 3-8 hold（保持倒地）。
    参照 atlas row3：膝盖弯曲下跪 → 前倾倒地。
    """
    create_action(arm_obj, "death_fall")
    bpy.context.scene.render.fps = 8

    poses = {
        1: {   # 受击趔趄，膝盖稍弯
            "spine":      (-10, 0,  5),
            "thigh_L":    (  5, 0,  0),
            "thigh_R":    ( 10, 0,  0),
            "shin_L":     (  5, 0,  0),
            "shin_R":     ( 20, 0,  0),
        },
        2: {   # 膝盖开始大幅弯曲
            "spine":      (-20, 0, 10),
            "thigh_L":    ( 20, 0,  0),
            "thigh_R":    ( 30, 0,  0),
            "shin_L":     ( 25, 0,  0),
            "shin_R":     ( 40, 0,  0),
            "upper_arm_L": ( 20, 0,  0),
            "upper_arm_R": ( 15, 0,  0),
        },
        3: {   # 跪倒，身体大幅前倾（hold 开始）
            "hips":       (0, 0, 0),
            "spine":      (-35, 0, 15),
            "chest":      (-20, 0,  8),
            "thigh_L":    ( 60, 0,  0),
            "thigh_R":    ( 70, 0,  0),
            "shin_L":     ( 60, 0,  0),
            "shin_R":     ( 80, 0,  0),
            "upper_arm_L": ( 40, 0, 10),
            "upper_arm_R": ( 30, 0, -10),
            "forearm_L":  (-40, 0,  0),
        },
        # frame 3-8: hold（保持同一姿态）
        8: {   # 与 frame 3 完全相同（hold）
            "hips":       (0, 0, 0),
            "spine":      (-35, 0, 15),
            "chest":      (-20, 0,  8),
            "thigh_L":    ( 60, 0,  0),
            "thigh_R":    ( 70, 0,  0),
            "shin_L":     ( 60, 0,  0),
            "shin_R":     ( 80, 0,  0),
            "upper_arm_L": ( 40, 0, 10),
            "upper_arm_R": ( 30, 0, -10),
            "forearm_L":  (-40, 0,  0),
        },
    }

    for frame, bone_rots in poses.items():
        reset_pose(arm_obj)
        for bone, rot in bone_rots.items():
            set_pose_bone_rotation(arm_obj, bone, (R(rot[0]), R(rot[1]), R(rot[2])))
        insert_keyframe(arm_obj, frame)

    print("[28D] death_fall 动作完成")


def main():
    print("[28D] 开始制作动作...")

    bpy.ops.wm.open_mainfile(filepath=INPUT)

    arm_obj = get_armature()
    if arm_obj is None:
        print("[28D] 错误：找不到 Armature")
        return

    # 激活 armature
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode='POSE')

    # 制作 4 个动作
    make_charge_run(arm_obj)
    make_spear_thrust(arm_obj)
    make_hit_recoil(arm_obj)
    make_death_fall(arm_obj)

    bpy.ops.object.mode_set(mode='OBJECT')

    # 把所有 action 加入 NLA
    arm_obj.animation_data_create()
    nla = arm_obj.animation_data.nla_tracks
    start = 1
    for action in bpy.data.actions:
        track = nla.new()
        track.name = action.name
        strip = track.strips.new(action.name, start, action)
        start += 10   # 间隔 10 帧

    # 保存
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT)
    print(f"[28D] 保存: {OUTPUT}")
    print(f"[28D] Actions: {[a.name for a in bpy.data.actions]}")
    print("[28D] 完成 ✓")


main()
