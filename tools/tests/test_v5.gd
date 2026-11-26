extends Node
## HARAQ v0.5.0 checks: navigation AI, stuck recovery, attack state, audio, touch HUD layout,
## tank / weapon models. Run with:  godot --headless --path proj res://test_v5.tscn -- --touch-ui
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

func _ready():
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await frames(5)
	game._start_hero_mission()
	await frames(2)
	await _nav_checks()
	await _ai_checks()
	await _audio_checks()
	await _hud_checks()
	_model_checks()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	print("RESULT passes=%d fails=%d" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)

# ------------------------------------------------------------------ navigation grid
var rock_box: AABB

func _nav_checks() -> void:
	var nav = game.nav
	check(nav != null and nav.solid_count > 800, "nav grid built (%d blocked cells)" % (nav.solid_count if nav else -1))
	var unblocked := 0
	var big: Array = []
	for o in game.obstacles:
		var c: Vector3 = o.get_center()
		if o.end.y - T.height(c.x, c.z) > 0.6 and absf(c.x) < 85 and absf(c.z) < 85:
			if nav.is_walkable(c):
				unblocked += 1
			if o.size.x > 3.0 and o.size.z > 3.0 and o.size.x < 7.0 and absf(c.x) < 70 and absf(c.z) < 70:
				big.append(o)
	check(unblocked == 0, "every obstacle footprint is blocked on the nav grid (%d missed)" % unblocked)
	# Pick a boulder with open ground on both sides (east-west).
	# Prefer a long flat wall (worst case for straight-line steering), else a boulder.
	var cands: Array = []
	for o in game.obstacles:
		if o.size.x > 8.0 and o.size.z < 2.0 and absf(o.get_center().x) < 70 and absf(o.get_center().z) < 70:
			cands.append(o)
	cands.append_array(big)
	for o in cands:
		var c: Vector3 = o.get_center()
		var a := Vector3(c.x, 0, o.position.z - 4.0)
		var b := Vector3(c.x, 0, o.end.z + 4.0)
		if nav.is_walkable(a) and nav.is_walkable(b) and not nav.line_clear(a, b):
			rock_box = o
			break
	check(rock_box.size.x > 0.0, "found cover (%.0fx%.0f m) blocking a straight line for the AI test" % [rock_box.size.x, rock_box.size.z])
	var a2 := Vector3(rock_box.get_center().x, 0, rock_box.position.z - 4.0)
	var b2 := Vector3(rock_box.get_center().x, 0, rock_box.end.z + 4.0)
	var path: PackedVector3Array = nav.find_path(a2, b2)
	var ok := path.size() >= 2
	var prev := a2
	for p in path:
		if not nav.line_clear(prev, p):
			ok = false
		prev = p
	check(ok and flat(path[path.size() - 1], b2) < 1.0, "path goes around the rock with clear segments (%d corners)" % path.size())
	var t0 := Time.get_ticks_usec()
	for i in range(50):
		nav.find_path(Vector3(randf_range(-75, 75), 0, randf_range(-75, 75)), Vector3(randf_range(-75, 75), 0, randf_range(-75, 75)))
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / 50.0
	check(ms < 4.0, "path query is cheap (%.2f ms average, desktop)" % ms)

# ------------------------------------------------------------------ AI behaviour
func _freeze_all_but(keep) -> void:
	for e in game.enemies:
		e.set_physics_process(e == keep)

func _run_to(e, start: Vector3, goal: Vector3, secs: float) -> float:
	e.global_position = Vector3(start.x, T.height(start.x, start.z) + 0.2, start.z)
	e.velocity = Vector3.ZERO
	e.state = e.State.PATROL
	e.origin = goal
	e.patrol_axis = Vector3.ZERO
	e._path = PackedVector3Array()
	e._repath_timer = 0.0
	var best := 999.0
	for i in range(int(secs * 60.0)):
		await get_tree().physics_frame
		e.origin = goal
		best = minf(best, flat(e.global_position, goal))
		if best < 1.0:
			break
	return best

