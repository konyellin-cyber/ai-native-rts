#!/bin/bash
# 并行运行所有 headless 场景测试
# 场景列表来自 scene_registry.json（window_mode=false 条目），每条目独立进程
# 用法：bash tests/run_scenarios_parallel.sh

GODOT=${GODOT:-godot}
PROJECT_PATH="$(cd "$(dirname "$0")/.." && pwd)"
REGISTRY="$PROJECT_PATH/tests/scene_registry.json"
TMPDIR_BASE="$PROJECT_PATH/tests/.tmp_parallel"

# 清理旧临时目录
rm -rf "$TMPDIR_BASE"
mkdir -p "$TMPDIR_BASE"

# 从 scene_registry.json 提取所有 window_mode=false 的场景路径
SCENES=$(python3 - <<'EOF'
import json, sys
with open(sys.argv[1]) as f:
    registry = json.load(f)
scenes = [e["scene"] for e in registry if not e.get("window_mode", False)]
print("\n".join(scenes))
EOF
"$REGISTRY")

if [ -z "$SCENES" ]; then
  echo "❌ No headless scenes found in $REGISTRY"
  exit 1
fi

readarray -t SCENE_LIST <<< "$SCENES"

echo ""
echo "════════════════════════════════════════"
echo "  PARALLEL HEADLESS REGRESSION"
echo "  Source: tests/scene_registry.json"
echo "  Scenes: ${#SCENE_LIST[@]} | Workers: ${#SCENE_LIST[@]}"
echo "════════════════════════════════════════"
echo ""

# 并行启动每个场景
declare -A PIDS
declare -A LOG_FILES

for scene in "${SCENE_LIST[@]}"; do
  # 用场景路径的最后一段作为名字（去掉 res:// 前缀和 .tscn 后缀）
  name=$(basename "$scene" .tscn)
  log_file="$TMPDIR_BASE/log_${name}.txt"
  LOG_FILES[$name]=$log_file

  echo "▶ Starting: $name  ($scene)"
  $GODOT --headless --path "$PROJECT_PATH" --scene "$scene" >"$log_file" 2>&1 &
  PIDS[$name]=$!
done

echo ""
echo "⏳ Waiting for all scenes to complete..."
echo ""

pass_count=0
fail_count=0
results=()

for name in "${!PIDS[@]}"; do
  pid=${PIDS[$name]}
  wait "$pid"
  exit_code=$?
  log_file=${LOG_FILES[$name]}

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "▶ Scene: $name"
  grep -E "\[PASS\]|\[FAIL\]|\[RESULT\]" "$log_file" | tail -5

  if [ $exit_code -eq 0 ] && grep -q "\[RESULT\].*0 failed\|All.*PASS\|PASS" "$log_file"; then
    echo "✅ PASS: $name"
    results+=("✅ $name")
    ((pass_count++))
  elif grep -q "\[RESULT\].*0 failed" "$log_file"; then
    echo "✅ PASS: $name"
    results+=("✅ $name")
    ((pass_count++))
  else
    echo "❌ FAIL: $name (exit=$exit_code)"
    results+=("❌ $name")
    ((fail_count++))
  fi
done

# 清理临时目录
rm -rf "$TMPDIR_BASE"

echo ""
echo "════════════════════════════════════════"
echo "  SUMMARY"
echo "════════════════════════════════════════"
for r in "${results[@]}"; do
  echo "  $r"
done
echo "────────────────────────────────────────"
echo "  Total: $((pass_count + fail_count)) | Pass: $pass_count | Fail: $fail_count"
echo "════════════════════════════════════════"

[ $fail_count -eq 0 ] && exit 0 || exit 1
