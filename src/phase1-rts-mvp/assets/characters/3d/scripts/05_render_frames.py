"""
Phase 28 — 05_render_frames.py
渲染 4 组动作各 8 帧，共 32 张 256x256 PNG，
然后拼接为 2048x1024 的 atlas 图。

输入: pikeman_animated.blend
输出: renders/row{0-3}_f{01-08}.png + pikeman_3d_atlas_2048x1024.png
"""

import bpy, sys, os, math

argv = sys.argv
assets_dir = "."
if "--" in argv:
    after = argv[argv.index("--") + 1:]
    for i, a in enumerate(after):
        if a == "--assets-dir" and i + 1 < len(after):
            assets_dir = after[i + 1]

INPUT       = os.path.join(assets_dir, "pikeman_animated.blend")
RENDER_DIR  = os.path.join(assets_dir, "renders")
ATLAS_PATH  = os.path.join(assets_dir, "pikeman_3d_atlas_2048x1024.png")

ACTIONS = ["charge_run", "spear_thrust", "hit_recoil", "death_fall"]
FRAME_COUNT = 8
FRAME_W, FRAME_H = 256, 256


def setup_render():
    scene = bpy.context.scene
    scene.render.engine       = 'BLENDER_EEVEE'
    scene.render.resolution_x = FRAME_W
    scene.render.resolution_y = FRAME_H
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode  = 'RGBA'


def render_action_frames(arm_obj, action_name, row_idx):
    """渲染某个 action 的 8 帧，存为 row{row}_f{01-08}.png。"""
    action = bpy.data.actions.get(action_name)
    if action is None:
        print(f"[28E] 警告：找不到 Action '{action_name}'，跳过")
        return []

    arm_obj.animation_data.action = action
    scene = bpy.context.scene
    paths = []

    for f in range(1, FRAME_COUNT + 1):
        scene.frame_set(f)
        filename = f"row{row_idx}_f{f:02d}.png"
        filepath = os.path.join(RENDER_DIR, filename)
        scene.render.filepath = filepath
        bpy.ops.render.render(write_still=True)
        paths.append(filepath)
        print(f"[28E] 渲染: {filename}")

    return paths


def stitch_atlas(frame_paths_by_row):
    """用 Blender 内置 Image API 拼接 32 帧成 2048x1024 atlas。"""
    import numpy as np

    cols, rows = 8, 4
    atlas_w, atlas_h = cols * FRAME_W, rows * FRAME_H
    atlas = np.zeros((atlas_h, atlas_w, 4), dtype=np.float32)

    for row_idx, paths in enumerate(frame_paths_by_row):
        for col_idx, path in enumerate(paths):
            if not os.path.exists(path):
                continue
            img = bpy.data.images.load(path)
            img.pixels  # 触发加载
            pixels = list(img.pixels)  # RGBA flat
            arr = np.array(pixels, dtype=np.float32).reshape((FRAME_H, FRAME_W, 4))
            # Blender 图像 Y 轴从下往上，需要翻转
            arr = arr[::-1]
            y0 = row_idx * FRAME_H
            x0 = col_idx * FRAME_W
            atlas[y0:y0 + FRAME_H, x0:x0 + FRAME_W] = arr
            bpy.data.images.remove(img)

    # 翻转回 Blender 坐标（底部在下）
    atlas = atlas[::-1]

    # 创建 Blender Image 并保存
    atlas_img = bpy.data.images.new("pikeman_3d_atlas",
                                    width=atlas_w, height=atlas_h,
                                    alpha=True)
    atlas_img.pixels = atlas.flatten().tolist()
    atlas_img.file_format = 'PNG'
    atlas_img.filepath_raw = ATLAS_PATH
    atlas_img.save()
    print(f"[28E] Atlas 拼接完成: {ATLAS_PATH}")


def main():
    print("[28E] 开始渲染...")
    os.makedirs(RENDER_DIR, exist_ok=True)

    bpy.ops.wm.open_mainfile(filepath=INPUT)

    arm_obj = next((o for o in bpy.context.scene.objects if o.type == 'ARMATURE'), None)
    if arm_obj is None:
        print("[28E] 错误：找不到 Armature")
        return

    setup_render()

    frame_paths_by_row = []
    for row_idx, action_name in enumerate(ACTIONS):
        paths = render_action_frames(arm_obj, action_name, row_idx)
        frame_paths_by_row.append(paths)

    # 拼 atlas
    try:
        stitch_atlas(frame_paths_by_row)
    except ImportError:
        print("[28E] numpy 不可用，跳过 atlas 拼接（帧文件已分别保存）")

    print("[28E] 完成 ✓")


main()
