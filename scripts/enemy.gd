extends CharacterBody3D
## Enemy soldier AI: patrol -> detect (range + line of sight) -> chase -> attack (hitscan).
## Movement follows the navigation grid (scripts/nav.gd) around cover, with separation from
## other soldiers and stuck detection + recovery.
## Also respects the shrinking zone: patrols relocate inside the next circle and soldiers
## caught outside run back in (and take zone damage like the player).

const G := preload("res://scripts/graphics.gd")
const Fx := preload("res://scripts/fx.gd")
const MUZZLE_POS := Vector3(0.14, 1.19, -1.05)

signal died(enemy: CharacterBody3D, by_player: bool)

enum State { PATROL, CHASE, ATTACK }

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
var _body: Node3D
var _legs: Array[Node3D] = []
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
	add_child(_muzzle)
	_flash_mesh = Fx.flash_mesh(0.22)
	_flash_mesh.position = MUZZLE_POS
	add_child(_flash_mesh)
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


## Low-poly 1942 desert infantryman: tan tunic and trousers, webbing, flared steel helmet,
## bolt-action rifle held at the ready. Legs swing while walking (see _animate).
func _build_soldier(uniform: Material, helmet: Material, metal: Material) -> void:
	_body = Node3D.new()
	add_child(_body)
	var skin := G.flat(Color(0.62, 0.45, 0.33), 0.8)
	var leather := G.flat(Color(0.2, 0.15, 0.11), 0.6)
	var webbing := G.flat(Color(0.42, 0.37, 0.27), 0.95)
	var wood := G.pbr("wood", Color(1.1, 0.85, 0.65), 3.0, true, 0.6, 0.0, 0.5, false)
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.11, 0.92, 0)
		_body.add_child(hip)
		_mesh(hip, _capsule(0.085, 0.86), Vector3(0, -0.42, 0), uniform)
		_mesh(hip, _box(Vector3(0.12, 0.13, 0.26)), Vector3(0, -0.86, -0.04), leather)
		_mesh(hip, _box(Vector3(0.13, 0.12, 0.14)), Vector3(0, -0.72, 0.0), webbing)
		_legs.append(hip)
	_mesh(_body, _box(Vector3(0.38, 0.11, 0.24)), Vector3(0, 0.96, 0), leather)
	_mesh(_body, _capsule(0.2, 0.66), Vector3(0, 1.26, 0), uniform, Vector3.ZERO, Vector3(1.0, 1.0, 0.68))
	for side in [-1.0, 1.0]:
		_mesh(_body, _box(Vector3(0.045, 0.5, 0.02)), Vector3(side * 0.09, 1.25, -0.14), webbing, Vector3(0, 0, side * 0.25))
		_mesh(_body, _box(Vector3(0.09, 0.1, 0.06)), Vector3(side * 0.12, 0.98, -0.14), webbing)
	_mesh(_body, _box(Vector3(0.26, 0.28, 0.12)), Vector3(0, 1.28, 0.17), webbing)
	_mesh(_body, _capsule(0.05, 0.14), Vector3(0, 1.53, 0), skin)
	var head := SphereMesh.new()
	head.radius = 0.105
	head.height = 0.23
	head.radial_segments = 12
	head.rings = 6
	_mesh(_body, head, Vector3(0, 1.64, -0.01), skin)
	var dome := SphereMesh.new()
	dome.radius = 0.145
	dome.height = 0.15
	dome.is_hemisphere = true
	dome.radial_segments = 14
	dome.rings = 4
	_mesh(_body, dome, Vector3(0, 1.68, 0), helmet)
	var skirt := CylinderMesh.new()
	skirt.top_radius = 0.145
	skirt.bottom_radius = 0.172
	skirt.height = 0.07
	skirt.radial_segments = 14
	skirt.rings = 1
	skirt.cap_top = false
	_mesh(_body, skirt, Vector3(0, 1.655, 0.01), helmet)
	# Arms holding the rifle in a low-ready.
	_mesh(_body, _capsule(0.065, 0.42), Vector3(0.24, 1.25, -0.06), uniform, Vector3(0.5, 0, 0.18))
	_mesh(_body, _capsule(0.06, 0.38), Vector3(0.2, 1.1, -0.28), uniform, Vector3(1.35, 0, 0.0))
	_mesh(_body, _capsule(0.065, 0.42), Vector3(-0.24, 1.27, -0.12), uniform, Vector3(0.75, 0, -0.25))
	_mesh(_body, _capsule(0.06, 0.4), Vector3(-0.08, 1.16, -0.38), uniform, Vector3(1.45, -0.6, 0.0))
	_mesh(_body, _box(Vector3(0.08, 0.08, 0.1)), Vector3(0.17, 1.1, -0.44), skin)
	_mesh(_body, _box(Vector3(0.08, 0.08, 0.1)), Vector3(0.05, 1.16, -0.56), skin)
	var rifle := Node3D.new()
	rifle.position = Vector3(0.12, 1.16, -0.45)
	rifle.rotation = Vector3(0.03, 0.12, 0)
	_body.add_child(rifle)
	_mesh(rifle, _box(Vector3(0.05, 0.07, 0.75)), Vector3(0, 0, -0.12), wood)
	_mesh(rifle, _box(Vector3(0.045, 0.11, 0.26)), Vector3(0, -0.03, 0.36), wood)
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.012
	barrel.bottom_radius = 0.012
	barrel.height = 0.36
	barrel.radial_segments = 6
	_mesh(rifle, barrel, Vector3(0, 0.025, -0.6), metal, Vector3(PI * 0.5, 0, 0))
	_mesh(rifle, _box(Vector3(0.04, 0.04, 0.2)), Vector3(0, 0.05, 0.02), metal)


