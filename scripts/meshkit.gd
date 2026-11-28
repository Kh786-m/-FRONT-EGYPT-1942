extends RefCounted
## HARAQ mesh kit: builds hard-surface models (tanks, guns) from primitives, bevelled extruded
## profiles and swept bands, and merges everything into ONE ArrayMesh with one surface per
## material, so a detailed tank is a single draw-call group instead of dozens of nodes.
## Works on CPU-side arrays only (fine with the headless/dummy renderer too).

var _parts := {} # material key -> {"mat": Material, "v": PackedVector3Array, "n": PackedVector3Array}
var triangles := 0


func _bucket(mat: Material) -> Dictionary:
	var key := mat.get_instance_id()
	if not _parts.has(key):
		_parts[key] = {"mat": mat, "v": PackedVector3Array(), "n": PackedVector3Array()}
	return _parts[key]


## Add raw triangles (local space) with optional per-vertex normals (flat normals when empty).
func add_tris(verts: PackedVector3Array, normals: PackedVector3Array, xf: Transform3D, mat: Material) -> void:
	var b := _bucket(mat)
	var flip := xf.basis.determinant() < 0.0
	var nb := xf.basis.inverse().transposed()
	var i := 0
	while i + 2 < verts.size():
		var tri := [xf * verts[i], xf * verts[i + 1], xf * verts[i + 2]]
		var nr := []
		if normals.size() == verts.size():
			nr = [(nb * normals[i]).normalized(), (nb * normals[i + 1]).normalized(), (nb * normals[i + 2]).normalized()]
		if flip:
			tri = [tri[0], tri[2], tri[1]]
			if not nr.is_empty():
				nr = [nr[0], nr[2], nr[1]]
		if nr.is_empty():
			# Godot front faces are clockwise when seen from outside.
			var fn: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
			nr = [fn, fn, fn]
		for k in range(3):
			b["v"].append(tri[k])
			b["n"].append(nr[k])
		triangles += 1
		i += 3


## Add a PrimitiveMesh (Box/Cylinder/Sphere...) using its CPU arrays.
func add_primitive(mesh: PrimitiveMesh, xf: Transform3D, mat: Material) -> void:
	var arr := mesh.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx = arr[Mesh.ARRAY_INDEX]
	var tv := PackedVector3Array()
	var tn := PackedVector3Array()
	if idx != null and idx.size() > 0:
		for i in idx:
			tv.append(v[i])
			tn.append(n[i])
	else:
		tv = v
		tn = n
	add_tris(tv, tn, xf, mat)


func box(size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	var b := BoxMesh.new()
	b.size = size
	add_primitive(b, Transform3D(Basis.from_euler(rot), pos), mat)


## Cylinder along local Y unless rotated.
func cyl(r_top: float, r_bottom: float, h: float, pos: Vector3, mat: Material, rot := Vector3.ZERO, seg := 14, caps := true) -> void:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	c.cap_top = caps
	c.cap_bottom = caps
	add_primitive(c, Transform3D(Basis.from_euler(rot), pos), mat)


func sphere(r: float, pos: Vector3, mat: Material, scl := Vector3.ONE, seg := 10) -> void:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = maxi(3, seg / 2)
	add_primitive(s, Transform3D(Basis.from_scale(scl), pos), mat)


## Bevelled box (chamfered edges) — reads much better than a plain cube up close.
func bbox(size: Vector3, pos: Vector3, mat: Material, bevel := 0.02, rot := Vector3.ZERO) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var poly := PackedVector2Array([Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)])
	extrude(poly, size.z, bevel, Transform3D(Basis.from_euler(rot), pos), mat)


