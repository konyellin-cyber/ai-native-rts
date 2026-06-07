"""
Phase 28 — 06_export.py
导出 pikeman_animated.blend 为 pikeman_v1.glb。

输入: pikeman_animated.blend
输出: pikeman_v1.glb
"""

import bpy, sys, os

argv = sys.argv
assets_dir = "."
if "--" in argv:
    after = argv[argv.index("--") + 1:]
    for i, a in enumerate(after):
        if a == "--assets-dir" and i + 1 < len(after):
            assets_dir = after[i + 1]

INPUT  = os.path.join(assets_dir, "pikeman_animated.blend")
OUTPUT = os.path.join(assets_dir, "pikeman_v1.glb")


def main():
    print("[28F] 开始 GLB 导出...")

    bpy.ops.wm.open_mainfile(filepath=INPUT)

    # 确保所有对象可见
    bpy.ops.object.select_all(action='SELECT')

    # 导出（Blender 5.x 用 export_scene.gltf）
    bpy.ops.export_scene.gltf(
        filepath=OUTPUT,
        export_format='GLB',
        export_animations=True,
        export_skins=True,
        export_morph=False,
        export_cameras=False,
        export_lights=False,
        export_apply=True,          # 应用修改器
    )

    size_kb = os.path.getsize(OUTPUT) / 1024
    print(f"[28F] 导出完成: {OUTPUT}")
    print(f"[28F] 文件大小: {size_kb:.1f} KB（目标 < 500 KB）")
    if size_kb < 500:
        print("[28F] ✓ 文件大小合格")
    else:
        print(f"[28F] ⚠ 文件偏大 ({size_kb:.1f} KB)")

    print("[28F] 完成 ✓")


main()
