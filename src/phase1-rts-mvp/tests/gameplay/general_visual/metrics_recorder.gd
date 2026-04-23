extends RefCounted
class_name MetricsRecorder

## Phase 19 Benchmark 数据采集 + 评分
## 每帧由 bootstrap 调用 record_frame()，场景边界由 on_scene_started/ended 通知。
## 全部场景结束后调用 finalize()，输出 JSON + 控制台摘要。

const OUTPUT_DIR = "res://tests/benchmark/"

var _general: Node = null
var _current_scene_id: int = -1
var _current_scene_name: String = ""

## 当前场景的逐帧数据
var _frame_data: Array = []

## 当前场景的告警计数
var _warn_counts: Dictionary = {}

## 所有场景的结果汇总
var _scene_results: Array = []

## 运行时间戳（用于文件名）
var _timestamp: String = ""

## 评分权重
const W_STD_DEV    := 40  ## march_score: pos_std_dev 在 30~300 的帧比例
const W_COHERENCE  := 30  ## march_score: velocity_coherence > 0.5 的帧比例
const W_WARN_FREE  := 30  ## march_score: 无 incoherent 告警
const W_OVERSHOOT  := 50  ## deploy_score: overshoot_count=0 的帧比例（展开阶段）
const W_FREEZE_SPD := 50  ## deploy_score: freeze_rate 达到 1.0 的速度（帧数越少分越高）
const FREEZE_TARGET_FRAMES := 300  ## 期望 5 秒内全员 freeze

## 告警阈值（与 bootstrap._check_quality_warnings 保持一致）
const THR_STD_LOW   := 30.0
const THR_STD_HIGH  := 400.0
const THR_LAT       := 120.0
const THR_COH       := 0.2
const THR_OVERSHOOT := 3


func setup(general: Node) -> void:
	_general = general
	var dt = Time.get_datetime_dict_from_system()
	_timestamp = "%04d%02d%02d_%02d%02d%02d" % [
		dt["year"], dt["month"], dt["day"],
		dt["hour"], dt["minute"], dt["second"]
	]


func on_scene_started(scene_id: int, scene_name: String) -> void:
	_current_scene_id = scene_id
	_current_scene_name = scene_name
	_frame_data = []
	_warn_counts = {
		"clump": 0, "scatter": 0, "lat_collapse": 0,
		"incoherent": 0, "overshoot": 0, "not_frozen": 0
	}
	print("[METRICS] 开始采集场景 %d: %s" % [scene_id, scene_name])


func record_frame(frame: int, summary: Dictionary, cur_state: String) -> void:
	if _current_scene_id < 0:
		return

	var snap = {
		"f": frame,
		"state": cur_state,
		"avg_err": summary.get("avg_slot_error", -1.0),
		"std": summary.get("pos_std_dev", -1.0),
		"lat": summary.get("lateral_spread", -1.0),
		"coh": summary.get("velocity_coherence", -1.0),
		"overshoot": summary.get("overshoot_count", 0),
		"freeze": summary.get("freeze_rate", 0.0),
		"waiting": summary.get("waiting_count", 0),
	}
	_frame_data.append(snap)

	## 统计告警触发帧数
	var std: float = snap["std"]
	var lat: float = snap["lat"]
	var coh: float = snap["coh"]
	var overshoot: int = snap["overshoot"]
	var freeze_r: float = snap["freeze"]

	if std >= 0 and std < THR_STD_LOW and cur_state == "marching":
		_warn_counts["clump"] += 1
	if std > THR_STD_HIGH:
		_warn_counts["scatter"] += 1
	if lat >= 0 and lat > THR_LAT and cur_state == "marching":
		_warn_counts["lat_collapse"] += 1
	if coh >= 0 and coh < THR_COH and cur_state == "marching":
		_warn_counts["incoherent"] += 1
	if overshoot > THR_OVERSHOOT:
		_warn_counts["overshoot"] += 1
	if cur_state == "deployed" and freeze_r < 0.9:
		_warn_counts["not_frozen"] += 1


