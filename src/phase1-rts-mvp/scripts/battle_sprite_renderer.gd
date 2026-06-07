extends Node3D
class_name BattleSpriteRenderer

## Phase 25 — 2.5D sprite renderer for MassBattleEngine.
## Keeps the Phase 24 MultiMesh contract, but draws camera-facing 2D quads.

const _HIDE_Y: float = -1000.0

const _SPRITE_W: float = 52.0
const _SPRITE_H: float = 52.0
const _RING_INNER: float = 2.97
const _RING_OUTER: float = 4.59
const _RING_Y: float = 1.0
const _CORPSE_DENSITY: float = 0.70

var _red_mmi: MultiMeshInstance3D = null
var _blue_mmi: MultiMeshInstance3D = null
var _red_mm: MultiMesh = null
var _blue_mm: MultiMesh = null

var _red_corpse_mmi: MultiMeshInstance3D = null
var _blue_corpse_mmi: MultiMeshInstance3D = null
var _red_corpse_mm: MultiMesh = null
var _blue_corpse_mm: MultiMesh = null

var _red_ring_mmi: MultiMeshInstance3D = null
var _blue_ring_mmi: MultiMeshInstance3D = null
var _red_ring_mm: MultiMesh = null
var _blue_ring_mm: MultiMesh = null

var _count_per_side: int = 250
var _is_headless: bool = false
var _initialized: bool = false
var _frame: int = 0

var _sprite_basis: Basis = Basis.IDENTITY
var _atlas_columns: int = 6
var _atlas_rows: int = 4
var _atlas_frame_max: int = 23
var _run_start: int = 0
var _run_count: int = 6
var _attack_start: int = 6
var _attack_count: int = 6
var _hit_start: int = 12
var _hit_count: int = 6
var _death_start: int = 18
var _death_count: int = 6
var _death_hold_frames: Array[int] = [19, 20, 22, 23]
var _use_atlas: bool = false
var _show_rings: bool = false


func init(count_per_side: int, cfg: Dictionary, headless: bool) -> void:
	_is_headless = headless
	_count_per_side = count_per_side
	if headless:
		return

	_sprite_basis = _make_sprite_basis()
	var mb: Dictionary = cfg.get("mass_battle", {})
	_atlas_columns = int(mb.get("sprite_atlas_columns", 6))
	_atlas_rows = int(mb.get("sprite_atlas_rows", 4))
	_atlas_frame_max = int(mb.get("sprite_atlas_frame_max", max(0, _atlas_columns * _atlas_rows - 1)))
	_run_start = int(mb.get("sprite_run_start", 0))
	_run_count = max(1, int(mb.get("sprite_run_count", min(6, _atlas_columns))))
	_attack_start = int(mb.get("sprite_attack_start", _atlas_columns))
	_attack_count = max(1, int(mb.get("sprite_attack_count", min(6, _atlas_columns))))
	_hit_start = int(mb.get("sprite_hit_start", _atlas_columns * 2))
	_hit_count = max(1, int(mb.get("sprite_hit_count", min(6, _atlas_columns))))
	_death_start = int(mb.get("sprite_death_start", _atlas_columns * 3))
	_death_count = max(1, int(mb.get("sprite_death_count", min(6, _atlas_columns))))
	_death_hold_frames = _parse_int_array(mb.get("sprite_death_hold_frames", []))
	if _death_hold_frames.is_empty():
		_death_hold_frames = _default_death_hold_frames()
	var red_atlas_path: String = String(mb.get("sprite_red_atlas", ""))
	var blue_atlas_path: String = String(mb.get("sprite_blue_atlas", ""))
	_show_rings = bool(mb.get("sprite_show_rings", false))
	var red_atlas: Texture2D = _load_png_texture(red_atlas_path)
	var blue_atlas: Texture2D = _load_png_texture(blue_atlas_path)
	_use_atlas = red_atlas != null and blue_atlas != null

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)

	_red_corpse_mmi = _build_sprite_mmi(quad, count_per_side,
		Color(0.62, 0.10, 0.08), Color(0.88, 0.72, 0.46), red_atlas, true)
	_blue_corpse_mmi = _build_sprite_mmi(quad, count_per_side,
		Color(0.12, 0.22, 0.62), Color(0.70, 0.74, 0.86), blue_atlas, true)
	_red_mmi = _build_sprite_mmi(quad, count_per_side,
		Color(0.62, 0.10, 0.08), Color(0.88, 0.72, 0.46), red_atlas, false)
	_blue_mmi = _build_sprite_mmi(quad, count_per_side,
		Color(0.12, 0.22, 0.62), Color(0.70, 0.74, 0.86), blue_atlas, false)
	add_child(_red_corpse_mmi)
	add_child(_blue_corpse_mmi)
	add_child(_red_mmi)
	add_child(_blue_mmi)
	_red_corpse_mm = _red_corpse_mmi.multimesh
	_blue_corpse_mm = _blue_corpse_mmi.multimesh
	_red_mm = _red_mmi.multimesh
	_blue_mm = _blue_mmi.multimesh

	var ring_mesh := _build_ring_mesh()
	_red_ring_mmi = _build_ring_mmi(ring_mesh, count_per_side, Color(1.0, 0.2, 0.2))
	_blue_ring_mmi = _build_ring_mmi(ring_mesh, count_per_side, Color(0.2, 0.4, 1.0))
	if _show_rings:
		add_child(_red_ring_mmi)
		add_child(_blue_ring_mmi)
	_red_ring_mm = _red_ring_mmi.multimesh
	_blue_ring_mm = _blue_ring_mmi.multimesh

	_initialized = true
	print("[BattleSpriteRenderer] Phase25 sprite2d: count_per_side=%d atlas=%s %dx%d frame_max=%d rings=%s" % [
		count_per_side, str(_use_atlas), _atlas_columns, _atlas_rows, _atlas_frame_max, str(_show_rings)])


