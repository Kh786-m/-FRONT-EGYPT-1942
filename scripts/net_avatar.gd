extends CharacterBody3D
## Server-side body of a remote LAN player (v0.7). The host simulates it from the client's
## input stream (server-authoritative movement), bots can see and shoot it, the host's and other
## players' bullets hit it, and the zone hurts it. Health, armour and medkits live here and are
## sent back to the owner in every snapshot.

const Rig := preload("res://scripts/soldier_rig.gd")
const Weapons := preload("res://scripts/weapons.gd")
const GRAVITY := 24.0
const JUMP_SPEED := 8.0
const MAX_SPEED := 10.5
const MAX_HP := 100.0
const ARMOR_ABSORB := 0.6
## Player-vs-player damage scale (guns are tuned for one-shotting bots at close range).
const PVP_SCALE := 0.6

signal died(avatar: Node3D, attacker: Node3D, cause: String)

var game: Node
var is_human := true
var peer := 0
var callsign := "لاعب"
var weapon := "webley"
var hit_points := MAX_HP
var armor := 0.0
var medkits := 0
var kills := 0
var dead := false
var aiming := false
var yaw := 0.0
var pitch := 0.0
var last_seq := -1
var last_attacker: Node3D = null
var last_shot_t := -9.0
## Bots treat us like any soldier: these fields keep enemy.gd's checks happy.
var state := -1
var _cover_phase := 0
var rig: Node3D
var _queue: Array = []
var _idle := 0.0
var _last_v := Vector3.ZERO


func setup(p_peer: int, p_name: String, variant: int, uniform: Material, helmet: Material) -> void:
	peer = p_peer
	callsign = p_name
	name = "Avatar%d" % peer
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	rig = Rig.new()
	add_child(rig)
	rig.build(variant, uniform, helmet)
	set_weapon(weapon)


func set_weapon(id: String) -> void:
	if not Weapons.DATA.has(id):
		return
	if id == weapon and rig.gun_holder.get_child_count() > 0:
		return
	weapon = id
	for c in rig.gun_holder.get_children():
		rig.gun_holder.remove_child(c)
		c.queue_free()
	Weapons.build_model(id, rig.gun_holder, 1.0, true)
	rig.align_weapon(Weapons.DATA[id].get("grip", Vector3.ZERO))


## One client input: [seq, vx, vz, jump, yaw, pitch, aim, weapon_index].
func push_input(inp: Array) -> void:
	if int(inp[0]) <= last_seq:
		return
	for q in _queue:
		if int(q[0]) == int(inp[0]):
			return
	_queue.append(inp)
	if _queue.size() > 30:
		_queue.pop_front()


func step(delta: float, weapon_ids: Array) -> void:
	if dead:
		return
	_queue.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
	# Normally one input per tick; catch up a little if the client got ahead.
	var n := 1 if _queue.size() <= 4 else 2
	var used := 0
	while used < n and not _queue.is_empty():
		var inp: Array = _queue.pop_front()
		if int(inp[0]) <= last_seq:
			continue
		_apply(inp, delta, weapon_ids)
		used += 1
	if used == 0:
		_idle += delta
		# Packet gap: keep the last motion briefly, then stop.
		var v := _last_v if _idle < 0.25 else Vector3.ZERO
		velocity.x = v.x
		velocity.z = v.z
		_move(delta, false)
	rig.set_motion(Vector2(velocity.x, velocity.z).length(), aiming)


func _apply(inp: Array, delta: float, weapon_ids: Array) -> void:
	_idle = 0.0
	last_seq = int(inp[0])
	var v := Vector3(float(inp[1]), 0.0, float(inp[2]))
	if v.length() > MAX_SPEED:
		v = v.normalized() * MAX_SPEED
	_last_v = v
	velocity.x = v.x
	velocity.z = v.z
	yaw = float(inp[4])
	pitch = clampf(float(inp[5]), -1.5, 1.5)
	rotation.y = yaw
	aiming = float(inp[6]) > 0.5
	var wi := int(inp[7])
	if wi > 0 and wi < weapon_ids.size():
		set_weapon(weapon_ids[wi])
	_move(delta, float(inp[3]) > 0.5)


func _move(delta: float, jump: bool) -> void:
	if is_on_floor():
		velocity.y = JUMP_SPEED if jump else 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()


func eye() -> Vector3:
	return global_position + Vector3(0, 1.62, 0)


## The host's own bullets (game.gd raycast).
func take_hit(damage: float) -> bool:
	return take_hit_from(damage * PVP_SCALE, game.player if game != null else null)


func take_hit_from(damage: float, attacker: Node3D) -> bool:
	if dead:
		return false
	var dmg := damage
	if armor > 0.0:
		var soaked := minf(armor, dmg * ARMOR_ABSORB)
		armor -= soaked
		dmg -= soaked
	hit_points -= dmg
	if attacker != null and is_instance_valid(attacker):
		last_attacker = attacker
	if hit_points <= 0.0:
		_die(attacker, "player")
		return true
	rig.hit()
	return false


func take_zone_damage(damage: float) -> bool:
	if dead:
		return false
	hit_points -= damage
	if hit_points <= 0.0:
		_die(null, "zone")
		return true
	return false


func _die(attacker: Node3D, cause: String) -> void:
	dead = true
	hit_points = 0.0
	velocity = Vector3.ZERO
	for c in get_children():
		if c is CollisionShape3D:
			c.set_deferred("disabled", true)
	died.emit(self, attacker, cause)
	if rig != null and get_parent() != null:
		rig.die(get_parent())
		rig = null