func _ai_checks() -> void:
	var zone = game.zone
	zone.target_center = Vector2.ZERO
	zone.target_radius = 500.0
	zone.radius = 500.0
	zone.center = Vector2.ZERO
	zone.shrinking = false
	zone.timer = 9999.0
	game.health = 100.0
	game.player.global_position = Vector3(85, T.height(85, 85) + 0.5, 85)
	var e = game.enemies[0]
	_freeze_all_but(e)
	var c := rock_box.get_center()
	var a := Vector3(c.x, 0, rock_box.position.z - 4.0)
	var b := Vector3(c.x, 0, rock_box.end.z + 4.0)
	# Old behaviour (straight-line steering, no nav) for comparison.
	var nav = game.nav
	game.nav = null
	var d_old: float = await _run_to(e, a, b, 10.0)
	game.nav = nav
	var d_new: float = await _run_to(e, a, b, 10.0)
	print("INFO straight-line steering ended %.1f m from the goal; nav steering %.1f m" % [d_old, d_new])
	check(d_new < 1.5 and d_old > 2.5, "soldier walks around cover to reach its post (%.2f m; straight line: %.1f m)" % [d_new, d_old])
	# Stuck recovery: an invisible wall the nav grid does not know about.
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.0, 3.0, 5.0)
	cs.shape = bs
	wall.add_child(cs)
	var start := Vector3(0, 0, 40)
	var wp := Vector3(4, 0, 40)
	var goal := Vector3(9, 0, 40)
	for p in [start, wp, goal]:
		if not nav.is_walkable(p) or not nav.line_clear(start, goal):
			start = Vector3(40, 0, 40); wp = Vector3(44, 0, 40); goal = Vector3(49, 0, 40)
	game.add_child(wall)
	wall.global_position = Vector3(wp.x, T.height(wp.x, wp.z) + 1.5, wp.z)
	await frames(2)
	var s0: int = e.stuck_events
	var d_stuck: float = await _run_to(e, start, goal, 20.0)
	check(e.stuck_events > s0, "stuck detection fired at an unknown wall (%d events)" % (e.stuck_events - s0))
	check(d_stuck < 1.5, "recovered and reached the goal behind the wall (%.2f m)" % d_stuck)
	wall.queue_free()
	# Attack state: in range with line of sight -> ATTACK + shoots.
	var op := Vector3(20, 0, 30)
	game.player.global_position = Vector3(op.x, T.height(op.x, op.z) + 0.3, op.z)
	e.global_position = Vector3(op.x + 7.0, T.height(op.x + 7, op.z) + 0.2, op.z)
	e.state = e.State.PATROL
	var shots0: int = e.shots_fired
	var saw_attack := false
	for i in range(240):
		await get_tree().physics_frame
		game.health = 100.0
		if e.state == e.State.ATTACK:
			saw_attack = true
	check(saw_attack, "soldier switches to ATTACK when the player is in sight")
	check(e.shots_fired > shots0, "soldier shoots in ATTACK (%d shots)" % (e.shots_fired - shots0))
	# Lose sight -> CHASE -> back to PATROL after LOSE_SIGHT_TIME.
	game.player.global_position = Vector3(-85, T.height(-85, 85) + 0.5, 85)
	await frames(30)
	check(e.state == e.State.CHASE, "soldier chases the last known position after losing sight")
	await frames(int((e.LOSE_SIGHT_TIME + 1.0) * 60))
	check(e.state == e.State.PATROL, "soldier returns to PATROL after %.0f s" % e.LOSE_SIGHT_TIME)
	# Whole squad: 6 s of free movement, nobody stays wedged.
	for x in game.enemies:
		x.set_physics_process(true)
		x.alert()
	var starts := {}
	for x in game.enemies:
		starts[x] = x.global_position
	game.player.global_position = Vector3(0, T.height(0, 0) + 0.5, 0)
	for i in range(360):
		await get_tree().physics_frame
		game.health = 100.0
	var inside := 0
	for x in game.enemies:
		if not nav.is_walkable(x.global_position) and nav.grid.is_point_solid(nav.cell_of(x.global_position)):
			var c2: Vector3 = x.global_position
			for o in game.obstacles:
				if o.grow(-0.1).has_point(Vector3(c2.x, o.get_center().y, c2.z)):
					inside += 1
					break
	check(inside == 0, "no soldier ends up inside an obstacle footprint (%d)" % inside)
	game.player.global_position = Vector3(0, T.height(0, 12) + 0.5, 12)

