extends "res://scripts/missions/mission_base.gd"
## Mission 2 / new map — Alexandria Eastern Harbour at dusk, autumn 1942.
## Fictionalised layout: Corniche + tram line, quay warehouses, cranes,
## moored feluccas, and a Qaitbay-inspired fort on the western mole.

func _mission_id() -> String: return "m02_alexandria_harbor"
func _mission_title() -> String: return "ميناء الإسكندرية | Alexandria Harbour"
func _briefing_text() -> String:
	return "الإسكندرية — الغروب، 1942\nمخربين بيزرعوا عبوات في مخازن الميناء. أوقفهم قبل ما المدينة تولّع.\nSaboteurs are rigging the harbour warehouses. Stop all 8 before nightfall."
func _objective_text() -> String: return "OBJECTIVE: stop the 8 saboteurs  |  الهدف: أوقف المخربين الـ8"
func _player_spawn() -> Vector3: return Vector3(0, 2, 44)
func _sky_preset() -> String: return "coast_dusk"

var water_mat: ShaderMaterial

func _create_world() -> void:
	var paving := material(Color(0.60, 0.55, 0.47))
	var asphalt := material(Color(0.25, 0.24, 0.23))
	var quay_stone := material(Color(0.50, 0.46, 0.40))
	# Land (quay + corniche + city) and sea.
	box(self, Vector3(0, -0.5, 30), Vector3(200, 1, 100), paving)
	box(self, Vector3(0, -2.5, -20.5), Vector3(200, 5, 1.2), quay_stone)  # quay wall face
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(500, 300)
	pm.subdivide_width = 80 if Campaign.quality_high else 20
	pm.subdivide_depth = 50 if Campaign.quality_high else 12
	sea.mesh = pm
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://assets/shaders/water.gdshader")
	sea.material_override = water_mat
	sea.position = Vector3(0, -1.4, -170)
	add_child(sea)
	# Corniche road + tram rails.
	box(self, Vector3(0, 0.01, 32), Vector3(200, 0.04, 12), asphalt, false)
	for z in [30.6, 31.6, 33.4, 34.4]:
		box(self, Vector3(0, 0.05, z), Vector3(200, 0.06, 0.1), material(Color(0.3, 0.3, 0.32), 0.3, 0.8), false)
	_tram(Vector3(-22, 0, 32))
	_bollards()
	_warehouses()
	_cranes()
	_feluccas()
	_city_block()
	_fort(Vector3(-78, 0, -48))
	_cover()
	_bounds()

func _tram(pos: Vector3) -> void:
	var body := material(Color(0.78, 0.62, 0.22), 0.6)
	var roof := material(Color(0.85, 0.82, 0.75), 0.6)
	var glass := material(Color(0.18, 0.24, 0.28), 0.1, 0.2)
	box(self, pos + Vector3(0, 1.75, 0.4), Vector3(11, 2.3, 2.4), body)
	box(self, pos + Vector3(0, 3.0, 0.4), Vector3(11.4, 0.25, 2.6), roof, false)
	for i in range(6):
		box(self, pos + Vector3(-4.5 + i * 1.8, 2.2, 0.4), Vector3(1.2, 0.8, 2.45), glass, false)
	LevelKit.arabic_sign(self, "ترام الرمل  RAMLEH TRAM", pos + Vector3(0, 3.4, 1.8), 0.0, Color(0.95, 0.9, 0.75), 70)

func _bollards() -> void:
	var iron := material(Color(0.12, 0.12, 0.12), 0.4, 0.7)
	for i in range(20):
		LevelKit.cylinder(self, Vector3(-95 + i * 10, 0.35, -19.4), 0.22, 0.7, iron, true, 10)

func _warehouses() -> void:
	var walls := [Color(0.72, 0.60, 0.44), Color(0.66, 0.52, 0.40), Color(0.74, 0.66, 0.52), Color(0.62, 0.55, 0.45)]
	var roof := material(Color(0.42, 0.30, 0.24))
	var door := material(Color(0.22, 0.17, 0.12))
	for i in range(4):
		var x := -48.0 + i * 30.0
		var c := Vector3(x, 0, 2)
		box(self, c + Vector3(0, 4, 0), Vector3(20, 8, 12), material(walls[i]))
		box(self, c + Vector3(0, 8.4, 0), Vector3(21, 0.8, 13), roof, false)
		box(self, c + Vector3(0, 2.2, -6.05), Vector3(6, 4.4, 0.2), door, false)
		box(self, c + Vector3(0, 2.2, 6.05), Vector3(6, 4.4, 0.2), door, false)
		LevelKit.arabic_sign(self, "مخزن %d  |  WAREHOUSE %d" % [i + 1, i + 1], c + Vector3(0, 6.2, -6.2), 180.0, Color(0.12, 0.08, 0.04), 110)

