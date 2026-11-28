extends Node
## HARAQ v0.7 LAN multiplayer test: two headless game instances on this machine run a mini
## match through real ENet + UDP discovery.
##   godot --headless --path proj res://test_net.tscn -- --role=host
##   godot --headless --path proj res://test_net.tscn -- --role=client
## (tools/tests/run_net_test.sh starts both and sums the results.)
var game
var net
var role := "host"
var fails := 0
var passes := 0
const T := preload("res://scripts/terrain.gd")

func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
		print("PASS [%s] %s" % [role, msg])
	else:
		fails += 1
		print("FAIL [%s] %s" % [role, msg])

func frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame

func secs(s: float) -> void:
	await get_tree().create_timer(s).timeout

## Wait (up to `limit` seconds) until cond.call() is true.
func until(cond: Callable, limit: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) / 1000.0 < limit:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()

func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _ready():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.substr(7)
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	net = game.net
	await frames(5)
	if role == "host":
		await _host()
	else:
		await _client()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	print("RESULT role=%s passes=%d fails=%d stats=%s" % [role, passes, fails, net.stats])
	await secs(1.0)
	net.leave()
	get_tree().quit(1 if fails > 0 else 0)

# ------------------------------------------------------------------ host
func _aim_at(from: Vector3, target: Vector3) -> void:
	game.player.global_position = from
	game.player.velocity = Vector3.ZERO
	var eye: Vector3 = from + Vector3(0, 1.62, 0)
	var d := target - eye
	game.player.rotation.y = atan2(-d.x, -d.z)
	game.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())

