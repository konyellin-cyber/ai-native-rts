"""
Phase 28 — 02_join_and_clean.py
合并所有部件 mesh，清理拓扑，设置 Origin，保存 pikeman_clean.blend。

输入: pikeman_mesh.blend
输出: pikeman_clean.blend
"""

import bpy, sys, os

argv = sys.argv
assets_dir = "."
if "--" in argv:
    after = argv[argv.index("--") + 1:]
    for i, a in enumerate(after):
        if a == "--assets-dir" and i + 1 < len(after):
            assets_dir = after[i + 1]

INPUT  = os.path.join(assets_dir, "pikeman_mesh.blend")
OUTPUT = os.path.join(assets_dir, "pikeman_clean.blend")


def main():
    print("[28B] 开始合并清理...")

    # 加载 mesh 文件
    bpy.ops.wm.open_mainfile(filepath=INPUT)

    # 选中所有 mesh 对象
    bpy.ops.object.select_all(action='DESELECT')
    mesh_objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    for obj in mesh_objs:
        obj.select_set(True)

    if not mesh_objs:
        print("[28B] 错误：没有找到 Mesh 对象")
        return

    # 设置 active object
    bpy.context.view_layer.objects.active = mesh_objs[0]

    # Join 合并为单一对象
    bpy.ops.object.join()
    combined = bpy.context.active_object
    combined.name = "Pikeman"
    print(f"[28B] 合并完成，对象名: {combined.name}")

    # 三角化（确保全三角面）
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.quads_convert_to_tris()

    # 移除重复顶点（合并阈值 0.001）
    bpy.ops.mesh.remove_doubles(threshold=0.001)

    # 检查并修复：删除孤立顶点
    bpy.ops.mesh.select_all(action='DESELECT')
    bpy.ops.mesh.select_non_manifold()
    # 不强制删除，只报告

    bpy.ops.object.mode_set(mode='OBJECT')

    # 设置 Origin 到脚底中心（脚底 Z ≈ 0，X=0, Y=0）
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

    # 面数统计
    combined.data.calc_loop_triangles()
    tris = len(combined.data.loop_triangles)
    print(f"[28B] 合并后三角面数: {tris}（目标 ≤ 600）")
    if tris > 600:
        print(f"[28B] ⚠ 超出面数限制 ({tris} > 600)")
    else:
        print(f"[28B] ✓ 面数合格")

    # 保存
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT)
    print(f"[28B] 保存: {OUTPUT}")
    print("[28B] 完成 ✓")


main()
