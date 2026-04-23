#!/bin/bash
# 验证 ai-renderer 目录结构：phase1 和 phase05 必须是指向 shared 的符号链接
# 用法：bash tools/check_renderer_links.sh（从项目根目录执行）
# 返回值：0=通过，1=漂移检测到

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SHARED="$ROOT/src/shared/ai-renderer"
PHASE1="$ROOT/src/phase1-rts-mvp/tools/ai-renderer"
PHASE05="$ROOT/src/phase05-rts-prototype/tools/ai-renderer"

ok=1

check_symlink() {
  local path="$1"
  local label="$2"
  if [ -L "$path" ]; then
    echo "✅ $label → $(readlink "$path")"
  elif [ -d "$path" ]; then
    echo "❌ $label is a REAL DIRECTORY (drift detected)"
    ok=0
  else
    echo "⚠️  $label does not exist"
    ok=0
  fi
}

echo ""
echo "════════════════════════════════════════"
echo "  AI Renderer Source Consistency Check"
echo "════════════════════════════════════════"
echo "  Canonical: $SHARED"
echo ""

check_symlink "$PHASE1"  "phase1-rts-mvp/tools/ai-renderer"
check_symlink "$PHASE05" "phase05-rts-prototype/tools/ai-renderer"

echo ""
if [ $ok -eq 1 ]; then
  echo "✅ All phase dirs are symlinks — no drift"
  exit 0
else
  echo "❌ Drift detected — run 18B merge procedure"
  exit 1
fi
