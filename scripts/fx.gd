extends RefCounted
## HARAQ combat effects (blood-free): sand-dust bullet impacts, sparks on metal / soldiers,
## muzzle flash burst, death dust puff. CPUParticles3D so they run on every renderer.

const G := preload("res://scripts/graphics.gd")

static var _dust_mat: StandardMaterial3D
static var _spark_mat: StandardMaterial3D
static var _quad_small: QuadMesh
static var _quad_big: QuadMesh


static func _init_res() -> void:
	if _dust_mat != null:
		return
	_dust_mat = G.particle_material(Color(0.86, 0.76, 0.6, 0.85))
	_spark_mat = G.particle_material(Color(1.0, 0.75, 0.35, 1.0), true)
	_quad_small = QuadMesh.new()
	_quad_small.size = Vector2(0.06, 0.06)
	_quad_big = QuadMesh.new()
	_quad_big.size = Vector2(0.55, 0.55)


## Particles need a real renderer (the headless dummy server spams errors for them).
static func enabled() -> bool:
	return DisplayServer.get_name() != "headless"


static func _burst(parent: Node, pos: Vector3, normal: Vector3, amount: int, mesh: Mesh, mat: Material, life: float, vmin: float, vmax: float, grav: float, spread: float, ramp: Gradient = null, scale_curve: Curve = null) -> CPUParticles3D:
	if not enabled():
		return null
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = life
	p.mesh = mesh
	p.material_override = mat
	p.direction = normal
	p.spread = spread
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = Vector3(0, -grav, 0)
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if ramp:
		p.color_ramp = ramp
	if scale_curve:
		p.scale_amount_curve = scale_curve
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	var t := parent.get_tree().create_timer(life + 0.3)
	t.timeout.connect(p.queue_free)
	return p


static func _fade(c: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, c)
	g.set_color(1, Color(c, 0.0))
	return g


static func _grow(a: float, b: float) -> Curve:
	var c := Curve.new()
	c.max_value = maxf(a, b)
	c.add_point(Vector2(0, a))
	c.add_point(Vector2(1, b))
	return c


## kind: "sand" (ground / walls), "metal" (wrecks), "soldier" (hit marker sparks, no blood).
static func impact(parent: Node, pos: Vector3, normal: Vector3, kind := "sand", detail := 1.0) -> void:
	_init_res()
	if normal.length_squared() < 0.01:
		normal = Vector3.UP
	if kind == "metal" or kind == "soldier":
		_burst(parent, pos, normal, int(10 * detail) + 3, _quad_small, _spark_mat, 0.35, 3.0, 7.0, 9.0, 40.0, _fade(Color(1, 0.8, 0.4)))
	if kind != "soldier" or detail > 0.5:
		_burst(parent, pos, normal, int(8 * detail) + 3, _quad_big, _dust_mat, 0.9, 0.6, 2.2, 1.2, 35.0,
			_fade(Color(0.86, 0.77, 0.62, 0.8) if kind != "soldier" else Color(0.55, 0.5, 0.4, 0.6)), _grow(0.4, 1.0))


static func death_puff(parent: Node, pos: Vector3, detail := 1.0) -> void:
	_init_res()
	_burst(parent, pos + Vector3(0, 0.4, 0), Vector3.UP, int(16 * detail) + 4, _quad_big, _dust_mat, 1.6, 0.8, 2.6, 0.4, 80.0,
		_fade(Color(0.84, 0.75, 0.6, 0.75)), _grow(0.8, 1.0))


## Star-shaped additive flash mesh (two crossed quads) for the end of a barrel.
static func flash_mesh(size := 0.35) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := size * 0.5
	for plane in [Basis(), Basis(Vector3.FORWARD, PI * 0.5)]:
		var b: Basis = plane
		var pts := [Vector3(-s, 0, 0), Vector3(s, 0, 0), Vector3(s, 0, -size * 2.2), Vector3(-s, 0, -size * 2.2)]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uvs[i])
			st.add_vertex(b * pts[i])
	# Front-facing disc.
	var disc := [Vector3(-s, -s, 0), Vector3(s, -s, 0), Vector3(s, s, 0), Vector3(-s, s, 0)]
	var duv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(duv[i])
		st.add_vertex(disc[i] * 1.4)
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1.0, 0.72, 0.35)
	m.albedo_texture = G.soft_dot()
	m.disable_receive_shadows = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi
