extends RefCounted
## Прогресс между забегами: осколки, здания убежища, жители, открытые герои.
## Хранится в одном из трёх слотов: user://save_1.cfg … save_3.cfg.

const OLD_PATH := "user://save.cfg"
const SLOTS_PATH := "user://slots.cfg"
const MAX_SLOTS := 3

static var slot := 0   # 0 — ещё не прочитан из slots.cfg

static var loaded := false
static var shards := 120
static var buildings := {}
static var followers: Array = []
static var total_runs := 0
static var best_time := 0.0
static var last_reward := {}
static var levels_cleared := 0
static var level_best := {}
static var nickname := "Охотник"
static var stats := {}  # статистика профиля: kills, time, bosses, wins, deaths, reactions, max_level, best_endless, heroes{}
static var seen := {}   # открытое в библиотеке: "w:bolt", "m:crit", "s:burn", "r:burn+chill", "a:damage"
## Материалы для постройки базы — собираются только в бою.
const MATERIALS := {
	"scrap": {"name": "Лом", "icon": "⚙", "color": Color(0.75, 0.75, 0.85)},
	"chips": {"name": "Микросхемы", "icon": "▣", "color": Color(0.35, 1.0, 0.6)},
	"cores": {"name": "Ядра", "icon": "✶", "color": Color(1.0, 0.45, 0.9)},
}
static var materials := {"scrap": 0, "chips": 0, "cores": 0}
static var quests: Array = []        # доска заданий (см. quests.gd)
static var contracts: Array = []     # взятые контракты таверны
static var offers: Array = []        # предложения трактирщика
static var construct := {}           # стройка: {"id", "lvl", "left"} — сколько вылазок осталось
static var just_built := ""          # для сообщения в убежище
static var trees := {}  # "w:bolt" / "c:vega" / "m:crit" -> [id узлов]

const BUILDINGS := {
	"forge": {"name": "Рунная кузница", "desc": "+6% к урону за уровень. Здесь прокачивается оружие — у каждого своё дерево; уровень кузницы открывает ярусы.", "max": 5, "base": 60,
		"color": Color(1.0, 0.55, 0.2), "pos": Vector3(-9, 0, -1)},
	"hall": {"name": "Таверна «Неоновый кабан»", "desc": "Здесь отдыхают открытые герои — подойдите к любому, чтобы взять его в бой. Наёмников у стойки можно нанять, а трактирщик даёт контракты. +5% опыта в бою за уровень.", "max": 5, "base": 90,
		"color": Color(1.0, 0.8, 0.3), "pos": Vector3(-7, 0, 10)},
	"shrine": {"name": "Алтарь героев", "desc": "+10% к шансу сундука за уровень. Здесь прокачиваются герои — у каждого своё дерево; уровень алтаря открывает ярусы.", "max": 5, "base": 70,
		"color": Color(1.0, 0.35, 0.8), "pos": Vector3(9, 0, -1)},
	"lab": {"name": "Лаборатория модулей", "desc": "Дерево прокачки модулей. Уровень здания открывает ярусы дерева.", "max": 5, "base": 100,
		"color": Color(0.4, 0.85, 1.0), "pos": Vector3(7, 0, 10)},
}

# ---------- Открытие героев ----------
# Вега доступна сразу. Остальных нужно ОТКРЫТЬ в Зале героев: выполнить условие
# и заплатить осколками. Чем дальше герой — тем сложнее условие.
const HERO_ORDER := ["vega", "rin", "bram", "kira", "skyla", "orm", "mora", "zephyr", "iris", "kai"]
const HERO_UNLOCK := {
	"vega": {"cost": 0, "conds": []},
	"rin": {"cost": 150, "conds": [["kills", 500]]},
	"bram": {"cost": 250, "conds": [["level", 1]]},
	"kira": {"cost": 350, "conds": [["reactions", 200], ["runs", 5]]},
	"skyla": {"cost": 450, "conds": [["bosses", 5]]},
	"orm": {"cost": 600, "conds": [["best_kills", 800], ["level", 2]]},
	"mora": {"cost": 800, "conds": [["level", 3], ["kills", 5000]]},
	"zephyr": {"cost": 1000, "conds": [["endless", 10]]},
	"iris": {"cost": 1300, "conds": [["endless", 15], ["bosses", 20]]},
	"kai": {"cost": 1700, "conds": [["endless", 20], ["level", 5]]},
}
static var heroes_owned: Array = ["vega"]
# Поиск героев: сначала героя нужно СПАСТИ в бою (пленник, шанс 1 из 100 на каждый
# бросок места задания), потом собрать его оружие из 3 частей (шанс 1 из 1000 с врага,
# иногда в тайнике). Только тогда его можно нанять в таверне (старые условия тоже нужны).
static var rescued: Array = []
static var parts := {}
const PARTS_NEED := 3

