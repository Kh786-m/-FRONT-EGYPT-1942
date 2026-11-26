extends Node3D
## HARAQ (حَرَق) — WAR FRONT: EGYPT 1942
## Fully procedural offline FPS vertical slice (Godot 4.3, GL Compatibility).

const EnemyScript := preload("res://scripts/enemy.gd")
const ZoneScript := preload("res://scripts/zone.gd")
const LootScript := preload("res://scripts/loot.gd")
const MinimapScript := preload("res://scripts/minimap.gd")
const Weapons := preload("res://scripts/weapons.gd")
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
var pickup_toast := ""
var pickup_toast_timer := 0.0
var reload_timer := 0.0
var aiming := false
var hit_marker_timer := 0.0
var mission_time := 0.0
var is_mobile := false


func _ready() -> void:
	randomize()
	is_mobile = OS.has_feature("mobile")
	_create_world()
	_create_egyptian_life()
	_create_player()
	_create_zone()
	_create_loot()
	_create_enemies()
	_create_ui()
	_create_muzzle_flash()
	_create_hero_intro()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if "--autostart" in OS.get_cmdline_user_args():
		_start_hero_mission()


func is_playing() -> bool:
	return state == GameState.PLAYING


func is_player_moving_fast() -> bool:
	return Vector2(player.velocity.x, player.velocity.z).length() > WALK_SPEED + 0.5


func material(color: Color, rough: float = 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


func box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, solid := true) -> Node3D:
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
		if parent == self and size.y < 50.0 and pos.y > -0.5:
			obstacles.append(AABB(pos - size / 2.0, size))
	return root


func _create_world() -> void:
	var env := WorldEnvironment.new()
	add_child(env)
	var e := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = SEA.lerp(BONE, 0.25)
	sky_mat.sky_horizon_color = BONE
	sky_mat.ground_horizon_color = SAND
	sky_mat.ground_bottom_color = KHAKI
	sky_mat.sun_angle_max = 30.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = SAND
	e.ambient_light_energy = 0.4
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -30, 0)
	sun.light_color = BONE
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	var sand := material(KHAKI.lerp(SAND, 0.55))
	var stone := material(KHAKI.darkened(0.1))
	var stone2 := material(KHAKI.lerp(INK, 0.15).lerp(SAND, 0.2))
	var dark := material(INK.lerp(KHAKI, 0.25))
	box(self, Vector3(0, -0.6, 0), Vector3(180, 1, 180), sand)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1942
	for i in range(75):
		var x := rng.randf_range(-76, 76)
		var z := rng.randf_range(-76, 76)
		if absf(x) < 10 and absf(z) < 10:
			continue
		var h := rng.randf_range(1.4, 5.5)
		box(self, Vector3(x, h / 2.0, z), Vector3(rng.randf_range(2.0, 6.0), h, rng.randf_range(2.0, 6.0)), stone if i % 2 == 0 else stone2)
	for i in range(18):
		var z := -55.0 + i * 6.0
		box(self, Vector3(-14, 1.2, z), Vector3(1.0, 2.4, 4.5), stone)
	for i in range(10):
		var x := -36.0 + i * 8.0
		box(self, Vector3(x, 0.6, -25), Vector3(3.5, 1.2, 1.8), dark)
	# Broken desert walls and a clear central combat lane.
	box(self, Vector3(17, 1.7, -10), Vector3(14, 3.4, 1.4), stone2)
	box(self, Vector3(23, 1.7, -20), Vector3(1.4, 3.4, 18), stone2)
	box(self, Vector3(-18, 1.3, 8), Vector3(11, 2.6, 1.2), stone)
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


func _create_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.position = Vector3(0, 2, 12)
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
		c.queue_free()
	if current_weapon() != "":
		Weapons.build_model(current_weapon(), gun, 0.8)


func _create_muzzle_flash() -> void:
	shot_flash = OmniLight3D.new()
	shot_flash.light_color = EMBER.lerp(BRASS, 0.4)
	shot_flash.light_energy = 0.0
	shot_flash.omni_range = 4.0
	camera.add_child(shot_flash)
	shot_flash.position = Vector3(0.25, -0.22, -0.9)


