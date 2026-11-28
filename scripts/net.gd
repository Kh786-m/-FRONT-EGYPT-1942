extends Node
## HARAQ LAN multiplayer, first version (v0.7).
##
## * Host / join on the same Wi-Fi with ENetMultiplayerPeer (UDP port 24942). Hosts announce
##   themselves with a UDP broadcast on port 24943 every second; clients list them, or type the
##   host's IP by hand.
## * 2–8 players plus bots. The HOST runs the whole match (server-authoritative): bots, zone,
##   loot crates, damage and kills. Clients send their inputs (movement, look, jump, aim,
##   weapon) ~30 times a second and fire requests; the host moves each client's body itself
##   and validates every shot with its own raycast.
## * The host sends snapshots 20 times a second. Clients predict their own movement and
##   reconcile with the host's position; everything else (other players, bots) is drawn
##   100 ms in the past and interpolated between snapshots.
## * Loot: crates exist on the host; a client asks to open a crate, the host locks it and
##   grants its contents, the client reports what is left. Armour, medkits and health are
##   tracked by the host. (Weapons/ammo in hand are tracked by each client — first version.)

const Rig := preload("res://scripts/soldier_rig.gd")
const Avatar := preload("res://scripts/net_avatar.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Fx := preload("res://scripts/fx.gd")
const G := preload("res://scripts/graphics.gd")
const Terrain := preload("res://scripts/terrain.gd")
const AudioScript := preload("res://scripts/audio.gd")

const PORT := 24942
const DISCOVERY_PORT := 24943
const MAX_PLAYERS := 8
const SNAP_INTERVAL := 0.05
const INPUT_INTERVAL := 1.0 / 30.0
const CRATE_SYNC_INTERVAL := 0.2
const INTERP_DELAY := 0.1
const GAME_TAG := "HARAQ"
const VERSION := "0.7.0"
const WEAPON_IDS := ["", "webley", "lee_enfield", "thompson", "mp40"]

signal lobby_changed
signal hosts_changed
signal status_changed(text: String)

var game: Node
var mode := "" ## "", "host" or "client"
var my_name := "خالد"
var players := {} ## peer id -> name
var in_match := false
var match_over := false
var winner_name := ""
var winner_peer := 0
var status := ""
var hosts := {} ## ip -> {"name", "players", "port", "seen", "state"}
var stats := {"broadcasts": 0, "snapshots_sent": 0, "snapshots_got": 0, "inputs_sent": 0, "inputs_got": 0, "shots_validated": 0, "shots_rejected": 0, "loot_grants": 0}

var _bcast: PacketPeerUDP
var _listen: PacketPeerUDP
var _bcast_timer := 0.0
var _clock := 0.0
# ---- host side
var avatars := {} ## peer -> Avatar
var spawns := {} ## peer -> Vector3
var _snap_timer := 0.0
var _crate_timer := 0.0
var _crate_seq := 0
var _crate_known := {} ## nid -> var_to_str(contents)
var _loot_locks := {} ## nid -> {"peer", "t", "before"}
var _bot_seq := 0
# ---- client side
var puppets := {} ## key ("p<peer>" / "b<nid>") -> {"rig", "buf", "weapon", "dead"}
var crates_by_id := {}
var spawning_from_server := false
var remote_alive := 0
var my_dead := false
var last_ack := -1
var reconcile_error := 0.0
var _seq := 0
var _pending: Array = [] ## [seq, vx, vz]
var _outbox: Array = []
var _input_timer := 0.0
var _server_t := 0.0
var _server_t_local := 0.0
var _loot_asked := {} ## nid -> local time
var _jump_flag := false
var _uniform: Material
var _helmet: Material


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_active() -> bool:
	return mode != ""


func is_server() -> bool:
	return mode == "host"


func is_client() -> bool:
	return mode == "client"


func my_id() -> int:
	return multiplayer.get_unique_id() if mode != "" else 1


func _set_status(t: String) -> void:
	status = t
	status_changed.emit(t)


func _mats() -> void:
	if _uniform == null:
		_uniform = G.pbr("linen", Color(0.74, 0.66, 0.48), 3.0, true, 0.95, 0.0, 0.9, false)
		_helmet = G.pbr("metal_rust", Color(0.56, 0.52, 0.4), 3.0, true, 0.6, 0.3, 0.5, false)


# ------------------------------------------------------------------ host / join / leave
func host(p_name := "") -> int:
	leave()
	if p_name != "":
		my_name = p_name
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		_set_status("مش قادر أفتح السيرفر (البورت %d مشغول؟)" % PORT)
		return err
	multiplayer.multiplayer_peer = peer
	mode = "host"
	stop_discovery() # a host announces, it does not browse (and frees the port for same-machine tests)
	players = {1: my_name}
	_bcast = PacketPeerUDP.new()
	_bcast.set_broadcast_enabled(true)
	_set_status("مستضيف — مستني لاعبين على نفس الواي فاي  (%s)" % ", ".join(local_ips()))
	lobby_changed.emit()
	return OK


func join(ip: String, p_name := "") -> int:
	leave()
	if p_name != "":
		my_name = p_name
	ip = ip.strip_edges()
	if not ip.is_valid_ip_address():
		_set_status("عنوان IP مش صحيح: %s" % ip)
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		_set_status("مش قادر أوصل لـ %s" % ip)
		return err
	multiplayer.multiplayer_peer = peer
	mode = "client"
	_set_status("بيتصل بـ %s ..." % ip)
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = ""
	players.clear()
	in_match = false
	_bcast = null
	lobby_changed.emit()


## Start listening for host announcements (lobby "browse" view).
func start_discovery() -> void:
	if _listen != null:
		return
	_listen = PacketPeerUDP.new()
	if _listen.bind(DISCOVERY_PORT) != OK:
		_listen = null
		_set_status("مش قادر أدوّر على ألعاب (بورت %d مشغول)" % DISCOVERY_PORT)


func stop_discovery() -> void:
	if _listen != null:
		_listen.close()
	_listen = null


static func local_ips() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


func _broadcast() -> void:
	if _bcast == null:
		return
	var msg := JSON.stringify({"g": GAME_TAG, "v": VERSION, "name": my_name, "port": PORT, "players": players.size(), "max": MAX_PLAYERS, "state": "playing" if in_match else "lobby"}).to_utf8_buffer()
	var targets := ["255.255.255.255", "127.0.0.1"]
	for ip in local_ips():
		var p := ip.split(".")
		targets.append("%s.%s.%s.255" % [p[0], p[1], p[2]])
	for t in targets:
		_bcast.set_dest_address(t, DISCOVERY_PORT)
		_bcast.put_packet(msg)
	stats["broadcasts"] += 1


func _poll_discovery() -> void:
	if _listen == null:
		return
	var changed := false
	while _listen.get_available_packet_count() > 0:
		var pkt := _listen.get_packet()
		var ip := _listen.get_packet_ip()
		var d = JSON.parse_string(pkt.get_string_from_utf8())
		if typeof(d) != TYPE_DICTIONARY or d.get("g", "") != GAME_TAG:
			continue
		hosts[ip] = {"name": str(d.get("name", "?")), "players": int(d.get("players", 1)), "max": int(d.get("max", MAX_PLAYERS)), "port": int(d.get("port", PORT)), "state": str(d.get("state", "lobby")), "seen": _clock}
		changed = true
	for ip in hosts.keys():
		if _clock - float(hosts[ip]["seen"]) > 4.0:
			hosts.erase(ip)
			changed = true
	if changed:
		hosts_changed.emit()


func _process(delta: float) -> void:
	_clock += delta
	_poll_discovery()
	if is_server():
		_bcast_timer -= delta
		if _bcast_timer <= 0.0:
			_bcast_timer = 1.0
			_broadcast()
	if is_client() and in_match:
		_update_puppets()


# ------------------------------------------------------------------ connection events
func _on_peer_connected(id: int) -> void:
	if is_server() and in_match:
		# First version: no joining a match already in progress.
		multiplayer.multiplayer_peer.disconnect_peer(id)


func _on_peer_disconnected(id: int) -> void:
	if not is_server():
		return
	players.erase(id)
	if avatars.has(id):
		var a = avatars[id]
		if is_instance_valid(a) and not a.dead:
			a.take_zone_damage(9999.0)
		avatars.erase(id)
	_rpc_lobby()


func _on_connected() -> void:
	_hello.rpc_id(1, my_name, VERSION)
	_set_status("اتصلت — مستني المستضيف يبدأ")


func _on_connection_failed() -> void:
	_set_status("الاتصال فشل")
	leave()


func _on_server_disconnected() -> void:
	_set_status("المستضيف قفل اللعبة")
	var was := in_match
	leave()
	if was and game != null and game.state == game.GameState.PLAYING:
		game._end_mission(false)


@rpc("any_peer", "reliable")
func _hello(p_name: String, version: String) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if version != VERSION or players.size() >= MAX_PLAYERS or in_match:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	players[id] = p_name.substr(0, 16) if p_name.strip_edges() != "" else "لاعب %d" % players.size()
	_rpc_lobby()


func _rpc_lobby() -> void:
	_lobby.rpc(players)
	lobby_changed.emit()
	_set_status("مستضيف — %d/%d لاعبين" % [players.size(), MAX_PLAYERS])


@rpc("authority", "reliable")
func _lobby(p: Dictionary) -> void:
	players = p
	lobby_changed.emit()
	_set_status("في اللوبي — %d لاعبين، مستني المستضيف" % players.size())


# ------------------------------------------------------------------ match start
func bot_count() -> int:
	return clampi(game.ENEMY_COUNT - (players.size() - 1), 8, game.ENEMY_COUNT)


func start_match() -> bool:
	if not is_server() or in_match:
		return false
	var ids := players.keys()
	ids.sort()
	spawns.clear()
	for i in range(ids.size()):
		var a := TAU * float(i) / float(ids.size()) + 0.3
		var p := Vector3(sin(a) * 9.0, 0.0, 12.0 + cos(a) * 9.0)
		if game.nav != null:
			p = game.nav.nearest_free_point(p)
		p.y = Terrain.height(p.x, p.z) + 0.1
		spawns[ids[i]] = p
	# Fewer bots when more humans join (2 players -> 19 bots ... 8 players -> 13).
	var keep := bot_count()
	while game.enemies.size() > keep:
		var e = game.enemies.pop_back()
		e.queue_free()
	for e in game.enemies:
		_bot_seq += 1
		e.set_meta("nid", _bot_seq)
	in_match = true
	match_over = false
	_crate_known.clear()
	_match_start.rpc(players, spawns)
	_begin_match()
	return true


@rpc("authority", "reliable")
func _match_start(p: Dictionary, sp: Dictionary) -> void:
	players = p
	spawns = sp
	in_match = true
	match_over = false
	my_dead = false
	# The host owns bots and crates: drop the local ones, mirrors arrive with the snapshots.
	for e in game.enemies:
		e.queue_free()
	game.enemies.clear()
	for c in game.loot_crates:
		if is_instance_valid(c):
			c.queue_free()
	game.loot_crates.clear()
	crates_by_id.clear()
	_begin_match()


func _begin_match() -> void:
	_mats()
	var me := my_id()
	if spawns.has(me):
		game.player.global_position = spawns[me]
		game.player.velocity = Vector3.ZERO
	if is_server():
		var ids := players.keys()
		ids.sort()
		for id in ids:
			if id == 1:
				continue
			var a = Avatar.new()
			game.add_child(a)
			a.game = game
			a.setup(id, players[id], int(id) % 2, _uniform, _helmet)
			a.global_position = spawns[id]
			a.died.connect(_on_avatar_died)
			avatars[id] = a
	if game.state != game.GameState.PLAYING:
		game._start_hero_mission()
	lobby_changed.emit()


# ------------------------------------------------------------------ host: per-tick work
func physics_tick(delta: float) -> void:
	if not in_match:
		return
	if is_server():
		_server_tick(delta)
	elif is_client():
		_client_tick(delta)


func _server_tick(delta: float) -> void:
	var zone = game.zone
	var dps: float = zone.damage_per_second()
	for id in avatars:
		var a = avatars[id]
		if not is_instance_valid(a) or a.dead:
			continue
		a.step(delta, WEAPON_IDS)
		if not match_over and not zone.is_inside(a.global_position):
			a.take_zone_damage(dps * delta)
	_crate_timer -= delta
	if _crate_timer <= 0.0:
		_crate_timer = CRATE_SYNC_INTERVAL
		_sync_crates()
	_snap_timer -= delta
	if _snap_timer <= 0.0:
		_snap_timer = SNAP_INTERVAL
		_send_snapshot()
	if not match_over:
		_check_match_over()


func alive_total() -> int:
	var n: int = game.enemies.size() + (1 if game.player_active() else 0)
	for id in avatars:
		if is_instance_valid(avatars[id]) and not avatars[id].dead:
			n += 1
	return n


func alive_humans() -> Array:
	var out := []
	if game.player_active():
		out.append(1)
	for id in avatars:
		if is_instance_valid(avatars[id]) and not avatars[id].dead:
			out.append(id)
	return out


func _check_match_over() -> void:
	if alive_total() > 1:
		return
	var humans := alive_humans()
	var wp: int = humans[0] if humans.size() == 1 else 0
	var wn: String = players.get(wp, "") if wp != 0 else (game.enemies[0].callsign if game.enemies.size() == 1 else "")
	_match_over.rpc(wn, wp)
	_match_over(wn, wp)


@rpc("authority", "reliable")
func _match_over(wn: String, wp: int) -> void:
	match_over = true
	winner_name = wn
	winner_peer = wp
	if game.state == game.GameState.PLAYING:
		game._end_mission(wp == my_id())


func _quant(v: float) -> float:
	return snappedf(v, 0.001)


func _send_snapshot() -> void:
	var pl := []
	for id in players:
		if id == 1:
			var p: CharacterBody3D = game.player
			var hv := Vector2(p.velocity.x, p.velocity.z).length()
			pl.append([1, p.global_position, p.rotation.y, game.head.rotation.x, hv, game.aiming, WEAPON_IDS.find(game.current_weapon()), game.health, game.armor, game.medkits, game.player_active(), -1, game.score])
		elif avatars.has(id) and is_instance_valid(avatars[id]):
			var a = avatars[id]
			pl.append([id, a.global_position, a.yaw, a.pitch, Vector2(a.velocity.x, a.velocity.z).length(), a.aiming, WEAPON_IDS.find(a.weapon), a.hit_points, a.armor, a.medkits, not a.dead, a.last_seq, a.kills])
	var bots := PackedFloat32Array()
	for e in game.enemies:
		if not is_instance_valid(e) or not e.has_meta("nid"):
			continue
		var aim: bool = e.state == e.State.ATTACK or (e.state == e.State.COVER and e._cover_phase == 2)
		bots.append_array(PackedFloat32Array([e.get_meta("nid"), e.global_position.x, e.global_position.y, e.global_position.z, e.rotation.y, Vector2(e.velocity.x, e.velocity.z).length(), 1.0 if aim else 0.0, WEAPON_IDS.find(e.weapon), e.rig_variant]))
	var z = game.zone
	var zs := [z.center, z.radius, z.target_center, z.target_radius, z.shrinking, z.timer, z.phase, z.finished]
	_snap.rpc([game.mission_time, pl, bots, zs, alive_total()])
	stats["snapshots_sent"] += 1


# ------------------------------------------------------------------ host: crates
func _sync_crates() -> void:
	var seen := {}
	for c in game.loot_crates:
		if not is_instance_valid(c) or c.is_queued_for_deletion():
			continue
		if not c.has_meta("nid"):
			_crate_seq += 1
			c.set_meta("nid", _crate_seq)
		var nid: int = c.get_meta("nid")
		seen[nid] = true
		var s := var_to_str(c.contents)
		if not _crate_known.has(nid):
			_crate_known[nid] = s
			_crate_spawn.rpc(nid, c.global_position, c.rotation.y, c.contents, bool(c.get_meta("small", false)))
		elif _crate_known[nid] != s:
			_crate_known[nid] = s
			_crate_set.rpc(nid, c.contents)
	for nid in _crate_known.keys():
		if not seen.has(nid):
			_crate_known.erase(nid)
			_crate_remove.rpc(nid)


func _crate_by_nid(nid: int) -> Node3D:
	for c in game.loot_crates:
		if is_instance_valid(c) and c.has_meta("nid") and int(c.get_meta("nid")) == nid:
			return c
	return null


@rpc("authority", "reliable")
func _crate_spawn(nid: int, pos: Vector3, rot: float, contents: Dictionary, small: bool) -> void:
	if crates_by_id.has(nid) and is_instance_valid(crates_by_id[nid]):
		return
	spawning_from_server = true
	var c = game._spawn_crate(pos, contents, small)
	spawning_from_server = false
	c.global_position = pos
	c.rotation.y = rot
	c.set_meta("nid", nid)
	crates_by_id[nid] = c


@rpc("authority", "reliable")
func _crate_set(nid: int, contents: Dictionary) -> void:
	var c = crates_by_id.get(nid)
	if c == null or not is_instance_valid(c):
		return
	var w_new: String = contents.get("weapon", "")
	if w_new != c.contents.get("weapon", ""):
		if w_new == "":
			c.take_weapon()
		else:
			c.put_weapon(w_new)
	c.contents = contents.duplicate(true)
	c.refresh_label()


@rpc("authority", "reliable")
func _crate_remove(nid: int) -> void:
	var c = crates_by_id.get(nid)
	crates_by_id.erase(nid)
	if c != null and is_instance_valid(c):
		game.loot_crates.erase(c)
		if game.nearby_crate == c:
			game.nearby_crate = null
		c.queue_free()


# ---- loot handshake
## Client: a crate is in reach — ask the host for it (throttled per crate).
func request_loot(crate: Node3D, interact: bool) -> void:
	if not crate.has_meta("nid") or my_dead:
		return
	var nid: int = crate.get_meta("nid")
	if not interact and _clock - float(_loot_asked.get(nid, -9.0)) < 0.6:
		return
	_loot_asked[nid] = _clock
	_req_loot.rpc_id(1, nid, interact)


@rpc("any_peer", "reliable")
func _req_loot(nid: int, interact: bool) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var a = avatars.get(id)
	var c := _crate_by_nid(nid)
	if a == null or a.dead or c == null:
		return
	var lock = _loot_locks.get(nid)
	if lock != null and _clock - float(lock["t"]) < 2.0:
		return
	var d := Vector2(c.global_position.x - a.global_position.x, c.global_position.z - a.global_position.z).length()
	if d > c.PICKUP_RADIUS + 1.5:
		return
	_loot_locks[nid] = {"peer": id, "t": _clock, "before": c.contents.duplicate(true)}
	stats["loot_grants"] += 1
	_grant_loot.rpc_id(id, nid, c.contents, interact)


@rpc("authority", "reliable")
func _grant_loot(nid: int, contents: Dictionary, interact: bool) -> void:
	var c = crates_by_id.get(nid)
	if c == null or not is_instance_valid(c):
		_loot_done.rpc_id(1, nid, contents)
		return
	c.contents = contents.duplicate(true)
	c.set_meta("granted", true)
	game._collect_from(c, interact)
	var left: Dictionary = {}
	if is_instance_valid(c) and not c.is_queued_for_deletion():
		c.remove_meta("granted")
		left = c.contents
	_loot_done.rpc_id(1, nid, left)


@rpc("any_peer", "reliable")
func _loot_done(nid: int, left: Dictionary) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var lock = _loot_locks.get(nid)
	if lock == null or int(lock["peer"]) != id:
		return
	_loot_locks.erase(nid)
	var c := _crate_by_nid(nid)
	var a = avatars.get(id)
	if c == null or a == null:
		return
	var before: Dictionary = lock["before"]
	a.armor = minf(game.MAX_ARMOR, a.armor + maxf(0.0, float(before.get("armor", 0.0)) - float(left.get("armor", 0.0))))
	a.medkits = mini(game.MAX_MEDKITS, a.medkits + maxi(0, int(before.get("medkits", 0)) - int(left.get("medkits", 0))))
	var w_left: String = left.get("weapon", "")
	if w_left != c.contents.get("weapon", ""):
		if w_left == "":
			c.take_weapon()
		elif Weapons.DATA.has(w_left):
			c.put_weapon(w_left)
	c.contents = {"weapon": w_left if Weapons.DATA.has(w_left) else "", "ammo": left.get("ammo", {}), "medkits": int(left.get("medkits", 0)), "armor": float(left.get("armor", 0.0))}
	c.refresh_label()
	if c.is_empty():
		game.loot_crates.erase(c)
		c.queue_free()


## Client dropped its old weapon when swapping: the host creates the crate.
func request_drop(pos: Vector3, contents: Dictionary) -> void:
	_req_drop.rpc_id(1, pos, contents)


@rpc("any_peer", "reliable")
func _req_drop(pos: Vector3, contents: Dictionary) -> void:
	if not is_server():
		return
	var a = avatars.get(multiplayer.get_remote_sender_id())
	if a == null or a.dead or not Weapons.DATA.has(contents.get("weapon", "")):
		return
	if pos.distance_to(a.global_position) > 4.0:
		pos = a.global_position
	game._spawn_crate(pos, {"weapon": contents["weapon"], "ammo": contents.get("ammo", {}), "medkits": 0, "armor": 0.0}, true)


func request_heal() -> void:
	_req_heal.rpc_id(1)


@rpc("any_peer", "reliable")
func _req_heal() -> void:
	if not is_server():
		return
	var a = avatars.get(multiplayer.get_remote_sender_id())
	if a == null or a.dead or a.medkits <= 0 or a.hit_points >= a.MAX_HP:
		return
	a.medkits -= 1
	a.hit_points = minf(a.MAX_HP, a.hit_points + game.MEDKIT_HEAL)


# ------------------------------------------------------------------ shots
## Client fired (ammo/cooldown already handled locally): the host re-traces the shot.
func request_shot(origin: Vector3, dir: Vector3, weapon_id: String) -> void:
	_req_shot.rpc_id(1, origin, dir, WEAPON_IDS.find(weapon_id))


@rpc("any_peer", "reliable")
func _req_shot(origin: Vector3, dir: Vector3, wi: int) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var a = avatars.get(id)
	if a == null or a.dead or wi <= 0 or wi >= WEAPON_IDS.size():
		stats["shots_rejected"] += 1
		return
	var wid: String = WEAPON_IDS[wi]
	var w: Dictionary = Weapons.DATA[wid]
	# Validation: plausible muzzle position and fire rate for that weapon.
	if origin.distance_to(a.eye()) > 1.8 or game.mission_time - a.last_shot_t < float(w["interval"]) * 0.7:
		stats["shots_rejected"] += 1
		return
	a.last_shot_t = game.mission_time
	a.set_weapon(wid)
	if a.rig != null:
		a.rig.fire()
	stats["shots_validated"] += 1
	dir = dir.normalized()
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 180.0)
	q.exclude = [a.get_rid()]
	var r: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(q)
	var hit_pos := origin + dir * 180.0
	var normal := Vector3.UP
	var kind := ""
	if not r.is_empty():
		hit_pos = r.position
		normal = r.normal
		kind = "sand"
		var hit: Object = r.collider
		if hit is Node and (hit as Node).has_meta("metal"):
			kind = "metal"
		if hit != null and hit.has_method("take_hit"):
			kind = "soldier"
			var head: bool = hit_pos.y > (hit as Node3D).global_position.y + 1.45
			var dmg: float = float(w["damage"]) * (float(w["head_mult"]) if head else 1.0)
			if hit == game.player:
				game.damage_player(dmg * Avatar.PVP_SCALE, origin, a)
			elif hit.has_method("take_hit_from"):
				if hit.take_hit_from(dmg * (Avatar.PVP_SCALE if "is_human" in hit else 1.0), a):
					a.kills += 1
		game.on_enemy_shot(a)
	broadcast_shot("p%d" % id, origin, hit_pos, normal, kind, wid)


