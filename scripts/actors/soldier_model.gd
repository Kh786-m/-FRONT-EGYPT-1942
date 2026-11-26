class_name SoldierModel
extends Node3D
## Procedural, animated low-poly 3D soldier/hero body (no imported assets).
## Used for: the 3D hero Khaled in the main menu, allies, and enemy patrols.
## Limbs hang from pivot nodes so a simple code-driven walk cycle works now;
## replace with a rigged .glb (Mixamo/Blender) later — keep the same API:
## set_motion(speed) and play_fire().

enum Kind { HERO, ALLY, AXIS }

const PALETTES := {
	Kind.HERO: {"uniform": Color(0.62, 0.55, 0.40), "trousers": Color(0.50, 0.44, 0.32), "skin": Color(0.62, 0.44, 0.31), "helmet": Color(0.55, 0.15, 0.12), "gear": Color(0.36, 0.27, 0.17)},
	Kind.ALLY: {"uniform": Color(0.58, 0.52, 0.36), "trousers": Color(0.47, 0.42, 0.30), "skin": Color(0.66, 0.48, 0.34), "helmet": Color(0.38, 0.36, 0.25), "gear": Color(0.33, 0.29, 0.19)},
	Kind.AXIS: {"uniform": Color(0.47, 0.45, 0.33), "trousers": Color(0.42, 0.40, 0.30), "skin": Color(0.80, 0.64, 0.52), "helmet": Color(0.36, 0.35, 0.27), "gear": Color(0.22, 0.20, 0.16)},
}

var kind: int = Kind.AXIS
var _phase := 0.0
var _speed := 0.0
var _fire_kick := 0.0
var leg_l: Node3D
var leg_r: Node3D
var arm_l: Node3D
var arm_r: Node3D
var torso: Node3D

func _init(k: int = Kind.AXIS) -> void:
	kind = k

func _ready() -> void:
	_build()

func _part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rough := 0.9) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = LevelKit.mat(color, rough)
	mi.position = pos
	parent.add_child(mi)
	return mi

func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 4
	return c

func _limb(parent: Node3D, pivot_pos: Vector3, r: float, length: float, color: Color, foot_color := Color.TRANSPARENT) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pivot_pos
	parent.add_child(pivot)
	_part(pivot, _capsule(r, length), color, Vector3(0, -length / 2.0, 0))
	if foot_color.a > 0.0:
		var b := BoxMesh.new()
		b.size = Vector3(r * 2.1, r * 1.3, r * 3.4)
		_part(pivot, b, foot_color, Vector3(0, -length + r * 0.4, -r * 0.7), 0.6)
	return pivot

func _build() -> void:
	var p: Dictionary = PALETTES[kind]
	torso = Node3D.new()
	torso.position = Vector3(0, 0.95, 0)
	add_child(torso)
	var chest := BoxMesh.new()
	chest.size = Vector3(0.46, 0.58, 0.26)
	_part(torso, chest, p.uniform, Vector3(0, 0.30, 0))
	var belt := BoxMesh.new()
	belt.size = Vector3(0.48, 0.08, 0.28)
	_part(torso, belt, p.gear, Vector3(0, 0.03, 0))
	var strap := BoxMesh.new()
	strap.size = Vector3(0.06, 0.62, 0.28)
	var s := _part(torso, strap, p.gear, Vector3(0, 0.32, 0))
	s.rotation_degrees.z = 28
	var pouch := BoxMesh.new()
	pouch.size = Vector3(0.14, 0.12, 0.08)
	for x in [-0.14, 0.14]:
		_part(torso, pouch, p.gear, Vector3(x, 0.12, -0.16))
	var neck := _capsule(0.07, 0.16)
	_part(torso, neck, p.skin, Vector3(0, 0.64, 0))
	var head_m := SphereMesh.new()
	head_m.radius = 0.13
	head_m.height = 0.30
	_part(torso, head_m, p.skin, Vector3(0, 0.80, 0), 0.7)
	_build_headgear(p)
	leg_l = _limb(self, Vector3(-0.12, 0.95, 0), 0.09, 0.88, p.trousers, Color(0.17, 0.12, 0.08))
	leg_r = _limb(self, Vector3(0.12, 0.95, 0), 0.09, 0.88, p.trousers, Color(0.17, 0.12, 0.08))
	arm_l = _limb(torso, Vector3(-0.29, 0.55, 0), 0.07, 0.62, p.uniform)
	arm_r = _limb(torso, Vector3(0.29, 0.55, 0), 0.07, 0.62, p.uniform)
	arm_r.rotation_degrees.x = -70
	arm_l.rotation_degrees = Vector3(-60, 0, -25)
	var rifle := build_rifle(false)
	rifle.position = Vector3(0.12, 0.35, -0.35)
	torso.add_child(rifle)

