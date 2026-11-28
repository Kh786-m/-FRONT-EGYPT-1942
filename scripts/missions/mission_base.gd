extends Node3D
## Base FPS mission for WAR FRONT: EGYPT 1942.
## Refactored from the "Enemy Patrol Upgrade" prototype (scripts/game.gd):
## all prototype features are kept (touch + PC controls, 30/150 ammo, reload,
## aim, muzzle flash, hit marker, XP + coins, patrolling targets, hero intro,
## Egyptian market set dressing). New: overridable hooks so every map/mission
## reuses this controller, enemy return fire, mission complete / fail screens,
## pause menu, campaign progress, and a higher quality environment.

const WALK_SPEED := 6.5
const RUN_SPEED := 10.0
const JUMP_SPEED := 8.0
const MOUSE_SENS := 0.0025
const TOUCH_SENS := 0.0035
const MENU_SCENE := "res://scenes/main_menu.tscn"

var player: CharacterBody3D
var head: Node3D
var camera: Camera3D
var gun: Node3D
var hud: Label
var status: Label
var objective_label: Label
var joy_base: Control
var joy_knob: Control
var fire_button: Button
var jump_button: Button
var sprint_button: Button
var joystick_id := -1
var look_id := -1
var joystick_vector := Vector2.ZERO
var touch_last := Vector2.ZERO
var fire_held := false
var sprint_held := false
var cooldown := 0.0
var score := 0
var total_targets := 0
var experience_points := 0
var reward_coins := 0
var patrol_clock := 0.0
var targets: Array[Node3D] = []
var recoil := 0.0
var health := 100
var ammo := 30
var reserve_ammo := 150
var magazine_size := 30
var reload_timer := 0.0
var aiming := false
var hit_marker_timer := 0.0
var damage_flash_timer := 0.0
var since_damage := 99.0
var qa_bot := false
var hit_marker: Label
var damage_vignette: ColorRect
var reload_button: Button
var aim_button: Button
var shot_flash: OmniLight3D
var mission_started := false
var mission_over := false
var intro_overlay: Control
var end_overlay: Control
var end_title: Label
var end_body: Label
var pause_overlay: Control
var ui_root: Control

# ---------------------------------------------------------------- hooks
func _mission_id() -> String: return "m01_alamein_outpost"
func _mission_title() -> String: return "العلمين — نقطة الحراسة | Alamein Outpost"
func _briefing_text() -> String:
	return "قائد المهمة | العلمين - مصر 1942\nMission briefing: Secure the desert outpost.\nاهزم الدورية وأمّن الطريق لأهل البلد."
func _objective_text() -> String: return "OBJECTIVE: neutralize the patrol  |  الهدف: تحييد الدورية"
func _player_spawn() -> Vector3: return Vector3(0, 2, 12)
func _sky_preset() -> String: return "desert_noon"

func _ready() -> void:
	_create_environment()
	_create_world()
	_create_egyptian_life()
	_create_player()
	_create_targets()
	total_targets = targets.size()
	_create_ui()
	_create_muzzle_flash()
	_create_hero_intro()
	_create_end_overlay()
	_create_pause_overlay()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# QA / capture hook: `godot -- --autostart` skips the briefing screen.
	qa_bot = "--qa-bot" in OS.get_cmdline_user_args()
	if "--autostart" in OS.get_cmdline_user_args() or qa_bot:
		_start_hero_mission.call_deferred()

func material(color: Color, rough: float = 0.95, metal: float = 0.0) -> StandardMaterial3D:
	return LevelKit.mat(color, rough, metal)

func box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, solid := true) -> Node3D:
	return LevelKit.box(parent, pos, size, mat, solid)

func _create_environment() -> void:
	LevelKit.apply_environment(self, _sky_preset())

