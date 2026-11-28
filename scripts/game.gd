extends Node3D
## HARAQ (حَرَق) — WAR FRONT: EGYPT 1942
## Procedural offline battle royale (Godot 4.3, GL Compatibility renderer for the widest
## Android support). v0.4: PBR desert terrain, Mediterranean coast, atmosphere, quality presets.

const EnemyScript := preload("res://scripts/enemy.gd")
const ZoneScript := preload("res://scripts/zone.gd")
const LootScript := preload("res://scripts/loot.gd")
const MinimapScript := preload("res://scripts/minimap.gd")
const Weapons := preload("res://scripts/weapons.gd")
const G := preload("res://scripts/graphics.gd")
const Terrain := preload("res://scripts/terrain.gd")
const Props := preload("res://scripts/props.gd")
const Fx := preload("res://scripts/fx.gd")
const NavScript := preload("res://scripts/nav.gd")
const CoverScript := preload("res://scripts/cover.gd")
const AudioScript := preload("res://scripts/audio.gd")
const ARABIC_FONT := preload("res://assets/fonts/NotoKufiArabic-SemiBold.ttf")

# HARAQ palette
const INK := Color("#1A1612")
const SAND := Color("#E4D2B0")
const BONE := Color("#F3E6D0")
const EMBER := Color("#E24A1B")
const SEA := Color("#1E4C5A")
const KHAKI := Color("#8A7048")
const BRASS := Color("#C6A15B")

const WALK_SPEED := 6.5
const RUN_SPEED := 10.0
const JUMP_SPEED := 8.0
const GRAVITY := 24.0
const MOUSE_SENS := 0.0025
const TOUCH_SENS := 0.0035
const HIP_FOV := 75.0
const ADS_FOV := 48.0
const GUN_HIP_POS := Vector3(0.3, -0.3, -0.95)
const GUN_ADS_POS := Vector3(0.0, -0.13, -0.62)
const ENEMY_COUNT := 20
const LOOT_CRATE_COUNT := 34
const MAX_ARMOR := 100.0
const ARMOR_ABSORB := 0.6
const MAX_MEDKITS := 3
const MEDKIT_HEAL := 50.0
const SWITCH_TIME := 0.45
const MAX_HEALTH := 100
const REGEN_DELAY := 5.0
const REGEN_RATE := 4.0
const SHOT_ALERT_RADIUS := 16.0

enum GameState { INTRO, PLAYING, DEAD, WON }

var state := GameState.INTRO
var player: CharacterBody3D
var head: Node3D
var camera: Camera3D
var gun: Node3D
var zone: Node3D
var minimap: Control
var zone_label: Label
var weapon_label: Label
var pickup_label: Label
var alive_label: Label
var interact_button: Button
var swap_button: Button
var heal_button: Button
var hud: Label
var status: Label
var health_label: Label
var joy_base: Control
var joy_knob: Control
var fire_button: Button
var jump_button: Button
var sprint_button: Button
var reload_button: Button
var aim_button: Button
var hit_marker: Label
var damage_flash: ColorRect
var shot_flash: OmniLight3D
var intro_overlay: Control
var end_overlay: Control
var joystick_id := -1
var look_id := -1
var joystick_vector := Vector2.ZERO
var touch_last := Vector2.ZERO
var fire_held := false
var sprint_held := false
var cooldown := 0.0
var score := 0
var experience_points := 0
var reward_coins := 0
var enemies: Array[CharacterBody3D] = []
var obstacles: Array[AABB] = []
var recoil := 0.0
var health := float(MAX_HEALTH)
var since_damage := 99.0
## Two weapon slots ("" = empty). Rounds in each weapon's magazine are tracked per weapon id,
## reserve ammo per ammo type (see weapons.gd).
var slots: Array[String] = ["webley", ""]
var current_slot := 0
var mag_ammo := {"webley": 6}
var reserve := {"pistol": 24, "rifle": 0, "smg": 0}
var armor := 0.0
var medkits := 0
var switch_timer := 0.0
var trigger_released := true
var loot_crates: Array[Node3D] = []
var nearby_crate: Node3D = null
var loot_rng := RandomNumberGenerator.new()
var placement := 0
var zone_kills := 0
var last_player_attacker: Node3D = null
var pickup_toast := ""
var pickup_toast_timer := 0.0
var reload_timer := 0.0
var aiming := false
var hit_marker_timer := 0.0
var mission_time := 0.0
var is_mobile := false
var quality := 1
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var bushes: MultiMeshInstance3D
var bush_total := 0
var smoke_plumes: Array[Node3D] = []
var player_flash: MeshInstance3D
var flash_timer := 0.0
var quality_buttons: Array[Button] = []
var touch_actions := {}
var touch_owner := {}
var joy_home := Vector2.ZERO
var joy_zone := Rect2()
var touch_layout_size := Vector2.ZERO
var nav: RefCounted
var cover: RefCounted
var kill_feed: Label
var kill_feed_entries: Array = [] # [{text, t}]
var kills_by_enemies := 0
## Battle royale: soldiers fight each other too (tests can switch it off to isolate one soldier).
var free_for_all := true
var enemy_loots := 0
const CALLSIGNS := ["Hans", "Tommy", "Fritz", "Jock", "Klaus", "Archie", "Otto", "Bertie", "Kurt", "Alfie", "Ernst", "Monty", "Wolf", "Reggie", "Karl", "Harry", "Dieter", "Percy", "Gunther", "Stan"]
const PLAYER_CALLSIGN := "خالد"
const ZONE_CALLSIGN := "الدايرة"
var step_distance := 0.0
var idle_time := 0.0
var _style_on: StyleBoxFlat
var _style_off: StyleBoxFlat
var volume_slider: HSlider
var mute_button: Button
var music_slider: HSlider
var sfx_slider: HSlider
var audio: Node


func _ready() -> void:
	randomize()
	is_mobile = OS.has_feature("mobile") or "--touch-ui" in OS.get_cmdline_user_args()
	audio = AudioScript.new()
	audio.name = "Audio"
	add_child(audio)
	quality = G.load_quality()
	_create_world()
	_create_egyptian_life()
	_build_nav()
	_create_player()
	_create_zone()
	_create_loot()
	_create_enemies()
	_create_ui()
	_create_muzzle_flash()
	_create_hero_intro()
	apply_quality(quality)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if "--autostart" in OS.get_cmdline_user_args():
		_start_hero_mission()


func _build_nav() -> void:
	nav = NavScript.new()
	nav.build(obstacles, func(x: float, z: float) -> float: return Terrain.height(x, z))
	cover = CoverScript.new()
	cover.build(obstacles, nav, func(x: float, z: float) -> float: return Terrain.height(x, z))


func is_playing() -> bool:
	return state == GameState.PLAYING


func is_player_moving_fast() -> bool:
	return Vector2(player.velocity.x, player.velocity.z).length() > WALK_SPEED + 0.5


func material(color: Color, rough: float = 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


func box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, solid := true, on_ground := true) -> Node3D:
	var register := parent == self and size.y < 50.0 and pos.y > -0.5
	if parent == self and on_ground:
		# Sit the box on the dunes: sink it to the lowest point under its footprint.
		pos.y += Terrain.footprint_min(pos, size) - 0.12
	var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
	parent.add_child(root)
	root.position = pos
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = mat
	root.add_child(mesh)
	if solid:
		var collider := CollisionShape3D.new()
		var c := BoxShape3D.new()
		c.size = size
		collider.shape = c
		root.add_child(collider)
		if register:
			obstacles.append(AABB(pos - size / 2.0, size))
	return root


