extends Node
## HARAQ v0.6.0 checks: final-zone spread, cover seeking + peeking, soldier-vs-soldier combat,
## kill feed and alive counter, enemy looting, weapon mesh cache, music / ducking / audio.
## Run with:  godot --headless --path proj res://test_v6.tscn
var game
var fails := 0
var passes := 0
const T := preload("res://scripts/terrain.gd")

func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
		print("PASS ", msg)
	else:
		fails += 1
		print("FAIL ", msg)

func frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame

func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func place(e, p: Vector3) -> void:
	e.global_position = Vector3(p.x, T.height(p.x, p.z) + 0.2, p.z)
	e.velocity = Vector3.ZERO
	e._can_see = false
	e.target = null
	e._los_timer = 0.0

func _ready():
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await frames(5)
	game._start_hero_mission()
	await frames(2)
	_freeze_zone()
	_static_checks()
	await _cover_checks()
	await _ffa_checks()
	await _loot_checks()
	await _spread_checks()
	await _audio_checks()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	print("RESULT passes=%d fails=%d" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)

func _freeze_zone() -> void:
	var zone = game.zone
	zone.target_center = Vector2.ZERO
	zone.target_radius = 500.0
	zone.radius = 500.0
	zone.center = Vector2.ZERO
	zone.shrinking = false
	zone.timer = 9999.0

func _isolate(keep: Array) -> void:
	for e in game.enemies:
		var on: bool = e in keep
		e.set_physics_process(on)
		if not on:
			# Park the rest of the squad far away so they don't join in.
			place(e, Vector3(-80 + randf() * 6.0, 0, -80 + randf() * 6.0))

# ------------------------------------------------------------------ static
func _static_checks() -> void:
	var cover = game.cover
	check(cover != null and cover.points.size() > 150, "cover map built (%d spots)" % (cover.points.size() if cover else -1))
	var bad := 0
	for sp in cover.points:
		if not game.nav.is_walkable(sp["p"]):
			bad += 1
	check(bad == 0, "every cover spot is walkable (%d bad)" % bad)
	var guns := {}
	var webleys := 0
	var signs := {}
	for e in game.enemies:
		guns[e.weapon] = true
		if e.weapon == "webley":
			webleys += 1
		signs[e.callsign] = true
		var gm = e._gun_holder.get_node_or_null("GunMesh")
		if gm == null:
			bad += 1
	check(bad == 0, "every soldier carries a real weapon model")
	check(webleys == 5 and guns.has("lee_enfield"), "squad starts with Lee-Enfields and 5 Webleys (%d)" % webleys)
	check(signs.size() == game.enemies.size(), "every soldier has a callsign for the kill feed")
	var m0 = game.enemies[0]._gun_holder.get_node("GunMesh").mesh
	var m1 = game.enemies[1]._gun_holder.get_node("GunMesh").mesh
	check(m0 == m1 and m0 != null, "weapon meshes are built once and shared (cache)")

# ------------------------------------------------------------------ cover
var cover_shot := {}

func _find_open_cover() -> Dictionary:
	# A cover spot with open ground ~12 m in front of the obstacle (the threat side).
	var nav = game.nav
	for sp in game.cover.points:
		var p: Vector3 = sp["p"]
		if absf(p.x) > 60 or absf(p.z) > 60:
			continue
		var threat: Vector3 = p - sp["n"] * 13.0
		if not nav.is_walkable(threat) or nav.line_clear(p, threat):
			continue
		var start: Vector3 = p + sp["t"] * 5.0 - sp["n"] * 1.0
		if nav.is_walkable(start) and nav.line_clear(start, threat):
			return {"p": p, "threat": threat, "start": start}
	return {}

