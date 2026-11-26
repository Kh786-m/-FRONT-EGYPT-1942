extends RefCounted
## HARAQ weapon table: WW2-flavoured stats and simple procedural model parts.
## Each part: [kind ("box" | "cyl" along Z | "drum" along X), position, size (box) or Vector3(radius, length, 0) (cyl), colour].

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
		"parts": [
			["box", Vector3(0, 0, -0.05), Vector3(0.09, 0.11, 0.26), STEEL],
			["cyl", Vector3(0, 0.02, -0.28), Vector3(0.022, 0.24, 0), STEEL],
			["cyl", Vector3(0, -0.005, -0.08), Vector3(0.05, 0.1, 0), BLUED],
			["box", Vector3(0, -0.12, 0.06), Vector3(0.07, 0.17, 0.09), WOOD],
		],
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
		"parts": [
			["box", Vector3(0, 0, -0.15), Vector3(0.09, 0.1, 0.95), WOOD],
			["box", Vector3(0, -0.05, 0.38), Vector3(0.08, 0.16, 0.32), WOOD],
			["cyl", Vector3(0, 0.04, -0.72), Vector3(0.018, 0.4, 0), STEEL],
			["box", Vector3(0, 0.065, -0.05), Vector3(0.07, 0.05, 0.3), STEEL],
			["box", Vector3(0.06, 0.07, 0.02), Vector3(0.06, 0.02, 0.02), BRASS],
			["box", Vector3(0, -0.09, -0.08), Vector3(0.06, 0.08, 0.12), STEEL],
		],
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
		"parts": [
			["box", Vector3(0, 0, -0.12), Vector3(0.1, 0.12, 0.55), BLUED],
			["cyl", Vector3(0, 0.01, -0.52), Vector3(0.025, 0.3, 0), STEEL],
			["box", Vector3(0, -0.03, 0.27), Vector3(0.08, 0.13, 0.3), WOOD],
			["box", Vector3(0, -0.07, -0.33), Vector3(0.05, 0.12, 0.06), WOOD],
			["drum", Vector3(0, -0.13, -0.12), Vector3(0.11, 0.07, 0), STEEL],
		],
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
		"parts": [
			["box", Vector3(0, 0, -0.1), Vector3(0.08, 0.1, 0.5), STEEL],
			["cyl", Vector3(0, 0.0, -0.48), Vector3(0.022, 0.28, 0), STEEL],
			["box", Vector3(0, -0.17, -0.18), Vector3(0.045, 0.26, 0.06), STEEL],
			["box", Vector3(0, -0.06, 0.1), Vector3(0.06, 0.14, 0.08), Color(0.25, 0.2, 0.17)],
			["box", Vector3(0, 0.02, 0.3), Vector3(0.03, 0.03, 0.3), STEEL],
		],
	},
}

## Weapons that can appear in loot crates (the pistol is the starting weapon).
const LOOT_WEAPONS := ["lee_enfield", "thompson", "mp40", "lee_enfield", "thompson", "webley"]


static func get_weapon(id: String) -> Dictionary:
	return DATA.get(id, {})


## Builds a simple procedural model of the weapon under `parent`.
static func build_model(id: String, parent: Node3D, scale_factor := 1.0) -> void:
	var w: Dictionary = DATA.get(id, {})
	if w.is_empty():
		return
	for part in w["parts"]:
		var mesh := MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = part[3]
		mat.roughness = 0.55 if part[3] != WOOD else 0.85
		mat.metallic = 0.5 if part[3] in [STEEL, BLUED] else 0.0
		if part[0] == "box":
			var b := BoxMesh.new()
			b.size = part[2] * scale_factor
			mesh.mesh = b
		else:
			var c := CylinderMesh.new()
			c.top_radius = part[2].x * scale_factor
			c.bottom_radius = part[2].x * scale_factor
			c.height = part[2].y * scale_factor
			c.radial_segments = 12
			mesh.mesh = c
			if part[0] == "drum":
				mesh.rotation_degrees.z = 90
			else:
				mesh.rotation_degrees.x = 90
		mesh.material_override = mat
		mesh.position = part[1] * scale_factor
		parent.add_child(mesh)