# ---------- Деревья прокачки ----------
# Дерево растёт сверху вниз: pos = (колонка, ряд), ряд = ярус - 1.
# Ярус N требует здание ур. N. «conds» — дополнительные условия (достижения).
## Дерево оружия: 4 колонки, ветви «Сила», «Точность», «Скорость», «Стихия».
## Условия — по тому, как вы играете ЭТИМ оружием: убийства им, вылазки с ним, элита, слияния.
const WEAPON_TREE := [
	{"id": "dmg1", "name": "Заточка I", "desc": "+10% урона", "cost": 40, "req": [], "tier": 1, "pos": Vector2(0, 0)},
	{"id": "crit1", "name": "Острый край", "desc": "+5% шанс крита этим оружием", "cost": 50, "req": [], "tier": 1, "pos": Vector2(1, 0)},
	{"id": "cd1", "name": "Разгон", "desc": "-10% перезарядки", "cost": 60, "req": [], "tier": 1, "pos": Vector2(2, 0)},
	{"id": "salvage", "name": "Утилизатор", "desc": "Враги, убитые этим оружием, вдвое чаще роняют лом", "cost": 60, "req": [], "tier": 1, "pos": Vector2(3, 0)},
	{"id": "dmg2", "name": "Заточка II", "desc": "+15% урона", "cost": 110, "req": ["dmg1"], "tier": 2, "pos": Vector2(0, 1)},
	{"id": "area1", "name": "Широкий захват", "desc": "+10% области и дальности", "cost": 100, "req": ["crit1"], "tier": 2, "pos": Vector2(1, 1)},
	{"id": "status", "name": "Стихийный резонанс", "desc": "+30% урона по целям со статусом", "cost": 120, "req": ["cd1"], "tier": 2, "pos": Vector2(2, 1)},
	{"id": "speed1", "name": "Импульс", "desc": "+15% скорости снарядов", "cost": 90, "req": ["cd1"], "tier": 2, "pos": Vector2(3, 1)},
	{"id": "critdmg", "name": "Смертельный удар", "desc": "Криты этим оружием бьют ×2.5 вместо ×2", "cost": 150, "req": ["crit1"], "tier": 2, "pos": Vector2(1, 2), "conds": [["wkills", 300]]},
	{"id": "leech", "name": "Жажда", "desc": "Убийство этим оружием лечит 0.3 здоровья", "cost": 140, "req": ["speed1"], "tier": 2, "pos": Vector2(3, 2), "conds": [["wkills", 500]]},
	{"id": "dmg3", "name": "Заточка III", "desc": "+15% урона", "cost": 200, "req": ["dmg2"], "tier": 3, "pos": Vector2(0, 3), "conds": [["bosses", 3]]},
	{"id": "count", "name": "Расширение", "desc": "+1 снаряд и +15% области", "cost": 220, "req": ["area1"], "tier": 3, "pos": Vector2(1, 3), "conds": [["wkills", 800]]},
	{"id": "cd2", "name": "Перегрев", "desc": "-10% перезарядки", "cost": 200, "req": ["status"], "tier": 3, "pos": Vector2(2, 3)},
	{"id": "dur", "name": "Затяжной эффект", "desc": "+25% длительности статусов", "cost": 180, "req": ["status", "speed1"], "tier": 3, "pos": Vector2(3, 3), "conds": [["reactions", 150]]},
	{"id": "elite", "name": "Гроза великанов", "desc": "+30% урона по элите и боссам", "cost": 260, "req": ["dmg3", "critdmg"], "tier": 3, "pos": Vector2(0.5, 4), "conds": [["elites", 15]]},
	{"id": "resonance", "name": "Эхо стихии", "desc": "+20% длительности статусов, +15% урона по статусу", "cost": 260, "req": ["cd2", "dur"], "tier": 3, "pos": Vector2(2.5, 4), "conds": [["wruns", 8]]},
	{"id": "master", "name": "Мастерство", "desc": "+20% урона, оружие героя с ур. 2", "cost": 320, "req": ["dmg3", "count"], "tier": 4, "pos": Vector2(0, 5), "conds": [["level", 2], ["wruns", 5]]},
	{"id": "execute", "name": "Добивание", "desc": "+50% урона по врагам с запасом здоровья ниже 30%", "cost": 340, "req": ["elite"], "tier": 4, "pos": Vector2(1, 5), "conds": [["wkills", 2000]]},
	{"id": "overcharge", "name": "Перегрузка", "desc": "+1 снаряд", "cost": 340, "req": ["cd2", "dur"], "tier": 4, "pos": Vector2(2, 5), "conds": [["endless", 10]]},
	{"id": "fusion", "name": "Сродство", "desc": "+20% урона, если оружие участвует в слиянии", "cost": 320, "req": ["resonance"], "tier": 4, "pos": Vector2(3, 5), "conds": [["fusions", 3]]},
	{"id": "legend", "name": "Легенда", "desc": "+25% урона и -10% перезарядки", "cost": 600, "req": ["master", "execute"], "tier": 5, "pos": Vector2(0.5, 6), "conds": [["endless", 20], ["wkills", 6000]]},
	{"id": "mythic", "name": "Миф", "desc": "+1 снаряд и -15% перезарядки", "cost": 650, "req": ["overcharge", "fusion"], "tier": 5, "pos": Vector2(2.5, 6), "conds": [["wkills", 5000], ["quests", 15]]},
]
## Дерево героя: условия — убийства ЭТИМ героем, шаги его личного задания, стиль игры.
const HERO_TREE := [
	{"id": "hp1", "name": "Закалка", "desc": "+15 здоровья", "cost": 40, "req": [], "tier": 1, "pos": Vector2(0, 0)},
	{"id": "mats1", "name": "Добытчик", "desc": "+20% материалов за вылазки этим героем", "cost": 60, "req": [], "tier": 1, "pos": Vector2(1, 0)},
	{"id": "spd1", "name": "Лёгкий шаг", "desc": "+6% скорости", "cost": 50, "req": [], "tier": 1, "pos": Vector2(2, 0)},
	{"id": "hp2", "name": "Стойкость", "desc": "+20 здоровья", "cost": 100, "req": ["hp1"], "tier": 2, "pos": Vector2(0, 1)},
	{"id": "regen1", "name": "Восстановление", "desc": "+0.4 здоровья в секунду", "cost": 110, "req": ["hp1"], "tier": 2, "pos": Vector2(1, 1)},
	{"id": "magnet1", "name": "Притяжение", "desc": "+25% радиуса сбора", "cost": 90, "req": ["spd1"], "tier": 2, "pos": Vector2(2, 1)},
	{"id": "cd", "name": "Фокус", "desc": "-15% перезарядки способности", "cost": 100, "req": ["spd1"], "tier": 2, "pos": Vector2(3, 1)},
	{"id": "legacy", "name": "Наследие", "desc": "+10 здоровья и +6% урона", "cost": 140, "req": ["regen1"], "tier": 2, "pos": Vector2(1, 2), "conds": [["hq", 1]]},
	{"id": "armor", "name": "Броня-кожа", "desc": "-1 к получаемому урону", "cost": 180, "req": ["hp2"], "tier": 3, "pos": Vector2(0, 3), "conds": [["hkills", 1500]]},
	{"id": "xp1", "name": "Ученик", "desc": "+10% опыта", "cost": 160, "req": ["legacy"], "tier": 3, "pos": Vector2(1, 3), "conds": [["hero_runs", 3]]},
	{"id": "dodge1", "name": "Уворот", "desc": "+5% уклонения", "cost": 190, "req": ["magnet1"], "tier": 3, "pos": Vector2(2, 3), "conds": [["hero_runs", 5]]},
	{"id": "power", "name": "Усиление дара", "desc": "+30% силы способности", "cost": 200, "req": ["cd"], "tier": 3, "pos": Vector2(3, 3)},
	{"id": "legend_tale", "name": "Предание", "desc": "+8% урона и -10% перезарядки способности", "cost": 260, "req": ["xp1", "dodge1"], "tier": 3, "pos": Vector2(1.5, 4), "conds": [["hq", 2]]},
	{"id": "awaken", "name": "Пробуждение", "desc": "Начинать забег со случайным модулем ур. 1", "cost": 300, "req": ["armor", "xp1"], "tier": 4, "pos": Vector2(0, 5), "conds": [["bosses", 5]]},
	{"id": "hunter", "name": "Охотник", "desc": "+12% урона", "cost": 320, "req": ["legend_tale"], "tier": 4, "pos": Vector2(1, 5), "conds": [["hkills", 4000]]},
	{"id": "cd2", "name": "Медитация", "desc": "-15% перезарядки способности", "cost": 320, "req": ["dodge1", "power"], "tier": 4, "pos": Vector2(2, 5), "conds": [["endless", 10]]},
	{"id": "laststand", "name": "Последний рубеж", "desc": "При здоровье ниже 30%: +30% урона и +15% скорости", "cost": 300, "req": ["power"], "tier": 4, "pos": Vector2(3, 5), "conds": [["nodmg_best", 60]]},
	{"id": "ascend", "name": "Вознесение", "desc": "+30 здоровья, +10% скорости, +20% силы способности", "cost": 600, "req": ["awaken", "cd2"], "tier": 5, "pos": Vector2(0.5, 6), "conds": [["endless", 15], ["hero_runs", 15]]},
	{"id": "myth", "name": "Легенда пустоши", "desc": "+20% урона, +20 здоровья, -10% перезарядки способности", "cost": 650, "req": ["hunter", "laststand"], "tier": 5, "pos": Vector2(2.5, 6), "conds": [["hq", 3], ["hkills", 10000]]},
]
## Дерево модуля: условия — сколько вылазок вы прошли с этим модулем.
const MODULE_TREE := [
	{"id": "boost1", "name": "Калибровка", "desc": "Эффект модуля +25%", "cost": 50, "req": [], "tier": 1, "pos": Vector2(1, 0)},
	{"id": "favor", "name": "Знакомый сигнал", "desc": "Модуль вдвое чаще предлагается при повышении уровня", "cost": 60, "req": [], "tier": 1, "pos": Vector2(2, 0), "conds": [["mused", 2]]},
	{"id": "boost2", "name": "Перегрузка", "desc": "Эффект модуля ещё +25%", "cost": 120, "req": ["boost1"], "tier": 2, "pos": Vector2(0, 1)},
	{"id": "tune", "name": "Тонкая настройка", "desc": "Эффект модуля +15%", "cost": 100, "req": ["boost1"], "tier": 2, "pos": Vector2(2, 1), "conds": [["mused", 4]]},
	{"id": "boost3", "name": "Резонанс", "desc": "Эффект модуля +25%", "cost": 220, "req": ["boost2"], "tier": 3, "pos": Vector2(0, 2), "conds": [["reactions", 300]]},
	{"id": "preinstall", "name": "Предустановка", "desc": "Модуль ур. 1 с начала каждого забега", "cost": 260, "req": ["tune"], "tier": 3, "pos": Vector2(2, 2), "conds": [["runs", 10], ["mused", 8]]},
	{"id": "boost4", "name": "Синхронизация", "desc": "Эффект модуля +25%", "cost": 360, "req": ["boost3", "preinstall"], "tier": 4, "pos": Vector2(1, 3), "conds": [["endless", 10]]},
	{"id": "boost5", "name": "Сингулярность", "desc": "Эффект модуля +50%", "cost": 650, "req": ["boost4"], "tier": 5, "pos": Vector2(1, 4), "conds": [["level", 5], ["mused", 20]]},
]