func _reload() -> void:
	var w := current_stats()
	if w.is_empty() or reload_timer > 0.0 or switch_timer > 0.0:
		return
	var id := current_weapon()
	if int(mag_ammo.get(id, 0)) >= int(w["mag"]) or int(reserve.get(w["ammo"], 0)) <= 0:
		return
	reload_timer = float(w["reload"])


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
	crate.position = Vector3(pos.x, 0.0, pos.z)
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


func _toggle_aim() -> void:
	aiming = not aiming


func _spawn_point_clear(p: Vector3) -> bool:
	var probe := AABB(p + Vector3(-0.8, 0.1, -0.8), Vector3(1.6, 1.8, 1.6))
	for o in obstacles:
		if o.intersects(probe):
			return false
	return true


func _create_enemies() -> void:
	var uniform := material(Color(0.33, 0.33, 0.24))
	var helmet := material(Color(0.20, 0.23, 0.17), 0.7)
	var metal := material(INK, 0.4)
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
		var enemy: CharacterBody3D = EnemyScript.new()
		enemy.name = "Enemy%d" % i
		add_child(enemy)
		enemy.position = p
		enemy.setup(self, p, Vector3(1, 0, 0) if i % 2 == 0 else Vector3(0, 0, 1), float(i) * 0.9, uniform, helmet, metal, ember_mat)
		enemy.died.connect(_on_enemy_died)
		enemies.append(enemy)


func _on_enemy_died(enemy: CharacterBody3D, by_player: bool) -> void:
	enemies.erase(enemy)
	if by_player:
		score += 1
		experience_points += 25
		reward_coins += 10
	else:
		zone_kills += 1
	# Fallen soldiers leave a small supply drop.
	_spawn_crate(enemy.global_position, LootScript.roll_enemy_drop(loot_rng), true)
	if enemies.is_empty() and state == GameState.PLAYING:
		_end_mission(true)


## Damage from enemy fire. Armour soaks part of it while it lasts.
func damage_player(amount: float, _from_pos: Vector3) -> void:
	if state != GameState.PLAYING:
		return
	var dmg := float(amount)
	if armor > 0.0:
		var soaked := minf(armor, dmg * ARMOR_ABSORB)
		armor -= soaked
		dmg -= soaked
	_apply_player_damage(dmg, 0.45)


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
		_end_mission(false)


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
	joy_base = ColorRect.new()
	joy_base.color = Color(SAND, 0.18)
	joy_base.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	joy_base.position = Vector2(45, -205)
	joy_base.size = Vector2(150, 150)
	joy_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(joy_base)
	joy_knob = ColorRect.new()
	joy_knob.color = Color(BONE, 0.5)
	joy_knob.position = Vector2(55, 55)
	joy_knob.size = Vector2(40, 40)
	joy_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joy_base.add_child(joy_knob)
	fire_button = _button(root, "FIRE", Vector2(-155, -185), Vector2(125, 125))
	fire_button.add_theme_stylebox_override("normal", _style(Color(EMBER, 0.6), BONE))
	fire_button.button_down.connect(func(): fire_held = true)
	fire_button.button_up.connect(func(): fire_held = false)
	jump_button = _button(root, "JUMP", Vector2(-290, -110), Vector2(115, 70))
	jump_button.pressed.connect(_jump)
	sprint_button = _button(root, "RUN", Vector2(-430, -110), Vector2(115, 70))
	sprint_button.button_down.connect(func(): sprint_held = true)
	sprint_button.button_up.connect(func(): sprint_held = false)
	reload_button = _button(root, "RELOAD", Vector2(-295, -200), Vector2(125, 65))
	reload_button.pressed.connect(_reload)
	aim_button = _button(root, "AIM", Vector2(-155, -265), Vector2(125, 65))
	aim_button.pressed.connect(_toggle_aim)
	swap_button = _button(root, "SWAP", Vector2(-295, -275), Vector2(125, 65))
	swap_button.pressed.connect(swap_weapon)
	interact_button = _button(root, "التقط", Vector2(-430, -200), Vector2(125, 65))
	interact_button.pressed.connect(interact)
	heal_button = _button(root, "HEAL", Vector2(-430, -275), Vector2(125, 65))
	heal_button.pressed.connect(use_medkit)
	# Touch controls only make sense on phones/tablets.
	for c in [joy_base, fire_button, jump_button, sprint_button, reload_button, aim_button, swap_button, interact_button, heal_button]:
		c.visible = is_mobile