## Everyone sees/hears a shot: shooter key, muzzle, impact point and what was hit.
func broadcast_shot(key: String, origin: Vector3, hit_pos: Vector3, normal: Vector3, kind: String, wid: String) -> void:
	if not is_server() or not in_match:
		return
	_fx_shot.rpc(key, origin, hit_pos, normal, kind, WEAPON_IDS.find(wid))


func bot_shot(e: Node3D) -> void:
	if e.has_meta("nid"):
		broadcast_shot("b%d" % int(e.get_meta("nid")), e.global_position + Vector3(0, 1.3, 0), Vector3.INF, Vector3.UP, "", e.weapon)


@rpc("authority", "unreliable")
func _fx_shot(key: String, origin: Vector3, hit_pos: Vector3, normal: Vector3, kind: String, wi: int) -> void:
	var wid: String = WEAPON_IDS[wi] if wi > 0 and wi < WEAPON_IDS.size() else "lee_enfield"
	var mine := key == "p%d" % my_id()
	if not mine:
		var pup = puppets.get(key)
		if pup != null and is_instance_valid(pup["rig"]):
			pup["rig"].fire()
		if game.audio:
			var snd: String = AudioScript.SHOT.get(wid, "shot_enemy") if key.begins_with("p") else ("shot_enemy" if wid == "lee_enfield" else AudioScript.SHOT.get(wid, "shot_enemy"))
			game.audio.play_at(snd, origin, -1.0, 0.08)
	if kind != "" and hit_pos.is_finite():
		Fx.impact(game, hit_pos + normal * 0.05, normal, kind, G.preset(game.quality)["detail"])
		if game.audio:
			game.audio.play_at({"soldier": "hit_flesh", "metal": "hit_metal"}.get(kind, "hit_sand"), hit_pos, -2.0 if kind == "soldier" else -6.0, 0.1)
		if mine and kind == "soldier":
			game.hit_marker_timer = 0.14


