extends RefCounted
## HARAQ weapon table: WW2-flavoured stats and simple procedural model parts.
## Each part: [kind ("box" | "cyl" along Z | "drum" along X), position, size (box) or Vector3(radius, length, 0) (cyl), colour].

const G := preload("res://scripts/graphics.gd")
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
		"parts": [
			["box", Vector3(0, 0.0, -0.02), Vector3(0.05, 0.085, 0.2), "steel"],
			["cyl", Vector3(0, 0.03, -0.22), Vector3(0.017, 0.22, 0), "blued"],
			["box", Vector3(0, 0.05, -0.22), Vector3(0.018, 0.016, 0.22), "blued"],
			["cyl", Vector3(0, 0.012, -0.05), Vector3(0.042, 0.075, 0), "blued"],
			["box", Vector3(0, 0.055, -0.03), Vector3(0.04, 0.016, 0.14), "steel"],
			["box", Vector3(0, 0.066, -0.325), Vector3(0.006, 0.02, 0.014), "steel"],
			["box", Vector3(0, -0.085, 0.075), Vector3(0.042, 0.14, 0.06), "wood", Vector3(-22, 0, 0)],
			["box", Vector3(0, -0.13, 0.095), Vector3(0.046, 0.025, 0.065), "steel", Vector3(-22, 0, 0)],
			["box", Vector3(0, -0.045, -0.035), Vector3(0.01, 0.01, 0.07), "steel"],
			["box", Vector3(0, -0.03, -0.015), Vector3(0.008, 0.035, 0.01), "steel", Vector3(15, 0, 0)],
			["box", Vector3(0, 0.06, 0.07), Vector3(0.014, 0.03, 0.02), "steel", Vector3(-35, 0, 0)],
			["cyl", Vector3(0, -0.04, -0.12), Vector3(0.006, 0.12, 0), "steel"],
		],	},
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
		"parts": [
			["box", Vector3(0, 0.0, -0.3), Vector3(0.07, 0.085, 0.82), "wood"],
			["box", Vector3(0, 0.05, -0.33), Vector3(0.06, 0.03, 0.62), "wood"],
			["box", Vector3(0, -0.03, 0.12), Vector3(0.055, 0.11, 0.16), "wood", Vector3(-12, 0, 0)],
			["box", Vector3(0, -0.04, 0.38), Vector3(0.06, 0.15, 0.38), "wood", Vector3(-6, 0, 0)],
			["box", Vector3(0, -0.04, 0.575), Vector3(0.064, 0.16, 0.02), "steel", Vector3(-6, 0, 0)],
			["cyl", Vector3(0, 0.045, -0.86), Vector3(0.015, 0.32, 0), "blued"],
			["box", Vector3(0, 0.065, -0.02), Vector3(0.055, 0.05, 0.26), "blued"],
			["cyl", Vector3(0.045, 0.075, 0.04), Vector3(0.008, 0.07, 0), "steel", Vector3(0, 90, 0)],
			["cyl", Vector3(0.085, 0.07, 0.04), Vector3(0.016, 0.02, 0), "steel", Vector3(0, 90, 0)],
			["box", Vector3(0, 0.1, 0.07), Vector3(0.03, 0.03, 0.03), "steel"],
			["box", Vector3(0, 0.075, -0.98), Vector3(0.008, 0.03, 0.012), "steel"],
			["box", Vector3(0, -0.075, -0.07), Vector3(0.05, 0.09, 0.11), "blued"],
			["box", Vector3(0, -0.07, 0.04), Vector3(0.01, 0.01, 0.1), "steel"],
			["box", Vector3(0, 0.0, -0.66), Vector3(0.075, 0.09, 0.02), "steel"],
			["box", Vector3(0, 0.0, -0.18), Vector3(0.075, 0.09, 0.02), "steel"],
		],	},
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
		"parts": [
			["box", Vector3(0, 0.0, -0.1), Vector3(0.07, 0.09, 0.42), "blued"],
			["box", Vector3(0, 0.055, -0.05), Vector3(0.05, 0.02, 0.24), "steel"],
			["cyl", Vector3(0, 0.025, -0.48), Vector3(0.019, 0.42, 0), "blued"],
			["cyl", Vector3(0, 0.025, -0.4), Vector3(0.032, 0.17, 0), "steel"],
			["cyl", Vector3(0, 0.025, -0.69), Vector3(0.028, 0.06, 0), "steel"],
			["box", Vector3(0, 0.075, 0.08), Vector3(0.03, 0.04, 0.03), "steel"],
			["box", Vector3(0, -0.085, 0.06), Vector3(0.05, 0.13, 0.06), "wood", Vector3(-15, 0, 0)],
			["box", Vector3(0, -0.085, -0.31), Vector3(0.05, 0.12, 0.06), "wood", Vector3(-8, 0, 0)],
			["box", Vector3(0, -0.02, 0.31), Vector3(0.06, 0.12, 0.3), "wood", Vector3(-6, 0, 0)],
			["box", Vector3(0, -0.02, 0.46), Vector3(0.062, 0.13, 0.015), "steel", Vector3(-6, 0, 0)],
			["drum", Vector3(0, -0.13, -0.13), Vector3(0.105, 0.06, 0), "blued"],
			["drum", Vector3(0, -0.13, -0.13), Vector3(0.03, 0.065, 0), "steel"],
			["box", Vector3(0, -0.05, -0.0), Vector3(0.01, 0.01, 0.08), "steel"],
			["box", Vector3(0.04, 0.03, -0.12), Vector3(0.012, 0.02, 0.05), "steel"],
		],	},
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
		"parts": [
			["cyl", Vector3(0, 0.0, -0.08), Vector3(0.034, 0.42, 0), "blued"],
			["box", Vector3(0, -0.03, -0.12), Vector3(0.05, 0.06, 0.3), "steel"],
			["cyl", Vector3(0, 0.0, -0.46), Vector3(0.016, 0.38, 0), "steel"],
			["box", Vector3(0, -0.025, -0.47), Vector3(0.02, 0.03, 0.06), "steel"],
			["box", Vector3(0, -0.2, -0.2), Vector3(0.03, 0.26, 0.055), "blued", Vector3(-4, 0, 0)],
			["box", Vector3(0, -0.075, -0.2), Vector3(0.045, 0.05, 0.08), "steel"],
			["box", Vector3(0, -0.085, 0.07), Vector3(0.045, 0.13, 0.06), "bake", Vector3(-15, 0, 0)],
			["box", Vector3(0, -0.035, -0.07), Vector3(0.06, 0.05, 0.1), "bake"],
			["box", Vector3(0, 0.0, 0.3), Vector3(0.015, 0.015, 0.36), "steel"],
			["box", Vector3(0, -0.07, 0.45), Vector3(0.015, 0.11, 0.015), "steel"],
			["box", Vector3(0, -0.03, 0.31), Vector3(0.012, 0.012, 0.3), "steel", Vector3(-12, 0, 0)],
			["box", Vector3(0.045, 0.01, -0.03), Vector3(0.04, 0.014, 0.014), "steel"],
			["box", Vector3(0, 0.045, -0.02), Vector3(0.012, 0.025, 0.03), "steel"],
			["box", Vector3(0, 0.04, -0.6), Vector3(0.008, 0.03, 0.012), "steel"],
		],	},
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


## Builds a procedural, PBR-textured model of the weapon under `parent`.
static func build_model(id: String, parent: Node3D, scale_factor := 1.0, shadows := true) -> void:
	var w: Dictionary = DATA.get(id, {})
	if w.is_empty():
		return
	for part in w["parts"]:
		var mesh := MeshInstance3D.new()
		if part[0] == "box":
			var b := BoxMesh.new()
			b.size = part[2] * scale_factor
			mesh.mesh = b
		else:
			var c := CylinderMesh.new()
			c.top_radius = part[2].x * scale_factor
			c.bottom_radius = part[2].x * scale_factor
			c.height = part[2].y * scale_factor
			c.radial_segments = 16
			c.rings = 1
			mesh.mesh = c
			if part[0] == "drum":
				mesh.rotation_degrees.z = 90
			else:
				mesh.rotation_degrees.x = 90
		if part.size() > 4:
			mesh.rotation_degrees += part[4]
		mesh.material_override = part_material(part[3])
		mesh.position = part[1] * scale_factor
		if not shadows:
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mesh)
