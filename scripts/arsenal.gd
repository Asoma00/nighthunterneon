extends RefCounted
## Арсенал охотника: какое оружие выковано, какие модули открыты, и достижения.
##
##  • Оружие. С самого начала есть только «Неоновый болт». Остальное нужно НАЙТИ:
##    части выпадают в бою (оружие героев — обломки рядом с местом, где томится герой;
##    остальное — из сундуков, элиты, боссов). Когда все части собраны — оружие
##    сковывают в Рунной кузнице. Только после ковки оно попадается при повышении уровня.
##  • Модули. С начала открыты четыре. Остальные открываются по-разному и вперемешку:
##    условием прохождения, сбором чертежей по частям или открытием героя.
##  • Достижения — от самых простых до легендарных, с наградами.

const Meta := preload("res://scripts/meta.gd")

const START_WEAPONS := ["bolt"]

## Оружие без своего героя: части добываются в бою.
## src: chest — сундуки, elite — элитные враги, boss — боссы, cache — тайники, puzzle — загадки.
const WEAPON_PARTS := {
	"blades": {"need": 3, "src": "chest"},
	"aura": {"need": 3, "src": "elite"},
	"lightning": {"need": 2, "src": "boss"},
}

const SRC_TEXT := {
	"chest": "сундуки", "elite": "элитные враги", "boss": "боссы", "cache": "тайники", "puzzle": "рунные загадки",
	"hero": "обломки у места, где томится герой",
}
## Шанс выпадения части при событии (если ещё есть что искать из этого источника).
const SRC_CHANCE := {"chest": 0.4, "elite": 0.14, "boss": 1.0, "cache": 0.6, "puzzle": 0.7}

const START_MODULES := ["hp", "damage", "speed", "cooldown"]

## Как открывается модуль: ["start"], ["cond", [вид, число]], ["hero", id], ["parts", N, источник].
const MODULE_UNLOCK := {
	"hp": ["start"], "damage": ["start"], "speed": ["start"], "cooldown": ["start"],
	"magnet": ["cond", ["kills", 300]],
	"area": ["parts", 3, "chest"],
	"regen": ["hero", "rin"],
	"crit": ["cond", ["bosses", 1]],
	"pierce": ["parts", 3, "elite"],
	"armor": ["hero", "bram"],
	"duration": ["cond", ["reactions", 150]],
	"luck": ["parts", 3, "cache"],
	"vamp": ["hero", "mora"],
	"multi": ["parts", 4, "puzzle"],
	"execute": ["cond", ["elites", 30]],
	"toxin": ["hero", "kira"],
	"shield": ["cond", ["nodmg_best", 45]],
	"giant": ["cond", ["level", 3]],
	"dodge": ["hero", "kai"],
	"dash": ["hero", "zephyr"],
}


# ---------------- Оружие ----------------

## Чьё это оружие (герой) или "" для оружия без героя.
static func weapon_hero(w: String) -> String:
	var D = preload("res://scripts/data.gd")
	for h in D.CHARACTERS:
		if h != "vega" and str(D.CHARACTERS[h].get("weapon", "")) == w:
			return h
	return ""


static func parts_need(w: String) -> int:
	if WEAPON_PARTS.has(w):
		return int(WEAPON_PARTS[w]["need"])
	return Meta.PARTS_NEED


static func parts_got(w: String) -> int:
	Meta.ensure_loaded()
	if w in Meta.forged:
		return parts_need(w)
	if WEAPON_PARTS.has(w):
		return mini(parts_need(w), int(Meta.wparts.get(w, 0)))
	var h := weapon_hero(w)
	if h != "":
		return mini(Meta.PARTS_NEED, int(Meta.parts.get(h, 0))) if not Meta.hero_unlocked(h) else Meta.PARTS_NEED
	return mini(parts_need(w), int(Meta.wparts.get(w, 0)))


static func weapon_src(w: String) -> String:
	if WEAPON_PARTS.has(w):
		return str(WEAPON_PARTS[w]["src"])
	return "hero" if weapon_hero(w) != "" else ""


static func is_forged(w: String) -> bool:
	Meta.ensure_loaded()
	return w in START_WEAPONS or w in Meta.forged