func _make_sprite_basis() -> Basis:
	## Camera in mass_battle is rot(-45, -45, 0). This upright billboard plane
	## faces that camera while keeping sprite height on world Y.
	var normal := Vector3(-1.0, 0.0, 1.0).normalized()
	var x_axis := Vector3.UP.cross(normal).normalized()
	var y_axis := Vector3.UP
	return Basis(x_axis, y_axis, normal)


func _load_png_texture(path: String) -> Texture2D:
	if path == "":
		return null
	var img := Image.new()
	var err := img.load(path)
	if err != OK:
		push_warning("[BattleSpriteRenderer] atlas load failed: %s err=%d" % [path, err])
		return null
	return ImageTexture.create_from_image(img)


func _build_sprite_mmi(
		mesh: Mesh,
		count: int,
		tunic: Color,
		accent: Color,
		atlas: Texture2D,
		flat_corpse: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count

	var hide_basis := _sprite_basis
	var hide_tf := Transform3D(hide_basis.scaled(Vector3(_SPRITE_W, _SPRITE_H, 1.0)),
		Vector3(0.0, _HIDE_Y, 0.0))
	for i in range(count):
		mm.set_instance_transform(i, hide_tf)
		mm.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, 1.0))

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _make_sprite_material(tunic, accent, atlas, flat_corpse)
	return mmi


func _make_sprite_material(tunic: Color, accent: Color, atlas: Texture2D, flat_corpse: bool) -> ShaderMaterial:
	var shader := Shader.new()
	if atlas != null:
		shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;

uniform sampler2D atlas_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform float atlas_columns = 6.0;
uniform float atlas_rows = 4.0;
uniform float atlas_frame_max = 23.0;
uniform float color_scale = 1.0;

varying float v_hit;
varying float v_frame;

void vertex() {
	v_hit = INSTANCE_CUSTOM.g;
	v_frame = INSTANCE_CUSTOM.b;
}

