extends Node3D
## HARAQ rigged soldier: a real Skeleton3D (18 bones) with ONE skinned mesh (rigid skinning,
## one surface per material) and an AnimationTree that blends idle / walk / run by speed,
## raises the weapon to aim, and layers fire (recoil), reload, hit-flinch and an animated
## death fall (no gore). Every animation is authored in code (key poses + two-bone IK so the
## hands stay on the weapon), so there are no imported assets to license.
##
## Mobile cost control: the tree is advanced manually and less often the further the soldier
## is from the camera (every frame up close, every 2nd / 4th / 8th frame further away).
## Meshes, skins and the animation library are built once and shared by every soldier.

const G := preload("res://scripts/graphics.gd")

## name, parent, rest offset (parent space). Rest rotations are identity, so pose = euler.
const BONES := [
	["hips", "", Vector3(0, 0.92, 0)],
	["spine", "hips", Vector3(0, 0.1, 0)],
	["chest", "spine", Vector3(0, 0.22, 0)],
	["neck", "chest", Vector3(0, 0.27, 0)],
	["head", "neck", Vector3(0, 0.1, 0)],
	["upperarm.R", "chest", Vector3(0.2, 0.2, 0)],
	["forearm.R", "upperarm.R", Vector3(0, -0.29, 0)],
	["hand.R", "forearm.R", Vector3(0, -0.26, 0)],
	["upperarm.L", "chest", Vector3(-0.2, 0.2, 0)],
	["forearm.L", "upperarm.L", Vector3(0, -0.29, 0)],
	["hand.L", "forearm.L", Vector3(0, -0.26, 0)],
	["thigh.R", "hips", Vector3(0.11, -0.04, 0)],
	["shin.R", "thigh.R", Vector3(0, -0.43, 0)],
	["foot.R", "shin.R", Vector3(0, -0.41, 0)],
	["thigh.L", "hips", Vector3(-0.11, -0.04, 0)],
	["shin.L", "thigh.L", Vector3(0, -0.43, 0)],
	["foot.L", "shin.L", Vector3(0, -0.41, 0)],
	["weapon", "chest", Vector3(0.1, -0.12, -0.3)],
]
const UPPER := ["spine", "chest", "neck", "head", "upperarm.R", "forearm.R", "hand.R", "upperarm.L", "forearm.L", "hand.L", "weapon"]
const TORSO := ["spine", "chest", "neck", "head"]
const UPPER_ARM := 0.29
const FORE_ARM := 0.26
## Where every weapon's grip is placed in the weapon bone's space (guns are offset to match).
const GRIP := Vector3(0, -0.07, 0.1)
const FORE := Vector3(0, -0.05, -0.26)
const ANIMS := ["idle", "walk", "run", "aim", "fire", "reload", "hit", "death"]
const WALK_SPEED := 1.6
const RUN_SPEED := 3.6
const CORPSE_TIME := 6.0

static var _mesh_cache := {}
static var _skin: Skin
static var _lib: AnimationLibrary
static var _rest_global := {}

var skeleton: Skeleton3D
var body_mesh: MeshInstance3D
var tree: AnimationTree
var weapon_attach: BoneAttachment3D
var gun_holder: Node3D
var muzzle_holder: Node3D
var variant := 0
var dead := false
## Diagnostics for tests: how many times the tree was advanced, and the current LOD step.
var advances := 0
var lod_step := 1
var _accum := 0.0
var _frame := 0
var _speed := 0.0
var _aim := 0.0
var _aim_target := 0.0
var _corpse_t := 0.0
var _last_state := ""


# ------------------------------------------------------------------ build
func build(p_variant: int, uniform: Material, helmet: Material) -> void:
	variant = p_variant
	name = "SoldierRig"
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)
	for b in BONES:
		skeleton.add_bone(b[0])
	for i in range(BONES.size()):
		var b: Array = BONES[i]
		if b[1] != "":
			skeleton.set_bone_parent(i, skeleton.find_bone(b[1]))
		skeleton.set_bone_rest(i, Transform3D(Basis.IDENTITY, b[2]))
	skeleton.reset_bone_poses()
	_compute_rest()
	body_mesh = MeshInstance3D.new()
	body_mesh.name = "Body"
	body_mesh.mesh = _soldier_mesh(variant, uniform, helmet)
	body_mesh.skin = _get_skin()
	skeleton.add_child(body_mesh)
	body_mesh.skeleton = NodePath("..")
	weapon_attach = BoneAttachment3D.new()
	weapon_attach.name = "WeaponAttach"
	skeleton.add_child(weapon_attach)
	weapon_attach.bone_name = "weapon"
	gun_holder = Node3D.new()
	gun_holder.name = "GunHolder"
	weapon_attach.add_child(gun_holder)
	muzzle_holder = Node3D.new()
	muzzle_holder.name = "MuzzleHolder"
	weapon_attach.add_child(muzzle_holder)
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	add_child(tree)
	tree.add_animation_library("", get_library())
	tree.tree_root = _make_tree()
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	_frame = randi() % 8
	set_motion(0.0, false)
	tree.advance(0.0)


