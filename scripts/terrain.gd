extends RefCounted
## HARAQ terrain: gently rolling dunes inside the 180 m arena, bigger dunes beyond the edge,
## and the Mediterranean coast to the north. `height()` is the single source of truth used by
## the visual mesh, the HeightMapShape3D collision and every prop / spawn placement.

const SEA_LEVEL := -0.55
const SHORE_BASE := -101.0
const PLAY_HALF := 90.0
const OUTER_HALF := 300.0

static var _n1: FastNoiseLite
static var _n2: FastNoiseLite


static func _init_noise() -> void:
	if _n1 != null:
		return
	_n1 = FastNoiseLite.new()
	_n1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n1.seed = 1942
	_n1.frequency = 0.016
	_n1.fractal_type = FastNoiseLite.FRACTAL_NONE
	_n2 = FastNoiseLite.new()
	_n2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n2.seed = 71
	_n2.frequency = 0.055
	_n2.fractal_type = FastNoiseLite.FRACTAL_NONE


## World-space Z of the waterline at a given X (north side of the map).
static func shore_z(x: float) -> float:
	return SHORE_BASE + 5.0 * sin(x * 0.021) + 2.5 * sin(x * 0.057 + 1.3)


static func _smooth(e0: float, e1: float, v: float) -> float:
	return smoothstep(e0, e1, v)


## 0..1 mask of areas kept flat for gameplay/set dressing (spawn, market lane).
static func flat_mask(x: float, z: float) -> float:
	var spawn := 1.0 - _smooth(12.0, 22.0, Vector2(x, z - 12.0).length())
	var dx := maxf(absf(x + 33.0) - 13.0, 0.0)
	var dz := maxf(absf(z + 17.0) - 28.0, 0.0)
	var market := 1.0 - _smooth(0.0, 7.0, Vector2(dx, dz).length())
	return maxf(spawn, market)


static func height(x: float, z: float) -> float:
	_init_noise()
	# Long, asymmetric dune ridges (stretched along X like wind-blown sand) plus small ripples.
	var ridge := _n1.get_noise_2d(x * 0.7, z * 1.25)
	ridge = 1.0 - absf(ridge)
	ridge = ridge * ridge - 0.45
	var dune := ridge * 1.6 + _n2.get_noise_2d(x, z) * 0.35
	var edge := maxf(absf(x), absf(z))
	var outer := _smooth(80.0, 150.0, edge)
	dune *= 1.0 + outer * 5.5
	dune *= 1.0 - flat_mask(x, z)
	# Coast: beach profile that dips under the sea north of the shoreline.
	var d := z - shore_z(x)
	var beach := clampf(d * 0.055 - 0.35, -5.0, 2.0)
	var land := _smooth(2.0, 34.0, d)
	return lerpf(beach, dune, land)


## Lowest ground height under a rectangular footprint (so boxes sit sunk into the sand).
static func footprint_min(pos: Vector3, size: Vector3) -> float:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var m := height(pos.x, pos.z)
	for o in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(-hx, hz), Vector2(hx, hz)]:
		m = minf(m, height(pos.x + o.x, pos.z + o.y))
	return m


static func _axis(fine_half: float, fine_step: float, outer_half: float, outer_step: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	var v := -outer_half
	while v < -fine_half - 0.01:
		a.append(v)
		v += outer_step
	v = -fine_half
	while v <= fine_half + 0.01:
		a.append(v)
		v += fine_step
	v = fine_half + outer_step
	while v <= outer_half + 0.01:
		a.append(v)
		v += outer_step
	return a


## Builds the visual terrain (non-uniform grid: 1.5 m inside the arena, 10 m outside).
static func build_mesh(fine_step := 1.5) -> ArrayMesh:
	var xs := _axis(PLAY_HALF + 6.0, fine_step, OUTER_HALF, 10.0)
	var zs := xs
	var nx := xs.size()
	var nz := zs.size()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.resize(nx * nz)
	normals.resize(nx * nz)
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	for j in range(nz):
		for i in range(nx):
			heights[j * nx + i] = height(xs[i], zs[j])
	for j in range(nz):
		for i in range(nx):
			var k := j * nx + i
			verts[k] = Vector3(xs[i], heights[k], zs[j])
			var il := maxi(i - 1, 0)
			var ir := mini(i + 1, nx - 1)
			var jd := maxi(j - 1, 0)
			var ju := mini(j + 1, nz - 1)
			var dhdx := (heights[j * nx + ir] - heights[j * nx + il]) / (xs[ir] - xs[il])
			var dhdz := (heights[ju * nx + i] - heights[jd * nx + i]) / (zs[ju] - zs[jd])
			normals[k] = Vector3(-dhdx, 1.0, -dhdz).normalized()
	var idx := PackedInt32Array()
	idx.resize((nx - 1) * (nz - 1) * 6)
	var t := 0
	for j in range(nz - 1):
		for i in range(nx - 1):
			var a := j * nx + i
			var b := a + 1
			var c := a + nx
			var d := c + 1
			idx[t] = a; idx[t + 1] = b; idx[t + 2] = c
			idx[t + 3] = b; idx[t + 4] = d; idx[t + 5] = c
			t += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## 1 m collision heightmap covering the playable square (plus a margin).
static func build_collision() -> CollisionShape3D:
	var half := int(PLAY_HALF) + 4
	var w := half * 2 + 1
	var data := PackedFloat32Array()
	data.resize(w * w)
	for j in range(w):
		for i in range(w):
			data[j * w + i] = height(float(i - half), float(j - half))
	var shape := HeightMapShape3D.new()
	shape.map_width = w
	shape.map_depth = w
	shape.map_data = data
	var col := CollisionShape3D.new()
	col.shape = shape
	return col


static func noise_texture(freq: float, seed_v: int, as_normal := false, size := 256) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	t.generate_mipmaps = true
	if as_normal:
		t.as_normal_map = true
		t.bump_strength = 6.0
	return t


static func terrain_material() -> ShaderMaterial:
	const G := preload("res://scripts/graphics.gd")
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/terrain.gdshader")
	m.set_shader_parameter("sand_albedo", G.tex("sand_albedo"))
	m.set_shader_parameter("sand_normal", G.tex("sand_normal"))
	m.set_shader_parameter("coarse_albedo", G.tex("sand_coarse_albedo"))
	m.set_shader_parameter("coarse_normal", G.tex("sand_coarse_normal"))
	m.set_shader_parameter("wet_albedo", G.tex("sand_wet_albedo"))
	m.set_shader_parameter("wet_normal", G.tex("sand_wet_normal"))
	m.set_shader_parameter("macro_noise", noise_texture(0.012, 5))
	m.set_shader_parameter("shore_base", SHORE_BASE)
	m.set_shader_parameter("sea_level", SEA_LEVEL)
	return m


static func build_sea() -> MeshInstance3D:
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1400, 620)
	plane.subdivide_width = 140
	plane.subdivide_depth = 60
	sea.mesh = plane
	sea.position = Vector3(0, SEA_LEVEL, SHORE_BASE - 290.0)
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/water.gdshader")
	m.set_shader_parameter("wave_normal", noise_texture(0.03, 11, true))
	m.set_shader_parameter("foam_noise", noise_texture(0.05, 23))
	m.set_shader_parameter("shore_base", SHORE_BASE)
	sea.material_override = m
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return sea
