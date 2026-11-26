extends Node
## HARAQ audio: pooled 2D/3D players for weapon, hit, footstep and UI sounds, looping desert wind
## and sea ambience, distant artillery, and the zone burn loop. Volume + mute live on the Master
## bus and are saved to user://settings.cfg. All sounds are procedurally generated (see
## tools/gen_audio.py and assets/audio/CREDITS.md).

const SETTINGS_PATH := "user://settings.cfg"
const DIR := "res://assets/audio/"
const NAMES := [
	"shot_webley", "shot_enfield", "shot_thompson", "shot_mp40", "shot_enemy", "dry", "reload",
	"switch", "hit_flesh", "hit_sand", "hit_metal", "hurt", "explosion", "zone_burn", "zone_alarm",
	"step", "wind_loop", "sea_loop", "ui_click", "pickup",
]
## Weapon id -> gunshot sound.
const SHOT := {"webley": "shot_webley", "lee_enfield": "shot_enfield", "thompson": "shot_thompson", "mp40": "shot_mp40"}
const POOL_2D := 8
const POOL_3D := 14

var streams := {}
var played := {}
var volume := 0.8
var muted := false
var _p2: Array[AudioStreamPlayer] = []
var _p3: Array[AudioStreamPlayer3D] = []
var _i2 := 0
var _i3 := 0
var wind: AudioStreamPlayer
var sea: AudioStreamPlayer
var burn: AudioStreamPlayer
var _shell_timer := 6.0


func _ready() -> void:
	for n in NAMES:
		var s = load(DIR + n + ".ogg")
		if s != null:
			if n.ends_with("_loop") or n == "zone_burn":
				s.loop = true
			streams[n] = s
	for i in range(POOL_2D):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_p2.append(p)
	for i in range(POOL_3D):
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 6.0
		p.max_distance = 140.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.attenuation_filter_cutoff_hz = 6000.0
		p.attenuation_filter_db = -18.0
		add_child(p)
		_p3.append(p)
	wind = _loop("wind_loop", -9.0)
	sea = _loop("sea_loop", -60.0)
	burn = _loop("zone_burn", -60.0)
	load_settings()


func _loop(n: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = streams.get(n)
	p.volume_db = db
	add_child(p)
	return p


func start_ambience() -> void:
	for p in [wind, sea, burn]:
		if p.stream != null and not p.playing:
			p.play()


func stop_ambience() -> void:
	for p in [sea, burn]:
		p.stop()


func _count(n: String) -> void:
	played[n] = int(played.get(n, 0)) + 1


## Non-positional sound (player's own gun, UI, pickups).
func play(n: String, db := 0.0, pitch_var := 0.0) -> void:
	if not streams.has(n):
		return
	_count(n)
	var p := _p2[_i2]
	_i2 = (_i2 + 1) % _p2.size()
	p.stream = streams[n]
	p.volume_db = db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


## Positional sound in the world (enemy shots, impacts, footsteps, shells).
func play_at(n: String, pos: Vector3, db := 0.0, pitch_var := 0.0) -> void:
	if not streams.has(n):
		return
	_count(n)
	var p := _p3[_i3]
	_i3 = (_i3 + 1) % _p3.size()
	p.stream = streams[n]
	p.volume_db = db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.global_position = pos
	p.play()


## Per-frame ambience mix: sea gets louder near the shore, the burn loop plays outside the zone,
## and shells land somewhere on the horizon every so often.
func update_mix(delta: float, sea_distance: float, outside_zone: float, listener: Vector3) -> void:
	sea.volume_db = lerpf(-4.0, -40.0, clampf(sea_distance / 70.0, 0.0, 1.0))
	burn.volume_db = -60.0 if outside_zone <= 0.0 else lerpf(-14.0, -2.0, clampf(outside_zone / 15.0, 0.0, 1.0))
	_shell_timer -= delta
	if _shell_timer <= 0.0:
		_shell_timer = randf_range(9.0, 22.0)
		var a := randf() * TAU
		play_at("explosion", listener + Vector3(cos(a), 0.0, sin(a)) * randf_range(70.0, 120.0), 14.0, 0.15)


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	_apply()
	save_settings()


func set_muted(m: bool) -> void:
	muted = m
	_apply()
	save_settings()


func _apply() -> void:
	AudioServer.set_bus_mute(0, muted or volume <= 0.001)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.001)))


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		volume = clampf(float(cfg.get_value("audio", "volume", 0.8)), 0.0, 1.0)
		muted = bool(cfg.get_value("audio", "muted", false))
	_apply()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("audio", "muted", muted)
	cfg.save(SETTINGS_PATH)