## Состояние оружия в кузнице: forged / ready (все части есть) / parts (ищем части) / lost (не встречалось).
static func weapon_state(w: String) -> String:
	if is_forged(w):
		return "forged"
	var got := parts_got(w)
	if got >= parts_need(w):
		return "ready"
	var h := weapon_hero(w)
	if h != "" and not WEAPON_PARTS.has(w) and not Meta.hero_rescued(h) and got == 0:
		return "lost"
	return "parts"


static func forge_cost(w: String) -> Dictionary:
	if weapon_hero(w) != "":
		return {"shards": 160, "scrap": 14, "chips": 4}
	return {"shards": 90, "scrap": 10, "chips": 1}


## Почему нельзя ковать ("" — можно).
static func forge_block(w: String) -> String:
	match weapon_state(w):
		"forged":
			return "уже выковано"
		"lost", "parts":
			return "собраны не все части (%d / %d)" % [parts_got(w), parts_need(w)]
	if Meta.level("forge") <= 0:
		return "сначала постройте кузницу"
	if not Meta.can_afford(forge_cost(w)):
		return "не хватает: " + Meta.cost_text(forge_cost(w))
	return ""


static func forge(w: String) -> bool:
	if forge_block(w) != "":
		return false
	Meta.pay(forge_cost(w))
	Meta.forged.append(w)
	Meta.discover("w:" + w)
	Meta.save()
	return true


static func forged_count() -> int:
	var D = preload("res://scripts/data.gd")
	var n := 0
	for w in D.WEAPONS:
		if is_forged(w):
			n += 1
	return n


# ---------------- Модули ----------------

static func module_open(m: String) -> bool:
	Meta.ensure_loaded()
	if m in Meta.mods_open:
		return true
	return _module_ready(m)


static func _module_ready(m: String) -> bool:
	var u: Array = MODULE_UNLOCK.get(m, ["start"])
	match str(u[0]):
		"start":
			return true
		"cond":
			return Meta.cond_met(u[1])
		"hero":
			return Meta.hero_unlocked(str(u[1]))
		"parts":
			return int(Meta.mparts.get(m, 0)) >= int(u[1])
	return false


static func modules_count() -> int:
	var D = preload("res://scripts/data.gd")
	var n := 0
	for m in D.PASSIVES:
		if module_open(m):
			n += 1
	return n


## Как открыть модуль — для библиотеки и лаборатории.
static func module_how(m: String) -> String:
	var u: Array = MODULE_UNLOCK.get(m, ["start"])
	match str(u[0]):
		"start":
			return "Доступен с самого начала"
		"cond":
			return "Открытие: " + Meta.cond_text(u[1])
		"hero":
			var D = preload("res://scripts/data.gd")
			return "Открытие: откройте героя «%s»" % str(D.CHARACTERS.get(str(u[1]), {}).get("name", u[1]))
		"parts":
			return "Открытие: соберите чертёж по частям (%d / %d) — %s" % [mini(int(Meta.mparts.get(m, 0)), int(u[1])), int(u[1]), SRC_TEXT.get(str(u[2]), "")]
	return ""


# ---------------- Добыча частей в бою ----------------

## Что сейчас можно найти из этого источника: [["w"|"m", id], ...].
static func wanted(src: String) -> Array:
	Meta.ensure_loaded()
	var out: Array = []
	for w in WEAPON_PARTS:
		if str(WEAPON_PARTS[w]["src"]) == src and not is_forged(w) and parts_got(w) < parts_need(w):
			out.append(["w", w])
	for m in MODULE_UNLOCK:
		var u: Array = MODULE_UNLOCK[m]
		if str(u[0]) == "parts" and str(u[2]) == src and not module_open(m):
			out.append(["m", m])
	return out


## Бросок добычи: возвращает {} или {"kind", "id", "n", "need"} — найденная часть.
static func roll(src: String, rng: RandomNumberGenerator) -> Dictionary:
	var list := wanted(src)
	if list.is_empty() or rng.randf() > float(SRC_CHANCE.get(src, 0.0)):
		return {}
	var pick: Array = list[rng.randi() % list.size()]
	var id: String = pick[1]
	if pick[0] == "w":
		Meta.wparts[id] = int(Meta.wparts.get(id, 0)) + 1
		return {"kind": "w", "id": id, "n": parts_got(id), "need": parts_need(id)}
	Meta.mparts[id] = int(Meta.mparts.get(id, 0)) + 1
	var need := int(MODULE_UNLOCK[id][1])
	return {"kind": "m", "id": id, "n": mini(need, int(Meta.mparts[id])), "need": need}


