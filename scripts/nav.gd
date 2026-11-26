extends RefCounted
## HARAQ navigation grid: a 1 m AStarGrid2D over the 180 x 180 m arena, built from the same
## obstacle footprints the world generator registers (rocks, ruins, walls, wrecks, sandbag pits,
## market houses). Building it takes a few milliseconds, so it is done at load time on the phone
## instead of baking a NavigationMesh. Paths are string-pulled so soldiers walk natural lines
## around cover instead of zig-zagging cell by cell.

const HALF := 90
const CELL := 1.0
## Extra clearance around every obstacle (soldier capsule radius + a little margin).
const CLEARANCE := 0.55
## Obstacles lower than this (road tiles, low rubble) are walkable.
const MIN_BLOCK_HEIGHT := 0.45

var grid := AStarGrid2D.new()
var size := HALF * 2
var solid_count := 0
var path_requests := 0
## Cells a soldier bumped into that the static map does not know about (another soldier, a
## crate, a collider without a footprint). They block planning for a while, then clear.
var _temp_blocks := {}
var temp_blocks_total := 0


func build(obstacles: Array, terrain_height: Callable) -> void:
	grid.region = Rect2i(0, 0, size, size)
	grid.cell_size = Vector2(CELL, CELL)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	solid_count = 0
	for o in obstacles:
		var box: AABB = o
		var cx := box.position.x + box.size.x * 0.5
		var cz := box.position.z + box.size.z * 0.5
		var ground: float = terrain_height.call(cx, cz)
		if box.end.y - ground < MIN_BLOCK_HEIGHT:
			continue
		var c0 := cell_of(Vector3(box.position.x - CLEARANCE, 0, box.position.z - CLEARANCE))
		var c1 := cell_of(Vector3(box.end.x + CLEARANCE, 0, box.end.z + CLEARANCE))
		for x in range(c0.x, c1.x + 1):
			for z in range(c0.y, c1.y + 1):
				var c := Vector2i(x, z)
				if grid.is_in_boundsv(c) and not grid.is_point_solid(c):
					grid.set_point_solid(c, true)
					solid_count += 1
	# Map edge (the invisible boundary walls).
	for i in range(size):
		for c in [Vector2i(i, 0), Vector2i(i, size - 1), Vector2i(0, i), Vector2i(size - 1, i)]:
			if not grid.is_point_solid(c):
				grid.set_point_solid(c, true)
				solid_count += 1


func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(clampi(floori((p.x + HALF) / CELL), 0, size - 1), clampi(floori((p.z + HALF) / CELL), 0, size - 1))


func world_of(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * CELL - HALF, 0.0, (c.y + 0.5) * CELL - HALF)


func is_walkable(p: Vector3) -> bool:
	return not grid.is_point_solid(cell_of(p))


## Closest walkable cell to `c` (spiral search), or `c` itself if nothing is free nearby.
func nearest_free(c: Vector2i, max_r := 8) -> Vector2i:
	if not grid.is_point_solid(c):
		return c
	for r in range(1, max_r + 1):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for x in range(c.x - r, c.x + r + 1):
			for z in [c.y - r, c.y + r]:
				var q := Vector2i(x, z)
				if grid.is_in_boundsv(q) and not grid.is_point_solid(q) and Vector2(q - c).length_squared() < best_d:
					best = q
					best_d = Vector2(q - c).length_squared()
		for z in range(c.y - r + 1, c.y + r):
			for x in [c.x - r, c.x + r]:
				var q := Vector2i(x, z)
				if grid.is_in_boundsv(q) and not grid.is_point_solid(q) and Vector2(q - c).length_squared() < best_d:
					best = q
					best_d = Vector2(q - c).length_squared()
		if best.x >= 0:
			return best
	return c


func nearest_free_point(p: Vector3) -> Vector3:
	var c := cell_of(p)
	if not grid.is_point_solid(c):
		return p
	var w := world_of(nearest_free(c))
	return Vector3(w.x, p.y, w.z)


## True if a soldier can walk the straight line a -> b without entering a blocked cell.
func line_clear(a: Vector3, b: Vector3) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var length := d.length()
	var steps := maxi(1, ceili(length / (CELL * 0.4)))
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var c := cell_of(Vector3(a.x + d.x * t, 0, a.z + d.y * t))
		if grid.is_point_solid(c):
			return false
	return true


## Walkable path from `from` to `to` as world points (y = 0; callers keep their own height).
## The first point is the first corner to head for; the last is the (snapped) goal.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	path_requests += 1
	var out := PackedVector3Array()
	var goal := nearest_free_point(to)
	if line_clear(from, goal):
		out.append(Vector3(goal.x, 0, goal.z))
		return out
	var a := nearest_free(cell_of(from))
	var b := nearest_free(cell_of(goal))
	var ids: Array[Vector2i] = grid.get_id_path(a, b, true)
	if ids.is_empty():
		out.append(Vector3(goal.x, 0, goal.z))
		return out
	# String pulling: from each anchor jump to the farthest cell still in straight sight.
	var anchor := Vector3(from.x, 0, from.z)
	var i := 0
	while i < ids.size() - 1:
		var j := i + 1
		while j + 1 < ids.size() and line_clear(anchor, world_of(ids[j + 1])):
			j += 1
		var p := world_of(ids[j])
		out.append(p)
		anchor = p
		i = j
	if out.is_empty() or b == cell_of(goal):
		if out.size() > 0:
			out.remove_at(out.size() - 1)
		out.append(Vector3(goal.x, 0, goal.z))
	return out


## Mark the cell at `p` as blocked for `seconds` (used by stuck recovery).
func block_temporarily(p: Vector3, now: float, seconds := 15.0) -> void:
	var c := cell_of(p)
	if grid.is_point_solid(c):
		return
	grid.set_point_solid(c, true)
	_temp_blocks[c] = now + seconds
	temp_blocks_total += 1


## Release temporary blocks whose time is up.
func tick(now: float) -> void:
	if _temp_blocks.is_empty():
		return
	for c in _temp_blocks.keys():
		if now >= float(_temp_blocks[c]):
			grid.set_point_solid(c, false)
			_temp_blocks.erase(c)
