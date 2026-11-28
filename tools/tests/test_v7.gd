extends Node
## HARAQ v0.7.0 checks: rigged + animated soldiers (Skeleton3D / AnimationTree / LOD / death
## fall), recorded audio, and (see test_net.gd) LAN multiplayer.
## Run with:  godot --headless --path proj res://test_v7.tscn
var game
var fails := 0
var passes := 0
const T := preload("res://scripts/terrain.gd")
const Rig := preload("res://scripts/soldier_rig.gd")
const Weapons := preload("res://scripts/weapons.gd")

func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
		print("PASS ", msg)
	else:
		fails += 1
		print("FAIL ", msg)

func frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame

func pframes(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func place(e, p: Vector3) -> void:
	e.global_position = Vector3(p.x, T.height(p.x, p.z) + 0.2, p.z)
	e.velocity = Vector3.ZERO
	e._can_see = false
	e.target = null
	e._los_timer = 0.0

func _ready():
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await frames(5)
	game._start_hero_mission()
	await frames(2)
	_freeze_zone()
	_rig_static_checks()
	_pose_checks()
	await _rig_runtime_checks()
	await _lod_checks()
	await _death_checks()
	if has_method("_audio_checks"):
		await call("_audio_checks")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	print("RESULT passes=%d fails=%d" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)

func _freeze_zone() -> void:
	var zone = game.zone
	zone.target_center = Vector2.ZERO
	zone.target_radius = 500.0
	zone.radius = 500.0
	zone.center = Vector2.ZERO
	zone.shrinking = false
	zone.timer = 9999.0

# ------------------------------------------------------------------ rig: static
func _rig_static_checks() -> void:
	var bad := 0
	var meshes := {}
	for e in game.enemies:
		var r = e._body
		if r == null or r.skeleton == null or r.skeleton.get_bone_count() < 18 or r.tree == null or not r.tree.active:
			bad += 1
			continue
		meshes[r.body_mesh.mesh] = true
	check(bad == 0, "every soldier has a Skeleton3D rig (%d bones) and an active AnimationTree" % game.enemies[0]._body.skeleton.get_bone_count())
	check(meshes.size() == 2, "skinned soldier meshes are shared: 2 variants for %d soldiers (%d meshes)" % [game.enemies.size(), meshes.size()])
	var r0 = game.enemies[0]._body
	var r1 = game.enemies[1]._body
	check(r0.variant != r1.variant, "both looks used (Afrika Korps / 8th Army)")
	var m: ArrayMesh = r0.body_mesh.mesh
	var arr := m.surface_get_arrays(0)
	var bones = arr[Mesh.ARRAY_BONES]
	var weights = arr[Mesh.ARRAY_WEIGHTS]
	check(bones != null and bones.size() > 0 and weights != null and weights.size() == bones.size(), "body mesh is skinned (bone indices + weights)")
	check(r0.body_mesh.skin != null and r0.body_mesh.skin.get_bind_count() == r0.skeleton.get_bone_count(), "skin binds every bone")
	check(m.get_surface_count() <= 6, "one surface per material (%d surfaces = few draw calls)" % m.get_surface_count())
	var tris: int = int(m.get_meta("tris", 0))
	check(tris > 1200 and tris < 6000, "soldier is detailed but phone-friendly (%d triangles)" % tris)
	var lib: AnimationLibrary = r0.tree.get_animation_library("")
	var missing := []
	for a in Rig.ANIMS:
		if not lib.has_animation(a):
			missing.append(a)
	check(missing.is_empty(), "animations idle/walk/run/aim/fire/reload/hit/death exist %s" % [missing])
	check(r0.tree.get_animation_library("") == r1.tree.get_animation_library(""), "animation library built once and shared")
	check(lib.get_animation("walk").loop_mode == Animation.LOOP_LINEAR and lib.get_animation("death").loop_mode == Animation.LOOP_NONE, "loops: walk loops, death plays once")
	check(r0.tree.tree_root is AnimationNodeBlendTree and r0.tree.tree_root.has_node("loco") and r0.tree.tree_root.get_node("loco") is AnimationNodeBlendSpace1D, "AnimationTree blends idle/walk/run in a BlendSpace1D")
	check(r0.gun_holder.get_node_or_null("GunMesh") != null and r0.weapon_attach.bone_name == "weapon", "gun rides on the weapon bone")

# ------------------------------------------------------------------ rig: poses (pure math)
func _hand_err(spec: Dictionary) -> Array:
	var p: Dictionary = Rig.pose(spec)
	var g: Dictionary = Rig._fk(p)
	var w: Transform3D = g["weapon"]
	var grip: Vector3 = w * (Rig.GRIP + Vector3(0, 0.05, 0))
	var fore: Vector3 = w * (Rig.FORE + Vector3(0, 0.03, 0))
	var wr: Vector3 = (g["hand.R"] as Transform3D).origin
	var wl: Vector3 = (g["hand.L"] as Transform3D).origin
	return [wr.distance_to(grip), wl.distance_to(fore), g]

func _pose_checks() -> void:
	for n in ["ready", "aim", "run"]:
		var spec: Dictionary = Rig.idle_spec(0.0) if n == "ready" else (Rig.aim_spec(0.0) if n == "aim" else Rig.walk_spec(0.25, true))
		var r := _hand_err(spec)
		check(r[0] < 0.03 and r[1] < 0.06, "%s pose: hands on the weapon (IK error R %.3f m, L %.3f m)" % [n, r[0], r[1]])
	var ga: Dictionary = _hand_err(Rig.aim_spec(0.0))[2]
	var gi: Dictionary = _hand_err(Rig.idle_spec(0.0))[2]
	var head: Vector3 = (ga["head"] as Transform3D).origin
	var wa: Transform3D = ga["weapon"]
	check(wa.origin.y > (gi["weapon"] as Transform3D).origin.y + 0.25, "aim raises the weapon to the shoulder (%.2f m vs %.2f m)" % [wa.origin.y, (gi["weapon"] as Transform3D).origin.y])
	check(absf(wa.origin.y - head.y) < 0.2 and (-wa.basis.z).dot(Vector3.FORWARD) > 0.95, "aimed weapon is at eye level and points forward")
	var gd: Dictionary = Rig._fk(Rig.pose(Rig.death_spec(1.0)))
	check((gd["hips"] as Transform3D).origin.y < 0.3 and (gd["head"] as Transform3D).origin.y < 0.45, "death pose ends lying on the ground (hips %.2f m, head %.2f m)" % [(gd["hips"] as Transform3D).origin.y, (gd["head"] as Transform3D).origin.y])
	var g0: Dictionary = Rig._fk(Rig.pose(Rig.walk_spec(0.0, false)))
	var g1: Dictionary = Rig._fk(Rig.pose(Rig.walk_spec(0.25, false)))
	check((g0["foot.R"] as Transform3D).origin.distance_to((g1["foot.R"] as Transform3D).origin) > 0.15, "walk cycle swings the legs")
	var lowest := 9.0
	for i in range(8):
		var gw: Dictionary = Rig._fk(Rig.pose(Rig.walk_spec(i / 8.0, true)))
		lowest = minf(lowest, minf((gw["foot.R"] as Transform3D).origin.y, (gw["foot.L"] as Transform3D).origin.y))
	check(lowest > -0.08 and lowest < 0.15, "run cycle keeps the feet on the ground (lowest foot %.2f m)" % lowest)

# ------------------------------------------------------------------ rig: runtime (in game)
func _bone_g(r, n: String) -> Transform3D:
	var sk: Skeleton3D = r.skeleton
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(n))