## Offset the gun model so its grip lands in the right hand (all weapons share the poses).
func align_weapon(grip: Vector3) -> void:
	gun_holder.position = GRIP - grip


static func _compute_rest() -> void:
	if not _rest_global.is_empty():
		return
	for b in BONES:
		var xf := Transform3D(Basis.IDENTITY, b[2])
		if b[1] != "":
			xf = _rest_global[b[1]] * xf
		_rest_global[b[0]] = xf


static func _bone_index(n: String) -> int:
	for i in range(BONES.size()):
		if BONES[i][0] == n:
			return i
	return -1


static func _get_skin() -> Skin:
	if _skin == null:
		_compute_rest()
		_skin = Skin.new()
		for i in range(BONES.size()):
			_skin.add_bind(i, (_rest_global[BONES[i][0]] as Transform3D).affine_inverse())
	return _skin


# ------------------------------------------------------------------ mesh
## Skinned mesh builder: primitives placed in bone space, every vertex bound 100% to one bone.
class SkinKit:
	var parts := {}
	var tris := 0
	var rests := {}
	var index := {}

	func add(mesh: PrimitiveMesh, bone: String, local: Transform3D, mat: Material) -> void:
		var key := mat.get_instance_id()
		if not parts.has(key):
			parts[key] = {"mat": mat, "v": PackedVector3Array(), "n": PackedVector3Array(), "i": PackedInt32Array(), "b": PackedInt32Array(), "w": PackedFloat32Array()}
		var p: Dictionary = parts[key]
		var arr := mesh.get_mesh_arrays()
		var bi: int = index[bone]
		var xf: Transform3D = (rests[bone] as Transform3D) * local
		var nb := xf.basis.inverse().transposed()
		var base: int = (p["v"] as PackedVector3Array).size()
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for k in range(vs.size()):
			p["v"].append(xf * vs[k])
			p["n"].append((nb * ns[k]).normalized())
			p["b"].append_array(PackedInt32Array([bi, 0, 0, 0]))
			p["w"].append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var flip := xf.basis.determinant() < 0.0
		var t := 0
		while t + 2 < idx.size():
			if flip:
				p["i"].append_array(PackedInt32Array([base + idx[t], base + idx[t + 2], base + idx[t + 1]]))
			else:
				p["i"].append_array(PackedInt32Array([base + idx[t], base + idx[t + 1], base + idx[t + 2]]))
			tris += 1
			t += 3

	func commit() -> ArrayMesh:
		var m := ArrayMesh.new()
		for key in parts:
			var p: Dictionary = parts[key]
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = p["v"]
			arr[Mesh.ARRAY_NORMAL] = p["n"]
			arr[Mesh.ARRAY_INDEX] = p["i"]
			arr[Mesh.ARRAY_BONES] = p["b"]
			arr[Mesh.ARRAY_WEIGHTS] = p["w"]
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			m.surface_set_material(m.get_surface_count() - 1, p["mat"])
		m.set_meta("tris", tris)
		return m


static func _cap(r: float, h: float, seg := 10) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 3
	return c


static func _bx(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


static func _cy(rt: float, rb: float, h: float, seg := 14, caps := true) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	c.cap_top = caps
	c.cap_bottom = caps
	return c


static func _sph(r: float, h: float, seg := 12, rings := 6, hemi := false) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = h
	s.radial_segments = seg
	s.rings = rings
	s.is_hemisphere = hemi
	return s


static func _t(pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot).scaled(scl), pos)


