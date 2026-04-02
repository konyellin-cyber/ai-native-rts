#!/bin/bash
# 运行所有场景化测试并汇总结果
# 用法：bash tests/run_scenarios.sh

GODOT=${GODOT:-godot}
PROJECT_PATH="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$PROJECT_PATH/config.json"
SCENARIOS_DIR="$PROJECT_PATH/tests/scenarios"
ORIGINAL_SCENARIO=$(python3 -c "import json; d=json.load(open('$CONFIG')); print(d.get('scenario_file',''))")

pass_count=0
fail_count=0
results=()

run_scenario() {
  local name="$1"
  local scenario_file="$2"

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "▶ Scenario: $name"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # 临时写入 scenario_file
  python3 -c "
import json
with open('$CONFIG') as f: d = json.load(f)
d['scenario_file'] = '$scenario_file'
with open('$CONFIG', 'w') as f: json.dump(d, f, indent=2)
"

  output=$($GODOT --headless --path "$PROJECT_PATH" 2>&1)
  result_line=$(echo "$output" | grep "CALIBRATE.*RESULT")
  echo "$output" | grep -E "\[CALIBRATE\]|\[BOOT\].*scenario|Applied config"

  if echo "$result_line" | grep -q "0 failed"; then
    echo "✅ PASS: $name"
    results+=("✅ $name: $result_line")
    ((pass_count++))
  else
    echo "❌ FAIL: $name"
    results+=("❌ $name: $result_line")
    ((fail_count++))
  fi
}

# 恢复 scenario_file 的函数
restore_config() {
  python3 -c "
import json
with open('$CONFIG') as f: d = json.load(f)
d['scenario_file'] = '$ORIGINAL_SCENARIO'
with open('$CONFIG', 'w') as f: json.dump(d, f, indent=2)
"
}
trap restore_config EXIT

# 运行三个场景
run_scenario "economy"     "$SCENARIOS_DIR/economy.json"
run_scenario "combat"      "$SCENARIOS_DIR/combat.json"
run_scenario "interaction" "$SCENARIOS_DIR/interaction.json"

# 恢复并汇总
restore_config
trap - EXIT

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
