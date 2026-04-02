#!/usr/bin/env bash
## test_ai_debug.sh — AI Debug Validation (0.5.16)
## Usage: ./tests/test_ai_debug.sh [sight_range_zero | attack_damage_zero | speed_zero | no_ref_filter]
## Injects a bug, runs headless, captures output, restores original code.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG="$PROJECT_DIR/config.json"
SEL_MGR="$PROJECT_DIR/scripts/selection_manager.gd"
OUTPUT_DIR="$PROJECT_DIR/tests/output"
mkdir -p "$OUTPUT_DIR"

BUG_TYPE="${1:-sight_range_zero}"
BACKUP="$OUTPUT_DIR/config_backup.json"
LOG="$OUTPUT_DIR/debug_${BUG_TYPE}.log"
SEL_MGR_BACKUP="$OUTPUT_DIR/selection_manager.gd.bak"

echo "=== AI Debug Test: $BUG_TYPE ==="

case "$BUG_TYPE" in
  sight_range_zero|attack_damage_zero|speed_zero)
    # Config-based bug injection
    cp "$CONFIG" "$BACKUP"
    case "$BUG_TYPE" in
      sight_range_zero)
        jq '.units.sight_range = 0' "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
        echo "[TEST] Injected: sight_range = 0 (units cannot detect enemies)"
        ;;
      attack_damage_zero)
        jq '.units.attack_damage = 0' "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
        echo "[TEST] Injected: attack_damage = 0 (units chase but never kill)"
        ;;
      speed_zero)
        jq '.units.speed = 0' "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
        echo "[TEST] Injected: speed = 0 (units cannot move)"
        ;;
    esac
    RESTORE_CONFIG=true
    RESTORE_SEL_MGR=false
    ;;
  no_ref_filter)
    # Code-based bug injection: disable is_instance_valid filtering in SelectionManager
    cp "$SEL_MGR" "$SEL_MGR_BACKUP"
    sed -i '' 's/_all_units = _all_units.filter(func(u): return is_instance_valid(u))/# BUG INJECTED: no ref filtering/' "$SEL_MGR"
    echo "[TEST] Injected: SelectionManager._on_selection_rect() no longer filters dead refs"
    RESTORE_CONFIG=false
    RESTORE_SEL_MGR=true
    ;;
  *)
    echo "Unknown bug type: $BUG_TYPE"
    echo "Usage: $0 [sight_range_zero | attack_damage_zero | speed_zero | no_ref_filter]"
    exit 1
    ;;
esac

# Run headless
echo "[TEST] Running headless..."
cd "$PROJECT_DIR"
godot --headless 2>&1 | tee "$LOG"

# Restore
if [ "$RESTORE_CONFIG" = true ]; then
  cp "$BACKUP" "$CONFIG"
  echo "[TEST] Restored config.json"
fi
if [ "$RESTORE_SEL_MGR" = true ]; then
  cp "$SEL_MGR_BACKUP" "$SEL_MGR"
  rm -f "$SEL_MGR_BACKUP"
  echo "[TEST] Restored selection_manager.gd"
fi

# Check Calibrator results
echo ""
echo "=== Calibrator Results ==="
if grep -q "\[FAIL\] node_lifecycle_integrity" "$LOG"; then
  echo "[PASS] node_lifecycle_integrity correctly detected the lifecycle bug"
elif grep -q "RESULT: 0 passed, [1-9]" "$LOG"; then
  echo "[PASS] Calibrator detected the bug (at least one [FAIL])"
elif grep -q "RESULT: [1-9] passed, [1-9]" "$LOG"; then
  echo "[PARTIAL] Some assertions passed, some failed"
  grep "CALIBRATE" "$LOG"
else
  echo "[FAIL] Calibrator did not detect the bug (all passed or no results)"
  grep "CALIBRATE" "$LOG"
fi

echo ""
echo "=== AI Diagnosis ==="
echo "Full log saved to: $LOG"
echo "Analyze with: cat $LOG"