func _button(parent: Control, label: String, offset: Vector2, dimensions: Vector2) -> Button:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	b.position = offset
	b.size = dimensions
	b.add_theme_font_size_override("font_size", 23)
	parent.add_child(b)
	return b


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
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x < get_viewport().get_visible_rect().size.x * 0.36 and joystick_id == -1:
				joystick_id = event.index
				_update_joystick(event.position)
			elif look_id == -1 and event.position.x < get_viewport().get_visible_rect().size.x * 0.73:
				look_id = event.index
				touch_last = event.position
		else:
			if event.index == joystick_id:
				joystick_id = -1
				joystick_vector = Vector2.ZERO
				joy_knob.position = Vector2(55, 55)
			if event.index == look_id:
				look_id = -1
	if event is InputEventScreenDrag:
		if event.index == joystick_id:
			_update_joystick(event.position)
		elif event.index == look_id:
			_look(event.position - touch_last, TOUCH_SENS)
			touch_last = event.position


func _update_joystick(screen_pos: Vector2) -> void:
	var center := joy_base.global_position + joy_base.size / 2.0
	joystick_vector = ((screen_pos - center) / 70.0).limit_length(1.0)
	joy_knob.position = Vector2(55, 55) + joystick_vector * 50.0


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
	var speed := RUN_SPEED if sprint_held or Input.is_action_pressed("sprint") else WALK_SPEED
	player.velocity.x = dir.x * speed
	player.velocity.z = dir.z * speed
	if not player.is_on_floor():
		player.velocity.y -= GRAVITY * delta
	if Input.is_action_just_pressed("jump"):
		_jump()
	player.move_and_slide()
	if player.global_position.y < -20.0:
		_end_mission(false)
		return
	since_damage += delta
	if since_damage > REGEN_DELAY and health < MAX_HEALTH:
		health = minf(MAX_HEALTH, health + REGEN_RATE * delta)
	_update_zone(delta)
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


func _shoot() -> void:
	var w := current_stats()
	if w.is_empty() or cooldown > 0 or reload_timer > 0 or switch_timer > 0:
		return
	if not bool(w["auto"]) and not trigger_released:
		return
	trigger_released = false
	var id := current_weapon()
	if int(mag_ammo.get(id, 0)) <= 0:
		_reload()
		return
	mag_ammo[id] = int(mag_ammo[id]) - 1
	shot_flash.light_energy = 3.5
	cooldown = float(w["interval"])
	recoil = -float(w["recoil"])
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
	if hit != null and hit.has_method("take_hit"):
		hit_marker_timer = 0.14
		# Headshots (top of the capsule) drop a soldier instantly.
		var headshot: bool = result.position.y > (hit as Node3D).global_position.y + 1.45
		hit.take_hit(float(w["damage"]) * (float(w["head_mult"]) if headshot else 1.0))


func _restart() -> void:
	get_tree().reload_current_scene()


func _end_mission(victory: bool) -> void:
	placement = 1 if victory else enemies.size() + 1
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
	restart.pressed.connect(_restart)
	box_layout.add_child(restart)