func _create_world() -> void:
	world_env = WorldEnvironment.new()
	add_child(world_env)
	var e := Environment.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/sky.gdshader")
	sky_mat.set_shader_parameter("cloud_noise", Terrain.noise_texture(0.02, 99, false, 512))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = SAND.lerp(SEA.lightened(0.5), 0.25)
	e.ambient_light_energy = 0.72
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 0.95
	e.tonemap_white = 6.0
	# Warm desert haze: distance fog tinted bone/sand, a little thicker near the ground.
	e.fog_enabled = true
	e.fog_light_color = BONE.lerp(SAND, 0.35)
	e.fog_light_energy = 1.0
	e.fog_sun_scatter = 0.25
	e.fog_density = 0.005
	e.fog_sky_affect = 0.45
	e.fog_height = 1.0
	e.fog_height_density = 0.015
	e.glow_enabled = true
	e.glow_intensity = 0.55
	e.glow_strength = 0.9
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 1.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# Colour grading toward the HARAQ palette: slightly warmer, less saturated, more contrast.
	e.adjustment_enabled = true
	e.adjustment_brightness = 1.0
	e.adjustment_contrast = 1.1
	e.adjustment_saturation = 0.9
	world_env.environment = e
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -42, 0)
	sun.light_color = Color(1.0, 0.9, 0.74)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.6
	sun.directional_shadow_fade_start = 0.75
	add_child(sun)
	# Terrain: rolling dunes (visual mesh + 1 m heightmap collision) and the sea to the north.
	var ground := StaticBody3D.new()
	ground.name = "Terrain"
	add_child(ground)
	var terrain_mesh := MeshInstance3D.new()
	terrain_mesh.mesh = Terrain.build_mesh()
	terrain_mesh.material_override = Terrain.terrain_material()
	ground.add_child(terrain_mesh)
	ground.add_child(Terrain.build_collision())
	add_child(Terrain.build_sea())
	var sandstone := G.pbr("sandstone", Color(1.0, 0.9, 0.74), 0.4)
	var sandstone2 := G.pbr("sandstone", Color(0.9, 0.78, 0.6), 0.33)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1942
	for i in range(75):
		var x := rng.randf_range(-76, 76)
		var z := rng.randf_range(-76, 76)
		if absf(x) < 10 and absf(z) < 10:
			continue
		var h := rng.randf_range(1.4, 5.5)
		var size := Vector3(rng.randf_range(2.0, 6.0), h, rng.randf_range(2.0, 6.0))
		if i % 6 != 3:
			# Boulders read better when they are not taller than they are wide.
			h = minf(h, maxf(size.x, size.z) * 0.95)
			size.y = h
		if i % 6 == 3:
			# Ruined sandstone block.
			box(self, Vector3(x, h / 2.0, z), size, sandstone if i % 2 == 0 else sandstone2)
		else:
			_add_boulder(Vector3(x, 0, z), size, i)
	for i in range(18):
		var z := -55.0 + i * 6.0
		box(self, Vector3(-14, 1.2, z), Vector3(1.0, 2.4, 4.5), sandstone2 if i % 3 == 0 else sandstone)
	# Sandbag emplacements (same cover footprint as before).
	var bag_xf: Array[Transform3D] = []
	var fill := G.pbr("sand_coarse", Color(0.95, 0.85, 0.68), 0.5)
	for i in range(10):
		var x := -36.0 + i * 8.0
		box(self, Vector3(x, 0.55, -25), Vector3(3.3, 1.1, 1.0), fill)
		for row in [-0.6, 0.6]:
			bag_xf.append_array(Props.sandbag_wall_transforms(Vector3(x - 1.8, 0, -25 + row), Vector3(x + 1.8, 0, -25 + row), 6))
	# Broken desert walls and a clear central combat lane.
	box(self, Vector3(17, 1.7, -10), Vector3(14, 3.4, 1.4), sandstone)
	box(self, Vector3(23, 1.7, -20), Vector3(1.4, 3.4, 18), sandstone2)
	box(self, Vector3(-18, 1.3, 8), Vector3(11, 2.6, 1.2), sandstone)
	_create_battlefield(bag_xf)
	# Invisible boundary walls so nobody walks off the edge of the map.
	for side in [Vector3(90, 5, 0), Vector3(-90, 5, 0), Vector3(0, 5, 90), Vector3(0, 5, -90)]:
		var wall := StaticBody3D.new()
		add_child(wall)
		wall.position = side
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1, 10, 180) if side.x != 0.0 else Vector3(180, 10, 1)
		col.shape = shape
		wall.add_child(col)


func _add_boulder(pos: Vector3, size: Vector3, seed_v: int) -> void:
	var gy := Terrain.footprint_min(pos, size) - 0.3
	Props.add_rock(self, Vector3(pos.x, gy, pos.z), Vector3(size.x * 0.95, size.y + 0.3, size.z * 0.95), seed_v, 0.0)
	obstacles.append(AABB(Vector3(pos.x - size.x * 0.5, gy, pos.z - size.z * 0.5), Vector3(size.x, size.y + 0.3, size.z)))


func _area_clear(center: Vector3, half: Vector3) -> bool:
	var probe := AABB(center - Vector3(half.x, -0.1 - Terrain.height(center.x, center.z), half.z), Vector3(half.x * 2.0, 3.0, half.z * 2.0))
	for o in obstacles:
		if o.intersects(probe):
			return false
	return true


## Find a free spot near `want` (spiral search) for a prop with the given half extents.
func _free_spot(want: Vector3, half: Vector3) -> Vector3:
	for k in range(40):
		var a := float(k) * 2.4
		var r := float(k) * 1.5
		var p := want + Vector3(cos(a) * r, 0, sin(a) * r)
		if absf(p.x) < 80 and absf(p.z) < 80 and _area_clear(p, half):
			return p
	return want


## El Alamein 1942 set dressing: wrecks, smoke, wire, sandbag pits, camel thorn, beach defences.
func _create_battlefield(bag_xf: Array[Transform3D]) -> void:
	var wrecks := [
		["tank", Vector3(32, 0, -46), 0.6, 0], ["tank", Vector3(-56, 0, 42), 2.3, 1], ["tank", Vector3(54, 0, 30), -0.9, 0],
		["truck", Vector3(8, 0, -64), 1.2, 0], ["truck", Vector3(-62, 0, -62), -0.4, 0], ["tank", Vector3(-8, 0, 58), 1.9, 1],
	]
	var n := 0
	for w in wrecks:
		var half := Vector3(3.6, 0, 3.6)
		var p := _free_spot(w[1], half)
		var body: StaticBody3D
		if w[0] == "tank":
			body = Props.add_tank(self, p, w[2], w[3])
		else:
			body = Props.add_truck(self, p, w[2])
		body.set_meta("metal", true)
		obstacles.append(AABB(Vector3(p.x - 3.3, body.position.y, p.z - 3.3), Vector3(6.6, 2.6, 6.6)))
		if n % 2 == 0 and Fx.enabled():
			smoke_plumes.append(Props.add_smoke(self, body.position + Vector3(0, 2.0, 0)))
		n += 1
	# Circular sandbag gun pits.
	for c in [Vector3(40, 0, 6), Vector3(-6, 0, -48), Vector3(-50, 0, 18), Vector3(60, 0, -62)]:
		var p := _free_spot(c, Vector3(2.6, 0, 2.6))
		for k in range(12):
			if k == 3 or k == 4:
				continue # opening
			var a0 := TAU * k / 12.0
			var a1 := TAU * (k + 1) / 12.0
			bag_xf.append_array(Props.sandbag_wall_transforms(p + Vector3(cos(a0), 0, sin(a0)) * 2.2, p + Vector3(cos(a1), 0, sin(a1)) * 2.2, 4))
			var mid := p + Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5)) * 2.2
			var col := StaticBody3D.new()
			add_child(col)
			col.position = Vector3(mid.x, Terrain.height(mid.x, mid.z) + 0.45, mid.z)
			col.rotation.y = -(a0 + a1) * 0.5
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(0.7, 0.9, 1.2)
			cs.shape = bs
			col.add_child(cs)
		obstacles.append(AABB(Vector3(p.x - 2.6, Terrain.height(p.x, p.z), p.z - 2.6), Vector3(5.2, 1.0, 5.2)))
	Props.sandbag_multimesh(self, bag_xf)
	# Concertina wire in front of the sandbag line and along the beach.
	for seg in [[Vector3(-38, 0, -29.5), Vector3(-22, 0, -29.5)], [Vector3(-12, 0, -29.5), Vector3(8, 0, -29.5)], [Vector3(16, 0, -29.5), Vector3(36, 0, -29.5)],
			[Vector3(-80, 0, -88), Vector3(-30, 0, -88)], [Vector3(-20, 0, -88), Vector3(30, 0, -88)], [Vector3(40, 0, -88), Vector3(84, 0, -88)]]:
		Props.add_wire(self, seg[0], seg[1])
	# Steel beach obstacles ("hedgehogs") on the sand outside the arena.
	var steel := G.pbr("metal_rust", Color(0.4, 0.33, 0.27), 1.0, true, 0.7, 0.6)
	var hrng := RandomNumberGenerator.new()
	hrng.seed = 42
	for i in range(14):
		var x := -120.0 + i * 18.0 + hrng.randf_range(-4, 4)
		var z := Terrain.shore_z(x) + hrng.randf_range(2.0, 9.0)
		var hh := Node3D.new()
		add_child(hh)
		hh.position = Vector3(x, Terrain.height(x, z) + 0.55, z)
		hh.rotation.y = hrng.randf() * TAU
		for r in [Vector3(0.6, 0, 0), Vector3(0, 0, 0.6), Vector3(0, PI * 0.5, 0.6)]:
			var bm := MeshInstance3D.new()
			var bb := BoxMesh.new()
			bb.size = Vector3(0.15, 1.7, 0.15)
			bm.mesh = bb
			bm.material_override = steel
			bm.rotation = r
			hh.add_child(bm)
	# Date palms along the coast road.
	for i in range(9):
		var x := -70.0 + i * 17.0 + hrng.randf_range(-3, 3)
		var z := -84.0 + hrng.randf_range(-2, 2)
		if _area_clear(Vector3(x, 0, z), Vector3(0.6, 0, 0.6)):
			Props.add_palm(self, Vector3(x, 0, z), hrng.randf_range(5.5, 8.0), i + 10)
	bushes = Props.scatter_bushes(self, 340, func(p: Vector3) -> bool: return _area_clear(p, Vector3(0.8, 0, 0.8)))
	bush_total = bushes.multimesh.visible_instance_count


func _create_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.position = Vector3(0, Terrain.height(0, 12) + 1.0, 12)
	add_child(player)
	var collider := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	collider.position.y = 0.9
	collider.shape = cap
	player.add_child(collider)
	head = Node3D.new()
	head.position.y = 1.62
	player.add_child(head)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = HIP_FOV
	camera.near = 0.03
	head.add_child(camera)
	gun = Node3D.new()
	gun.position = GUN_HIP_POS
	camera.add_child(gun)
	_rebuild_gun_model()


