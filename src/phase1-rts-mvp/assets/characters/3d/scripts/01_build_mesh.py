"""
Phase 28 — 01_build_mesh.py
用 bmesh API 程序化生成枪兵各部件体块，输出 pikeman_mesh.blend。

比例参照 Phase 27 线稿（001-spearman-perspective-construction.png）：
  总高   1.80 BU   头 0.38  躯干 0.55  大腿 0.38  小腿+靴 0.49
  肩宽   0.55 BU   长枪 2.40
"""

import bpy, bmesh, math, sys, os

# ── 参数解析 ──────────────────────────────────────────
argv = sys.argv
assets_dir = "."
if "--" in argv:
    after = argv[argv.index("--") + 1:]
    for i, a in enumerate(after):
        if a == "--assets-dir" and i + 1 < len(after):
            assets_dir = after[i + 1]

OUTPUT = os.path.join(assets_dir, "pikeman_mesh.blend")


# ── 工具函数 ──────────────────────────────────────────

def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    for block in list(bpy.data.meshes):
        bpy.data.meshes.remove(block)


def add_box(name, size, location, rotation=(0, 0, 0)):
    """创建一个轴对齐长方体，size=(sx, sy, sz)，location 是中心点。"""
    mesh = bpy.data.meshes.new(name)
    obj  = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    # 按 size 缩放
    sx, sy, sz = size
    for v in bm.verts:
        v.co.x *= sx
        v.co.y *= sy
        v.co.z *= sz
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()

    obj.location = location
    obj.rotation_euler = rotation
    return obj


def add_cylinder(name, radius, depth, segments, location, rotation=(0, 0, 0)):
    """创建一个圆柱，轴朝 Z 方向，然后按 rotation 旋转。"""
    mesh = bpy.data.meshes.new(name)
    obj  = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segments,
        radius1=radius,
        radius2=radius,
        depth=depth,
    )
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()

    obj.location = location
    obj.rotation_euler = rotation
    return obj


def add_cone(name, radius, depth, segments, location, rotation=(0, 0, 0)):
    """创建锥体（矛头）。"""
    mesh = bpy.data.meshes.new(name)
    obj  = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segments,
        radius1=radius,
        radius2=0.001,
        depth=depth,
    )
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()

    obj.location = location
    obj.rotation_euler = rotation
    return obj


def add_uv_sphere(name, radius, segments, rings, location):
    mesh = bpy.data.meshes.new(name)
    obj  = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()

    obj.location = location
    return obj


R = math.radians   # 简写


# ── 建模：各部件 ────────────────────────────────────────

def build_pikeman():
    objs = []

    # ── 头盔（bowl helm）──────────────────────────────
    # 半球 + 下沿帽檐
    helmet_top = add_uv_sphere("helmet_top", radius=0.19, segments=8, rings=5,
                               location=(0, 0, 1.69))
    # 只保留上半球：删除 Z < 1.69 的顶点（Z 以局部坐标计，即 z < 0）
    # 简化：直接用半球配合压扁表达
    helmet_top.scale.z = 0.75
    bpy.context.view_layer.update()

    # 帽檐（薄扁盒）
    brim = add_box("helmet_brim", (0.44, 0.44, 0.04), (0, 0, 1.50))
    objs += [helmet_top, brim]

    # ── 脖子（连接头盔和躯干）────────────────────────
    neck = add_cylinder("neck", radius=0.06, depth=0.10, segments=6,
                        location=(0, 0, 1.43))
    objs.append(neck)

    # ── 躯干（梯形胸甲，上宽下窄）────────────────────
    # 用 box 近似，肩部宽 0.52，腰部宽 0.36，深 0.22，高 0.32
    chest = add_box("chest", (0.52, 0.22, 0.32), (0, 0, 1.20))
    waist = add_box("waist", (0.38, 0.20, 0.23), (0, 0, 0.97))
    objs += [chest, waist]

    # ── 肩部护甲（左右各一，圆球压扁）────────────────
    for side, sx in [("L", -1), ("R", 1)]:
        sp = add_uv_sphere(f"shoulder_{side}", radius=0.12,
                           segments=6, rings=4,
                           location=(sx * 0.28, 0, 1.30))
        sp.scale = (1.0, 0.75, 0.75)
        bpy.context.view_layer.update()
        objs.append(sp)

    # ── 上臂（左右各一）──────────────────────────────
    # 默认 Y 朝上，需要旋转 90° 使轴朝 X
    for side, sx in [("L", -1), ("R", 1)]:
        ua = add_cylinder(f"upper_arm_{side}",
                          radius=0.07, depth=0.25, segments=6,
                          location=(sx * 0.31, 0, 1.13),
                          rotation=(0, R(90), 0))
        objs.append(ua)

    # ── 前臂（左右各一）──────────────────────────────
    for side, sx in [("L", -1), ("R", 1)]:
        fa = add_cylinder(f"forearm_{side}",
                          radius=0.06, depth=0.22, segments=6,
                          location=(sx * 0.31, 0, 0.88),
                          rotation=(0, R(90), 0))
        objs.append(fa)

    # ── 手（握拳体块，左右各一）──────────────────────
    for side, sx in [("L", -1), ("R", 1)]:
        h = add_box(f"hand_{side}", (0.10, 0.10, 0.10),
                    (sx * 0.31, 0, 0.74))
        objs.append(h)

    # ── 腰裙（护甲，box）─────────────────────────────
    skirt = add_box("waist_skirt", (0.36, 0.18, 0.10), (0, 0, 0.84))
    objs.append(skirt)

    # ── 大腿（左右各一）──────────────────────────────
    for side, sx in [("L", -1), ("R", 1)]:
        th = add_cylinder(f"thigh_{side}",
                          radius=0.085, depth=0.34, segments=8,
                          location=(sx * 0.13, 0, 0.63))
        objs.append(th)

    # ── 膝甲（圆球压扁）──────────────────────────────
    for side, sx in [("L", -1), ("R", 1)]:
        kp = add_uv_sphere(f"knee_{side}", radius=0.09,
                           segments=6, rings=4,
                           location=(sx * 0.13, 0, 0.46))
        kp.scale.z = 0.6
        bpy.context.view_layer.update()
        objs.append(kp)

    # ── 小腿（左右各一）──────────────────────────────
    for side, sx in [("L", -1), ("R", 1)]:
        sh = add_cylinder(f"shin_{side}",
                          radius=0.07, depth=0.28, segments=8,
                          location=(sx * 0.13, 0, 0.28))
        objs.append(sh)

    # ── 靴（方盒）────────────────────────────────────
    for side, sx in [("L", -1), ("R", 1)]:
        bt = add_box(f"boot_{side}",
                     (0.14, 0.22, 0.12),
                     (sx * 0.13, 0.04, 0.06))
        objs.append(bt)

    # ── 长枪（spear）─────────────────────────────────
    # 枪身：细圆柱，从右手延伸，斜 30° 朝左前方
    shaft_angle = R(-30)   # 斜向左前方
    spear_len   = 2.20
    spear = add_cylinder("spear_shaft",
                          radius=0.025, depth=spear_len, segments=6,
                          location=(0.05, 0, 0.76),
                          rotation=(R(90), 0, shaft_angle))
    objs.append(spear)

    # 矛头：小锥体
    tip_x = 0.05 + math.sin(shaft_angle) * spear_len * 0.5
    tip_z = 0.76 - math.cos(shaft_angle) * spear_len * 0.5
    tip = add_cone("spear_tip",
                   radius=0.04, depth=0.18, segments=6,
                   location=(tip_x, 0, tip_z),
                   rotation=(R(90), 0, shaft_angle))
    objs.append(tip)

    return objs