## Variant 0: Afrika Korps style (olive-tan, deep flared Stahlhelm).
## Variant 1: 8th Army style (khaki drill, shallow wide-brim Brodie helmet, shorts + puttees).
static func _soldier_mesh(v: int, uniform: Material, helmet: Material) -> ArrayMesh:
	var key := "%d|%d|%d" % [v, uniform.get_instance_id(), helmet.get_instance_id()]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	_compute_rest()
	var cloth: Material = uniform
	var hat: Material = helmet
	if v == 1:
		cloth = (uniform as BaseMaterial3D).duplicate()
		(cloth as BaseMaterial3D).albedo_color = Color("#8A7048").lerp(Color("#E4D2B0"), 0.45)
		hat = (helmet as BaseMaterial3D).duplicate()
		(hat as BaseMaterial3D).albedo_color = Color(0.42, 0.4, 0.3)
	var skin := G.flat(Color(0.62, 0.45, 0.33), 0.8)
	var leather := G.flat(Color(0.2, 0.15, 0.11), 0.6)
	var webbing := G.flat(Color(0.42, 0.37, 0.27) if v == 1 else Color(0.3, 0.27, 0.2), 0.95)
	var k := SkinKit.new()
	k.rests = _rest_global
	for i in range(BONES.size()):
		k.index[BONES[i][0]] = i
	# Legs.
	for s in ["R", "L"]:
		var sx := 1.0 if s == "R" else -1.0
		if v == 1:
			k.add(_cap(0.092, 0.3), "thigh." + s, _t(Vector3(0, -0.12, 0)), cloth) # shorts
			k.add(_cap(0.072, 0.3), "thigh." + s, _t(Vector3(0, -0.33, 0)), skin)
			k.add(_cap(0.068, 0.2), "shin." + s, _t(Vector3(0, -0.06, 0)), skin)
			k.add(_cy(0.07, 0.066, 0.22, 10), "shin." + s, _t(Vector3(0, -0.27, 0)), webbing) # puttees
		else:
			k.add(_cap(0.09, 0.48), "thigh." + s, _t(Vector3(0, -0.21, 0)), cloth)
			k.add(_bx(Vector3(0.05, 0.12, 0.1)), "thigh." + s, _t(Vector3(sx * 0.08, -0.22, -0.01)), cloth) # pocket
			k.add(_cap(0.076, 0.44), "shin." + s, _t(Vector3(0, -0.19, 0)), cloth)
			k.add(_cy(0.07, 0.065, 0.16, 10), "shin." + s, _t(Vector3(0, -0.32, 0)), leather) # boot shaft
		k.add(_bx(Vector3(0.12, 0.1, 0.27)), "foot." + s, _t(Vector3(0, -0.0, -0.05)), leather)
	# Pelvis + belt.
	k.add(_cap(0.17, 0.34), "hips", _t(Vector3(0, 0.0, 0), Vector3(0, 0, PI / 2), Vector3(1, 1, 0.75)), cloth)
	k.add(_cy(0.2, 0.2, 0.07, 14), "spine", _t(Vector3(0, -0.04, 0), Vector3.ZERO, Vector3(1, 1, 0.7)), leather)
	for sx in [-1.0, 1.0]:
		k.add(_bx(Vector3(0.1, 0.1, 0.06)), "spine", _t(Vector3(sx * 0.12, -0.05, -0.13)), webbing) # ammo pouches
	k.add(_bx(Vector3(0.05, 0.1, 0.05)), "spine", _t(Vector3(0.17, -0.12, 0.04)), webbing) # bayonet frog
	# Torso (tunic) with chest pockets and webbing straps, small pack on the back.
	k.add(_cap(0.19, 0.42), "spine", _t(Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.7)), cloth)
	k.add(_cap(0.205, 0.5), "chest", _t(Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.68)), cloth)
	for sx in [-1.0, 1.0]:
		k.add(_bx(Vector3(0.1, 0.1, 0.03)), "chest", _t(Vector3(sx * 0.09, 0.06, -0.135)), cloth)
		k.add(_bx(Vector3(0.045, 0.52, 0.02)), "chest", _t(Vector3(sx * 0.09, 0.0, -0.142), Vector3(0, 0, sx * 0.22)), webbing)
		k.add(_cap(0.075, 0.2), "chest", _t(Vector3(sx * 0.17, 0.19, 0), Vector3(0, 0, PI / 2)), cloth) # shoulders
	k.add(_bx(Vector3(0.28, 0.28, 0.12)), "chest", _t(Vector3(0, 0.02, 0.16)), webbing)
	k.add(_cy(0.05, 0.05, 0.12, 10), "chest", _t(Vector3(0.0, -0.16, 0.18), Vector3(0, 0, PI / 2)), helmet if v == 0 else webbing) # mess tin / roll
	# Neck, head, face details, helmet.
	k.add(_cap(0.052, 0.16), "neck", _t(Vector3(0, 0.02, 0)), skin)
	k.add(_sph(0.105, 0.24), "head", _t(Vector3(0, 0.03, -0.01)), skin)
	k.add(_bx(Vector3(0.03, 0.05, 0.04)), "head", _t(Vector3(0, 0.02, -0.115)), skin) # nose
	k.add(_bx(Vector3(0.14, 0.02, 0.02)), "head", _t(Vector3(0, 0.07, -0.1)), leather) # brow shadow
	if v == 0:
		k.add(_sph(0.142, 0.2, 14, 5, true), "head", _t(Vector3(0, 0.055, 0), Vector3.ZERO, Vector3(1, 1.25, 1.06)), hat)
		k.add(_cy(0.142, 0.175, 0.07, 14, false), "head", _t(Vector3(0, 0.03, 0.012)), hat)
		k.add(_bx(Vector3(0.24, 0.012, 0.02)), "head", _t(Vector3(0, 0.07, -0.135)), hat) # goggles band
	else:
		k.add(_sph(0.13, 0.12, 14, 4, true), "head", _t(Vector3(0, 0.1, 0)), hat)
		k.add(_cy(0.2, 0.205, 0.016, 16), "head", _t(Vector3(0, 0.1, 0)), hat) # wide brim
	# Arms.
	for s in ["R", "L"]:
		k.add(_cap(0.068, 0.33), "upperarm." + s, _t(Vector3(0, -0.14, 0)), cloth)
		if v == 1:
			k.add(_cap(0.058, 0.18), "forearm." + s, _t(Vector3(0, -0.04, 0)), cloth) # rolled sleeve
			k.add(_cap(0.052, 0.22), "forearm." + s, _t(Vector3(0, -0.15, 0)), skin)
		else:
			k.add(_cap(0.06, 0.3), "forearm." + s, _t(Vector3(0, -0.13, 0)), cloth)
		k.add(_bx(Vector3(0.075, 0.1, 0.09)), "hand." + s, _t(Vector3(0, -0.04, 0)), skin)
	var m := k.commit()
	_mesh_cache[key] = m
	return m