# ---------------------------------------------------------------- world (prototype map)
func _create_world() -> void:
	var sand := material(Color(0.69, 0.56, 0.37))
	var stone := material(Color(0.52, 0.44, 0.33))
	var stone2 := material(Color(0.62, 0.54, 0.40))
	var dark := material(Color(0.24, 0.24, 0.21))
	box(self, Vector3(0, -0.6, 0), Vector3(180, 1, 180), sand)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1942
	for i in range(75):
		var x := rng.randf_range(-76, 76)
		var z := rng.randf_range(-76, 76)
		if absf(x) < 10 and absf(z) < 10: continue
		var h := rng.randf_range(1.4, 5.5)
		if _near_patrol_ring(Vector3(x, 0, z)): continue
		box(self, Vector3(x, h / 2.0, z), Vector3(rng.randf_range(2.0, 6.0), h, rng.randf_range(2.0, 6.0)), stone if i % 2 == 0 else stone2)
	for i in range(18):
		var z := -55.0 + i * 6.0
		box(self, Vector3(-14, 1.2, z), Vector3(1.0, 2.4, 4.5), stone)
	for i in range(10):
		var x := -36.0 + i * 8.0
		box(self, Vector3(x, 0.6, -25), Vector3(3.5, 1.2, 1.8), dark)
	box(self, Vector3(17, 1.7, -10), Vector3(14, 3.4, 1.4), stone2)
	box(self, Vector3(23, 1.7, -20), Vector3(1.4, 3.4, 18), stone2)
	box(self, Vector3(-18, 1.3, 8), Vector3(11, 2.6, 1.2), stone)
	LevelKit.dunes(self, 1942, 26, 95.0, sand)

# Egyptian civilian atmosphere: fictional 1942-inspired market set dressing.
func _create_egyptian_life() -> void:
	var mud := material(Color(0.68, 0.51, 0.34))
	var wood := material(Color(0.31, 0.20, 0.12))
	var cloth := material(Color(0.65, 0.18, 0.11))
	var road := material(Color(0.49, 0.40, 0.29))
	box(self, Vector3(-33, 0.01, -17), Vector3(9, 0.05, 46), road, false)
	var names := ["قهوة المحروسة", "بقالة عم سيد", "ورشة أولاد النيل", "عيش بلدي", "سوق البلد"]
	for i in range(5):
		var z := -35.0 + float(i) * 9.0
		box(self, Vector3(-40, 2.0, z), Vector3(5, 4, 6), mud)
		box(self, Vector3(-37.3, 1.2, z), Vector3(0.3, 2.4, 1.5), wood, false)
		box(self, Vector3(-37.0, 2.6, z), Vector3(3, 0.18, 3), cloth, false)
		box(self, Vector3(-36.8, 0.6, z - 1.2), Vector3(1.4, 1.2, 0.6), wood)
		LevelKit.arabic_sign(self, names[i], Vector3(-36.9, 3.5, z), 90.0)
	for i in range(7):
		LevelKit.palm(self, Vector3(-23, 0, -38.0 + float(i) * 11.0))
	LevelKit.cart(self, Vector3(-28, 0, -6))

# Prototype targets now use the patrol AI actor (walks, spots, returns fire).
func _ring_point(i: int) -> Vector3:
	var angle := i * TAU / 12.0
	var radius := 20.0 + float(i % 4) * 7.0
	return Vector3(sin(angle) * radius, 0.1, cos(angle) * radius)

## Keeps the random ruins from spawning on top of a patrol route (the original
## prototype could bury targets inside walls, making the mission unwinnable).
func _near_patrol_ring(p: Vector3) -> bool:
	for i in range(12):
		var r := _ring_point(i)
		if Vector2(p.x - r.x, p.z - r.z).length() < 7.5: return true
	return false

func _create_targets() -> void:
	for i in range(12):
		var p := _ring_point(i)
		var axis := Vector3(1, 0, 0) if i % 2 == 0 else Vector3(0, 0, 1)
		_spawn_enemy(p, [p - axis * 2.5, p + axis * 2.5])

func _spawn_enemy(pos: Vector3, route: Array) -> PatrolEnemy:
	var e := PatrolEnemy.new()
	e.position = pos
	var pts: Array[Vector3] = []
	for r in route: pts.append(r)
	e.waypoints = pts
	add_child(e)
	e.setup(self)
	targets.append(e)
	return e