func _cover_checks() -> void:
	game.free_for_all = false
	var e = game.enemies[0]
	_isolate([e])
	var c := _find_open_cover()
	check(not c.is_empty(), "found an open-ground cover test site")
	if c.is_empty():
		return
	var threat: Vector3 = c["threat"]
	var found: Dictionary = game.cover.find(c["start"], threat, e, game.nav)
	check(not found.is_empty() and not game.nav.line_clear(found["p"], threat), "cover search returns a spot hidden from the threat")
	check(not found.is_empty() and game.nav.line_clear(found["peek"], threat) , "cover spot has a peek position with a line of fire")
	var other = game.enemies[1]
	var found2: Dictionary = game.cover.find(c["start"], threat, other, game.nav)
	check(found2.is_empty() or flat(found2["p"], found["p"]) > 0.5, "two soldiers never get the same cover spot (reservations)")
	game.cover.release(e)
	game.cover.release(other)
	# Live: player fires on a soldier standing in the open; he runs for cover while reloading.
	game.player.global_position = Vector3(threat.x, T.height(threat.x, threat.z) + 0.5, threat.z)
	place(e, c["start"])
	e.state = e.State.PATROL
	e.hit_points = 100.0
	e.target = null
	var entered := false
	var hidden_frames := 0
	var peeked := false
	var shots0: int = e.shots_fired
	for i in range(60 * 14):
		await get_tree().physics_frame
		game.health = 100.0
		if i == 20:
			e.take_hit(22.0)
			e._mag = 0
			e._shoot(5.0)
		if e.state == e.State.COVER:
			entered = true
			if e._cover_phase == 1 and e.is_hidden_from(game.player.global_position):
				hidden_frames += 1
			if e._cover_phase == 2:
				peeked = true
		if i == 60 * 5 and entered:
			cover_shot = {"e": e, "threat": threat}
	check(entered, "soldier under fire while reloading runs for cover (%d entries)" % e.cover_entries)
	check(hidden_frames > 30, "soldier hides behind the obstacle, out of the player's line of sight (%d frames)" % hidden_frames)
	check(peeked and e.peeks > 0, "soldier peeks out of cover (%d peeks)" % e.peeks)
	check(e.shots_fired > shots0, "soldier shoots back from the peek spot (%d shots)" % (e.shots_fired - shots0))
	check(e._mag > 0, "soldier reloaded in cover (mag %d)" % e._mag)

# ------------------------------------------------------------------ free-for-all
func _ffa_checks() -> void:
	game.free_for_all = true
	game.player.global_position = Vector3(85, T.height(85, 85) + 0.5, 85)
	var a = game.enemies[2]
	var b = game.enemies[3]
	_isolate([a, b])
	var spot := Vector3(10, 0, -30)
	if not game.nav.is_walkable(spot):
		spot = game.nav.nearest_free_point(spot)
	place(a, spot)
	place(b, game.nav.nearest_free_point(spot + Vector3(9, 0, 0)))
	a.state = a.State.PATROL
	b.state = b.State.PATROL
	a.origin = a.global_position
	b.origin = b.global_position
	a.hit_points = 100.0
	b.hit_points = 12.0
	b.equip("webley")
	a.equip("mp40")
	var alive0: int = game.alive_count()
	var feed0: int = game.kill_feed_entries.size()
	var zk0: int = game.zone_kills
	var sc0: int = game.score
	var b_name: String = b.callsign
	var a_name: String = a.callsign
	var targeted := false
	for i in range(60 * 25):
		await get_tree().physics_frame
		if is_instance_valid(a) and a.target == b:
			targeted = true
		if not is_instance_valid(b) or not is_instance_valid(a):
			break
		if i % 120 == 0:
			print("INFO ffa t=%d a=%s st=%d tgt=%s see=%s shots=%d hp=%.0f | b=%s st=%d see=%s shots=%d hp=%.0f" % [i, a.global_position, a.state, a.target, a._can_see, a.shots_fired, a.hit_points, b.global_position, b.state, b._can_see, b.shots_fired, b.hit_points])
	check(targeted, "soldiers target each other (everyone is hostile)")
	check(not is_instance_valid(a) or not is_instance_valid(b), "a soldier was killed by another soldier")
	await frames(2)
	check(game.alive_count() == alive0 - 1, "alive counter drops by one (%d -> %d)" % [alive0, game.alive_count()])
	check(game.zone_kills == zk0 and game.score == sc0, "enemy kill is not counted as zone kill or player score")
	check(game.kills_by_enemies >= 1, "kills by soldiers counted (%d)" % game.kills_by_enemies)
	var last: String = game.kill_feed_entries[-1]["text"] if game.kill_feed_entries.size() > feed0 else ""
	check(last.find("»") > 0 and (last.find(b_name) > 0 or last.find(a_name) > 0), "kill feed shows KILLER » VICTIM (%s)" % last)
	check(last.find("(") > 0, "kill feed names the weapon")
	check(game.kill_feed.text.find(last) >= 0, "kill feed label on screen")
	game._update_hud()
	check(game.alive_label.text.find("ALIVE %d" % game.alive_count()) == 0, "HUD alive label matches (%s)" % game.alive_label.text)
	# Zone kill entry + player kill entry.
	var z = game.enemies[4]
	var zname: String = z.callsign
	z.take_zone_damage(500.0)
	await frames(1)
	check(game.kill_feed_entries[-1]["text"].find(zname) > 0 and game.kill_feed_entries[-1]["text"].begins_with(game.ZONE_CALLSIGN), "zone death shows in the kill feed")
	var pk = game.enemies[5]
	var pname: String = pk.callsign
	pk.take_hit(500.0)
	await frames(1)
	check(game.kill_feed_entries[-1]["text"].begins_with(game.PLAYER_CALLSIGN) and game.kill_feed_entries[-1]["text"].find(pname) > 0, "player kill shows in the kill feed")
	check(game.kill_feed_entries.size() <= 5, "kill feed keeps the last 5 entries")
	game.mission_time += 7.0
	game._refresh_kill_feed()
	check(game.kill_feed.text == "", "kill feed entries fade after 6 s")
	# Enemy gunfire draws nearby idle soldiers.
	var s = game.enemies[6]
	var w = game.enemies[7]
	_isolate([])
	place(s, Vector3(30, 0, 30))
	place(w, game.nav.nearest_free_point(Vector3(38, 0, 30)))
	w.target = null
	w.state = w.State.PATROL
	game.on_enemy_shot(s)
	check(w.target == s and w.state == w.State.CHASE, "gunfire alerts nearby soldiers to the shooter")