# ------------------------------------------------------------------ poses / animations
## Forward kinematics on a pose dictionary {bone: {"r": Basis, "p": Vector3}} -> globals.
static func _fk(pose: Dictionary) -> Dictionary:
	var out := {}
	for b in BONES:
		var n: String = b[0]
		var e: Dictionary = pose.get(n, {})
		var xf := Transform3D(e.get("r", Basis.IDENTITY), e.get("p", b[2]))
		if b[1] != "":
			xf = out[b[1]] * xf
		out[n] = xf
	return out


## Basis whose -Y axis points along `down`, twisted by a hint vector.
static func _down_basis(down: Vector3, hint: Vector3) -> Basis:
	var y := -down.normalized()
	var x := hint.cross(y)
	if x.length() < 0.001:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## Two-bone IK (chest space): returns [upper pose basis, fore pose basis].
static func _ik(shoulder: Vector3, target: Vector3, pole: Vector3) -> Array:
	var d := target - shoulder
	var l := clampf(d.length(), 0.08, UPPER_ARM + FORE_ARM - 0.002)
	var dir := d.normalized()
	var c := clampf((UPPER_ARM * UPPER_ARM + l * l - FORE_ARM * FORE_ARM) / (2.0 * UPPER_ARM * l), -1.0, 1.0)
	var ang := acos(c)
	var pp := (pole - dir * pole.dot(dir))
	if pp.length() < 0.001:
		pp = Vector3.DOWN
	pp = pp.normalized()
	var elbow := shoulder + (dir * cos(ang) + pp * sin(ang)) * UPPER_ARM
	var wrist := shoulder + dir * l
	var bu := _down_basis(elbow - shoulder, pp)
	var bf := _down_basis(wrist - elbow, pp)
	return [bu, bu.inverse() * bf]