func current_weapon() -> String:
	return slots[current_slot]


func current_stats() -> Dictionary:
	return Weapons.get_weapon(current_weapon())


func _rebuild_gun_model() -> void:
	for c in gun.get_children():
		gun.remove_child(c)
		if c != player_flash:
			c.queue_free()
	if current_weapon() != "":
		Weapons.build_model(current_weapon(), gun, 0.8, false)
		_build_fp_arms()
	if player_flash != null:
		gun.add_child(player_flash)
		_place_flash()


## First-person sleeves and hands gripping the current weapon.
func _build_fp_arms() -> void:
	var w := current_stats()
	var sleeve := G.pbr("linen", Color(0.62, 0.53, 0.37), 6.0, true, 0.95, 0.0, 0.5, false)
	var skin := G.flat(Color(0.66, 0.47, 0.34), 0.75)
	var cuff := G.flat(Color(0.5, 0.42, 0.29), 0.9)
	var grip: Vector3 = (w.get("grip", Vector3(0, -0.08, 0.05)) as Vector3) * 0.8
	var fore: Vector3 = (w.get("fore", Vector3(0, -0.08, -0.25)) as Vector3) * 0.8
	var pistol: bool = current_weapon() == "webley"
	var hands := [[grip + Vector3(0.012, 0.0, 0.0), Vector3(0.22, -0.5, 0.45)]]
	if pistol:
		hands.append([grip + Vector3(-0.045, -0.01, 0.01), Vector3(-0.2, -0.5, 0.42)])
	else:
		hands.append([fore + Vector3(-0.02, -0.01, 0.0), Vector3(-0.28, -0.5, 0.25)])
	for h in hands:
		var hand_pos: Vector3 = h[0]
		var elbow: Vector3 = h[1]
		var hand := MeshInstance3D.new()
		var hb := BoxMesh.new()
		hb.size = Vector3(0.07, 0.085, 0.1)
		hand.mesh = hb
		hand.material_override = skin
		hand.position = hand_pos
		hand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gun.add_child(hand)
		var arm := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		var length := hand_pos.distance_to(elbow)
		cyl.top_radius = 0.036
		cyl.bottom_radius = 0.046
		cyl.height = length
		cyl.radial_segments = 10
		arm.mesh = cyl
		arm.material_override = sleeve
		arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gun.add_child(arm)
		var mid := (hand_pos + elbow) * 0.5
		var up := (hand_pos - elbow).normalized()
		var side := up.cross(Vector3.FORWARD).normalized()
		if side.length() < 0.1:
			side = Vector3.RIGHT
		var fwd := side.cross(up).normalized()
		arm.transform = Transform3D(Basis(side, up, fwd), mid)
		var c := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.04
		cm.bottom_radius = 0.04
		cm.height = 0.035
		cm.radial_segments = 10
		c.mesh = cm
		c.material_override = cuff
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.transform = Transform3D(Basis(side, up, fwd), hand_pos - up * 0.07)
		gun.add_child(c)


func _create_muzzle_flash() -> void:
	shot_flash = OmniLight3D.new()
	shot_flash.light_color = EMBER.lerp(BRASS, 0.4)
	shot_flash.light_energy = 0.0
	shot_flash.omni_range = 4.0
	camera.add_child(shot_flash)
	shot_flash.position = Vector3(0.25, -0.22, -0.9)
	shot_flash.shadow_enabled = false
	player_flash = Fx.flash_mesh(0.3)
	gun.add_child(player_flash)
	_place_flash()


func _place_flash() -> void:
	if player_flash == null:
		return
	var w := current_stats()
	player_flash.position = (w.get("muzzle", Vector3(0, 0, -0.6)) as Vector3) * 0.8


func _reload() -> void:
	var w := current_stats()
	if w.is_empty() or reload_timer > 0.0 or switch_timer > 0.0:
		return
	var id := current_weapon()
	if int(mag_ammo.get(id, 0)) >= int(w["mag"]) or int(reserve.get(w["ammo"], 0)) <= 0:
		return
	reload_timer = float(w["reload"])
	audio.play("reload", -3.0, 0.03)


func _finish_reload() -> void:
	var w := current_stats()
	if w.is_empty():
		return
	var id := current_weapon()
	var have := int(mag_ammo.get(id, 0))
	var count := mini(int(w["mag"]) - have, int(reserve.get(w["ammo"], 0)))
	mag_ammo[id] = have + count
	reserve[w["ammo"]] = int(reserve[w["ammo"]]) - count


## Select weapon slot 0/1 (ignored if that slot is empty).
func switch_to_slot(slot: int) -> void:
	if slot == current_slot or slot < 0 or slot >= slots.size() or slots[slot] == "":
		return
	current_slot = slot
	reload_timer = 0.0
	switch_timer = SWITCH_TIME
	aiming = false
	_rebuild_gun_model()
	gun.position = GUN_HIP_POS + Vector3(0, -0.35, 0)
	audio.play("switch", -6.0, 0.05)


func swap_weapon() -> void:
	switch_to_slot(1 - current_slot)


func use_medkit() -> void:
	if medkits <= 0 or health >= MAX_HEALTH or state != GameState.PLAYING:
		return
	medkits -= 1
	health = minf(MAX_HEALTH, health + MEDKIT_HEAL)
	_toast("+%d HP  إسعاف" % int(MEDKIT_HEAL))


func _toast(text: String) -> void:
	pickup_toast = text
	pickup_toast_timer = 2.2


## Give the player a weapon. Fills an empty slot, otherwise replaces the held weapon
## (the old one is dropped in a small crate). Returns true if taken.
func give_weapon(id: String, allow_replace := true) -> bool:
	if id == "" or not Weapons.DATA.has(id):
		return false
	var w: Dictionary = Weapons.DATA[id]
	if id in slots:
		# Duplicate weapon: convert it into ammo for that weapon.
		var t: String = w["ammo"]
		reserve[t] = mini(int(Weapons.AMMO_MAX[t]), int(reserve.get(t, 0)) + int(w["mag"]))
		_toast("+%d %s" % [int(w["mag"]), Weapons.AMMO_NAMES[t]])
		return true
	var empty := slots.find("")
	if empty != -1:
		slots[empty] = id
		mag_ammo[id] = int(w["mag"])
		switch_to_slot(empty)
		_toast("%s  %s" % [w["name"], w["name_ar"]])
		return true
	if not allow_replace:
		return false
	var old := current_weapon()
	slots[current_slot] = id
	mag_ammo[id] = int(w["mag"])
	if old != "":
		var drop_contents := {"weapon": old, "ammo": {}, "medkits": 0, "armor": 0.0}
		var left := int(mag_ammo.get(old, 0))
		if left > 0:
			drop_contents["ammo"][Weapons.DATA[old]["ammo"]] = left
		mag_ammo.erase(old)
		_spawn_crate(player.global_position + player.global_transform.basis.z * 1.8, drop_contents, true)
	reload_timer = 0.0
	switch_timer = SWITCH_TIME
	_rebuild_gun_model()
	_toast("%s  %s" % [w["name"], w["name_ar"]])
	return true


## Take everything that can be auto-collected from a crate. A weapon is only auto-taken
## if there is a free slot (or it is a duplicate); otherwise E / INTERACT swaps it in.
func _collect_from(crate: Node3D, interact: bool) -> void:
	var c: Dictionary = crate.contents
	var got: PackedStringArray = []
	var ammo: Dictionary = c.get("ammo", {})
	for t in ammo.keys():
		var cap := int(Weapons.AMMO_MAX.get(t, 999))
		var have := int(reserve.get(t, 0))
		var take := mini(int(ammo[t]), cap - have)
		if take > 0:
			reserve[t] = have + take
			got.append("+%d %s" % [take, Weapons.AMMO_NAMES.get(t, t)])
			ammo[t] = int(ammo[t]) - take
		if int(ammo[t]) <= 0:
			ammo.erase(t)
	if int(c.get("medkits", 0)) > 0 and medkits < MAX_MEDKITS:
		var take_m := mini(int(c["medkits"]), MAX_MEDKITS - medkits)
		medkits += take_m
		c["medkits"] = int(c["medkits"]) - take_m
		got.append("+%d MEDKIT" % take_m)
	if float(c.get("armor", 0.0)) > 0.0 and armor < MAX_ARMOR:
		var take_a := minf(float(c["armor"]), MAX_ARMOR - armor)
		armor += take_a
		c["armor"] = float(c["armor"]) - take_a
		got.append("+%d ARMOR" % int(take_a))
	var w: String = c.get("weapon", "")
	if w != "" and (interact or "" in slots or w in slots):
		if give_weapon(w, interact):
			crate.take_weapon()
	if not got.is_empty():
		_toast("  ".join(got))
		audio.play("pickup", -4.0, 0.06)
	crate.refresh_label()
	if crate.is_empty():
		loot_crates.erase(crate)
		crate.queue_free()
		if nearby_crate == crate:
			nearby_crate = null


func interact() -> void:
	if state == GameState.PLAYING and nearby_crate != null and is_instance_valid(nearby_crate):
		_collect_from(nearby_crate, true)


func _spawn_crate(pos: Vector3, contents: Dictionary, small := false) -> Node3D:
	var crate: Node3D = LootScript.new()
	add_child(crate)
	crate.position = Vector3(pos.x, Terrain.height(pos.x, pos.z) - 0.04, pos.z)
	crate.rotation.y = loot_rng.randf() * TAU
	crate.setup(contents, small)
	loot_crates.append(crate)
	return crate