# ------------------------------------------------------------------ deaths / feed
func _on_avatar_died(a: Node3D, attacker: Node3D, cause: String) -> void:
	var killer := ""
	var wname := ""
	if cause == "zone" or attacker == null or not is_instance_valid(attacker):
		killer = game.ZONE_CALLSIGN
	else:
		killer = attacker.callsign if "callsign" in attacker else game.player_callsign()
		if attacker == game.player:
			killer = game.player_callsign()
			game.score += 1
			wname = Weapons.get_weapon(game.current_weapon()).get("name", "")
		elif "weapon" in attacker:
			wname = Weapons.get_weapon(attacker.weapon).get("name", "")
	game.add_kill_feed(killer, a.callsign, wname)
	if a.peer in multiplayer.get_peers():
		_you_died.rpc_id(a.peer, alive_total() + 1, killer)


@rpc("authority", "reliable")
func _you_died(placement: int, killer: String) -> void:
	my_dead = true
	game.health = 0.0
	if game.state == game.GameState.PLAYING:
		game._end_mission(false)
		game.placement = placement


func send_feed(killer: String, victim: String, weapon_name: String) -> void:
	if is_server() and in_match:
		_feed.rpc(killer, victim, weapon_name)


@rpc("authority", "reliable")
func _feed(killer: String, victim: String, weapon_name: String) -> void:
	game.add_kill_feed(killer, victim, weapon_name)


