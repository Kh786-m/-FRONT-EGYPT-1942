extends "res://scripts/missions/mission_base.gd"
## Mission 1 — the original prototype map (desert outpost near El Alamein),
## now running on the shared mission controller with patrol AI.

## Tutorial-level tuning: shorter sight, slower and weaker return fire.
func _spawn_enemy(pos: Vector3, route: Array) -> PatrolEnemy:
	var e := super._spawn_enemy(pos, route)
	e.view_range = 22.0
	e.fire_interval = 1.8
	e.damage = 5
	return e
