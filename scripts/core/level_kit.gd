class_name LevelKit
extends RefCounted
## Shared procedural building blocks + environment presets for every map.
## Everything is generated in code (no imported meshes yet) so the project
## stays tiny and builds on GitHub Actions. Swap these for authored .glb
## assets later (see docs/ART_DIRECTION_3D.md) without touching mission logic.

static var _mat_cache := {}

static func mat(color: Color, rough: float = 0.95, metal: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f" % [color.to_html(), rough, metal]
	if _mat_cache.has(key): return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	_mat_cache[key] = m
	return m

static func box(parent: Node3D, pos: Vector3, size: Vector3, material: Material, solid := true) -> Node3D:
	var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
	parent.add_child(root)
	root.position = pos
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = material
	root.add_child(mesh)
	if solid:
		var collider := CollisionShape3D.new()
		var c := BoxShape3D.new()
		c.size = size
		collider.shape = c
		root.add_child(collider)
	return root

static func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, material: Material, solid := false, sides := 16) -> Node3D:
	var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
	parent.add_child(root)
	root.position = pos
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = sides
	mi.mesh = cm
	mi.material_override = material
	root.add_child(mi)
	if solid:
		var col := CollisionShape3D.new()
		var cs := CylinderShape3D.new()
		cs.radius = radius
		cs.height = height
		col.shape = cs
		root.add_child(col)
	return root

static func arabic_sign(parent: Node3D, text: String, pos: Vector3, yaw_deg: float, color := Color(0.12, 0.08, 0.04), size := 80) -> Label3D:
	var s := Label3D.new()
	s.text = text
	s.font_size = size
	s.pixel_size = 0.003
	s.position = pos
	s.rotation_degrees.y = yaw_deg
	s.modulate = color
	s.outline_size = 0
	if ResourceLoader.exists("res://assets/fonts/NotoKufiArabic.ttf"):
		s.font = load("res://assets/fonts/NotoKufiArabic.ttf")
	parent.add_child(s)
	return s

static func palm(parent: Node3D, base: Vector3, height := 4.4) -> void:
	var trunk := mat(Color(0.36, 0.26, 0.16))
	var leaf := mat(Color(0.20, 0.34, 0.16), 0.8)
	for seg in range(5):
		var t := float(seg) / 5.0
		cylinder(parent, base + Vector3(t * 0.4, height * (t + 0.1), 0), 0.24 - t * 0.06, height / 5.0 + 0.05, trunk, seg == 0, 8)
	var top := base + Vector3(0.4, height, 0)
	for k in range(7):
		var frond := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.6, 0.06, 0.55)
		frond.mesh = bm
		frond.material_override = leaf
		frond.position = top
		frond.rotation = Vector3(0, k * TAU / 7.0, deg_to_rad(-22))
		frond.translate_object_local(Vector3(1.2, 0, 0))
		parent.add_child(frond)

static func cart(parent: Node3D, pos: Vector3) -> void:
	var wood := mat(Color(0.31, 0.20, 0.12))
	box(parent, pos + Vector3(0, 0.9, 0), Vector3(3.1, 0.3, 1.6), wood, true)
	box(parent, pos + Vector3(2.3, 0.85, 0.45), Vector3(1.8, 0.08, 0.08), wood, false)
	box(parent, pos + Vector3(2.3, 0.85, -0.45), Vector3(1.8, 0.08, 0.08), wood, false)
	for side in [-1.0, 1.0]:
		var w := cylinder(parent, pos + Vector3(0, 0.7, side * 0.85), 0.65, 0.15, wood, false, 14)
		w.rotation_degrees.x = 90

static func crate_stack(parent: Node3D, pos: Vector3, seed_val: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var wood := mat(Color(0.45, 0.33, 0.2))
	var n := rng.randi_range(1, 4)
	for i in range(n):
		var s := rng.randf_range(0.9, 1.3)
		box(parent, pos + Vector3(rng.randf_range(-0.3, 0.3), s / 2.0 + float(i >> 1) * 1.1, float(i % 2) * 1.2), Vector3(s, s, s), wood, true)

static func dunes(parent: Node3D, seed_val: int, count: int, radius: float, sand: Material) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	for i in range(count):
		var a := rng.randf() * TAU
		var r := radius + rng.randf_range(0, 60)
		var d := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(14, 30)
		sm.height = rng.randf_range(5, 12)
		sm.radial_segments = 24
		sm.rings = 8
		d.mesh = sm
		d.material_override = sand
		d.position = Vector3(cos(a) * r, -1.0, sin(a) * r)
		d.scale = Vector3(1.6, 1.0, 1.0)
		d.rotation.y = rng.randf() * TAU
		parent.add_child(d)

static func impact_puff(parent: Node3D, pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 10
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -6, 0)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.12
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = mat(Color(0.75, 0.65, 0.5))
	p.mesh = sm
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(1.0).timeout.connect(p.queue_free)

## Environment presets: desert_noon, coast_dusk, night_blackout.
static func apply_environment(parent: Node3D, preset: String) -> void:
	var high: bool = Campaign.quality_high
	var env_node := WorldEnvironment.new()
	parent.add_child(env_node)
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0 if high else 60.0
	match preset:
		"coast_dusk":
			sm.sky_top_color = Color(0.23, 0.33, 0.52)
			sm.sky_horizon_color = Color(0.96, 0.62, 0.38)
			sm.ground_horizon_color = Color(0.70, 0.50, 0.36)
			sm.ground_bottom_color = Color(0.20, 0.17, 0.15)
			sun.rotation_degrees = Vector3(-14, 120, 0)
			sun.light_color = Color(1.0, 0.72, 0.48)
			sun.light_energy = 1.25
			e.ambient_light_energy = 0.55
			e.fog_light_color = Color(0.85, 0.62, 0.48)
			e.fog_density = 0.006
		"night_blackout":
			sm.sky_top_color = Color(0.02, 0.03, 0.07)
			sm.sky_horizon_color = Color(0.08, 0.10, 0.16)
			sm.ground_horizon_color = Color(0.05, 0.05, 0.07)
			sm.ground_bottom_color = Color(0.01, 0.01, 0.02)
			sun.rotation_degrees = Vector3(-40, -60, 0)
			sun.light_color = Color(0.55, 0.65, 0.95)
			sun.light_energy = 0.25
			e.ambient_light_energy = 0.25
			e.fog_light_color = Color(0.08, 0.1, 0.16)
			e.fog_density = 0.012
		_:
			sm.sky_top_color = Color(0.32, 0.52, 0.74)
			sm.sky_horizon_color = Color(0.82, 0.78, 0.68)
			sm.ground_horizon_color = Color(0.76, 0.66, 0.5)
			sm.ground_bottom_color = Color(0.45, 0.37, 0.27)
			sun.rotation_degrees = Vector3(-48, -30, 0)
			sun.light_color = Color(1.0, 0.95, 0.85)
			sun.light_energy = 1.05
			e.ambient_light_energy = 0.4
			e.fog_light_color = Color(0.86, 0.78, 0.64)
			e.fog_density = 0.0035
	sm.sun_angle_max = 30.0
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.85 if preset == "desert_noon" else 1.0
	e.fog_enabled = true
	e.fog_sky_affect = 0.35
	e.glow_enabled = high
	e.glow_intensity = 0.6
	e.glow_bloom = 0.08
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.08
	e.adjustment_saturation = 1.05
	env_node.environment = e
	parent.add_child(sun)