const NAME_A := ["Ар", "Бел", "Вир", "Гло", "Дин", "Зе", "Ки", "Лум", "Ми", "Нок", "Ор", "Пикс", "Ру", "Сай", "Тэк", "Ул", "Фе", "Хо", "Це", "Эн"]
const NAME_B := ["ка", "ло", "рис", "та", "вен", "ми", "сс", "ни", "ро", "кс", "ла", "ди", "рон", "ви", "эль"]

const PHRASES := [
	"Неон греет душу.", "Ещё один осколок!", "Видел Лича? Жуть...", "Чиню генератор.",
	"Ночь будет долгой.", "Слышишь гул портала?", "Здесь безопасно.", "Удачной вылазки!",
	"Кузня опять дымит.", "Я верю в тебя!", "Где мой паяльник?", "Пахнет озоном.",
]


# ---------- Слоты сохранений ----------

static func slot_path(n: int) -> String:
	return "user://save_%d.cfg" % n


static func current_slot() -> int:
	if slot == 0:
		var c := ConfigFile.new()
		slot = 1
		if c.load(SLOTS_PATH) == OK:
			slot = clampi(int(c.get_value("slots", "current", 1)), 1, MAX_SLOTS)
		# Перенос старого единственного сохранения в слот 1
		if FileAccess.file_exists(OLD_PATH) and not FileAccess.file_exists(slot_path(1)):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(OLD_PATH), ProjectSettings.globalize_path(slot_path(1)))
			DirAccess.remove_absolute(ProjectSettings.globalize_path(OLD_PATH))
	return slot


static func slot_exists(n: int) -> bool:
	current_slot()
	return FileAccess.file_exists(slot_path(n))