# ------------------------------------------------------------------ looting
func _loot_checks() -> void:
	game.free_for_all = false
	game.player.global_position = Vector3(85, T.height(85, 85) + 0.5, 85)
	var e = game.enemies[8]
	_isolate([e])
	var p: Vector3 = game.nav.nearest_free_point(Vector3(-20, 0, 20))
	place(e, p)
	e.equip("webley")
	e.hit_points = 55.0
	e.state = e.State.PATROL
	e.origin = e.global_position
	e.patrol_axis = Vector3.ZERO
	e._loot_timer = 0.0
	var cp: Vector3 = p
	for off in [Vector3(7, 0, 3), Vector3(-7, 0, 3), Vector3(6, 0, -5), Vector3(-6, 0, -5), Vector3(0, 0, 8), Vector3(0, 0, -8)]:
		cp = game.nav.nearest_free_point(p + off)
		if game.nav.line_clear(p, cp):
			break
	for old in game.loot_crates.duplicate():
		if is_instance_valid(old) and flat(old.global_position, p) < 30.0:
			game.loot_crates.erase(old)
			old.queue_free()
	var crate = game._spawn_crate(cp, {"weapon": "thompson", "ammo": {}, "medkits": 1, "armor": 0.0}, true)
	var loot0: int = game.enemy_loots
	for i in range(60 * 10):
		await get_tree().physics_frame
		if e.weapon == "thompson":
			break
	print("INFO loot: state=%d crate=%s pos=%s crate_at=%s origin=%s find=%s timer=%.2f" % [e.state, e._loot_crate, e.global_position, cp, e.origin, e._find_loot(), e._loot_timer])
	check(e.weapon == "thompson", "soldier walks to a nearby crate and takes the better weapon")
	check(e.hit_points > 55.0, "soldier used the medkit (hp %.0f)" % e.hit_points)
	check(game.enemy_loots > loot0, "enemy loot counted (%d)" % game.enemy_loots)
	check(is_instance_valid(crate) and crate.contents.get("weapon", "") == "webley", "his old weapon is left in the crate")
	check(e._gun_holder.get_node_or_null("GunMesh") != null, "new weapon model in his hands")
	await frames(3)
	var gm := 0
	for c in e._gun_holder.get_children():
		if not c.is_queued_for_deletion():
			gm += 1
	check(gm == 1, "old weapon model removed (%d models)" % gm)
	# He won't go back for the worse gun.
	e._loot_timer = 0.0
	e.origin = e.global_position
	await frames(90)
	check(e.weapon == "thompson", "soldier ignores worse weapons")
	# Claims: two soldiers don't go for the same crate.
	var f1 = game.enemies[9]
	var f2 = game.enemies[10]
	f1.equip("webley")
	f2.equip("webley")
	place(f1, p)
	place(f2, game.nav.nearest_free_point(p + Vector3(0, 0, -2)))
	var crate2 = game._spawn_crate(cp, {"weapon": "mp40", "ammo": {}, "medkits": 0, "armor": 0.0}, true)
	var c1 = f1._find_loot()
	var c2 = f2._find_loot()
	check(c1 == crate2 and c2 != crate2, "a crate is claimed by one soldier at a time")