# ---------------- Достижения ----------------

## tier: 0 — бронза, 1 — серебро, 2 — золото, 3 — легенда.
const TIERS := [
	{"name": "Бронза", "color": Color(0.85, 0.55, 0.3), "reward": {"shards": 30}},
	{"name": "Серебро", "color": Color(0.75, 0.85, 0.95), "reward": {"shards": 80, "scrap": 6}},
	{"name": "Золото", "color": Color(1.0, 0.82, 0.3), "reward": {"shards": 200, "chips": 4}},
	{"name": "Легенда", "color": Color(1.0, 0.4, 0.9), "reward": {"shards": 500, "cores": 3}},
]

const ACHIEVEMENTS := [
	# ---- Бронза: самое начало ----
	{"id": "first_blood", "name": "Первая кровь", "t": 0, "c": ["kills", 1]},
	{"id": "first_run", "name": "Первая вылазка", "t": 0, "c": ["runs", 1]},
	{"id": "lvl5", "name": "Набираю силу", "t": 0, "c": ["max_level", 5]},
	{"id": "chest1", "name": "Кладоискатель", "t": 0, "c": ["chests", 1]},
	{"id": "kills100", "name": "Сотня", "t": 0, "c": ["kills", 100]},
	{"id": "elite1", "name": "Не такой уж элитный", "t": 0, "c": ["elites", 1]},
	{"id": "mods6", "name": "Паяльник", "t": 0, "c": ["modules", 6]},
	{"id": "forge2", "name": "Первая ковка", "t": 0, "c": ["forged", 2]},
	# ---- Серебро ----
	{"id": "kills1000", "name": "Тысяча теней", "t": 1, "c": ["kills", 1000]},
	{"id": "boss1", "name": "Убийца великанов", "t": 1, "c": ["bosses", 1]},
	{"id": "level1", "name": "Первый рубеж", "t": 1, "c": ["level", 1]},
	{"id": "react100", "name": "Алхимик стихий", "t": 1, "c": ["reactions", 100]},
	{"id": "heroes2", "name": "Уже не один", "t": 1, "c": ["heroes", 2]},
	{"id": "caches5", "name": "Нюх на тайники", "t": 1, "c": ["caches", 5]},
	{"id": "puzzles3", "name": "Знаток рун", "t": 1, "c": ["puzzles", 3]},
	{"id": "lvl20", "name": "Неоновый пик", "t": 1, "c": ["max_level", 20]},
	{"id": "runs10", "name": "Завсегдатай Врат", "t": 1, "c": ["runs", 10]},
	{"id": "nodmg30", "name": "Неуловимый", "t": 1, "c": ["nodmg_best", 30]},
	{"id": "chests25", "name": "Сундучник", "t": 1, "c": ["chests", 25]},
	# ---- Золото ----
	{"id": "kills10000", "name": "Жнец пустошей", "t": 2, "c": ["kills", 10000]},
	{"id": "bosses10", "name": "Гроза владык", "t": 2, "c": ["bosses", 10]},
	{"id": "level5", "name": "Глубже во тьму", "t": 2, "c": ["level", 5]},
	{"id": "forge6", "name": "Мастер-оружейник", "t": 2, "c": ["forged", 6]},
	{"id": "mods12", "name": "Инженер модулей", "t": 2, "c": ["modules", 12]},
	{"id": "heroes6", "name": "Отряд света", "t": 2, "c": ["heroes", 6]},
	{"id": "endless15", "name": "Вечная ночь", "t": 2, "c": ["endless", 15]},
	{"id": "best1500", "name": "Бойня", "t": 2, "c": ["best_kills", 1500]},
	{"id": "fusions3", "name": "Кузнец слияний", "t": 2, "c": ["fusions", 3]},
	{"id": "elites100", "name": "Охотник на элиту", "t": 2, "c": ["elites", 100]},
	{"id": "nodmg90", "name": "Призрак", "t": 2, "c": ["nodmg_best", 90]},
	{"id": "rank10", "name": "Ветеран убежища", "t": 2, "c": ["rank", 10]},
	# ---- Легенда ----
	{"id": "kills50000", "name": "Конец Хора", "t": 3, "c": ["kills", 50000]},
	{"id": "bosses50", "name": "Палач владык", "t": 3, "c": ["bosses", 50]},
	{"id": "level15", "name": "Половина пути", "t": 3, "c": ["level", 15]},
	{"id": "level30", "name": "Последний свет", "t": 3, "c": ["level", 30]},
	{"id": "forge_all", "name": "Полный арсенал", "t": 3, "c": ["forged", 13]},
	{"id": "mods_all", "name": "Все чертежи", "t": 3, "c": ["modules", 20]},
	{"id": "heroes_all", "name": "Все на стене", "t": 3, "c": ["heroes", 13]},
	{"id": "endless30", "name": "Рассвет не наступит", "t": 3, "c": ["endless", 30]},
	{"id": "nodmg180", "name": "Неприкасаемый", "t": 3, "c": ["nodmg_best", 180]},
	{"id": "all", "name": "Легенда убежища", "t": 3, "c": ["achievements", 40]},
]


