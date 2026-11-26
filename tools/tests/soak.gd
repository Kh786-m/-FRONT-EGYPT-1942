extends Node
## Full-match soak: 4x time scale, player parked in the zone centre, records physics cost and
## AI health (stuck / wedged soldiers). Works on both v0.4.0 and v0.5.0. Usage: -- --tag=NAME
var game
var f := 0
var tag := "after"
var samples: PackedFloat32Array = []
var last_pos := {}
var still := {}
var wedged_max := 0
var t0 := 0
var stuck_seen := {}
var repath_seen := {}

func _ready():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="): tag = a.substr(6)
	seed(1942)
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	game._start_hero_mission()
	# Run with --fixed-fps 60: one physics step per frame, unthrottled, so the physics
	# monitor is a clean per-step cost.
	Engine.physics_ticks_per_second = 60
	t0 = Time.get_ticks_msec()

func _physics_process(_d):
	f += 1
	samples.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	if game.state == game.GameState.PLAYING:
		game.health = 100.0
		game.player.global_position = Vector3(game.zone.center.x, 0.5 + 2.0, game.zone.center.y)
	# A soldier is "wedged" if it wanted to move for 10 s of game time but stayed within 1 m.
	if f % 60 == 0:
		for e in game.enemies:
			if is_instance_valid(e) and "stuck_events" in e:
				stuck_seen[e.get_instance_id()] = e.stuck_events
				repath_seen[e.get_instance_id()] = e.repaths
	if f % 600 == 0:
		var w := 0
		for e in game.enemies:
			if not is_instance_valid(e):
				continue
			var p: Vector3 = e.global_position
			if last_pos.has(e) and Vector2(p.x - last_pos[e].x, p.z - last_pos[e].z).length() < 1.0 and e.velocity.length() > 0.5:
				still[e] = int(still.get(e, 0)) + 1
				w += 1
			else:
				still[e] = 0
			last_pos[e] = p
		wedged_max = maxi(wedged_max, w)
	if f % 1800 == 0:
		print("t=%ds phase=%d r=%.1f alive=%d zone_kills=%d wedged_now=%d" % [int(game.mission_time), game.zone.phase_number(), game.zone.radius, game.enemies.size(), game.zone_kills, _wedged_now()])
	if f > 40000 or game.state == game.GameState.WON:
		var sorted := samples.duplicate()
		sorted.sort()
		var avg := 0.0
		for s in samples:
			avg += s
		avg /= maxf(1.0, samples.size())
		var stuck := 0
		var repaths := 0
		for k in stuck_seen.keys():
			stuck += int(stuck_seen[k])
			repaths += int(repath_seen[k])
		print("SOAK tag=%s game_time=%ds state=%d enemies_left=%d zone_kills=%d frames=%d avg_physics_ms=%.3f p99_physics_ms=%.3f max_physics_ms=%.3f wedged_max=%d stuck_events=%d repaths=%d wall_s=%.1f" % [tag, int(game.mission_time), game.state, game.enemies.size(), game.zone_kills, samples.size(), avg, sorted[int(sorted.size() * 0.99)], sorted[sorted.size() - 1], wedged_max, stuck, repaths, (Time.get_ticks_msec() - t0) / 1000.0])
		get_tree().quit()

func _wedged_now() -> int:
	var n := 0
	for e in still.keys():
		if is_instance_valid(e) and int(still[e]) > 0:
			n += 1
	return n