func _create_loot() -> void:
	loot_rng.randomize()
	var placed := 0
	var tries := 0
	while placed < LOOT_CRATE_COUNT and tries < 600:
		tries += 1
		var p := Vector3(loot_rng.randf_range(-78, 78), 0.0, loot_rng.randf_range(-78, 78))
		if not _spawn_point_clear(p):
			continue
		var too_close := false
		for c in loot_crates:
			if c.position.distance_to(p) < 9.0:
				too_close = true
				break
		if too_close:
			continue
		_spawn_crate(p, LootScript.roll_map_crate(loot_rng))
		placed += 1
	# A guaranteed starter crate near the spawn so the loop is obvious.
	_spawn_crate(Vector3(3.5, 0, 8.5), {"weapon": "thompson", "ammo": {"smg": 60}, "medkits": 1, "armor": 0.0})


func _create_zone() -> void:
	zone = ZoneScript.new()
	zone.name = "Zone"
	add_child(zone)
	zone.phase_changed.connect(func(_phase: int, shrinking: bool) -> void:
		if shrinking and state == GameState.PLAYING:
			audio.play("zone_alarm", -4.0))


func _toggle_aim() -> void:
	aiming = not aiming


func _spawn_point_clear(p: Vector3) -> bool:
	var probe := AABB(Vector3(p.x - 0.8, Terrain.height(p.x, p.z) + 0.1, p.z - 0.8), Vector3(1.6, 1.8, 1.6))
	for o in obstacles:
		if o.intersects(probe):
			return false
	return true


func _create_enemies() -> void:
	var uniform := G.pbr("linen", Color(0.74, 0.66, 0.48), 3.0, true, 0.95, 0.0, 0.9, false)
	var helmet := G.pbr("metal_rust", Color(0.56, 0.52, 0.4), 3.0, true, 0.6, 0.3, 0.5, false)
	var metal := G.flat(INK, 0.4, 0.7)
	var ember_mat := StandardMaterial3D.new()
	ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_mat.albedo_color = EMBER
	for i in range(ENEMY_COUNT):
		var angle := i * TAU / float(ENEMY_COUNT)
		var radius := 18.0 + float(i % 5) * 12.0
		var p := Vector3(sin(angle) * radius, 0.05, cos(angle) * radius)
		# Push the spawn outward/inward until it is not inside a building or rock.
		var tries := 0
		while not _spawn_point_clear(p) and tries < 40:
			tries += 1
			var r := radius + (1.5 * tries if tries % 2 == 0 else -1.2 * tries)
			r = clampf(r, 14.0, 76.0)
			p = Vector3(sin(angle + tries * 0.05) * r, 0.05, cos(angle + tries * 0.05) * r)
		p.y = Terrain.height(p.x, p.z) + 0.1
		var enemy: CharacterBody3D = EnemyScript.new()
		enemy.name = "Enemy%d" % i
		add_child(enemy)
		enemy.position = p
		enemy.rig_variant = i % 2
		enemy.setup(self, p, Vector3(1, 0, 0) if i % 2 == 0 else Vector3(0, 0, 1), float(i) * 0.9, uniform, helmet, metal, ember_mat)
		enemy.callsign = CALLSIGNS[i % CALLSIGNS.size()]
		enemy.equip("webley" if i % 4 == 3 else "lee_enfield")
		enemy.died.connect(_on_enemy_died)
		enemies.append(enemy)


func _on_enemy_died(enemy: CharacterBody3D, by_player: bool) -> void:
	enemies.erase(enemy)
	var cause: String = enemy.death_cause
	if by_player:
		score += 1
		experience_points += 25
		reward_coins += 10
		add_kill_feed(PLAYER_CALLSIGN, enemy.callsign, Weapons.get_weapon(current_weapon()).get("name", ""))
	elif cause == "zone" or cause == "":
		zone_kills += 1
		add_kill_feed(ZONE_CALLSIGN, enemy.callsign, "")
	else:
		kills_by_enemies += 1
		var killer = enemy.last_attacker
		var kname: String = killer.callsign if killer != null and is_instance_valid(killer) and "callsign" in killer else "?"
		var kw: String = Weapons.get_weapon(killer.weapon)["name"] if killer != null and is_instance_valid(killer) and "weapon" in killer else ""
		add_kill_feed(kname, enemy.callsign, kw)
	# Fallen soldiers leave a small supply drop.
	_spawn_crate(enemy.global_position, LootScript.roll_enemy_drop(loot_rng), true)
	if enemies.is_empty() and state == GameState.PLAYING:
		_end_mission(true)


## Damage from enemy fire. Armour soaks part of it while it lasts.
func damage_player(amount: float, _from_pos: Vector3, attacker: Node3D = null) -> void:
	if state != GameState.PLAYING:
		return
	if attacker != null:
		last_player_attacker = attacker
	var dmg := float(amount)
	if armor > 0.0:
		var soaked := minf(armor, dmg * ARMOR_ABSORB)
		armor -= soaked
		dmg -= soaked
	_apply_player_damage(dmg, 0.45)
	audio.play("hurt", -2.0, 0.1)


## Zone damage ignores armour.
func damage_player_zone(amount: float) -> void:
	if state != GameState.PLAYING:
		return
	_apply_player_damage(amount, 0.25)


func _apply_player_damage(dmg: float, flash: float) -> void:
	health = maxf(0.0, health - dmg)
	since_damage = 0.0
	damage_flash.color.a = maxf(damage_flash.color.a, flash)
	if health <= 0.0:
		if flash < 0.3 or last_player_attacker == null or not is_instance_valid(last_player_attacker):
			add_kill_feed(ZONE_CALLSIGN, PLAYER_CALLSIGN, "")
		else:
			add_kill_feed(last_player_attacker.callsign, PLAYER_CALLSIGN, Weapons.get_weapon(last_player_attacker.weapon)["name"])
		_end_mission(false)


## Kill feed (top centre): "KILLER » VICTIM (WEAPON)", last 5 entries, each fades after 6 s.
func add_kill_feed(killer: String, victim: String, weapon_name: String) -> void:
	var line := "%s  »  %s" % [killer, victim]
	if weapon_name != "":
		line += "  (%s)" % weapon_name
	kill_feed_entries.append({"text": line, "t": mission_time})
	while kill_feed_entries.size() > 5:
		kill_feed_entries.pop_front()
	_refresh_kill_feed()


func _refresh_kill_feed() -> void:
	if kill_feed == null:
		return
	var keep: Array = []
	for k in kill_feed_entries:
		if mission_time - float(k["t"]) < 6.0:
			keep.append(k)
	kill_feed_entries = keep
	var lines: PackedStringArray = []
	for k in kill_feed_entries:
		lines.append(k["text"])
	kill_feed.text = "\n".join(lines)


## A soldier reached a crate: take a better gun (leaving his old one) and/or a medkit.
func enemy_loot(e: Node3D, crate: Node3D) -> void:
	if not is_instance_valid(crate) or not is_instance_valid(e):
		return
	crate.remove_meta("claimed_by")
	var took := false
	var w: String = crate.contents.get("weapon", "")
	if w != "" and EnemyScript.WEAPONS.has(w) and int(EnemyScript.WEAPONS[w]["tier"]) > e.weapon_tier():
		var old: String = e.weapon
		e.equip(w)
		crate.put_weapon(old)
		took = true
	if int(crate.contents.get("medkits", 0)) > 0 and e.hit_points < 80.0:
		crate.contents["medkits"] = int(crate.contents["medkits"]) - 1
		e.hit_points = minf(e.MAX_HP, e.hit_points + 40.0)
		took = true
	if not took:
		return
	e.loots += 1
	enemy_loots += 1
	audio.play_at("pickup", crate.global_position, -6.0, 0.06)
	crate.refresh_label()
	if crate.is_empty():
		loot_crates.erase(crate)
		crate.queue_free()
		if nearby_crate == crate:
			nearby_crate = null


## Enemy gunfire is loud too: soldiers nearby with nothing to shoot at come for the shooter.
func on_enemy_shot(shooter: Node3D) -> void:
	for e in enemies:
		if e == shooter or not is_instance_valid(e):
			continue
		if e.target == null and e.global_position.distance_to(shooter.global_position) < SHOT_ALERT_RADIUS:
			e.alert(shooter)
	if audio != null and audio.has_method("duck"):
		var d := shooter.global_position.distance_to(player.global_position)
		if d < 40.0:
			audio.duck(clampf(1.0 - d / 40.0, 0.2, 1.0) * 0.6)


func alive_count() -> int:
	return enemies.size() + (1 if state != GameState.DEAD else 0)