void fragment() {
	float frame_index = floor(clamp(v_frame, 0.0, 1.0) * atlas_frame_max + 0.5);
	float col = mod(frame_index, atlas_columns);
	float row = floor(frame_index / atlas_columns);
	vec2 atlas_uv = vec2((col + UV.x) / atlas_columns, (row + UV.y) / atlas_rows);
	vec4 tex = texture(atlas_texture, atlas_uv);
	if (tex.a < 0.08) {
		discard;
	}
	vec3 color = mix(tex.rgb, vec3(0.42, 0.02, 0.015), clamp(v_hit, 0.0, 1.0) * 0.18);
	ALBEDO = color * color_scale;
	ALPHA = 1.0;
}
"""
	else:
		shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 tunic_color : source_color;
uniform vec4 accent_color : source_color;
uniform vec4 metal_color : source_color;
uniform vec4 leather_color : source_color;

varying float v_hit;
varying float v_phase;

void vertex() {
	v_phase = INSTANCE_CUSTOM.r;
	v_hit = INSTANCE_CUSTOM.g;
}

void fragment() {
	vec2 p = UV;
	vec3 col = vec3(0.0);
	bool mask = false;

	float bob = (v_phase - 0.5) * 0.018;

	if (distance(p, vec2(0.50, 0.18 + bob)) < 0.080) {
		mask = true;
		col = metal_color.rgb;
	}
	if (abs(p.x - 0.50) < 0.120 && p.y > 0.27 + bob && p.y < 0.66 + bob) {
		mask = true;
		col = tunic_color.rgb;
	}
	if (distance(p, vec2(0.39, 0.48 + bob)) < 0.095) {
		mask = true;
		col = accent_color.rgb * 0.85;
	}
	if (abs((p.x - 0.68) + (p.y - 0.48) * 0.18) < 0.018 && p.y > 0.16 && p.y < 0.92) {
		mask = true;
		col = leather_color.rgb;
	}
	if ((abs(p.x - 0.45) < 0.045 || abs(p.x - 0.56) < 0.045) && p.y > 0.64 + bob && p.y < 0.86 + bob) {
		mask = true;
		col = leather_color.rgb * 0.8;
	}

	if (!mask) {
		discard;
	}

	col = mix(col, vec3(0.42, 0.02, 0.015), clamp(v_hit, 0.0, 1.0) * 0.18);
	ALBEDO = col;
	ALPHA = 1.0;
}
"""

	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.render_priority = -10 if flat_corpse else 0
	if atlas != null:
		mat.set_shader_parameter("atlas_texture", atlas)
		mat.set_shader_parameter("atlas_columns", float(_atlas_columns))
		mat.set_shader_parameter("atlas_rows", float(_atlas_rows))
		mat.set_shader_parameter("atlas_frame_max", float(_atlas_frame_max))
		mat.set_shader_parameter("color_scale", 0.92 if flat_corpse else 1.0)
	else:
		mat.set_shader_parameter("tunic_color", tunic)
		mat.set_shader_parameter("accent_color", accent)
		mat.set_shader_parameter("metal_color", Color(0.55, 0.56, 0.58))
		mat.set_shader_parameter("leather_color", Color(0.24, 0.15, 0.08))
	return mat


func _build_ring_mesh() -> Mesh:
	var torus := TorusMesh.new()
	torus.inner_radius = _RING_INNER
	torus.outer_radius = _RING_OUTER
	torus.rings = 8
	torus.ring_segments = 16
	return torus


func _build_ring_mmi(mesh: Mesh, count: int, color: Color) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count

	var hide_tf := Transform3D(Basis.IDENTITY, Vector3(0.0, _HIDE_Y, 0.0))
	for i in range(count):
		mm.set_instance_transform(i, hide_tf)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	return mmi


