extends RefCounted
## HARAQ weapon table: WW2-flavoured stats and simple procedural model parts.
## Models are built by build_model() with the mesh kit (see scripts/meshkit.gd).

const G := preload("res://scripts/graphics.gd")
const MeshKit := preload("res://scripts/meshkit.gd")
const WOOD := Color(0.36, 0.22, 0.12)
const STEEL := Color(0.13, 0.12, 0.11)
const BLUED := Color(0.18, 0.19, 0.21)
const BRASS := Color("#C6A15B")
const KHAKI := Color("#8A7048")

const AMMO_NAMES := {
	"pistol": ".455",
	"rifle": ".303",
	"smg": "9mm/.45",
}

## Max reserve ammo a player can carry per type.
const AMMO_MAX := {
	"pistol": 60,
	"rifle": 50,
	"smg": 180,
}

const DATA := {
	"webley": {
		"name": "WEBLEY Mk VI",
		"name_ar": "مسدس ويبلي",
		"ammo": "pistol",
		"damage": 34.0,
		"head_mult": 2.5,
		"interval": 0.32,
		"auto": false,
		"mag": 6,
		"reload": 2.0,
		"spread": 0.018,
		"recoil": 0.05,
		"muzzle": Vector3(0, 0.03, -0.36),
		"grip": Vector3(0, -0.08, 0.07),
		"fore": Vector3(0, -0.08, 0.07),
	},
	"lee_enfield": {
		"name": "LEE-ENFIELD No.4",
		"name_ar": "بندقية لي إنفيلد",
		"ammo": "rifle",
		"damage": 80.0,
		"head_mult": 2.0,
		"interval": 1.05,
		"auto": false,
		"mag": 10,
		"reload": 2.6,
		"spread": 0.004,
		"recoil": 0.12,
		"muzzle": Vector3(0, 0.045, -1.02),
		"grip": Vector3(0, -0.06, 0.13),
		"fore": Vector3(0, -0.03, -0.38),
	},
	"thompson": {
		"name": "THOMPSON M1928",
		"name_ar": "رشاش طومسون",
		"ammo": "smg",
		"damage": 17.0,
		"head_mult": 2.0,
		"interval": 0.085,
		"auto": true,
		"mag": 30,
		"reload": 2.4,
		"spread": 0.03,
		"recoil": 0.025,
		"muzzle": Vector3(0, 0.025, -0.72),
		"grip": Vector3(0, -0.09, 0.03),
		"fore": Vector3(0, -0.09, -0.3),
	},
	"mp40": {
		"name": "MP 40",
		"name_ar": "رشاش إم بي 40",
		"ammo": "smg",
		"damage": 20.0,
		"head_mult": 2.0,
		"interval": 0.11,
		"auto": true,
		"mag": 32,
		"reload": 2.2,
		"spread": 0.024,
		"recoil": 0.028,
		"muzzle": Vector3(0, 0.0, -0.68),
		"grip": Vector3(0, -0.09, 0.06),
		"fore": Vector3(0, -0.17, -0.2),
	},
}

## Weapons that can appear in loot crates (the pistol is the starting weapon).
const LOOT_WEAPONS := ["lee_enfield", "thompson", "mp40", "lee_enfield", "thompson", "webley"]


static func get_weapon(id: String) -> Dictionary:
	return DATA.get(id, {})


static var _mats := {}