# ---------------------------------------------------------------- player
func _create_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.position = _player_spawn()
	add_child(player)
	var collider := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	collider.position.y = 0.9
	collider.shape = cap
	player.add_child(collider)
	head = Node3D.new()
	head.position.y = 1.62
	player.add_child(head)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 75
	camera.far = 900.0
	head.add_child(camera)
	gun = SoldierModel.build_rifle(true)
	gun.position = Vector3(0.24, -0.26, -0.7)
	gun.scale = Vector3.ONE * 0.8
	gun.rotation_degrees.y = 4
	camera.add_child(gun)

func _create_muzzle_flash() -> void:
	shot_flash = OmniLight3D.new()
	shot_flash.light_color = Color(1.0, 0.66, 0.28)
	shot_flash.light_energy = 0.0
	shot_flash.omni_range = 4.0
	camera.add_child(shot_flash)
	shot_flash.position = Vector3(0.25, -0.22, -0.9)

func _reload() -> void:
	if reload_timer > 0.0 or ammo >= magazine_size or reserve_ammo <= 0: return
	reload_timer = 1.8

func _finish_reload() -> void:
	var count := mini(magazine_size - ammo, reserve_ammo)
	ammo += count
	reserve_ammo -= count

func _toggle_aim() -> void:
	aiming = not aiming

## Called by enemies when their shot connects.
func damage_player(amount: int) -> void:
	if mission_over or not mission_started: return
	health = maxi(0, health - amount)
	damage_flash_timer = 0.25
	since_damage = 0.0
	if health <= 0: _finish_mission(false)

# ---------------------------------------------------------------- UI
func _create_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui_root = Control.new()
	var root := ui_root
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	layer.add_child(root)
	damage_vignette = ColorRect.new()
	damage_vignette.color = Color(0.7, 0.05, 0.02, 0.0)
	damage_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	damage_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(damage_vignette)
	hud = Label.new()
	hud.text = "WAR FRONT: EGYPT 1942  |  " + _mission_title()
	hud.position = Vector2(20, 14)
	hud.add_theme_font_size_override("font_size", 24)
	root.add_child(hud)
	status = Label.new()
	status.position = Vector2(20, 50)
	status.add_theme_font_size_override("font_size", 21)
	root.add_child(status)
	objective_label = Label.new()
	objective_label.text = _objective_text()
	objective_label.position = Vector2(20, 82)
	objective_label.add_theme_font_size_override("font_size", 19)
	objective_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	root.add_child(objective_label)
	var cross := Label.new()
	cross.text = "+"
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	cross.position = Vector2(-8, -18)
	cross.add_theme_font_size_override("font_size", 38)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cross)
	hit_marker = Label.new()
	hit_marker.text = "X"
	hit_marker.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hit_marker.position = Vector2(-9, -18)
	hit_marker.add_theme_font_size_override("font_size", 34)
	hit_marker.add_theme_color_override("font_color", Color(1.0, 0.25, 0.16))
	hit_marker.visible = false
	hit_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hit_marker)
	joy_base = ColorRect.new()
	joy_base.color = Color(0.9, 0.9, 0.9, 0.16)
	joy_base.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	joy_base.position = Vector2(45, -205)
	joy_base.size = Vector2(150, 150)
	joy_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(joy_base)
	joy_knob = ColorRect.new()
	joy_knob.color = Color(1, 1, 1, 0.43)
	joy_knob.position = Vector2(55, 55)
	joy_knob.size = Vector2(40, 40)
	joy_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joy_base.add_child(joy_knob)
	fire_button = _button(root, "FIRE", Vector2(-155, -185), Vector2(125, 125))
	fire_button.button_down.connect(func(): fire_held = true)
	fire_button.button_up.connect(func(): fire_held = false)
	jump_button = _button(root, "JUMP", Vector2(-290, -110), Vector2(115, 70))
	jump_button.pressed.connect(_jump)
	sprint_button = _button(root, "RUN", Vector2(-430, -110), Vector2(115, 70))
	sprint_button.button_down.connect(func(): sprint_held = true)
	sprint_button.button_up.connect(func(): sprint_held = false)
	reload_button = _button(root, "RELOAD", Vector2(-295, -200), Vector2(125, 65))
	reload_button.pressed.connect(_reload)
	aim_button = _button(root, "AIM", Vector2(-155, -265), Vector2(125, 65))
	aim_button.pressed.connect(_toggle_aim)
	var pause_btn := Button.new()
	pause_btn.text = "II"
	pause_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pause_btn.position = Vector2(-90, 14)
	pause_btn.size = Vector2(70, 56)
	pause_btn.pressed.connect(_toggle_pause)
	root.add_child(pause_btn)
	var mobile := OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	for c in [joy_base, fire_button, jump_button, sprint_button, reload_button, aim_button]:
		c.visible = mobile

