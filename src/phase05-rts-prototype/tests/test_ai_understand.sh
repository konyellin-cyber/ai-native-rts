#!/usr/bin/env bash
## test_ai_understand.sh — AI Understanding Validation (0.5.17)
## Runs a normal game, captures full output for AI battle analysis.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/tests/output"
mkdir -p "$OUTPUT_DIR"

LOG="$OUTPUT_DIR/battle_normal.log"
echo "=== AI Understanding Test ==="

cd "$PROJECT_DIR"
echo "[TEST] Running normal battle..."
godot --headless 2>&1 | tee "$LOG"

echo ""
echo "=== Battle Summary ==="
grep -E "\[BATTLE\]|\[CALIBRATE\] RESULT|\[PERF\]" "$LOG"

echo ""
echo "=== Timeline ==="
grep "\[TICK\]" "$LOG" | tail -5
grep "\[DEATH\]" "$LOG" | head -3
echo "..."
grep "\[DEATH\]" "$LOG" | tail -3

echo ""
echo "Full log saved to: $LOG"
echo "Total lines: $(wc -l < "$LOG")"