static func part_material(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: StandardMaterial3D
	match key:
		"wood":
			m = G.pbr("wood", Color(0.95, 0.72, 0.55), 6.0, true, 0.62, 0.0, 0.6, false)
		"bake":
			m = G.pbr("wood", Color(0.55, 0.42, 0.36), 5.0, true, 0.5, 0.0, 0.4, false)
		"steel":
			m = G.pbr("metal_rust", Color(0.24, 0.23, 0.22), 4.0, true, 0.38, 0.85, 0.35, false)
		"blued":
			m = G.pbr("metal_rust", Color(0.15, 0.16, 0.19), 4.0, true, 0.32, 0.9, 0.3, false)
		"brass":
			m = G.flat(BRASS, 0.35, 0.9)
		_:
			m = G.flat(KHAKI)
	_mats[key] = m
	return m


## Builds a procedural, PBR-textured model of the weapon under `parent`: bevelled receivers,
## extruded wooden stocks and grips with real silhouettes, fluted cylinders, cooling fins,
## ribbed magazines — merged into one mesh (one surface per material) for the phone.
static func build_model(id: String, parent: Node3D, scale_factor := 1.0, shadows := true) -> void:
	if not DATA.has(id):
		return
	var k := MeshKit.new()
	match id:
		"webley":
			_webley(k)
		"lee_enfield":
			_enfield(k)
		"thompson":
			_thompson(k)
		"mp40":
			_mp40(k)
	var mi := k.instance(parent, shadows)
	mi.name = "GunMesh"
	mi.scale = Vector3.ONE * scale_factor


## Side profile given as (z, y) points, extruded across X (width), centred at x = 0.
static func _prof(k: MeshKit, pts: Array, width: float, bevel: float, mat: String, x := 0.0) -> void:
	var poly := PackedVector2Array()
	for p in pts:
		poly.append(Vector2(p[0], p[1]))
	# Local (u, v, w) = (z, y, x): basis columns map u -> +Z, v -> +Y, w -> +X.
	var b := Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(1, 0, 0))
	k.extrude(poly, width, bevel, Transform3D(b, Vector3(x, 0, 0)), part_material(mat))


## Cylinder along Z from z0 to z1.
static func _zc(k: MeshKit, r: float, y: float, z0: float, z1: float, mat: String, x := 0.0, seg := 14) -> void:
	k.cyl(r, r, absf(z1 - z0), Vector3(x, y, (z0 + z1) * 0.5), part_material(mat), Vector3(PI * 0.5, 0, 0), seg)


static func _bx(k: MeshKit, size: Vector3, pos: Vector3, mat: String, bevel := 0.0, rot_deg := Vector3.ZERO) -> void:
	var rot := rot_deg * (PI / 180.0)
	if bevel > 0.0:
		k.bbox(size, pos, part_material(mat), bevel, rot)
	else:
		k.box(size, pos, part_material(mat), rot)


static func _webley(k: MeshKit) -> void:
	_zc(k, 0.017, 0.03, -0.1, -0.345, "blued", 0.0, 16)
	_zc(k, 0.019, 0.03, -0.335, -0.36, "steel", 0.0, 16)
	_bx(k, Vector3(0.016, 0.018, 0.24), Vector3(0, 0.05, -0.22), "blued", 0.004)
	_bx(k, Vector3(0.014, 0.024, 0.2), Vector3(0, 0.008, -0.2), "blued", 0.004)
	_bx(k, Vector3(0.005, 0.022, 0.014), Vector3(0, 0.068, -0.33), "steel")
	# Frame with top strap, recoil shield and trigger-guard root.
	_prof(k, [[0.09, 0.035], [0.075, 0.068], [-0.1, 0.068], [-0.105, 0.045], [-0.09, 0.045], [-0.085, -0.025], [-0.02, -0.035], [0.03, -0.045], [0.07, -0.035], [0.1, -0.01]], 0.044, 0.007, "blued")
	# Fluted cylinder.
	_zc(k, 0.043, 0.012, -0.012, -0.088, "blued", 0.0, 18)
	for f in range(6):
		var a := TAU * f / 6.0 + 0.5
		_bx(k, Vector3(0.012, 0.012, 0.05), Vector3(cos(a) * 0.04, 0.012 + sin(a) * 0.04, -0.05), "steel", 0.0, Vector3(0, 0, rad_to_deg(a)))
	_zc(k, 0.008, 0.012, -0.088, -0.1, "steel")
	_zc(k, 0.006, -0.008, -0.1, -0.22, "steel", 0.0, 8)
	# Bird's-head wooden grip with lanyard ring.
	_prof(k, [[0.035, -0.03], [0.09, -0.025], [0.135, -0.155], [0.118, -0.19], [0.07, -0.19], [0.045, -0.12]], 0.048, 0.012, "wood")
	_bx(k, Vector3(0.05, 0.012, 0.06), Vector3(0, -0.19, 0.095), "steel", 0.003, Vector3(-12, 0, 0))
	k.cyl(0.012, 0.012, 0.005, Vector3(0, -0.205, 0.1), part_material("steel"), Vector3(0, 0, PI * 0.5), 10)
	# Trigger guard (three-piece loop) and trigger.
	_bx(k, Vector3(0.008, 0.006, 0.075), Vector3(0, -0.072, -0.008), "steel")
	_bx(k, Vector3(0.008, 0.04, 0.006), Vector3(0, -0.055, -0.046), "steel", 0.0, Vector3(20, 0, 0))
	_bx(k, Vector3(0.008, 0.035, 0.006), Vector3(0, -0.055, 0.03), "steel", 0.0, Vector3(-25, 0, 0))
	_bx(k, Vector3(0.006, 0.032, 0.008), Vector3(0, -0.045, -0.01), "steel", 0.0, Vector3(18, 0, 0))
	# Hammer spur and barrel latch.
	_prof(k, [[0.06, 0.05], [0.085, 0.085], [0.1, 0.09], [0.095, 0.07], [0.08, 0.04]], 0.012, 0.002, "steel")
	_bx(k, Vector3(0.05, 0.014, 0.022), Vector3(0, 0.07, 0.055), "steel", 0.003)