## Targets the bots may shoot at besides the host and each other.
func bot_targets() -> Array:
	var out := []
	for id in avatars:
		var a = avatars[id]
		if is_instance_valid(a) and not a.dead:
			out.append(a)
	return out


# ------------------------------------------------------------------ client: input + snapshots
## Called by game.gd every physics frame on clients with the locally predicted velocity.
func record_input(v: Vector3, jump: bool) -> void:
	if not in_match or my_dead:
		return
	_seq += 1
	var inp := [_seq, _quant(v.x), _quant(v.z), 1.0 if jump else 0.0, game.player.rotation.y, game.head.rotation.x, 1.0 if game.aiming else 0.0, WEAPON_IDS.find(game.current_weapon())]
	_outbox.append(inp)
	_pending.append([_seq, v.x, v.z])
	if _pending.size() > 120:
		_pending.pop_front()


func _client_tick(delta: float) -> void:
	_input_timer -= delta
	if _input_timer <= 0.0 and not _outbox.is_empty():
		_input_timer = INPUT_INTERVAL
		# Send the newest inputs plus a few older ones again (cheap insurance against loss).
		var batch: Array = _outbox.slice(maxi(0, _outbox.size() - 6))
		_inputs.rpc_id(1, batch)
		stats["inputs_sent"] += 1
		if _outbox.size() > 6:
			_outbox = _outbox.slice(_outbox.size() - 3)


