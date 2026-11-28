extends Node
## Two-player screenshots (run two real-display instances):  -- --role=host|client --out=DIR
var game
var net
var role := "host"
var out := "/workspace/haraq-shots-v7"
const T := preload("res://scripts/terrain.gd")

func frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func secs(s: float) -> void:
	await get_tree().create_timer(s).timeout

func until(cond: Callable, limit: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) / 1000.0 < limit:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()

func _save(n: String) -> void:
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, n])
	print("saved ", n)

func _look(from: Vector3, target: Vector3) -> void:
	game.player.global_position = Vector3(from.x, T.height(from.x, from.z) + 0.05, from.z)
	game.player.velocity = Vector3.ZERO
	var eye: Vector3 = game.player.global_position + Vector3(0, 1.62, 0)
	var d: Vector3 = target - eye
	game.player.rotation.y = atan2(-d.x, -d.z)
	game.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())

func _ready():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="): role = a.substr(7)
		if a.begins_with("--out="): out = a.substr(6)
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	net = game.net
	await frames(20)
	game.open_lan_panel()
	if role == "host":
		net.host("خالد")
		await until(func(): return net.players.size() >= 2, 60.0)
		await secs(1.5)
		await _save("lobby_host")
		net.start_match()
		var cid: int = net.players.keys().filter(func(k): return k != 1)[0]
		await secs(1.0)
		for e in game.enemies:
			e.set_physics_process(false)
			e.global_position = Vector3(-70 + randf() * 8.0, T.height(-70, -70) + 0.1, -70 + randf() * 8.0)
		game.zone.timer = 9999.0
		# Stand 5 m in front of the client, facing it; hold a rifle.
		var sp: Vector3 = net.spawns[cid]
		game.give_weapon("lee_enfield")
		_look(sp + Vector3(2.2, 0, -5.5), sp + Vector3(0, 1.3, 0))
		game.health = 100.0
		await secs(14.0)
		await _save("match_host_view")
		await secs(8.0)
	else:
		var f: bool = await until(func(): return not net.hosts.is_empty(), 30.0)
		await secs(1.0)
		await _save("lobby_client_browse")
		net.join(net.hosts.keys()[0], "Tommy")
		await until(func(): return net.in_match, 60.0)
		await secs(3.0)
		game.give_weapon("thompson") if false else null
		await secs(3.0)
		var host_rig = net.puppets["p1"]["rig"]
		var hp: Vector3 = host_rig.global_position
		var me: Vector3 = game.player.global_position
		_look(me, hp + Vector3(0, 1.2, 0))
		await secs(2.0)
		await _save("match_client_view")
		await secs(12.0)
	net.leave()
	get_tree().quit()