## Краткие сведения о слоте для меню (без загрузки в игру).
static func slot_info(n: int) -> Dictionary:
	var cfg := ConfigFile.new()
	if not slot_exists(n) or cfg.load(slot_path(n)) != OK:
		return {}
	var st: Dictionary = cfg.get_value("meta", "stats", {})
	return {"nickname": cfg.get_value("meta", "nickname", "Охотник"),
		"runs": cfg.get_value("meta", "runs", 0),
		"shards": cfg.get_value("meta", "shards", 0),
		"levels": cfg.get_value("meta", "levels_cleared", 0),
		"time": float(st.get("time", 0.0)),
		"saved": cfg.get_value("meta", "saved_at", "")}


## Выбрать слот: текущий прогресс сохраняется, затем загружается выбранный
## (пустой слот начинается с нуля и сразу создаётся на диске).
static func switch_slot(n: int) -> void:
	n = clampi(n, 1, MAX_SLOTS)
	if loaded and slot_exists(current_slot()):
		save()
	slot = n
	var c := ConfigFile.new()
	c.set_value("slots", "current", n)
	c.save(SLOTS_PATH)
	reset()
	ensure_loaded()
	if not slot_exists(n):
		save()


static func delete_slot(n: int) -> void:
	if slot_exists(n):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(n)))
	if n == current_slot():
		reset()
		ensure_loaded()


## Значения нового прогресса
static func reset() -> void:
	loaded = false
	shards = 120
	buildings = {}
	followers = []
	heroes_owned = ["vega"]
	total_runs = 0
	best_time = 0.0
	last_reward = {}
	levels_cleared = 0
	level_best = {}
	nickname = "Охотник"
	stats = {}
	seen = {}
	trees = {}
	materials = {"scrap": 0, "chips": 0, "cores": 0}
	quests = []
	contracts = []
	offers = []
	rescued = []
	parts = {}
	construct = {}
	just_built = ""


static func ensure_loaded() -> void:
	if loaded:
		return
	loaded = true
	for id in BUILDINGS:
		buildings[id] = 0
	var cfg := ConfigFile.new()
	if cfg.load(slot_path(current_slot())) != OK:
		return
	shards = cfg.get_value("meta", "shards", shards)
	total_runs = cfg.get_value("meta", "runs", 0)
	best_time = cfg.get_value("meta", "best_time", 0.0)
	var b: Dictionary = cfg.get_value("meta", "buildings", {})
	for id in b:
		if buildings.has(id):
			buildings[id] = b[id]
	followers = cfg.get_value("meta", "followers", [])
	levels_cleared = cfg.get_value("meta", "levels_cleared", 0)
	level_best = cfg.get_value("meta", "level_best", {})
	trees = cfg.get_value("meta", "trees", {})
	if cfg.has_section_key("meta", "heroes_owned"):
		heroes_owned = cfg.get_value("meta", "heroes_owned", ["vega"])
		rescued = cfg.get_value("meta", "rescued", [])
		parts = cfg.get_value("meta", "parts", {})
	else:
		# Старое сохранение: герои открывались уровнем зала — оставляем уже открытых
		heroes_owned = []
		var hl := int(buildings.get("hall", 0))
		for i in HERO_ORDER.size():
			if i <= hl:
				heroes_owned.append(HERO_ORDER[i])
	if not ("vega" in heroes_owned):
		heroes_owned.push_front("vega")
	seen = cfg.get_value("meta", "seen", {})
	nickname = cfg.get_value("meta", "nickname", nickname)
	stats = cfg.get_value("meta", "stats", {})
	var mat: Dictionary = cfg.get_value("meta", "materials", {})
	materials = {"scrap": int(mat.get("scrap", 0)), "chips": int(mat.get("chips", 0)), "cores": int(mat.get("cores", 0))}
	quests = cfg.get_value("meta", "quests", [])
	contracts = cfg.get_value("meta", "contracts", [])
	offers = cfg.get_value("meta", "offers", [])
	construct = cfg.get_value("meta", "construct", {})
	# Старые сохранения: всё оружие и модули уже встречались
	if seen.is_empty() and total_runs > 0:
		var D = preload("res://scripts/data.gd")
		for w in D.WEAPONS:
			seen["w:" + w] = true
		for m in D.PASSIVES:
			seen["m:" + m] = true


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "shards", shards)
	cfg.set_value("meta", "runs", total_runs)
	cfg.set_value("meta", "best_time", best_time)
	cfg.set_value("meta", "buildings", buildings)
	cfg.set_value("meta", "followers", followers)
	cfg.set_value("meta", "levels_cleared", levels_cleared)
	cfg.set_value("meta", "level_best", level_best)
	cfg.set_value("meta", "trees", trees)
	cfg.set_value("meta", "heroes_owned", heroes_owned)
	cfg.set_value("meta", "seen", seen)
	cfg.set_value("meta", "nickname", nickname)
	cfg.set_value("meta", "stats", stats)
	cfg.set_value("meta", "materials", materials)
	cfg.set_value("meta", "quests", quests)
	cfg.set_value("meta", "contracts", contracts)
	cfg.set_value("meta", "rescued", rescued)
	cfg.set_value("meta", "parts", parts)
	cfg.set_value("meta", "offers", offers)
	cfg.set_value("meta", "construct", construct)
	cfg.set_value("meta", "saved_at", Time.get_datetime_string_from_system(false, true))
	cfg.save(slot_path(current_slot()))


## Отметить найденное для библиотеки (сохраняется вместе с итогом забега).
static func discover(key: String) -> void:
	if not seen.has(key):
		seen[key] = true


static func discovered(key: String) -> bool:
	ensure_loaded()
	return seen.has(key)


static func level(id: String) -> int:
	ensure_loaded()
	return buildings.get(id, 0)


static func upgrade_cost(id: String) -> int:
	var b: Dictionary = BUILDINGS[id]
	return int(b["base"] * 1.3 * pow(level(id) + 1, 1.7))


## Цена узла дерева (прокачка стала дороже — каждый узел надо заработать).
static func node_cost(n: Dictionary) -> int:
	return int(round(float(n["cost"]) * 1.35))


## Угроза: растёт с пройденными уровнями и вылазками. Враги крепче и злее,
## награда — выше. Так каждая вылазка остаётся испытанием.
static func threat() -> int:
	return clampi(levels_cleared * 2 + total_runs / 4, 0, 40)