static func _enfield(k: MeshKit) -> void:
	# Butt stock with comb, wrist and pistol grip.
	_prof(k, [[0.08, 0.025], [0.36, 0.015], [0.585, 0.045], [0.6, -0.15], [0.22, -0.075], [0.155, -0.125], [0.1, -0.12], [0.06, -0.04]], 0.056, 0.014, "wood")
	_bx(k, Vector3(0.06, 0.2, 0.014), Vector3(0, -0.05, 0.597), "brass", 0.004, Vector3(-4, 0, 0))
	# Fore-end and upper handguard.
	_prof(k, [[0.05, -0.05], [0.05, 0.032], [-0.75, 0.032], [-0.775, 0.008], [-0.76, -0.028], [-0.12, -0.052]], 0.062, 0.014, "wood")
	_prof(k, [[-0.12, 0.03], [-0.13, 0.068], [-0.73, 0.062], [-0.745, 0.03]], 0.052, 0.012, "wood")
	# Receiver, bolt with knob, aperture sight, magazine, trigger guard.
	_bx(k, Vector3(0.054, 0.056, 0.27), Vector3(0, 0.058, -0.0), "blued", 0.01)
	_zc(k, 0.011, 0.082, 0.12, -0.08, "steel")
	k.cyl(0.007, 0.007, 0.075, Vector3(0.045, 0.075, 0.08), part_material("steel"), Vector3(0, 0, PI * 0.5), 8)
	k.sphere(0.017, Vector3(0.085, 0.068, 0.085), part_material("steel"))
	_bx(k, Vector3(0.034, 0.045, 0.028), Vector3(0, 0.105, 0.105), "blued", 0.005)
	k.cyl(0.012, 0.012, 0.012, Vector3(0, 0.13, 0.105), part_material("blued"), Vector3(PI * 0.5, 0, 0), 10)
	_bx(k, Vector3(0.05, 0.075, 0.105), Vector3(0, -0.08, -0.06), "blued", 0.008)
	_bx(k, Vector3(0.01, 0.008, 0.11), Vector3(0, -0.09, 0.07), "steel")
	_bx(k, Vector3(0.008, 0.03, 0.012), Vector3(0, -0.065, 0.06), "steel", 0.0, Vector3(15, 0, 0))
	# Barrel, nose cap, front sight with protectors, bands, swivels.
	_zc(k, 0.0145, 0.045, -0.74, -1.02, "blued", 0.0, 14)
	_zc(k, 0.017, 0.045, -1.0, -1.025, "steel", 0.0, 14)
	_bx(k, Vector3(0.064, 0.07, 0.05), Vector3(0, 0.02, -0.765), "blued", 0.01)
	_bx(k, Vector3(0.006, 0.03, 0.012), Vector3(0, 0.08, -0.99), "steel")
	for sx in [-1.0, 1.0]:
		_bx(k, Vector3(0.006, 0.036, 0.03), Vector3(sx * 0.016, 0.08, -0.99), "steel")
	for z in [-0.2, -0.55]:
		_bx(k, Vector3(0.068, 0.095, 0.02), Vector3(0, 0.012, z), "steel", 0.006)
	k.cyl(0.012, 0.012, 0.004, Vector3(0, -0.05, -0.56), part_material("steel"), Vector3(0, 0, PI * 0.5), 10)
	k.cyl(0.012, 0.012, 0.004, Vector3(0, -0.14, 0.45), part_material("steel"), Vector3(0, 0, PI * 0.5), 10)


