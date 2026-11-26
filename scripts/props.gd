extends RefCounted
## HARAQ procedural set dressing for El Alamein 1942: boulders, camel-thorn bushes, concertina
## wire, sandbag walls, wrecked tanks and trucks, date palms, smoke plumes. Everything is built
## from code (no external models) and textured with the bundled CC0 PBR textures.

const G := preload("res://scripts/graphics.gd")
const Terrain := preload("res://scripts/terrain.gd")

const SAND := Color("#E4D2B0")
const KHAKI := Color("#8A7048")
const INK := Color("#1A1612")
const BONE := Color("#F3E6D0")
const BRASS := Color("#C6A15B")
const EMBER := Color("#E24A1B")

static var _rock_noise: FastNoiseLite
static var _bush_tex: ImageTexture
static var _frond_tex: ImageTexture
static var _bag_mesh: Mesh
static var _last_rock_points := PackedVector3Array()


# ---------------------------------------------------------------- rocks
## Irregular faceted boulder with the given footprint/height baked into the mesh.
static func rock_mesh(size: Vector3, seed_v: int) -> ArrayMesh:
	if _rock_noise == null:
		_rock_noise = FastNoiseLite.new()
		_rock_noise.frequency = 0.9
		_rock_noise.fractal_octaves = 3
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 12
	sphere.rings = 7
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var off := Vector3(seed_v * 3.17, seed_v * 1.71, seed_v * 2.33)
	for i in range(verts.size()):
		var v := verts[i]
		var n := v.normalized()
		var disp := 1.0 + _rock_noise.get_noise_3dv(v * 2.0 + off) * 0.55
		v = n * 0.5 * disp
		# Flat-ish bottom so it sits in the sand, slightly flattened top.
		v.y = maxf(v.y, -0.32)
		if v.y > 0.3:
			v.y = 0.3 + (v.y - 0.3) * 0.6
		verts[i] = Vector3(v.x * size.x, (v.y + 0.32) * size.y / 0.62, v.z * size.z)
	_last_rock_points = verts
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in idx:
		st.add_vertex(verts[i])
	st.generate_normals()
	return st.commit()


static func add_rock(parent: Node3D, pos: Vector3, size: Vector3, seed_v: int, yaw: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	parent.add_child(body)
	body.position = pos
	body.rotation.y = yaw
	var mesh := rock_mesh(size, seed_v)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var tint := Color(0.92, 0.84, 0.74).lerp(SAND, float(seed_v % 5) * 0.08)
	mi.material_override = G.pbr("rock", tint, 0.35, true, 0.95)
	body.add_child(mi)
	var col := CollisionShape3D.new()
	# Built from the vertex list directly (works with the headless/dummy renderer too).
	var shape := ConvexPolygonShape3D.new()
	shape.points = _last_rock_points
	col.shape = shape
	body.add_child(col)
	return body


# ---------------------------------------------------------------- camel thorn
static func _bush_texture() -> ImageTexture:
	if _bush_tex != null:
		return _bush_tex
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for b in range(46):
		var p := Vector2(s * 0.5 + rng.randf_range(-10, 10), s - 2)
		var dir := Vector2(rng.randf_range(-0.9, 0.9), -1.0).normalized()
		var length := rng.randi_range(40, 110)
		for k in range(length):
			p += dir * 1.0
			dir = (dir + Vector2(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.05, 0.08))).normalized()
			if p.x < 1 or p.x >= s - 1 or p.y < 1 or p.y >= s - 1:
				break
			var c := Color(0.30, 0.22, 0.14, 1.0).lerp(Color(0.45, 0.38, 0.24), float(k) / length)
			img.set_pixelv(Vector2i(p), c)
			if k > 10 and rng.randf() < 0.22:
				var leaf := Color(0.42, 0.45, 0.28).lerp(Color(0.62, 0.56, 0.36), rng.randf())
				for o in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
					var q: Vector2i = Vector2i(p) + o + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2))
					if q.x >= 0 and q.x < s and q.y >= 0 and q.y < s:
						img.set_pixelv(q, leaf)
	img.generate_mipmaps()
	_bush_tex = ImageTexture.create_from_image(img)
	return _bush_tex