## Build a full pose from a compact spec:
##  "hips_p": Vector3, bone euler entries (Vector3), "gun": [model-space pos, euler],
##  optional "lh": left-hand target in chest space (else on the forend), "free_arms": true.
static func pose(spec: Dictionary) -> Dictionary:
	var p := {}
	for b in BONES:
		var n: String = b[0]
		if spec.has(n):
			p[n] = {"r": Basis.from_euler(spec[n])}
		else:
			p[n] = {"r": Basis.IDENTITY}
	p["hips"]["p"] = spec.get("hips_p", Vector3(0, 0.92, 0))
	var g := _fk(p)
	var chest: Transform3D = g["chest"]
	var gun: Array = spec.get("gun", [Vector3(0.12, 1.08, -0.32), Vector3(-0.2, 0.1, 0.0)])
	var gun_model := Transform3D(Basis.from_euler(gun[1]), gun[0])
	var gun_local := chest.affine_inverse() * gun_model
	p["weapon"] = {"r": gun_local.basis.orthonormalized(), "p": gun_local.origin}
	if not spec.get("free_arms", false):
		var sr: Vector3 = BONES[_bone_index("upperarm.R")][2]
		var sl: Vector3 = BONES[_bone_index("upperarm.L")][2]
		var grip := gun_local * (GRIP + Vector3(0, 0.05, 0))
		var fore := gun_local * (FORE + Vector3(0, 0.03, 0))
		if spec.has("lh"):
			fore = spec["lh"]
		var r := _ik(sr, grip, Vector3(1.0, -0.8, 0.5))
		var l := _ik(sl, fore, Vector3(-1.0, -1.0, 0.2))
		p["upperarm.R"]["r"] = r[0]
		p["forearm.R"]["r"] = r[1]
		p["upperarm.L"]["r"] = l[0]
		p["forearm.L"]["r"] = l[1]
		# Hands follow the weapon's orientation.
		var g2 := _fk(p)
		var wb: Basis = (g2["weapon"] as Transform3D).basis
		var hand_r := ((g2["forearm.R"] as Transform3D).basis.inverse() * wb * Basis.from_euler(Vector3(PI / 2, 0, 0))).orthonormalized()
		var hand_l := ((g2["forearm.L"] as Transform3D).basis.inverse() * wb * Basis.from_euler(Vector3(PI / 2, 0, 0.4))).orthonormalized()
		p["hand.R"]["r"] = hand_r
		p["hand.L"]["r"] = hand_l
	return p


## Common pieces of the specs.
const READY_GUN := [Vector3(-0.02, 1.13, -0.27), Vector3(-0.12, 0.7, 0.12)]
const PORT_GUN := [Vector3(0.04, 1.16, -0.3), Vector3(0.35, 0.55, 0.85)]
const AIM_GUN := [Vector3(0.05, 1.5, -0.3), Vector3(0.0, 0.0, 0.0)]


static func _leg_spec(spec: Dictionary, r_thigh: float, r_shin: float, l_thigh: float, l_shin: float) -> Dictionary:
	spec["thigh.R"] = Vector3(r_thigh, 0, 0)
	spec["shin.R"] = Vector3(r_shin, 0, 0)
	spec["foot.R"] = Vector3(-(r_thigh + r_shin) * 0.8, 0, 0)
	spec["thigh.L"] = Vector3(l_thigh, 0, 0)
	spec["shin.L"] = Vector3(l_shin, 0, 0)
	spec["foot.L"] = Vector3(-(l_thigh + l_shin) * 0.8, 0, 0)
	return spec


static func idle_spec(t: float) -> Dictionary:
	var br := sin(t * TAU) * 0.025
	var s := {"hips_p": Vector3(0, 0.915 + br * 0.1, 0), "spine": Vector3(br, 0, 0), "chest": Vector3(br * 0.5, 0.05, 0),
		"head": Vector3(0.05, -0.05 + br, 0), "gun": [READY_GUN[0] + Vector3(0, br * 0.3, 0), READY_GUN[1]]}
	return _leg_spec(s, 0.06, -0.1, -0.04, -0.06)


static func walk_spec(t: float, run: bool) -> Dictionary:
	var ph := t * TAU
	var amp := 0.75 if run else 0.42
	var knee := 1.45 if run else 0.75
	var rt := sin(ph) * amp
	var lt := -rt
	# Knee bends most while the leg swings forward (sin phase leading).
	var rk := -(maxf(0.0, sin(ph + PI * 0.5)) * knee + 0.08)
	var lk := -(maxf(0.0, sin(ph + PI * 1.5)) * knee + 0.08)
	var bob := -absf(cos(ph)) * (0.06 if run else 0.03)
	var lean := -0.22 if run else -0.04
	var s := {"hips_p": Vector3(0, (0.88 if run else 0.92) + bob + 0.02, 0),
		"hips": Vector3(0, sin(ph) * 0.12, 0), "spine": Vector3(lean, -sin(ph) * 0.1, 0),
		"chest": Vector3(lean * 0.4, -sin(ph) * 0.06, 0), "head": Vector3(-lean * 1.2, 0, 0)}
	var g: Array = PORT_GUN if run else READY_GUN
	s["gun"] = [g[0] + Vector3(0, bob * 0.5, 0), g[1]]
	return _leg_spec(s, rt, rk, lt, lk)


