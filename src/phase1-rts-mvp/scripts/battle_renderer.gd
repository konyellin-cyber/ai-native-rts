extends Node3D
class_name BattleRenderer

## Phase 24 — BattleRenderer v3  （Phase23 exact approach）
##
## Phase23 dummy_soldier.gd 精确还原：
##   - 模型：GLB 原始纹理，scale_f=60.4，model.position.y = -capsule_half_h
##   - 圆环：TorusMesh UNSHADED，inner=collision_r*0.55, outer=collision_r*0.85
##           ring.position.y = -capsule_half_h + 1.0
##   - 朝向：velocity XZ + rotate_y(PI) 修正
##
## MultiMesh 里每个实例的 Transform3D.origin 是"胶囊中心"位置（Phase23 CharacterBody3D pos）
## 但 MBE 给的 positions[i] 是地面坐标（y≈0）
## → MultiMesh 模型需要把"脚底偏移" bake 进 Basis 的 origin 偏移
##   模型 y_offset = 0           （模型原点已在脚底，不需要额外偏移）
##   圆环 y_offset = ring_y_rel  （相对胶囊中心的 y，Phase23 = -cap_half_h+1）
##                               在 MultiMesh 中 pos.y=0 是地面，圆环放 y=1.0

const _HIDE_Y: float = -1000.0

## ── Phase23 精确参数 ──────────────────────────────────
## collision_radius = 5.4  (general config: radius=12 × 0.45)
## target_h        = collision_radius × 2.5 = 13.5
## model_native_h  = 0.671  (Kenney Mini 实测)
## dummy_model_scale = 3.0  (config 默认值)
## scale_f = (13.5 / 0.671) × 3.0 ≈ 60.4
## capsule_half_h  = collision_radius × 1.25 = 6.75
## ring y (rel to capsule center) = -capsule_half_h + 1.0 = -5.75
## → 在 MultiMesh（pos.y=地面=0）：ring y = 1.0（稍高于地面）
const _SOLDIER_SCALE:  float = 60.4
const _RING_INNER:     float = 2.97   ## 5.4 × 0.55
const _RING_OUTER:     float = 4.59   ## 5.4 × 0.85
const _RING_Y:         float = 1.0    ## 圆环贴地高度

## model MMI（红蓝各用不同 GLB 素材）
var _red_mmi:  MultiMeshInstance3D = null
var _blue_mmi: MultiMeshInstance3D = null
var _red_mm:   MultiMesh = null
var _blue_mm:  MultiMesh = null

## 从 GLB MeshInstance3D 提取的 surface 材质列表（还原 GLB 原始纹理）
var _glb_surface_materials: Array = []

## ring MMI（UNSHADED 单色）
var _red_ring_mmi:  MultiMeshInstance3D = null
var _blue_ring_mmi: MultiMeshInstance3D = null
var _red_ring_mm:   MultiMesh = null
var _blue_ring_mm:  MultiMesh = null

var _count_per_side: int  = 250
var _is_headless:    bool = false
var _initialized:    bool = false
var _soldier_scale:  float = _SOLDIER_SCALE   ## CapsuleMesh fallback 时设为 1.0


## ─────────────────────────────────────────────────────
## 初始化
## ─────────────────────────────────────────────────────

func init(count_per_side: int, cfg: Dictionary, headless: bool) -> void:
	_is_headless    = headless
	_count_per_side = count_per_side

	if headless:
		return

	var use_glb: bool = bool(cfg.get("mass_battle", {}).get("use_glb_model", true))

	## ── 红方：soldier.glb，蓝方：soldier_b.glb（不同素材区分队伍） ──
	var red_mesh:  Mesh = _load_glb_mesh("res://assets/characters/soldier.glb",   use_glb)
	var blue_mesh: Mesh = _load_glb_mesh("res://assets/characters/soldier_b.glb", use_glb)

	## ── 士兵 MultiMesh（Phase23：无 material_override，GLB 原始纹理） ──
	_red_mmi  = _build_model_mmi(red_mesh,  count_per_side)
	_blue_mmi = _build_model_mmi(blue_mesh, count_per_side)
	add_child(_red_mmi)
	add_child(_blue_mmi)
	_red_mm  = _red_mmi.multimesh
	_blue_mm = _blue_mmi.multimesh

	## ── 地面圆环 MultiMesh（Phase23：UNSHADED，队伍色） ──
	var ring_mesh := _build_ring_mesh()
	_red_ring_mmi  = _build_ring_mmi(ring_mesh, count_per_side, Color(1.0, 0.2, 0.2))
	_blue_ring_mmi = _build_ring_mmi(ring_mesh, count_per_side, Color(0.2, 0.4, 1.0))
	add_child(_red_ring_mmi)
	add_child(_blue_ring_mmi)
	_red_ring_mm  = _red_ring_mmi.multimesh
	_blue_ring_mm = _blue_ring_mmi.multimesh

	_initialized = true
	print("[BattleRenderer] v3 Phase23-exact: scale=%.1f  ring=%.2f~%.2f  mesh=%s" % [
		_soldier_scale, _RING_INNER, _RING_OUTER,
		"GLB" if use_glb else "Capsule"])