## Испытания вылазки — одно случайное на каждый бой, с бонусом к награде.
const CHALLENGES := {
	"swift": {"name": "Стремительные", "desc": "враги на 20% быстрее", "bonus": 0.2},
	"armored": {"name": "Бронированные", "desc": "враги на 35% крепче", "bonus": 0.25},
	"elite": {"name": "Ночь элиты", "desc": "элита и усиленные враги вдвое чаще", "bonus": 0.3},
	"starved": {"name": "Голод", "desc": "лечение вдвое слабее", "bonus": 0.25},
	"glass": {"name": "Стеклянная пушка", "desc": "вы наносите +15% урона, но получаете +30%", "bonus": 0.2},
	"swarm": {"name": "Рой", "desc": "врагов на 30% больше", "bonus": 0.25},
	"cursed": {"name": "Проклятие", "desc": "после 2 минут у каждого врага есть усиление", "bonus": 0.35},
}


## База растёт по шагам: каждый уровень здания — это осколки + материалы из боя,
## условие (сколько уровней главы пройдено) и стройка, которая идёт несколько вылазок.
const REQ_CLEARED := [0, 0, 1, 2, 4, 6]
const BUILD_RUNS := [0, 0, 1, 1, 2, 3]


static func build_cost(id: String) -> Dictionary:
	var L := level(id) + 1
	return {"shards": upgrade_cost(id), "scrap": 8 * L * L, "chips": 3 * (L - 1) * (L - 1),
		"cores": maxi(0, L - 3) * 2}


static func build_req(id: String) -> int:
	return REQ_CLEARED[mini(level(id) + 1, 5)]


static func building_busy(id: String) -> bool:
	return construct.get("id", "") == id


static func can_afford(cost: Dictionary) -> bool:
	if shards < int(cost.get("shards", 0)):
		return false
	for m in MATERIALS:
		if int(materials.get(m, 0)) < int(cost.get(m, 0)):
			return false
	return true


static func pay(cost: Dictionary) -> void:
	shards -= int(cost.get("shards", 0))
	for m in MATERIALS:
		materials[m] = int(materials.get(m, 0)) - int(cost.get(m, 0))


static func cost_text(cost: Dictionary) -> String:
	var parts: Array = ["%d ◆" % int(cost.get("shards", 0))]
	for m in MATERIALS:
		if int(cost.get(m, 0)) > 0:
			parts.append("%d %s" % [int(cost[m]), MATERIALS[m]["icon"]])
	return "  ".join(parts)


## Почему нельзя строить ("" — можно).
static func upgrade_block(id: String) -> String:
	if level(id) >= int(BUILDINGS[id]["max"]):
		return "максимум"
	if not construct.is_empty():
		return "уже идёт стройка: " + str(BUILDINGS.get(construct.get("id", ""), {}).get("name", ""))
	if levels_cleared < build_req(id):
		return "пройдите уровней главы: %d" % build_req(id)
	if not can_afford(build_cost(id)):
		return "не хватает ресурсов"
	return ""


static func can_upgrade(id: String) -> bool:
	return upgrade_block(id) == ""


## Начать стройку. Первый уровень строится сразу, дальше — несколько вылазок.
static func upgrade(id: String) -> bool:
	if not can_upgrade(id):
		return false
	pay(build_cost(id))
	var L := level(id) + 1
	var runs: int = BUILD_RUNS[mini(L, 5)]
	if runs <= 0:
		buildings[id] = L
	else:
		construct = {"id": id, "lvl": L, "left": runs}
	save()
	return true


static func add_reward(r: Dictionary) -> void:
	shards += int(r.get("shards", 0))
	for m in MATERIALS:
		materials[m] = int(materials.get(m, 0)) + int(r.get(m, 0))


## После вылазки стройка продвигается.
static func _advance_construction() -> void:
	if construct.is_empty():
		return
	construct["left"] = int(construct.get("left", 1)) - 1
	if int(construct["left"]) <= 0:
		buildings[construct["id"]] = int(construct["lvl"])
		just_built = str(construct["id"])
		construct = {}


static func hero_unlocked(id: String) -> bool:
	ensure_loaded()
	return id == "vega" or id in heroes_owned


## Значение показателя для условия (по всей статистике слота).
static func stat_value(kind: String, hero := "") -> int:
	ensure_loaded()
	match kind:
		"kills":
			return int(stats.get("kills", 0))
		"best_kills":
			return int(stats.get("best_kills", 0))
		"bosses":
			return int(stats.get("bosses", 0))
		"reactions":
			return int(stats.get("reactions", 0))
		"endless":
			return int(stats.get("best_endless", 0))
		"level":
			return levels_cleared
		"runs":
			return total_runs
		"max_level":
			return int(stats.get("max_level", 0))
		"hero_runs":
			return int(stats.get("heroes", {}).get(hero, 0))
		"wkills":
			return int(stats.get("wkills", {}).get(hero, 0))
		"hkills":
			return int(stats.get("hkills", {}).get(hero, 0))
		"wruns":
			return int(stats.get("wruns", {}).get(hero, 0))
		"mused":
			return int(stats.get("mused", {}).get(hero, 0))
		"hq":
			return int(stats.get("hq", {}).get(hero, 0))
		"quests", "caches", "puzzles", "beacons", "events", "elites", "nodmg_best", "fusions":
			return int(stats.get(kind, 0))
	return 0


static func cond_met(c: Array, hero := "") -> bool:
	return stat_value(c[0], hero) >= int(c[1])


static func conds_met(conds: Array, hero := "") -> bool:
	for c in conds:
		if not cond_met(c, hero):
			return false
	return true