# Egyptian civilian atmosphere: fictional 1942-inspired market set dressing.
func _create_egyptian_life() -> void:
	var mud := material(KHAKI.lerp(SAND, 0.3))
	var wood := material(Color(0.31, 0.20, 0.12))
	var cloth := material(EMBER.darkened(0.2))
	var leaf := material(Color(0.20, 0.34, 0.16))
	var road := material(KHAKI.darkened(0.2))
	# Market lane on the edge of the existing training arena.
	box(self, Vector3(-33, 0.01, -17), Vector3(9, 0.05, 46), road, false)
	for i in range(5):
		var z := -35.0 + float(i) * 9.0
		box(self, Vector3(-40, 2.0, z), Vector3(5, 4, 6), mud)
		box(self, Vector3(-37.3, 1.2, z), Vector3(0.3, 2.4, 1.5), wood, false)
		box(self, Vector3(-37.0, 2.6, z), Vector3(3, 0.18, 3), cloth if i % 2 == 0 else material(SEA), false)
		box(self, Vector3(-36.8, 0.6, z - 1.2), Vector3(1.4, 1.2, 0.6), wood)
		var sign := Label3D.new()
		sign.text = ["قهوة المحروسة", "بقالة عم سيد", "ورشة أولاد النيل", "عيش بلدي", "سوق البلد"][i]
		sign.font = ARABIC_FONT
		sign.font_size = 80
		sign.pixel_size = 0.003
		sign.position = Vector3(-36.9, 3.5, z)
		sign.rotation_degrees.y = 90
		sign.modulate = INK
		sign.outline_modulate = Color(BONE, 0.6)
		sign.outline_size = 8
		sign.no_depth_test = false
		add_child(sign)
	for i in range(7):
		var z := -38.0 + float(i) * 11.0
		box(self, Vector3(-23, 2.2, z), Vector3(0.5, 4.4, 0.5), wood, false)
		for k in range(4):
			var crown := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 2.1
			sphere.height = 0.8
			crown.mesh = sphere
			crown.material_override = leaf
			crown.position = Vector3(-23 + cos(float(k) * PI / 2.0) * 1.1, 4.7, z + sin(float(k) * PI / 2.0) * 1.1)
			add_child(crown)
	# A simple Egyptian-style donkey cart silhouette (static prop, no animals).
	box(self, Vector3(-28, 0.9, -6), Vector3(3.1, 0.3, 1.6), wood, false)
	for side in [-1.0, 1.0]:
		var wheel := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.65
		cyl.bottom_radius = 0.65
		cyl.height = 0.15
		wheel.mesh = cyl
		wheel.material_override = wood
		wheel.rotation_degrees.z = 90
		wheel.position = Vector3(-28, 0.7, -6 + side * 0.85)
		add_child(wheel)


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
	layout.offset_top = 40
	layout.offset_bottom = -40
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
	content.add_theme_constant_override("separation", 14)
	layout.add_child(content)
	var brand := Label.new()
	brand.text = "حَرَق  HARAQ"
	brand.add_theme_font_size_override("font_size", 72)
	brand.add_theme_color_override("font_color", EMBER)
	content.add_child(brand)
	var title := Label.new()
	title.text = "WAR FRONT: EGYPT 1942"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", BRASS)
	content.add_child(title)
	var hero := Label.new()
	hero.text = "خالد كارم عبداللا\nKHALED KAREM ABDALLA"
	hero.add_theme_font_size_override("font_size", 28)
	hero.add_theme_color_override("font_color", SAND)
	content.add_child(hero)
	_label(content, "قائد المهمة | العلمين - مصر 1942", 21)
	_label(content, "باتل رويال: 20 جندي، صناديق إمداد، والدايرة بتضيق — آخر واحد واقف يكسب", 21)
	_label(content, "Battle royale vs 20 soldiers — loot crates, shrinking zone, last one standing wins", 20, SAND)
	var controls := Label.new()
	controls.text = "Touch: stick + drag to look, FIRE / AIM / RELOAD / SWAP / PICK UP / HEAL" if is_mobile else "WASD · Mouse · RMB aim · R reload · E pick up · 1/2/wheel swap · H heal"
	controls.add_theme_font_size_override("font_size", 17)
	controls.add_theme_color_override("font_color", Color(BONE, 0.7))
	content.add_child(controls)
	var start := Button.new()
	start.text = "ابدأ المهمة  |  START MISSION"
	start.custom_minimum_size = Vector2(420, 82)
	start.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	start.add_theme_font_size_override("font_size", 28)
	start.add_theme_stylebox_override("normal", _style(Color(EMBER, 0.85), BRASS))
	content.add_child(start)
	start.pressed.connect(_start_hero_mission)


func _start_hero_mission() -> void:
	state = GameState.PLAYING
	intro_overlay.visible = false
	if not is_mobile:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