# ------------------------------------------------------------------ final zone spread
func _spread_checks() -> void:
	game.free_for_all = false
	game.player.global_position = Vector3(85, T.height(85, 85) + 0.5, 85)
	var zone = game.zone
	var c: Vector3 = game.nav.nearest_free_point(Vector3(5, 0, 5))
	zone.target_center = Vector2(c.x, c.z)
	zone.center = Vector2(c.x, c.z)
	zone.target_radius = 12.0
	zone.radius = 12.0
	var squad: Array = []
	for e in game.enemies:
		if squad.size() < 10:
			squad.append(e)
	_isolate(squad)
	for i in range(squad.size()):
		var e = squad[i]
		e.target = null
		e.state = e.State.PATROL
		e.hit_points = 100.0
		e._loot_crate = null
		e._loot_timer = 999.0
		place(e, game.nav.nearest_free_point(c + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))))
	var origins := {}
	await frames(2)
	for e in squad:
		origins[e.origin.snapped(Vector3(1, 100, 1))] = true
	check(origins.size() == squad.size(), "small zone: every soldier gets its own post (%d unique of %d)" % [origins.size(), squad.size()])
	await frames(60 * 12)
	var min_d := 999.0
	var close := 0
	var outside := 0
	for i in range(squad.size()):
		for j in range(i + 1, squad.size()):
			var d := flat(squad[i].global_position, squad[j].global_position)
			min_d = minf(min_d, d)
			if d < 1.2:
				close += 1
		if not zone.is_inside(squad[i].global_position):
			outside += 1
	print("INFO final-zone spread: min pair distance %.2f m, pairs closer than 1.2 m: %d" % [min_d, close])
	check(close == 0, "no two soldiers jammed together in the final zone (min %.2f m)" % min_d)
	check(min_d > 1.5, "soldiers keep spacing in the final zone (%.2f m)" % min_d)
	check(outside == 0, "everyone stays inside the small zone (%d outside)" % outside)
	_freeze_zone()

# ------------------------------------------------------------------ audio
func _audio_checks() -> void:
	var au = game.audio
	print("INFO music track=%s streams=%s state=%d" % [au.music_track, au.music_streams.keys(), game.state])
	check(AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("SFX") >= 0, "separate Music and SFX buses")
	check(au.has_method("set_music_volume") and au.has_method("set_sfx_volume"), "music and SFX volume setters")
	check(au.music_player != null and au.music_player.playing, "in-match music loop playing")
	check(au.music_player.stream != null and String(au.music_player.stream.resource_path if au.music_player.stream else "").find("music_battle") >= 0, "battle theme loaded (%s)" % au.music_player.stream.resource_path)
	check(ResourceLoader.exists("res://assets/audio/music_menu.ogg"), "menu theme shipped")
	au.set_music_volume(0.3)
	au.set_sfx_volume(0.8)
	await frames(1)
	var mb := AudioServer.get_bus_index("Music")
	var sb := AudioServer.get_bus_index("SFX")
	check(absf(db_to_linear(AudioServer.get_bus_volume_db(sb)) - 0.8) < 0.02, "SFX bus volume follows its slider")
	var before := AudioServer.get_bus_volume_db(mb)
	au.duck(0.6)
	await frames(3)
	var ducked := AudioServer.get_bus_volume_db(mb)
	check(ducked < before - 3.0, "music ducks on gunfire (%.1f -> %.1f dB)" % [before, ducked])
	await frames(150)
	check(AudioServer.get_bus_volume_db(mb) > ducked + 3.0, "music recovers after the duck (%.1f dB)" % AudioServer.get_bus_volume_db(mb))
	au.save_settings()
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	check(absf(float(cfg.get_value("audio", "music", -1.0)) - 0.3) < 0.01 and absf(float(cfg.get_value("audio", "sfx", -1.0)) - 0.8) < 0.01, "music / SFX volumes saved")
	check(game.music_slider != null and game.sfx_slider != null, "intro has separate MUSIC and SFX sliders")
	var p0 = au.players[0] if "players" in au else null
	check(p0 == null or p0.bus == "SFX", "sound effects play on the SFX bus")
	for n in ["shot_enfield", "shot_thompson", "explosion"]:
		var s: AudioStream = load("res://assets/audio/%s.ogg" % n)
		check(s != null and s.get_length() > 0.9, "%s has a reverb tail (%.2f s)" % [n, s.get_length() if s else 0.0])