func _button(parent: Control, label: String, offset: Vector2, dimensions: Vector2) -> Button:
	var b := Button.new()
	b.text = label
	b.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	b.position = offset
	b.size = dimensions
	b.add_theme_font_size_override("font_size", 23)
	parent.add_child(b)
	return b

func _overlay(color: Color) -> Control:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var o := ColorRect.new()
	o.color = color
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(o)
	return o

func _create_hero_intro() -> void:
	intro_overlay = _overlay(Color(0.035, 0.055, 0.075, 0.96))
	var layout := HBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 38)
	layout.offset_left = 65
	layout.offset_right = -65
	layout.offset_top = 55
	layout.offset_bottom = -55
	intro_overlay.add_child(layout)
	var portrait := TextureRect.new()
	if ResourceLoader.exists("res://assets/hero/khaled_portrait.jpg"):
		portrait.texture = load("res://assets/hero/khaled_portrait.jpg")
	portrait.custom_minimum_size = Vector2(330, 440)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	layout.add_child(portrait)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 20)
	layout.add_child(content)
	var title := Label.new()
	title.text = "WAR FRONT: EGYPT 1942"
	title.add_theme_font_size_override("font_size", 40)
	content.add_child(title)
	var hero := Label.new()
	hero.text = "خالد كارم عبداللا\nKHALED KAREM ABDALLA"
	hero.add_theme_font_size_override("font_size", 32)
	content.add_child(hero)
	var briefing := Label.new()
	briefing.text = _mission_title() + "\n" + _briefing_text()
	briefing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	briefing.add_theme_font_size_override("font_size", 23)
	content.add_child(briefing)
	var start := Button.new()
	start.text = "ابدأ المهمة  |  START MISSION"
	start.custom_minimum_size = Vector2(420, 82)
	start.add_theme_font_size_override("font_size", 28)
	content.add_child(start)
	start.pressed.connect(_start_hero_mission)

func _create_end_overlay() -> void:
	end_overlay = _overlay(Color(0.03, 0.04, 0.05, 0.92))
	end_overlay.visible = false
	var box_v := VBoxContainer.new()
	box_v.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box_v.custom_minimum_size = Vector2(640, 380)
	box_v.position = Vector2(-320, -190)
	box_v.add_theme_constant_override("separation", 18)
	end_overlay.add_child(box_v)
	end_title = Label.new()
	end_title.add_theme_font_size_override("font_size", 42)
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box_v.add_child(end_title)
	end_body = Label.new()
	end_body.add_theme_font_size_override("font_size", 22)
	end_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box_v.add_child(end_body)
	var retry := Button.new()
	retry.text = "إعادة | RETRY"
	retry.custom_minimum_size = Vector2(0, 70)
	retry.pressed.connect(func(): get_tree().reload_current_scene())
	box_v.add_child(retry)
	var menu := Button.new()
	menu.text = "الحملة | CAMPAIGN MENU"
	menu.custom_minimum_size = Vector2(0, 70)
	menu.pressed.connect(_go_menu)
	box_v.add_child(menu)

func _create_pause_overlay() -> void:
	pause_overlay = _overlay(Color(0, 0, 0, 0.7))
	pause_overlay.visible = false
	pause_overlay.get_parent().process_mode = Node.PROCESS_MODE_ALWAYS
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	v.position = Vector2(-220, -120)
	v.custom_minimum_size = Vector2(440, 240)
	v.add_theme_constant_override("separation", 16)
	pause_overlay.add_child(v)
	var resume := Button.new()
	resume.text = "متابعة | RESUME"
	resume.custom_minimum_size = Vector2(0, 70)
	resume.pressed.connect(_toggle_pause)
	v.add_child(resume)
	var menu := Button.new()
	menu.text = "الحملة | CAMPAIGN MENU"
	menu.custom_minimum_size = Vector2(0, 70)
	menu.pressed.connect(_go_menu)
	v.add_child(menu)

