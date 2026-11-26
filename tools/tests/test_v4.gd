extends Node
## Scripted test + screenshots for HARAQ v0.4.0 battle-royale (graphics upgrade) features.
var game
var t := 0
var shots := "--shots" in OS.get_cmdline_user_args()
var fails := 0
var h0 := 0.0
var e_hp0 := 0.0
var probe_enemy

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS ", msg)
	else:
		fails += 1
		print("FAIL ", msg)

func _ready():
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func shot(n):
	if not shots:
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/workspace/haraq-shots-v5/v4test_%s.png" % n)
	print("saved ", n)

func _face_toward(p: Vector3) -> void:
	var d = p - game.player.global_position
	game.player.rotation.y = atan2(-d.x, -d.z)

func _physics_process(_d):
	t += 1
	if t == 15: shot("1_intro")
	if t == 20:
		game._start_hero_mission()
		check(game.slots[0] == "webley" and game.slots[1] == "", "starts with pistol only")
		check(game.enemies.size() == 20, "20 enemies spawned (got %d)" % game.enemies.size())
		check(game.loot_crates.size() >= 25, "loot crates placed (got %d)" % game.loot_crates.size())
	# --- v0.4 graphics: quality presets, terrain placement
	if t == 21:
		var Gfx = load("res://scripts/graphics.gd")
		var T = load("res://scripts/terrain.gd")
		game.set_quality(0)
		check(game.get_viewport().msaa_3d == Viewport.MSAA_DISABLED and not game.sun.shadow_enabled, "LOW preset: no MSAA, no shadows")
		check(Gfx.load_quality() == 0, "quality saved to user://settings.cfg")
		game.set_quality(2)
		check(game.get_viewport().msaa_3d == Viewport.MSAA_4X and game.sun.shadow_enabled and game.sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "HIGH preset: MSAA 4x, 4-split shadows")
		check(game.camera.far >= 500.0, "HIGH preset draw distance")
		game.set_quality(1)
		check(Gfx.load_quality() == 1 and game.world_env.environment.glow_enabled, "MEDIUM preset saved, glow on")
		var max_dev := 0.0
		for c in game.loot_crates:
			max_dev = maxf(max_dev, absf(c.global_position.y - T.height(c.global_position.x, c.global_position.z)))
		check(max_dev < 0.2, "loot crates sit on the dunes (max dev %.2f)" % max_dev)
		var lo := 99.0
		var hi := -99.0
		for x in range(-80, 81, 8):
			for z in range(-80, 81, 8):
				var h: float = T.height(float(x), float(z))
				lo = minf(lo, h)
				hi = maxf(hi, h)
		check(hi - lo > 1.0 and hi - lo < 6.0, "arena has gentle dunes (range %.2f m)" % (hi - lo))
		check(T.height(0, -130) < -0.55, "sea north of the arena is below sea level")
	if t == 24:
		var T = load("res://scripts/terrain.gd")
		var bad := 0
		for e in game.enemies:
			if absf(e.global_position.y - T.height(e.global_position.x, e.global_position.z)) > 1.0:
				bad += 1
		check(bad == 0, "all enemies spawned on the terrain (%d off)" % bad)
	# --- Pickup: walk onto starter Thompson crate (free slot -> auto pick)
	if t == 25:
		game.player.global_position = Vector3(3.5, 0.1, 8.5)
	if t == 30:
		check(game.slots[1] == "thompson", "auto-picked Thompson into slot 2 (slots=%s)" % [game.slots])
		check(game.current_slot == 1, "switched to new weapon")
		check(int(game.reserve["smg"]) >= 60, "smg ammo picked up (%d)" % int(game.reserve["smg"]))
		check(game.medkits == 1, "medkit picked up")
		game.player.global_position = Vector3(0, 0.1, 18)
	# --- Shooting consumes per-weapon magazine
	if t == 50:
		var before := int(game.mag_ammo["thompson"])
		game.switch_timer = 0.0
		game.cooldown = 0.0
		game._shoot()
		check(int(game.mag_ammo["thompson"]) == before - 1, "Thompson fired (mag %d -> %d)" % [before, int(game.mag_ammo["thompson"])])
	# --- Switch with keys/API
	if t == 52:
		game.switch_to_slot(0)
		check(game.current_weapon() == "webley", "switch to slot 1 = pistol")
		var ev := InputEventKey.new()
		ev.keycode = KEY_2
		ev.pressed = true
		Input.parse_input_event(ev)
	if t == 56:
		check(game.current_weapon() == "thompson", "key 2 switches to Thompson")
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		Input.parse_input_event(wheel)
	if t == 60:
		check(game.current_weapon() == "webley", "mouse wheel swaps back to pistol")
	# --- Interact replaces held weapon when both slots are full
	if t == 62:
		var c = game._spawn_crate(Vector3(6, 0, 18), {"weapon": "lee_enfield", "ammo": {"rifle": 20}, "medkits": 0, "armor": 50.0})
		game.player.global_position = Vector3(6, 0.1, 18.5)
	if t == 66:
		check(game.slots.find("lee_enfield") == -1, "full slots: rifle not auto-taken")
		check(game.armor >= 50.0, "armor auto-picked (%d)" % int(game.armor))
		check(int(game.reserve["rifle"]) >= 20, "rifle ammo auto-picked")
		game.interact()
		check(game.slots[0] == "lee_enfield" and game.current_weapon() == "lee_enfield", "E swaps pistol for Lee-Enfield (slots=%s)" % [game.slots])
	if t == 70:
		var found := false
		for c in game.loot_crates:
			if is_instance_valid(c) and c.contents.get("weapon", "") == "webley":
				found = true
		check(found, "old pistol dropped in a crate")
	# --- Armor soaks enemy damage
	if t == 72:
		var hp = game.health
		var ar = game.armor
		game.damage_player(10.0, Vector3.ZERO)
		check(is_equal_approx(game.health, hp - 4.0) and is_equal_approx(game.armor, ar - 6.0), "armor absorbs 60%% (hp %.1f ar %.1f)" % [game.health, game.armor])
		game.use_medkit()
		check(game.medkits == 0 and game.health > hp - 4.0, "medkit heals")
	# --- Zone damage hits player and enemies
	if t == 80:
		probe_enemy = game.enemies[0]
		e_hp0 = probe_enemy.hit_points
		var pp = game.player.global_position
		game.zone.center = Vector2(pp.x, pp.z) + Vector2(0, -40)
		game.zone.radius = 20.0
		game.zone.target_center = game.zone.center
		game.zone.target_radius = 10.0
		game.zone._from_center = game.zone.center
		game.zone._from_radius = 20.0
		game.zone.phase = 2
		game.zone.shrinking = true
		game.zone.timer = 30.0
		h0 = game.health
	if t == 110:
		check(game.health < h0, "zone damages player outside (%.1f -> %.1f)" % [h0, game.health])
		if is_instance_valid(probe_enemy) and not game.zone.is_inside(probe_enemy.global_position):
			check(probe_enemy.hit_points < e_hp0, "zone damages enemy outside (%.1f -> %.1f)" % [e_hp0, probe_enemy.hit_points])
		check(game.zone.radius < 20.0, "zone shrinking (r=%.2f)" % game.zone.radius)
		_face_toward(Vector3(game.zone.center.x, 1, game.zone.center.y))
		game.health = 100.0
	if t == 120: shot("3_zone_outside")
	if t == 125:
		# Back inside; look around at loot.
		game.zone.center = Vector2(0, 0); game.zone.radius = 55.0; game.zone.target_center = Vector2(10, -8); game.zone.target_radius = 30.0
		game.zone._from_center = game.zone.center; game.zone._from_radius = 55.0
		game.zone.shrinking = false; game.zone.phase = 1; game.zone.timer = 41.0
		game.zone._update_visuals()
		var best = null
		for c in game.loot_crates:
			if is_instance_valid(c) and c.contents.get("weapon", "") != "" and c.global_position.distance_to(Vector3.ZERO) < 40:
				best = c
				break
		if best:
			game.player.global_position = best.global_position + Vector3(0, 0.1, 4.0)
			_face_toward(best.global_position)
			game.head.rotation.x = -0.25
	if t == 150: shot("4_loot_crate")
	if t == 155:
		game.player.global_position = Vector3(0, 0.1, 25)
		game.player.rotation.y = 0
		game.head.rotation.x = 0.05
		game.switch_to_slot(0)
		game.switch_timer = 0
		game.aiming = true
	if t == 190: shot("5_rifle_ads_zone_wall")
	if t == 192:
		game.aiming = false
		game.switch_to_slot(1)
	if t == 220: shot("6_thompson_hud")
	# --- Death placement
	if t == 222:
		var T = load("res://scripts/terrain.gd")
		var fell := 0
		for e in game.enemies:
			if e.global_position.y < T.height(e.global_position.x, e.global_position.z) - 0.6:
				fell += 1
		check(fell == 0, "no enemy fell through the terrain after 200 frames (%d)" % fell)
	if t == 225:
		game.damage_player_zone(1000.0)
		check(game.state == game.GameState.DEAD, "player dies")
		check(game.placement == game.enemies.size() + 1, "placement #%d shown" % game.placement)
	if t == 232: shot("7_dead_placement")
	if t == 270:
		game.end_overlay.get_parent().queue_free()
		game.state = game.GameState.PLAYING
		for e in game.enemies.duplicate():
			e.take_zone_damage(1000.0)
		check(game.state == game.GameState.WON and game.placement == 1, "last one standing wins (#1)")
		check(game.zone_kills > 0, "zone kills counted (%d)" % game.zone_kills)
	if t == 290: shot("8_victory")
	if t == 310:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
		print("RESULT fails=%d" % fails)
		get_tree().quit(1 if fails > 0 else 0)
