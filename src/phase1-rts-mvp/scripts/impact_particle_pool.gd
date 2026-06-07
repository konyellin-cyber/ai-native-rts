extends Node3D
class_name ImpactParticlePool

## Phase 24 — ImpactParticlePool
## 预创建 32 个 GPUParticles3D，复用池，避免运行时实例化开销。
## 红方受击 → 深红色粒子；蓝方受击 → 深蓝色粒子。
## headless 模式下 init() 直接返回，所有方法静默跳过。

const POOL_SIZE: int = 32

var _pool_red:  Array = []   ## Array[GPUParticles3D]
var _pool_blue: Array = []

var _ptr_red:  int = 0
var _ptr_blue: int = 0

var _initialized: bool = false
var _cfg: Dictionary = {}


## ─────────────────────────────────────────────────────
## 初始化
## ─────────────────────────────────────────────────────

func init(headless: bool, cfg: Dictionary = {}) -> void:
	if headless:
		return

	_cfg = cfg
	var blood_color := Color(0.45, 0.01, 0.01, 1.0)
	var red_color: Color = _get_color("hit_particle_red", Color(0.8, 0.05, 0.05, 1.0))
	var blue_color: Color = _get_color("hit_particle_blue", Color(0.1, 0.2, 0.9, 1.0))
	if String(_cfg.get("hit_particle_style", "team")) == "blood":
		red_color = blood_color
		blue_color = blood_color

	_pool_red  = _build_pool(red_color, POOL_SIZE)
	_pool_blue = _build_pool(blue_color, POOL_SIZE)

	for p in _pool_red:
		add_child(p)
	for p in _pool_blue:
		add_child(p)

	_initialized = true
	print("[ImpactParticlePool] init: pool_size=%d style=%s" % [
		POOL_SIZE, String(_cfg.get("hit_particle_style", "team"))])


func _build_pool(color: Color, size: int) -> Array:
	var arr: Array = []
	for _i in range(size):
		var gp := GPUParticles3D.new()
		gp.amount         = int(_cfg.get("hit_particle_amount", 12))
		gp.lifetime       = float(_cfg.get("hit_particle_lifetime", 0.35))
		gp.one_shot       = true
		gp.emitting       = false
		gp.explosiveness  = 0.9   ## 全部粒子在触发时同时喷出
		gp.process_material = _make_particle_material(color)
		gp.draw_pass_1    = _make_particle_mesh(color)
		arr.append(gp)
	return arr


func _make_particle_material(color: Color) -> ParticleProcessMaterial:
	var mat := ParticleProcessMaterial.new()
	## 向上 + 随机方向喷射
	mat.direction           = Vector3(0.0, 1.0, 0.0)
	mat.spread              = float(_cfg.get("hit_particle_spread", 60.0))
	mat.initial_velocity_min = float(_cfg.get("hit_particle_velocity_min", 40.0))
	mat.initial_velocity_max = float(_cfg.get("hit_particle_velocity_max", 100.0))
	mat.gravity             = Vector3(0.0, float(_cfg.get("hit_particle_gravity_y", -120.0)), 0.0)
	mat.color               = color
	mat.scale_min           = float(_cfg.get("hit_particle_scale_min", 2.0))
	mat.scale_max           = float(_cfg.get("hit_particle_scale_max", 4.0))
	return mat


func _make_particle_mesh(color: Color) -> Mesh:
	var sm := SphereMesh.new()
	sm.radius = float(_cfg.get("hit_particle_mesh_radius", 2.0))
	sm.height = float(_cfg.get("hit_particle_mesh_height", 4.0))
	var mat := StandardMaterial3D.new()
	mat.albedo_color  = color
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material       = mat
	return sm


## ─────────────────────────────────────────────────────
## 触发接口（由 CombatResolver 命中回调调用）
## ─────────────────────────────────────────────────────

## team: 0=红方受击，1=蓝方受击
func emit_at(pos: Vector3, team: int) -> void:
	if not _initialized:
		return

	if team == 0:
		_emit_from_pool(_pool_red, _ptr_red, pos)
		_ptr_red = (_ptr_red + 1) % POOL_SIZE
	else:
		_emit_from_pool(_pool_blue, _ptr_blue, pos)
		_ptr_blue = (_ptr_blue + 1) % POOL_SIZE


func _emit_from_pool(pool: Array, ptr: int, pos: Vector3) -> void:
	if pool.is_empty():
		return
	var gp: GPUParticles3D = pool[ptr]
	if not is_instance_valid(gp):
		return
	gp.global_position = pos
	gp.restart()   ## restart() 会重置并立即开始发射（one_shot = true）


func _get_color(key: String, fallback: Color) -> Color:
	var value = _cfg.get(key, null)
	if value is Array and value.size() >= 4:
		return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return fallback
