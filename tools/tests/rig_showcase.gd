extends Node3D
## v0.7 rigged-soldier pose lineup:  godot --resolution 1920x1080 res://rig_showcase.tscn -- --out=DIR
var out := "/workspace/haraq-shots-v7"
var cam: Camera3D
var t := 0
var shots := []
var si := 0
const Rig := preload("res://scripts/soldier_rig.gd")
const Weapons := preload("res://scripts/weapons.gd")

func _ready():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	var G = load("res://scripts/graphics.gd")
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#E4D2B0").lerp(Color("#1E4C5A"), 0.15)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#E4D2B0")
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -30, 0)
	sun.light_energy = 1.4
	sun.light_color = Color(1.0, 0.92, 0.78)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	ground.material_override = G.pbr("sand", Color(0.8, 0.72, 0.6), 0.3)
	add_child(ground)
	get_viewport().msaa_3d = Viewport.MSAA_4X
	var uniform = G.pbr("linen", Color(0.74, 0.66, 0.48), 3.0, true, 0.95, 0.0, 0.9, false)
	var helmet = G.pbr("metal_rust", Color(0.56, 0.52, 0.4), 3.0, true, 0.6, 0.3, 0.5, false)
	var poses := [["idle", 0.0], ["walk", 0.3], ["run", 0.2], ["aim", 0.0], ["fire", 0.05], ["reload", 0.7], ["hit", 0.14], ["death", 0.55], ["death", 2.0]]
	for i in range(poses.size()):
		var r = Rig.new()
		add_child(r)
		r.build(i % 2, uniform, helmet)
		var gun := "lee_enfield" if i % 3 != 2 else ("thompson" if i % 2 == 0 else "mp40")
		Weapons.build_model(gun, r.gun_holder, 1.0, true)
		r.align_weapon(Weapons.DATA[gun]["grip"])
		r.position = Vector3((i - 4) * 1.25, 0, 0)
		r.rotation.y = -0.35
		r.set_process(false)
		var p: String = poses[i][0]
		var at: float = poses[i][1]
		var tr: AnimationTree = r.tree
		match p:
			"idle": tr.set("parameters/loco/blend_position", 0.0)
			"walk": tr.set("parameters/loco/blend_position", 1.6)
			"run": tr.set("parameters/loco/blend_position", 3.6)
			"aim", "fire": tr.set("parameters/aim/blend_amount", 1.0)
		tr.advance(0.5)
		if p == "fire": r.fire()
		if p == "reload": r.reload()
		if p == "hit": r.hit()
		if p == "death": r.die()
		tr.advance(0.0)
		var left := at
		while left > 0.0:
			var st := minf(left, 0.02)
			tr.advance(st)
			left -= st
	cam = Camera3D.new()
	cam.fov = 38
	add_child(cam)
	shots = [
		["poses_lineup", Vector3(0.6, 1.5, -9.2), Vector3(0.6, 0.85, 0)],
		["poses_close_left", Vector3(-3.0, 1.35, -3.6), Vector3(-3.0, 0.95, 0)],
		["poses_close_right", Vector3(2.6, 1.3, -3.6), Vector3(2.6, 0.75, 0)],
		["poses_side", Vector3(-7.5, 1.4, -2.5), Vector3(0, 0.8, 0)],
	]

func _process(_d):
	t += 1
	if t % 20 == 1 and si < shots.size():
		cam.global_position = shots[si][1]
		cam.look_at(shots[si][2])
	if t % 20 == 18 and si < shots.size():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, shots[si][0]])
		print("saved ", shots[si][0])
		si += 1
		if si >= shots.size():
			get_tree().quit()