static func _cross_quads(width: float, height: float, planes := 3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in range(planes):
		var a := PI * float(p) / planes
		var dx := Vector3(cos(a), 0, sin(a)) * width * 0.5
		var n := Vector3(-sin(a), 0.6, cos(a)).normalized()
		var v0 := -dx
		var v1 := dx
		var v2 := dx + Vector3(0, height, 0)
		var v3 := -dx + Vector3(0, height, 0)
		for tri in [[v0, Vector2(0, 1)], [v1, Vector2(1, 1)], [v2, Vector2(1, 0)], [v0, Vector2(0, 1)], [v2, Vector2(1, 0)], [v3, Vector2(0, 0)]]:
			st.set_normal(n)
			st.set_uv(tri[1])
			st.add_vertex(tri[0])
	return st.commit()


## Scatter camel-thorn bushes with one MultiMesh (one draw call).
static func scatter_bushes(parent: Node3D, count: int, is_clear: Callable, seed_v := 33) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _cross_quads(1.6, 1.0)
	mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 8:
		tries += 1
		var x := rng.randf_range(-160, 160)
		var z := rng.randf_range(-95, 160)
		if absf(x) < 88 and absf(z) < 88 and not is_clear.call(Vector3(x, 0, z)):
			continue
		if z - Terrain.shore_z(x) < 6.0 or Terrain.flat_mask(x, z) > 0.5:
			continue
		var s := rng.randf_range(0.6, 1.5)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.7, 1.1), s))
		mm.set_instance_transform(placed, Transform3D(basis, Vector3(x, Terrain.height(x, z) - 0.05, z)))
		mm.set_instance_color(placed, Color(1, 1, 1).lerp(Color(0.8, 0.85, 0.65), rng.randf()))
		placed += 1
	mm.visible_instance_count = placed
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.albedo_texture = _bush_texture()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mmi.material_override = m
	parent.add_child(mmi)
	return mmi


# ---------------------------------------------------------------- sandbags
static func _sandbag_mesh() -> Mesh:
	if _bag_mesh != null:
		return _bag_mesh
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 10
	s.rings = 5
	var arrays := s.get_mesh_arrays()
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in range(v.size()):
		var p := v[i]
		# Pillow shape: squash the ends of a sphere into a filled sack.
		p = Vector3(signf(p.x) * pow(absf(p.x) * 2.0, 0.6) * 0.5, p.y, signf(p.z) * pow(absf(p.z) * 2.0, 0.7) * 0.5)
		v[i] = Vector3(p.x * 0.62, p.y * 0.24, p.z * 0.34)
		n[i] = Vector3(n[i].x / 0.62, n[i].y / 0.24, n[i].z / 0.34).normalized()
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_bag_mesh = m
	return m


## Returns transforms of sandbags for a straight wall from a to b (layers high).
static func sandbag_wall_transforms(a: Vector3, b: Vector3, layers := 3) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var dir := (b - a)
	dir.y = 0
	var length := dir.length()
	dir = dir.normalized()
	var yaw := atan2(dir.x, dir.z) + PI * 0.5
	var count := maxi(1, int(length / 0.6))
	for layer in range(layers):
		var shift := 0.3 if layer % 2 == 1 else 0.0
		for i in range(count):
			var t := (float(i) * 0.6 + shift + 0.3)
			if t > length:
				continue
			var p := a + dir * t
			var y := Terrain.height(p.x, p.z) + 0.1 + layer * 0.21
			var basis := Basis(Vector3.UP, yaw + randf_range(-0.08, 0.08))
			out.append(Transform3D(basis, Vector3(p.x, y, p.z)))
	return out