func _host() -> void:
	game.open_lan_panel()
	check(game.lan_panel.visible and game.lan_panel.get_node_or_null("VBoxContainer") != null or game.lan_panel.visible, "LAN lobby panel opens from the menu")
	check(net.host("Host") == OK and net.is_server(), "ENet server listening on UDP %d" % net.PORT)
	await secs(1.2)
	check(net.stats["broadcasts"] >= 1, "host announces itself by UDP broadcast (%d)" % net.stats["broadcasts"])
	var joined: bool = await until(func(): return net.players.size() >= 2, 45.0)
	check(joined, "client joined the lobby (%s)" % [net.players.values()])
	if not joined:
		return
	check(game.lan_start.visible and not game.lan_start.disabled, "host sees START once 2 players are in")
	await secs(0.5)
	check(net.start_match(), "host starts the match")
	await frames(3)
	var cid: int = net.players.keys().filter(func(k): return k != 1)[0]
	var av = net.avatars.get(cid)
	check(av != null and is_instance_valid(av), "server-side body created for the client")
	check(game.enemies.size() == net.bot_count() and game.enemies.size() == game.ENEMY_COUNT - 1, "bots trimmed for 2 players (%d bots)" % game.enemies.size())
	check(game.state == game.GameState.PLAYING, "host is playing")
	# Keep the test calm: park the bots far away, frozen; one static target in front of the client.
	var spawn: Vector3 = net.spawns[cid]
	var target_bot = game.enemies[0]
	for e in game.enemies:
		e.set_physics_process(false)
		if e != target_bot:
			e.global_position = Vector3(-70 + randf() * 8.0, T.height(-70, -70) + 0.1, -70 + randf() * 8.0)
	var zone = game.zone
	zone.shrinking = false
	zone.timer = 9999.0
	var bp: Vector3 = game.nav.nearest_free_point(spawn + Vector3(0, 0, -7))
	target_bot.global_position = Vector3(bp.x, T.height(bp.x, bp.z) + 0.05, bp.z)
	target_bot.rotation.y = 0.0
	# 1) Movement: the host walks sideways while the client walks forward.
	game.joystick_vector = Vector2(1, 0)
	var moved: bool = await until(func(): return flat(av.global_position, spawn) > 2.5, 15.0)
	game.joystick_vector = Vector2.ZERO
	check(moved, "client's inputs move its body on the host (%.1f m, server-authoritative)" % flat(av.global_position, spawn))
	check(net.stats["inputs_got"] > 20, "input packets received (%d)" % net.stats["inputs_got"])
	# Wait until the client stands still, then shoot it.
	await until(func(): return Vector2(av.velocity.x, av.velocity.z).length() < 0.1, 8.0)
	await secs(0.6)
	var hp0: float = av.hit_points
	var shot_ok := false
	for i in range(4):
		var off := Vector3(5, 0, 0).rotated(Vector3.UP, i * PI / 2.0)
		var from: Vector3 = game.nav.nearest_free_point(av.global_position + off)
		from.y = T.height(from.x, from.z) + 0.05
		if not game.nav.line_clear(from, av.global_position):
			continue
		_aim_at(from, av.global_position + Vector3(0, 1.0, 0))
		await frames(2)
		game.cooldown = 0.0
		game.trigger_released = true
		game.mag_ammo["webley"] = 6
		game._shoot()
		await frames(2)
		if av.hit_points < hp0:
			shot_ok = true
			break
	check(shot_ok, "host's bullet hits the client's body (hp %.0f -> %.0f)" % [hp0, av.hit_points])
	game.player.global_position = Vector3(-60, T.height(-60, 40) + 0.1, 40)
	# 2) The client shoots the bot: validated + traced on the host.
	var bot_dead: bool = await until(func(): return not is_instance_valid(target_bot) or target_bot.hit_points <= 0.0, 25.0)
	check(bot_dead, "client's shots (traced by the host) killed the bot")
	check(net.stats["shots_validated"] >= 1, "client shots validated by the host (%d ok, %d rejected)" % [net.stats["shots_validated"], net.stats["shots_rejected"]])
	var fed := false
	for k in game.kill_feed_entries:
		if str(k["text"]).contains(net.players[cid]):
			fed = true
	check(fed, "kill feed credits the client by name")
	await secs(1.0)
	# 3) Loot: a crate next to the client — host locks + grants it, client takes armour/medkit.
	var cp: Vector3 = av.global_position + Vector3(0.6, 0, 0.3)
	var crate = game._spawn_crate(cp, {"weapon": "", "ammo": {"smg": 30}, "medkits": 1, "armor": 40.0}, true)
	var looted: bool = await until(func(): return not is_instance_valid(crate) or crate.is_queued_for_deletion(), 15.0)
	check(looted, "client picked up the crate (host removed it)")
	check(av.armor >= 39.0 and av.medkits == 1, "host tracks the client's armour/medkits from the loot (%.0f / %d)" % [av.armor, av.medkits])
	check(net.stats["loot_grants"] >= 1, "loot granted through the host lock (%d)" % net.stats["loot_grants"])
	# 4) Zone: host moves the circle; the client must follow.
	zone.center = Vector2(5, 5)
	zone.radius = 60.0
	zone.target_center = Vector2(5, 5)
	zone.target_radius = 60.0
	zone._update_visuals()
	await secs(3.0)
	# 5) End: all bots down, then the client — the host is the last one standing.
	for e in game.enemies.duplicate():
		if is_instance_valid(e):
			e.take_hit_from(999.0, game.player)
	await frames(5)
	check(game.state == game.GameState.PLAYING and not net.match_over, "match continues while 2 humans are alive")
	av.take_hit_from(999.0, game.player)
	await frames(5)
	check(net.match_over and net.winner_peer == 1, "match over: host wins as last one standing")
	check(game.state == game.GameState.WON, "host shows the victory screen")
	await secs(2.0)

