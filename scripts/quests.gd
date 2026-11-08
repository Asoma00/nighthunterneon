extends RefCounted
## Квесты: доска заданий в убежище (3 задания) и личные задания героев.
## Прогресс считается за ОДНУ вылазку — задание нужно выполнить в бою,
## а не накопить. Счётчики забега хранятся в main.run (см. main.gd).

const Meta := preload("res://scripts/meta.gd")

## k — счётчик забега; g — цели по ступеням сложности (ступень растёт с выполненными заданиями).
const POOL := {
	"kills": {"t": "Зачистка", "d": "Уничтожьте %d врагов за вылазку", "g": [250, 450, 700, 1000, 1400]},
	"elites": {"t": "Крупная дичь", "d": "Победите %d элитных врагов", "g": [2, 3, 5, 7, 10]},
	"boss": {"t": "Голова чудовища", "d": "Победите босса (%d)", "g": [1, 1, 1, 2, 2]},
	"altars": {"t": "Паломник", "d": "Активируйте алтари: %d", "g": [1, 2, 2, 3, 4]},
	"trials": {"t": "Испытание духа", "d": "Пройдите испытания алтаря: %d", "g": [1, 1, 2, 2, 3]},
	"caches": {"t": "Кладоискатель", "d": "Найдите тайники на карте: %d", "g": [1, 2, 2, 3, 4]},
	"puzzles": {"t": "Рунная загадка", "d": "Решите загадку рунных столбов: %d", "g": [1, 1, 1, 2, 2]},
	"beacons": {"t": "Свет во тьме", "d": "Зажгите все сигнальные маяки: %d", "g": [1, 1, 1, 2, 2]},
	"reactions": {"t": "Алхимия стихий", "d": "Вызовите %d реакций стихий", "g": [25, 50, 90, 140, 200]},
	"scrap": {"t": "Сборщик", "d": "Соберите %d лома", "g": [15, 30, 50, 75, 100]},
	"events": {"t": "Буревестник", "d": "Переживите случайные события: %d", "g": [1, 1, 2, 2, 3]},
	"nodmg": {"t": "Неуловимый", "d": "Продержитесь %d с подряд без урона", "g": [25, 40, 55, 75, 100]},
	"minutes": {"t": "Выживание", "d": "Продержитесь %d мин", "g": [3, 4, 5, 6, 8]},
	"level": {"t": "Рост силы", "d": "Достигните %d уровня героя за вылазку", "g": [10, 15, 20, 26, 32]},
	"combo": {"t": "Шквал", "d": "Наберите комбо из %d убийств", "g": [30, 50, 80, 120, 160]},
}

## Личные задания героев: цепочка из 3 шагов с кусочком истории.
## Выполняются только этим героем. Шаги открывают узлы его дерева («личное задание N»).
const HERO_QUESTS := {
	"vega": [
		["caches", 2, "Осколки посоха", "Вега ищет осколки старого посоха наставника — их растащили по тайникам пустоши."],
		["reactions", 60, "Резонанс", "Собранный посох отзывается на стихии. Вызовите реакции, чтобы настроить кристалл."],
		["puzzles", 1, "Печать Академии", "На посохе печать сгоревшей Академии. Руны пустоши знают, как её снять."],
	],
	"rin": [
		["kills", 400, "Путь клинка", "Рин дала клятву: не вкладывать катану в ножны, пока пустошь не станет тише."],
		["nodmg", 40, "Пустая форма", "Учитель говорил: лучший удар — тот, на который не ответили."],
		["elites", 5, "Долг чести", "Големы клана Тэцу носят знак её семьи. Пора вернуть его."],
	],
	"bram": [
		["scrap", 30, "Руда пустоши", "Кузнецу нужен металл. В пустоши его больше, чем в любой шахте."],
		["altars", 2, "Пламя рун", "Старые алтари хранят рунное пламя. Брам хочет разжечь им горн."],
		["boss", 1, "Наковальня колосса", "Говорят, сердце колосса — лучшая наковальня в мире."],
	],
	"kira": [
		["beacons", 1, "Сигнал", "Кира ловит в эфире чужой сигнал. Нужно поднять маяки, чтобы найти источник."],
		["reactions", 80, "Взлом стихий", "Сеть пустоши — это стихии. Кира учится их перепрограммировать."],
		["caches", 3, "Потерянный дрон", "Её первый дрон пропал в пустоши. Его части разбросаны по тайникам."],
	],
	"skyla": [
		["combo", 40, "Град", "Скайла проверяет новую тетиву: стрелы должны лететь без остановки."],
		["elites", 4, "Охота", "Старшие охотницы клана меряют добычу элитными зверями."],
		["minutes", 5, "Дозор", "Ночной дозор длится долго. Выстоять — тоже искусство."],
	],
	"orm": [
		["trials", 1, "Обет", "Паладин даёт обет у алтаря испытаний — и должен выдержать его."],
		["nodmg", 35, "Святая броня", "Броня Орма помнит каждый удар. Сегодня она не должна запомнить ни одного."],
		["boss", 1, "Очищение", "Ересь пустоши носит лицо босса. Орм идёт её очистить."],
	],
	"mora": [
		["kills", 500, "Жатва данных", "Мора собирает обрывки душ-кодов павших врагов."],
		["puzzles", 1, "Мёртвый язык", "Рунные столбы говорят на мёртвом языке. Мора его помнит."],
		["events", 2, "Шёпот бури", "В случайных бурях слышны голоса тех, кого она потеряла."],
	],
	"zephyr": [
		["events", 1, "Зов шторма", "Шаман чувствует бурю ещё до её прихода."],
		["beacons", 1, "Громоотводы", "Маяки — это громоотводы. Зефир хочет собрать в них молнии."],
		["reactions", 120, "Око бури", "Чем больше стихий сталкивается, тем ближе Око бури."],
	],
	"iris": [
		["scrap", 25, "Реактивы", "Для нового зелья нужен лом с особыми примесями."],
		["altars", 2, "Живая вода", "Источники жизни — лучшая основа для эликсиров."],
		["level", 20, "Мутация", "Ирис проверяет на себе формулу роста силы."],
	],
	"kai": [
		["nodmg", 45, "Тень", "Ниндзя, которого задели, — плохой ниндзя."],
		["caches", 2, "Свитки клана", "Кай ищет украденные свитки клана Безлунных."],
		["combo", 80, "Тысяча сюрикенов", "Финальное испытание клана: шквал без передышки."],
	],
}