static func sandbag_multimesh(parent: Node3D, transforms: Array[Transform3D]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _sandbag_mesh()
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = G.pbr("burlap", Color(0.93, 0.82, 0.62), 1.4, true, 1.0, 0.0, 1.2)
	parent.add_child(mmi)
	return mmi


# ---------------------------------------------------------------- concertina wire
static func wire_mesh(length: float, radius := 0.42, pitch := 0.28) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := int(length / pitch * 10.0)
	var tube := 0.012
	var prev: Array = []
	for i in range(steps + 1):
		var t := float(i) / 10.0
		var ang := t * TAU
		var c := Vector3(t * pitch, radius + sin(ang) * radius * 0.9, cos(ang) * radius)
		var ring: Array = []
		for k in range(3):
			var a := TAU * k / 3.0
			ring.append(c + Vector3(0, cos(a), sin(a)) * tube)
		if not prev.is_empty():
			for k in range(3):
				var k2 := (k + 1) % 3
				for v in [prev[k], ring[k], ring[k2], prev[k], ring[k2], prev[k2]]:
					st.add_vertex(v)
		prev = ring
	st.generate_normals()
	return st.commit()


static func add_wire(parent: Node3D, a: Vector3, b: Vector3) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	var d := b - a
	d.y = 0
	var length := d.length()
	root.position = Vector3(a.x, Terrain.height(a.x, a.z) - 0.05, a.z)
	root.rotation.y = atan2(-d.z, d.x)
	var wire := MeshInstance3D.new()
	wire.mesh = wire_mesh(length)
	wire.material_override = G.flat(Color(0.24, 0.2, 0.17), 0.55, 0.7)
	wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(wire)
	var post_mat := G.pbr("wood", Color(0.75, 0.62, 0.48), 2.0, true, 0.9)
	var n := int(length / 3.0)
	for i in range(n + 1):
		var x := minf(float(i) * 3.0, length)
		for s in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.035
			cyl.bottom_radius = 0.045
			cyl.height = 1.3
			cyl.radial_segments = 6
			post.mesh = cyl
			post.material_override = post_mat
			post.position = Vector3(x, 0.55, 0)
			post.rotation = Vector3(s * 0.45, 0, 0)
			root.add_child(post)
	return root


# ---------------------------------------------------------------- wrecks
static func _part(parent: Node3D, mesh: Mesh, pos: Vector3, rot: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _boxm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _cylm(r: float, h: float, seg := 14) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	return c


## Burnt-out desert tank (Crusader / Panzer III silhouette). Returns the body and its footprint.
static func add_tank(parent: Node3D, pos: Vector3, yaw: float, variant := 0) -> StaticBody3D:
	var body := StaticBody3D.new()
	parent.add_child(body)
	var gy := Terrain.footprint_min(pos, Vector3(6.4, 0, 3.2))
	body.position = Vector3(pos.x, gy - 0.18, pos.z)
	body.rotation = Vector3(randf_range(-0.04, 0.04), yaw, randf_range(-0.06, 0.06))
	var paint := Color(0.5, 0.46, 0.34) if variant % 2 == 0 else Color(0.42, 0.42, 0.34)
	var hull := G.pbr("metal_rust", paint, 0.6, true, 0.75, 0.3)
	var scorched := G.pbr("metal_rust", Color(0.16, 0.14, 0.12), 0.6, true, 0.9, 0.2)
	var track := G.pbr("metal_rust", Color(0.2, 0.18, 0.16), 1.6, true, 0.75, 0.6)
	# Lower hull, sloped glacis and rear deck.
	_part(body, _boxm(Vector3(4.6, 0.9, 2.1)), Vector3(-0.2, 0.95, 0), Vector3.ZERO, hull)
	_part(body, _boxm(Vector3(1.5, 0.12, 2.1)), Vector3(2.65, 1.05, 0), Vector3(0, 0, -0.62), hull)
	_part(body, _boxm(Vector3(1.0, 0.12, 2.1)), Vector3(2.55, 0.55, 0), Vector3(0, 0, 0.75), hull)
	_part(body, _boxm(Vector3(1.6, 0.08, 1.9)), Vector3(-1.6, 1.43, 0), Vector3.ZERO, scorched)
	_part(body, _boxm(Vector3(1.1, 0.35, 1.5)), Vector3(0.9, 1.55, 0), Vector3.ZERO, hull)
	for s in [-1.0, 1.0]:
		# Track run, mudguard, road wheels, drive sprocket.
		_part(body, _boxm(Vector3(5.4, 0.18, 0.55)), Vector3(0, 0.85, s * 1.32), Vector3.ZERO, track)
		_part(body, _boxm(Vector3(5.6, 0.06, 0.7)), Vector3(0, 1.42, s * 1.3), Vector3.ZERO, hull)
		_part(body, _boxm(Vector3(5.4, 0.12, 0.5)), Vector3(0, 0.08, s * 1.32), Vector3.ZERO, track)
		for i in range(6):
			_part(body, _cylm(0.33, 0.22, 14), Vector3(-2.1 + i * 0.84, 0.4, s * 1.32), Vector3(PI * 0.5, 0, 0), track)
			_part(body, _cylm(0.12, 0.24, 8), Vector3(-2.1 + i * 0.84, 0.4, s * 1.32), Vector3(PI * 0.5, 0, 0), hull)
		_part(body, _cylm(0.38, 0.22, 10), Vector3(2.6, 0.6, s * 1.32), Vector3(PI * 0.5, 0, 0), scorched)
		_part(body, _cylm(0.3, 0.22, 10), Vector3(-2.75, 0.62, s * 1.32), Vector3(PI * 0.5, 0, 0), track)
	# Turret knocked askew by the hit that stopped it.
	var turret := Node3D.new()
	body.add_child(turret)
	turret.position = Vector3(-0.3, 1.78, 0.15)
	turret.rotation = Vector3(0.1, randf_range(0.4, 1.6), -0.14)
	var tmesh := CylinderMesh.new()
	tmesh.top_radius = 0.82
	tmesh.bottom_radius = 1.0
	tmesh.height = 0.7
	tmesh.radial_segments = 6
	tmesh.rings = 1
	_part(turret, tmesh, Vector3(0, 0.35, 0), Vector3.ZERO, hull)
	_part(turret, _boxm(Vector3(0.9, 0.55, 1.3)), Vector3(-0.95, 0.33, 0), Vector3.ZERO, scorched)
	_part(turret, _boxm(Vector3(0.35, 0.45, 0.7)), Vector3(0.95, 0.32, 0), Vector3.ZERO, hull)
	_part(turret, _cylm(0.075, 2.4, 10), Vector3(2.25, 0.32, 0), Vector3(0, 0, PI * 0.5 + 0.1), track)
	_part(turret, _cylm(0.3, 0.3, 10), Vector3(-0.2, 0.8, 0.25), Vector3.ZERO, hull)
	_part(turret, _cylm(0.32, 0.05, 10), Vector3(-0.2, 0.97, 0.25), Vector3(0.6, 0, 0), scorched)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(6.2, 2.4, 3.3)
	col.shape = shape
	col.position = Vector3(0, 1.2, 0)
	body.add_child(col)
	return body


## Abandoned Bedford/Opel-style lorry, half sunk in the sand.
static func add_truck(parent: Node3D, pos: Vector3, yaw: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	parent.add_child(body)
	var gy := Terrain.footprint_min(pos, Vector3(6.0, 0, 2.4))
	body.position = Vector3(pos.x, gy - 0.25, pos.z)
	body.rotation = Vector3(0.05, yaw, -0.09)
	var paint := G.pbr("metal_rust", Color(0.62, 0.58, 0.44), 0.7, true, 0.8, 0.2)
	var dark := G.pbr("metal_rust", Color(0.2, 0.18, 0.15), 1.0, true, 0.85, 0.3)
	var wood := G.pbr("planks", Color(0.72, 0.6, 0.45), 0.8, true, 0.95)
	var glass := G.flat(Color(0.12, 0.14, 0.14), 0.15, 0.4)
	_part(body, _boxm(Vector3(5.8, 0.25, 1.9)), Vector3(0, 0.75, 0), Vector3.ZERO, dark)
	_part(body, _boxm(Vector3(1.5, 1.0, 1.7)), Vector3(2.35, 1.35, 0), Vector3.ZERO, paint)
	_part(body, _boxm(Vector3(1.3, 1.25, 2.0)), Vector3(1.05, 1.55, 0), Vector3.ZERO, paint)
	_part(body, _boxm(Vector3(0.05, 0.5, 1.6)), Vector3(1.72, 1.85, 0), Vector3.ZERO, glass)
	_part(body, _boxm(Vector3(3.3, 0.12, 2.2)), Vector3(-1.4, 1.0, 0), Vector3.ZERO, wood)
	for s in [-1.0, 1.0]:
		_part(body, _boxm(Vector3(3.3, 0.55, 0.08)), Vector3(-1.4, 1.33, s * 1.08), Vector3(s * 0.15, 0, 0), wood)
		for x in [2.3, -0.6, -2.0]:
			_part(body, _cylm(0.48, 0.3, 14), Vector3(x, 0.48, s * 0.95), Vector3(PI * 0.5, 0, 0), dark)
	_part(body, _boxm(Vector3(0.08, 0.55, 2.2)), Vector3(-3.05, 1.33, 0), Vector3(0, 0, 0.6), wood)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(6.0, 2.2, 2.3)
	col.shape = shape
	col.position = Vector3(0, 1.1, 0)
	body.add_child(col)
	return body


# ---------------------------------------------------------------- palms
static func _frond_texture() -> ImageTexture:
	if _frond_tex != null:
		return _frond_tex
	var w := 64
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for y in range(h):
		for x in range(w / 2 - 1, w / 2 + 2):
			img.set_pixel(x, y, Color(0.38, 0.36, 0.2))
	var y0 := 6
	while y0 < h - 4:
		var taper := 1.0 - float(y0) / h * 0.7
		for s in [-1, 1]:
			var length := int((w / 2 - 2) * taper * rng.randf_range(0.8, 1.0))
			var col := Color(0.24, 0.36, 0.17).lerp(Color(0.46, 0.48, 0.25), rng.randf())
			for k in range(length):
				var x: int = w / 2 + s * k
				var y := y0 + int(k * 0.55)
				if y < h:
					img.set_pixel(clampi(x, 0, w - 1), y, col)
					img.set_pixel(clampi(x, 0, w - 1), mini(y + 1, h - 1), col.darkened(0.15))
		y0 += 4
	img.generate_mipmaps()
	_frond_tex = ImageTexture.create_from_image(img)
	return _frond_tex


static func _frond_mesh(length: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 8
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in range(seg + 1):
		var t := float(i) / seg
		var x := t * length
		var y := sin(t * PI * 0.55) * length * 0.32 - t * t * length * 0.55
		var w := 0.55 * (1.0 - t * 0.75)
		var l := Vector3(x, y, -w)
		var r := Vector3(x, y, w)
		if i > 0:
			var tp := float(i - 1) / seg
			for v in [[prev_l, Vector2(0, tp)], [l, Vector2(0, t)], [r, Vector2(1, t)], [prev_l, Vector2(0, tp)], [r, Vector2(1, t)], [prev_r, Vector2(1, tp)]]:
				st.set_uv(v[1])
				st.set_normal(Vector3.UP)
				st.add_vertex(v[0])
		prev_l = l
		prev_r = r
	return st.commit()


static func add_palm(parent: Node3D, pos: Vector3, height: float, seed_v: int) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	root.position = Vector3(pos.x, Terrain.height(pos.x, pos.z) - 0.1, pos.z)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	root.rotation = Vector3(rng.randf_range(-0.07, 0.07), 0, rng.randf_range(-0.07, 0.07))
	var bark := G.pbr("wood", Color(1.0, 0.86, 0.68), 1.5, true, 1.0, 0.0, 1.5, false)
	var segs := 7
	var top := Vector3.ZERO
	for i in range(segs):
		var t := float(i) / segs
		var seg := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = lerpf(0.24, 0.17, t + 1.0 / segs)
		c.bottom_radius = lerpf(0.27, 0.19, t)
		c.height = height / segs
		c.radial_segments = 8
		seg.mesh = c
		seg.material_override = bark
		seg.position = Vector3(0, (t + 0.5 / segs) * height, 0)
		seg.rotation.y = rng.randf() * TAU
		root.add_child(seg)
		# Leaf-scar ring between segments.
		var ring := MeshInstance3D.new()
		var rc := CylinderMesh.new()
		rc.top_radius = c.top_radius + 0.025
		rc.bottom_radius = c.top_radius + 0.04
		rc.height = 0.08
		rc.radial_segments = 8
		ring.mesh = rc
		ring.material_override = bark
		ring.position = Vector3(0, (t + 1.0 / segs) * height - 0.04, 0)
		root.add_child(ring)
		top = Vector3(0, height, 0)
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = _frond_texture()
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	fm.alpha_scissor_threshold = 0.4
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.roughness = 0.85
	fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var crown := Node3D.new()
	crown.position = top
	root.add_child(crown)
	var fronds := 11
	for k in range(fronds):
		var f := MeshInstance3D.new()
		f.mesh = _frond_mesh(rng.randf_range(2.6, 3.6))
		f.material_override = fm
		f.rotation = Vector3(rng.randf_range(-0.2, 0.15), TAU * k / fronds + rng.randf_range(-0.2, 0.2), 0)
		crown.add_child(f)
	# Date clusters.
	var dates := G.flat(Color(0.55, 0.28, 0.12), 0.7)
	for k in range(3):
		var d := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.18
		s.height = 0.4
		s.radial_segments = 8
		s.rings = 4
		d.mesh = s
		d.material_override = dates
		d.position = top + Vector3(cos(k * 2.1) * 0.3, -0.3, sin(k * 2.1) * 0.3)
		root.add_child(d)
	return root


# ---------------------------------------------------------------- smoke
static func add_smoke(parent: Node3D, pos: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	parent.add_child(p)
	p.position = pos
	p.amount = 28
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(2.2, 2.2)
	p.mesh = q
	p.material_override = G.particle_material(Color(0.2, 0.17, 0.15, 0.55))
	p.direction = Vector3(0.15, 1, 0)
	p.spread = 12.0
	p.gravity = Vector3(0.35, 0.55, 0.1)
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 3.5))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.35, 0.3, 0.26, 0.0))
	grad.add_point(0.1, Color(0.25, 0.22, 0.2, 0.7))
	grad.set_color(grad.get_point_count() - 1, Color(0.75, 0.68, 0.58, 0.0))
	p.color_ramp = grad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p
