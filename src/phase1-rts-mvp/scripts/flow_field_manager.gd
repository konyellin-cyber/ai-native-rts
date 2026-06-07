extends Node
class_name FlowFieldManager

## Phase 24 — FlowFieldManager
## 管理多将领的局部流场，供 MassBattleEngine 的 CrowdSimulator 查询。
## 基于 Phase 23 general_unit.gd 的 _update_flow_field / get_flow_direction 逻辑，
## 提取为独立管理器，支持多将领并行流场。
##
## 使用方式：
##   ffm = FlowFieldManager.new()
##   ffm.register_general(0, red_general)
##   ffm.register_general(1, blue_general)
##   ffm.setup(cfg)
##   # 每帧（或由 MBE 调用）：ffm.tick()
##   # 查询：dir = ffm.get_direction(general_id, pos)

## ── 配置 ──────────────────────────────────────────────
var _cell_size:        float = 20.0
var _half_width:       int   = 6       ## 轨迹两侧扩展格数（比 Phase23 大，覆盖更宽战线）
var _update_interval:  int   = 15      ## 每隔多少帧重建一次
var _max_buffer_pts:   int   = 40      ## 最多使用轨迹点数

## ── 数据 ──────────────────────────────────────────────
## _generals[id] → GeneralUnit 节点
var _generals: Dictionary = {}
## _fields[id]   → Dictionary<Vector2i, Vector3>（格子 → 方向）
var _fields: Dictionary = {}
## _march_dirs[id] → Vector3（将领当前行进方向，fallback 用）
var _march_dirs: Dictionary = {}

## 分帧更新：记录上次更新到哪个 general_id
var _update_frame:   int = 0
var _update_round:   int = 0   ## 轮次，对 general 数量取模决定本帧更新哪一个


## ─────────────────────────────────────────────────────
## 初始化
## ─────────────────────────────────────────────────────

func setup(cfg: Dictionary) -> void:
	var mb: Dictionary = cfg.get("mass_battle", {})
	_cell_size       = float(mb.get("flow_field_cell_size",    20.0))
	_half_width      = int(mb.get("flow_field_half_width",     6))
	_update_interval = int(mb.get("flow_field_update_interval", 15))


func register_general(id: int, general: Node) -> void:
	_generals[id]    = general
	_fields[id]      = {}
	_march_dirs[id]  = Vector3(1.0 if id == 0 else -1.0, 0.0, 0.0)


## ─────────────────────────────────────────────────────
## 每帧调用（由 MassBattleEngine._physics_process 前置调用）
## ─────────────────────────────────────────────────────

func tick() -> void:
	_update_frame += 1
	if _update_frame < _update_interval:
		return
	_update_frame = 0

	## 分帧：每次只更新一个将领的流场，避免同帧峰值
	var ids: Array = _generals.keys()
	if ids.is_empty():
		return
	var id: int = ids[_update_round % ids.size()]
	_update_round += 1
	_build_field(id)


## ─────────────────────────────────────────────────────
## 流场构建（参考 general_unit._update_flow_field）
## ─────────────────────────────────────────────────────

func _build_field(id: int) -> void:
	if not _generals.has(id):
		return
	var general: Node = _generals[id]
	if not is_instance_valid(general):
		return

	## 读取将领历史轨迹
	var buf: Array = []
	if general.has_method("get_path_buffer"):
		buf = general.get_path_buffer()
	else:
		## fallback：将领当前位置 + 行进方向构造简单路径
		var pos: Vector3 = general.global_position
		var dir: Vector3 = _march_dirs.get(id, Vector3(1.0, 0.0, 0.0))
		for k in range(8):
			buf.append(pos - dir * float(k) * _cell_size)

	var n: int = buf.size()
	if n < 2:
		## 路径太短，用行进方向填满整个流场所在区域
		_fill_fallback_field(id)
		return

	var use_n: int = min(n, _max_buffer_pts)
	var field: Dictionary = {}
	var cell := _cell_size

	for i in range(use_n - 1):
		var p0: Vector3 = buf[i]       ## 较新点（索引小 = 更近将领）
		var p1: Vector3 = buf[i + 1]   ## 较旧点
		var fwd := Vector3(p0.x - p1.x, 0.0, p0.z - p1.z)
		if fwd.length_squared() < 0.001:
			continue
		fwd = fwd.normalized()
		## 更新行进方向缓存（取最新段方向）
		if i == 0:
			_march_dirs[id] = fwd
		var lat := Vector3(-fwd.z, 0.0, fwd.x)

		var mid := Vector3((p0.x + p1.x) * 0.5, 0.0, (p0.z + p1.z) * 0.5)
		for w in range(-_half_width, _half_width + 1):
			var world_pos := mid + lat * w * cell
			var gx := int(floor(world_pos.x / cell))
			var gz := int(floor(world_pos.z / cell))
			var key := Vector2i(gx, gz)
			if field.has(key):
				## 方向融合：加权平均，让重叠格子更平滑
				field[key] = (field[key] + fwd).normalized()
			else:
				field[key] = fwd

	_fields[id] = field


func _fill_fallback_field(id: int) -> void:
	## 将领静止或路径不足：保持旧流场不变
	## 什么都不做，下次轨迹充足后自动重建
	pass


## ─────────────────────────────────────────────────────
## 查询接口
## ─────────────────────────────────────────────────────

## 查询指定将领流场在 pos 处的方向
## 无数据时退回将领行进方向（fallback）
func get_direction(general_id: int, pos: Vector3) -> Vector3:
	if not _fields.has(general_id):
		## 流场未注册，返回零向量让 MBE fallback 处理
		return Vector3.ZERO

	var field: Dictionary = _fields[general_id]
	if field.is_empty():
		## 流场为空（将领刚出发还没路径），返回零向量让 MBE fallback 处理
		return Vector3.ZERO

	var cell := _cell_size
	var key := Vector2i(int(floor(pos.x / cell)), int(floor(pos.z / cell)))

	if field.has(key):
		return field[key]

	## 最近邻搜索（2 格范围）
	var best_dir: Vector3 = Vector3.ZERO
	var best_dist: float  = INF
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var k := Vector2i(key.x + dx, key.y + dz)
			if field.has(k):
				var d := float(dx * dx + dz * dz)
				if d < best_dist:
					best_dist = d
					best_dir  = field[k]
	return best_dir
