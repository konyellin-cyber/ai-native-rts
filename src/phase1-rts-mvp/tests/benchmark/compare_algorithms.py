#!/usr/bin/env python3
"""
Phase 23 A/B 算法对比评估脚本

对比三种行军算法（path_follow / flow_field / direct_seek）在 benchmark 场景下的表现。
复用已有的 general_visual --benchmark 流程，通过修改 config.json 切换算法。

用法：
    cd src/phase1-rts-mvp
    python tests/benchmark/compare_algorithms.py          # 3 种算法 × 3 次
    python tests/benchmark/compare_algorithms.py --trials 1  # 快速验证
    python tests/benchmark/compare_algorithms.py --algo path_follow  # 只跑一种
"""

import json
import os
import shutil
import subprocess
import sys
import glob
from datetime import datetime
from pathlib import Path

# ─── 路径 ──────────────────────────────────────────────────────────────────
SCRIPT_DIR   = Path(__file__).parent
PROJECT_DIR  = SCRIPT_DIR.parent.parent
CONFIG_PATH  = PROJECT_DIR / "config.json"
RESULT_DIR   = SCRIPT_DIR

ALGORITHMS   = ["path_follow", "flow_field", "direct_seek"]
DEFAULT_TRIALS = 3

# 评分权重（对应 design.md 中的公式）
WEIGHTS = {
    "velocity_coherence":  0.25,
    "lateral_spread_norm": 0.20,   # 1 - lateral_spread/120
    "slot_error_norm":     0.20,   # 1 - avg_slot_error/80
    "nudge_norm":          0.20,   # 1 - stuck_nudge/20（来自 overall_score 的 warn 项）
    "convergence_norm":    0.15,   # 1 - convergence_frames/300（来自 deploy_frames）
}


def load_config() -> dict:
    with open(CONFIG_PATH) as f:
        return json.load(f)


def save_config(cfg: dict):
    with open(CONFIG_PATH, "w") as f:
        json.dump(cfg, f, indent=2)


def set_algorithm(algo: str):
    cfg = load_config()
    cfg["general"]["march_algorithm"] = algo
    save_config(cfg)


