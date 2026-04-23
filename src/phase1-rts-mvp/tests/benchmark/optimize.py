#!/usr/bin/env python3
"""
Phase 19D — 参数自动优化 (Optuna 贝叶斯优化)

用法:
  # 启动优化（默认 50 trials）
  python tests/benchmark/optimize.py

  # 指定 trial 数
  python tests/benchmark/optimize.py --trials 100

  # 把最优参数写回 config.json
  python tests/benchmark/optimize.py --apply-best

  # 从上次中断的地方继续
  python tests/benchmark/optimize.py --resume
"""

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, List, Optional

# ── 路径常量（用 __file__ 推算，脚本可从任意目录执行） ──────────────────────
# 本文件在 src/phase1-rts-mvp/tests/benchmark/optimize.py
# 项目根 = 上四级目录
_SCRIPT_DIR   = Path(__file__).resolve().parent          # .../tests/benchmark/
_PROJECT_ROOT = _SCRIPT_DIR.parent.parent.parent.parent  # ai-native-rts/
_GODOT_PATH   = "src/phase1-rts-mvp"                     # --path 参数（相对项目根）
_CONFIG_JSON  = _PROJECT_ROOT / "src/phase1-rts-mvp/config.json"
_BENCH_DIR    = _PROJECT_ROOT / "src/phase1-rts-mvp/tests/benchmark"
_BEST_PARAMS  = _BENCH_DIR / "best_params.json"
_OPTUNA_DB    = _BENCH_DIR / "optuna_study.db"
_RESULT_GLOB  = "result_*.json"

# ── 参数空间定义 ─────────────────────────────────────────────────────────────
PARAM_SPACE = {
    # (type, low, high)
    "dummy_drive_strength":   ("float", 400.0,  3200.0),
    "dummy_linear_damp":      ("float", 4.0,    16.0),
    "dummy_slow_radius":      ("float", 60.0,   300.0),
    "dummy_arrive_threshold": ("float", 8.0,    30.0),
    ## 以下参数为体验规格，锁定不参与优化：
    ## - march_column_width = 2（两列纵队）
    ## - march_row_path_step = 8（纵队排间距 = 2.5× 碰撞直径，防止重叠挤压）
    ## - march_lead_offset = 3（队首与将领保持合理距离）
    "deploy_trigger_frames":  ("int",   10,     60),
    "deploy_ready_threshold": ("float", 20.0,   80.0),
}


def check_optuna() -> None:
    """依赖检查：确认 optuna 已安装。"""
    try:
        import optuna  # noqa: F401
    except ImportError:
        print("[optimize] optuna 未安装，请先执行：")
        print("    pip install optuna")
        sys.exit(1)


def read_config() -> dict:
    with open(_CONFIG_JSON, encoding="utf-8") as f:
        return json.load(f)


