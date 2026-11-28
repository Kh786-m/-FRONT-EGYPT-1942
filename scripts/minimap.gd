extends Control
## Top-down minimap: map bounds, current zone (ember), next zone (bone), player arrow,
## and an arrow on the rim pointing to the zone centre when the player is outside it.

const INK := Color("#1A1612")
const SAND := Color("#E4D2B0")
const BONE := Color("#F3E6D0")
const EMBER := Color("#E24A1B")
const BRASS := Color("#C6A15B")
const KHAKI := Color("#8A7048")
const WORLD_HALF := 90.0

var game: Node


func _process(_delta: float) -> void:
	queue_redraw()


func _to_map(p: Vector2) -> Vector2:
	return size * 0.5 + p / WORLD_HALF * (size.x * 0.5)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(INK, 0.72))
	draw_rect(Rect2(Vector2.ZERO, size), Color(KHAKI, 0.25).lerp(SAND, 0.15), true)
	draw_rect(Rect2(Vector2.ZERO, size), BRASS, false, 2.0)
	if game == null or game.zone == null or game.player == null:
		return
	var scale_k := size.x * 0.5 / WORLD_HALF
	var zone = game.zone
	if not zone.finished and zone.target_radius < zone.radius - 0.5:
		draw_arc(_to_map(zone.target_center), zone.target_radius * scale_k, 0, TAU, 64, Color(BONE, 0.9), 1.5)
	draw_arc(_to_map(zone.center), zone.radius * scale_k, 0, TAU, 72, EMBER, 2.5)
	# Loot crates as tiny brass dots.
	for c in game.loot_crates:
		if is_instance_valid(c):
			draw_rect(Rect2(_to_map(Vector2(c.global_position.x, c.global_position.z)) - Vector2(1.5, 1.5), Vector2(3, 3)), Color(BRASS, 0.85))
	var pp: Vector3 = game.player.global_position
	var p2 := _to_map(Vector2(pp.x, pp.z))
	# Player arrow: forward is -Z of the player body.
	var fwd3: Vector3 = -game.player.global_transform.basis.z
	var fwd := Vector2(fwd3.x, fwd3.z).normalized()
	var side := Vector2(-fwd.y, fwd.x)
	draw_colored_polygon(PackedVector2Array([p2 + fwd * 8.0, p2 - fwd * 5.0 + side * 5.0, p2 - fwd * 5.0 - side * 5.0]), BONE)
	# Outside the zone: draw a line toward the centre.
	if not zone.is_inside(pp):
		var c2 := _to_map(zone.center)
		draw_dashed_line(p2, c2, Color(EMBER, 0.9), 2.0, 5.0)