func _build_headgear(p: Dictionary) -> void:
	match kind:
		Kind.HERO:
			# Tarboosh-red field cap over a keffiyeh-style scarf: Egyptian identity.
			var cap := CylinderMesh.new()
			cap.top_radius = 0.10
			cap.bottom_radius = 0.13
			cap.height = 0.16
			_part(torso, cap, p.helmet, Vector3(0, 0.95, 0))
			var scarf := _capsule(0.12, 0.26)
			var sc := _part(torso, scarf, Color(0.86, 0.82, 0.72), Vector3(0, 0.66, 0.02))
			sc.rotation_degrees.x = 90
		Kind.ALLY:
			var brim := CylinderMesh.new()
			brim.top_radius = 0.22
			brim.bottom_radius = 0.24
			brim.height = 0.03
			_part(torso, brim, p.helmet, Vector3(0, 0.90, 0), 0.6)
			var dome := SphereMesh.new()
			dome.radius = 0.14
			dome.height = 0.16
			_part(torso, dome, p.helmet, Vector3(0, 0.92, 0), 0.6)
		_:
			var shell := SphereMesh.new()
			shell.radius = 0.16
			shell.height = 0.24
			_part(torso, shell, p.helmet, Vector3(0, 0.88, 0), 0.6)
			var rim := CylinderMesh.new()
			rim.top_radius = 0.16
			rim.bottom_radius = 0.18
			rim.height = 0.06
			_part(torso, rim, p.helmet, Vector3(0, 0.82, 0), 0.6)

## A simple bolt-action style rifle built from primitives.
static func build_rifle(first_person: bool) -> Node3D:
	var r := Node3D.new()
	var wood := LevelKit.mat(Color(0.38, 0.22, 0.12), 0.55)
	var steel := LevelKit.mat(Color(0.12, 0.12, 0.13), 0.35, 0.6)
	var sc := 1.0 if first_person else 0.8
	var stock := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.07, 0.11, 0.75) * sc
	stock.mesh = sb
	stock.material_override = wood
	r.add_child(stock)
	var barrel := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.018 * sc
	cm.bottom_radius = 0.022 * sc
	cm.height = 0.55 * sc
	cm.radial_segments = 10
	barrel.mesh = cm
	barrel.material_override = steel
	barrel.rotation_degrees.x = 90
	barrel.position = Vector3(0, 0.04, -0.55) * sc
	r.add_child(barrel)
	var bolt := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.05, 0.05, 0.16) * sc
	bolt.mesh = bb
	bolt.material_override = steel
	bolt.position = Vector3(0.0, 0.07, -0.05) * sc
	r.add_child(bolt)
	var mag := MeshInstance3D.new()
	var mb := BoxMesh.new()
	mb.size = Vector3(0.05, 0.12, 0.08) * sc
	mag.mesh = mb
	mag.material_override = steel
	mag.position = Vector3(0, -0.1, -0.12) * sc
	r.add_child(mag)
	return r

func set_motion(speed: float) -> void:
	_speed = speed

func play_fire() -> void:
	_fire_kick = 1.0

func _process(delta: float) -> void:
	if leg_l == null: return
	var amount := clampf(_speed / 4.0, 0.0, 1.0)
	_phase += delta * (3.0 + _speed * 1.6)
	var swing := sin(_phase) * 0.6 * amount
	leg_l.rotation.x = swing
	leg_r.rotation.x = -swing
	arm_l.rotation.x = deg_to_rad(-60) - swing * 0.3
	torso.position.y = 0.95 + absf(sin(_phase)) * 0.03 * amount
	_fire_kick = move_toward(_fire_kick, 0.0, delta * 6.0)
	arm_r.rotation.x = deg_to_rad(-70) + _fire_kick * 0.25