func _toggle_pause() -> void:
	if mission_over or not mission_started: return
	pause_overlay.visible = not pause_overlay.visible
	get_tree().paused = pause_overlay.visible
	if pause_overlay.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not OS.has_feature("mobile"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _go_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)

func _start_hero_mission() -> void:
	mission_started = true
	intro_overlay.get_parent().visible = false
	if not OS.has_feature("mobile"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _exit_tree() -> void:
	if "--report" in OS.get_cmdline_user_args():
		print("REPORT mission=%s hp=%d score=%d/%d over=%s" % [_mission_id(), health, score, total_targets, mission_over])

func _finish_mission(success: bool) -> void:
	if mission_over: return
	mission_over = true
	fire_held = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	end_overlay.visible = true
	if success:
		var stars := Campaign.complete_mission(_mission_id(), health, experience_points, reward_coins)
		end_title.text = "تمت المهمة | MISSION COMPLETE"
		end_body.text = "%s\nXP +%d   COINS +%d   HP %d\n%s" % [_mission_title(), experience_points, reward_coins, health, "★".repeat(stars) + "☆".repeat(3 - stars)]
	else:
		end_title.text = "فشلت المهمة | MISSION FAILED"
		end_body.text = "خالد اتصاب — خد ساتر واستخدم التصويب.\nKhaled is down. Use cover and aim."

# ---------------------------------------------------------------- input / loop
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_toggle_pause()
		return
	if not mission_started or mission_over: return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.relative * MOUSE_SENS)
	if event is InputEventKey and event.pressed and event.keycode == KEY_R: _reload()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed: _toggle_aim()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not OS.has_feature("mobile"):
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x < get_viewport().get_visible_rect().size.x * 0.36 and joystick_id == -1:
				joystick_id = event.index
				_update_joystick(event.position)
			elif look_id == -1 and event.position.x < get_viewport().get_visible_rect().size.x * 0.73:
				look_id = event.index
				touch_last = event.position
		else:
			if event.index == joystick_id:
				joystick_id = -1
				joystick_vector = Vector2.ZERO
				joy_knob.position = Vector2(55, 55)
			if event.index == look_id: look_id = -1
	if event is InputEventScreenDrag:
		if event.index == joystick_id: _update_joystick(event.position)
		elif event.index == look_id:
			_look(event.position - touch_last, TOUCH_SENS)
			touch_last = event.position

func _update_joystick(screen_pos: Vector2) -> void:
	var center := joy_base.global_position + joy_base.size / 2.0
	joystick_vector = ((screen_pos - center) / 70.0).limit_length(1.0)
	joy_knob.position = Vector2(55, 55) + joystick_vector * 50.0

func _look(delta: Vector2, sensitivity: float = 1.0) -> void:
	player.rotate_y(-delta.x * sensitivity)
	head.rotation.x = clampf(head.rotation.x - delta.y * sensitivity, -1.35, 1.35)

func _jump() -> void:
	if player.is_on_floor(): player.velocity.y = JUMP_SPEED