func _label(parent: Control, text: String, font_size: int, color: Color = BONE, centered := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


func _style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(3)
	s.set_corner_radius_all(10)
	s.content_margin_left = 12
	s.content_margin_right = 12
	return s


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = ARABIC_FONT
	t.default_font_size = 22
	t.set_color("font_color", "Label", BONE)
	t.set_color("font_shadow_color", "Label", Color(INK, 0.85))
	t.set_constant("shadow_offset_x", "Label", 2)
	t.set_constant("shadow_offset_y", "Label", 2)
	t.set_stylebox("normal", "Button", _style(Color(INK, 0.55), BRASS))
	t.set_stylebox("hover", "Button", _style(Color(INK, 0.75), SAND))
	t.set_stylebox("pressed", "Button", _style(Color(EMBER, 0.75), BONE))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", BONE)
	t.set_color("font_hover_color", "Button", SAND)
	t.set_color("font_pressed_color", "Button", BONE)
	return t


func _create_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.theme = _make_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	damage_flash = ColorRect.new()
	damage_flash.color = Color(EMBER, 0.0)
	damage_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(damage_flash)
	hud = Label.new()
	hud.text = "HARAQ  حَرَق  |  WAR FRONT: EGYPT 1942"
	hud.position = Vector2(20, 10)
	hud.add_theme_font_size_override("font_size", 24)
	hud.add_theme_color_override("font_color", BRASS)
	root.add_child(hud)
	health_label = Label.new()
	health_label.position = Vector2(20, 48)
	health_label.add_theme_font_size_override("font_size", 26)
	root.add_child(health_label)
	weapon_label = Label.new()
	weapon_label.position = Vector2(20, 88)
	weapon_label.add_theme_font_size_override("font_size", 20)
	weapon_label.add_theme_color_override("font_color", SAND)
	root.add_child(weapon_label)
	status = Label.new()
	status.position = Vector2(20, 166)
	status.add_theme_font_size_override("font_size", 17)
	status.add_theme_color_override("font_color", Color(BONE, 0.85))
	root.add_child(status)
	# Top-right: alive counter, minimap and zone status.
	alive_label = Label.new()
	alive_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	alive_label.position = Vector2(-215, 8)
	alive_label.size = Vector2(200, 34)
	alive_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	alive_label.add_theme_font_size_override("font_size", 22)
	alive_label.add_theme_color_override("font_color", BRASS)
	root.add_child(alive_label)
	minimap = MinimapScript.new()
	minimap.game = self
	minimap.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	minimap.position = Vector2(-195, 46)
	minimap.size = Vector2(180, 180)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(minimap)
	kill_feed = Label.new()
	kill_feed.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	kill_feed.position = Vector2(-260, 46)
	kill_feed.size = Vector2(520, 140)
	kill_feed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kill_feed.add_theme_font_size_override("font_size", 18)
	kill_feed.add_theme_color_override("font_color", BONE)
	kill_feed.add_theme_color_override("font_outline_color", INK)
	kill_feed.add_theme_constant_override("outline_size", 6)
	kill_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(kill_feed)
	zone_label = Label.new()
	zone_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	zone_label.position = Vector2(-560, 230)
	zone_label.size = Vector2(545, 70)
	zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	zone_label.add_theme_font_size_override("font_size", 19)
	root.add_child(zone_label)
	pickup_label = Label.new()
	pickup_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	pickup_label.position = Vector2(-400, -300)
	pickup_label.size = Vector2(800, 80)
	pickup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pickup_label.add_theme_font_size_override("font_size", 21)
	pickup_label.add_theme_color_override("font_color", BONE)
	pickup_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pickup_label)
	var cross := Label.new()
	cross.text = "+"
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	cross.position = Vector2(-8, -24)
	cross.add_theme_font_size_override("font_size", 38)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cross)
	hit_marker = Label.new()
	hit_marker.text = "X"
	hit_marker.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hit_marker.position = Vector2(-9, -24)
	hit_marker.add_theme_font_size_override("font_size", 34)
	hit_marker.add_theme_color_override("font_color", EMBER)
	hit_marker.visible = false
	hit_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hit_marker)
	_create_touch_controls(root)
	get_viewport().size_changed.connect(func() -> void: layout_touch_controls(get_viewport().get_visible_rect().size))
	layout_touch_controls(get_viewport().get_visible_rect().size)


## ---------------------------------------------------------------- touch HUD
## Touch buttons are hit-tested by hand per finger (Godot's Control buttons only see the first
## finger through mouse emulation), so FIRE works while the other thumb holds the stick, and a
## touch that starts on any button never turns into a camera drag.
func _create_touch_controls(root: Control) -> void:
	joy_base = Panel.new()
	var jb := StyleBoxFlat.new()
	jb.bg_color = Color(SAND, 0.14)
	jb.border_color = Color(BONE, 0.35)
	jb.set_border_width_all(3)
	jb.set_corner_radius_all(100)
	jb.anti_aliasing = true
	joy_base.add_theme_stylebox_override("panel", jb)
	joy_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(joy_base)
	joy_knob = Panel.new()
	var jk := StyleBoxFlat.new()
	jk.bg_color = Color(BONE, 0.5)
	jk.set_corner_radius_all(36)
	joy_knob.add_theme_stylebox_override("panel", jk)
	joy_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joy_base.add_child(joy_knob)
	fire_button = _button(root, "FIRE")
	var fs := _style(Color(EMBER, 0.62), BONE)
	fs.set_corner_radius_all(76)
	fire_button.add_theme_stylebox_override("normal", fs)
	fire_button.add_theme_font_size_override("font_size", 28)
	aim_button = _button(root, "AIM")
	reload_button = _button(root, "RELOAD")
	jump_button = _button(root, "JUMP")
	swap_button = _button(root, "SWAP")
	heal_button = _button(root, "HEAL")
	interact_button = _button(root, "التقط  PICK UP")
	interact_button.add_theme_stylebox_override("normal", _style(Color(SEA, 0.8), BRASS))
	sprint_button = _button(root, "RUN")
	touch_actions = {
		fire_button: [func() -> void: fire_held = true, func() -> void: fire_held = false],
		aim_button: [_toggle_aim, Callable()],
		reload_button: [_reload, Callable()],
		jump_button: [_jump, Callable()],
		swap_button: [swap_weapon, Callable()],
		heal_button: [use_medkit, Callable()],
		interact_button: [interact, Callable()],
		sprint_button: [func() -> void: sprint_held = not sprint_held, Callable()],
	}
	for c in [joy_base, fire_button, jump_button, sprint_button, reload_button, aim_button, swap_button, interact_button, heal_button]:
		c.visible = is_mobile
	interact_button.visible = false


