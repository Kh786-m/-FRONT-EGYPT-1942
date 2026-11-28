extends Node
## In-game screenshots on a phone aspect (run the window at 2400x1080) for before/after:
## -- --out=DIR --tag=before|after
var game
var t := 0
var out := "/workspace/haraq-shots-v5"
var tag := "after"
var overlay: Control
var step := 0
var plan := []

func _ready():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--tag="): tag = a.substr(6)
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	plan = ["intro", "hud", "zones", "tank0", "tank1", "gun_webley", "gun_lee_enfield", "gun_thompson", "gun_mp40", "ads"]

func _ground(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60, z), Vector3(x, -30, z))
	q.exclude = [game.player.get_rid()]
	var r = game.get_world_3d().direct_space_state.intersect_ray(q)
	return r.position.y if not r.is_empty() else 0.0

func _save(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, tag, n])
	print("saved ", n)

func _touch_ui_on() -> void:
	game.is_mobile = true
	for n in ["joy_base", "fire_button", "jump_button", "sprint_button", "reload_button", "aim_button", "swap_button", "interact_button", "heal_button"]:
		var c = game.get(n)
		if c:
			c.visible = true
	if game.has_method("layout_touch_controls"):
		game.layout_touch_controls(get_viewport().get_visible_rect().size)

func _touch_ui_hide() -> void:
	for n in ["joy_base", "fire_button", "jump_button", "sprint_button", "reload_button", "aim_button", "swap_button", "interact_button", "heal_button"]:
		var c = game.get(n)
		if c:
			c.visible = false

func _wreck(near: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := 1e9
	for c in game.get_children():
		if c is StaticBody3D and c.has_meta("metal"):
			var d: float = c.global_position.distance_to(near)
			if d < bd:
				bd = d
				best = c
	return best

func _look_at_point(from: Vector3, target: Vector3) -> void:
	game.player.global_position = from
	game.player.velocity = Vector3.ZERO
	var d := target - (from + Vector3(0, 1.62, 0))
	game.player.rotation.y = atan2(-d.x, -d.z)
	game.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())

func _setup(n: String) -> void:
	for e in game.enemies:
		e.set_physics_process(false)
	game.health = 100.0
	game.aiming = false
	if overlay:
		overlay.queue_free()
		overlay = null
	match n:
		"hud", "zones":
			game.player.global_position = Vector3(0, _ground(0, 16) + 0.05, 16)
			game.player.rotation.y = 0
			game.head.rotation.x = -0.05
			game.give_weapon("thompson")
			game.switch_to_slot(game.slots.find("thompson"))
			game.switch_timer = 0
			if n == "zones":
				_add_overlay()
		"tank0", "tank1":
			_touch_ui_hide()
			var w := _wreck(Vector3(32, 0, -46) if n == "tank0" else Vector3(-56, 0, 42))
			var c := w.global_position
			var fwd := w.global_transform.basis.x
			var side := w.global_transform.basis.z
			var p := c + fwd * 2.2 + side * 4.3
			_look_at_point(Vector3(p.x, _ground(p.x, p.z) + 0.05, p.z), c + Vector3(0, 1.0, 0))
			game.gun.visible = false
		_:
			game.gun.visible = true
			if n.begins_with("gun_") or n == "ads":
				_touch_ui_hide()
				var id := n.substr(4) if n != "ads" else "lee_enfield"
				game.player.global_position = Vector3(2, _ground(2, -16) + 0.05, -16)
				game.player.rotation.y = 0.3
				game.head.rotation.x = -0.3
				if not (id in game.slots):
					game.give_weapon(id)
				game.switch_to_slot(game.slots.find(id))
				game.switch_timer = 0
				game.aiming = n == "ads"

## Touch-zone map: green = drag-to-look, blue = movement stick, red = a button that ALSO
## starts a camera drag (the v0.4 overlap bug), brass outline = buttons.
func _add_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(overlay)
	overlay.draw.connect(_draw_zones)
	overlay.queue_redraw()

func _buttons() -> Array:
	var out_b := []
	for n in ["fire_button", "jump_button", "sprint_button", "reload_button", "aim_button", "swap_button", "interact_button", "heal_button"]:
		var c = game.get(n)
		if c and c.visible:
			out_b.append(c)
	return out_b

func _old_kind(p: Vector2, vp: Vector2) -> String:
	if p.x < vp.x * 0.36:
		return "joystick"
	if p.x < vp.x * 0.73:
		return "look"
	return "none"

func _draw_zones() -> void:
	var vp := overlay.get_viewport_rect().size
	var cell := 16.0
	var y := 0.0
	while y < vp.y:
		var x := 0.0
		while x < vp.x:
			var p := Vector2(x + cell * 0.5, y + cell * 0.5)
			var kind: String
			var on_button := false
			for b in _buttons():
				if b.get_global_rect().has_point(p):
					on_button = true
			if game.has_method("classify_touch"):
				kind = game.classify_touch(p)
			else:
				kind = _old_kind(p, vp)
				if on_button and kind == "look":
					kind = "conflict"
				elif on_button:
					kind = "button"
			var col := Color(0, 0, 0, 0)
			match kind:
				"look": col = Color(0.2, 0.75, 0.35, 0.28)
				"joystick": col = Color(0.12, 0.3, 0.9, 0.28)
				"conflict": col = Color(0.95, 0.1, 0.05, 0.6)
				"button": col = Color(0.78, 0.63, 0.36, 0.25)
			overlay.draw_rect(Rect2(x, y, cell, cell), col)
			x += cell
		y += cell
	for b in _buttons():
		overlay.draw_rect(b.get_global_rect(), Color("#C6A15B"), false, 3.0)

func _process(_d):
	t += 1
	if t == 30:
		await _save("intro")
	if t == 40:
		game._start_hero_mission()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_touch_ui_on()
	if t >= 50 and (t - 50) % 30 == 0:
		step = (t - 50) / 30 + 1
		if step >= plan.size():
			get_tree().quit()
			return
		_setup(plan[step])
	if t >= 50 and (t - 50) % 30 == 27 and step >= 1 and step < plan.size():
		game.player.velocity = Vector3.ZERO
		if plan[step] == "hud" or plan[step] == "zones":
			game._update_hud()
			if game.interact_button:
				game.interact_button.visible = true
		await _save(plan[step])