func update(
		positions: PackedVector3Array,
		velocities: PackedVector3Array,
		states: PackedInt32Array,
		_teams: PackedInt32Array,
		count_per_side: int,
		stun_frames: PackedInt32Array = PackedInt32Array()) -> void:

	if not _initialized:
		return

	_frame += 1
	var hide_sprite := Transform3D(_sprite_basis.scaled(Vector3(_SPRITE_W, _SPRITE_H, 1.0)),
		Vector3(0.0, _HIDE_Y, 0.0))
	var hide_corpse := Transform3D(_sprite_basis.scaled(Vector3(_SPRITE_W, _SPRITE_H, 1.0)),
		Vector3(0.0, _HIDE_Y, 0.0))
	var hide_ring := Transform3D(Basis.IDENTITY, Vector3(0.0, _HIDE_Y, 0.0))

	for i in range(count_per_side):
		var ri: int = i
		_update_one(_red_mm, _red_corpse_mm, _red_ring_mm, i, ri, positions, velocities, states, stun_frames,
			hide_sprite, hide_corpse, hide_ring)

		var bi: int = count_per_side + i
		_update_one(_blue_mm, _blue_corpse_mm, _blue_ring_mm, i, bi, positions, velocities, states, stun_frames,
			hide_sprite, hide_corpse, hide_ring)


func _update_one(
		model_mm: MultiMesh,
		corpse_mm: MultiMesh,
		ring_mm: MultiMesh,
		instance_idx: int,
		soldier_idx: int,
		positions: PackedVector3Array,
		velocities: PackedVector3Array,
		states: PackedInt32Array,
		stun_frames: PackedInt32Array,
		hide_sprite: Transform3D,
		hide_corpse: Transform3D,
		hide_ring: Transform3D) -> void:

	if states[soldier_idx] == 2:
		model_mm.set_instance_transform(instance_idx, hide_sprite)
		var corpse_frame: int = _pick_corpse_frame(soldier_idx)
		if _seed01(soldier_idx, 419) < _CORPSE_DENSITY:
			corpse_mm.set_instance_transform(instance_idx,
				_transform_for_corpse(positions[soldier_idx], soldier_idx))
			corpse_mm.set_instance_custom_data(instance_idx, Color(0.0, 0.0, _encode_frame(corpse_frame), 1.0))
		else:
			corpse_mm.set_instance_transform(instance_idx, hide_corpse)
			corpse_mm.set_instance_custom_data(instance_idx, Color(0.0, 0.0, _encode_frame(corpse_frame), 1.0))
		if _show_rings:
			ring_mm.set_instance_transform(instance_idx, hide_ring)
		model_mm.set_instance_custom_data(instance_idx, Color(0.0, 0.0, _encode_frame(_death_start), 1.0))
		return

	var pos: Vector3 = positions[soldier_idx]
	var vel: Vector3 = velocities[soldier_idx]
	var speed: float = Vector2(vel.x, vel.z).length()
	var walking: float = clamp(speed / 120.0, 0.0, 1.0)
	var phase: float = 0.5 + sin(float(_frame + soldier_idx * 3) * 0.28) * 0.5 * walking

	var stun := 0
	if not stun_frames.is_empty() and soldier_idx < stun_frames.size():
		stun = stun_frames[soldier_idx]
	var hit: float = 1.0 if stun > 0 else 0.0
	var anim_frame: int = _pick_anim_frame(soldier_idx, speed, hit, stun)

	var squash: float = 1.0 + 0.05 * walking + _seed01(soldier_idx, 17) * 0.035
	var stretch: float = 1.0 + (phase - 0.5) * 0.06 * walking + _seed01(soldier_idx, 23) * 0.025
	if hit > 0.0:
		squash = 1.08 + _seed01(soldier_idx, 31) * 0.08
		stretch = 0.88 + _seed01(soldier_idx, 37) * 0.06

	model_mm.set_instance_transform(instance_idx, _transform_for_sprite(pos, soldier_idx, squash, stretch))
	model_mm.set_instance_custom_data(instance_idx, Color(phase, hit, _encode_frame(anim_frame), 1.0))
	corpse_mm.set_instance_transform(instance_idx, hide_corpse)
	corpse_mm.set_instance_custom_data(instance_idx, Color(0.0, 0.0, _encode_frame(_death_start), 1.0))

	if _show_rings:
		ring_mm.set_instance_transform(instance_idx,
			Transform3D(Basis.IDENTITY, Vector3(pos.x, _RING_Y, pos.z)))


