extends Node3D
## Close-up model showcase (same scene for before/after): -- --out=DIR --tag=before|after
var out := "/workspace/haraq-shots-v5"
var tag := "after"
var cam: Camera3D
var t := 0
var shots := []
var si := 0

func _ready():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--tag="): tag = a.substr(6)
	var Props = load("res://scripts/props.gd")
	var Weapons = load("res://scripts/weapons.gd")
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#E4D2B0").lerp(Color("#1E4C5A"), 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#E4D2B0")
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.0
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_energy = 1.4
	sun.light_color = Color(1.0, 0.92, 0.78)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var G = load("res://scripts/graphics.gd")
	ground.material_override = G.pbr("sand", Color(1, 0.95, 0.85), 0.3)
	add_child(ground)
	get_viewport().msaa_3d = Viewport.MSAA_4X
	# Tanks side by side (terrain height is ~0 far from the arena? use x=200 band and offset).
	var T = load("res://scripts/terrain.gd")
	var t0 = Props.add_tank(self, Vector3(0, 0, 0), 0.0, 0)
	var t1 = Props.add_tank(self, Vector3(0, 0, 9), 0.0, 1)
	for tk in [t0, t1]:
		tk.position.y = 0.0
		tk.rotation = Vector3.ZERO
	t1.position = Vector3(0, 0, 9)
	# Guns on a rack (y=1.0), in a row, side view.
	var guns := ["webley", "lee_enfield", "thompson", "mp40"]
	for i in range(guns.size()):
		var h := Node3D.new()
		add_child(h)
		h.position = Vector3(30 + [0.0, 0.0, 0.0, 0.0][i], 1.0 + 0.0, -0.6 * i - 0.0)
		h.position = Vector3(30, 1.0 + 0.32 * (3 - i), 0)
		h.rotation.y = PI * 0.5  # barrel (-Z) points to +X
		Weapons.build_model(guns[i], h, 1.0, true)
	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	shots = [
		["tank_panzer", Vector3(6.5, 2.6, 5.5), Vector3(0, 1.0, 0)],
		["tank_panzer_close", Vector3(3.6, 1.3, 3.1), Vector3(1.0, 0.8, 1.0)],
		["tank_crusader", Vector3(6.5, 2.6, 14.5), Vector3(0, 1.0, 9)],
		["tank_crusader_close", Vector3(-2.2, 1.2, 12.2), Vector3(-1.2, 0.7, 10.2)],
		["guns_side", Vector3(30.1, 1.5, 3.3), Vector3(30.1, 1.5, 0)],
		["guns_angle", Vector3(31.8, 2.3, 2.4), Vector3(30.1, 1.45, 0)],
	]

func _process(_d):
	t += 1
	if t % 20 == 1 and si < shots.size():
		var s = shots[si]
		cam.global_position = s[1]
		cam.look_at(s[2])
		cam.fov = 30 if s[0].begins_with("guns") else 40
	if t % 20 == 18 and si < shots.size():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, tag, shots[si][0]])
		print("saved ", shots[si][0])
		si += 1
		if si >= shots.size():
			get_tree().quit()