static func aim_spec(recoil := 0.0) -> Dictionary:
	var s := {"spine": Vector3(-0.04 + recoil * 0.12, -0.3, 0), "chest": Vector3(0.0, -0.25, 0),
		"neck": Vector3(0.1, 0.25, 0), "head": Vector3(0.12, 0.3, -0.12),
		"gun": [AIM_GUN[0] + Vector3(0, recoil * 0.02, recoil * 0.07), AIM_GUN[1] + Vector3(recoil * 0.2, 0, 0)]}
	return _leg_spec(s, 0.15, -0.15, -0.2, -0.1)


static func reload_spec(t: float) -> Dictionary:
	# Weapon tilted up in front of the chest; left hand to the pouch, to the gun, back.
	var tilt := Vector3(0.45, 0.2, 0.7)
	var g := [Vector3(0.02, 1.18, -0.34), tilt]
	var s := {"spine": Vector3(-0.08, 0, 0), "chest": Vector3(-0.06, 0.1, 0), "head": Vector3(0.35, 0.1, 0), "gun": g}
	var pouch := Vector3(-0.14, -0.38, -0.2)
	var magw := Vector3(-0.02, -0.12, -0.35)
	if t > 0.12 and t < 0.88:
		var u := clampf((t - 0.12) / 0.76, 0.0, 1.0)
		if u < 0.35:
			s["lh"] = magw.lerp(pouch, u / 0.35)
		elif u < 0.6:
			s["lh"] = pouch.lerp(magw, (u - 0.35) / 0.25)
		else:
			s["lh"] = magw + Vector3(0, sin((u - 0.6) * 18.0) * 0.02, 0)
	return _leg_spec(s, 0.06, -0.12, -0.05, -0.08)


static func hit_spec(t: float) -> Dictionary:
	var k := sin(clampf(t, 0.0, 1.0) * PI) * (1.0 - t * 0.4)
	var s := {"spine": Vector3(0.28 * k, 0.15 * k, 0.05 * k), "chest": Vector3(0.18 * k, -0.1 * k, 0), "neck": Vector3(0.2 * k, 0, 0),
		"head": Vector3(0.25 * k, 0.1 * k, 0.1 * k)}
	return s


static func death_spec(t: float) -> Dictionary:
	# 0..0.3 knees buckle, 0.3..0.8 fall back, 0.8..1 settle (small bounce).
	var buckle := clampf(t / 0.3, 0.0, 1.0)
	var fall := clampf((t - 0.25) / 0.55, 0.0, 1.0)
	fall = fall * fall * (3.0 - 2.0 * fall)
	var settle := sin(clampf((t - 0.8) / 0.2, 0.0, 1.0) * PI) * 0.06
	var hy := lerpf(lerpf(0.92, 0.66, buckle), 0.15, fall) + settle * 0.3
	var hz := lerpf(0.0, 0.55, fall)
	var s := {"hips_p": Vector3(0, hy, hz), "hips": Vector3(lerpf(0.15 * buckle, 1.45, fall) + settle, 0.0, 0.1 * fall),
		"spine": Vector3(lerpf(-0.3 * buckle, 0.05, fall), 0, 0), "chest": Vector3(lerpf(-0.15 * buckle, 0.0, fall), 0.0, 0.0),
		"neck": Vector3(lerpf(0.0, -0.25, fall), 0, 0), "head": Vector3(lerpf(0.2 * buckle, -0.2, fall), lerpf(0.0, 0.6, fall), 0),
		"free_arms": true,
		"upperarm.R": Vector3(lerpf(0.6, -0.2, fall), 0, lerpf(0.2, 1.2, fall)), "forearm.R": Vector3(lerpf(1.2, 0.3, fall), 0, 0),
		"upperarm.L": Vector3(lerpf(0.8, 0.1, fall), 0, lerpf(-0.2, -1.0, fall)), "forearm.L": Vector3(lerpf(1.0, 0.4, fall), 0, 0),
		"hand.R": Vector3(0.3, 0, 0), "hand.L": Vector3(0.3, 0, 0),
		"gun": [Vector3(0.1, 1.06, -0.36).lerp(Vector3(0.55, 0.06, -0.1), fall), Vector3(-0.28, 0.32, 0.12).lerp(Vector3(0.0, 1.2, PI / 2), fall)]}
	# Legs: knees bend while buckling, then splay out on the ground.
	var th := lerpf(0.55 * buckle, 0.05, fall)
	var sh := lerpf(-1.0 * buckle, -0.15, fall)
	s["thigh.R"] = Vector3(th, 0, lerpf(0.0, 0.15, fall))
	s["shin.R"] = Vector3(sh, 0, 0)
	s["thigh.L"] = Vector3(th * 0.8 + lerpf(0.0, 0.3, fall), 0, lerpf(0.0, -0.12, fall))
	s["shin.L"] = Vector3(sh * 1.1 - lerpf(0.0, 0.5, fall), 0, 0)
	s["foot.R"] = Vector3(-0.3 * buckle, 0, 0)
	s["foot.L"] = Vector3(-0.3 * buckle, 0, 0)
	return s


