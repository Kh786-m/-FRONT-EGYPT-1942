extends RefCounted
## HARAQ graphics helpers: quality presets (Low / Medium / High) saved to user://settings.cfg,
## and a small cached factory for the CC0 PBR materials in res://assets/textures.

const SETTINGS_PATH := "user://settings.cfg"

enum Quality { LOW, MEDIUM, HIGH }

const NAMES := ["LOW", "MEDIUM", "HIGH"]
const NAMES_AR := ["منخفض", "متوسط", "عالي"]

## Per-preset knobs. "scale_mobile" is the 3D render scale used on phones.
const PRESETS := {
	Quality.LOW: {
		"shadows": false, "shadow_distance": 0.0, "shadow_atlas": 1024, "shadow_mode": 0,
		"glow": false, "msaa": Viewport.MSAA_DISABLED, "scale": 0.8, "scale_mobile": 0.7,
		"far": 200.0, "fog_density": 0.009, "detail": 0.35, "smoke": false, "lod_bias": 0.5,
	},
	Quality.MEDIUM: {
		"shadows": true, "shadow_distance": 45.0, "shadow_atlas": 2048, "shadow_mode": 1,
		"glow": true, "msaa": Viewport.MSAA_2X, "scale": 1.0, "scale_mobile": 0.85,
		"far": 340.0, "fog_density": 0.005, "detail": 0.7, "smoke": true, "lod_bias": 1.0,
	},
	Quality.HIGH: {
		"shadows": true, "shadow_distance": 90.0, "shadow_atlas": 4096, "shadow_mode": 2,
		"glow": true, "msaa": Viewport.MSAA_4X, "scale": 1.0, "scale_mobile": 1.0,
		"far": 520.0, "fog_density": 0.0038, "detail": 1.0, "smoke": true, "lod_bias": 1.5,
	},
}

static var _tex_cache := {}
static var _mat_cache := {}


static func default_quality() -> int:
	return Quality.MEDIUM if OS.has_feature("mobile") else Quality.HIGH


static func load_quality() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return default_quality()
	return clampi(int(cfg.get_value("graphics", "quality", default_quality())), 0, 2)


static func save_quality(q: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("graphics", "quality", clampi(q, 0, 2))
	cfg.save(SETTINGS_PATH)


static func preset(q: int) -> Dictionary:
	return PRESETS[clampi(q, 0, 2)]


static func tex(name: String) -> Texture2D:
	if not _tex_cache.has(name):
		_tex_cache[name] = load("res://assets/textures/%s.jpg" % name)
	return _tex_cache[name]


## PBR material from one of the bundled CC0 textures (albedo + normal), tinted and optionally
## world-triplanar (no UV seams on procedural boxes / rocks).
static func pbr(tex_name: String, tint: Color = Color.WHITE, uv_scale: float = 1.0, triplanar := true, rough: float = 0.9, metal: float = 0.0, normal_strength: float = 1.0, world := true) -> StandardMaterial3D:
	var key := "%s|%s|%.3f|%s|%.2f|%.2f|%.2f|%s" % [tex_name, tint.to_html(), uv_scale, triplanar, rough, metal, normal_strength, world]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex(tex_name + "_albedo")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = tex(tex_name + "_normal")
	m.normal_scale = normal_strength
	m.roughness = rough
	m.metallic = metal
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if triplanar:
		m.uv1_triplanar = true
		m.uv1_world_triplanar = world
		m.uv1_triplanar_sharpness = 4.0
		m.uv1_scale = Vector3.ONE * uv_scale
	else:
		m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	_mat_cache[key] = m
	return m


static func flat(color: Color, rough: float = 0.9, metal: float = 0.0) -> StandardMaterial3D:
	var key := "flat|%s|%.2f|%.2f" % [color.to_html(), rough, metal]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	_mat_cache[key] = m
	return m


## Soft round sprite (for dust, smoke and muzzle flash billboards).
static func soft_dot() -> Texture2D:
	if _tex_cache.has("_soft_dot"):
		return _tex_cache["_soft_dot"]
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.55))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 64
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	_tex_cache["_soft_dot"] = t
	return t


static func particle_material(color: Color, additive := false, tex: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.albedo_texture = tex if tex != null else soft_dot()
	m.disable_receive_shadows = true
	return m