func _animate(delta: float, speed: float) -> void:
	var amount := clampf(speed / CHASE_SPEED, 0.0, 1.0)
	_walk_phase += delta * (2.0 + speed * 2.2)
	var swing := sin(_walk_phase) * 0.55 * amount
	if _legs.size() == 2:
		_legs[0].rotation.x = swing
		_legs[1].rotation.x = -swing
	_body.position.y = absf(cos(_walk_phase)) * 0.04 * amount
	# Footsteps (only audible close by; throttled by the walk cycle).
	if amount > 0.15 and game != null and game.audio != null:
		var step := floorf(_walk_phase / PI)
		if step != _step_phase:
			_step_phase = step
			var d: float = global_position.distance_to(game.player.global_position)
			if d < 16.0:
				game.audio.play_at("step", global_position, -6.0 + amount * 3.0, 0.12)


## Called by the player's weapon. Returns true if this hit killed the enemy.
func take_hit(damage: float) -> bool:
	if hit_points <= 0.0:
		return false
	hit_points -= damage
	alert()
	if hit_points <= 0.0:
		_die(true)
		return true
	return false


## Damage from standing outside the zone. Returns true if it killed the soldier.
func take_zone_damage(damage: float) -> bool:
	if hit_points <= 0.0:
		return false
	hit_points -= damage
	if hit_points <= 0.0:
		_die(false)
		return true
	return false


func _die(by_player: bool) -> void:
	if is_inside_tree() and get_parent() != null:
		Fx.death_puff(get_parent(), global_position, 1.0)
	died.emit(self, by_player)
	queue_free()


