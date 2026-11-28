extends CharacterBody3D
## Enemy soldier AI: patrol -> detect (range + line of sight) -> chase -> attack (hitscan).
## Movement follows the navigation grid (scripts/nav.gd) around cover, with separation from
## other soldiers and stuck detection + recovery.
## Also respects the shrinking zone: patrols relocate inside the next circle and soldiers
## caught outside run back in (and take zone damage like the player).

const G := preload("res://scripts/graphics.gd")
const Fx := preload("res://scripts/fx.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Audio := preload("res://scripts/audio.gd")
const Rig := preload("res://scripts/soldier_rig.gd")
## Soldier-side weapon stats. dmg_player is per hit on the player; dmg_soldier on other soldiers.
const WEAPONS := {
	"webley": {"interval": 1.1, "dmg_player": 5.0, "dmg_soldier": 24.0, "range": 15.0, "hit": 0.5, "mag": 6, "reload": 2.2, "tier": 0},
	"lee_enfield": {"interval": 1.7, "dmg_player": 6.0, "dmg_soldier": 40.0, "range": 22.0, "hit": 0.55, "mag": 10, "reload": 2.6, "tier": 1},
	"mp40": {"interval": 0.42, "dmg_player": 4.0, "dmg_soldier": 14.0, "range": 17.0, "hit": 0.42, "mag": 32, "reload": 2.3, "tier": 2},
	"thompson": {"interval": 0.38, "dmg_player": 4.0, "dmg_soldier": 13.0, "range": 16.0, "hit": 0.42, "mag": 30, "reload": 2.4, "tier": 2},
}
const SMALL_ZONE := 22.0
const SEPARATION := 2.1
const LOOT_RANGE := 16.0
const MUZZLE_POS := Vector3(0.14, 1.19, -1.05)

signal died(enemy: CharacterBody3D, by_player: bool)

enum State { PATROL, CHASE, ATTACK, COVER }

const PATROL_SPEED := 1.6
const CHASE_SPEED := 3.6
const DETECT_RANGE := 30.0
const ATTACK_RANGE := 20.0
const KEEP_DISTANCE := 9.0
const LOSE_SIGHT_TIME := 5.0
const FIRE_INTERVAL := 1.7
const DAMAGE := 6
const BASE_HIT_CHANCE := 0.55
const GRAVITY := 24.0
const EYE_HEIGHT := 1.55
const MAX_HP := 100.0

var game: Node3D
var hit_points := MAX_HP
var origin := Vector3.ZERO
var patrol_axis := Vector3.RIGHT
var patrol_phase := 0.0
var state := State.PATROL
var _clock := 0.0
var _fire_cooldown := 1.0
var _lost_timer := 0.0
var _last_known := Vector3.ZERO
var _los_timer := 0.0
var _can_see := false
var _muzzle: OmniLight3D
var _flash_mesh: MeshInstance3D
## Skeleton3D-rigged body with AnimationTree (scripts/soldier_rig.gd).
var _body: Node3D
var rig_variant := 0
var _anim_speed := 0.0
var _walk_phase := 0.0
var _path := PackedVector3Array()
var _path_i := 0
var _path_goal := Vector3(INF, 0, INF)
var _repath_timer := 0.0
var _strafe_timer := 0.0
var _strafe_side := 1.0
var _stuck_clock := 0.0
var _stuck_from := Vector3.ZERO
var _stuck_streak := 0
var _unstick_timer := 0.0
var _unstick_dir := Vector3.ZERO
var _step_phase := 0.0
## Diagnostics (tests / soak): how often this soldier got stuck and re-planned.
var stuck_events := 0
var repaths := 0
var shots_fired := 0
var cover_entries := 0
var peeks := 0
var hiding_time := 0.0
var kills := 0
var loots := 0
var callsign := "SOLDIER"
var weapon := "lee_enfield"
## Combat: current hostile (player or another soldier), who hit us last, how we died.
var target: Node3D = null
var last_attacker: Node3D = null
var death_cause := ""
var _mag := 10
var _reload_timer := 0.0
var _under_fire := 0.0
var _loot_timer := 1.0
var _loot_crate = null
var _post_key := Vector4.ZERO
var _cover_point := Vector3.ZERO
var _peek_point := Vector3.ZERO
var _cover_phase := 0
var _cover_timer := 0.0
var _cover_cycles := 0
var _cover_cooldown := 0.0
var _peek_aimed := false
var _peek_blind := 0.0
var _gun_holder: Node3D


func setup(p_game: Node3D, p_origin: Vector3, p_axis: Vector3, p_phase: float, uniform: Material, helmet: Material, metal: Material, ember: Material) -> void:
	game = p_game
	origin = p_origin
	patrol_axis = p_axis
	patrol_phase = p_phase
	_fire_cooldown = randf_range(0.8, 2.0)
	var collider := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	collider.shape = cap
	collider.position.y = 0.9
	add_child(collider)
	_build_soldier(uniform, helmet, metal)
	_muzzle = OmniLight3D.new()
	_muzzle.light_color = Color("#E24A1B")
	_muzzle.light_energy = 0.0
	_muzzle.omni_range = 3.5
	_muzzle.shadow_enabled = false
	_muzzle.position = MUZZLE_POS
	_body.muzzle_holder.add_child(_muzzle)
	_flash_mesh = Fx.flash_mesh(0.22)
	_flash_mesh.position = MUZZLE_POS
	_body.muzzle_holder.add_child(_flash_mesh)
	_muzzle.visible = false


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation = rot
	m.scale = scl
	parent.add_child(m)
	return m


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 10
	c.rings = 3
	return c


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## Rigged 1942 desert infantryman (Afrika Korps or 8th Army look, see soldier_rig.gd):
## a Skeleton3D + one skinned mesh, animated by an AnimationTree (idle/walk/run, aim, fire,
## reload, hit, death fall). The weapon sits on the rig's "weapon" bone.
func _build_soldier(uniform: Material, helmet: Material, _metal: Material) -> void:
	_body = Rig.new()
	add_child(_body)
	_body.build(rig_variant, uniform, helmet)
	_gun_holder = _body.gun_holder


func _animate(delta: float, speed: float) -> void:
	# Drive the AnimationTree from the real ground speed and the AI state.
	var hv := Vector2(velocity.x, velocity.z).length()
	_anim_speed = move_toward(_anim_speed, minf(hv, speed if speed > 0.0 else hv), delta * 10.0)
	var aiming := state == State.ATTACK or (state == State.COVER and _cover_phase == 2 and _peek_aimed)
	_body.set_motion(_anim_speed, aiming)
	var amount := clampf(_anim_speed / CHASE_SPEED, 0.0, 1.0)
	_walk_phase += delta * (2.0 + _anim_speed * 2.2)
	# Footsteps (only audible close by; throttled by the walk cycle).
	if amount > 0.15 and game != null and game.audio != null:
		var step := floorf(_walk_phase / PI)
		if step != _step_phase:
			_step_phase = step
			var d: float = global_position.distance_to(game.player.global_position)
			if d < 16.0:
				game.audio.play_at("step", global_position, -6.0 + amount * 3.0, 0.12)


## Called by the player's weapon. Returns true if this hit killed the soldier.
func take_hit(damage: float) -> bool:
	return take_hit_from(damage, game.player if game != null else null)


## Damage from any combatant (the player or another soldier).
func take_hit_from(damage: float, attacker: Node3D) -> bool:
	if hit_points <= 0.0:
		return false
	hit_points -= damage
	_under_fire = 3.5
	last_attacker = attacker
	if attacker != null and is_instance_valid(attacker) and attacker != self:
		alert(attacker)
	if hit_points <= 0.0:
		death_cause = "player" if game != null and attacker == game.player else "enemy"
		_die(death_cause == "player")
		return true
	_body.hit()
	return false


## Damage from standing outside the zone. Returns true if it killed the soldier.
func take_zone_damage(damage: float) -> bool:
	if hit_points <= 0.0:
		return false
	hit_points -= damage
	if hit_points <= 0.0:
		death_cause = "zone"
		_die(false)
		return true
	return false


func _die(by_player: bool) -> void:
	if game != null:
		if game.nav != null:
			game.nav.release_claim(self)
		if game.cover != null:
			game.cover.release(self)
	if is_inside_tree() and get_parent() != null:
		Fx.death_puff(get_parent(), global_position, 1.0)
		# The body plays its fall animation on its own after this soldier is gone.
		_body.die(get_parent())
	died.emit(self, by_player)
	queue_free()


## Something hostile is around: by default the player (gunfire noise), or a given attacker.
func alert(attacker: Node3D = null) -> void:
	if attacker == null and game and is_instance_valid(game.player):
		attacker = game.player
	if attacker != null and is_instance_valid(attacker):
		if target == null or not is_instance_valid(target) or not _can_see:
			target = attacker
		_last_known = attacker.global_position
	if state == State.PATROL:
		state = State.CHASE
		_repath_timer = 0.0
	_lost_timer = 0.0


## Equip a weapon (also updates the model in the soldier's hands).
func equip(id: String) -> void:
	if not WEAPONS.has(id):
		return
	weapon = id
	_mag = int(WEAPONS[id]["mag"])
	_reload_timer = 0.0
	if _gun_holder != null:
		for c in _gun_holder.get_children():
			_gun_holder.remove_child(c)
			c.queue_free()
		Weapons.build_model(id, _gun_holder, 1.0, true)
		_body.align_weapon(Weapons.DATA[id].get("grip", Vector3.ZERO))
		var m: Vector3 = Weapons.DATA[id].get("muzzle", Vector3(0, 0, -0.6))
		var mp := _gun_holder.position + _gun_holder.basis * m
		_muzzle.position = mp
		_flash_mesh.position = mp


func _start_reload() -> void:
	_reload_timer = float(WEAPONS[weapon]["reload"])
	_body.reload(_reload_timer)


func weapon_tier() -> int:
	return int(WEAPONS[weapon]["tier"])


func is_reloading() -> bool:
	return _reload_timer > 0.0


func _valid(t) -> bool:
	if t == null or not is_instance_valid(t):
		return false
	if game != null and t == game.player:
		return game.is_playing()
	return t.hit_points > 0.0


## Pick the nearest visible hostile (player or any other soldier — battle royale).
func _update_target() -> void:
	var me := global_position
	var cands: Array = []
	if game.is_playing():
		cands.append(game.player)
	if game.free_for_all:
		for e in game.enemies:
			if e != self and is_instance_valid(e):
				cands.append(e)
	var near: Array = []
	for c in cands:
		var d: float = Vector2(c.global_position.x - me.x, c.global_position.z - me.z).length()
		if d < DETECT_RANGE:
			near.append([d, c])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var keep := _valid(target)
	var keep_d := INF
	if keep:
		keep_d = Vector2(target.global_position.x - me.x, target.global_position.z - me.z).length()
	var found = null
	var checks := 0
	for pair in near:
		if checks >= 3:
			break
		checks += 1
		# Sticky: don't drop a visible target for one that is only slightly closer.
		if keep and pair[1] != target and pair[0] > keep_d * 0.7:
			continue
		if _has_line_of_sight(pair[1]):
			found = pair[1]
			break
	if found == null and keep and keep_d < DETECT_RANGE and _has_line_of_sight(target):
		found = target
	_can_see = found != null
	if found != null:
		target = found
	elif not keep:
		target = null


func _physics_process(delta: float) -> void:
	_muzzle.light_energy = move_toward(_muzzle.light_energy, 0.0, delta * 30.0)
	_flash_mesh.visible = _muzzle.light_energy > 0.5
	_muzzle.visible = _muzzle.light_energy > 0.01
	if game == null or not game.is_playing():
		velocity = Vector3.ZERO
		return
	_clock += delta
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	_repath_timer -= delta
	_under_fire = maxf(0.0, _under_fire - delta)
	_loot_timer -= delta
	if _reload_timer > 0.0:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_mag = int(WEAPONS[weapon]["mag"])
	# Target scans (line-of-sight raycasts) are throttled to keep mobile CPU cost low.
	_los_timer -= delta
	if _los_timer <= 0.0:
		_los_timer = 0.22 + randf() * 0.06
		_update_target()
	var has_target := _valid(target)
	var tpos: Vector3 = target.global_position if has_target else _last_known
	var to_t := tpos - global_position
	to_t.y = 0.0
	var dist := to_t.length()
	var move_dir := Vector3.ZERO
	var speed := 0.0
	var zone: Node3D = game.zone
	var outside_zone: bool = zone != null and not zone.is_inside(global_position)
	_update_post(zone)
	if outside_zone and state != State.ATTACK:
		if state == State.COVER:
			_leave_cover()
		state = State.PATROL
	match state:
		State.PATROL:
			if _can_see and not outside_zone:
				alert(target)
			var goal := _patrol_goal()
			var to_goal := goal - global_position
			to_goal.y = 0.0
			# Soldiers at their post look around for better gear nearby.
			if _loot_crate == null and to_goal.length() < 1.0 and _loot_timer <= 0.0 and not outside_zone:
				_loot_timer = randf_range(0.8, 1.4)
				_loot_crate = _find_loot()
			if _loot_crate != null:
				if not is_instance_valid(_loot_crate) or _loot_crate.is_queued_for_deletion():
					_loot_crate = null
				elif Vector2(_loot_crate.global_position.x - origin.x, _loot_crate.global_position.z - origin.z).length() > LOOT_RANGE + 2.0 \
						or (zone != null and not zone.is_inside(_loot_crate.global_position)):
					# Our post moved (zone shrank / new orders): forget that crate.
					_loot_crate.remove_meta("claimed_by")
					_loot_crate = null
				else:
					goal = _loot_crate.global_position
					to_goal = goal - global_position
					to_goal.y = 0.0
					if to_goal.length() < 1.8:
						game.enemy_loot(self, _loot_crate)
						_loot_crate = null
			if to_goal.length() > 0.4:
				move_dir = _steer_to(goal)
				speed = CHASE_SPEED if outside_zone else (PATROL_SPEED if to_goal.length() < 4.0 else CHASE_SPEED * 0.7)
		State.CHASE:
			_loot_crate = null
			if _can_see and has_target:
				_last_known = tpos
				_lost_timer = 0.0
				if dist < ATTACK_RANGE:
					state = State.ATTACK
					_strafe_timer = 0.0
			else:
				_lost_timer += delta
				if _lost_timer > LOSE_SIGHT_TIME:
					state = State.PATROL
					target = null
			var to_last := _last_known - global_position
			to_last.y = 0.0
			if to_last.length() > 1.0:
				move_dir = _steer_to(_last_known)
				speed = CHASE_SPEED
		State.ATTACK:
			if not _can_see or not has_target or dist > ATTACK_RANGE * 1.15:
				state = State.CHASE
				_repath_timer = 0.0
			else:
				_last_known = tpos
				_lost_timer = 0.0
				_face(to_t, delta)
				if _wants_cover() and _try_take_cover(tpos):
					pass
				elif dist > KEEP_DISTANCE:
					move_dir = _steer_to(tpos)
					speed = CHASE_SPEED * 0.8
				else:
					# Hold the line and side-step so the soldier is not a static target.
					_strafe_timer -= delta
					if _strafe_timer <= 0.0:
						_strafe_timer = randf_range(1.2, 2.4)
						_strafe_side = -_strafe_side
					var side := Vector3(-to_t.z, 0, to_t.x).normalized() * _strafe_side
					if game.nav == null or game.nav.is_walkable(global_position + side * 1.2):
						move_dir = side
						speed = PATROL_SPEED
				if state == State.ATTACK and _fire_cooldown <= 0.0:
					_shoot(dist)
		State.COVER:
			var r := _cover_step(delta, has_target, tpos, dist)
			move_dir = r[0]
			speed = r[1]
	# Stuck recovery overrides the planned direction for a moment.
	if _unstick_timer > 0.0:
		_unstick_timer -= delta
		move_dir = _unstick_dir
		speed = maxf(speed, PATROL_SPEED * 1.5)
	elif move_dir != Vector3.ZERO:
		move_dir = (move_dir + _separation() * 0.8).normalized()
	elif state == State.PATROL:
		# Idle soldiers still drift apart if someone is standing on them.
		var push := _separation()
		if push.length() > 0.25:
			move_dir = push.normalized()
			speed = PATROL_SPEED * 0.6
	if move_dir != Vector3.ZERO and state != State.ATTACK and not (state == State.COVER and _cover_phase == 2):
		_face(move_dir, delta)
	velocity.x = move_dir.x * speed
	velocity.z = move_dir.z * speed
	_animate(delta, speed)
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	_check_stuck(delta, speed)


# ------------------------------------------------------------------ posts / final-zone spread
## Small zones: every soldier gets its own slot on two rings around the centre (claimed on the
## nav grid), instead of everyone patrolling to the same few metres.
func _update_post(zone: Node3D) -> void:
	if zone == null:
		return
	var tc: Vector2 = zone.target_center
	var tr: float = zone.target_radius
	if tr < SMALL_ZONE:
		var n: int = maxi(1, game.enemies.size())
		var slot: int = maxi(0, game.enemies.find(self))
		var key := Vector4(tc.x, tc.y, tr, n)
		if key != _post_key:
			_post_key = key
			var ring := 0.72 if slot % 2 == 0 else 0.4
			var ang := TAU * float(slot) / float(n) + 0.37
			var want := Vector3(tc.x + cos(ang) * tr * ring, 0.0, tc.y + sin(ang) * tr * ring)
			origin = game.nav.claim_near(want, self) if game.nav != null else want
			_repath_timer = 0.0
	elif Vector2(origin.x, origin.z).distance_to(tc) > tr * 0.85:
		_set_origin(zone.random_point_in_target())


func _patrol_goal() -> Vector3:
	var amp := 3.0
	if game.zone != null and game.zone.target_radius < SMALL_ZONE:
		amp = 0.6
	return origin + patrol_axis * sin(_clock * 0.5 + patrol_phase) * amp


func _set_origin(p: Vector3) -> void:
	origin = game.nav.claim_near(p, self) if game != null and game.nav != null else p
	_repath_timer = 0.0


# ------------------------------------------------------------------ cover
func _wants_cover() -> bool:
	if game.cover == null or _cover_cooldown > _clock:
		return false
	return _reload_timer > 0.0 or (_under_fire > 0.0 and hit_points < 80.0)


func _try_take_cover(threat: Vector3) -> bool:
	var c: Dictionary = game.cover.find(global_position, threat, self, game.nav)
	if c.is_empty():
		_cover_cooldown = _clock + 2.0
		return false
	_cover_point = c["p"]
	_peek_point = c["peek"]
	_cover_phase = 0
	_cover_cycles = 0
	state = State.COVER
	cover_entries += 1
	_repath_timer = 0.0
	return true


func _leave_cover() -> void:
	if game.cover != null:
		game.cover.release(self)
	_cover_cooldown = _clock + 3.0
	_cover_phase = 0


## COVER: 0 = run to the spot, 1 = hide (reload / wait), 2 = peek out and fire, then back.
func _cover_step(delta: float, has_target: bool, tpos: Vector3, dist: float) -> Array:
	if not has_target:
		_lost_timer += delta
		if _lost_timer > LOSE_SIGHT_TIME:
			_leave_cover()
			state = State.CHASE
			return [Vector3.ZERO, 0.0]
	else:
		_lost_timer = 0.0
		_last_known = tpos
	_cover_timer -= delta
	match _cover_phase:
		0:
			var d := Vector2(_cover_point.x - global_position.x, _cover_point.z - global_position.z).length()
			if d < 0.7:
				_cover_phase = 1
				_cover_timer = maxf(_reload_timer, 0.0) + randf_range(0.8, 1.6)
				if _mag < int(WEAPONS[weapon]["mag"]) and _reload_timer <= 0.0:
					_start_reload()
					_cover_timer += _reload_timer
				return [Vector3.ZERO, 0.0]
			return [_steer_to(_cover_point), CHASE_SPEED]
		1:
			hiding_time += delta
			if _cover_timer <= 0.0 and _reload_timer <= 0.0:
				_cover_phase = 2
				_cover_timer = randf_range(1.5, 2.6)
				peeks += 1
			var d1 := Vector2(_cover_point.x - global_position.x, _cover_point.z - global_position.z).length()
			return [_steer_to(_cover_point) if d1 > 0.5 else Vector3.ZERO, PATROL_SPEED]
		2:
			var d2 := Vector2(_peek_point.x - global_position.x, _peek_point.z - global_position.z).length()
			var at_peek := d2 <= 0.5
			if has_target:
				var to_t := tpos - global_position
				to_t.y = 0.0
				_face(to_t, delta)
				if _can_see and _mag > 0:
					if not _peek_aimed:
						# Out of cover with a clear view: a short aim, then fire.
						_peek_aimed = true
						_fire_cooldown = minf(_fire_cooldown, randf_range(0.25, 0.45))
						_cover_timer = maxf(_cover_timer, 1.2)
					if _fire_cooldown <= 0.0:
						_shoot(dist)
			if at_peek and not _can_see:
				_peek_blind += delta
				if _peek_blind > 0.7:
					# No line of fire from this side: try the other side of the cover.
					_peek_blind = 0.0
					_peek_point = _cover_point * 2.0 - _peek_point
			if _cover_timer <= 0.0 or _reload_timer > 0.0:
				_cover_cycles += 1
				_peek_aimed = false
				_peek_blind = 0.0
				if _cover_cycles >= 3 and hit_points > 50.0:
					_leave_cover()
					state = State.ATTACK
				else:
					_cover_phase = 1
					_cover_timer = randf_range(0.8, 1.6)
				return [Vector3.ZERO, 0.0]
			return [_steer_to(_peek_point) if not at_peek else Vector3.ZERO, PATROL_SPEED * 1.3]
	return [Vector3.ZERO, 0.0]


func is_hidden_from(threat: Vector3) -> bool:
	return game.nav != null and not game.nav.line_clear(global_position, threat)


# ------------------------------------------------------------------ loot
func _find_loot():
	var cands: Array = []
	for c in game.loot_crates:
		if not is_instance_valid(c) or c.is_queued_for_deletion():
			continue
		var d: float = Vector2(c.global_position.x - global_position.x, c.global_position.z - global_position.z).length()
		if d >= LOOT_RANGE:
			continue
		var claimed = c.get_meta("claimed_by", 0)
		if claimed != 0 and claimed != get_instance_id() and is_instance_id_valid(claimed):
			continue
		var w: String = c.contents.get("weapon", "")
		var wants_gun: bool = w != "" and WEAPONS.has(w) and int(WEAPONS[w]["tier"]) > weapon_tier()
		var wants_med: bool = int(c.contents.get("medkits", 0)) > 0 and hit_points < 80.0
		if wants_gun or wants_med:
			cands.append([d, c])
	cands.sort_custom(func(x, y): return x[0] < y[0])
	# Only crates that are actually close on foot (not behind a long wall).
	for i in range(mini(2, cands.size())):
		var c = cands[i][1]
		if game.nav != null:
			var path: PackedVector3Array = game.nav.find_path(global_position, c.global_position)
			var length := 0.0
			var prev := global_position
			for q in path:
				length += Vector2(q.x - prev.x, q.z - prev.z).length()
				prev = q
			if path.is_empty() or length > LOOT_RANGE * 1.4:
				continue
		c.set_meta("claimed_by", get_instance_id())
		return c
	return null


# ------------------------------------------------------------------ movement helpers
## Direction toward `goal`, following the navigation grid around rocks, ruins and wrecks.
func _steer_to(goal: Vector3) -> Vector3:
	var pos := global_position
	var nav = game.nav
	if nav == null:
		var d := goal - pos
		d.y = 0.0
		return d.normalized()
	var goal_moved := Vector2(goal.x - _path_goal.x, goal.z - _path_goal.z).length() > 2.0
	if _path.is_empty() or _repath_timer <= 0.0 or (goal_moved and _repath_timer < 0.45):
		_repath_timer = randf_range(0.6, 1.0)
		_path = nav.find_path(pos, goal)
		_path_i = 0
		_path_goal = goal
		repaths += 1
	while _path_i < _path.size() - 1 and Vector2(_path[_path_i].x - pos.x, _path[_path_i].z - pos.z).length() < 0.8:
		_path_i += 1
	if _path.is_empty():
		return Vector3.ZERO
	var tgt := _path[_path_i]
	var d2 := Vector3(tgt.x - pos.x, 0.0, tgt.z - pos.z)
	return d2.normalized() if d2.length() > 0.05 else Vector3.ZERO


## Keep distance from other soldiers so squads do not jam in gaps or in the final circle.
func _separation() -> Vector3:
	var push := Vector3.ZERO
	var r := SEPARATION
	for e in game.enemies:
		if e == self or not is_instance_valid(e):
			continue
		var d: Vector3 = global_position - e.global_position
		d.y = 0.0
		var l := d.length()
		if l < r and l > 0.01:
			push += d / l * (r - l)
		elif l <= 0.01:
			push += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	return push


## Detect "trying to move but not getting anywhere" and recover: side-step, re-plan, and after
## repeated failures pick a fresh patrol post.
func _check_stuck(delta: float, speed: float) -> void:
	if speed < 0.5 or _unstick_timer > 0.0:
		_stuck_clock = 0.0
		_stuck_from = global_position
		return
	_stuck_clock += delta
	if _stuck_clock < 0.8:
		return
	var moved := Vector2(global_position.x - _stuck_from.x, global_position.z - _stuck_from.z).length()
	if moved < speed * _stuck_clock * 0.25:
		stuck_events += 1
		_stuck_streak += 1
		var fwd := Vector3(velocity.x, 0, velocity.z).normalized()
		if fwd == Vector3.ZERO:
			fwd = -global_transform.basis.z
		var side := Vector3(-fwd.z, 0, fwd.x) * (1.0 if randf() < 0.5 else -1.0)
		_unstick_dir = (side - fwd * 0.6).normalized()
		_unstick_timer = 0.6
		# Remember what we bumped into so the next plan goes around it — unless it's just
		# another soldier (they move; blocking their cell would wall off the final circle).
		if game.nav != null and not _soldier_ahead(fwd):
			game.nav.block_temporarily(global_position + fwd * 0.9, game.mission_time)
		_path = PackedVector3Array()
		_repath_timer = 0.0
		if _stuck_streak >= 3:
			_stuck_streak = 0
			if state == State.PATROL and game.zone != null:
				_post_key = Vector4.ZERO
				_set_origin(game.zone.random_point_in_target())
			elif state == State.COVER:
				_leave_cover()
				state = State.ATTACK
	else:
		_stuck_streak = 0
	_stuck_clock = 0.0
	_stuck_from = global_position


func _soldier_ahead(fwd: Vector3) -> bool:
	var probe := global_position + fwd * 1.0
	for e in game.enemies:
		if e != self and is_instance_valid(e) and Vector2(e.global_position.x - probe.x, e.global_position.z - probe.z).length() < 1.0:
			return true
	return false


func _face(dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	var yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * 8.0, 0.0, 1.0))


