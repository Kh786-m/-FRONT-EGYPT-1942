extends Node3D
## HARAQ loot crate: a wooden supply crate holding weapons, ammo, medkits and armour.
## The game script checks the player's distance and calls take_* helpers.

const Weapons := preload("res://scripts/weapons.gd")
const G := preload("res://scripts/graphics.gd")
const ARABIC_FONT := preload("res://assets/fonts/NotoKufiArabic-SemiBold.ttf")

const PICKUP_RADIUS := 1.7

## contents keys: "weapon" (String id or ""), "ammo" ({type: count}), "medkits" (int), "armor" (float)
var contents := {"weapon": "", "ammo": {}, "medkits": 0, "armor": 0.0}
var _label: Label3D
var _bob := 0.0
var _lid: Node3D
var _weapon_model: Node3D
var _model_y := 1.05


func setup(p_contents: Dictionary, small := false) -> void:
	contents = p_contents
	var wood := G.pbr("planks", Color(0.78, 0.66, 0.46), 1.6, true, 0.9, 0.0, 1.0, false)
	var band := G.pbr("metal_rust", Color(0.55, 0.47, 0.32), 2.0, true, 0.5, 0.6, 0.6, false)
	var s := 0.7 if small else 1.0
	_add_box(Vector3(0, 0.3 * s, 0), Vector3(1.0, 0.6, 0.62) * s, wood)
	_add_box(Vector3(0, 0.3 * s, 0), Vector3(1.03, 0.08, 0.65) * s, band)
	_add_box(Vector3(-0.38 * s, 0.3 * s, 0), Vector3(0.06, 0.62, 0.65) * s, band)
	_add_box(Vector3(0.38 * s, 0.3 * s, 0), Vector3(0.06, 0.62, 0.65) * s, band)
	_lid = Node3D.new()
	add_child(_lid)
	var lid_mesh := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(1.04, 0.07, 0.66) * s
	lid_mesh.mesh = b
	lid_mesh.material_override = wood
	lid_mesh.position = Vector3(0, 0.63 * s, 0)
	_lid.add_child(lid_mesh)
	# A floating weapon model shows what is inside.
	if contents.get("weapon", "") != "":
		_weapon_model = Node3D.new()
		_model_y = 1.05 * s
		_weapon_model.position = Vector3(0, _model_y, 0)
		add_child(_weapon_model)
		Weapons.build_model(contents["weapon"], _weapon_model, 1.3)
	_label = Label3D.new()
	_label.font = ARABIC_FONT
	_label.font_size = 48
	_label.pixel_size = 0.004
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Color("#F3E6D0")
	_label.outline_modulate = Color("#1A1612")
	_label.outline_size = 10
	_label.position = Vector3(0, 1.5 * s, 0)
	_label.visibility_range_end = 16.0
	_label.no_depth_test = false
	add_child(_label)
	refresh_label()


func _add_box(pos: Vector3, size: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	m.position = pos
	add_child(m)


func _process(delta: float) -> void:
	_bob += delta
	if _weapon_model:
		_weapon_model.rotation.y = _bob * 1.2
		_weapon_model.position.y = _model_y + sin(_bob * 2.0) * 0.06


func is_empty() -> bool:
	return contents.get("weapon", "") == "" and (contents.get("ammo", {}) as Dictionary).is_empty() \
		and int(contents.get("medkits", 0)) <= 0 and float(contents.get("armor", 0.0)) <= 0.0


func take_weapon() -> String:
	var w: String = contents.get("weapon", "")
	contents["weapon"] = ""
	if _weapon_model:
		_weapon_model.queue_free()
		_weapon_model = null
	refresh_label()
	return w


func summary() -> String:
	var parts: PackedStringArray = []
	var w: String = contents.get("weapon", "")
	if w != "":
		parts.append(Weapons.DATA[w]["name"])
	var ammo: Dictionary = contents.get("ammo", {})
	for t in ammo:
		parts.append("%s x%d" % [Weapons.AMMO_NAMES.get(t, t), ammo[t]])
	if int(contents.get("medkits", 0)) > 0:
		parts.append("MEDKIT x%d" % int(contents["medkits"]))
	if float(contents.get("armor", 0.0)) > 0.0:
		parts.append("ARMOR %d" % int(contents["armor"]))
	return " · ".join(parts)


func refresh_label() -> void:
	if _label:
		_label.text = "صندوق إمداد\n" + summary()


## Random contents for a crate placed on the map.
static func roll_map_crate(rng: RandomNumberGenerator) -> Dictionary:
	var c := {"weapon": "", "ammo": {}, "medkits": 0, "armor": 0.0}
	if rng.randf() < 0.45:
		c["weapon"] = Weapons.LOOT_WEAPONS[rng.randi() % Weapons.LOOT_WEAPONS.size()]
		var t: String = Weapons.DATA[c["weapon"]]["ammo"]
		c["ammo"][t] = int(Weapons.DATA[c["weapon"]]["mag"]) * 2
	var types := ["pistol", "rifle", "smg"]
	var t2: String = types[rng.randi() % types.size()]
	var amount := {"pistol": 18, "rifle": 15, "smg": 60}
	c["ammo"][t2] = int(c["ammo"].get(t2, 0)) + amount[t2]
	if rng.randf() < 0.35:
		c["medkits"] = 1
	if rng.randf() < 0.25:
		c["armor"] = 50.0
	return c


## Smaller drop left behind by a fallen enemy soldier.
static func roll_enemy_drop(rng: RandomNumberGenerator) -> Dictionary:
	var c := {"weapon": "", "ammo": {}, "medkits": 0, "armor": 0.0}
	if rng.randf() < 0.5:
		c["ammo"]["rifle"] = 10
	else:
		c["ammo"]["smg"] = 40
	if rng.randf() < 0.3:
		c["ammo"]["pistol"] = 12
	if rng.randf() < 0.25:
		c["medkits"] = 1
	if rng.randf() < 0.15:
		c["armor"] = 25.0
	if rng.randf() < 0.18:
		c["weapon"] = ["mp40", "lee_enfield", "thompson"][rng.randi() % 3]
	return c