static func _key_pose(anim: Animation, tracks: Dictionary, time: float, p: Dictionary, bones: Array) -> void:
	for n in bones:
		if not tracks.has(n):
			var ti := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(ti, NodePath("Skeleton3D:" + n))
			tracks[n] = ti
		anim.rotation_track_insert_key(tracks[n], time, (p[n]["r"] as Basis).get_rotation_quaternion())
		if n == "hips" or n == "weapon":
			var pk: String = n + "#p"
			if not tracks.has(pk):
				var tp := anim.add_track(Animation.TYPE_POSITION_3D)
				anim.track_set_path(tp, NodePath("Skeleton3D:" + n))
				tracks[pk] = tp
			anim.position_track_insert_key(tracks[pk], time, p[n]["p"])


static func _make_anim(length: float, keys: int, loop: bool, bones: Array, spec_fn: Callable) -> Animation:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var tracks := {}
	for i in range(keys + 1):
		var t := float(i) / float(keys)
		_key_pose(a, tracks, t * length, pose(spec_fn.call(t)), bones)
	return a


static func all_bones() -> Array:
	var out := []
	for b in BONES:
		out.append(b[0])
	return out


static func get_library() -> AnimationLibrary:
	if _lib != null:
		return _lib
	_compute_rest()
	var all := all_bones()
	_lib = AnimationLibrary.new()
	_lib.add_animation(&"idle", _make_anim(2.4, 6, true, all, func(t): return idle_spec(t)))
	_lib.add_animation(&"walk", _make_anim(1.0, 8, true, all, func(t): return walk_spec(t, false)))
	_lib.add_animation(&"run", _make_anim(0.66, 8, true, all, func(t): return walk_spec(t, true)))
	_lib.add_animation(&"aim", _make_anim(1.0, 1, true, all, func(_t): return aim_spec(0.0)))
	_lib.add_animation(&"fire", _make_anim(0.22, 4, false, UPPER, func(t): return aim_spec(sin(minf(t * 2.5, 1.0) * PI) if t < 0.4 else maxf(0.0, 1.0 - (t - 0.2) * 1.25) * 0.0)))
	_lib.add_animation(&"reload", _make_anim(2.2, 16, false, UPPER, func(t): return reload_spec(t)))
	_lib.add_animation(&"hit", _make_anim(0.4, 4, false, TORSO, func(t): return hit_spec(t)))
	_lib.add_animation(&"death", _make_anim(1.4, 14, false, all, func(t): return death_spec(t)))
	return _lib


