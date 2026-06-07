#!/usr/bin/env bash
# Phase 28 — Blender 枪兵低多边形建模全流程脚本
# 用法: bash scripts/run_all.sh
# 要求: Blender 5.1+ 安装在 /Applications/Blender.app

set -e

BLENDER=/Applications/Blender.app/Contents/MacOS/Blender
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
ASSETS_DIR="$(dirname "$SCRIPTS_DIR")"

echo "=== Phase 28 Blender Pipeline ==="
echo "Blender: $BLENDER"
echo "Scripts: $SCRIPTS_DIR"
echo "Assets:  $ASSETS_DIR"
echo ""

run_step() {
  local step="$1"
  local script="$2"
  echo "--- $step ---"
  $BLENDER --background --python "$SCRIPTS_DIR/$script" -- --assets-dir "$ASSETS_DIR"
  echo "✓ $step 完成"
  echo ""
}

run_step "28A 体块建模"        "01_build_mesh.py"
run_step "28B 合并清理"        "02_join_and_clean.py"
run_step "28C 骨骼绑定"        "03_rig.py"
run_step "28D 动作制作"        "04_pose_and_animate.py"
run_step "28E 等距渲染验证"    "05_render_frames.py"
run_step "28F GLB 导出"        "06_export.py"

echo "=== 全流程完成 ==="
echo "交付物:"
echo "  $ASSETS_DIR/pikeman_animated.blend"
echo "  $ASSETS_DIR/pikeman_v1.glb"
echo "  $ASSETS_DIR/renders/ (32 帧 PNG)"
