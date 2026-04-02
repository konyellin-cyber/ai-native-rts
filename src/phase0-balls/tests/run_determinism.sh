#!/bin/bash
set -e
FRAMES="/Users/konyel/.agent/.openclaw/workspace/memory/projects/ai-native-rts/src/phase0-balls/frames"
PHASE0="/Users/konyel/.agent/.openclaw/workspace/memory/projects/ai-native-rts/src/phase0-balls"
N=${1:-10}
TMPDIR_DET="/tmp/determinism_test"
mkdir -p "$TMPDIR_DET"

# Strip timestamp field for comparison
strip_ts() {
    sed 's/"timestamp": [0-9]*/"timestamp": 0/' "$1"
}

echo "=== Determinism test: $N runs ==="
echo ""

# Run 1 (baseline)
echo -n "Run 1/$N ... "
find "$FRAMES" -name "*.json" -delete 2>/dev/null
godot --headless --path "$PHASE0" 2>/dev/null | grep PERF
cp "$FRAMES/frame_000300.json" "$TMPDIR_DET/run_001.json"
strip_ts "$TMPDIR_DET/run_001.json" > "$TMPDIR_DET/baseline.json"
echo "OK"

# Runs 2..N
PASS=0
FAIL=0
for i in $(seq 2 $N); do
    NUM=$(printf "%03d" $i)
    echo -n "Run $i/$N ... "
    find "$FRAMES" -name "*.json" -delete 2>/dev/null
    godot --headless --path "$PHASE0" 2>/dev/null | grep PERF
    cp "$FRAMES/frame_000300.json" "$TMPDIR_DET/run_$NUM.json"
    strip_ts "$TMPDIR_DET/run_$NUM.json" > "$TMPDIR_DET/curr.json"
    if diff "$TMPDIR_DET/baseline.json" "$TMPDIR_DET/curr.json" > /dev/null 2>&1; then
        echo "MATCH"
        PASS=$((PASS + 1))
    else
        echo "MISMATCH!"
        diff "$TMPDIR_DET/baseline.json" "$TMPDIR_DET/curr.json" | head -10
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "=== Results ==="
echo "Passed: $PASS/$((N-1))"
echo "Failed: $FAIL/$((N-1))"
if [ $FAIL -eq 0 ]; then
    echo "STATUS: PASS - All runs deterministic"
else
    echo "STATUS: FAIL - Non-deterministic behavior detected"
fi