static func _inset(poly: PackedVector2Array, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	var ccw := _area(poly) > 0.0
	for i in range(n):
		var p0 := poly[(i - 1 + n) % n]
		var p1 := poly[i]
		var p2 := poly[(i + 1) % n]
		var e1 := (p1 - p0).normalized()
		var e2 := (p2 - p1).normalized()
		# Inward normals.
		var n1 := Vector2(-e1.y, e1.x) if ccw else Vector2(e1.y, -e1.x)
		var n2 := Vector2(-e2.y, e2.x) if ccw else Vector2(e2.y, -e2.x)
		var k := 1.0 + n1.dot(n2)
		var off := (n1 + n2) * (d / maxf(k, 0.35))
		out.append(p1 + off)
	return out


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in range(poly.size()):
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


## Extrude a 2D profile (local XY) along local Z (centred), with chamfered edges of size `bevel`.
func extrude(poly: PackedVector2Array, depth: float, bevel: float, xf: Transform3D, mat: Material) -> void:
	if _area(poly) < 0.0:
		poly.reverse()
	var n := poly.size()
	var b := minf(bevel, depth * 0.45)
	var inner := _inset(poly, b) if b > 0.0 else poly
	var z0 := depth * 0.5
	var zi := z0 - b
	var verts := PackedVector3Array()
	var tri_idx := Geometry2D.triangulate_polygon(inner)
	# Caps (front +Z, back -Z).
	for t in range(0, tri_idx.size(), 3):
		var a := inner[tri_idx[t]]
		var c := inner[tri_idx[t + 1]]
		var d := inner[tri_idx[t + 2]]
		if (c - a).cross(d - a) < 0.0:
			var tmp := c
			c = d
			d = tmp
		verts.append_array([Vector3(a.x, a.y, z0), Vector3(d.x, d.y, z0), Vector3(c.x, c.y, z0)])
		verts.append_array([Vector3(a.x, a.y, -z0), Vector3(c.x, c.y, -z0), Vector3(d.x, d.y, -z0)])
	for i in range(n):
		var j := (i + 1) % n
		var p := poly[i]
		var q := poly[j]
		var pi := inner[i]
		var qi := inner[j]
		# Side wall between the two full-size rings.
		_quad(verts, Vector3(p.x, p.y, zi), Vector3(q.x, q.y, zi), Vector3(q.x, q.y, -zi), Vector3(p.x, p.y, -zi))
		if b > 0.0:
			_quad(verts, Vector3(pi.x, pi.y, z0), Vector3(qi.x, qi.y, z0), Vector3(q.x, q.y, zi), Vector3(p.x, p.y, zi))
			_quad(verts, Vector3(p.x, p.y, -zi), Vector3(q.x, q.y, -zi), Vector3(qi.x, qi.y, -z0), Vector3(pi.x, pi.y, -z0))
	add_tris(verts, PackedVector3Array(), xf, mat)


## Quad a-b-c-d where a->b runs counter-clockwise around the profile (outward faces).
static func _quad(verts: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	verts.append_array([a, b, c, a, c, d])


## Sweep a rectangular band (thickness outward, width along Z) around a closed 2D path in XY.
## Used for tank tracks: the band wraps the wheels, with grousers added separately.
func band(path: PackedVector2Array, thickness: float, width: float, xf: Transform3D, mat: Material) -> void:
	if _area(path) < 0.0:
		path.reverse()
	var outer := _inset(path, -thickness)
	var n := path.size()
	var z := width * 0.5
	var verts := PackedVector3Array()
	for i in range(n):
		var j := (i + 1) % n
		var p := path[i]
		var q := path[j]
		var po := outer[i]
		var qo := outer[j]
		_quad(verts, Vector3(po.x, po.y, z), Vector3(qo.x, qo.y, z), Vector3(qo.x, qo.y, -z), Vector3(po.x, po.y, -z)) # tread face
		_quad(verts, Vector3(q.x, q.y, z), Vector3(p.x, p.y, z), Vector3(p.x, p.y, -z), Vector3(q.x, q.y, -z)) # inner face
		_quad(verts, Vector3(p.x, p.y, z), Vector3(q.x, q.y, z), Vector3(qo.x, qo.y, z), Vector3(po.x, po.y, z)) # outer side
		_quad(verts, Vector3(q.x, q.y, -z), Vector3(p.x, p.y, -z), Vector3(po.x, po.y, -z), Vector3(qo.x, qo.y, -z)) # inner side
	add_tris(verts, PackedVector3Array(), xf, mat)


## Evenly spaced points along a closed path (for grousers / track links).
static func resample(path: PackedVector2Array, spacing: float) -> Array:
	var out := []
	var carry := 0.0
	for i in range(path.size()):
		var p := path[i]
		var q := path[(i + 1) % path.size()]
		var seg := p.distance_to(q)
		var dir := (q - p) / maxf(seg, 0.0001)
		var t := carry
		while t < seg:
			out.append([p + dir * t, dir])
			t += spacing
		carry = t - seg
	return out


func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for key in _parts.keys():
		var b: Dictionary = _parts[key]
		if (b["v"] as PackedVector3Array).is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = b["v"]
		arr[Mesh.ARRAY_NORMAL] = b["n"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, b["mat"])
	mesh.set_meta("tris", triangles)
	return mesh


func instance(parent: Node3D, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = commit()
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
