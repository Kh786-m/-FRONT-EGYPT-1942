class_name PatrolEnemy
extends CharacterBody3D
## Enemy patrol soldier: follows a waypoint loop, spots the player inside a
## view cone with line of sight, turns, and returns fire (hit chance falls off
## with distance and when the player aims/sprints). Loses the player -> searches
## the last known spot -> returns to the route. Upgrade of the zip's sine-wave
## "patrol targets" (Enemy Patrol Upgrade).

enum State { PATROL, ALERT, SEARCH }

@export var waypoints: Array[Vector3] = []
@export var walk_speed := 2.2
@export var run_speed := 3.6
@export var view_range := 30.0
@export var view_cos := 0.45
@export var fire_interval := 1.3
@export var damage := 7
@export var hit_points := 3

var state: int = State.PATROL
var mission: Node
var model: SoldierModel
var _wp := 0
var _fire_t := 0.0
var _last_seen := Vector3.ZERO
var _search_t := 0.0
var _think_t := 0.0
var _flash: OmniLight3D

func setup(owner_mission: Node) -> void:
	mission = owner_mission

func _ready() -> void:
	set_meta("target", true)
	set_meta("hit_points", hit_points)
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	model = SoldierModel.new(SoldierModel.Kind.AXIS)
	add_child(model)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1, 0.7, 0.3)
	_flash.light_energy = 0.0
	_flash.omni_range = 3.0
	_flash.position = Vector3(0.1, 1.4, -0.9)
	add_child(_flash)
	_fire_t = randf_range(0.4, fire_interval)

func take_hit(amount: int) -> bool:
	hit_points -= amount
	set_meta("hit_points", hit_points)
	if mission and mission.player:
		_last_seen = mission.player.global_position
		state = State.ALERT
	if hit_points <= 0:
		_die()
		return true
	return false

func _die() -> void:
	set_physics_process(false)
	remove_meta("target")
	for c in get_children():
		if c is CollisionShape3D: c.set_deferred("disabled", true)
	var tw := create_tween()
	tw.tween_property(model, "rotation:x", deg_to_rad(-88), 0.45).set_trans(Tween.TRANS_QUAD)
	tw.tween_interval(2.0)
	tw.tween_property(model, "position:y", -1.0, 0.8)
	tw.tween_callback(queue_free)

func _can_see_player() -> bool:
	if mission == null or mission.player == null: return false
	var eye := global_position + Vector3(0, 1.6, 0)
	var target: Vector3 = mission.player.global_position + Vector3(0, 1.4, 0)
	var to := target - eye
	var dist := to.length()
	if dist > view_range: return false
	var fwd := -global_transform.basis.z
	if state == State.PATROL and fwd.dot(to.normalized()) < view_cos and dist > 6.0: return false
	var q := PhysicsRayQueryParameters3D.create(eye, target)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit.collider == mission.player

func _face(point: Vector3, delta: float) -> void:
	var flat := Vector3(point.x, global_position.y, point.z)
	if flat.distance_to(global_position) < 0.05: return
	var target_basis := Basis.looking_at((flat - global_position).normalized(), Vector3.UP)
	global_transform.basis = global_transform.basis.slerp(target_basis, clampf(delta * 6.0, 0.0, 1.0)).orthonormalized()

func _move_to(point: Vector3, speed: float, delta: float) -> bool:
	var to := Vector3(point.x - global_position.x, 0, point.z - global_position.z)
	if to.length() < 0.4:
		velocity.x = 0
		velocity.z = 0
		return true
	var d := to.normalized()
	velocity.x = d.x * speed
	velocity.z = d.z * speed
	_face(point, delta)
	return false

func _physics_process(delta: float) -> void:
	if mission == null or not mission.mission_started or mission.mission_over:
		model.set_motion(0.0)
		return
	if not is_on_floor(): velocity.y -= 24.0 * delta
	_think_t -= delta
	var sees := false
	if _think_t <= 0.0:
		_think_t = 0.2
		sees = _can_see_player()
		if sees:
			state = State.ALERT
			_last_seen = mission.player.global_position
		elif state == State.ALERT:
			state = State.SEARCH
			_search_t = 6.0
	match state:
		State.PATROL:
			if waypoints.size() > 0 and _move_to(waypoints[_wp], walk_speed, delta):
				_wp = (_wp + 1) % waypoints.size()
		State.ALERT:
			velocity.x = 0
			velocity.z = 0
			_face(mission.player.global_position, delta)
			_fire_t -= delta
			if _fire_t <= 0.0:
				_fire_t = fire_interval * randf_range(0.8, 1.25)
				_fire()
		State.SEARCH:
			_search_t -= delta
			if _move_to(_last_seen, run_speed, delta) or _search_t <= 0.0:
				state = State.PATROL
	_flash.light_energy = move_toward(_flash.light_energy, 0.0, delta * 30.0)
	model.set_motion(Vector2(velocity.x, velocity.z).length())
	move_and_slide()

func _fire() -> void:
	model.play_fire()
	_flash.light_energy = 2.5
	var dist := global_position.distance_to(mission.player.global_position)
	var chance := clampf(0.75 - dist / 45.0, 0.12, 0.7)
	if mission.aiming: chance *= 0.8
	if randf() < chance:
		mission.damage_player(damage)