func _load_glb_mesh(path: String, use_glb: bool) -> Mesh:
	if use_glb:
		var res = ResourceLoader.load(path)
		if res != null:
			var scene: Node = res.instantiate()
			var all_mi: Array = []
			_collect_mesh_instances(scene, all_mi)

			if all_mi.size() > 0:
				var combined := ArrayMesh.new()
				for mi: MeshInstance3D in all_mi:
					var mesh: Mesh = mi.mesh
					if mesh == null:
						continue
					for s in range(mesh.get_surface_count()):
						var arrays = mesh.surface_get_arrays(s)
						## 材质：优先 MeshInstance3D surface override，其次 Mesh 自带
						var mat = mi.get_surface_override_material(s)
						if mat == null:
							mat = mesh.surface_get_material(s)
						combined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
						if mat != null:
							combined.surface_set_material(combined.get_surface_count() - 1, mat)

				scene.queue_free()
				print("[BattleRenderer] %s → %d MI, %d surfaces" % [
					path.get_file(), all_mi.size(), combined.get_surface_count()])
				return combined
			scene.queue_free()
		push_warning("[BattleRenderer] GLB 加载失败，退回 CapsuleMesh: %s" % path)

	## Fallback
	var c := CapsuleMesh.new()
	c.radius = 4.86
	c.height = 12.15
	_soldier_scale = 1.0
	return c


func _collect_mesh_instances(node: Node, result: Array) -> void:
	if node is MeshInstance3D and node.mesh != null:
		result.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child, result)


## 士兵 MMI：Mesh 已经在 _load_soldier_mesh 里 surface_set_material，直接用
func _build_model_mmi(mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors       = false
	mm.mesh             = mesh
	mm.instance_count   = count

	var hide_tf := Transform3D(Basis.IDENTITY, Vector3(0.0, _HIDE_Y, 0.0))
	for i in range(count):
		mm.set_instance_transform(i, hide_tf)

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	## 不需要再单独赋材质，Mesh.surface_set_material 已经绑定
	return mmi


## 地面圆环 Mesh（Phase23 exact 尺寸）
func _build_ring_mesh() -> Mesh:
	var torus := TorusMesh.new()
	torus.inner_radius  = _RING_INNER
	torus.outer_radius  = _RING_OUTER
	torus.rings         = 8
	torus.ring_segments = 16
	return torus


## 圆环 MMI：UNSHADED 单色
func _build_ring_mmi(mesh: Mesh, count: int, color: Color) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors       = false
	mm.mesh             = mesh
	mm.instance_count   = count

	var hide_tf := Transform3D(Basis.IDENTITY, Vector3(0.0, _HIDE_Y, 0.0))
	for i in range(count):
		mm.set_instance_transform(i, hide_tf)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh         = mm
	mmi.material_override = mat
	return mmi


## ─────────────────────────────────────────────────────
## 每帧更新
## ─────────────────────────────────────────────────────

## Phase23 朝向：velocity XZ + rotate_y(PI)（Kenney GLB 默认朝 +Z，需修正 180°）
func _vel_to_basis(vel: Vector3) -> Basis:
	var vel_xz := Vector3(vel.x, 0.0, vel.z)
	if vel_xz.length_squared() < 100.0:   ## 速度 < 10 units/s 不转向
		return Basis.IDENTITY
	var forward := vel_xz.normalized()
	var right   := Vector3.UP.cross(forward).normalized()
	var up      := forward.cross(right)
	## rotate_y(PI) 修正：negate X 轴和 Z 轴
	return Basis(-right, up, forward)


func update(
		positions:  PackedVector3Array,
		velocities: PackedVector3Array,
		states:     PackedInt32Array,
		_teams:     PackedInt32Array,
		count_per_side: int,
		_stun_frames: PackedInt32Array = PackedInt32Array()) -> void:

	if not _initialized:
		return

	var s := _soldier_scale
	var hide_model := Transform3D(Basis.IDENTITY.scaled(Vector3(s, s, s)), Vector3(0.0, _HIDE_Y, 0.0))
	var hide_ring  := Transform3D(Basis.IDENTITY, Vector3(0.0, _HIDE_Y, 0.0))

	for i in range(count_per_side):
		## ── 红方 ──
		var ri: int = i
		if states[ri] == 2:  ## DEAD
			_red_mm.set_instance_transform(i, hide_model)
			_red_ring_mm.set_instance_transform(i, hide_ring)
		else:
			var pos := positions[ri]
			var vel := velocities[ri]
			## 模型：origin = 地面坐标（y=0），scale + 朝向 bake 进 Basis
			var rot_b := _vel_to_basis(vel)
			var model_b := rot_b.scaled(Vector3(s, s, s))
			_red_mm.set_instance_transform(i,
				Transform3D(model_b, Vector3(pos.x, 0.0, pos.z)))
			## 圆环：y=_RING_Y 稍高于地面（Phase23: -cap_half_h+1 ≈ 贴地）
			_red_ring_mm.set_instance_transform(i,
				Transform3D(Basis.IDENTITY, Vector3(pos.x, _RING_Y, pos.z)))

		## ── 蓝方 ──
		var bi: int = count_per_side + i
		if states[bi] == 2:
			_blue_mm.set_instance_transform(i, hide_model)
			_blue_ring_mm.set_instance_transform(i, hide_ring)
		else:
			var pos := positions[bi]
			var vel := velocities[bi]
			var rot_b := _vel_to_basis(vel)
			var model_b := rot_b.scaled(Vector3(s, s, s))
			_blue_mm.set_instance_transform(i,
				Transform3D(model_b, Vector3(pos.x, 0.0, pos.z)))
			_blue_ring_mm.set_instance_transform(i,
				Transform3D(Basis.IDENTITY, Vector3(pos.x, _RING_Y, pos.z)))