func _button(parent: Control, label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_theme_font_size_override("font_size", 23)
	parent.add_child(b)
	return b


## Thumb-reachable layout for any screen: buttons fan out around FIRE in the bottom-right
## corner, the stick + RUN sit bottom-left, and PICK UP pops up between them only when there
## is something to pick up. Sizes follow the viewport height and keep clear of notches.
func layout_touch_controls(vp: Vector2) -> void:
	if fire_button == null:
		return
	var s := clampf(vp.y / 720.0, 0.85, 1.5)
	var safe := _safe_margins(vp)
	var gap := 14.0 * s
	var r := vp.x - safe.y - 28.0 * s
	var btm := vp.y - safe.z - 24.0 * s
	var bw := 128.0 * s
	var bh := 76.0 * s
	var fire := 156.0 * s
	_place(fire_button, Vector2(r - fire, btm - fire), Vector2(fire, fire))
	(fire_button.get_theme_stylebox("normal") as StyleBoxFlat).set_corner_radius_all(int(fire * 0.5) - 2)
	_place(aim_button, Vector2(r - fire + (fire - bw) * 0.5, btm - fire - gap - bh), Vector2(bw, bh))
	_place(reload_button, Vector2(r - fire - gap - bw, btm - bh), Vector2(bw, bh))
	_place(jump_button, Vector2(r - fire - gap - bw, btm - bh * 2.0 - gap), Vector2(bw, bh))
	_place(swap_button, Vector2(r - fire - gap * 2.0 - bw * 2.0, btm - bh), Vector2(bw, bh))
	_place(heal_button, Vector2(r - fire - gap * 2.0 - bw * 2.0, btm - bh * 2.0 - gap), Vector2(bw, bh))
	_place(interact_button, Vector2(r - fire - gap * 2.0 - bw * 2.0, btm - bh * 3.0 - gap * 2.0 - 8.0 * s), Vector2(bw * 2.0 + gap, bh))
	var joy := 210.0 * s
	joy_home = Vector2(safe.x + 48.0 * s, btm - joy)
	joy_base.size = Vector2(joy, joy)
	(joy_base.get_theme_stylebox("panel") as StyleBoxFlat).set_corner_radius_all(int(joy * 0.5) - 2)
	(joy_knob.get_theme_stylebox("panel") as StyleBoxFlat).set_corner_radius_all(int(joy * 0.18) - 1)
	joy_base.position = joy_home
	joy_knob.size = Vector2(joy, joy) * 0.36
	joy_knob.position = (joy_base.size - joy_knob.size) * 0.5
	_place(sprint_button, Vector2(joy_home.x + (joy - bw) * 0.5, joy_home.y - gap - bh), Vector2(bw, bh))
	joy_zone = Rect2(0, vp.y * 0.32, minf(vp.x * 0.4, joy_home.x + joy + 150.0 * s), vp.y * 0.68)
	touch_layout_size = vp


func _place(c: Control, pos: Vector2, sz: Vector2) -> void:
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.position = pos
	c.size = sz


## Safe-area margins (left, right, bottom) in viewport units, for notches / rounded corners.
func _safe_margins(vp: Vector2) -> Vector3:
	if DisplayServer.get_name() == "headless" or not is_mobile:
		return Vector3.ZERO
	var win := Vector2(DisplayServer.window_get_size())
	var sa := DisplayServer.get_display_safe_area()
	if win.x <= 0.0 or sa.size.x <= 0:
		return Vector3.ZERO
	var k := vp.x / win.x
	return Vector3(maxf(0.0, sa.position.x * k), maxf(0.0, (win.x - sa.end.x) * k), maxf(0.0, (win.y - sa.end.y) * k))


func _touch_button_at(pos: Vector2) -> Button:
	for b in touch_actions.keys():
		if (b as Control).visible and (b as Control).get_global_rect().grow(4.0).has_point(pos):
			return b
	return null


## What a finger landing at `pos` controls: "button", "joystick" or "look".
func classify_touch(pos: Vector2) -> String:
	if _touch_button_at(pos) != null:
		return "button"
	if joy_zone.has_point(pos):
		return "joystick"
	return "look"


func _touch_press(index: int, pos: Vector2) -> void:
	var b := _touch_button_at(pos)
	if b != null:
		touch_owner[index] = b
		b.modulate = Color(1.25, 1.15, 1.0)
		var down: Callable = touch_actions[b][0]
		if down.is_valid():
			down.call()
		# Drag from FIRE also aims (fire + look with one thumb).
		if b == fire_button and look_id == -1:
			look_id = index
			touch_last = pos
		return
	if joy_zone.has_point(pos) and joystick_id == -1:
		joystick_id = index
		# Floating stick: it re-centres under the thumb.
		var half := joy_base.size * 0.5
		joy_base.position = (pos - half).clamp(Vector2.ZERO, get_viewport().get_visible_rect().size - joy_base.size)
		_update_joystick(pos)
	elif look_id == -1:
		look_id = index
		touch_last = pos


func _touch_release(index: int) -> void:
	if touch_owner.has(index):
		var b: Button = touch_owner[index]
		touch_owner.erase(index)
		b.modulate = Color.WHITE
		var up: Callable = touch_actions[b][1]
		if up.is_valid():
			up.call()
	if index == joystick_id:
		joystick_id = -1
		joystick_vector = Vector2.ZERO
		joy_base.position = joy_home
		joy_knob.position = (joy_base.size - joy_knob.size) * 0.5
	if index == look_id:
		look_id = -1


func _input(event: InputEvent) -> void:
	if not is_mobile:
		return
	if state != GameState.PLAYING:
		for i in touch_owner.keys():
			_touch_release(i)
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_press(event.index, event.position)
		else:
			_touch_release(event.index)
	elif event is InputEventScreenDrag:
		if event.index == joystick_id:
			_update_joystick(event.position)
		elif event.index == look_id:
			_look(event.position - touch_last, TOUCH_SENS)
			touch_last = event.position


func _unhandled_input(event: InputEvent) -> void:
	if state != GameState.PLAYING:
		if state != GameState.INTRO and event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_restart()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.relative * MOUSE_SENS)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				_reload()
			KEY_E, KEY_F:
				interact()
			KEY_1:
				switch_to_slot(0)
			KEY_2:
				switch_to_slot(1)
			KEY_Q:
				swap_weapon()
			KEY_H:
				use_medkit()
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		swap_weapon()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_toggle_aim()
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not is_mobile:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _update_joystick(screen_pos: Vector2) -> void:
	var center := joy_base.global_position + joy_base.size / 2.0
	var reach := joy_base.size.x * 0.42
	joystick_vector = ((screen_pos - center) / reach).limit_length(1.0)
	joy_knob.position = (joy_base.size - joy_knob.size) * 0.5 + joystick_vector * reach * 0.75


func _look(delta: Vector2, sensitivity: float = 1.0) -> void:
	player.rotate_y(-delta.x * sensitivity)
	head.rotation.x = clampf(head.rotation.x - delta.y * sensitivity, -1.35, 1.35)


func _jump() -> void:
	if state == GameState.PLAYING and player.is_on_floor():
		player.velocity.y = JUMP_SPEED


func _physics_process(delta: float) -> void:
	damage_flash.color.a = move_toward(damage_flash.color.a, 0.0, delta * 1.2)
	if state != GameState.PLAYING:
		return
	mission_time += delta
	var axis := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if joystick_vector.length() > 0.1:
		axis = joystick_vector
	var dir := player.global_transform.basis * Vector3(axis.x, 0, axis.y)
	# Pushing the stick all the way forward also sprints (thumb-friendly).
	var stick_sprint := joystick_id != -1 and joystick_vector.y < -0.92
	if sprint_held and axis.length() < 0.1:
		idle_time += delta
		if idle_time > 0.6:
			sprint_held = false
	else:
		idle_time = 0.0
	var speed := RUN_SPEED if sprint_held or stick_sprint or Input.is_action_pressed("sprint") else WALK_SPEED
	player.velocity.x = dir.x * speed
	player.velocity.z = dir.z * speed
	if not player.is_on_floor():
		player.velocity.y -= GRAVITY * delta
	if Input.is_action_just_pressed("jump"):
		_jump()
	var before_step := player.global_position
	player.move_and_slide()
	if player.is_on_floor():
		step_distance += Vector2(player.global_position.x - before_step.x, player.global_position.z - before_step.z).length()
		if step_distance > (2.6 if speed > WALK_SPEED else 2.0):
			step_distance = 0.0
			audio.play("step", -8.0 if speed <= WALK_SPEED else -5.0, 0.12)
	audio.update_mix(delta, player.global_position.z - Terrain.shore_z(player.global_position.x), zone.distance_outside(player.global_position), player.global_position)
	if player.global_position.y < -20.0:
		_end_mission(false)
		return
	since_damage += delta
	if since_damage > REGEN_DELAY and health < MAX_HEALTH:
		health = minf(MAX_HEALTH, health + REGEN_RATE * delta)
	_update_zone(delta)
	if nav:
		nav.tick(mission_time)
	if state != GameState.PLAYING:
		return
	_update_loot_proximity()
	pickup_toast_timer = maxf(0.0, pickup_toast_timer - delta)
	switch_timer = maxf(0.0, switch_timer - delta)
	cooldown = maxf(0.0, cooldown - delta)
	if reload_timer > 0.0:
		reload_timer -= delta
		if reload_timer <= 0.0:
			_finish_reload()
	hit_marker_timer = maxf(0.0, hit_marker_timer - delta)
	hit_marker.visible = hit_marker_timer > 0.0
	shot_flash.light_energy = move_toward(shot_flash.light_energy, 0.0, delta * 45.0)
	shot_flash.visible = shot_flash.light_energy > 0.01
	flash_timer = maxf(0.0, flash_timer - delta)
	player_flash.visible = flash_timer > 0.0
	camera.fov = move_toward(camera.fov, ADS_FOV if aiming else HIP_FOV, delta * 180.0)
	# Mouse "fire" is also emulated from touches on phones, so only the FIRE button shoots there.
	var trigger := fire_held or (not is_mobile and Input.is_action_pressed("fire"))
	if trigger:
		_shoot()
	else:
		trigger_released = true
	recoil = move_toward(recoil, 0.0, delta * 3.0)
	var gun_target := (GUN_ADS_POS if aiming else GUN_HIP_POS) + Vector3(0, recoil, -recoil * 1.2)
	gun.position = gun.position.lerp(gun_target, clampf(delta * 12.0, 0.0, 1.0))
	_update_hud()


func _update_zone(delta: float) -> void:
	zone.tick(delta)
	var dps: float = zone.damage_per_second()
	for e in enemies.duplicate():
		if is_instance_valid(e) and not zone.is_inside(e.global_position):
			e.take_zone_damage(dps * delta)
	if not zone.is_inside(player.global_position):
		damage_player_zone(dps * delta)


func _update_loot_proximity() -> void:
	nearby_crate = null
	var best := LootScript.PICKUP_RADIUS
	var pp := player.global_position
	for c in loot_crates.duplicate():
		if not is_instance_valid(c):
			continue
		var d := Vector2(c.global_position.x - pp.x, c.global_position.z - pp.z).length()
		if d < best:
			best = d
			nearby_crate = c
	if nearby_crate != null:
		_collect_from(nearby_crate, false)