const REWARD_BASE := {"shards": 40, "scrap": 6, "chips": 0, "cores": 0}


static func tier() -> int:
	return clampi(int(Meta.stats.get("quests_done", 0)) / 4, 0, 4)


## Новое задание для доски (не повторяет уже взятые).
static func make(exclude: Array) -> Dictionary:
	var keys: Array = POOL.keys().filter(func(k): return not (k in exclude))
	# Боссы бывают не на каждом уровне — задание на босса реже
	if keys.has("boss") and randf() < 0.6:
		keys.erase("boss")
	var k: String = keys[randi() % keys.size()]
	var t := tier()
	return {"k": k, "g": int(POOL[k]["g"][t]), "tier": t}


static func reward(q: Dictionary) -> Dictionary:
	var t := int(q.get("tier", 0))
	var r := {"shards": 40 + 25 * t, "scrap": 5 + 3 * t, "chips": 1 + t / 2, "cores": 1 if t >= 3 else 0}
	if q.has("hero"):
		r = {"shards": 120, "scrap": 10, "chips": 3, "cores": 1}
	return r


static func reward_text(r: Dictionary) -> String:
	var parts: Array = []
	if int(r.get("shards", 0)) > 0:
		parts.append("%d ◆" % int(r["shards"]))
	for m in Meta.MATERIALS:
		if int(r.get(m, 0)) > 0:
			parts.append("%d %s" % [int(r[m]), Meta.MATERIALS[m]["icon"]])
	return "  ".join(parts)


static func title(q: Dictionary) -> String:
	if q.has("hero"):
		return str(q.get("title", ""))
	return POOL[q["k"]]["t"]


static func desc(q: Dictionary) -> String:
	if q.get("k") == "boss":
		return "Победите босса" if int(q["g"]) <= 1 else "Победите боссов: %d" % int(q["g"])
	return POOL[q["k"]]["d"] % int(q["g"])


## Доска заданий: всегда 3 задания.
static func board() -> Array:
	Meta.ensure_loaded()
	var b: Array = Meta.quests
	while b.size() < 3:
		var ex: Array = []
		for q in b:
			ex.append(q["k"])
		b.append(make(ex))
	Meta.quests = b
	return b


## Личное задание героя (текущий шаг) или пустой словарь, если цепочка пройдена.
static func hero_quest(hero: String) -> Dictionary:
	var steps: Array = HERO_QUESTS.get(hero, [])
	var n := int(Meta.stats.get("hq", {}).get(hero, 0))
	if n >= steps.size():
		return {}
	var s: Array = steps[n]
	return {"k": s[0], "g": int(s[1]), "title": s[2], "lore": s[3], "hero": hero, "step": n, "tier": 2}


static func hero_step(hero: String) -> int:
	return int(Meta.stats.get("hq", {}).get(hero, 0))


## Все активные задания этого забега (доска + личное задание героя).
static func active(hero: String) -> Array:
	var out: Array = board().duplicate(true)
	var hq := hero_quest(hero)
	if not hq.is_empty():
		out.append(hq)
	return out


static func progress(q: Dictionary, run: Dictionary) -> int:
	return int(run.get(q["k"], 0))


static func done(q: Dictionary, run: Dictionary) -> bool:
	return progress(q, run) >= int(q["g"])


## Конец забега: выполненные задания — награда, на доске появляются новые.
## Возвращает список выполненных [название, награда].
static func settle(run: Dictionary, hero: String) -> Array:
	Meta.ensure_loaded()
	var out: Array = []
	var keep: Array = []
	for q in board():
		if done(q, run):
			var r := reward(q)
			Meta.add_reward(r)
			out.append([title(q), reward_text(r)])
			Meta.stats["quests_done"] = int(Meta.stats.get("quests_done", 0)) + 1
		else:
			keep.append(q)
	Meta.quests = keep
	board()
	var hq := hero_quest(hero)
	if not hq.is_empty() and done(hq, run):
		var r := reward(hq)
		Meta.add_reward(r)
		var h: Dictionary = Meta.stats.get("hq", {})
		h[hero] = int(h.get(hero, 0)) + 1
		Meta.stats["hq"] = h
		Meta.stats["quests_done"] = int(Meta.stats.get("quests_done", 0)) + 1
		out.append(["Личное: " + str(hq["title"]), reward_text(r)])
	return out
