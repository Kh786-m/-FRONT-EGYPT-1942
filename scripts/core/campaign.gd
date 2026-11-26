extends Node
## Autoload "Campaign": chapters, missions, unlocks and saved progress.
## Story source of truth: docs/STORY_AND_CAMPAIGN.md

const SAVE_PATH := "user://progress.cfg"

## scene == "" -> designed but not built yet (shown as "قريبًا | COMING SOON").
const CHAPTERS := [
	{
		"id": "ch1", "title_ar": "الفصل الأول: رمال العلمين", "title_en": "Chapter 1: Sands of Alamein",
		"missions": [
			{"id": "m01_alamein_outpost", "title_ar": "نقطة الحراسة", "title_en": "The Desert Outpost", "scene": "res://scenes/missions/m01_alamein_outpost.tscn",
				"brief_ar": "يوليو 1942. دورية معادية قطعت طريق المية عن قرية الحمّام. أمّن نقطة الحراسة.", "brief_en": "July 1942. A hostile patrol has cut the water road to El Hammam. Secure the outpost."},
			{"id": "m03_ruweisat_night", "title_ar": "ليلة رويسات", "title_en": "Ruweisat Night", "scene": "",
				"brief_ar": "تسلل ليلي على تل رويسات لإنقاذ قافلة دليل بدوي.", "brief_en": "Night infiltration on Ruweisat Ridge to rescue a Bedouin guide's caravan."},
		]
	},
	{
		"id": "ch2", "title_ar": "الفصل الثاني: الإسكندرية تنتظر", "title_en": "Chapter 2: Alexandria Waits",
		"missions": [
			{"id": "m02_alexandria_harbor", "title_ar": "ميناء الإسكندرية", "title_en": "Alexandria Harbour", "scene": "res://scenes/maps/m02_alexandria_harbor.tscn",
				"brief_ar": "مخربين بيزرعوا عبوات في مخازن الميناء وقت الغروب. وقفهم قبل ما المدينة تولّع.", "brief_en": "Saboteurs are planting charges in the harbour warehouses at dusk. Stop them before the city burns."},
			{"id": "m04_corniche_blackout", "title_ar": "إظلام الكورنيش", "title_en": "Corniche Blackout", "scene": "",
				"brief_ar": "غارة ليلية والكورنيش ضلمة. وصّل العيلات للمخبأ.", "brief_en": "Night air raid, the Corniche is blacked out. Escort families to the shelter."},
		]
	},
	{
		"id": "ch3", "title_ar": "الفصل الثالث: القطار الأخير", "title_en": "Chapter 3: The Last Train",
		"missions": [
			{"id": "m05_hammam_railway", "title_ar": "محطة الحمّام", "title_en": "El Hammam Station", "scene": "",
				"brief_ar": "احمِ قطار الإمدادات الطبية على خط الصحراء.", "brief_en": "Protect the medical supply train on the desert line."},
		]
	},
	{
		"id": "ch4", "title_ar": "الفصل الرابع: نار أكتوبر", "title_en": "Chapter 4: October Fire",
		"missions": [
			{"id": "m06_devils_gardens", "title_ar": "حدائق الشيطان", "title_en": "The Devil's Gardens", "scene": "",
				"brief_ar": "23 أكتوبر 1942. افتح ممر آمن في حقول الألغام قبل القصف.", "brief_en": "23 October 1942. Clear a safe lane through the minefields before the barrage."},
			{"id": "m07_tel_el_eisa", "title_ar": "تل العيس", "title_en": "Tel el Eisa", "scene": "",
				"brief_ar": "المعركة الأخيرة. رجّع خالد لبيته.", "brief_en": "The final push. Bring Khaled home."},
		]
	},
]

var progress := {}   # mission_id -> {"stars": int, "xp": int}
var total_xp := 0
var total_coins := 0
var quality_high := true

func _ready() -> void:
	quality_high = not OS.has_feature("mobile")
	_load()

func mission_order() -> Array:
	var out := []
	for ch in CHAPTERS:
		for m in ch.missions:
			if m.scene != "": out.append(m.id)
	return out

func is_unlocked(mission_id: String) -> bool:
	var order := mission_order()
	var i := order.find(mission_id)
	if i <= 0: return i == 0
	return progress.has(order[i - 1])

func complete_mission(mission_id: String, hp: int, xp: int, coins: int) -> int:
	var stars := 1 + int(hp >= 50) + int(hp >= 85)
	var prev: Dictionary = progress.get(mission_id, {"stars": 0, "xp": 0})
	progress[mission_id] = {"stars": maxi(stars, prev.stars), "xp": maxi(xp, prev.xp)}
	total_xp += xp
	total_coins += coins
	_save()
	return stars

func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("player", "xp", total_xp)
	cf.set_value("player", "coins", total_coins)
	cf.set_value("player", "quality_high", quality_high)
	cf.set_value("player", "progress", progress)
	cf.save(SAVE_PATH)

func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK: return
	total_xp = cf.get_value("player", "xp", 0)
	total_coins = cf.get_value("player", "coins", 0)
	quality_high = cf.get_value("player", "quality_high", quality_high)
	progress = cf.get_value("player", "progress", {})

func set_quality(high: bool) -> void:
	quality_high = high
	_save()
