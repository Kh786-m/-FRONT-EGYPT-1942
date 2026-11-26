extends Node3D
## HARAQ shrinking zone ("الدايرة"): phases of WAIT -> SHRINK toward a random centre
## inside the current circle. Outside the circle you take damage that ramps per phase.

signal phase_changed(phase: int, shrinking: bool)

## [wait seconds, shrink seconds, end radius, damage per second outside during/after this phase]
## Total ~5.3 minutes; the last phase closes completely so a match always ends.
const PHASES := [
	[50.0, 40.0, 80.0, 2.0],
	[40.0, 35.0, 48.0, 4.0],
	[30.0, 30.0, 26.0, 7.0],
	[25.0, 25.0, 12.0, 11.0],
	[20.0, 25.0, 0.0, 18.0],
]
const START_RADIUS := 130.0
const MAP_HALF := 82.0
const WALL_HEIGHT := 70.0

var center := Vector2.ZERO
var radius := START_RADIUS
var target_center := Vector2.ZERO
var target_radius := START_RADIUS
var phase := 0 ## 0-based index into PHASES; == PHASES.size() when finished
var shrinking := false
var timer := 0.0
var finished := false
var rng := RandomNumberGenerator.new()

var _from_center := Vector2.ZERO
var _from_radius := START_RADIUS
var _wall: MeshInstance3D
var _target_ring: MeshInstance3D


func _ready() -> void:
	rng.randomize()
	_wall = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = WALL_HEIGHT
	cyl.radial_segments = 96
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	_wall.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(Color("#E24A1B"), 0.17)
	mat.disable_receive_shadows = true
	_wall.material_override = mat
	_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_wall)
	# Thin bone-coloured ring on the ground marking where the circle will close to next.
	_target_ring = MeshInstance3D.new()
	var ring := CylinderMesh.new()
	ring.top_radius = 1.0
	ring.bottom_radius = 1.0
	ring.height = 3.0
	ring.radial_segments = 96
	ring.rings = 1
	ring.cap_top = false
	ring.cap_bottom = false
	_target_ring.mesh = ring
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rmat.albedo_color = Color(Color("#F3E6D0"), 0.55)
	_target_ring.material_override = rmat
	_target_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_target_ring)
	_begin_phase(0)


func _begin_phase(index: int) -> void:
	phase = index
	shrinking = false
	_from_center = center
	_from_radius = radius
	if phase >= PHASES.size():
		finished = true
		timer = 0.0
		target_center = center
		target_radius = radius
		_update_visuals()
		return
	timer = PHASES[phase][0]
	target_radius = PHASES[phase][2]
	# Random new centre such that the new circle fits inside the current one (and the map).
	var slack := maxf(0.0, radius - target_radius)
	var tries := 0
	while true:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * slack
		target_center = center + Vector2(cos(a), sin(a)) * d
		tries += 1
		if (absf(target_center.x) + target_radius * 0.5 < MAP_HALF and absf(target_center.y) + target_radius * 0.5 < MAP_HALF) or tries > 30:
			break
	target_center = target_center.clamp(Vector2(-MAP_HALF + 6, -MAP_HALF + 6), Vector2(MAP_HALF - 6, MAP_HALF - 6))
	phase_changed.emit(phase, false)
	_update_visuals()


func tick(delta: float) -> void:
	if finished:
		return
	timer -= delta
	if not shrinking:
		if timer <= 0.0:
			shrinking = true
			timer = PHASES[phase][1]
			phase_changed.emit(phase, true)
	else:
		var total: float = PHASES[phase][1]
		var t := clampf(1.0 - timer / total, 0.0, 1.0)
		center = _from_center.lerp(target_center, t)
		radius = lerpf(_from_radius, target_radius, t)
		if timer <= 0.0:
			center = target_center
			radius = target_radius
			_begin_phase(phase + 1)
	_update_visuals()


func _update_visuals() -> void:
	_wall.position = Vector3(center.x, WALL_HEIGHT * 0.5 - 2.0, center.y)
	_wall.scale = Vector3(radius, 1.0, radius)
	_target_ring.visible = not finished and target_radius < radius - 0.5
	_target_ring.position = Vector3(target_center.x, 0.0, target_center.y)
	_target_ring.scale = Vector3(target_radius, 1.0, target_radius)


func distance_outside(pos: Vector3) -> float:
	return Vector2(pos.x, pos.z).distance_to(center) - radius


func is_inside(pos: Vector3) -> bool:
	return distance_outside(pos) <= 0.0


## Damage per second applied to anyone outside the circle right now.
func damage_per_second() -> float:
	if phase == 0 and not shrinking:
		return PHASES[0][3]
	var i := mini(phase, PHASES.size() - 1)
	if not shrinking and not finished and phase > 0:
		i = phase - 1
	return PHASES[i][3]


## A random point inside the circle the zone is closing toward (good place for AI to head).
func random_point_in_target(margin := 0.7) -> Vector3:
	var a := randf() * TAU
	var d := sqrt(randf()) * target_radius * margin
	return Vector3(target_center.x + cos(a) * d, 0.05, target_center.y + sin(a) * d)


func phase_number() -> int:
	return mini(phase + 1, PHASES.size())


func status_text() -> String:
	var secs := maxi(0, ceili(timer))
	var clock := "%d:%02d" % [int(secs / 60.0), secs % 60]
	if finished:
		return "الدايرة الأخيرة  |  FINAL CIRCLE"
	if shrinking:
		return "المرحلة %d/%d  |  المنطقة بتضيق  %s" % [phase_number(), PHASES.size(), clock]
	return "المرحلة %d/%d  |  الدايرة هتضيق بعد  %s" % [phase_number(), PHASES.size(), clock]