func _physics_process(delta: float) -> void:
	if not mission_started or mission_over: return
	patrol_clock += delta
	var axis := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if joystick_vector.length() > 0.1: axis = joystick_vector
	var dir := player.global_transform.basis * Vector3(axis.x, 0, axis.y)
	var speed := RUN_SPEED if sprint_held or Input.is_action_pressed("sprint") else WALK_SPEED
	if aiming: speed *= 0.55
	player.velocity.x = dir.x * speed
	player.velocity.z = dir.z * speed
	if not player.is_on_floor(): player.velocity.y -= 24.0 * delta
	if Input.is_action_just_pressed("jump"): _jump()
	player.move_and_slide()
	cooldown = maxf(0, cooldown - delta)
	if reload_timer > 0.0:
		reload_timer -= delta
		if reload_timer <= 0.0: _finish_reload()
	hit_marker_timer = maxf(0.0, hit_marker_timer - delta)
	hit_marker.visible = hit_marker_timer > 0.0
	damage_flash_timer = maxf(0.0, damage_flash_timer - delta)
	damage_vignette.color.a = damage_flash_timer * 1.4
	shot_flash.light_energy = move_toward(shot_flash.light_energy, 0.0, delta * 45.0)
	camera.fov = move_toward(camera.fov, 48.0 if aiming else 75.0, delta * 180.0)
	gun.position.x = move_toward(gun.position.x, 0.0 if aiming else 0.24, delta * 1.8)
	gun.position.z = move_toward(gun.position.z, -0.55 if aiming else -0.7, delta * 1.8)
	# Modern-shooter style regeneration after 5 s without taking damage.
	since_damage += delta
	if since_damage > 5.0 and health < 100:
		health = mini(100, health + int(ceil(10.0 * delta)))
	if qa_bot: _qa_bot_step()
	if fire_held or Input.is_action_pressed("fire"): _shoot()
	recoil = move_toward(recoil, 0, delta * 3.0)
	var bob := sin(patrol_clock * 9.0) * 0.012 * clampf(Vector2(player.velocity.x, player.velocity.z).length() / RUN_SPEED, 0.0, 1.0)
	gun.position.y = (-0.16 if aiming else -0.26) + recoil + bob
	status.text = "TARGETS %d/%d | HP %d | AMMO %d/%d | XP %d | COINS %d | FPS %d%s" % [score, total_targets, health, ammo, reserve_ammo, experience_points, reward_coins, Engine.get_frames_per_second(), "  | RELOADING" if reload_timer > 0 else ""]
	if total_targets > 0 and score >= total_targets: _finish_mission(true)

## QA only (`-- --qa-bot`): aim at the nearest target and fire, to smoke-test
## the full combat loop (hit -> kill -> XP -> mission complete) in CI.
func _qa_bot_step() -> void:
	var best: Node3D = null
	var best_d := 1e9
	for t in targets:
		if is_instance_valid(t) and t.has_meta("target"):
			var d := player.global_position.distance_to(t.global_position)
			if d < best_d:
				best_d = d
				best = t
	if best == null:
		fire_held = false
		return
	if best_d > 10.0:  # QA shortcut: hop next to the target (tests logic, not navigation)
		var away := (player.global_position - best.global_position)
		away.y = 0
		player.global_position = best.global_position + away.normalized() * 5.0 + Vector3(0, 0.5, 0)
	var aim_point := best.global_position + Vector3(0, 1.3, 0)
	var flat := Vector3(aim_point.x, player.global_position.y, aim_point.z)
	if flat.distance_to(player.global_position) > 0.1:
		player.look_at(flat, Vector3.UP)
	head.rotation.x = atan2(aim_point.y - camera.global_position.y, Vector2(aim_point.x - camera.global_position.x, aim_point.z - camera.global_position.z).length())
	aiming = true
	fire_held = true
	if ammo == 0 and reserve_ammo == 0: reserve_ammo = 150

func _shoot() -> void:
	if cooldown > 0 or reload_timer > 0: return
	if ammo <= 0:
		_reload()
		return
	ammo -= 1
	shot_flash.light_energy = 3.5
	cooldown = 0.14
	recoil = -0.05
	var origin := camera.global_position
	var spread := 0.0 if aiming else 0.012
	var fwd := -camera.global_transform.basis.z + Vector3(randf_range(-spread, spread), randf_range(-spread, spread), 0)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + fwd.normalized() * 220.0)
	query.exclude = [player.get_rid()]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty(): return
	LevelKit.impact_puff(self, result.position)
	var hit: Object = result.collider
	if hit is Node and hit.has_meta("target"):
		hit_marker_timer = 0.14
		var dead := false
		if hit.has_method("take_hit"):
			dead = hit.take_hit(1)
		else:
			var hp: int = hit.get_meta("hit_points") - 1
			hit.set_meta("hit_points", hp)
			dead = hp <= 0
			if dead: hit.queue_free()
		if dead:
			targets.erase(hit)
			score += 1
			experience_points += 25
			reward_coins += 10
