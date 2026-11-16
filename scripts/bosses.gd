extends RefCounted
## Свой босс на каждом уровне: 30 владык, ни один не повторяется.
## base — телосложение (лич / колосс / королева / омега), body/glow — окраска,
## feats — свой облик поверх основы, abil — приёмы по фазам, phases — названия фаз.

const ROSTER := [
	# ---------- Глава 1: Неоновый город ----------
	{"id": "b01", "name": "Неоновый Падальщик", "base": "queen", "body": Color(0.22, 0.2, 0.3), "glow": Color(1.0, 0.3, 0.75),
		"feats": ["eyes", "spikes"], "abil": [["fan", "summon_bat"], ["swirl", "teleport"], ["homing_burst", "eggs"]],
		"phases": ["Голод", "Стая слетается", "Пир на костях"], "hp": 0.8},
	{"id": "b02", "name": "Кристальная Матка", "base": "queen", "body": Color(0.2, 0.3, 0.4), "glow": Color(0.35, 0.95, 1.0),
		"feats": ["shards", "orbs"], "abil": [["fan", "summon_spider"], ["pull", "swirl"], ["eggs", "beam"]],
		"phases": ["Звон кристаллов", "Разлом поёт", "Осколочная буря"]},
	{"id": "b03", "name": "Нейро-Лич", "base": "lich", "keep": true, "feats": [], "glow": Color(0.75, 0.4, 1.0)},
	{"id": "b04", "name": "Корневой Страж", "base": "colossus", "body": Color(0.22, 0.3, 0.22), "glow": Color(0.45, 1.0, 0.4),
		"feats": ["tentacles", "cracks"], "abil": [["charge"], ["stomp", "mines"], ["rockfall", "shield"]],
		"phases": ["Корни шевелятся", "Чаща проснулась", "Древо гнева"]},
	{"id": "b05", "name": "Королева Дронов", "base": "queen", "body": Color(0.3, 0.3, 0.33), "glow": Color(1.0, 0.6, 0.15),
		"feats": ["orbs", "mask"], "abil": [["fan", "summon_bat"], ["homing_burst", "mines"], ["eggs", "beam", "pull"]],
		"phases": ["Взлёт", "Рой дронов", "Ковровый удар"]},
	{"id": "b06", "name": "Колосс Врат", "base": "colossus", "keep": true, "feats": [], "glow": Color(1.0, 0.5, 0.15)},
	{"id": "b07", "name": "Рунный Некромант", "base": "lich", "body": Color(0.16, 0.24, 0.18), "glow": Color(0.4, 1.0, 0.55),
		"feats": ["horns", "chains"], "abil": [["skulls", "summon_imp"], ["ring", "teleport", "summon_wraith"], ["meteors", "stream"]],
		"phases": ["Руны горят", "Мёртвые встают", "Некрополь зовёт"]},
	{"id": "b08", "name": "Матерь Роя", "base": "queen", "body": Color(0.3, 0.26, 0.14), "glow": Color(1.0, 0.85, 0.2),
		"feats": ["tail", "eyes"], "abil": [["summon_bat", "fan"], ["summon_spider", "eggs"], ["swirl", "homing_burst", "pull"]],
		"phases": ["Гул", "Рой поднимается", "Улей в ярости"]},
	{"id": "b09", "name": "Королева Терний", "base": "queen", "body": Color(0.3, 0.14, 0.2), "glow": Color(1.0, 0.25, 0.35),
		"feats": ["crown", "spikes"], "abil": [["fan", "summon_bat", "teleport"], ["swirl", "summon_spider", "pull"], ["eggs", "homing_burst", "beam"]],
		"phases": ["Охота", "Терновый трон", "Матка гнева"]},
	{"id": "b10", "name": "Омега", "base": "omega", "keep": true, "feats": [], "glow": Color(1.0, 0.85, 0.35)},
	# ---------- Глава 2: Пепел и сплав ----------
	{"id": "b11", "name": "Пепельный Голем", "base": "colossus", "body": Color(0.3, 0.22, 0.2), "glow": Color(1.0, 0.4, 0.1),
		"feats": ["flames", "cracks"], "abil": [["charge", "stomp"], ["waves", "rockfall"], ["multi_charge", "meteors"]],
		"phases": ["Тлеет", "Раскалённый корпус", "Извержение"]},
	{"id": "b12", "name": "Шахтёр Глубин", "base": "colossus", "body": Color(0.32, 0.28, 0.18), "glow": Color(1.0, 0.85, 0.25),
		"feats": ["mask", "chains"], "abil": [["charge", "mines"], ["rockfall", "stomp"], ["multi_charge", "waves", "shield"]],
		"phases": ["Забой", "Обвал", "Сердце копей"]},
	{"id": "b13", "name": "Литейный Лич", "base": "lich", "body": Color(0.3, 0.18, 0.12), "glow": Color(1.0, 0.55, 0.15),
		"feats": ["crown", "flames"], "abil": [["ring", "meteors"], ["stream", "teleport"], ["beam", "skulls", "summon_imp"]],
		"phases": ["Плавка", "Жидкий металл", "Последняя отливка"]},
	{"id": "b14", "name": "Обугленная Вдова", "base": "queen", "body": Color(0.18, 0.14, 0.14), "glow": Color(1.0, 0.3, 0.2),
		"feats": ["horns", "tail"], "abil": [["fan", "summon_spider"], ["pull", "eggs"], ["beam", "swirl"]],
		"phases": ["Паутина", "Гнездо в огне", "Вдовий танец"]},
	{"id": "b15", "name": "Ржавый Дракон", "base": "queen", "body": Color(0.34, 0.2, 0.12), "glow": Color(1.0, 0.5, 0.15),
		"feats": ["wings", "spikes", "tail"], "abil": [["fan", "stream"], ["meteors", "swirl"], ["beam", "homing_burst", "pull"]],
		"phases": ["Скрежет", "Пламя из пасти", "Огненный шторм"]},
	{"id": "b16", "name": "Пепельный Колосс", "base": "colossus", "body": Color(0.26, 0.16, 0.16), "glow": Color(1.0, 0.2, 0.15),
		"feats": ["crown", "flames", "spikes"], "abil": [["charge", "waves"], ["stomp", "mines", "shield"], ["multi_charge", "rockfall", "meteors"]],
		"phases": ["Разгон", "Пепельная броня", "Сердце вразнос"]},
	{"id": "b17", "name": "Хозяин Литейщиков", "base": "lich", "body": Color(0.28, 0.22, 0.14), "glow": Color(1.0, 0.7, 0.2),
		"feats": ["horns", "mantle", "chains"], "abil": [["summon_guard", "ring"], ["skulls", "teleport"], ["stream", "meteors", "summon_wraith"]],
		"phases": ["Смена", "Цех встаёт", "Литьё душ"]},
	{"id": "b18", "name": "Пепельница-Матка", "base": "queen", "body": Color(0.3, 0.2, 0.16), "glow": Color(1.0, 0.45, 0.25),
		"feats": ["eyes", "orbs"], "abil": [["summon_bat", "eggs"], ["fan", "swirl"], ["homing_burst", "pull", "beam"]],
		"phases": ["Кладка", "Пепельный рой", "Улей пылает"]},
	{"id": "b19", "name": "Королева Пепла", "base": "queen", "body": Color(0.22, 0.12, 0.12), "glow": Color(1.0, 0.35, 0.1),
		"feats": ["crown", "wings"], "abil": [["fan", "teleport"], ["swirl", "summon_spider", "meteors"], ["eggs", "homing_burst", "beam"]],
		"phases": ["Пепельный трон", "Крылья углей", "Королевский пожар"]},
	{"id": "b20", "name": "Омега-Сплав", "base": "omega", "body": Color(0.3, 0.2, 0.16), "glow": Color(1.0, 0.5, 0.15),
		"feats": ["flames", "orbs"], "abil": [["ring", "fan", "charge"], ["beam", "meteors", "summon_guard"], ["stream", "shield", "pull", "rockfall"]],
		"phases": ["Испытание огнём", "Сплав стихий", "Конец второй главы"]},
	# ---------- Глава 3: Цитадель и Врата ----------
	{"id": "b21", "name": "Привратник Цитадели", "base": "colossus", "body": Color(0.22, 0.26, 0.34), "glow": Color(0.5, 0.85, 1.0),
		"feats": ["mask", "halo", "spikes"], "abil": [["charge", "shield"], ["waves", "stomp"], ["multi_charge", "beam"]],
		"phases": ["Стой!", "Засов сорван", "Цитадель не пустит"]},
	{"id": "b22", "name": "Искажённая Садовница", "base": "queen", "body": Color(0.14, 0.28, 0.26), "glow": Color(0.3, 1.0, 0.8),
		"feats": ["tentacles", "orbs"], "abil": [["pull", "fan"], ["swirl", "eggs"], ["teleport", "homing_burst", "stream"]],
		"phases": ["Цветение", "Искажение", "Сад пожирает"]},
	{"id": "b23", "name": "Архивариус Слияния", "base": "lich", "body": Color(0.14, 0.22, 0.3), "glow": Color(0.35, 0.9, 1.0),
		"feats": ["halo", "orbs", "mask"], "abil": [["ring", "beam"], ["teleport", "skulls"], ["stream", "meteors", "pull"]],
		"phases": ["Каталог", "Стирание", "Слияние"]},
	{"id": "b24", "name": "Мост-Левиафан", "base": "colossus", "body": Color(0.16, 0.22, 0.32), "glow": Color(0.3, 0.6, 1.0),
		"feats": ["tentacles", "eyes"], "abil": [["charge", "pull"], ["waves", "rockfall"], ["multi_charge", "stream"]],
		"phases": ["Глубина", "Мост дрожит", "Пасть миров"]},
	{"id": "b25", "name": "Машина-Дракон", "base": "queen", "body": Color(0.26, 0.28, 0.32), "glow": Color(0.6, 0.95, 1.0),
		"feats": ["wings", "horns", "tail"], "abil": [["fan", "charge"], ["stream", "meteors"], ["beam", "swirl", "homing_burst"]],
		"phases": ["Пробуждение", "Форсаж", "Драконий залп"]},
	{"id": "b26", "name": "Небесный Колосс", "base": "colossus", "body": Color(0.34, 0.32, 0.26), "glow": Color(1.0, 0.92, 0.55),
		"feats": ["halo", "wings", "crown"], "abil": [["charge", "ring"], ["stomp", "beam", "shield"], ["multi_charge", "meteors", "waves"]],
		"phases": ["Небо гремит", "Свет и сталь", "Небесный суд"]},
	{"id": "b27", "name": "Хормейстер Призраков", "base": "lich", "body": Color(0.24, 0.2, 0.32), "glow": Color(0.85, 0.7, 1.0),
		"feats": ["halo", "chains", "mantle"], "abil": [["summon_wraith", "ring"], ["stream", "teleport"], ["beam", "skulls", "swirl"]],
		"phases": ["Распевка", "Хор теней", "Реквием"]},
	{"id": "b28", "name": "Матка Цитадели", "base": "queen", "body": Color(0.24, 0.16, 0.3), "glow": Color(0.8, 0.4, 1.0),
		"feats": ["crown", "eyes", "spikes"], "abil": [["summon_spider", "fan"], ["eggs", "pull", "teleport"], ["homing_burst", "beam", "swirl"]],
		"phases": ["Кладка", "Стражи улья", "Матка Цитадели гневается"]},
	{"id": "b29", "name": "Королева Врат", "base": "queen", "body": Color(0.3, 0.2, 0.3), "glow": Color(1.0, 0.55, 0.95),
		"feats": ["crown", "halo", "wings"], "abil": [["fan", "teleport", "summon_bat"], ["swirl", "pull", "meteors"], ["eggs", "beam", "homing_burst", "stream"]],
		"phases": ["Трон Врат", "Сквозь миры", "Королева без короны"]},
	{"id": "b30", "name": "Страж Первых Врат", "base": "omega", "body": Color(0.32, 0.32, 0.38), "glow": Color(0.9, 0.95, 1.0),
		"feats": ["halo", "wings", "crown", "orbs"], "abil": [["ring", "fan", "charge", "teleport"], ["beam", "meteors", "summon_guard", "swirl"], ["stream", "shield", "pull", "rockfall", "homing_burst"]],
		"phases": ["Первое испытание", "Свет Врат", "Последние Врата"]},
]


static func for_level(i: int) -> Dictionary:
	if i < 0 or i >= ROSTER.size():
		return {}
	return ROSTER[i]


static func by_id(id: String) -> Dictionary:
	for d in ROSTER:
		if d["id"] == id:
			return d
	return {}