static func _thompson(k: MeshKit) -> void:
	_bx(k, Vector3(0.068, 0.088, 0.4), Vector3(0, 0.0, -0.1), "blued", 0.012)
	_bx(k, Vector3(0.05, 0.022, 0.26), Vector3(0, 0.054, -0.06), "blued", 0.006)
	k.sphere(0.016, Vector3(0, 0.07, -0.16), part_material("steel"))
	# Lyman rear sight + front blade.
	_bx(k, Vector3(0.03, 0.05, 0.03), Vector3(0, 0.07, 0.075), "steel", 0.004)
	_bx(k, Vector3(0.006, 0.025, 0.012), Vector3(0, 0.05, -0.62), "steel")
	# Finned barrel + Cutts compensator.
	_zc(k, 0.019, 0.025, -0.3, -0.66, "blued")
	for f in range(14):
		_zc(k, 0.033, 0.025, -0.34 - f * 0.018, -0.346 - f * 0.018, "blued", 0.0, 16)
	_bx(k, Vector3(0.05, 0.05, 0.09), Vector3(0, 0.025, -0.69), "blued", 0.01)
	for f in range(3):
		_bx(k, Vector3(0.03, 0.006, 0.008), Vector3(0, 0.051, -0.67 - f * 0.018), "steel")
	# Finger-grooved vertical fore grip and pistol grip.
	_prof(k, [[-0.26, -0.035], [-0.33, -0.035], [-0.345, -0.075], [-0.334, -0.1], [-0.346, -0.125], [-0.334, -0.15], [-0.344, -0.185], [-0.3, -0.2], [-0.262, -0.18], [-0.252, -0.1]], 0.05, 0.012, "wood")
	_prof(k, [[0.02, -0.035], [0.075, -0.035], [0.105, -0.175], [0.075, -0.195], [0.04, -0.185]], 0.048, 0.012, "wood")
	_bx(k, Vector3(0.01, 0.008, 0.09), Vector3(0, -0.075, -0.015), "steel")
	_bx(k, Vector3(0.008, 0.03, 0.01), Vector3(0, -0.06, -0.03), "steel", 0.0, Vector3(15, 0, 0))
	# Butt stock.
	_prof(k, [[0.1, 0.035], [0.46, 0.02], [0.47, -0.11], [0.42, -0.105], [0.16, -0.06], [0.1, -0.045]], 0.054, 0.013, "wood")
	_bx(k, Vector3(0.058, 0.135, 0.012), Vector3(0, -0.045, 0.468), "steel", 0.004)
	# 50-round drum: body, ribs, hub, winding key.
	k.cyl(0.105, 0.105, 0.06, Vector3(0, -0.13, -0.13), part_material("blued"), Vector3(0, 0, PI * 0.5), 24)
	for r in [0.07, 0.095]:
		k.cyl(r, r, 0.066, Vector3(0, -0.13, -0.13), part_material("steel"), Vector3(0, 0, PI * 0.5), 24)
	k.cyl(0.06, 0.06, 0.068, Vector3(0, -0.13, -0.13), part_material("blued"), Vector3(0, 0, PI * 0.5), 24)
	k.cyl(0.02, 0.02, 0.08, Vector3(0, -0.13, -0.13), part_material("steel"), Vector3(0, 0, PI * 0.5), 10)
	_bx(k, Vector3(0.012, 0.012, 0.05), Vector3(0.042, -0.13, -0.13), "brass")