func _rig_runtime_checks() -> void:
	var e = game.enemies[0]
	for o in game.enemies:
		if o != e:
			o.set_physics_process(false)
	e.set_physics_process(false)
	place(e, Vector3(30, 0, 30))
	var r = e._body
	game.player.global_position = e.global_position + Vector3(0, 0, 6)
	await pframes(2)
	r.set_motion(0.0, false)
	await pframes(30)
	var _idle_foot: Vector3 = _bone_g(r, "foot.R").origin
	r.set_motion(1.6, false)
	var moved := 0.0
	var prev := _bone_g(r, "foot.R").origin
	for i in range(40):
		await pframes(1)
		var now := _bone_g(r, "foot.R").origin
		moved += now.distance_to(prev)
		prev = now
	check(absf(float(r.tree.get("parameters/loco/blend_position")) - 1.6) < 0.01, "speed drives the locomotion blend")
	check(moved > 0.3, "legs animate while walking (foot travelled %.2f m)" % moved)
	r.set_motion(0.0, false)
	await pframes(30)
	var ready_w := _bone_g(r, "weapon").origin.y
	r.set_motion(0.0, true)
	await pframes(40)
	var aim_w := _bone_g(r, "weapon").origin.y
	check(aim_w > ready_w + 0.2, "aiming blends the rifle up (%.2f -> %.2f m)" % [ready_w, aim_w])
	r.fire()
	await pframes(2)
	check(bool(r.tree.get("parameters/fire/active")), "fire one-shot plays (recoil)")
	r.reload()
	await pframes(2)
	check(r.is_reload_playing(), "reload one-shot plays")
	r.hit()
	await pframes(2)
	check(bool(r.tree.get("parameters/hit/active")), "hit flinch plays")
	r.set_motion(0.0, false)
	# AI wiring: a soldier in ATTACK aims, one that is shot flinches, a shot triggers recoil.
	e.state = e.State.ATTACK
	e._animate(0.016, 0.0)
	check(r._aim_target == 1.0, "AI ATTACK state raises the weapon")
	e.state = e.State.PATROL
	e._animate(0.016, 0.0)
	check(r._aim_target == 0.0, "AI PATROL lowers it")
	e.set_physics_process(true)
	for o in game.enemies:
		o.set_physics_process(true)
	# Muzzle flash light lives on the weapon bone so it follows the animated gun.
	check(e._muzzle.get_parent() == r.muzzle_holder, "muzzle flash follows the animated weapon")
	# Real movement: after a few seconds of play most soldiers walking have a moving blend.
	await frames(120)
	var walking := 0
	for o in game.enemies:
		if float(o._body.tree.get("parameters/loco/blend_position")) > 0.3:
			walking += 1
	check(walking >= 3, "patrolling soldiers play walk/run (%d of %d)" % [walking, game.enemies.size()])