def write_config(cfg: dict) -> None:
    with open(_CONFIG_JSON, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write("\n")


def patch_config(params: dict) -> None:
    """把采样参数 patch 到 general 节点，其他字段不动。
    同时自动计算 path_buffer_size 确保能覆盖最深一排的 path_idx。
    """
    cfg = read_config()
    cfg["general"].update(params)

    # 自动维护 path_buffer_size >= 最深排 path_idx + 5（余量）
    g = cfg["general"]
    soldiers = int(g.get("dummy_soldier_count", 30))
    cols = int(g.get("march_column_width", 2))
    rows = soldiers // cols
    lead = int(g.get("march_lead_offset", 3))
    step = int(g.get("march_row_path_step", 8))
    required = lead + (rows - 1) * step + 5
    if g.get("path_buffer_size", 60) < required:
        cfg["general"]["path_buffer_size"] = required

    write_config(cfg)


def find_latest_result() -> Optional[Path]:
    """找 benchmark 目录下最新的 result_*.json。"""
    candidates = sorted(_BENCH_DIR.glob(_RESULT_GLOB), key=lambda p: p.stat().st_mtime)
    return candidates[-1] if candidates else None


def run_benchmark(timeout: int = 180) -> float:
    """
    启动 godot --benchmark，等待退出，读取最新 result JSON。
    返回 overall_score；超时或失败返回 0.0。
    """
    # 记录运行前已有的 result 文件集合，方便找"本次新生成的"
    before = set(_BENCH_DIR.glob(_RESULT_GLOB))

    cmd = [
        "godot",
        "--path", str(_PROJECT_ROOT / _GODOT_PATH),
        "--scene", "res://tests/gameplay/general_visual/scene.tscn",
        "--",
        "--benchmark",
    ]

    try:
        proc = subprocess.run(
            cmd,
            cwd=str(_PROJECT_ROOT),
            timeout=timeout,
            capture_output=True,
            text=True,
        )
    except subprocess.TimeoutExpired:
        print(f"    [warn] godot 超时（>{timeout}s），本 trial 计 0.0")
        return 0.0
    except FileNotFoundError:
        print("    [error] 找不到 godot 命令，请确认 PATH 配置")
        return 0.0

    if proc.returncode != 0:
        print(f"    [warn] godot 退出码={proc.returncode}，本 trial 计 0.0")
        return 0.0

    # 找本次新生成的 result 文件（若有多个取最新）
    after = set(_BENCH_DIR.glob(_RESULT_GLOB))
    new_files = sorted(after - before, key=lambda p: p.stat().st_mtime)
    result_path = new_files[-1] if new_files else find_latest_result()

    if result_path is None:
        print("    [warn] 未找到 result_*.json，本 trial 计 0.0")
        return 0.0

    with open(result_path, encoding="utf-8") as f:
        data = json.load(f)

    score = float(data.get("overall_score", 0.0))
    return score


def load_best():
    if _BEST_PARAMS.exists():
        with open(_BEST_PARAMS, encoding="utf-8") as f:
            return json.load(f)
    return None


def save_best(score: float, trial_number: int, params: dict) -> None:
    payload = {"score": score, "trial": trial_number, "params": params}
    with open(_BEST_PARAMS, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)
        f.write("\n")


def format_params_short(params: dict) -> str:
    """生成紧凑的参数摘要，用于进度输出。"""
    kmap = {
        "dummy_drive_strength":   "drive",
        "dummy_linear_damp":      "damp",
        "dummy_slow_radius":      "slow_r",
        "dummy_arrive_threshold": "arrive",
        "march_column_width":     "col_w",
        "march_row_path_step":    "row_step",
        "march_lead_offset":      "lead",
        "deploy_trigger_frames":  "dep_frm",
        "deploy_ready_threshold": "dep_thr",
    }
    parts = []
    for k, v in params.items():
        short = kmap.get(k, k)
        if isinstance(v, float):
            parts.append(f"{short}={v:.1f}")
        else:
            parts.append(f"{short}={v}")
    return ", ".join(parts)


def build_objective(total_trials: int):
    """闭包：生成 Optuna objective 函数，绑定 total_trials 用于进度输出。"""
    best_score_holder = [load_best()["score"] if load_best() else -1.0]

    def objective(trial) -> float:
        import optuna

        # 1. 采样参数
        params = {}
        for name, (ptype, low, high) in PARAM_SPACE.items():
            if ptype == "float":
                params[name] = trial.suggest_float(name, low, high)
            else:
                params[name] = trial.suggest_int(name, low, high)

        # 2. Patch config.json
        patch_config(params)

        # 3. 运行 benchmark
        score = run_benchmark(timeout=180)

        # 4. 更新 best_params.json
        is_best = score > best_score_holder[0]
        if is_best:
            best_score_holder[0] = score
            save_best(score, trial.number, params)

        # 5. 进度输出
        best_marker = " ★ best" if is_best else "      "
        params_str  = format_params_short(params)
        print(
            f"Trial {trial.number + 1}/{total_trials} | "
            f"score={score:.1f}{best_marker} | "
            f"params={{{params_str}}}"
        )

        return score

    return objective


def run_optimize(total_trials: int, resume: bool) -> None:
    """主优化流程。"""
    import optuna
    from optuna.samplers import TPESampler

    # resume=True 时使用已有 study；False 时若 DB 存在则覆盖
    storage = f"sqlite:///{_OPTUNA_DB}"

    if not resume and _OPTUNA_DB.exists():
        # 删除旧 study 重新开始
        _OPTUNA_DB.unlink()
        print("[optimize] 已清除旧 study，重新开始")

    study = optuna.create_study(
        study_name="phase19_tuning",
        storage=storage,
        direction="maximize",
        sampler=TPESampler(),
        load_if_exists=True,   # resume 模式下继续；非 resume 已删 DB 所以无冲突
    )

    already_done = len(study.trials)
    remaining    = max(0, total_trials - already_done)

    if resume and already_done > 0:
        print(f"[optimize] 从上次中断继续，已完成 {already_done} trials，剩余 {remaining}")

    if remaining == 0:
        print("[optimize] 目标 trials 已全部完成，无需运行")
        return

    objective = build_objective(total_trials)
    study.optimize(objective, n_trials=remaining)

    best = study.best_trial
    print("\n─── 优化完成 ───────────────────────────────────")
    print(f"最优 score : {best.value:.2f}")
    print(f"Trial 编号 : {best.number}")
    print("最优参数   :")
    for k, v in best.params.items():
        print(f"  {k}: {v}")


def run_apply_best() -> None:
    """将 best_params.json 中的参数写回 config.json。"""
    best = load_best()
    if best is None:
        print("[apply-best] 未找到 best_params.json，请先运行优化")
        sys.exit(1)

    params  = best["params"]
    score   = best["score"]
    trial   = best["trial"]

    cfg = read_config()
    old_general = {k: cfg["general"].get(k) for k in params}

    patch_config(params)

    print(f"[apply-best] 已将 Trial {trial}（score={score:.2f}）的最优参数写入 config.json")
    print("\n变更摘要（general 节点）：")
    print(f"  {'参数名':<30}  {'旧值':>12}  →  {'新值':>12}")
    print("  " + "─" * 60)
    for k, new_v in params.items():
        old_v = old_general[k]
        marker = "  " if old_v == new_v else "✎"
        if isinstance(new_v, float):
            print(f"  {marker} {k:<28}  {str(old_v):>12}  →  {new_v:>12.4f}")
        else:
            print(f"  {marker} {k:<28}  {str(old_v):>12}  →  {new_v:>12}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Phase 19D 参数自动优化（Optuna 贝叶斯优化）"
    )
    parser.add_argument("--trials",     type=int, default=50,
                        help="总 trial 数（默认 50）")
    parser.add_argument("--apply-best", action="store_true",
                        help="将最优参数写回 config.json，不运行优化")
    parser.add_argument("--resume",     action="store_true",
                        help="从上次中断的地方继续优化")
    args = parser.parse_args()

    # apply-best 不需要 optuna，单独处理
    if args.apply_best:
        run_apply_best()
    else:
        check_optuna()  # 只在真正要跑优化时才检查
        run_optimize(total_trials=args.trials, resume=args.resume)


if __name__ == "__main__":
    main()