func _has_line_of_sight(t: Node3D) -> bool:
	var from := global_position + Vector3(0, EYE_HEIGHT, 0)
	var to := t.global_position + Vector3(0, 1.4, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	return not result.is_empty() and result.collider == t


func _shoot(dist: float) -> void:
	if _reload_timer > 0.0 or not _valid(target):
		return
	if _mag <= 0:
		_start_reload()
		return
	var w: Dictionary = WEAPONS[weapon]
	_mag -= 1
	_fire_cooldown = float(w["interval"]) * randf_range(1.0, 1.35)
	_muzzle.light_energy = 4.0
	_muzzle.visible = true
	_flash_mesh.rotation.z = randf() * TAU
	_body.fire()
	shots_fired += 1
	if game.audio:
		game.audio.play_at("shot_enemy" if weapon == "lee_enfield" else Audio.SHOT.get(weapon, "shot_enemy"), global_position + Vector3(0, 1.3, 0), -1.0, 0.08)
	game.on_enemy_shot(self)
	var rng: float = float(w["range"])
	var chance: float = float(w["hit"]) * clampf(1.25 - dist / rng, 0.25, 1.0)
	if target == game.player:
		if game.is_player_moving_fast():
			chance *= 0.6
		if randf() < chance:
			game.damage_player(float(w["dmg_player"]), global_position, self)
	else:
		# Soldiers peeking from cover are harder to hit.
		if target.state == State.COVER and target._cover_phase != 2:
			chance *= 0.25
		if randf() < chance:
			if target.take_hit_from(float(w["dmg_soldier"]), self):
				kills += 1