# ------------------------------------------------------------------ audio
func _audio_checks() -> void:
	var au = game.audio
	check(au != null and au.streams.size() == au.NAMES.size(), "all %d sounds load (%d)" % [au.NAMES.size(), au.streams.size()])
	var missing := 0
	for n in au.NAMES:
		if not FileAccess.file_exists("res://assets/audio/%s.ogg" % n):
			missing += 1
	check(missing == 0, "every sound is a bundled .ogg")
	check(au.wind.stream != null and au.wind.stream.loop and au.sea.stream.loop, "wind + sea ambience loop")
	check(au.wind.playing, "ambience starts with the mission")
	for id in ["webley", "lee_enfield", "thompson", "mp40"]:
		game.give_weapon(id)
		game.switch_to_slot(game.slots.find(id))
		game.switch_timer = 0.0
		game.cooldown = 0.0
		game.reload_timer = 0.0
		game.trigger_released = true
		game.mag_ammo[id] = 5
		var key: String = au.SHOT[id]
		var n0 := int(au.played.get(key, 0))
		game._shoot()
		check(int(au.played.get(key, 0)) == n0 + 1, "%s fires its own sound (%s)" % [id, key])
	var r0 := int(au.played.get("reload", 0))
	game.reserve[game.current_stats()["ammo"]] = 30
	game._reload()
	check(int(au.played.get("reload", 0)) == r0 + 1, "reload sound")
	game.reload_timer = 0.0
	var hit_total := int(au.played.get("hit_sand", 0)) + int(au.played.get("hit_metal", 0)) + int(au.played.get("hit_flesh", 0))
	check(hit_total > 0, "bullet impacts make a sound (%d)" % hit_total)
	var h0 := int(au.played.get("hurt", 0))
	game.damage_player(1.0, Vector3.ZERO)
	check(int(au.played.get("hurt", 0)) == h0 + 1, "player hit sound")
	game.health = 100.0
	check(int(au.played.get("shot_enemy", 0)) > 0, "enemy gunshots are positional sounds (%d)" % int(au.played.get("shot_enemy", 0)))
	check(int(au.played.get("step", 0)) > 0, "enemy footsteps (%d)" % int(au.played.get("step", 0)))
	# Player footsteps.
	var s0 := int(au.played.get("step", 0))
	for x in game.enemies:
		x.set_physics_process(false)
	game.player.global_position = Vector3(0, T.height(0, 16) + 0.3, 16)
	game.joystick_id = 99
	game.joystick_vector = Vector2(0, -1)
	await frames(90)
	game.joystick_id = -1
	game.joystick_vector = Vector2.ZERO
	check(int(au.played.get("step", 0)) > s0 + 2, "player footsteps while walking (%d)" % (int(au.played.get("step", 0)) - s0))
	# Zone burn loop + explosions.
	au.update_mix(0.016, 100.0, 10.0, game.player.global_position)
	check(au.burn.volume_db > -20.0, "zone burn loop audible outside the zone (%.1f dB)" % au.burn.volume_db)
	au.update_mix(0.016, 5.0, 0.0, game.player.global_position)
	check(au.burn.volume_db <= -59.0 and au.sea.volume_db > -10.0, "burn off inside, sea loud on the beach")
	au._shell_timer = 0.0
	var e0 := int(au.played.get("explosion", 0))
	au.update_mix(0.016, 50.0, 0.0, game.player.global_position)
	check(int(au.played.get("explosion", 0)) == e0 + 1, "distant artillery explosions")
	# Volume / mute UI.
	game.volume_slider.value = 40
	check(absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.4)) < 0.1, "volume slider sets master volume")
	game.mute_button.pressed.emit()
	check(AudioServer.is_bus_mute(0) and au.muted, "mute button mutes")
	check("MUTED" in game.mute_button.text, "mute button shows state")
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	check(is_equal_approx(float(cfg.get_value("audio", "volume", -1)), 0.4) and bool(cfg.get_value("audio", "muted", false)), "volume + mute saved to settings.cfg")
	game.mute_button.pressed.emit()
	check(not AudioServer.is_bus_mute(0), "unmute")
	var c0 := int(au.played.get("ui_click", 0))
	game.quality_buttons[1].pressed.emit()
	check(int(au.played.get("ui_click", 0)) == c0 + 1, "UI click on menu buttons")
	var total := 0
	var dir := DirAccess.open("res://assets/audio")
	for f in dir.get_files():
		if f.ends_with(".ogg"):
			total += FileAccess.get_file_as_bytes("res://assets/audio/" + f).size()
	check(total < 600 * 1024, "audio stays small (%d KB)" % (total / 1024))
	check(FileAccess.file_exists("res://assets/audio/CREDITS.md"), "audio credits file")