func _cranes() -> void:
	var steel := material(Color(0.55, 0.22, 0.12), 0.6, 0.4)
	for x in [-30.0, 25.0]:
		for dx in [-1.6, 1.6]:
			for dz in [-1.6, 1.6]:
				box(self, Vector3(x + dx, 6, -15 + dz), Vector3(0.4, 12, 0.4), steel)
		box(self, Vector3(x, 12.5, -15), Vector3(4, 1.2, 4), steel, false)
		box(self, Vector3(x, 13.6, -22), Vector3(0.8, 0.8, 20), steel, false)
		box(self, Vector3(x, 9.5, -30), Vector3(0.05, 8, 0.05), material(Color(0.1, 0.1, 0.1)), false)

func _feluccas() -> void:
	var hull := material(Color(0.33, 0.22, 0.14), 0.7)
	var sail := material(Color(0.93, 0.90, 0.82), 0.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1882
	for i in range(7):
		var p := Vector3(-60 + i * 19 + rng.randf_range(-4, 4), -1.0, -28 - rng.randf_range(0, 14))
		var boat := Node3D.new()
		boat.position = p
		boat.rotation.y = rng.randf_range(-0.4, 0.4)
		add_child(boat)
		box(boat, Vector3(0, 0, 0), Vector3(2.2, 0.9, 7), hull, false)
		box(boat, Vector3(0, 3.2, 0.5), Vector3(0.12, 6, 0.12), hull, false)
		var s := MeshInstance3D.new()
		var pr := PrismMesh.new()
		pr.size = Vector3(4.5, 5.5, 0.05)
		pr.left_to_right = 0.0
		s.mesh = pr
		s.material_override = sail
		s.position = Vector3(0, 3.8, 0.5)
		s.rotation_degrees.y = 90
		boat.add_child(s)
		boat.set_meta("bob", rng.randf() * TAU)
		boat.add_to_group("bobbing")

func _city_block() -> void:
	var tones := [Color(0.86, 0.80, 0.66), Color(0.80, 0.70, 0.55), Color(0.90, 0.85, 0.74), Color(0.76, 0.64, 0.50)]
	var shutter := material(Color(0.25, 0.38, 0.32))
	var iron := material(Color(0.1, 0.1, 0.1), 0.5, 0.5)
	var names := ["قهوة الكورنيش", "صيدلية الإسكندرية", "مكتبة الرمل", "فندق البحر", "حلواني بحري", "ترزي المنشية"]
	for i in range(12):
		var x := -88.0 + i * 16.0
		var floors := 3 + (i * 7) % 3
		var h := floors * 3.4
		var c := Vector3(x, h / 2.0, 52)
		box(self, c, Vector3(14, h, 10), material(tones[i % 4]))
		for f in range(1, floors):
			box(self, Vector3(x, f * 3.4, 46.6), Vector3(10, 0.18, 1.4), iron, false)
			for k in range(4):
				box(self, Vector3(x - 4.5 + k * 3, f * 3.4 + 1.3, 46.95), Vector3(1.2, 1.9, 0.1), shutter, false)
		if i % 2 == 0:
			LevelKit.arabic_sign(self, names[(i / 2) % names.size()], Vector3(x, 2.9, 46.85), 180.0, Color(0.1, 0.07, 0.04), 100)
	# Street lamps along the Corniche (lit at dusk on high quality).
	for i in range(10):
		var p := Vector3(-80 + i * 18, 0, 26)
		LevelKit.cylinder(self, p + Vector3(0, 2.5, 0), 0.08, 5, iron, true, 8)
		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.44
		bulb.mesh = sm
		var em := StandardMaterial3D.new()
		em.albedo_color = Color(1, 0.85, 0.6)
		em.emission_enabled = true
		em.emission = Color(1, 0.78, 0.45)
		em.emission_energy_multiplier = 2.5
		bulb.material_override = em
		bulb.position = p + Vector3(0, 5.1, 0)
		add_child(bulb)
		if Campaign.quality_high and i % 2 == 0:
			var l := OmniLight3D.new()
			l.light_color = Color(1, 0.75, 0.45)
			l.omni_range = 12
			l.light_energy = 1.4
			l.position = p + Vector3(0, 4.8, 0)
			add_child(l)
	for i in range(9):
		LevelKit.palm(self, Vector3(-75 + i * 19, 0, 38), 5.0)

func _fort(c: Vector3) -> void:
	var lime := material(Color(0.80, 0.74, 0.62))
	box(self, c + Vector3(0, -0.5, 0), Vector3(46, 1, 40), material(Color(0.6, 0.55, 0.47)))  # mole
	box(self, c + Vector3(0, 6, 0), Vector3(14, 12, 14), lime)            # keep
	box(self, c + Vector3(0, 13, 0), Vector3(6, 2.5, 6), lime)            # minaret base
	LevelKit.cylinder(self, c + Vector3(0, 15.5, 0), 1.2, 3.0, lime, false, 12)
	for dx in [-17.0, 17.0]:
		for dz in [-15.0, 15.0]:
			LevelKit.cylinder(self, c + Vector3(dx, 4.5, dz), 3.0, 9, lime, true, 20)
	box(self, c + Vector3(0, 3, -15), Vector3(34, 6, 2), lime)
	box(self, c + Vector3(0, 3, 15), Vector3(34, 6, 2), lime)
	box(self, c + Vector3(-17, 3, 0), Vector3(2, 6, 30), lime)
	box(self, c + Vector3(17, 3, 4), Vector3(2, 6, 22), lime)  # gate gap on the city side
	for i in range(14):
		box(self, c + Vector3(-15 + i * 2.3, 6.4, -15), Vector3(1.0, 0.8, 2), lime, false)

func _cover() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var barrel := material(Color(0.25, 0.32, 0.28), 0.6, 0.3)
	for i in range(26):
		var p := Vector3(rng.randf_range(-90, 90), 0, rng.randf_range(-17, 22))
		if absf(p.z - 2) < 7.5 and fmod(absf(p.x + 48), 30.0) < 11.0: continue
		if i % 3 == 0:
			LevelKit.cylinder(self, p + Vector3(0, 0.6, 0), 0.45, 1.2, barrel, true, 12)
		else:
			LevelKit.crate_stack(self, p, i)
	# sandbag positions near the tram line
	var bag := material(Color(0.62, 0.55, 0.40))
	for x in [-60.0, -10.0, 35.0, 70.0]:
		box(self, Vector3(x, 0.5, 24), Vector3(4.5, 1.0, 1.0), bag)

func _bounds() -> void:
	var inv := StandardMaterial3D.new()
	inv.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	inv.albedo_color = Color(0, 0, 0, 0)
	box(self, Vector3(0, 5, -20.6), Vector3(200, 10, 0.5), inv).get_child(0).visible = false
	box(self, Vector3(0, 5, 79), Vector3(200, 10, 0.5), inv).get_child(0).visible = false
	box(self, Vector3(-100, 5, 30), Vector3(0.5, 10, 100), inv).get_child(0).visible = false
	box(self, Vector3(100, 5, 30), Vector3(0.5, 10, 100), inv).get_child(0).visible = false

func _create_egyptian_life() -> void:
	# Market corner at the east end of the Corniche (reuses prototype props).
	var cloth := [material(Color(0.65, 0.18, 0.11)), material(Color(0.15, 0.35, 0.55)), material(Color(0.85, 0.65, 0.2))]
	var wood := material(Color(0.31, 0.20, 0.12))
	for i in range(4):
		var p := Vector3(62 + i * 6, 0, 18)
		box(self, p + Vector3(0, 0.6, 0), Vector3(2.4, 1.2, 1.2), wood)
		box(self, p + Vector3(0, 2.4, 0), Vector3(3, 0.12, 2.4), cloth[i % 3], false)
		for dx in [-1.3, 1.3]:
			box(self, p + Vector3(dx, 1.2, 1.0), Vector3(0.1, 2.4, 0.1), wood, false)
	LevelKit.cart(self, Vector3(55, 0, 14))
	LevelKit.arabic_sign(self, "سوق السمك  |  FISH MARKET", Vector3(71, 3.6, 18), 180.0, Color(0.95, 0.9, 0.75), 90)

func _create_targets() -> void:
	var routes := [
		[Vector3(-58, 0.1, -10), Vector3(-38, 0.1, -10), Vector3(-38, 0.1, -16)],
		[Vector3(-28, 0.1, -9), Vector3(-8, 0.1, -9)],
		[Vector3(2, 0.1, -10), Vector3(22, 0.1, -10), Vector3(22, 0.1, -17)],
		[Vector3(32, 0.1, -9), Vector3(52, 0.1, -9)],
		[Vector3(-50, 0.1, 13), Vector3(-30, 0.1, 13)],
		[Vector3(-12, 0.1, 13), Vector3(12, 0.1, 13)],
		[Vector3(30, 0.1, 14), Vector3(48, 0.1, 14), Vector3(48, 0.1, 20)],
		[Vector3(58, 0.1, 10), Vector3(82, 0.1, 10), Vector3(82, 0.1, 4)],
	]
	for r in routes:
		var e := _spawn_enemy(r[0], r)
		e.view_range = 34.0

func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for b in get_tree().get_nodes_in_group("bobbing"):
		var ph: float = b.get_meta("bob")
		b.position.y = -1.0 + sin(t * 1.1 + ph) * 0.15
		b.rotation.z = sin(t * 0.9 + ph) * 0.04