# ── 摄像机 ────────────────────────────────────────────

def setup_camera():
    cam_data = bpy.data.cameras.new("IsoCamera")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 3.5   # 充分覆盖 1.8m 士兵 + 长枪

    cam_obj = bpy.data.objects.new("IsoCamera", cam_data)
    bpy.context.collection.objects.link(cam_obj)

    # 真等距 45°：X=54.74°，Z=45°（与 Phase 27 构造线稿一致）
    cam_obj.rotation_euler = (R(54.74), 0, R(45))

    # 对准角色中心（身体中点约 Z=0.9），正交摄像机 location 只影响方向，
    # 沿摄像机 -Z 轴方向距离不重要，关键是 XY 平面上的偏移
    import mathutils
    # 从等距视角看，摄像机需要在角色后上方
    cam_obj.location = (5.0, -5.0, 6.8)

    bpy.context.scene.camera = cam_obj
    return cam_obj


# ── 灯光 ──────────────────────────────────────────────

def setup_lights():
    # 主光源
    sun_data = bpy.data.lights.new("Sun", 'SUN')
    sun_data.energy = 3.0
    sun_obj = bpy.data.objects.new("Sun", sun_data)
    bpy.context.collection.objects.link(sun_obj)
    sun_obj.rotation_euler = (R(45), 0, R(45))

    # 补光
    fill_data = bpy.data.lights.new("Fill", 'SUN')
    fill_data.energy = 1.0
    fill_obj = bpy.data.objects.new("Fill", fill_data)
    bpy.context.collection.objects.link(fill_obj)
    fill_obj.rotation_euler = (R(30), 0, R(-135))


# ── 渲染验证（等距静帧）────────────────────────────────

def render_preview(output_path):
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = output_path

    bpy.ops.render.render(write_still=True)
    print(f"[28A] 预览渲染完成: {output_path}")


# ── 面数统计 ──────────────────────────────────────────

def count_tris():
    total = 0
    for obj in bpy.context.scene.objects:
        if obj.type == 'MESH':
            mesh = obj.data
            mesh.calc_loop_triangles()
            total += len(mesh.loop_triangles)
    return total


# ── 主流程 ────────────────────────────────────────────

def main():
    print("[28A] 开始建模...")
    clear_scene()

    objs = build_pikeman()
    setup_camera()
    setup_lights()

    bpy.context.view_layer.update()

    tris = count_tris()
    print(f"[28A] 三角面总数: {tris}（目标 ≤ 600）")
    if tris > 600:
        print(f"[28A] ⚠ 超出面数限制！({tris} > 600)")
    else:
        print(f"[28A] ✓ 面数合格")

    # 保存 .blend
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT)
    print(f"[28A] 保存: {OUTPUT}")

    # 渲染预览
    render_dir = os.path.join(assets_dir, "renders")
    os.makedirs(render_dir, exist_ok=True)
    render_preview(os.path.join(render_dir, "28A_preview_iso.png"))

    print("[28A] 完成 ✓")


main()
