extends Node3D
## Main menu / campaign map: 3D hero Khaled on a dusk desert diorama,
## chapter + mission list driven by the Campaign autoload.

var hero: SoldierModel
var cam: Camera3D
var t := 0.0
var info: Label

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	LevelKit.apply_environment(self, "coast_dusk")
	var sand := LevelKit.mat(Color(0.72, 0.57, 0.38))
	LevelKit.box(self, Vector3(0, -0.5, 0), Vector3(120, 1, 120), sand)
	LevelKit.dunes(self, 7, 18, 40.0, sand)
	for i in range(5):
		LevelKit.palm(self, Vector3(-9 + i * 1.7, 0, -7 - (i % 2) * 2.5), 4.0 + (i % 3) * 0.6)
	LevelKit.cart(self, Vector3(4.5, 0, -4))
	LevelKit.crate_stack(self, Vector3(-3.5, 0, -2.5), 3)
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 200)
	sea.mesh = pm
	sea.material_override = LevelKit.mat(Color(0.118, 0.298, 0.353), 0.15, 0.3)
	sea.position = Vector3(0, 0.02, -120)
	add_child(sea)
	hero = SoldierModel.new(SoldierModel.Kind.HERO)
	hero.position = Vector3(1.6, 0, 0)
	add_child(hero)
	for i in range(2):
		var ally := SoldierModel.new(SoldierModel.Kind.ALLY)
		ally.position = Vector3(3.2 + i * 1.1, 0, -1.6 - i)
		ally.rotation_degrees.y = 20
		add_child(ally)
	cam = Camera3D.new()
	cam.position = Vector3(0.4, 1.6, 4.4)
	cam.fov = 50
	add_child(cam)
	cam.look_at(Vector3(1.4, 1.2, 0))
	_build_ui()

func _process(delta: float) -> void:
	t += delta
	hero.rotation.y = sin(t * 0.4) * 0.6
	cam.position.x = 0.4 + sin(t * 0.15) * 0.3

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.62)
	shade.anchor_bottom = 1.0
	shade.offset_right = 560
	root.add_child(shade)
	var v := VBoxContainer.new()
	v.position = Vector2(36, 28)
	v.custom_minimum_size = Vector2(500, 660)
	v.add_theme_constant_override("separation", 8)
	root.add_child(v)
	var title := Label.new()
	title.text = "WAR FRONT: EGYPT 1942"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.98, 0.83, 0.52))
	v.add_child(title)
	var sub := Label.new()
	sub.text = "جبهة الحرب: مصر 1942 — خالد كارم عبداللا"
	sub.add_theme_font_size_override("font_size", 22)
	v.add_child(sub)
	info = Label.new()
	info.text = "XP %d   •   COINS %d" % [Campaign.total_xp, Campaign.total_coins]
	info.add_theme_font_size_override("font_size", 18)
	v.add_child(info)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 470)
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for ch in Campaign.CHAPTERS:
		var h := Label.new()
		h.text = "%s\n%s" % [ch.title_ar, ch.title_en]
		h.add_theme_font_size_override("font_size", 19)
		h.add_theme_color_override("font_color", Color(0.95, 0.72, 0.42))
		list.add_child(h)
		for m in ch.missions:
			var b := Button.new()
			b.custom_minimum_size = Vector2(480, 58)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_font_size_override("font_size", 18)
			var stars := 0
			if Campaign.progress.has(m.id): stars = Campaign.progress[m.id].stars
			if m.scene == "":
				b.text = "  %s | %s  —  قريبًا COMING SOON" % [m.title_ar, m.title_en]
				b.disabled = true
			elif not Campaign.is_unlocked(m.id):
				b.text = "  [مقفول LOCKED] %s | %s" % [m.title_ar, m.title_en]
				b.disabled = true
			else:
				b.text = "  ▶ %s | %s   %s" % [m.title_ar, m.title_en, "★".repeat(stars)]
				var path: String = m.scene
				b.pressed.connect(func(): get_tree().change_scene_to_file(path))
			b.tooltip_text = "%s\n%s" % [m.brief_ar, m.brief_en]
			list.add_child(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var q := Button.new()
	q.custom_minimum_size = Vector2(240, 54)
	q.text = "جرافيك: عالي | HIGH" if Campaign.quality_high else "جرافيك: موفّر | LOW"
	q.pressed.connect(func():
		Campaign.set_quality(not Campaign.quality_high)
		get_tree().reload_current_scene())
	row.add_child(q)
	var quit := Button.new()
	quit.custom_minimum_size = Vector2(240, 54)
	quit.text = "خروج | QUIT"
	quit.pressed.connect(func(): get_tree().quit())
	row.add_child(quit)