## Текст условия: «Убейте 1500 врагов (523 / 1500)».
static func cond_text(c: Array, hero := "", with_progress := true) -> String:
	var v := int(c[1])
	var t := ""
	match str(c[0]):
		"kills":
			t = "Уничтожьте %d врагов (всего)" % v
		"best_kills":
			t = "Уничтожьте %d врагов за один забег" % v
		"bosses":
			t = "Победите боссов: %d" % v
		"reactions":
			t = "Вызовите реакций: %d" % v
		"endless":
			t = "Продержитесь %d мин в бесконечном режиме" % v
		"level":
			t = "Пройдите уровней: %d" % v
		"runs":
			t = "Совершите вылазок: %d" % v
		"max_level":
			t = "Достигните %d уровня в забеге" % v
		"hero_runs":
			t = "Вылазок этим героем: %d" % v
		"wkills":
			t = "Уничтожьте этим оружием врагов: %d" % v
		"hkills":
			t = "Уничтожьте этим героем врагов: %d" % v
		"wruns":
			t = "Вылазок с этим оружием: %d" % v
		"mused":
			t = "Вылазок с этим модулем: %d" % v
		"hq":
			t = "Выполните шагов личного задания героя: %d" % v
		"quests":
			t = "Выполните заданий с доски: %d" % v
		"caches":
			t = "Найдите тайников: %d" % v
		"puzzles":
			t = "Решите рунных загадок: %d" % v
		"beacons":
			t = "Зажгите маяки (раз): %d" % v
		"events":
			t = "Переживите случайных событий: %d" % v
		"elites":
			t = "Победите элитных врагов: %d" % v
		"nodmg_best":
			t = "Продержитесь без урона %d с" % v
		"fusions":
			t = "Совершите слияний оружия: %d" % v
	if with_progress:
		t += "  (%d / %d)" % [mini(stat_value(c[0], hero), v), v]
	return t


## Короткая подпись условия для кнопки узла: «боссы 1/3».
static func cond_short(c: Array, hero := "") -> String:
	var names := {"kills": "убийства", "best_kills": "убийств за забег", "bosses": "боссы", "reactions": "реакции",
		"endless": "бесконечный, мин", "level": "уровни", "runs": "вылазки", "max_level": "ур. в забеге", "hero_runs": "вылазки героем",
		"wkills": "убийства оружием", "hkills": "убийства героем", "wruns": "вылазки с оружием", "mused": "вылазки с модулем",
		"hq": "личное задание", "quests": "задания", "caches": "тайники", "puzzles": "загадки", "beacons": "маяки",
		"events": "события", "elites": "элита", "nodmg_best": "без урона, с", "fusions": "слияния"}
	return "%s %d/%d" % [names.get(str(c[0]), str(c[0])), mini(stat_value(c[0], hero), int(c[1])), int(c[1])]


## Первое невыполненное условие (или пустой массив).
static func first_unmet(conds: Array, hero := "") -> Array:
	for c in conds:
		if not cond_met(c, hero):
			return c
	return []


## Состояние героя в Зале: owned / open (можно открыть) / expensive / cond (условие не выполнено)
static func hero_rescued(id: String) -> bool:
	ensure_loaded()
	return id == "vega" or id in heroes_owned or id in rescued


static func parts_have(id: String) -> int:
	if hero_unlocked(id):
		return PARTS_NEED
	return mini(PARTS_NEED, int(parts.get(id, 0)))


## Кого ещё можно встретить пленником в бою.
static func rescue_candidates() -> Array:
	var out: Array = []
	for h in HERO_ORDER:
		if not hero_rescued(h):
			out.append(h)
	return out


## Чьё оружие сейчас ищем: спасённые, но с несобранным оружием.
static func parts_hunt() -> Array:
	var out: Array = []
	for h in HERO_ORDER:
		if hero_rescued(h) and parts_have(h) < PARTS_NEED:
			out.append(h)
	return out


static func add_part(id: String) -> int:
	parts[id] = mini(PARTS_NEED, int(parts.get(id, 0)) + 1)
	return int(parts[id])


static func rescue(id: String) -> void:
	if not (id in rescued):
		rescued.append(id)


## Оружие героя недоступно в бою, пока его не соберут (у открытых героев — всегда доступно).
static func weapon_available(w: String) -> bool:
	var D = preload("res://scripts/data.gd")
	for h in D.CHARACTERS:
		if h != "vega" and str(D.CHARACTERS[h].get("weapon", "")) == w:
			return parts_have(h) >= PARTS_NEED
	return true


static func hero_state(id: String) -> String:
	if hero_unlocked(id):
		return "owned"
	if not hero_rescued(id):
		return "lost"
	if parts_have(id) < PARTS_NEED:
		return "parts"
	var u: Dictionary = HERO_UNLOCK.get(id, {"cost": 99999, "conds": [["level", 99]]})
	if not conds_met(u["conds"]):
		return "cond"
	return "open" if shards >= int(u["cost"]) else "expensive"


static func unlock_hero(id: String) -> bool:
	if hero_state(id) != "open":
		return false
	shards -= int(HERO_UNLOCK[id]["cost"])
	heroes_owned.append(id)
	save()
	return true


static func follower_cap() -> int:
	return level("beacon") * 2


static func recruit_cost() -> int:
	return 30 + followers.size() * 25


static func can_recruit() -> bool:
	return followers.size() < follower_cap() and shards >= recruit_cost()


static func recruit() -> Dictionary:
	if not can_recruit():
		return {}
	shards -= recruit_cost()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var f := {"name": NAME_A[rng.randi_range(0, NAME_A.size() - 1)] + NAME_B[rng.randi_range(0, NAME_B.size() - 1)],
		"seed": rng.randi_range(1, 99999)}
	followers.append(f)
	save()
	return f


## Бонусы убежища, которые действуют в забеге.
static func run_mods() -> Dictionary:
	ensure_loaded()
	return {
		"damage": 1.0 + 0.06 * level("forge"),
		"hp": 0.0,
		"cooldown": 1.0,
		"magnet": 1.0,
		"xp": 1.0 + 0.05 * mini(level("hall"), 5),
		"chest": 0.1 * level("shrine"),
	}