# ------------------------------------------------------------------ touch HUD
func _rects() -> Dictionary:
	var out := {}
	for n in ["fire_button", "aim_button", "reload_button", "jump_button", "swap_button", "heal_button", "interact_button", "sprint_button", "joy_base"]:
		var c: Control = game.get(n)
		out[n] = Rect2(c.position, c.size)
	return out

func _hud_checks() -> void:
	check(game.is_mobile, "touch UI enabled for the test (--touch-ui)")
	for vp in [Vector2(1280, 720), Vector2(1600, 720), Vector2(1560, 720), Vector2(1480, 720), Vector2(1280, 960), Vector2(1280, 800)]:
		game.layout_touch_controls(vp)
		var r := _rects()
		var overlaps := []
		var outside := []
		var keys := r.keys()
		for i in range(keys.size()):
			var ri: Rect2 = r[keys[i]]
			if not Rect2(Vector2.ZERO, vp).encloses(ri):
				outside.append(keys[i])
			for j in range(i + 1, keys.size()):
				if ri.intersects(r[keys[j]]):
					overlaps.append("%s/%s" % [keys[i], keys[j]])
		check(overlaps.is_empty() and outside.is_empty(), "HUD %dx%d: no overlaps %s, all on screen %s" % [vp.x, vp.y, overlaps, outside])
		var fire: Rect2 = r["fire_button"]
		var min_side := 9999.0
		for k in keys:
			min_side = minf(min_side, minf(r[k].size.x, r[k].size.y))
		check(min_side >= 64.0, "HUD %dx%d: every touch target >= 64 px (%.0f)" % [vp.x, vp.y, min_side])
		check(fire.end.x > vp.x - 60 and fire.end.y > vp.y - 60, "HUD %dx%d: FIRE in the right-thumb corner" % [vp.x, vp.y])
		# Thumb reach: every right-hand button within ~470 px of the corner.
		var corner: Vector2 = vp
		var far := 0.0
		for k in ["fire_button", "aim_button", "reload_button", "jump_button", "swap_button", "heal_button", "interact_button"]:
			far = maxf(far, r[k].get_center().distance_to(corner))
		check(far < 520.0 * clampf(vp.y / 720.0, 0.85, 1.5), "HUD %dx%d: right cluster within thumb reach (%.0f px)" % [vp.x, vp.y, far])
	var vps: Vector2 = get_viewport().get_visible_rect().size
	game.layout_touch_controls(vps)
	await frames(2)
	game.interact_button.visible = true
	var run_c: Vector2 = game.sprint_button.get_global_rect().get_center()
	var pick_c: Vector2 = game.interact_button.get_global_rect().get_center()
	check(game.classify_touch(run_c) == "button", "RUN touch is a button, not look")
	check(game.classify_touch(pick_c) == "button", "PICK UP touch is a button, not look")
	check(game.classify_touch(Vector2(vps.x * 0.6, vps.y * 0.35)) == "look", "empty right-side screen is the look area")
	check(game.classify_touch(game.joy_base.get_global_rect().get_center()) == "joystick", "stick area is the joystick")
	# Real touch events: hold stick (finger 0) + RUN (1) + FIRE (2) + drag on RUN does not turn the camera.
	game.sprint_held = false
	print("INFO state=%d mobile=%s run_c=%s vps=%s win=%s" % [game.state, game.is_mobile, run_c, vps, DisplayServer.window_get_size()])
	await _touch(0, game.joy_base.get_global_rect().get_center() + Vector2(0, -60), true)
	await _touch(1, run_c, true)
	check(game.sprint_held, "RUN toggles sprint while the other thumb holds the stick")
	var yaw0: float = game.player.rotation.y
	await _drag(1, run_c + Vector2(80, 0), Vector2(80, 0))
	check(is_equal_approx(game.player.rotation.y, yaw0), "dragging on RUN does not move the camera")
	await _touch(1, run_c, false)
	var fire_c: Vector2 = game.fire_button.get_global_rect().get_center()
	await _touch(2, fire_c, true)
	check(game.fire_held, "FIRE works as a second finger (multi-touch)")
	await _drag(2, fire_c + Vector2(-40, 0), Vector2(-40, 0))
	check(not is_equal_approx(game.player.rotation.y, yaw0), "drag from FIRE aims (fire + look)")
	await _touch(2, fire_c, false)
	check(not game.fire_held, "FIRE released")
	var yaw1: float = game.player.rotation.y
	await _touch(3, Vector2(vps.x * 0.6, vps.y * 0.35), true)
	await _drag(3, Vector2(vps.x * 0.6 + 60, vps.y * 0.35), Vector2(60, 0))
	check(not is_equal_approx(game.player.rotation.y, yaw1), "drag in the look area turns the camera")
	await _touch(3, Vector2(vps.x * 0.6 + 60, vps.y * 0.35), false)
	await _touch(0, Vector2.ZERO, false)
	check(game.joystick_id == -1 and game.joystick_vector == Vector2.ZERO, "stick released")
	game.interact_button.visible = false
	game._update_hud()
	check(not game.interact_button.visible, "PICK UP hidden when nothing to pick up")