@rpc("any_peer", "unreliable_ordered")
func _inputs(batch: Array) -> void:
	if not is_server():
		return
	var a = avatars.get(multiplayer.get_remote_sender_id())
	if a == null:
		return
	stats["inputs_got"] += 1
	for inp in batch:
		if inp is Array and inp.size() == 8:
			a.push_input(inp)


@rpc("authority", "unreliable_ordered")
func _snap(s: Array) -> void:
	if not is_client() or not in_match:
		return
	stats["snapshots_got"] += 1
	var t: float = s[0]
	if t < _server_t - 1.0:
		return
	_server_t = t
	_server_t_local = _clock
	var me := my_id()
	var live := {}
	for p in s[1]:
		var id: int = p[0]
		if id == me:
			_apply_self(p)
			continue
		var key := "p%d" % id
		live[key] = true
		_feed_puppet(key, t, p[1], p[2], p[4], p[5], int(p[6]), int(id) % 2, bool(p[10]))
	var b: PackedFloat32Array = s[2]
	var i := 0
	while i + 8 < b.size():
		var key := "b%d" % int(b[i])
		live[key] = true
		_feed_puppet(key, t, Vector3(b[i + 1], b[i + 2], b[i + 3]), b[i + 4], b[i + 5], b[i + 6] > 0.5, int(b[i + 7]), int(b[i + 8]), true)
		i += 9
	for key in puppets.keys():
		if not live.has(key):
			_kill_puppet(key)
	var z = game.zone
	var zs: Array = s[3]
	z.center = zs[0]
	z.radius = zs[1]
	z.target_center = zs[2]
	z.target_radius = zs[3]
	z.shrinking = zs[4]
	z.timer = zs[5]
	z.phase = zs[6]
	z.finished = zs[7]
	z._update_visuals()
	remote_alive = int(s[4])


