extends Node
## HARAQ audio: pooled 2D/3D players for weapon, hit, footstep and UI sounds, looping desert wind
## and sea ambience, distant artillery, and the zone burn loop, plus a menu theme and a tense
## in-match music loop. Buses: Master (overall volume + mute) -> Music and SFX (own sliders).
## Music ducks under nearby gunfire and explosions. Settings are saved to user://settings.cfg. All sounds are procedurally generated (see
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

const MUSIC_DB := -7.0
const DUCK_RECOVER := 9.0 # dB per second

var streams := {}
var music_streams := {}
var music_volume := 0.6
var sfx_volume := 1.0
var music_player: AudioStreamPlayer
var music_track := ""
var _duck_db := 0.0
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


static func ensure_buses() -> void:
	for b in ["Music", "SFX"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")


func _ready() -> void:
	ensure_buses()
	for n in ["music_menu", "music_battle"]:
		var ms = load(DIR + n + ".ogg")
		if ms != null:
			ms.loop = true
			music_streams[n] = ms
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	music_player.volume_db = MUSIC_DB
	add_child(music_player)
	for n in NAMES:
		var s = load(DIR + n + ".ogg")
		if s != null:
			if n.ends_with("_loop") or n == "zone_burn":
				s.loop = true
			streams[n] = s
	for i in range(POOL_2D):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_p2.append(p)
	for i in range(POOL_3D):
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 6.0
		p.max_distance = 140.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.attenuation_filter_cutoff_hz = 6000.0
		p.attenuation_filter_db = -18.0
		p.bus = "SFX"
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
	p.bus = "SFX"
	add_child(p)
	return p


## Cross to another music track ("music_menu" / "music_battle"); "" stops the music.
func play_music(n: String) -> void:
	if n == music_track and (n == "" or music_player.playing):
		return
	music_track = n
	if n == "" or not music_streams.has(n):
		music_player.stop()
		return
	music_player.stream = music_streams[n]
	music_player.play()


## Push the music down under loud sounds (amount 0..1 -> up to -14 dB), recovering smoothly.
func duck(amount: float) -> void:
	_duck_db = minf(_duck_db, -14.0 * clampf(amount, 0.0, 1.0))
	_apply_music()


func _process(delta: float) -> void:
	if _duck_db < 0.0:
		_duck_db = minf(0.0, _duck_db + DUCK_RECOVER * delta)
		_apply_music()


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
		duck(0.35)


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	_apply()
	save_settings()


func set_muted(m: bool) -> void:
	muted = m
	_apply()
	save_settings()


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_apply()
	save_settings()


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply()
	save_settings()


func _apply() -> void:
	AudioServer.set_bus_mute(0, muted or volume <= 0.001)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.001)))
	var sb := AudioServer.get_bus_index("SFX")
	if sb >= 0:
		AudioServer.set_bus_mute(sb, sfx_volume <= 0.001)
		AudioServer.set_bus_volume_db(sb, linear_to_db(maxf(sfx_volume, 0.001)))
	_apply_music()


func _apply_music() -> void:
	var mb := AudioServer.get_bus_index("Music")
	if mb >= 0:
		AudioServer.set_bus_mute(mb, music_volume <= 0.001)
		AudioServer.set_bus_volume_db(mb, linear_to_db(maxf(music_volume, 0.001)) + _duck_db)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		volume = clampf(float(cfg.get_value("audio", "volume", 0.8)), 0.0, 1.0)
		muted = bool(cfg.get_value("audio", "muted", false))
		music_volume = clampf(float(cfg.get_value("audio", "music", 0.6)), 0.0, 1.0)
		sfx_volume = clampf(float(cfg.get_value("audio", "sfx", 1.0)), 0.0, 1.0)
	_apply()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("audio", "muted", muted)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.save(SETTINGS_PATH)
