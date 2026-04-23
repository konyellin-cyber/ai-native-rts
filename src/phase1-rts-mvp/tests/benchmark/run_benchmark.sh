#!/bin/bash
## Phase 19 Benchmark 一键运行脚本
## 用法：
##   bash tests/benchmark/run_benchmark.sh          # 运行并与上次对比
##   bash tests/benchmark/run_benchmark.sh --no-run # 只对比最近两次结果，不启动 Godot

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BENCH_DIR="$PROJECT_DIR/tests/benchmark"

## ── 1. 运行 Godot Benchmark ────────────────────────────────────────────────
if [[ "$1" != "--no-run" ]]; then
    echo "🚀 启动 Benchmark..."
    echo "   项目: $PROJECT_DIR"
    echo "   场景: tests/gameplay/general_visual/scene.tscn"
    echo ""
    godot --path "$PROJECT_DIR" \
          --scene res://tests/gameplay/general_visual/scene.tscn \
          -- --benchmark
    echo ""
    echo "✅ Godot 退出，开始分析结果..."
fi

## ── 2. 找最近两次结果 ─────────────────────────────────────────────────────
RESULTS=( $(ls -t "$BENCH_DIR"/result_*.json 2>/dev/null) )

if [[ ${#RESULTS[@]} -eq 0 ]]; then
    echo "❌ 没有找到任何 benchmark 结果文件（$BENCH_DIR/result_*.json）"
    exit 1
fi

LATEST="${RESULTS[0]}"
echo "📊 最新结果: $(basename $LATEST)"

if [[ ${#RESULTS[@]} -ge 2 ]]; then
    PREV="${RESULTS[1]}"
    echo "📊 对比基线: $(basename $PREV)"
else
    echo "ℹ️  首次运行，无历史基线可对比"
    PREV=""
fi

## ── 3. Python 对比分析 ────────────────────────────────────────────────────
python3 - "$LATEST" "$PREV" << 'PYEOF'
import sys, json

def load(path):
    if not path:
        return None
    try:
        with open(path) as f:
            return json.load(f)
    except:
        return None

def score_icon(score):
    if score >= 70: return "🟢"
    if score >= 50: return "🟡"
    return "🔴"

def diff_str(new_val, old_val):
    if old_val is None:
        return ""
    delta = new_val - old_val
    if abs(delta) < 0.5:
        return "  (→ 持平)"
    sign = "+" if delta > 0 else ""
    arrow = "↑" if delta > 0 else "↓"
    return f"  ({arrow} {sign}{delta:.1f})"

latest = load(sys.argv[1])
prev   = load(sys.argv[2]) if len(sys.argv) > 2 else None

if not latest:
    print("❌ 无法读取结果文件")
    sys.exit(1)

print()
print("═══════════════════════════════════════════════════════")
print(f"  BENCHMARK REPORT — {latest['timestamp']}")
print(f"  Overall: {score_icon(latest['overall_score'])} {latest['overall_score']:.1f} / 100", end="")
if prev:
    print(diff_str(latest['overall_score'], prev.get('overall_score')), end="")
print()
print("───────────────────────────────────────────────────────")

# 建立 prev 场景索引
prev_scenes = {}
if prev:
    for s in prev.get("scenes", []):
        prev_scenes[s["scene_name"]] = s

for scene in latest.get("scenes", []):
    name = scene["scene_name"]
    ms = scene["march_score"]
    ds = scene["deploy_score"]
    ts = scene["total_score"]
    ps = prev_scenes.get(name)

    print(f"\n  {score_icon(ts)} {name}")
    print(f"    行军质量: {ms:5.1f}{diff_str(ms, ps['march_score'] if ps else None)}")
    print(f"    展开质量: {ds:5.1f}{diff_str(ds, ps['deploy_score'] if ps else None)}")
    print(f"    综合评分: {ts:5.1f}{diff_str(ts, ps['total_score'] if ps else None)}")

    warns = scene.get("warn_counts", {})
    pw = ps.get("warn_counts", {}) if ps else {}
    print(f"    告警: clump={warns.get('clump',0)}{diff_str(warns.get('clump',0), pw.get('clump')) if ps else ''} "
          f"incoherent={warns.get('incoherent',0)}{diff_str(warns.get('incoherent',0), pw.get('incoherent')) if ps else ''} "
          f"overshoot={warns.get('overshoot',0)}{diff_str(warns.get('overshoot',0), pw.get('overshoot')) if ps else ''}")

    ftf = scene.get("freeze_frames_to_full", -1)
    if ftf > 0:
        print(f"    横阵稳定: {ftf}帧 ({ftf/60:.1f}s)")
    else:
        print(f"    横阵稳定: 未完成")

print()
print("═══════════════════════════════════════════════════════")

# 回归检测
regressions = []
if prev:
    for scene in latest.get("scenes", []):
        name = scene["scene_name"]
        ps = prev_scenes.get(name)
        if not ps:
            continue
        if scene["total_score"] < ps["total_score"] - 5:
            regressions.append(f"  ⚠️  {name}: 综合评分下降 {ps['total_score'] - scene['total_score']:.1f} 分")
        if scene["march_score"] < ps["march_score"] - 8:
            regressions.append(f"  ⚠️  {name}: 行军质量下降 {ps['march_score'] - scene['march_score']:.1f} 分")

    if regressions:
        print()
        print("⚠️  回归警告:")
        for r in regressions:
            print(r)
    else:
        print("✅ 无回归（各项评分未出现明显下降）")

print()
PYEOF