func on_scene_ended(scene_id: int, _scene_name: String, player_result: Dictionary) -> void:
	if _current_scene_id < 0:
		return

	var total_frames = _frame_data.size()
	if total_frames == 0:
		return

	## 分离行军帧 / 展开帧
	var march_frames: Array = _frame_data.filter(func(s): return s["state"] == "marching")
	var deploy_frames: Array = _frame_data.filter(func(s): return s["state"] == "deployed")

	## ── march_score ──────────────────────────────────────────────
	var march_score := 0.0
	if march_frames.size() > 0:
		var mf = march_frames.size()
		## std_dev 在 30~300 的帧比例
		var std_ok = march_frames.filter(func(s): return s["std"] >= THR_STD_LOW and s["std"] <= 300.0).size()
		## coherence > 0.5 的帧比例
		var coh_ok = march_frames.filter(func(s): return s["coh"] > 0.5).size()
		## 无 incoherent 告警帧比例（coherence 在 0.2 以上即可）
		var warn_ok = march_frames.filter(func(s): return s["coh"] >= THR_COH).size()

		march_score = (
			float(std_ok) / float(mf) * W_STD_DEV +
			float(coh_ok) / float(mf) * W_COHERENCE +
			float(warn_ok) / float(mf) * W_WARN_FREE
		)

	## ── deploy_score ─────────────────────────────────────────────
	var deploy_score := 0.0
	var freeze_frames_to_full := -1  ## 从 deployed 入场到 freeze_rate=1.0 的帧数
	if deploy_frames.size() > 0:
		var df = deploy_frames.size()
		## overshoot=0 的帧比例
		var overshoot_ok = deploy_frames.filter(func(s): return s["overshoot"] == 0).size()
		## 找到 freeze_rate 第一次到 1.0 的帧
		for i in range(deploy_frames.size()):
			if deploy_frames[i]["freeze"] >= 1.0:
				freeze_frames_to_full = i + 1
				break
		var freeze_speed_score := 0.0
		if freeze_frames_to_full > 0:
			freeze_speed_score = clampf(
				float(FREEZE_TARGET_FRAMES - freeze_frames_to_full) / float(FREEZE_TARGET_FRAMES),
				0.0, 1.0
			) * W_FREEZE_SPD
		elif deploy_frames.size() > 0 and deploy_frames[-1]["freeze"] < 1.0:
			freeze_speed_score = 0.0  ## 超时未完成
		else:
			freeze_speed_score = 0.0

		deploy_score = (
			float(overshoot_ok) / float(df) * W_OVERSHOOT +
			freeze_speed_score
		)

	var total_score = (march_score + deploy_score) / 2.0

	var result = {
		"scene_id": scene_id,
		"scene_name": _current_scene_name,
		"total_frames": total_frames,
		"march_frames": march_frames.size(),
		"deploy_frames": deploy_frames.size(),
		"march_score": snappedf(march_score, 0.1),
		"deploy_score": snappedf(deploy_score, 0.1),
		"total_score": snappedf(total_score, 0.1),
		"warn_counts": _warn_counts.duplicate(),
		"freeze_frames_to_full": freeze_frames_to_full,
		"player_result": player_result,
	}
	_scene_results.append(result)

	## 控制台摘要
	print("[METRICS] 场景 %s 评分: march=%.0f deploy=%.0f total=%.0f" % [
		_current_scene_name, march_score, deploy_score, total_score])
	print("          warns: clump=%d incoherent=%d overshoot=%d not_frozen=%d" % [
		_warn_counts["clump"], _warn_counts["incoherent"],
		_warn_counts["overshoot"], _warn_counts["not_frozen"]
	])
	if freeze_frames_to_full > 0:
		print("          freeze_full: %d帧 (%.1fs)" % [freeze_frames_to_full, freeze_frames_to_full / 60.0])
	else:
		print("          freeze_full: 未完成")

	_current_scene_id = -1


func finalize() -> void:
	## 计算总分
	var overall := 0.0
	for r in _scene_results:
		overall += r["total_score"]
	if _scene_results.size() > 0:
		overall /= float(_scene_results.size())

	var output = {
		"timestamp": _timestamp,
		"overall_score": snappedf(overall, 0.1),
		"scenes": _scene_results,
	}

	## 保存 JSON
	var dir = DirAccess.open("res://")
	if dir and not dir.dir_exists("tests/benchmark"):
		dir.make_dir_recursive("tests/benchmark")

	var path = OUTPUT_DIR + "result_%s.json" % _timestamp
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(output, "\t"))
		f.close()
		print("[METRICS] 结果已保存: %s" % path)
	else:
		push_error("[METRICS] 无法写入文件: %s" % path)

	## 控制台总结
	print("")
	print("═══════════════════════════════════════════")
	print("  BENCHMARK RESULT — %s" % _timestamp)
	print("  Overall Score: %.1f / 100" % overall)
	print("───────────────────────────────────────────")
	for r in _scene_results:
		var icon = "✅" if r["total_score"] >= 60 else ("⚠️" if r["total_score"] >= 40 else "❌")
		print("  %s %s: march=%.0f deploy=%.0f total=%.0f" % [
			icon, r["scene_name"],
			r["march_score"], r["deploy_score"], r["total_score"]
		])
	print("═══════════════════════════════════════════")
	print("")