func _update_hud() -> void:
	var hp := int(ceil(health))
	health_label.text = "HP %d / %d   ARMOR %d   MEDKIT %d" % [hp, MAX_HEALTH, int(armor), medkits]
	health_label.add_theme_color_override("font_color", EMBER if hp <= 35 else BONE)
	var lines: PackedStringArray = []
	for i in range(slots.size()):
		var id := slots[i]
		var mark := ">" if i == current_slot else " "
		if id == "":
			lines.append("%s[%d] —" % [mark, i + 1])
			continue
		var w: Dictionary = Weapons.DATA[id]
		lines.append("%s[%d] %s   %d / %d %s" % [mark, i + 1, w["name"], int(mag_ammo.get(id, 0)), int(reserve.get(w["ammo"], 0)), Weapons.AMMO_NAMES[w["ammo"]]])
	if reload_timer > 0.0:
		lines[current_slot] += "   RELOADING..."
	weapon_label.text = "\n".join(lines)
	status.text = "KILLS %d | XP %d | COINS %d | FPS %d" % [score, experience_points, reward_coins, Engine.get_frames_per_second()]
	alive_label.text = "ALIVE %d  |  أحياء" % alive_count()
	_refresh_kill_feed()
	var zone_text: String = zone.status_text()
	var outside: float = zone.distance_outside(player.global_position)
	if outside > 0.0:
		zone_text += "\nإنت برا المنطقة! ارجع للدايرة  %dم  (-%d HP/s)" % [ceili(outside), ceili(zone.damage_per_second())]
		zone_label.add_theme_color_override("font_color", EMBER)
	else:
		zone_label.add_theme_color_override("font_color", EMBER if zone.shrinking else BONE)
	zone_label.text = zone_text
	var prompt := ""
	if nearby_crate != null and is_instance_valid(nearby_crate) and nearby_crate.contents.get("weapon", "") != "":
		var wid: String = nearby_crate.contents["weapon"]
		prompt = "%s  —  اضغط %s للتبديل" % [Weapons.DATA[wid]["name"], "التقط" if is_mobile else "E"]
	if pickup_toast_timer > 0.0:
		prompt = pickup_toast + ("\n" + prompt if prompt != "" else "")
	pickup_label.text = prompt
	if is_mobile:
		var can_pick: bool = nearby_crate != null and is_instance_valid(nearby_crate) and nearby_crate.contents.get("weapon", "") != ""
		interact_button.visible = can_pick
		heal_button.modulate.a = 1.0 if medkits > 0 and health < MAX_HEALTH else 0.45
		if _style_on == null:
			_style_on = _style(Color(EMBER, 0.8), BRASS)
			_style_off = _style(Color(INK, 0.55), BRASS)
		sprint_button.add_theme_stylebox_override("normal", _style_on if sprint_held else _style_off)
		aim_button.add_theme_stylebox_override("normal", _style_on if aiming else _style_off)


func _shoot() -> void:
	var w := current_stats()
	if w.is_empty() or cooldown > 0 or reload_timer > 0 or switch_timer > 0:
		return
	if not bool(w["auto"]) and not trigger_released:
		return
	trigger_released = false
	var id := current_weapon()
	if int(mag_ammo.get(id, 0)) <= 0:
		if int(reserve.get(w["ammo"], 0)) <= 0:
			audio.play("dry", -4.0)
			cooldown = 0.3
		_reload()
		return
	mag_ammo[id] = int(mag_ammo[id]) - 1
	audio.play(AudioScript.SHOT.get(id, "shot_webley"), -1.0, 0.04)
	shot_flash.light_energy = 3.5
	flash_timer = 0.05
	player_flash.visible = true
	player_flash.rotation.z = randf() * TAU
	player_flash.scale = Vector3.ONE * randf_range(0.8, 1.25)
	cooldown = float(w["interval"])
	recoil = -float(w["recoil"])
	audio.duck(0.45)
	# Gunfire is loud: nearby patrols come looking.
	for e in enemies:
		if is_instance_valid(e) and e.global_position.distance_to(player.global_position) < SHOT_ALERT_RADIUS:
			e.alert()
	var origin := camera.global_position
	var spread: float = float(w["spread"]) * (0.25 if aiming else 1.0) * (1.6 if is_player_moving_fast() else 1.0)
	var cam_basis := camera.global_transform.basis
	var dir := (-cam_basis.z + cam_basis.x * randf_range(-spread, spread) + cam_basis.y * randf_range(-spread, spread)).normalized()
	var end := origin + dir * 180.0
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = [player.get_rid()]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return
	var hit: Object = result.collider
	var detail: float = G.preset(quality)["detail"]
	var kind := "sand"
	if hit != null and hit.has_method("take_hit"):
		kind = "soldier"
	elif hit is Node and (hit as Node).has_meta("metal"):
		kind = "metal"
	Fx.impact(self, result.position + result.normal * 0.05, result.normal, kind, detail)
	audio.play_at({"soldier": "hit_flesh", "metal": "hit_metal"}.get(kind, "hit_sand"), result.position, -2.0 if kind == "soldier" else -6.0, 0.1)
	if hit != null and hit.has_method("take_hit"):
		hit_marker_timer = 0.14
		# Headshots (top of the capsule) drop a soldier instantly.
		var headshot: bool = result.position.y > (hit as Node3D).global_position.y + 1.45
		hit.take_hit(float(w["damage"]) * (float(w["head_mult"]) if headshot else 1.0))


func _restart() -> void:
	get_tree().reload_current_scene()


func _end_mission(victory: bool) -> void:
	placement = 1 if victory else enemies.size() + 1
	audio.stop_ambience()
	audio.play_music("music_menu")
	state = GameState.WON if victory else GameState.DEAD
	fire_held = false
	sprint_held = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	end_overlay = ColorRect.new()
	(end_overlay as ColorRect).color = Color(INK, 0.9)
	end_overlay.theme = _make_theme()
	end_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(end_overlay)
	var box_layout := VBoxContainer.new()
	box_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box_layout.alignment = BoxContainer.ALIGNMENT_CENTER
	box_layout.add_theme_constant_override("separation", 22)
	end_overlay.add_child(box_layout)
	_label(box_layout, "#1  النصر!  VICTORY" if victory else "#%d  |  سقطت في المعركة" % placement, 64, BRASS if victory else EMBER, true)
	_label(box_layout, "آخر واحد واقف — العلمين 1942" if victory else "المركز #%d من %d — حاول مرة أخرى" % [placement, ENEMY_COUNT + 1], 26, BONE, true)
	_label(box_layout, ("Last one standing — all %d soldiers are down (%d lost to the zone)" % [ENEMY_COUNT, zone_kills]) if victory else ("Placed #%d of %d — %d enemies remain" % [placement, ENEMY_COUNT + 1, enemies.size()]), 24, BONE, true)
	_label(box_layout, "KILLS %d   |   XP %d   |   COINS %d   |   TIME %d:%02d" % [score, experience_points, reward_coins, floori(mission_time / 60.0), int(mission_time) % 60], 22, SAND, true)
	var restart := Button.new()
	restart.text = "إعادة المهمة  |  RESTART"
	restart.custom_minimum_size = Vector2(420, 82)
	restart.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart.add_theme_font_size_override("font_size", 28)
	restart.pressed.connect(func() -> void:
		audio.play("ui_click")
		_restart())
	box_layout.add_child(restart)


# Egyptian civilian atmosphere: fictional 1942-inspired market set dressing.
func _create_egyptian_life() -> void:
	var mud := G.pbr("mudbrick", Color(1.0, 0.97, 0.92), 0.45)
	var mud_dark := G.pbr("mudbrick", Color(0.88, 0.8, 0.7), 0.45)
	var wood := G.pbr("planks", Color(0.62, 0.48, 0.34), 0.9)
	var dark := G.flat(INK.lerp(KHAKI, 0.15), 1.0)
	var road := G.pbr("sand_coarse", Color(1.0, 0.9, 0.74), 0.3)
	var awning_a := G.pbr("burlap", EMBER.lerp(BONE, 0.15), 1.2, true, 1.0)
	var awning_b := G.pbr("burlap", SEA.lerp(BONE, 0.2), 1.2, true, 1.0)
	# Market lane on the edge of the arena (packed earth).
	box(self, Vector3(-33, 0.0, -17), Vector3(9, 0.3, 46), road, false)
	for i in range(5):
		var z := -35.0 + float(i) * 9.0
		var hh := 4.0 + float(i % 2) * 0.6
		box(self, Vector3(-40, hh / 2.0, z), Vector3(5, hh, 6), mud if i % 2 == 0 else mud_dark)
		# Roof parapet, door and small windows.
		box(self, Vector3(-40, hh + 0.2, z), Vector3(5.2, 0.4, 6.2), mud_dark, false)
		box(self, Vector3(-37.47, 1.1, z + 1.6), Vector3(0.1, 2.2, 1.1), dark, false)
		for wz in [-1.6, 0.0]:
			box(self, Vector3(-37.47, 2.6, z + wz), Vector3(0.1, 0.7, 0.6), dark, false)
		box(self, Vector3(-37.3, 1.2, z), Vector3(0.3, 2.4, 1.5), wood, false)
		box(self, Vector3(-36.6, 2.6, z), Vector3(2.2, 0.08, 3.2), awning_a if i % 2 == 0 else awning_b, false)
		box(self, Vector3(-36.8, 0.6, z - 1.2), Vector3(1.4, 1.2, 0.6), wood)
		var sign := Label3D.new()
		sign.text = ["قهوة المحروسة", "بقالة عم سيد", "ورشة أولاد النيل", "عيش بلدي", "سوق البلد"][i]
		sign.font = ARABIC_FONT
		sign.font_size = 80
		sign.pixel_size = 0.003
		sign.position = Vector3(-37.4, 3.45, z - 0.6)
		sign.rotation_degrees.y = 90
		sign.modulate = INK
		sign.outline_modulate = Color(BONE, 0.6)
		sign.outline_size = 8
		sign.no_depth_test = false
		add_child(sign)
	for i in range(7):
		var z := -38.0 + float(i) * 11.0
		Props.add_palm(self, Vector3(-23, 0, z), 4.8 + float(i % 3) * 0.7, i)
		# Keep the old trunk collision so cover/AI behaviour is unchanged.
		var trunk := StaticBody3D.new()
		add_child(trunk)
		trunk.position = Vector3(-23, Terrain.height(-23, z) + 2.2, z)
		var tc := CollisionShape3D.new()
		var tb := BoxShape3D.new()
		tb.size = Vector3(0.5, 4.4, 0.5)
		tc.shape = tb
		trunk.add_child(tc)
		obstacles.append(AABB(Vector3(-23.25, Terrain.height(-23, z), z - 0.25), Vector3(0.5, 4.4, 0.5)))
	# Egyptian donkey cart (static prop, no animals).
	box(self, Vector3(-28, 0.9, -6), Vector3(3.1, 0.3, 1.6), wood, false)
	box(self, Vector3(-28, 1.2, -6.75), Vector3(3.1, 0.35, 0.08), wood, false)
	box(self, Vector3(-28, 1.2, -5.25), Vector3(3.1, 0.35, 0.08), wood, false)
	box(self, Vector3(-30.2, 0.8, -6), Vector3(1.6, 0.08, 0.08), wood, false)
	for side in [-1.0, 1.0]:
		var wheel := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.65
		cyl.bottom_radius = 0.65
		cyl.height = 0.12
		cyl.radial_segments = 16
		wheel.mesh = cyl
		wheel.material_override = wood
		wheel.rotation_degrees.x = 90
		wheel.position = Vector3(-28, Terrain.height(-28, -6) + 0.62, -6 + side * 0.85)
		add_child(wheel)


