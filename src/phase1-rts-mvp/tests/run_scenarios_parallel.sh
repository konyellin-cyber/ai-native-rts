#!/bin/bash
# 并行运行所有场景化测试，汇总结果
# 用法：bash tests/run_scenarios_parallel.sh
# 原理：每个场景写临时 config 后并行启动 Godot，最后等待全部完成
# 为什么并行：各场景断言独立，无共享状态，天然适合并发

GODOT=${GODOT:-godot}
PROJECT_PATH="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$PROJECT_PATH/config.json"
SCENARIOS_DIR="$PROJECT_PATH/tests/scenarios"
TMPDIR_BASE="$PROJECT_PATH/tests/.tmp_parallel"

# 清理旧的临时目录
rm -rf "$TMPDIR_BASE"
mkdir -p "$TMPDIR_BASE"

# 场景列表：name:scenario_file
SCENARIOS=(
  "economy:$SCENARIOS_DIR/economy.json"
  "combat:$SCENARIOS_DIR/combat.json"
  "interaction:$SCENARIOS_DIR/interaction.json"
)

# 为每个场景创建独立 config 副本，避免并发写冲突
prepare_config() {
  local name="$1"
  local scenario_file="$2"
  local tmp_config="$TMPDIR_BASE/config_${name}.json"

  python3 -c "
import json
with open('$CONFIG') as f: d = json.load(f)
d['scenario_file'] = '$scenario_file'
with open('$tmp_config', 'w') as f: json.dump(d, f, indent=2)
"
  echo "$tmp_config"
}

# 启动单个场景（后台），输出写到临时文件
run_scenario_bg() {
  local name="$1"
  local scenario_file="$2"
  local tmp_config
  tmp_config=$(prepare_config "$name" "$scenario_file")
  local log_file="$TMPDIR_BASE/log_${name}.txt"

  # --path 指定项目目录，--config-file 在 Godot 4.x 不直接支持
  # 改用：先 cp 为临时目录下的 config，再 --path 临时目录
  local tmp_project="$TMPDIR_BASE/project_${name}"
  mkdir -p "$tmp_project"
  # 用符号链接复用所有项目文件，只替换 config.json
  for f in "$PROJECT_PATH"/*; do
    local base
    base=$(basename "$f")
    if [ "$base" != ".godot" ] && [ "$base" != "tests" ]; then
      ln -s "$f" "$tmp_project/$base" 2>/dev/null
    fi
  done
  # .godot 目录必须是实体，否则 Godot 会重建
  if [ -d "$PROJECT_PATH/.godot" ]; then
    ln -s "$PROJECT_PATH/.godot" "$tmp_project/.godot" 2>/dev/null
  fi
  # 覆盖 config.json（实体文件，非链接）
  cp "$tmp_config" "$tmp_project/config.json"

  $GODOT --headless --path "$tmp_project" >"$log_file" 2>&1 &
  echo $!
}

echo ""
echo "════════════════════════════════════════"
echo "  PARALLEL SCENARIO TEST"
echo "  Scenarios: ${#SCENARIOS[@]} | Workers: ${#SCENARIOS[@]}"
echo "════════════════════════════════════════"

# 并行启动所有场景，记录 PID
declare -A PIDS
declare -A NAMES
for entry in "${SCENARIOS[@]}"; do
  name="${entry%%:*}"
  scenario_file="${entry##*:}"
  echo "▶ Starting: $name"
  pid=$(run_scenario_bg "$name" "$scenario_file")
  PIDS[$name]=$pid
done

echo ""
echo "⏳ Waiting for all scenarios to complete..."
echo ""

# 等待所有 PID 完成，收集结果
pass_count=0
fail_count=0
results=()

for name in "${!PIDS[@]}"; do
  pid=${PIDS[$name]}
  wait "$pid"
  exit_code=$?
  log_file="$TMPDIR_BASE/log_${name}.txt"

  result_line=$(grep "CALIBRATE.*RESULT" "$log_file" | tail -1)

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "▶ Scenario: $name"
  grep -E "\[CALIBRATE\]|\[BOOT\].*scenario|Applied config" "$log_file"

  if echo "$result_line" | grep -q "0 failed"; then
    echo "✅ PASS: $name"
    results+=("✅ $name: $result_line")
    ((pass_count++))
  else
    echo "❌ FAIL: $name"
    echo "  $result_line"
    results+=("❌ $name: $result_line")
    ((fail_count++))
  fi
done

# 清理临时目录
rm -rf "$TMPDIR_BASE"

echo ""
echo "════════════════════════════════════════"
echo "  SCENARIO TEST SUMMARY"
echo "════════════════════════════════════════"
for r in "${results[@]}"; do
  echo "  $r"
done
echo "────────────────────────────────────────"
echo "  Total: $((pass_count + fail_count)) | Pass: $pass_count | Fail: $fail_count"
echo "════════════════════════════════════════"

[ $fail_count -eq 0 ] && exit 0 || exit 1