# ------------------------------------------------------------------ LOD
func _lod_checks() -> void:
	var cam := get_viewport().get_camera_3d()
	var uniform := StandardMaterial3D.new()
	var helmet := StandardMaterial3D.new()
	var near = Rig.new()
	var far = Rig.new()
	add_child(near)
	add_child(far)
	near.build(0, uniform, helmet)
	far.build(1, uniform, helmet)
	near.global_position = cam.global_position + Vector3(0, -1.6, -5)
	far.global_position = cam.global_position + Vector3(0, -1.6, -90)
	near.advances = 0
	far.advances = 0
	await pframes(64)
	check(near.lod_step == 1 and far.lod_step == 8, "LOD step by distance (near %d, far %d)" % [near.lod_step, far.lod_step])
	check(near.advances >= 60 and far.advances <= 10, "far soldiers animate less often (%d vs %d updates in 64 frames)" % [near.advances, far.advances])
	near.queue_free()
	far.queue_free()

# ------------------------------------------------------------------ death fall
func _death_checks() -> void:
	var e = game.enemies[2]
	var pos: Vector3 = e.global_position
	var r = e._body
	e.take_hit_from(500.0, game.player)
	await pframes(2)
	check(not is_instance_valid(e) or e.is_queued_for_deletion(), "dead soldier's logic node is removed as before")
	check(is_instance_valid(r) and r.dead and r.get_parent() == game, "his body stays in the world as a corpse")
	check(r.current_state() == "dead", "AnimationTree switched to the death animation")
	var hips0: float = _bone_g(r, "hips").origin.y - r.global_position.y
	await get_tree().create_timer(1.6).timeout
	var hips1: float = _bone_g(r, "hips").origin.y - r.global_position.y
	check(hips0 > 0.6 and hips1 < 0.35, "animated fall: hips %.2f -> %.2f m (no gore, just a fall)" % [hips0, hips1])
	await get_tree().create_timer(Rig.CORPSE_TIME - 1.0).timeout
	check(not is_instance_valid(r), "corpse sinks into the sand and is freed")

# ------------------------------------------------------------------ recorded audio
const RECORDED := ["shot_webley", "shot_enfield", "shot_thompson", "shot_mp40", "shot_enemy", "explosion", "step", "wind_loop", "sea_loop"]

func _audio_checks() -> void:
	var credits := FileAccess.get_file_as_string("res://assets/audio/CREDITS.md")
	var missing := []
	var big := []
	var bad_len := []
	for n in RECORDED:
		var path := "res://assets/audio/%s.ogg" % n
		var st = load(path)
		if st == null:
			missing.append(n)
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		var kb := f.get_length() / 1024.0
		var limit := 80.0 if n.ends_with("_loop") else 24.0
		if kb > limit:
			big.append("%s %.0fKB" % [n, kb])
		var l: float = st.get_length()
		if (n.ends_with("_loop") and l < 10.0) or (not n.ends_with("_loop") and (l < 0.2 or l > 6.0)):
			bad_len.append("%s %.1fs" % [n, l])
		if not credits.contains(n + ".ogg"):
			missing.append(n + " (credits)")
	check(missing.is_empty(), "every recorded sound loads and is credited %s" % [missing])
	check(big.is_empty(), "recorded files stay small (shots < 24 KB, loops < 80 KB) %s" % [big])
	check(bad_len.is_empty(), "sane lengths (one-shots 0.2–6 s, loops >= 10 s) %s" % [bad_len])
	var urls := 0
	for line in credits.split("\n"):
		if line.contains("https://freesound.org/people/") and line.contains("CC0 1.0"):
			urls += 1
	check(urls >= RECORDED.size(), "CREDITS.md lists a source URL + CC0 license per recording (%d)" % urls)
	check(not credits.contains("No third-party recordings are used"), "old 'no recordings' claim removed from credits")
	var a = game.audio
	check(a != null and a.streams.has("shot_enfield") and a.streams.has("wind_loop"), "audio system loaded the recorded streams")
	check(a.wind != null and a.wind.stream != null and a.wind.stream.loop, "wind recording loops")
	check(a.sea != null and a.sea.stream != null and a.sea.stream.loop, "surf recording loops")
	check(a.music_streams.has("music_menu") and a.music_streams.has("music_battle"), "procedural music kept")
