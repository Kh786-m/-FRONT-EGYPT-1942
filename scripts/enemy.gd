extends CharacterBody3D
## Simple enemy soldier AI: patrol -> detect (range + line of sight) -> chase -> shoot (hitscan).

signal died(enemy: CharacterBody3D)

enum State { PATROL, CHASE }

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

var game: Node3D
var hit_points := 3
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
	_add_box(Vector3(0, 0.85, 0), Vector3(0.75, 1.3, 0.5), uniform)
	_add_box(Vector3(0, 1.62, 0), Vector3(0.38, 0.36, 0.36), uniform)
	_add_box(Vector3(0, 1.84, 0), Vector3(0.52, 0.14, 0.52), helmet)
	_add_box(Vector3(0.22, 1.15, -0.45), Vector3(0.1, 0.12, 0.8), metal)
	_muzzle = OmniLight3D.new()
	_muzzle.light_color = Color("#E24A1B")
	_muzzle.light_energy = 0.0
	_muzzle.omni_range = 3.5
	_muzzle.position = Vector3(0.22, 1.15, -0.95)
	add_child(_muzzle)
	_flash_mesh = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.09
	s.height = 0.18
	_flash_mesh.mesh = s
	_flash_mesh.material_override = ember
	_flash_mesh.position = _muzzle.position
	_flash_mesh.visible = false
	add_child(_flash_mesh)


func _add_box(pos: Vector3, size: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	m.position = pos
	add_child(m)


## Called by the player's weapon. Returns true if this hit killed the enemy.
func take_hit(damage: int) -> bool:
	if hit_points <= 0:
		return false
	hit_points -= damage
	alert()
	if hit_points <= 0:
		died.emit(self)
		queue_free()
		return true
	return false


func alert() -> void:
	if game and is_instance_valid(game.player):
		_last_known = game.player.global_position
	state = State.CHASE
	_lost_timer = 0.0


func _physics_process(delta: float) -> void:
	_muzzle.light_energy = move_toward(_muzzle.light_energy, 0.0, delta * 30.0)
	_flash_mesh.visible = _muzzle.light_energy > 0.5
	if game == null or not game.is_playing():
		velocity = Vector3.ZERO
		return
	_clock += delta
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
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
	match state:
		State.PATROL:
			if _can_see:
				alert()
			var goal := origin + patrol_axis * sin(_clock * 0.5 + patrol_phase) * 3.0
			var to_goal := goal - global_position
			to_goal.y = 0.0
			if to_goal.length() > 0.2:
				move_dir = to_goal.normalized()
				speed = PATROL_SPEED if to_goal.length() < 4.0 else CHASE_SPEED * 0.7
		State.CHASE:
			if _can_see:
				_last_known = player.global_position
				_lost_timer = 0.0
				_face(to_player, delta)
				if dist > KEEP_DISTANCE:
					move_dir = to_player.normalized()
					speed = CHASE_SPEED
				if dist < ATTACK_RANGE and _fire_cooldown <= 0.0:
					_shoot(dist)
			else:
				_lost_timer += delta
				var to_last := _last_known - global_position
				to_last.y = 0.0
				if to_last.length() > 1.0:
					move_dir = to_last.normalized()
					speed = CHASE_SPEED
				if _lost_timer > LOSE_SIGHT_TIME:
					state = State.PATROL
	if move_dir != Vector3.ZERO and not (state == State.CHASE and _can_see):
		_face(move_dir, delta)
	velocity.x = move_dir.x * speed
	velocity.z = move_dir.z * speed
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()


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
	var chance := BASE_HIT_CHANCE * clampf(1.25 - dist / ATTACK_RANGE, 0.3, 1.0)
	if game.is_player_moving_fast():
		chance *= 0.6
	if randf() < chance:
		game.damage_player(DAMAGE, global_position)