func _transform_for_sprite(pos: Vector3, soldier_idx: int, squash: float, stretch: float) -> Transform3D:
	var basis: Basis = _sprite_basis.scaled(Vector3(_SPRITE_W * squash, _SPRITE_H * stretch, 1.0))
	var y: float = (_SPRITE_H * stretch) * 0.5
	var jitter_x: float = (_seed01(soldier_idx, 101) - 0.5) * 1.6
	var jitter_z: float = (_seed01(soldier_idx, 103) - 0.5) * 1.6
	return Transform3D(basis, Vector3(pos.x + jitter_x, y, pos.z + jitter_z))


func _transform_for_corpse(pos: Vector3, soldier_idx: int) -> Transform3D:
	var scale: float = 0.70 + _seed01(soldier_idx, 211) * 0.08
	var basis: Basis = _sprite_basis.scaled(Vector3(_SPRITE_W * scale, _SPRITE_H * scale, 1.0))
	var jitter_x: float = (_seed01(soldier_idx, 213) - 0.5) * 3.0
	var jitter_z: float = (_seed01(soldier_idx, 217) - 0.5) * 3.0
	var y: float = (_SPRITE_H * scale) * 0.34
	return Transform3D(basis, Vector3(pos.x + jitter_x, y, pos.z + jitter_z))


func _pick_corpse_frame(soldier_idx: int) -> int:
	var idx: int = int(_seed01(soldier_idx, 421) * float(_death_hold_frames.size()))
	idx = clampi(idx, 0, _death_hold_frames.size() - 1)
	return _death_hold_frames[idx]


func _pick_anim_frame(soldier_idx: int, speed: float, hit: float, stun: int) -> int:
	var tempo: int = 5 + int(_seed01(soldier_idx, 307) * 4.0)
	var phase_offset: int = int(_seed01(soldier_idx, 311) * 31.0)
	var run_frame: int = int((_frame + phase_offset) / tempo) % _run_count
	var attack_frame: int = int((_frame + phase_offset) / tempo) % _attack_count
	var hit_frame: int = int((_frame + phase_offset + stun + int(_seed01(soldier_idx, 313) * 3.0)) / tempo) % _hit_count
	if hit > 0.0:
		return _hit_start + hit_frame
	var brace_bias: float = _seed01(soldier_idx, 317)
	if speed < 35.0 or (speed < 85.0 and brace_bias > 0.45):
		return _attack_start + attack_frame
	if speed >= 85.0 and brace_bias > 0.86 and run_frame >= int(float(_run_count) * 0.66):
		return _attack_start + attack_frame
	return _run_start + run_frame


func _encode_frame(frame_idx: int) -> float:
	if _atlas_frame_max <= 0:
		return 0.0
	return clamp(float(frame_idx) / float(_atlas_frame_max), 0.0, 1.0)


func _parse_int_array(value: Variant) -> Array[int]:
	var out: Array[int] = []
	if value is Array:
		for item in value:
			out.append(clampi(int(item), 0, _atlas_frame_max))
	return out


func _default_death_hold_frames() -> Array[int]:
	var out: Array[int] = []
	var first_hold: int = _death_start + min(1, max(0, _death_count - 1))
	for i in range(first_hold, _death_start + _death_count):
		out.append(clampi(i, 0, _atlas_frame_max))
	if out.is_empty():
		out.append(clampi(_death_start, 0, _atlas_frame_max))
	return out


func _seed01(idx: int, salt: int) -> float:
	var n: int = idx * 1103515245 + salt * 12345
	n = (n ^ (n >> 16)) & 0x7fffffff
	return float(n % 10000) / 9999.0