# ------------------------------------------------------------------ client
func _client() -> void:
	game.open_lan_panel()
	var found: bool = await until(func(): return not net.hosts.is_empty(), 20.0)
	check(found, "host discovered by UDP broadcast (%s)" % [net.hosts.keys()])
	if not found:
		return
	check(game.lan_hosts.get_child_count() >= 1, "lobby lists the discovered game")
	var ip: String = net.hosts.keys()[0]
	check(net.join("not-an-ip", "x") != OK, "bad manual IP is rejected")
	check(net.join(ip, "Client") == OK, "joining %s" % ip)
	var in_lobby: bool = await until(func(): return net.players.size() >= 2, 20.0)
	check(in_lobby, "connected; lobby shows %s" % [net.players.values()])
	var started: bool = await until(func(): return net.in_match and game.state == game.GameState.PLAYING, 40.0)
	check(started, "match started on the client")
	if not started:
		return
	await secs(1.0)
	check(game.enemies.is_empty(), "client runs no bots of its own (host owns them)")
	check(net.crates_by_id.size() >= 20, "crates mirrored from the host (%d)" % net.crates_by_id.size())
	var bots: int = net.puppets.keys().filter(func(k): return k.begins_with("b")).size()
	check(bots >= 15, "bot puppets drawn from snapshots (%d)" % bots)
	check(net.puppets.has("p1"), "host player visible as an animated soldier")
	check(net.stats["snapshots_got"] > 10, "snapshots arriving (%d)" % net.stats["snapshots_got"])
	# 1) Walk forward ~2.5 s (prediction) while watching the host's puppet glide (interpolation).
	var start_pos: Vector3 = game.player.global_position
	var host_rig = net.puppets["p1"]["rig"]
	var host_start: Vector3 = host_rig.global_position
	var max_jump := 0.0
	var prev: Vector3 = host_rig.global_position
	game.joystick_vector = Vector2(0, -0.7)
	for i in range(150):
		await get_tree().process_frame
		if is_instance_valid(host_rig):
			max_jump = maxf(max_jump, host_rig.global_position.distance_to(prev))
			prev = host_rig.global_position
	game.joystick_vector = Vector2.ZERO
	check(flat(game.player.global_position, start_pos) > 2.5, "client moves immediately (prediction, %.1f m)" % flat(game.player.global_position, start_pos))
	await secs(1.2)
	check(net.reconcile_error < 0.35, "client and host agree on the client's position (error %.2f m)" % net.reconcile_error)
	if is_instance_valid(host_rig):
		var host_moved := flat(host_rig.global_position, host_start)
		check(host_moved > 1.5 and max_jump < 0.6, "host puppet moves smoothly (%.1f m, biggest step per frame %.2f m)" % [host_moved, max_jump])
	# 2) Get shot by the host.
	var hurt: bool = await until(func(): return game.health < 100.0, 20.0)
	check(hurt, "host's hit reaches the client's health (%.0f HP)" % game.health)
	# 3) Shoot the nearest bot until the host says it is dead.
	var key := ""
	var best := 1e9
	for k in net.puppets:
		if k.begins_with("b"):
			var d := flat(net.puppets[k]["rig"].global_position, game.player.global_position)
			if d < best:
				best = d
				key = k
	check(key != "" and best < 15.0, "bot target nearby (%s at %.1f m)" % [key, best])
	var killed := false
	for i in range(14):
		if not net.puppets.has(key):
			killed = true
			break
		var bpos: Vector3 = net.puppets[key]["rig"].global_position + Vector3(0, 1.1, 0)
		var eye: Vector3 = game.player.global_position + Vector3(0, 1.62, 0)
		var d := bpos - eye
		game.player.rotation.y = atan2(-d.x, -d.z)
		game.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())
		await frames(2)
		game.cooldown = 0.0
		game.trigger_released = true
		game.reload_timer = 0.0
		game.mag_ammo[game.current_weapon()] = 6
		game._shoot()
		await secs(0.45)
	if not killed:
		killed = await until(func(): return not net.puppets.has(key), 3.0)
	check(killed, "client killed the bot (puppet removed after host confirmation)")
	var fed: bool = await until(func():
		for k in game.kill_feed_entries:
			if str(k["text"]).contains("Client"):
				return true
		return false, 4.0)
	check(fed, "kill feed received from the host")
	# 4) Loot: the host drops a crate at our feet.
	var looted: bool = await until(func(): return game.armor >= 39.0 and game.medkits == 1, 20.0)
	check(looted, "crate loot applied (armour %.0f, medkits %d)" % [game.armor, game.medkits])
	# 5) Zone follows the host.
	var zsync: bool = await until(func(): return game.zone.center.distance_to(Vector2(5, 5)) < 0.1 and absf(game.zone.radius - 60.0) < 0.1, 12.0)
	check(zsync, "zone state synced from the host (centre %s, r %.1f)" % [game.zone.center, game.zone.radius])
	# 6) Death + match over.
	var died: bool = await until(func(): return net.my_dead and game.state == game.GameState.DEAD, 20.0)
	check(died, "client gets its death from the host (end screen)")
	var over: bool = await until(func(): return net.match_over, 10.0)
	check(over and net.winner_name == "Host", "client told the match is over (winner %s)" % net.winner_name)