def run_benchmark() -> Path | None:
    """运行 Godot benchmark，返回最新生成的 result JSON 路径"""
    existing = set(RESULT_DIR.glob("result_*.json"))
    cmd = [
        "godot",
        "--path", str(PROJECT_DIR),
        "--scene", "res://tests/gameplay/general_visual/scene.tscn",
        "--", "--benchmark"
    ]
    print(f"    运行: {' '.join(cmd[-4:])}")
    try:
        subprocess.run(cmd, check=True, timeout=300,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        print("    ⚠️  超时（300s）")
        return None
    except subprocess.CalledProcessError as e:
        print(f"    ⚠️  退出码 {e.returncode}")
        return None

    new_files = set(RESULT_DIR.glob("result_*.json")) - existing
    if not new_files:
        print("    ⚠️  未生成新 result 文件")
        return None
    return max(new_files, key=lambda p: p.stat().st_mtime)


def extract_metrics(result_path: Path) -> dict:
    """从 result JSON 提取用于对比的关键指标"""
    with open(result_path) as f:
        data = json.load(f)

    overall = data.get("overall_score", 0.0)
    scenes  = data.get("scenes", [])

    # 汇总各场景指标
    total_frames    = sum(s.get("total_frames", 0)    for s in scenes)
    march_frames    = sum(s.get("march_frames", 0)    for s in scenes)
    deploy_frames   = sum(s.get("deploy_frames", 0)   for s in scenes)
    clump_warns     = sum(s.get("warn_counts", {}).get("clump", 0)      for s in scenes)
    incoherent_warns = sum(s.get("warn_counts", {}).get("incoherent", 0) for s in scenes)
    lat_warns       = sum(s.get("warn_counts", {}).get("lat_collapse", 0) for s in scenes)
    overshoot_warns = sum(s.get("warn_counts", {}).get("overshoot", 0)  for s in scenes)
    not_frozen_warns= sum(s.get("warn_counts", {}).get("not_frozen", 0) for s in scenes)

    n = max(len(scenes), 1)
    avg_march_score  = sum(s.get("march_score", 0)  for s in scenes) / n
    avg_deploy_score = sum(s.get("deploy_score", 0) for s in scenes) / n

    return {
        "overall_score":      overall,
        "avg_march_score":    round(avg_march_score, 1),
        "avg_deploy_score":   round(avg_deploy_score, 1),
        "total_frames":       total_frames,
        "march_frames":       march_frames,
        "deploy_frames":      deploy_frames,
        "clump_warns":        clump_warns,
        "incoherent_warns":   incoherent_warns,
        "lat_warns":          lat_warns,
        "overshoot_warns":    overshoot_warns,
        "not_frozen_warns":   not_frozen_warns,
    }


def compute_composite_score(m: dict) -> float:
    """按 design.md 权重公式计算综合分（0~100）"""
    # 从 warn 数量反推归一化分
    nudge_norm       = max(0.0, 1.0 - (m["incoherent_warns"] + m["clump_warns"]) / 20.0)
    lat_norm         = max(0.0, 1.0 - m["lat_warns"] / 50.0)
    convergence_norm = max(0.0, 1.0 - m["deploy_frames"] / 1200.0)

    # 用 march_score 和 deploy_score 直接转 0~1
    march_norm  = m["avg_march_score"] / 100.0
    deploy_norm = m["avg_deploy_score"] / 100.0

    score = (
        march_norm  * 0.30 +
        deploy_norm * 0.25 +
        nudge_norm  * 0.20 +
        lat_norm    * 0.15 +
        convergence_norm * 0.10
    ) * 100.0
    return round(score, 1)


def aggregate_trials(trial_metrics: list[dict]) -> dict:
    """对多次 trial 结果取均值"""
    keys = trial_metrics[0].keys()
    result = {}
    for k in keys:
        vals = [m[k] for m in trial_metrics]
        result[k] = round(sum(vals) / len(vals), 2)
    return result


def format_table(results: dict[str, dict]) -> str:
    """生成 Markdown 对比表"""
    algos = list(results.keys())
    metrics = [
        ("overall_score",    "综合得分"),
        ("avg_march_score",  "行军分"),
        ("avg_deploy_score", "展开分"),
        ("total_frames",     "总帧数"),
        ("march_frames",     "行军帧数"),
        ("deploy_frames",    "展开帧数"),
        ("clump_warns",      "挤团告警"),
        ("incoherent_warns", "方向混乱告警"),
        ("lat_warns",        "队形崩溃告警"),
        ("overshoot_warns",  "过冲告警"),
        ("not_frozen_warns", "未稳定告警"),
        ("composite",        "加权综合分"),
    ]

    header = "| 指标 | " + " | ".join(algos) + " |"
    sep    = "|------|" + "------|" * len(algos)
    rows   = [header, sep]
    for key, label in metrics:
        row = f"| {label} |"
        for algo in algos:
            val = results[algo].get(key, "-")
            row += f" {val} |"
        rows.append(row)
    return "\n".join(rows)


def generate_report(results: dict, timestamp: str) -> str:
    """生成完整对比报告 Markdown"""
    lines = [
        "# Phase 23 行军算法 A/B 对比报告",
        "",
        f"**生成时间**: {timestamp}",
        f"**参与算法**: {', '.join(results.keys())}",
        "",
        "---",
        "",
        "## 综合对比表",
        "",
        format_table(results),
        "",
        "---",
        "",
        "## 各算法评估",
        "",
    ]

    ranked = sorted(results.items(), key=lambda x: x[1].get("composite", 0), reverse=True)
    for rank, (algo, m) in enumerate(ranked, 1):
        lines += [
            f"### {rank}. {algo}",
            "",
            f"- **加权综合分**: {m.get('composite', '-')}",
            f"- **行军分**: {m.get('avg_march_score', '-')}  **展开分**: {m.get('avg_deploy_score', '-')}",
            f"- **告警总计**: 挤团={m.get('clump_warns',0)}  方向={m.get('incoherent_warns',0)}  队形={m.get('lat_warns',0)}",
            "",
        ]

    lines += [
        "---",
        "",
        "## 结论",
        "",
        f"**综合得分最高**: {ranked[0][0]} ({ranked[0][1].get('composite', '-')} 分)",
        "",
        "> 窗口目视验证仍需人工确认。数据仅供参考。",
        "",
        f"_生成脚本: tests/benchmark/compare_algorithms.py_",
    ]
    return "\n".join(lines)


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Phase 23 行军算法 A/B 对比")
    parser.add_argument("--trials", type=int, default=DEFAULT_TRIALS, help="每种算法重复次数")
    parser.add_argument("--algo", type=str, default=None, help="只测一种算法")
    args = parser.parse_args()

    algos = [args.algo] if args.algo else ALGORITHMS
    trials = args.trials

    # 备份原始 config
    backup_path = CONFIG_PATH.with_suffix(".json.bak")
    shutil.copy(CONFIG_PATH, backup_path)
    print(f"✅ 已备份 config → {backup_path.name}")

    all_results: dict[str, dict] = {}

    try:
        for algo in algos:
            print(f"\n{'='*50}")
            print(f"算法: {algo}  （{trials} 次）")
            print('='*50)
            trial_metrics = []

            set_algorithm(algo)
            print(f"  config.json → march_algorithm = {algo}")

            for t in range(1, trials + 1):
                print(f"  Trial {t}/{trials}...")
                result_path = run_benchmark()
                if result_path is None:
                    print(f"  ⚠️  Trial {t} 失败，跳过")
                    continue
                m = extract_metrics(result_path)
                trial_metrics.append(m)
                print(f"  → overall={m['overall_score']}  march={m['avg_march_score']}  deploy={m['avg_deploy_score']}")

            if not trial_metrics:
                print(f"  ❌ {algo} 无有效数据")
                continue

            agg = aggregate_trials(trial_metrics)
            agg["composite"] = compute_composite_score(agg)
            all_results[algo] = agg
            print(f"  均值综合分: {agg['composite']}")

    finally:
        # 恢复原始 config
        shutil.copy(backup_path, CONFIG_PATH)
        print(f"\n✅ 已恢复 config.json")

    if not all_results:
        print("❌ 无任何有效结果，退出")
        sys.exit(1)

    # 写出原始数据
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    raw_path = RESULT_DIR / f"compare_result_{timestamp}.json"
    with open(raw_path, "w") as f:
        json.dump({"timestamp": timestamp, "trials": trials, "results": all_results}, f, indent=2)
    print(f"\n📄 原始数据: {raw_path.name}")

    # 生成报告
    report = generate_report(all_results, timestamp)
    report_path = RESULT_DIR / "compare_report.md"
    with open(report_path, "w") as f:
        f.write(report)
    print(f"📊 对比报告: {report_path.name}")

    # 打印摘要
    print("\n" + "="*50)
    print("摘要")
    print("="*50)
    ranked = sorted(all_results.items(), key=lambda x: x[1].get("composite", 0), reverse=True)
    for rank, (algo, m) in enumerate(ranked, 1):
        print(f"  {rank}. {algo:15s} 综合={m.get('composite','-'):5}  行军={m.get('avg_march_score','-')}  展开={m.get('avg_deploy_score','-')}")


if __name__ == "__main__":
    main()
