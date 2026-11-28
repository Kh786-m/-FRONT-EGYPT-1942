extends RefCounted
## HARAQ cover map: candidate hiding spots around every obstacle tall enough to stop a bullet
## (rocks, ruins, walls, sandbag pits, wrecks, houses). Each spot knows which way its cover
## faces, so a soldier can pick one that puts the obstacle between it and its threat, plus a
## "peek" spot to the side from where it can shoot back. Spots are reserved so two soldiers
## don't pile into the same one.

const MIN_HEIGHT := 0.9
const OFFSET := 0.85
const SPACING := 1.8
const BUCKET := 8.0

var points: Array = [] # [{p: Vector3, n: Vector3 (outward from cover), t: Vector3 (along cover)}]
var _buckets := {}
var _reserved := {} # point index -> soldier instance id
var searches := 0


func build(obstacles: Array, nav, terrain_height: Callable) -> void:
	points.clear()
	_buckets.clear()
	for o in obstacles:
		var box: AABB = o
		var c := box.get_center()
		var ground: float = terrain_height.call(c.x, c.z)
		if box.end.y - ground < MIN_HEIGHT or box.size.x > 30.0 or box.size.z > 30.0:
			continue
		var sides := [
			[Vector3(box.position.x, 0, box.position.z), Vector3(box.end.x, 0, box.position.z), Vector3(0, 0, -1)],
			[Vector3(box.end.x, 0, box.position.z), Vector3(box.end.x, 0, box.end.z), Vector3(1, 0, 0)],
			[Vector3(box.end.x, 0, box.end.z), Vector3(box.position.x, 0, box.end.z), Vector3(0, 0, 1)],
			[Vector3(box.position.x, 0, box.end.z), Vector3(box.position.x, 0, box.position.z), Vector3(-1, 0, 0)],
		]
		for s in sides:
			var a: Vector3 = s[0]
			var b: Vector3 = s[1]
			var n: Vector3 = s[2]
			var length := a.distance_to(b)
			var count := maxi(1, int(length / SPACING))
			for i in range(count):
				var t := (float(i) + 0.5) / float(count)
				var p: Vector3 = a.lerp(b, t) + n * (OFFSET + float(nav.CLEARANCE))
				if absf(p.x) > 86.0 or absf(p.z) > 86.0 or not nav.is_walkable(p):
					continue
				var idx := points.size()
				points.append({"p": p, "n": n, "t": (b - a).normalized()})
				var key := Vector2i(floori(p.x / BUCKET), floori(p.z / BUCKET))
				if not _buckets.has(key):
					_buckets[key] = []
				_buckets[key].append(idx)


## Best cover spot near `from` that hides from `threat`. Returns {} or {"i", "p", "peek"}.
func find(from: Vector3, threat: Vector3, who: Object, nav, max_dist := 14.0) -> Dictionary:
	searches += 1
	var best := {}
	var best_score := INF
	var kb := Vector2i(floori(from.x / BUCKET), floori(from.z / BUCKET))
	var r := ceili(max_dist / BUCKET)
	var me := who.get_instance_id()
	for bx in range(kb.x - r, kb.x + r + 1):
		for bz in range(kb.y - r, kb.y + r + 1):
			for idx in _buckets.get(Vector2i(bx, bz), []):
				var sp: Dictionary = points[idx]
				var p: Vector3 = sp["p"]
				var d := Vector2(p.x - from.x, p.z - from.z).length()
				if d > max_dist:
					continue
				var owner = _reserved.get(idx, 0)
				if owner != 0 and owner != me and is_instance_id_valid(owner):
					continue
				var td := Vector3(threat.x - p.x, 0, threat.z - p.z)
				var tdist := td.length()
				if tdist < 4.0:
					continue
				td /= tdist
				var n: Vector3 = sp["n"]
				# The cover must sit between the spot and the threat.
				if n.dot(td) > -0.35:
					continue
				var score := d + absf(n.dot(td) + 1.0) * 3.0 + (6.0 if tdist < 8.0 else 0.0)
				if score >= best_score:
					continue
				if nav.line_clear(p, threat):
					continue
				best_score = score
				best = {"i": idx, "p": p}
	if best.is_empty():
		return best
	var sp2: Dictionary = points[best["i"]]
	var base: Vector3 = sp2["p"]
	var tan: Vector3 = sp2["t"]
	var peek := base + tan * 1.5
	for cand in [base + tan * 1.5, base - tan * 1.5, base + tan * 2.4, base - tan * 2.4]:
		if nav.is_walkable(cand) and nav.line_clear(cand, threat):
			peek = cand
			break
	best["peek"] = peek
	release(who)
	_reserved[best["i"]] = me
	return best


func release(who: Object) -> void:
	var me := who.get_instance_id()
	for k in _reserved.keys():
		if _reserved[k] == me:
			_reserved.erase(k)


func reserved_count() -> int:
	return _reserved.size()