static func _anim_node(n: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = StringName(n)
	return a


static func _filter(node: AnimationNode, bones: Array) -> void:
	node.filter_enabled = true
	for b in bones:
		node.set_filter_path(NodePath("Skeleton3D:" + b), true)


## loco (BlendSpace1D idle/walk/run) -> aim (Blend2, upper body) -> reload / fire (OneShot,
## upper body) -> hit (OneShot, torso) -> state (Transition alive/dead) -> output.
static func _make_tree() -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace1D.new()
	loco.min_space = 0.0
	loco.max_space = RUN_SPEED
	loco.add_blend_point(_anim_node("idle"), 0.0)
	loco.add_blend_point(_anim_node("walk"), WALK_SPEED)
	loco.add_blend_point(_anim_node("run"), RUN_SPEED)
	loco.sync = true
	bt.add_node("loco", loco, Vector2(0, 0))
	bt.add_node("aim_anim", _anim_node("aim"), Vector2(0, 200))
	var aim := AnimationNodeBlend2.new()
	_filter(aim, UPPER)
	bt.add_node("aim", aim, Vector2(250, 0))
	var reload := AnimationNodeOneShot.new()
	reload.fadein_time = 0.15
	reload.fadeout_time = 0.25
	_filter(reload, UPPER)
	bt.add_node("reload_anim", _anim_node("reload"), Vector2(250, 200))
	bt.add_node("reload", reload, Vector2(500, 0))
	var fire := AnimationNodeOneShot.new()
	fire.fadein_time = 0.02
	fire.fadeout_time = 0.08
	_filter(fire, UPPER)
	bt.add_node("fire_anim", _anim_node("fire"), Vector2(500, 200))
	bt.add_node("fire", fire, Vector2(750, 0))
	var hit := AnimationNodeOneShot.new()
	hit.fadein_time = 0.04
	hit.fadeout_time = 0.15
	_filter(hit, TORSO)
	bt.add_node("hit_anim", _anim_node("hit"), Vector2(750, 200))
	bt.add_node("hit", hit, Vector2(1000, 0))
	var st := AnimationNodeTransition.new()
	st.input_count = 2
	st.set_input_name(0, "alive")
	st.set_input_name(1, "dead")
	st.xfade_time = 0.12
	bt.add_node("death_anim", _anim_node("death"), Vector2(1000, 200))
	bt.add_node("state", st, Vector2(1250, 0))
	bt.connect_node("aim", 0, "loco")
	bt.connect_node("aim", 1, "aim_anim")
	bt.connect_node("reload", 0, "aim")
	bt.connect_node("reload", 1, "reload_anim")
	bt.connect_node("fire", 0, "reload")
	bt.connect_node("fire", 1, "fire_anim")
	bt.connect_node("hit", 0, "fire")
	bt.connect_node("hit", 1, "hit_anim")
	bt.connect_node("state", 0, "hit")
	bt.connect_node("state", 1, "death_anim")
	bt.connect_node("output", 0, "state")
	return bt


# ------------------------------------------------------------------ runtime API
func set_motion(speed: float, aiming: bool) -> void:
	_speed = speed
	_aim_target = 1.0 if aiming else 0.0


func fire() -> void:
	if not dead:
		tree.set("parameters/fire/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func reload(duration := 2.2) -> void:
	if not dead:
		tree.set("parameters/reload/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func hit() -> void:
	if not dead:
		tree.set("parameters/hit/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func is_reload_playing() -> bool:
	return bool(tree.get("parameters/reload/active"))


## Play the death fall. The rig is moved to `new_parent` (keeps its world transform) so the
## soldier's logic node can be freed right away; the body lies for a while, sinks, and frees.
func die(new_parent: Node = null) -> void:
	if dead:
		return
	dead = true
	_speed = 0.0
	_aim_target = 0.0
	tree.set("parameters/state/transition_request", "dead")
	if new_parent != null and get_parent() != new_parent:
		var xf := global_transform
		get_parent().remove_child(self)
		new_parent.add_child(self)
		global_transform = xf


func current_state() -> String:
	return str(tree.get("parameters/state/current_state"))


func _process(delta: float) -> void:
	if tree == null:
		return
	_aim = move_toward(_aim, _aim_target, delta * 5.0)
	tree.set("parameters/loco/blend_position", clampf(_speed, 0.0, RUN_SPEED))
	tree.set("parameters/aim/blend_amount", _aim)
	# Distance-based update rate (LOD).
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var d := 0.0
	if cam != null:
		d = cam.global_position.distance_to(global_position)
	lod_step = 1 if d < 18.0 else (2 if d < 35.0 else (4 if d < 70.0 else 8))
	if dead:
		lod_step = 1
	_frame += 1
	_accum += delta
	if _frame % lod_step == 0:
		tree.advance(_accum)
		advances += 1
		_accum = 0.0
	if dead:
		_corpse_t += delta
		if _corpse_t > CORPSE_TIME - 1.5:
			position.y -= delta * 0.35
		if _corpse_t > CORPSE_TIME:
			queue_free()