static func _mp40(k: MeshKit) -> void:
	_zc(k, 0.034, 0.0, 0.13, -0.29, "blued", 0.0, 18)
	_zc(k, 0.036, 0.0, 0.13, 0.12, "steel", 0.0, 18)
	_bx(k, Vector3(0.05, 0.06, 0.3), Vector3(0, -0.035, -0.11), "bake", 0.01)
	_zc(k, 0.016, 0.0, -0.29, -0.67, "steel")
	_zc(k, 0.024, 0.0, -0.29, -0.33, "blued", 0.0, 12)
	_zc(k, 0.018, 0.0, -0.65, -0.68, "blued")
	# Resting bar under the barrel, front sight hood.
	_bx(k, Vector3(0.02, 0.035, 0.07), Vector3(0, -0.03, -0.46), "blued", 0.004)
	k.cyl(0.014, 0.014, 0.025, Vector3(0, 0.03, -0.62), part_material("steel"), Vector3(PI * 0.5, 0, 0), 10)
	_bx(k, Vector3(0.004, 0.02, 0.008), Vector3(0, 0.03, -0.62), "steel")
	_bx(k, Vector3(0.012, 0.025, 0.03), Vector3(0, 0.045, -0.02), "steel", 0.003)
	# Ribbed magazine well and the long straight magazine.
	_bx(k, Vector3(0.04, 0.1, 0.075), Vector3(0, -0.08, -0.2), "blued", 0.008)
	for r in range(4):
		_bx(k, Vector3(0.044, 0.006, 0.079), Vector3(0, -0.05 - r * 0.02, -0.2), "steel")
	_bx(k, Vector3(0.028, 0.24, 0.055), Vector3(0, -0.24, -0.2), "steel", 0.006, Vector3(-4, 0, 0))
	for r in range(2):
		_bx(k, Vector3(0.031, 0.2, 0.006), Vector3(0, -0.24, -0.2 + (r - 0.5) * 0.024), "blued", 0.0, Vector3(-4, 0, 0))
	# Bakelite pistol grip + trigger.
	_prof(k, [[0.025, -0.04], [0.085, -0.04], [0.115, -0.17], [0.085, -0.19], [0.05, -0.18]], 0.046, 0.012, "bake")
	_bx(k, Vector3(0.01, 0.008, 0.08), Vector3(0, -0.075, -0.0), "steel")
	_bx(k, Vector3(0.008, 0.028, 0.01), Vector3(0, -0.06, -0.01), "steel", 0.0, Vector3(15, 0, 0))
	# Folding stock (rods + butt plate) and cocking handle.
	for sx in [-1.0, 1.0]:
		_zc(k, 0.0075, -0.01, 0.13, 0.47, "steel", sx * 0.02, 8)
	k.cyl(0.006, 0.006, 0.17, Vector3(0, -0.075, 0.38), part_material("steel"), Vector3(-0.9, 0, 0), 8)
	_bx(k, Vector3(0.05, 0.13, 0.016), Vector3(0, -0.06, 0.475), "blued", 0.004)
	_bx(k, Vector3(0.03, 0.014, 0.014), Vector3(-0.05, 0.01, -0.05), "steel", 0.003)
	k.sphere(0.011, Vector3(-0.068, 0.01, -0.05), part_material("steel"))