func alert() -> void:
	if game and is_instance_valid(game.player):
		_last_known = game.player.global_position
	if state == State.PATROL:
		state = State.CHASE
		_repath_timer = 0.0
	_lost_timer = 0.0


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
	var player: CharacterBody3D = game.player
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	# Line-of-sight raycasts are throttled to keep mobile CPU cost low.
	_los_timer -= delta
	if _los_timer <= 0.0:
		_los_timer = 0.2
		_can_see = dist < DETECT_RANGE and _has_line_of_sight(player)
	var move_dir := Vector3.ZERO
	var speed := 0.0
	var zone: Node3D = game.zone
	var outside_zone: bool = zone != null and not zone.is_inside(global_position)
	# Keep the patrol post inside the circle the zone is closing toward (and off blocked cells).
	if zone != null and Vector2(origin.x, origin.z).distance_to(zone.target_center) > zone.target_radius * 0.85:
		_set_origin(zone.random_point_in_target())
	if outside_zone and state != State.ATTACK:
		state = State.PATROL
	match state:
		State.PATROL:
			if _can_see and not outside_zone:
				alert()
			var goal := origin + patrol_axis * sin(_clock * 0.5 + patrol_phase) * 3.0
			var to_goal := goal - global_position
			to_goal.y = 0.0
			if to_goal.length() > 0.4:
				move_dir = _steer_to(goal)
				speed = CHASE_SPEED if outside_zone else (PATROL_SPEED if to_goal.length() < 4.0 else CHASE_SPEED * 0.7)
		State.CHASE:
			if _can_see:
				_last_known = player.global_position
				_lost_timer = 0.0
				if dist < ATTACK_RANGE:
					state = State.ATTACK
					_strafe_timer = 0.0
			else:
				_lost_timer += delta
				if _lost_timer > LOSE_SIGHT_TIME:
					state = State.PATROL
			var to_last := _last_known - global_position
			to_last.y = 0.0
			if to_last.length() > 1.0:
				move_dir = _steer_to(_last_known)
				speed = CHASE_SPEED
		State.ATTACK:
			if not _can_see or dist > ATTACK_RANGE * 1.15:
				state = State.CHASE
				_repath_timer = 0.0
			else:
				_last_known = player.global_position
				_lost_timer = 0.0
				_face(to_player, delta)
				if dist > KEEP_DISTANCE:
					move_dir = _steer_to(player.global_position)
					speed = CHASE_SPEED * 0.8
				else:
					# Hold the line and side-step so the soldier is not a static target.
					_strafe_timer -= delta
					if _strafe_timer <= 0.0:
						_strafe_timer = randf_range(1.2, 2.4)
						_strafe_side = -_strafe_side
					var side := Vector3(-to_player.z, 0, to_player.x).normalized() * _strafe_side
					if game.nav == null or game.nav.is_walkable(global_position + side * 1.2):
						move_dir = side
						speed = PATROL_SPEED
				if _fire_cooldown <= 0.0:
					_shoot(dist)
	# Stuck recovery overrides the planned direction for a moment.
	if _unstick_timer > 0.0:
		_unstick_timer -= delta
		move_dir = _unstick_dir
		speed = maxf(speed, PATROL_SPEED * 1.5)
	elif move_dir != Vector3.ZERO:
		move_dir = (move_dir + _separation() * 0.8).normalized()
	if move_dir != Vector3.ZERO and state != State.ATTACK:
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


func _set_origin(p: Vector3) -> void:
	origin = game.nav.nearest_free_point(p) if game != null and game.nav != null else p
	_repath_timer = 0.0


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
	var target := _path[_path_i]
	var d2 := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
	return d2.normalized() if d2.length() > 0.05 else Vector3.ZERO


## Keep a little distance from other soldiers so squads do not jam in gaps.
func _separation() -> Vector3:
	var push := Vector3.ZERO
	for e in game.enemies:
		if e == self or not is_instance_valid(e):
			continue
		var d: Vector3 = global_position - e.global_position
		d.y = 0.0
		var l := d.length()
		if l < 1.6 and l > 0.01:
			push += d / l * (1.6 - l)
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
		if game.nav != null:
			# Remember what we bumped into so the next plan goes around it.
			game.nav.block_temporarily(global_position + fwd * 0.9, game.mission_time)
		_path = PackedVector3Array()
		_repath_timer = 0.0
		if _stuck_streak >= 3:
			_stuck_streak = 0
			if state == State.PATROL and game.zone != null:
				_set_origin(game.zone.random_point_in_target())
	else:
		_stuck_streak = 0
	_stuck_clock = 0.0
	_stuck_from = global_position


func _face(dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	var yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * 8.0, 0.0, 1.0))


func _has_line_of_sight(player: CharacterBody3D) -> bool:
	var from := global_position + Vector3(0, EYE_HEIGHT, 0)
	var to := player.global_position + Vector3(0, 1.4, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	return not result.is_empty() and result.collider == player


func _shoot(dist: float) -> void:
	_fire_cooldown = FIRE_INTERVAL + randf() * 0.6
	_muzzle.light_energy = 4.0
	_muzzle.visible = true
	_flash_mesh.rotation.z = randf() * TAU
	shots_fired += 1
	if game.audio:
		game.audio.play_at("shot_enemy", global_position + Vector3(0, 1.3, 0), 0.0, 0.08)
	var chance := BASE_HIT_CHANCE * clampf(1.25 - dist / ATTACK_RANGE, 0.3, 1.0)
	if game.is_player_moving_fast():
		chance *= 0.6
	if randf() < chance:
		game.damage_player(DAMAGE, global_position)