## Подсчёт награды за забег. Возвращает словарь с подробностями.
static func finish_run(kills: int, time_alive: float, bosses: int, victory: bool, level := -1, first_bonus := 0, endless_min := 0, run := {}) -> Dictionary:
	ensure_loaded()
	var extra := _settle_run(run, victory)
	var first := 0
	if victory and level >= 0:
		if level >= levels_cleared:
			levels_cleared = level + 1
			first = first_bonus
		level_best[level] = maxf(float(level_best.get(level, 0.0)), time_alive)
	var r := {
		"first": first,
		"kills": kills / 10,
		"time": int(time_alive / 12.0),
		"bosses": bosses * 40,
		"victory": 100 if victory else 0,
		"followers": 0,
		"endless": endless_min * 25,
	}
	var total := 0
	for k in r:
		total += r[k]
	# Угроза и испытание вылазки повышают награду
	var bonus_k := 1.0 + 0.03 * float(run.get("threat", 0)) + float(CHALLENGES.get(run.get("challenge", ""), {}).get("bonus", 0.0))
	r["bonus"] = int(round(float(total) * (bonus_k - 1.0)))
	total += r["bonus"]
	r["total"] = total
	shards += total
	total_runs += 1
	stats["kills"] = int(stats.get("kills", 0)) + kills
	stats["time"] = float(stats.get("time", 0.0)) + time_alive
	stats["bosses"] = int(stats.get("bosses", 0)) + bosses
	stats["wins" if victory else "deaths"] = int(stats.get("wins" if victory else "deaths", 0)) + 1
	stats["best_endless"] = maxi(int(stats.get("best_endless", 0)), endless_min)
	stats["shards"] = int(stats.get("shards", 0)) + total
	stats["best_kills"] = maxi(int(stats.get("best_kills", 0)), kills)
	best_time = maxf(best_time, time_alive)
	r.merge(extra)
	last_reward = r
	save()
	return r


## Материалы, задания, мастерство оружия/героя, стройка.
static func _settle_run(run: Dictionary, victory: bool) -> Dictionary:
	var out := {"materials": {}, "quests": [], "built": ""}
	if run.is_empty():
		_advance_construction()
		out["built"] = just_built
		return out
	# Материалы: при поражении теряется часть добычи
	var k := 1.0 if victory else 0.6
	if has_node("c:" + str(run.get("hero", "")), "mats1"):
		k *= 1.2
	for m in MATERIALS:
		var v := int(round(float(run.get("mat_" + m, 0)) * k))
		if v > 0:
			materials[m] = int(materials.get(m, 0)) + v
			out["materials"][m] = v
	var hero: String = run.get("hero", "")
	for key in ["caches", "puzzles", "beacons", "events", "elites"]:
		stats[key] = int(stats.get(key, 0)) + int(run.get(key, 0))
	stats["nodmg_best"] = maxi(int(stats.get("nodmg_best", 0)), int(run.get("nodmg", 0)))
	stats["fusions"] = int(stats.get("fusions", 0)) + int(run.get("fusions", 0))
	var wk: Dictionary = stats.get("wkills", {})
	for w in run.get("wkills", {}):
		wk[w] = int(wk.get(w, 0)) + int(run["wkills"][w])
	stats["wkills"] = wk
	var wr: Dictionary = stats.get("wruns", {})
	for w in run.get("weapons", []):
		wr[w] = int(wr.get(w, 0)) + 1
	stats["wruns"] = wr
	var mu: Dictionary = stats.get("mused", {})
	for m in run.get("modules", []):
		mu[m] = int(mu.get(m, 0)) + 1
	stats["mused"] = mu
	if hero != "":
		var hk: Dictionary = stats.get("hkills", {})
		hk[hero] = int(hk.get(hero, 0)) + int(run.get("kills", 0))
		stats["hkills"] = hk
	out["quests"] = preload("res://scripts/quests.gd").settle(run, hero)
	_advance_construction()
	out["built"] = just_built
	return out



# ---------- Деревья ----------

static func tree_nodes(tree_key: String) -> Array:
	var extra: Array = preload("res://scripts/tree_extra.gd").nodes(tree_key)
	match tree_key.left(2):
		"w:":
			return WEAPON_TREE + extra
		"c:":
			return HERO_TREE + extra
		"m:":
			return MODULE_TREE + extra
	return []


static func _fx(tree_key: String) -> Dictionary:
	return preload("res://scripts/tree_extra.gd").fx_sum(tree_key, trees.get(tree_key, []))


static func tree_building(tree_key: String) -> String:
	return {"w:": "forge", "c:": "shrine", "m:": "lab"}.get(tree_key.left(2), "")


static func has_node(tree_key: String, node: String) -> bool:
	ensure_loaded()
	return node in trees.get(tree_key, [])


static func node_state(tree_key: String, n: Dictionary) -> String:
	if has_node(tree_key, n["id"]):
		return "owned"
	if level(tree_building(tree_key)) < int(n["tier"]):
		return "tier"
	for r in n["req"]:
		if not has_node(tree_key, r):
			return "locked"
	if n.has("req_any"):
		var any := false
		for r in n["req_any"]:
			any = any or has_node(tree_key, r)
		if not any:
			return "locked"
	if n.has("excl"):
		for m in tree_nodes(tree_key):
			if m.get("excl", "") == n["excl"] and m["id"] != n["id"] and has_node(tree_key, m["id"]):
				return "excl"
	if not conds_met(n.get("conds", []), tree_hero(tree_key)):
		return "cond"
	return "open" if shards >= node_cost(n) else "expensive"


## Для дерева героя «c:rin» — id героя (для условий «вылазок этим героем»).
static func tree_hero(tree_key: String) -> String:
	return tree_key.substr(2)   # герой, оружие или модуль дерева — «субъект» условий


static func buy_node(tree_key: String, n: Dictionary) -> bool:
	if node_state(tree_key, n) != "open":
		return false
	shards -= node_cost(n)
	if not trees.has(tree_key):
		trees[tree_key] = []
	trees[tree_key].append(n["id"])
	save()
	return true