## Apply a graphics preset (0 Low / 1 Medium / 2 High) to the environment, sun, viewport and props.
func apply_quality(q: int) -> void:
	quality = clampi(q, 0, 2)
	var pr := G.preset(quality)
	var e := world_env.environment
	e.glow_enabled = pr["glow"]
	e.fog_density = pr["fog_density"]
	sun.shadow_enabled = pr["shadows"]
	sun.directional_shadow_mode = [DirectionalLight3D.SHADOW_ORTHOGONAL, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS][int(pr["shadow_mode"])]
	sun.directional_shadow_max_distance = maxf(10.0, pr["shadow_distance"])
	RenderingServer.directional_shadow_atlas_set_size(int(pr["shadow_atlas"]), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW if quality < 2 else RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	var vp := get_viewport()
	vp.msaa_3d = pr["msaa"]
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = pr["scale_mobile"] if is_mobile else pr["scale"]
	vp.mesh_lod_threshold = 1.0 / float(pr["lod_bias"])
	if camera:
		camera.far = pr["far"]
	if bushes:
		bushes.multimesh.visible_instance_count = int(bush_total * float(pr["detail"]))
	for sp in smoke_plumes:
		if is_instance_valid(sp):
			sp.visible = pr["smoke"]
			(sp as CPUParticles3D).emitting = pr["smoke"]
	for i in range(quality_buttons.size()):
		quality_buttons[i].add_theme_stylebox_override("normal", _style(Color(EMBER, 0.85) if i == quality else Color(INK, 0.55), BRASS))


func set_quality(q: int) -> void:
	apply_quality(q)
	G.save_quality(quality)


func _create_hero_intro() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	intro_overlay = ColorRect.new()
	(intro_overlay as ColorRect).color = Color(INK, 0.97)
	intro_overlay.theme = _make_theme()
	intro_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(intro_overlay)
	var layout := HBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 38)
	layout.offset_left = 65
	layout.offset_right = -65
	layout.offset_top = 22
	layout.offset_bottom = -22
	intro_overlay.add_child(layout)
	var portrait := TextureRect.new()
	portrait.texture = load("res://assets/khaled_portrait.jpg")
	portrait.custom_minimum_size = Vector2(330, 440)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	layout.add_child(portrait)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 5)
	layout.add_child(content)
	var brand := Label.new()
	brand.text = "حَرَق  HARAQ"
	brand.add_theme_font_size_override("font_size", 60)
	brand.add_theme_color_override("font_color", EMBER)
	content.add_child(brand)
	var title := Label.new()
	title.text = "WAR FRONT: EGYPT 1942"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", BRASS)
	content.add_child(title)
	var hero := Label.new()
	hero.text = "خالد كارم عبداللا\nKHALED KAREM ABDALLA"
	hero.add_theme_font_size_override("font_size", 24)
	hero.add_theme_color_override("font_color", SAND)
	content.add_child(hero)
	_label(content, "قائد المهمة | العلمين - مصر 1942", 21)
	_label(content, "باتل رويال: 20 جندي، صناديق إمداد، والدايرة بتضيق — آخر واحد واقف يكسب", 21)
	_label(content, "Battle royale vs 20 soldiers — loot crates, shrinking zone, last one standing wins", 20, SAND)
	var controls := Label.new()
	controls.text = "Touch: floating stick (push fully up = run) · drag anywhere else to look · drag from FIRE to aim while shooting" if is_mobile else "WASD · Mouse · RMB aim · R reload · E pick up · 1/2/wheel swap · H heal"
	controls.add_theme_font_size_override("font_size", 17)
	controls.add_theme_color_override("font_color", Color(BONE, 0.7))
	content.add_child(controls)
	var qrow := HBoxContainer.new()
	qrow.add_theme_constant_override("separation", 10)
	content.add_child(qrow)
	var ql := Label.new()
	ql.text = "الجرافيك  GRAPHICS"
	ql.add_theme_font_size_override("font_size", 20)
	ql.add_theme_color_override("font_color", BRASS)
	qrow.add_child(ql)
	quality_buttons.clear()
	for i in range(3):
		var qb := Button.new()
		qb.text = "%s  %s" % [G.NAMES_AR[i], G.NAMES[i]]
		qb.custom_minimum_size = Vector2(170, 48)
		qb.add_theme_font_size_override("font_size", 19)
		qb.pressed.connect(set_quality.bind(i))
		qb.pressed.connect(audio.play.bind("ui_click", 0.0, 0.0))
		qrow.add_child(qb)
		quality_buttons.append(qb)
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 12)
	content.add_child(arow)
	var al := Label.new()
	al.text = "الصوت  SOUND"
	al.add_theme_font_size_override("font_size", 20)
	al.add_theme_color_override("font_color", BRASS)
	arow.add_child(al)
	volume_slider = _make_slider(audio.volume, 260)
	volume_slider.value_changed.connect(func(v: float) -> void:
		audio.set_volume(v / 100.0)
		_refresh_mute_button())
	volume_slider.drag_ended.connect(func(_c: bool) -> void: audio.play("ui_click"))
	arow.add_child(volume_slider)
	mute_button = Button.new()
	mute_button.custom_minimum_size = Vector2(170, 48)
	mute_button.add_theme_font_size_override("font_size", 19)
	mute_button.focus_mode = Control.FOCUS_NONE
	mute_button.pressed.connect(func() -> void:
		audio.set_muted(not audio.muted)
		audio.play("ui_click")
		_refresh_mute_button())
	arow.add_child(mute_button)
	_refresh_mute_button()
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 12)
	content.add_child(mrow)
	var ml := Label.new()
	ml.text = "موسيقى  MUSIC"
	ml.add_theme_font_size_override("font_size", 18)
	ml.add_theme_color_override("font_color", BRASS)
	mrow.add_child(ml)
	music_slider = _make_slider(audio.music_volume, 170)
	music_slider.value_changed.connect(func(v: float) -> void: audio.set_music_volume(v / 100.0))
	mrow.add_child(music_slider)
	var sl := Label.new()
	sl.text = "مؤثرات  SFX"
	sl.add_theme_font_size_override("font_size", 18)
	sl.add_theme_color_override("font_color", BRASS)
	mrow.add_child(sl)
	sfx_slider = _make_slider(audio.sfx_volume, 170)
	sfx_slider.value_changed.connect(func(v: float) -> void: audio.set_sfx_volume(v / 100.0))
	sfx_slider.drag_ended.connect(func(_c: bool) -> void: audio.play("shot_webley", -6.0))
	mrow.add_child(sfx_slider)
	audio.play_music("music_menu")
	var start := Button.new()
	start.text = "ابدأ المهمة  |  START MISSION"
	start.custom_minimum_size = Vector2(420, 70)
	start.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	start.add_theme_font_size_override("font_size", 28)
	start.add_theme_stylebox_override("normal", _style(Color(EMBER, 0.85), BRASS))
	content.add_child(start)
	start.pressed.connect(_start_hero_mission)


func _make_slider(value: float, width: float) -> HSlider:
	var sl := HSlider.new()
	sl.min_value = 0
	sl.max_value = 100
	sl.step = 5
	sl.value = value * 100.0
	sl.custom_minimum_size = Vector2(width, 40)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.focus_mode = Control.FOCUS_NONE
	var track := _style(Color(SAND, 0.25), BRASS)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	sl.add_theme_stylebox_override("slider", track)
	var fill := _style(Color(EMBER, 0.85), BRASS)
	fill.content_margin_top = 6
	fill.content_margin_bottom = 6
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill)
	return sl


func _refresh_mute_button() -> void:
	if mute_button == null:
		return
	var off: bool = audio.muted or audio.volume <= 0.001
	mute_button.text = "صامت  MUTED" if off else "كتم  MUTE"
	mute_button.add_theme_stylebox_override("normal", _style(Color(EMBER, 0.85) if off else Color(INK, 0.55), BRASS))


func _start_hero_mission() -> void:
	state = GameState.PLAYING
	audio.play("ui_click")
	audio.start_ambience()
	audio.play_music("music_battle")
	intro_overlay.visible = false
	if not is_mobile:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