static func ach_done(id: String) -> bool:
	Meta.ensure_loaded()
	return id in Meta.achieved


static func ach_reward(a: Dictionary) -> Dictionary:
	return TIERS[int(a["t"])]["reward"]


# ---------------- Проверка открытий ----------------

## Проверяет модули и достижения. Возвращает новые открытия: [["m", id] | ["a", id] | ["w", id]].
## Награды за достижения начисляются сразу.
static func refresh() -> Array:
	Meta.ensure_loaded()
	var out: Array = []
	var D = preload("res://scripts/data.gd")
	for m in D.PASSIVES:
		if not (m in Meta.mods_open) and _module_ready(m):
			Meta.mods_open.append(m)
			if not (m in START_MODULES):
				out.append(["m", m])
	for w in D.WEAPONS:
		var st := weapon_state(w)
		var key: String = "ready:" + str(w)
		if st == "ready" and not Meta.seen.has(key):
			Meta.seen[key] = true
			out.append(["w", w])
	# Достижения: несколько проходов — одно может открыть другое («Легенда убежища»)
	for _pass in 2:
		for a in ACHIEVEMENTS:
			if a["id"] in Meta.achieved:
				continue
			if Meta.cond_met(a["c"]):
				Meta.achieved.append(a["id"])
				var r := ach_reward(a)
				Meta.shards += int(r.get("shards", 0))
				for k in Meta.MATERIALS:
					Meta.materials[k] = int(Meta.materials.get(k, 0)) + int(r.get(k, 0))
				out.append(["a", a["id"]])
	return out


static func ach_by_id(id: String) -> Dictionary:
	for a in ACHIEVEMENTS:
		if a["id"] == id:
			return a
	return {}


## Подписи открытий для тоста и экрана итогов.
static func unlock_lines(list: Array) -> Array:
	var D = preload("res://scripts/data.gd")
	var out: Array = []
	for u in list:
		match str(u[0]):
			"m":
				out.append("◈ Открыт модуль «%s»" % D.PASSIVES[u[1]]["name"])
			"w":
				out.append("⚒ Все части «%s» собраны — скуйте в кузнице!" % D.WEAPONS[u[1]]["name"])
			"a":
				var a := ach_by_id(str(u[1]))
				out.append("★ Достижение «%s» (%s): +%s" % [a.get("name", ""), TIERS[int(a.get("t", 0))]["name"], Meta.cost_text(ach_reward(a))])
	return out


## Перенос старых сохранений: всё, что игрок уже имел, остаётся.
static func migrate(old_save: bool) -> void:
	var D = preload("res://scripts/data.gd")
	if old_save:
		for w in ["blades", "aura", "lightning"]:
			if not (w in Meta.forged):
				Meta.forged.append(w)
		for h in Meta.heroes_owned:
			var w: String = str(D.CHARACTERS.get(h, {}).get("weapon", ""))
			if w != "" and not (w in Meta.forged):
				Meta.forged.append(w)
		# Модули, которые уже были в игре до 0.15.12, остаются открытыми
		for m in ["hp", "speed", "magnet", "regen", "armor", "vamp", "luck", "damage", "cooldown", "area", "crit", "multi", "duration"]:
			if not (m in Meta.mods_open):
				Meta.mods_open.append(m)
	if not ("bolt" in Meta.forged):
		Meta.forged.push_front("bolt")