## Модификаторы оружия из Арсенала.
static func weapon_mods(id: String) -> Dictionary:
	var k := "w:" + id
	var dmg := 1.0
	for pair in [["dmg1", 0.10], ["dmg2", 0.15], ["dmg3", 0.15], ["master", 0.20], ["legend", 0.25]]:
		if has_node(k, pair[0]):
			dmg += pair[1]
	var cd := 1.0
	for n in ["cd1", "cd2", "legend"]:
		if has_node(k, n):
			cd *= 0.9
	if has_node(k, "mythic"):
		cd *= 0.85
	var res := has_node(k, "resonance")
	var fx := _fx(k)
	return {"damage": maxf(0.3, dmg + float(fx.get("damage", 0.0))), "cooldown": cd * float(fx.get("cooldown", 1.0)),
		"count": int(has_node(k, "count")) + int(has_node(k, "overcharge")) + int(has_node(k, "mythic")) + int(fx.get("count", 0.0)),
		"area": maxf(0.5, 1.0 + (0.10 if has_node(k, "area1") else 0.0) + (0.15 if has_node(k, "count") else 0.0) + float(fx.get("area", 0.0))),
		"status": (1.3 if has_node(k, "status") else 1.0) + (0.15 if res else 0.0) + float(fx.get("status", 0.0)), "master": has_node(k, "master"),
		"duration": (1.25 if has_node(k, "dur") else 1.0) + (0.2 if res else 0.0) + float(fx.get("duration", 0.0)),
		"speed": (1.15 if has_node(k, "speed1") else 1.0) * (1.0 + float(fx.get("speed", 0.0))),
		"crit": (0.05 if has_node(k, "crit1") else 0.0) + float(fx.get("crit", 0.0)), "critdmg": (0.5 if has_node(k, "critdmg") else 0.0) + float(fx.get("critdmg", 0.0)),
		"elite": (1.3 if has_node(k, "elite") else 1.0) * float(fx.get("elite", 1.0)), "execute": (1.5 if has_node(k, "execute") else 1.0) * float(fx.get("execute", 1.0)),
		"leech": (0.3 if has_node(k, "leech") else 0.0) + float(fx.get("leech", 0.0)), "salvage": 1.0 if has_node(k, "salvage") else 0.0,
		"fusion": 1.2 if has_node(k, "fusion") else 1.0}


## Модификаторы героя из Академии.
static func hero_mods(id: String) -> Dictionary:
	var k := "c:" + id
	var asc := has_node(k, "ascend")
	var myth := has_node(k, "myth")
	var fx := _fx(k)
	var dmg := 1.0 + (0.06 if has_node(k, "legacy") else 0.0) + (0.08 if has_node(k, "legend_tale") else 0.0) \
		+ (0.12 if has_node(k, "hunter") else 0.0) + (0.2 if myth else 0.0) + float(fx.get("damage", 0.0))
	var out := {"hp": (15.0 if has_node(k, "hp1") else 0.0) + (20.0 if has_node(k, "hp2") else 0.0) + (30.0 if asc else 0.0)
			+ (10.0 if has_node(k, "legacy") else 0.0) + (20.0 if myth else 0.0),
		"damage": dmg, "laststand": has_node(k, "laststand"),
		"speed": (1.06 if has_node(k, "spd1") else 1.0) * (1.1 if asc else 1.0),
		"ability_cd": (0.85 if has_node(k, "cd") else 1.0) * (0.85 if has_node(k, "cd2") else 1.0)
			* (0.9 if has_node(k, "legend_tale") else 1.0) * (0.9 if myth else 1.0),
		"power": (1.3 if has_node(k, "power") else 1.0) + (0.2 if asc else 0.0),
		"armor": 1.0 if has_node(k, "armor") else 0.0, "awaken": has_node(k, "awaken"),
		"regen": 0.4 if has_node(k, "regen1") else 0.0, "magnet": 1.25 if has_node(k, "magnet1") else 1.0,
		"xp": 1.1 if has_node(k, "xp1") else 1.0, "dodge": 0.05 if has_node(k, "dodge1") else 0.0}
	# Личная ветвь героя
	out["hp"] = float(out["hp"]) + float(fx.get("hp", 0.0))
	out["speed"] = float(out["speed"]) * float(fx.get("speed", 1.0))
	out["ability_cd"] = float(out["ability_cd"]) * float(fx.get("ability_cd", 1.0))
	out["power"] = float(out["power"]) + float(fx.get("power", 0.0))
	out["armor"] = float(out["armor"]) + float(fx.get("armor", 0.0))
	out["regen"] = float(out["regen"]) + float(fx.get("regen", 0.0))
	out["magnet"] = float(out["magnet"]) * float(fx.get("magnet", 1.0))
	out["xp"] = float(out["xp"]) * float(fx.get("xp", 1.0))
	out["dodge"] = float(out["dodge"]) + float(fx.get("dodge", 0.0))
	return out


## Усиление модуля из Лаборатории (множитель эффекта) и предустановка.
static func module_boost(id: String) -> float:
	var k := "m:" + id
	var b := 1.0
	for pair in [["boost1", 0.25], ["boost2", 0.25], ["tune", 0.15], ["boost3", 0.25], ["boost4", 0.25], ["boost5", 0.5]]:
		if has_node(k, pair[0]):
			b += pair[1]
	return b + float(_fx(k).get("boost", 0.0))


static func module_preinstalled(id: String) -> bool:
	return has_node("m:" + id, "preinstall")


## Вся прокачка игрока для героя — отправляется хосту в сетевой игре,
## чтобы второй игрок играл со своими улучшениями.
## Дополнительная статистика забега (вызывается до finish_run).
static func note_run(reactions: int, max_level: int, hero: String) -> void:
	ensure_loaded()
	stats["reactions"] = int(stats.get("reactions", 0)) + reactions
	stats["max_level"] = maxi(int(stats.get("max_level", 0)), max_level)
	var h: Dictionary = stats.get("heroes", {})
	h[hero] = int(h.get(hero, 0)) + 1
	stats["heroes"] = h


static func profile(hero: String) -> Dictionary:
	ensure_loaded()
	var Data := preload("res://scripts/data.gd")
	var w := {}
	for id in Data.WEAPONS:
		w[id] = weapon_mods(id)
	var boost := {}
	var pre: Array = []
	for id in Data.PASSIVES:
		boost[id] = module_boost(id)
		if module_preinstalled(id):
			pre.append(id)
	return {"run": run_mods(), "hero": hero_mods(hero), "weapons": w, "boost": boost, "pre": pre, "nick": nickname}