func _apply_self(p: Array) -> void:
	var hp: float = p[7]
	if hp < game.health - 0.01:
		game.damage_flash.color.a = maxf(game.damage_flash.color.a, 0.45)
		game.since_damage = 0.0
	game.health = hp
	game.armor = p[8]
	game.medkits = int(p[9])
	game.score = int(p[12])
	# Reconcile: host position + our inputs it has not processed yet.
	var ack: int = p[11]
	last_ack = ack
	while not _pending.is_empty() and int(_pending[0][0]) <= ack:
		_pending.pop_front()
	var pred: Vector3 = p[1]
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	for q in _pending:
		pred += Vector3(float(q[1]), 0.0, float(q[2])) * dt
	var cur: Vector3 = game.player.global_position
	var err := Vector2(pred.x - cur.x, pred.z - cur.z)
	reconcile_error = err.length()
	if reconcile_error > 3.0:
		game.player.global_position = Vector3(pred.x, maxf(cur.y, float(p[1].y)), pred.z)
	elif reconcile_error > 0.05:
		game.player.global_position += Vector3(err.x, 0.0, err.y) * 0.25


func _feed_puppet(key: String, t: float, pos: Vector3, yaw: float, speed: float, aim: bool, wi: int, variant: int, alive: bool) -> void:
	var pup = puppets.get(key)
	if not alive:
		if pup != null:
			_kill_puppet(key)
		return
	if pup == null:
		_mats()
		var rig = Rig.new()
		game.add_child(rig)
		rig.build(variant, _uniform, _helmet)
		rig.global_position = pos
		rig.rotation.y = yaw
		pup = {"rig": rig, "buf": [], "weapon": ""}
		puppets[key] = pup
	var wid: String = WEAPON_IDS[wi] if wi > 0 and wi < WEAPON_IDS.size() else ""
	if wid != pup["weapon"] and wid != "":
		pup["weapon"] = wid
		var gh: Node3D = pup["rig"].gun_holder
		for c in gh.get_children():
			gh.remove_child(c)
			c.queue_free()
		Weapons.build_model(wid, gh, 1.0, true)
		pup["rig"].align_weapon(Weapons.DATA[wid].get("grip", Vector3.ZERO))
	var buf: Array = pup["buf"]
	buf.append([t, pos, yaw, speed, aim])
	while buf.size() > 12:
		buf.pop_front()


func _kill_puppet(key: String) -> void:
	var pup = puppets.get(key)
	puppets.erase(key)
	if pup != null and is_instance_valid(pup["rig"]):
		pup["rig"].die(game)


## Draw every remote body INTERP_DELAY in the past, between the two snapshots around it.
func _update_puppets() -> void:
	var render_t := _server_t + (_clock - _server_t_local) - INTERP_DELAY
	for key in puppets:
		var pup = puppets[key]
		var rig = pup["rig"]
		var buf: Array = pup["buf"]
		if buf.is_empty() or not is_instance_valid(rig):
			continue
		var a: Array = buf[0]
		var b: Array = buf[0]
		for i in range(buf.size()):
			if float(buf[i][0]) <= render_t:
				a = buf[i]
				b = buf[mini(i + 1, buf.size() - 1)]
		var span: float = float(b[0]) - float(a[0])
		var f := clampf((render_t - float(a[0])) / span, 0.0, 1.0) if span > 0.0001 else 1.0
		rig.global_position = (a[1] as Vector3).lerp(b[1], f)
		rig.rotation.y = lerp_angle(float(a[2]), float(b[2]), f)
		rig.set_motion(lerpf(float(a[3]), float(b[3]), f), bool(b[4]))