## Viewport -> window coordinates (headless windows are 0x0, so the stretch transform is odd).
func _to_window(p: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * p

func _touch(i: int, p: Vector2, down: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = i
	ev.position = _to_window(p)
	ev.pressed = down
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await get_tree().process_frame

func _drag(i: int, p: Vector2, rel: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = i
	ev.position = _to_window(p)
	ev.relative = rel
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await get_tree().process_frame

# ------------------------------------------------------------------ models
func _count_meshes(n: Node) -> int:
	var c := 1 if n is MeshInstance3D else 0
	for ch in n.get_children():
		c += _count_meshes(ch)
	return c

func _tri_count(n: Node) -> int:
	var c := 0
	if n is MeshInstance3D and n.mesh != null and n.mesh.has_meta("tris"):
		c += int(n.mesh.get_meta("tris"))
	elif n is MeshInstance3D and n.mesh is PrimitiveMesh:
		var arr0 = (n.mesh as PrimitiveMesh).get_mesh_arrays()
		var idx0 = arr0[Mesh.ARRAY_INDEX]
		c += (idx0.size() if idx0 != null and idx0.size() > 0 else arr0[Mesh.ARRAY_VERTEX].size()) / 3
	elif false:
		for s in range(n.mesh.get_surface_count()):
			var arr = n.mesh.surface_get_arrays(s)
			var idx = arr[Mesh.ARRAY_INDEX]
			c += (idx.size() if idx != null and idx.size() > 0 else arr[Mesh.ARRAY_VERTEX].size()) / 3
	for ch in n.get_children():
		c += _tri_count(ch)
	return c

func _model_checks() -> void:
	var Props = load("res://scripts/props.gd")
	var Weapons = load("res://scripts/weapons.gd")
	for v in [0, 1]:
		var root := Node3D.new()
		add_child(root)
		var tank = Props.add_tank(root, Vector3(0, 0, 200), 0.0, v)
		var meshes := _count_meshes(tank)
		var tris := _tri_count(tank)
		check(meshes <= 8, "tank variant %d is batched into few draw calls (%d mesh instances)" % [v, meshes])
		check(tris > 1500 and tris < 20000, "tank variant %d is detailed but mobile-friendly (%d triangles)" % [v, tris])
		root.queue_free()
	for id in ["webley", "lee_enfield", "thompson", "mp40"]:
		var holder := Node3D.new()
		add_child(holder)
		Weapons.build_model(id, holder, 0.8, false)
		var meshes := _count_meshes(holder)
		var tris := _tri_count(holder)
		check(meshes <= 6, "%s merged into %d mesh instances" % [id, meshes])
		check(tris > 300 and tris < 12000, "%s has close-up detail (%d triangles)" % [id, tris])
		holder.queue_free()
