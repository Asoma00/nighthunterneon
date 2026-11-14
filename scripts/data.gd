extends RefCounted
## Справочник игры: герои, оружие, эволюции, модули, враги, боссы, статусы и реакции.

static var selected_character := "vega"
static var selected_level := 0
static var coop := false                 # локальный кооператив на одном экране
static var selected_character2 := "rin"   # герой второго игрока
static var coop_devices := [-2, -3]       # устройства игроков: -2 клав. WASD, -3 клав. стрелки, 0.. геймпады
static var world_seed := 0                # сид мира (сетевая игра: одинаковый у обоих)
static var menu_page := ""                # с какой страницы открыть меню
static var menu_return := ""              # куда вернуться со страницы (например, профиль из убежища → "hub")
static var music_volume := 0.6
static var sfx_volume := 0.8

const MAX_WEAPON_LEVEL := 10
const ASPECT_EVERY := 6      # аспект — один раз, на 6 уровне оружия
const ASPECT_LEVEL := 6
const MAX_ASPECTS := 1
const MAX_FUSIONS := 2       # слияний оружия за бой
const MAX_PASSIVE_LEVEL := 10
const MAX_WEAPONS := 3        # в бою не больше 3 оружий
const MAX_PASSIVES := 5       # и не больше 5 модулей:
const MAX_WEAPON_MODULES := 3 # 3 модуля оружия
const MAX_HERO_MODULES := 2   # и 2 модуля героя


static func module_cap(kind: String) -> int:
	return MAX_WEAPON_MODULES if kind == "weapon" else MAX_HERO_MODULES
const WIN_TIME := 360.0

# ---------- Герои ----------
const CHARACTERS := {
	"vega": {
		"name": "Вега", "title": "Техномаг", "sprite": "hero", "weapon": "bolt",
		"color": Color(0.3, 0.95, 1.0), "hp": 100.0, "speed": 210.0,
		"trait": "Разгон: перезарядка оружия -10%",
		"active": "Фазовый сдвиг", "active_desc": "Рывок сквозь врагов. Неуязвимость, след бьёт током.",
		"active_cd": 4.0,
	},
	"rin": {
		"name": "Рин", "title": "Кибер-самурай", "sprite": "rin", "weapon": "katana",
		"color": Color(1.0, 0.3, 0.6), "hp": 90.0, "speed": 235.0,
		"trait": "Ловкость: +15% скорости, +10% урона",
		"active": "Танец клинков", "active_desc": "Вихрь из трёх ударов вокруг: урон и кровотечение.",
		"active_cd": 6.0,
	},
	"bram": {
		"name": "Брам", "title": "Рунный кузнец", "sprite": "bram", "weapon": "quake",
		"color": Color(1.0, 0.7, 0.25), "hp": 150.0, "speed": 185.0,
		"trait": "Броня: -2 к любому получаемому урону",
		"active": "Рунный щит", "active_desc": "3 с неуязвимости и ледяной импульс, отбрасывающий врагов.",
		"active_cd": 10.0,
	},
	"kira": {
		"name": "Кира", "title": "Ведьма сети", "sprite": "kira", "weapon": "drones",
		"color": Color(0.4, 1.0, 0.5), "hp": 85.0, "speed": 205.0,
		"trait": "Сборщица: радиус сбора +40%, опыт +15%",
		"active": "Сбой системы", "active_desc": "Взламывает всех врагов на экране: урон и заморозка.",
		"active_cd": 12.0,
	},
	"skyla": {
		"name": "Скайла", "title": "Неоновая лучница", "sprite": "skyla", "weapon": "railbow",
		"color": Color(0.5, 1.0, 0.8), "hp": 90.0, "speed": 220.0,
		"trait": "Меткость: +15% шанс критического удара",
		"active": "Град стрел", "active_desc": "Ливень светящихся стрел вокруг: урон и кровотечение.",
		"active_cd": 7.0,
	},
	"orm": {
		"name": "Орм", "title": "Паровой паладин", "sprite": "orm", "weapon": "sunbeam",
		"color": Color(1.0, 0.85, 0.4), "hp": 160.0, "speed": 175.0,
		"trait": "Латы: -3 к любому урону, +20 здоровья",
		"active": "Святой контур", "active_desc": "2 с неуязвимости и лечение 30 здоровья.",
		"active_cd": 11.0,
	},
	"mora": {
		"name": "Мора", "title": "Некро-хакерша", "sprite": "mora", "weapon": "spirits",
		"color": Color(0.7, 0.5, 1.0), "hp": 95.0, "speed": 205.0,
		"trait": "Жатва: каждое убийство лечит 0.5 здоровья",
		"active": "Восстание данных", "active_desc": "Выпускает 10 духов, которые ищут врагов.",
		"active_cd": 8.0,
	},
	"zephyr": {
		"name": "Зефир", "title": "Шторм-шаман", "sprite": "zephyr", "weapon": "ball",
		"color": Color(0.5, 0.8, 1.0), "hp": 100.0, "speed": 210.0,
		"trait": "Буревестник: статусы держатся на 30% дольше",
		"active": "Смерч", "active_desc": "Вихрь идёт вперёд, затягивает и бьёт током.",
		"active_cd": 9.0,
	},
	"iris": {
		"name": "Ирис", "title": "Алхимик-биотех", "sprite": "iris", "weapon": "flask",
		"color": Color(0.6, 1.0, 0.3), "hp": 110.0, "speed": 200.0,
		"trait": "Зелья: +1 здоровья в секунду, лечение +25%",
		"active": "Целебный туман", "active_desc": "Лечит 40 здоровья и замораживает врагов вокруг.",
		"active_cd": 12.0,
	},
	"lyra": {
		"name": "Лира", "title": "Танцовщица клинков", "sprite": "lyra", "weapon": "blades",
		"color": Color(0.35, 1.0, 0.95), "hp": 95.0, "speed": 230.0,
		"trait": "Вихрь: +10% урона и +10% области атак",
		"active": "Буря лезвий", "active_desc": "Три волны вращающихся лезвий вокруг: урон и кровотечение.",
		"active_cd": 7.0,
	},
	"sol": {
		"name": "Сол", "title": "Жрец солнечной ауры", "sprite": "sol", "weapon": "aura",
		"color": Color(1.0, 0.75, 0.3), "hp": 140.0, "speed": 190.0,
		"trait": "Свет: +30 здоровья и +0.5 здоровья в секунду",
		"active": "Солнечная вспышка", "active_desc": "Лечит 20 здоровья, обжигает и отбрасывает врагов вокруг.",
		"active_cd": 9.0,
	},
	"volt": {
		"name": "Вольт", "title": "Громовой механик", "sprite": "volt", "weapon": "lightning",
		"color": Color(0.55, 0.75, 1.0), "hp": 105.0, "speed": 205.0,
		"trait": "Статика: перезарядка -8%, статусы держатся на 15% дольше",
		"active": "Грозовой разряд", "active_desc": "Восемь молний бьют по ближайшим врагам и оглушают их током.",
		"active_cd": 8.0,
	},
	"kai": {
		"name": "Кай", "title": "Кибер-ниндзя", "sprite": "kai", "weapon": "shuriken",
		"color": Color(1.0, 0.35, 0.35), "hp": 80.0, "speed": 245.0,
		"trait": "Тень: 12% шанс уклониться от удара",
		"active": "Теневой веер", "active_desc": "Короткая неуязвимость и веер из 12 сюрикенов.",
		"active_cd": 6.0,
	},
}

## История героев (библиотека, зал героев, личные задания).
const HERO_LORE := {
	"vega": "Выпускница Академии техномагии — последней школы, где заклинания учили писать кодом. В Ночь Врат её наставник Омега исчез, а Академия сгорела. Вега пришла в Неоновое убежище с обломком посоха и одним вопросом: почему учитель предал мир. Она верит, что техномагия Сплава может не только жечь тварей, но и зашить разорванное небо.",
	"rin": "Наследница клана Тэцу — самураев, которые после Слияния первыми научились вплетать неон в сталь. Когда открылись Врата, боевые големы клана сошли с ума от чужого кода и вырезали её семью. Рин поклялась не вложить катану в ножны, пока последние Врата не закроются.",
	"bram": "Рунный кузнец из подгорного народа, что веками ковал клинки драконам, а после Слияния — двигатели корпорациям. Ночь Врат застала его у горна: в кузню ворвались железные колоссы, выкованные из его же чертежей. С тех пор Брам ищет, кто перепрошил его творения, и держит молот холодным — руной льда.",
	"kira": "Ведьма сети, выросшая в серверных катакомбах павшего мегаполиса. Для неё дроны — фамильяры, а чары — пароли. С детства Кира слышит сигнал, идущий из-под земли; в Ночь Врат он стал хором. Кира уверена: кто-то управляет ордами через сеть, и только ведьма может перехватить этот голос.",
	"skyla": "Лучница ордена Серебряных Сов — ночных дозорных, что охраняли дороги между лагерями. Её лук-рельса стреляет сгущённым светом, а глаза видят тварей Врат сквозь туман. Орден пал, защищая последний караван. Скайла выжила одна — и теперь охотится на тех, кто идёт по следу беглецов.",
	"orm": "Паровой паладин ордена Медного Солнца. Под бронёй — сердце-котёл, которое поддерживает его жизнь уже сорок лет. Орден строил первые островки безопасности; Орм своими руками поднимал стены из рунного бетона. Он верит: пока горит хоть один костёр в лагере, Врата не победили.",
	"mora": "Некро-хакерша, которая умерла в Ночь Врат — и отказалась это признавать. Она загрузила свою душу в кибер-тело и теперь собирает из обрывков кода души павших, чтобы вернуть их родным. Твари Врат для неё — это мёртвые, которых кто-то заставляет ходить. Мора хочет найти этого «кого-то».",
	"zephyr": "Шаман степных племён, где после Слияния молнии ловили медными тотемами. Зефир слышит бури раньше грома — и в Ночь Врат услышал бурю, которой не было на небе. Он ищет Око бури, место, где сталкиваются все стихии: по легенде, там открылись первые Врата.",
	"iris": "Алхимик-биотех, бывшая сотрудница корпорации «Сплав-Индастриз». Она одной из первых поняла, что твари Врат — это болезнь мира, а не просто враги. Ирис сбежала из лаборатории с журналом формул и уверена: лекарство от Врат существует, и его можно сварить.",
	"lyra": "Танцовщица из бродячего цирка «Сплав», где акробаты жонглировали зачарованными клинками под неоном. В Ночь Врат цирк стал первой линией обороны: клинки Лиры, послушные её танцу, кружили вокруг шатра, пока дети убегали к стенам. Теперь она танцует за стеной — и каждое движение в её танце кому-то спасает жизнь.",
	"sol": "Жрец храма Полуденного Солнца — последнего святилища, где свет молитв усиливали линзами и реакторами. Его аура — сплав веры и плазмы: она лечит союзников и сжигает тварей Врат. Сол уверен, что Врата боятся рассвета, и носит рассвет с собой.",
	"volt": "Механик подстанции «Гроза», которая питала целый квартал. Когда открылись Врата, Вольт перенастроил трансформаторы так, что молнии били по тварям вместо проводов. Подстанция пала, но Вольт унёс с собой её сердце — разрядник, который теперь носит на спине. Шутит, что стал единственным громоотводом, который бьёт в ответ.",
	"kai": "Последний из клана Безлунных — ниндзя, хранивших свитки о Слиянии. В Ночь Врат свитки украли, а клан вырезали тени в масках Хора. Кай не оставляет следов и, говорят, отражений. Он ищет свитки — потому что в них написано, как Врата открыть… и как закрыть.",
}

# ---------- Оружие ----------
const WEAPONS := {
	"bolt": {"name": "Плазменная искра", "desc": "Плазменные сферы летят в ближайших врагов.",
		"status": "shock", "evo_with": "cooldown"},
	"blades": {"name": "Голо-клинки", "desc": "Неоновые клинки кружат вокруг героя.",
		"status": "bleed", "evo_with": "area"},
	"aura": {"name": "Рунный круг", "desc": "Пылающий круг рун обжигает всех рядом.",
		"status": "burn", "evo_with": "hp"},
	"lightning": {"name": "Шторм-протокол", "desc": "Молнии с небес бьют по врагам.",
		"status": "shock", "evo_with": "damage"},
	"katana": {"name": "Моно-катана", "desc": "Широкий удар клинком перед героем.",
		"status": "bleed", "evo_with": "speed"},
	"quake": {"name": "Крио-молот", "desc": "Удар о землю: волна холода. Двойной урон по замороженным.",
		"status": "chill", "evo_with": "regen"},
	"drones": {"name": "Дроны-фамильяры", "desc": "Дроны кружат рядом и жгут врагов лазером.",
		"status": "burn", "evo_with": "magnet"},
	"railbow": {"name": "Лук-рельса", "desc": "Магнитные стрелы пробивают врагов насквозь.",
		"status": "bleed", "evo_with": "crit"},
	"sunbeam": {"name": "Солнечный луч", "desc": "Луч света выжигает линию врагов перед героем.",
		"status": "burn", "evo_with": "armor"},
	"spirits": {"name": "Цифровые духи", "desc": "Призрачные духи сами находят врагов и леденят их.",
		"status": "chill", "evo_with": "vamp"},
	"ball": {"name": "Шаровая молния", "desc": "Медленный шар бьёт током всех рядом с собой.",
		"status": "shock", "evo_with": "duration"},
	"flask": {"name": "Колбы-нейротоксин", "desc": "Брошенные колбы оставляют ядовитые лужи.",
		"status": "poison", "evo_with": "luck"},
	"shuriken": {"name": "Сюрикены-бумеранги", "desc": "Сюрикены летят вперёд и возвращаются.",
		"status": "bleed", "evo_with": "multi"},
}

## Катализаторы: каждое оружие усиливается от статуса, который кладут ДРУГИЕ оружия.
## [статус-катализатор, название связки, описание]
const CATALYSTS := {
	"bolt": ["burn", "ДЕТОНАЦИЯ", "сфера взрывается в горящем враге"],
	"blades": ["shock", "ЗАРЯД", "удар по врагу под током заряжает клинки"],
	"aura": ["bleed", "КРОВАВЫЙ КРУГ", "кровоточащие враги в круге лечат героя"],
	"lightning": ["chill", "ПРОВОДНИК", "по замороженному молния бьёт дважды и прыгает дальше"],
	"katana": ["bleed", "КАЗНЬ", "добивает кровоточащих врагов ниже 20% здоровья"],
	"quake": ["chill", "РАСКОЛ", "двойной урон по замороженным"],
	"drones": ["shock", "ПЕРЕГРУЗ КОНТУРА", "луч по врагу под током прыгает ещё на двоих"],
	"railbow": ["chill", "ЛЕДОЛОМ", "стрела раскалывает замороженного на осколки"],
	"sunbeam": ["shock", "ПРИЗМА", "луч преломляется в соседних врагов"],
	"spirits": ["burn", "ПОЖИРАТЕЛЬ", "дух съедает огонь и раздваивается"],
	"ball": ["burn", "РАСКАЛЕНИЕ", "шар растёт и живёт дольше, жаля горящих"],
	"flask": ["shock", "ЭЛЕКТРОЛИТ", "лужа рядом с врагом под током бьёт и током"],
	"shuriken": ["chill", "РИКОШЕТ", "от замороженного врага отскакивает новый сюрикен"],
}

## Физические связки: как снаряды и поля разных оружий влияют друг на друга.
const FIELD_LINKS := [
	"Любой снаряд, пролетевший сквозь круг, лужу, туман, смерч или шаровую молнию, перенимает её стихию",
	"Солнечный луч и молния перезаряжают шаровую молнию",
	"Катана и сюрикены разрубают шаровую молнию надвое",
	"Крио-молот расплёскивает лужи и туман шире",
	"Способность героя: импульс — перезаряжает оружие, подпитывает поля и даёт стихию героя всем ударам на 4 с",
]

## Стихия способности каждого героя (её получают все удары во время импульса).
const ABILITY_ELEMENT := {
	"vega": "shock", "rin": "bleed", "bram": "chill", "kira": "chill", "skyla": "bleed",
	"orm": "burn", "mora": "chill", "zephyr": "shock", "iris": "chill", "kai": "bleed",
	"lyra": "bleed", "sol": "burn", "volt": "shock",
}

## Аспект модуля. Каждый модуль даёт ВСЕМ оружиям слабую версию своего аспекта
## (сила растёт с уровнем модуля), а эволюция оружия с этим модулем — полную.
## adj: прилагательное для названия эволюции [м, ж, ср].
const ASPECTS := {
	"hp": {"name": "Живучесть", "adj": ["Живой", "Живая", "Живое"], "color": Color(0.4, 1.0, 0.5),
		"desc": "попадания лечат героя"},
	"speed": {"name": "Стремительность", "adj": ["Стремительный", "Стремительная", "Стремительное"], "color": Color(0.5, 0.9, 1.0),
		"desc": "быстрее перезарядка и полёт снарядов"},
	"magnet": {"name": "Притяжение", "adj": ["Гравитонный", "Гравитонная", "Гравитонное"], "color": Color(0.7, 0.5, 1.0),
		"desc": "попадания стягивают врагов к цели"},
	"damage": {"name": "Ярость", "adj": ["Яростный", "Яростная", "Яростное"], "color": Color(1.0, 0.35, 0.25),
		"desc": "+45% к урону этого оружия"},
	"cooldown": {"name": "Эхо", "adj": ["Эхо-", "Эхо-", "Эхо-"], "color": Color(0.4, 0.8, 1.0),
		"desc": "залп с шансом 35% повторяется; постоянное оружие бьёт на 30% чаще"},
	"area": {"name": "Ударная волна", "adj": ["Великий", "Великая", "Великое"], "color": Color(1.0, 0.75, 0.3),
		"desc": "+30% к области; попадания с шансом 30% расходятся волной"},
	"regen": {"name": "Цветение", "adj": ["Цветущий", "Цветущая", "Цветущее"], "color": Color(0.5, 1.0, 0.6),
		"desc": "убийства лечат и выпускают споры"},
	"crit": {"name": "Прицел", "adj": ["Снайперский", "Снайперская", "Снайперское"], "color": Color(1.0, 0.3, 0.35),
		"desc": "+25% к шансу крита; криты взрываются"},
	"armor": {"name": "Бастион", "adj": ["Бастионный", "Бастионная", "Бастионное"], "color": Color(0.7, 0.8, 0.9),
		"desc": "попадания дают герою временную броню"},
	"multi": {"name": "Размножение", "adj": ["Роевой", "Роевая", "Роевое"], "color": Color(0.9, 0.5, 1.0),
		"desc": "попадание с шансом 40% перескакивает на соседнего врага"},
	"duration": {"name": "Вечность", "adj": ["Вечный", "Вечная", "Вечное"], "color": Color(0.6, 0.95, 1.0),
		"desc": "статусы на 60% дольше; удар с шансом 25% кладёт вторую стихию"},
	"vamp": {"name": "Жажда", "adj": ["Кровожадный", "Кровожадная", "Кровожадное"], "color": Color(0.9, 0.1, 0.3),
		"desc": "удары пускают кровь, убийства лечат"},
	"luck": {"name": "Фортуна", "adj": ["Счастливый", "Счастливая", "Счастливое"], "color": Color(1.0, 0.9, 0.4),
		"desc": "убийства дают больше кристаллов, иногда сундук"},
}

## Род названия эволюции: 0 — м, 1 — ж, 2 — ср.
const EVO_GENDER := {
	"bolt": 0, "blades": 0, "aura": 0, "lightning": 0, "katana": 1, "quake": 0, "drones": 0,
	"railbow": 1, "sunbeam": 1, "spirits": 0, "ball": 2, "flask": 0, "shuriken": 0,
}


## Имя эволюции двух оружий: «Шторм-протокол + Плазменная искра».
static func fusion_name(a: String, b: String) -> String:
	return fused_name(a, b)


## Части имён для слияний: [приставка, существительное].
const FUSE_PARTS := {
	"bolt": ["Плазмо", "искры"], "blades": ["Голо", "клинки"], "aura": ["Руно", "круг"],
	"lightning": ["Шторм", "протокол"], "katana": ["Моно", "катана"], "quake": ["Крио", "молот"],
	"drones": ["Дроно", "фамильяры"], "railbow": ["Рельсо", "лук"], "sunbeam": ["Солнце", "луч"],
	"spirits": ["Цифро", "духи"], "ball": ["Шаро", "молния"], "flask": ["Токсо", "колбы"],
	"shuriken": ["Сюрико", "бумеранги"],
}


## Имя слитого оружия: основа — существительное, второе оружие — приставка.
## bolt + blades → «Голо-искры», blades + bolt → «Плазмо-клинки».
static func fused_name(base: String, other: String) -> String:
	var pb: Array = FUSE_PARTS.get(base, [WEAPONS[base]["name"], ""])
	var po: Array = FUSE_PARTS.get(other, [WEAPONS[other]["name"], ""])
	if pb[1] == "":
		return "%s + %s" % [WEAPONS[base]["name"], WEAPONS[other]["name"]]
	return "%s-%s" % [po[0], pb[1]]


## Уникальное имя эволюции: «Кровожадный плазменный шторм», «Эхо-гнев Матрицы»...
static func evo_name(weapon: String, module: String) -> String:
	var base: String = EVOLUTIONS[weapon]["name"]
	if module == "" or not ASPECTS.has(module):
		return base
	var adj: String = ASPECTS[module]["adj"][EVO_GENDER.get(weapon, 0)]
	var rest := base.substr(0, 1).to_lower() + base.substr(1)
	if adj.ends_with("-"):
		return adj + rest
	return adj + " " + rest


static func evo_desc(weapon: String, module: String) -> String:
	var d: String = EVOLUTIONS[weapon]["desc"]
	if module == "" or not ASPECTS.has(module):
		return d
	return "%s\n%s в полную силу: %s." % [d, ASPECTS[module]["name"], ASPECTS[module]["desc"]]


static func catalyst_text(weapon_id: String) -> String:
	if not CATALYSTS.has(weapon_id):
		return ""
	var c: Array = CATALYSTS[weapon_id]
	return "%s + %s: %s" % [c[1], STATUSES[c[0]]["name"], c[2]]


const EVOLUTIONS := {
	"bolt": {"name": "Плазменный шторм", "desc": "4 самонаводящиеся сферы взрываются при попадании."},
	"blades": {"name": "Неоновый смерч", "desc": "8 клинков, радиус пульсирует, урон +50%."},
	"aura": {"name": "Пожирающий круг", "desc": "Огромный круг замедляет врагов и лечит героя."},
	"lightning": {"name": "Гнев Матрицы", "desc": "Шесть молний, каждая перескакивает на соседей."},
	"katana": {"name": "Призрачная катана", "desc": "Удары во все стороны и летящие волны клинка."},
	"quake": {"name": "Абсолютный ноль", "desc": "Двойная волна огромного радиуса."},
	"drones": {"name": "Рой ИИ", "desc": "6 дронов, лучи перескакивают на соседних врагов."},
	"railbow": {"name": "Звёздная баллиста", "desc": "Веер из трёх стрел, бесконечное пробитие."},
	"sunbeam": {"name": "Корона рассвета", "desc": "Три луча разом и двойной урон."},
	"spirits": {"name": "Легион призраков", "desc": "Вдвое больше духов, взрываются при попадании."},
	"ball": {"name": "Грозовое ядро", "desc": "Три шара, разряды цепляют соседей."},
	"flask": {"name": "Великий котёл", "desc": "Три колбы и огромные лужи."},
	"shuriken": {"name": "Вихрь клинков", "desc": "Шесть сюрикенов летят по спирали."},
}

## Модули: "hero" — только для героя, "weapon" — только для оружия. Без побочных эффектов.
const PASSIVES := {
	# ---- Модули героя ----
	"hp": {"name": "Кибер-сердце", "kind": "hero", "desc": "+20 к максимальному здоровью"},
	"speed": {"name": "Неоновые сапоги", "kind": "hero", "desc": "+10% к скорости движения"},
	"magnet": {"name": "Гравимагнит", "kind": "hero", "desc": "+35% к радиусу сбора кристаллов"},
	"regen": {"name": "Нано-лечение", "kind": "hero", "desc": "+0.5 здоровья в секунду"},
	"armor": {"name": "Рунная броня", "kind": "hero", "desc": "-1 к любому получаемому урону"},
	"vamp": {"name": "Вампирский чип", "kind": "hero", "desc": "+0.4 здоровья за каждое убийство"},
	"luck": {"name": "Квантовая удача", "kind": "hero", "desc": "+8% опыта и +8% шанс сундука"},
	"shield": {"name": "Энергощит", "kind": "hero", "desc": "Щит поглощает удар; перезарядка 14 с, −2 с за уровень"},
	"dodge": {"name": "Фазовый сдвиг", "kind": "hero", "desc": "+6% шанс уклониться от удара"},
	"dash": {"name": "Импульсный привод", "kind": "hero", "desc": "−12% к перезарядке способности героя"},
	# ---- Модули оружия ----
	"damage": {"name": "Руна ярости", "kind": "weapon", "desc": "+12% к урону оружия"},
	"cooldown": {"name": "Разгон ядра", "kind": "weapon", "desc": "-8% к перезарядке оружия"},
	"area": {"name": "Усилитель поля", "kind": "weapon", "desc": "+12% к области и дальности оружия"},
	"crit": {"name": "Прицел-имплант", "kind": "weapon", "desc": "+8% шанс крита оружия (двойной урон)"},
	"multi": {"name": "Мультиядро", "kind": "weapon", "desc": "+1 к количеству у любого оружия: снаряды, клинки, дроны, молнии, лучи, волны"},
	"duration": {"name": "Катализатор", "kind": "weapon", "desc": "+20% к длительности статусов и луж от оружия"},
	"pierce": {"name": "Бронебойный сердечник", "kind": "weapon", "desc": "+1 к пробиванию снарядов и +6% урона оружия"},
	"execute": {"name": "Добивающий чип", "kind": "weapon", "desc": "+25% урона по врагам, у которых меньше 30% здоровья"},
	"giant": {"name": "Гроза титанов", "kind": "weapon", "desc": "+15% урона по элите и боссам"},
	"toxin": {"name": "Стихийный реактор", "kind": "weapon", "desc": "+25% к урону горения, кровотечения и яда"},
}

# ---------- Усиления врагов (появляются со временем) ----------
const AFFIXES := {
	"armored": {"name": "Бронированный", "color": Color(0.7, 0.8, 1.0)},
	"swift": {"name": "Стремительный", "color": Color(0.4, 1.0, 0.9)},
	"regen": {"name": "Регенерирующий", "color": Color(0.4, 1.0, 0.4)},
	"berserk": {"name": "Берсерк", "color": Color(1.0, 0.25, 0.2)},
	"shielded": {"name": "Щитоносец", "color": Color(0.5, 0.7, 1.0)},
	"explosive": {"name": "Взрывной", "color": Color(1.0, 0.6, 0.1)},
	"giant": {"name": "Гигант", "color": Color(0.9, 0.5, 1.0)},
}

# ---------- Статусы и реакции ----------
const STATUSES := {
	"burn": {"name": "Горение", "color": Color(1.0, 0.5, 0.1), "time": 3.0},
	"shock": {"name": "Электризация", "color": Color(0.4, 0.7, 1.0), "time": 2.5},
	"chill": {"name": "Заморозка", "color": Color(0.55, 0.95, 1.0), "time": 2.5},
	"bleed": {"name": "Кровотечение", "color": Color(1.0, 0.15, 0.3), "time": 3.0},
	"poison": {"name": "Отравление", "color": Color(0.5, 1.0, 0.2), "time": 5.0},
	# Производный статус — появляется только из реакции
	"wet": {"name": "Мокрый", "color": Color(0.3, 0.55, 1.0), "time": 5.0, "derived": true},
}

## Реакции: когда на враге встречаются два статуса.
const REACTIONS := {
	"burn+chill": {"name": "МОКРЫЙ", "desc": "лёд тает — враг становится мокрым и замедляется", "color": Color(0.35, 0.6, 1.0)},
	"shock+wet": {"name": "ЭЛЕКТРОШОК", "desc": "сильный удар током, оглушение и разряд по мокрым соседям", "color": Color(0.6, 0.85, 1.0)},
	"chill+wet": {"name": "ЛЕДЯНАЯ ГЛЫБА", "desc": "враг вмерзает в лёд и оглушён", "color": Color(0.7, 0.95, 1.0)},
	"burn+wet": {"name": "ПАР", "desc": "облако обжигающего пара вокруг", "color": Color(0.85, 0.85, 0.95)},
	"burn+shock": {"name": "ПЕРЕГРУЗКА", "desc": "взрыв по области", "color": Color(1.0, 0.45, 0.9)},
	"chill+shock": {"name": "СВЕРХПРОВОДНИК", "desc": "ток перескакивает на соседей", "color": Color(0.5, 0.9, 1.0)},
	"bleed+burn": {"name": "ПРИЖИГАНИЕ", "desc": "урон и лечение героя", "color": Color(1.0, 0.35, 0.2)},
	"bleed+chill": {"name": "ЛЕДЯНЫЕ ОСКОЛКИ", "desc": "разлёт ледяных осколков", "color": Color(0.6, 0.9, 1.0)},
	"bleed+shock": {"name": "РАЗРЯД КРОВИ", "desc": "урон цели и всем рядом", "color": Color(1.0, 0.3, 0.7)},
	"burn+poison": {"name": "ТОКСИЧНЫЙ ВЗРЫВ", "desc": "взрыв и ядовитое облако", "color": Color(0.7, 1.0, 0.2)},
	"chill+poison": {"name": "ОЦЕПЕНЕНИЕ", "desc": "яд и холод — враг оглушён", "color": Color(0.6, 1.0, 0.7)},
	"poison+shock": {"name": "НЕЙРОТОКСИН", "desc": "ток разносит яд по соседям", "color": Color(0.6, 1.0, 0.5)},
	"bleed+poison": {"name": "ЗАРАЖЕНИЕ", "desc": "яд в крови — тройной урон отравления", "color": Color(0.8, 1.0, 0.3)},
}


static func reaction_key(a: String, b: String) -> String:
	var arr := [a, b]
	arr.sort()
	return "%s+%s" % arr


## Подсказка о сочетаниях для статуса: «Огонь: +Ток → ПЕРЕГРУЗКА, ...»
static func synergy_text(status: String) -> String:
	var parts: Array[String] = []
	for key in REACTIONS:
		var pair: PackedStringArray = (key as String).split("+")
		if status in pair:
			var other: String = pair[0] if pair[1] == status else pair[1]
			parts.append("+%s → %s" % [STATUSES[other]["name"], REACTIONS[key]["name"]])
	return "%s:  %s" % [STATUSES[status]["name"], ",  ".join(parts)]


# ---------- Враги ----------
const ENEMIES := {
	"imp": {"hp": 9.0, "speed": 72.0, "damage": 8.0, "radius": 12.0,
		"color": Color(1.0, 0.3, 0.2), "xp": 1, "from": 0.0},
	"bat": {"hp": 5.0, "speed": 125.0, "damage": 5.0, "radius": 9.0,
		"color": Color(0.9, 0.3, 1.0), "xp": 1, "from": 25.0},
	"ghoul": {"hp": 32.0, "speed": 55.0, "damage": 13.0, "radius": 18.0,
		"color": Color(0.4, 1.0, 0.45), "xp": 3, "from": 80.0},
	"wraith": {"hp": 60.0, "speed": 95.0, "damage": 16.0, "radius": 15.0,
		"color": Color(0.3, 0.9, 1.0), "xp": 5, "from": 200.0},
	"brute": {"hp": 420.0, "speed": 48.0, "damage": 28.0, "radius": 34.0,
		"color": Color(1.0, 0.55, 0.1), "xp": 25, "from": 99999.0},
	"goblin": {"hp": 14.0, "speed": 105.0, "damage": 9.0, "radius": 11.0,
		"color": Color(0.5, 1.0, 0.3), "xp": 1, "from": 0.0, "ai": "dash"},
	"slime": {"hp": 26.0, "speed": 50.0, "damage": 10.0, "radius": 16.0,
		"color": Color(0.3, 1.0, 0.8), "xp": 2, "from": 0.0, "split": "slimelet"},
	"slimelet": {"hp": 8.0, "speed": 80.0, "damage": 5.0, "radius": 9.0,
		"color": Color(0.3, 1.0, 0.8), "xp": 1, "from": 99999.0},
	"spider": {"hp": 40.0, "speed": 70.0, "damage": 12.0, "radius": 17.0,
		"color": Color(1.0, 0.4, 0.3), "xp": 3, "from": 0.0, "split": "spiderling"},
	"spiderling": {"hp": 6.0, "speed": 130.0, "damage": 4.0, "radius": 8.0,
		"color": Color(1.0, 0.4, 0.3), "xp": 0, "from": 99999.0},
	"caster": {"hp": 30.0, "speed": 60.0, "damage": 10.0, "radius": 13.0,
		"color": Color(0.8, 0.4, 1.0), "xp": 3, "from": 0.0, "ai": "ranged"},
	"bomber": {"hp": 12.0, "speed": 115.0, "damage": 30.0, "radius": 12.0,
		"color": Color(1.0, 0.6, 0.1), "xp": 2, "from": 0.0, "ai": "bomber"},
	"knight": {"hp": 120.0, "speed": 52.0, "damage": 20.0, "radius": 18.0,
		"color": Color(0.6, 0.8, 1.0), "xp": 6, "from": 0.0, "armor": 0.45},
	# ---- Алтарь мобов (точка интереса): стоит на месте и призывает врагов ----
	"mob_altar": {"hp": 260.0, "speed": 0.0, "damage": 0.0, "radius": 26.0, "sprite": "statue0",
		"color": Color(1.0, 0.25, 0.3), "xp": 20, "from": 99999.0, "ai": "altar"},
	# ---- Адские мобы бесконечного режима: быстрые, живучие, больно бьют ----
	"hell_imp": {"hp": 140.0, "speed": 165.0, "damage": 22.0, "radius": 13.0, "sprite": "imp", "hell": true,
		"color": Color(1.0, 0.35, 0.1), "xp": 4, "from": 99999.0},
	"hell_hound": {"hp": 180.0, "speed": 195.0, "damage": 26.0, "radius": 12.0, "sprite": "goblin", "hell": true,
		"color": Color(1.0, 0.3, 0.1), "xp": 5, "from": 99999.0, "ai": "dash"},
	"hell_bat": {"hp": 90.0, "speed": 220.0, "damage": 18.0, "radius": 10.0, "sprite": "bat", "hell": true,
		"color": Color(1.0, 0.4, 0.2), "xp": 3, "from": 99999.0},
	"hell_wraith": {"hp": 320.0, "speed": 175.0, "damage": 34.0, "radius": 15.0, "sprite": "wraith", "hell": true,
		"color": Color(1.0, 0.5, 0.2), "xp": 7, "from": 99999.0},
	"hell_knight": {"hp": 650.0, "speed": 125.0, "damage": 42.0, "radius": 18.0, "sprite": "knight", "hell": true,
		"color": Color(1.0, 0.3, 0.15), "xp": 10, "from": 99999.0, "armor": 0.3},
	"hell_brute": {"hp": 2400.0, "speed": 105.0, "damage": 60.0, "radius": 34.0, "sprite": "brute", "hell": true,
		"color": Color(1.0, 0.25, 0.1), "xp": 60, "from": 99999.0},
}

const BOSS_TYPES := {
	"lich": {"name": "НЕЙРО-ЛИЧ", "hp": 4420.0, "speed": 69.0, "radius": 30.0, "damage": 27.0, "color": Color(0.65, 0.4, 1.0)},
	"colossus": {"name": "ЖЕЛЕЗНЫЙ КОЛОСС", "hp": 11050.0, "speed": 55.2, "radius": 42.0, "damage": 40.5, "color": Color(1.0, 0.5, 0.15)},
	"queen": {"name": "КОРОЛЕВА РОЯ", "hp": 18700.0, "speed": 86.2, "radius": 34.0, "damage": 37.8, "color": Color(1.0, 0.3, 0.7)},
	"omega": {"name": "АРХИМАГ ОМЕГА", "hp": 40800.0, "speed": 66.7, "radius": 40.0, "damage": 43.2, "color": Color(0.3, 1.0, 0.9)},
}

# ---------- Глава I: Неоновые пустоши ----------
const CHAPTER_NAME := "Глава I. Неоновые пустоши"
const LEVELS_PER_CHAPTER := 10


static func chapter_of(i: int) -> int:
	return clampi(i / LEVELS_PER_CHAPTER, 0, 2)
const LEVELS := [
	{"name": "Окраины неона", "desc": "Бесы и кибер-гоблины лезут из подворотен.",
		"time": 360.0, "districts": ["street", "street", "market", "park"], "biomes": [0], "enemies": ["imp", "goblin", "bat"], "hp": 0.8, "rate": 0.8,
		"elites": [120.0], "bosses": [], "reward": 60, "final": "lich"},
	{"name": "Кристальный разлом", "desc": "Нано-слизь делится, кристаллы режут свет.",
		"time": 360.0, "districts": ["crystal", "crystal", "ruins", "field"], "biomes": [1], "enemies": ["imp", "slime", "bat", "goblin"], "hp": 0.9, "rate": 0.9,
		"elites": [100.0, 200.0], "bosses": [], "reward": 80, "final": "queen"},
	{"name": "Склеп кода", "desc": "В руинах проснулся Нейро-Лич.",
		"time": 360.0, "districts": ["ruins", "castle", "field", "ruins"], "biomes": [2], "enemies": ["imp", "wraith", "spider", "ghoul"], "hp": 1.0, "rate": 1.0,
		"elites": [90.0], "bosses": [[240.0, "lich"]], "reward": 120, "final": "lich"},
	{"name": "Техно-чаща", "desc": "Техноманты стреляют из-за деревьев.",
		"time": 360.0, "districts": ["forest", "forest", "park", "field"], "biomes": [3], "enemies": ["goblin", "caster", "ghoul", "spider"], "hp": 1.1, "rate": 1.0,
		"elites": [120.0, 240.0], "bosses": [], "reward": 120, "final": "colossus"},
	{"name": "Свалка павших дронов", "desc": "Дроны-камикадзе взрываются рядом с вами.",
		"time": 360.0, "districts": ["junk", "junk", "field", "street"], "biomes": [4], "enemies": ["bomber", "imp", "slime", "goblin"], "hp": 1.2, "rate": 1.1,
		"elites": [110.0, 220.0, 300.0], "bosses": [], "reward": 150, "final": "queen"},
	{"name": "Врата колосса", "desc": "Железный Колосс охраняет путь вглубь.",
		"time": 360.0, "districts": ["castle", "street", "junk", "market"], "biomes": [0, 4], "enemies": ["knight", "goblin", "bomber", "ghoul"], "hp": 1.3, "rate": 1.1,
		"elites": [120.0], "bosses": [[300.0, "colossus"]], "reward": 200, "final": "colossus"},
	{"name": "Рунный некрополь", "desc": "Рыцари-призраки в рунной броне.",
		"time": 360.0, "districts": ["ruins", "crystal", "castle", "park"], "biomes": [2, 1], "enemies": ["knight", "wraith", "caster", "spider"], "hp": 1.45, "rate": 1.2,
		"elites": [100.0, 200.0, 300.0], "bosses": [], "reward": 220, "final": "lich"},
	{"name": "Гнездо роя", "desc": "Пауки и нетопыри затапливают лес.",
		"time": 360.0, "districts": ["forest", "forest", "crystal", "field"], "biomes": [3, 1], "enemies": ["spider", "bat", "bomber", "slime"], "hp": 1.6, "rate": 1.3,
		"elites": [130.0, 260.0], "bosses": [], "reward": 250, "final": "queen"},
	{"name": "Трон Королевы", "desc": "Королева роя ждёт в сердце гнезда.",
		"time": 360.0, "districts": ["forest", "ruins", "castle", "junk"], "biomes": [3, 4, 2], "enemies": ["spider", "caster", "knight", "bat", "goblin"], "hp": 1.75, "rate": 1.35,
		"elites": [120.0, 240.0], "bosses": [[300.0, "queen"]], "reward": 320, "final": "queen"},
	{"name": "Сердце Омеги", "desc": "Финал главы: Архимаг Омега и его стражи.",
		"time": 360.0, "districts": ["street", "market", "park", "field", "forest", "crystal", "ruins", "castle", "junk"], "biomes": [0, 1, 2, 3, 4], "enemies": ["knight", "caster", "bomber", "spider", "wraith", "slime"], "hp": 2.0, "rate": 1.45,
		"elites": [90.0, 270.0], "bosses": [[150.0, "lich"], [250.0, "colossus"], [320.0, "omega"]], "reward": 500, "final": "omega"},
	# ---------- Глава II ----------
	{"name": "Пепельные окраины", "desc": "Пыль, жар и первые твари Предела.",
		"time": 360.0, "districts": ["junk", "street", "field", "junk"], "biomes": [4], "enemies": ["imp", "goblin", "bomber", "bat"], "hp": 2.2, "rate": 1.45,
		"elites": [100.0, 220.0], "bosses": [], "reward": 820, "final": "colossus"},
	{"name": "Огненные копи", "desc": "Шахтёры-автоматоны копают к Вратам.",
		"time": 360.0, "districts": ["ruins", "junk", "crystal", "ruins"], "biomes": [4, 1], "enemies": ["knight", "bomber", "slime", "imp"], "hp": 2.35, "rate": 1.5,
		"elites": [90.0, 200.0, 300.0], "bosses": [], "reward": 880, "final": "colossus"},
	{"name": "Плавильня «Сплав»", "desc": "Здесь куют тела для орды.",
		"time": 360.0, "districts": ["junk", "castle", "street", "junk"], "biomes": [4, 0], "enemies": ["knight", "caster", "bomber", "ghoul"], "hp": 2.5, "rate": 1.5,
		"elites": [120.0], "bosses": [[240.0, "lich"]], "reward": 940, "final": "lich"},
	{"name": "Лес обугленных мачт", "desc": "Антенны ловят сигнал Врат.",
		"time": 360.0, "districts": ["forest", "junk", "forest", "field"], "biomes": [3, 4], "enemies": ["caster", "spider", "bat", "goblin"], "hp": 2.65, "rate": 1.55,
		"elites": [100.0, 220.0], "bosses": [], "reward": 1000, "final": "queen"},
	{"name": "Драконья свалка", "desc": "Кости драконов, обвитые кабелями.",
		"time": 360.0, "districts": ["junk", "ruins", "field", "junk"], "biomes": [4, 2], "enemies": ["ghoul", "wraith", "bomber", "knight"], "hp": 2.8, "rate": 1.6,
		"elites": [90.0, 200.0, 300.0], "bosses": [], "reward": 1060, "final": "lich"},
	{"name": "Ворота Пепельного Колосса", "desc": "Брат Железного Колосса стережёт Предел.",
		"time": 360.0, "districts": ["castle", "junk", "street", "castle"], "biomes": [0, 4], "enemies": ["knight", "bomber", "caster", "goblin"], "hp": 3.0, "rate": 1.6,
		"elites": [120.0], "bosses": [[300.0, "colossus"]], "reward": 1120, "final": "colossus"},
	{"name": "Некрополь литейщиков", "desc": "Призраки рабочих, сгоревших в ночь Врат.",
		"time": 360.0, "districts": ["ruins", "castle", "ruins", "junk"], "biomes": [2, 4], "enemies": ["wraith", "knight", "ghoul", "caster"], "hp": 3.2, "rate": 1.65,
		"elites": [100.0, 200.0, 300.0], "bosses": [], "reward": 1180, "final": "lich"},
	{"name": "Улей пепельниц", "desc": "Огненный рой дронов-насекомых.",
		"time": 360.0, "districts": ["forest", "junk", "crystal", "field"], "biomes": [3, 4], "enemies": ["spider", "bat", "bomber", "slime"], "hp": 3.4, "rate": 1.7,
		"elites": [130.0, 260.0], "bosses": [], "reward": 1240, "final": "queen"},
	{"name": "Тронный зал пепла", "desc": "Королева Пепла ждёт на троне.",
		"time": 360.0, "districts": ["castle", "ruins", "junk", "forest"], "biomes": [2, 4, 3], "enemies": ["spider", "caster", "knight", "bat", "bomber"], "hp": 3.6, "rate": 1.75,
		"elites": [120.0, 240.0], "bosses": [[300.0, "queen"]], "reward": 1300, "final": "queen"},
	{"name": "Цех номер ноль", "desc": "Финал главы: Пепельный Архимаг держит Врата Предела.",
		"time": 360.0, "districts": ["junk", "street", "castle", "ruins", "crystal", "forest"], "biomes": [0, 1, 2, 3, 4], "enemies": ["knight", "caster", "bomber", "spider", "wraith", "slime"], "hp": 3.9, "rate": 1.8,
		"elites": [90.0, 270.0], "bosses": [[150.0, "lich"], [250.0, "colossus"], [320.0, "omega"]], "reward": 1760, "final": "omega"},
	# ---------- Глава III ----------
	{"name": "Подступы к Цитадели", "desc": "Улицы, висящие в небе.",
		"time": 360.0, "districts": ["street", "castle", "market", "street"], "biomes": [0, 2], "enemies": ["knight", "caster", "imp", "bat", "goblin"], "hp": 4.1, "rate": 1.8,
		"elites": [100.0, 220.0], "bosses": [], "reward": 1120, "final": "colossus"},
	{"name": "Сад искажений", "desc": "Деревья из кристалла и кода.",
		"time": 360.0, "districts": ["park", "crystal", "forest", "crystal"], "biomes": [1, 3], "enemies": ["slime", "spider", "caster", "wraith"], "hp": 4.3, "rate": 1.85,
		"elites": [90.0, 200.0, 300.0], "bosses": [], "reward": 1180, "final": "queen"},
	{"name": "Архив Слияния", "desc": "Библиотека, где книги — сервера.",
		"time": 360.0, "districts": ["ruins", "castle", "ruins", "street"], "biomes": [2, 0], "enemies": ["wraith", "caster", "knight", "ghoul"], "hp": 4.5, "rate": 1.85,
		"elites": [120.0], "bosses": [[240.0, "lich"]], "reward": 1240, "final": "lich"},
	{"name": "Мост двух миров", "desc": "Замки по одну сторону, небоскрёбы — по другую.",
		"time": 360.0, "districts": ["castle", "street", "castle", "market"], "biomes": [0, 2], "enemies": ["knight", "goblin", "bomber", "caster"], "hp": 4.7, "rate": 1.9,
		"elites": [100.0, 220.0], "bosses": [], "reward": 1300, "final": "colossus"},
	{"name": "Кладбище машин-драконов", "desc": "Хор оживил драконов кодом.",
		"time": 360.0, "districts": ["junk", "ruins", "junk", "field"], "biomes": [4, 2], "enemies": ["ghoul", "bomber", "knight", "wraith"], "hp": 4.9, "rate": 1.9,
		"elites": [90.0, 200.0, 300.0], "bosses": [], "reward": 1360, "final": "lich"},
	{"name": "Врата Небесного Колосса", "desc": "Последний страж Цитадели.",
		"time": 360.0, "districts": ["castle", "crystal", "castle", "junk"], "biomes": [1, 4], "enemies": ["knight", "caster", "bomber", "spider"], "hp": 5.1, "rate": 1.95,
		"elites": [120.0], "bosses": [[300.0, "colossus"]], "reward": 1420, "final": "colossus"},
	{"name": "Хоры призраков", "desc": "Голоса павших поют гимн Врат.",
		"time": 360.0, "districts": ["ruins", "castle", "crystal", "ruins"], "biomes": [2, 1], "enemies": ["wraith", "knight", "caster", "bat"], "hp": 5.3, "rate": 2.0,
		"elites": [100.0, 200.0, 300.0], "bosses": [], "reward": 1480, "final": "lich"},
	{"name": "Улей Цитадели", "desc": "Рой — иммунитет Врат.",
		"time": 360.0, "districts": ["forest", "crystal", "forest", "junk"], "biomes": [3, 1], "enemies": ["spider", "bat", "bomber", "slime", "imp"], "hp": 5.5, "rate": 2.05,
		"elites": [130.0, 260.0], "bosses": [], "reward": 1540, "final": "queen"},
	{"name": "Трон Врат", "desc": "Королева Хора ведёт последнюю защиту.",
		"time": 360.0, "districts": ["castle", "forest", "ruins", "crystal"], "biomes": [3, 2, 1], "enemies": ["spider", "caster", "knight", "wraith", "bomber"], "hp": 5.8, "rate": 2.1,
		"elites": [120.0, 240.0], "bosses": [[300.0, "queen"]], "reward": 1600, "final": "queen"},
	{"name": "Первые Врата", "desc": "Финал: Сердце Хора.",
		"time": 360.0, "districts": ["street", "market", "park", "field", "forest", "crystal", "ruins", "castle", "junk"], "biomes": [0, 1, 2, 3, 4], "enemies": ["knight", "caster", "bomber", "spider", "wraith", "slime", "ghoul"], "hp": 6.2, "rate": 2.2,
		"elites": [90.0, 270.0], "bosses": [[120.0, "lich"], [220.0, "colossus"], [290.0, "queen"], [330.0, "omega"]], "reward": 2060, "final": "omega"},
]


## Уровни 6–9: база 5-го уровня, дальше растут урон, скорость, область и количество.
static func weapon_stats(id: String, lvl: int, evo := false) -> Dictionary:
	var s := _weapon_base(id, mini(lvl, 5), evo)
	var over := lvl - 5
	if over > 0:
		s["damage"] = float(s.get("damage", 0.0)) * (1.0 + 0.18 * over)
		for k in ["cooldown", "interval"]:
			if s.has(k):
				s[k] = float(s[k]) * (1.0 - 0.05 * over)
		for k in ["radius", "range", "length"]:
			if s.has(k):
				s[k] = float(s[k]) * (1.0 + 0.04 * over)
		for k in ["count", "strikes", "beams"]:
			if s.has(k):
				s[k] = int(s[k]) + over / 2
	return s


static func _weapon_base(id: String, lvl: int, evo := false) -> Dictionary:
	match id:
		"bolt":
			return {
				"cooldown": (0.8 if evo else 1.05 - 0.1 * (lvl - 1)),
				"count": 4 if evo else 1 + int(lvl >= 2) + int(lvl >= 4),
				"damage": (34.0 if evo else 10.0 + 4.0 * (lvl - 1)),
				"pierce": 3 if evo else 1 + int(lvl >= 3) + int(lvl >= 5),
				"speed": 540.0, "homing": evo, "explode": 60.0 if evo else 0.0,
			}
		"blades":
			return {
				"count": 8 if evo else mini(lvl + 1, 6),
				"damage": (7.0 + 3.0 * lvl) * (1.5 if evo else 1.0),
				"radius": 75.0 + 5.0 * lvl + (25.0 if evo else 0.0),
				"spin": 2.6 + 0.3 * lvl, "hit_cd": 0.4, "pulse": evo,
			}
		"aura":
			return {
				"radius": 150.0 if evo else 60.0 + 12.0 * lvl,
				"damage": (3.0 + 2.0 * lvl) * (1.5 if evo else 1.0),
				"tick": 0.5, "slow": evo, "lifesteal": evo,
			}
		"lightning":
			return {
				"cooldown": 1.2 if evo else 2.4 - 0.25 * (lvl - 1),
				"strikes": 6 if evo else lvl,
				"damage": 20.0 + 10.0 * lvl + (20.0 if evo else 0.0),
				"radius": 45.0 + 5.0 * lvl, "chain": 3 if evo else 0,
			}
		"katana":
			return {
				"cooldown": 0.8 if evo else 1.25 - 0.1 * (lvl - 1),
				"damage": 18.0 + 7.0 * lvl + (20.0 if evo else 0.0),
				"range": 105.0 + 8.0 * lvl + (20.0 if evo else 0.0),
				"arc": TAU if evo else deg_to_rad(110.0 + 8.0 * lvl),
				"waves": evo,
			}
		"quake":
			return {
				"cooldown": 2.4 if evo else 3.2 - 0.3 * (lvl - 1),
				"damage": 14.0 + 7.0 * lvl + (15.0 if evo else 0.0),
				"radius": 120.0 + 16.0 * lvl + (60.0 if evo else 0.0),
				"double": evo,
			}
		"drones":
			return {
				"count": 6 if evo else [1, 2, 2, 3, 3][lvl - 1],
				"interval": 0.7 if evo else 1.0 - 0.06 * lvl,
				"damage": 7.0 + 3.0 * lvl + (8.0 if evo else 0.0),
				"range": 320.0, "chain": 2 if evo else 0,
			}
		"railbow":
			return {
				"cooldown": 0.9 if evo else 1.3 - 0.1 * (lvl - 1),
				"count": 3 if evo else 1 + int(lvl >= 4),
				"damage": 16.0 + 6.0 * lvl + (15.0 if evo else 0.0),
				"pierce": 99 if evo else 3 + lvl, "speed": 900.0,
			}
		"sunbeam":
			return {
				"cooldown": 1.6 if evo else 2.4 - 0.2 * (lvl - 1),
				"damage": (14.0 + 6.0 * lvl) * (2.0 if evo else 1.0),
				"length": 420.0 + 30.0 * lvl, "width": 34.0 + 4.0 * lvl,
				"beams": 3 if evo else 1,
			}
		"spirits":
			return {
				"cooldown": 1.0 if evo else 1.5 - 0.1 * (lvl - 1),
				"count": (2 + lvl) * (2 if evo else 1) / 2 + 1,
				"damage": 9.0 + 4.0 * lvl + (8.0 if evo else 0.0),
				"explode": 55.0 if evo else 0.0,
			}
		"ball":
			return {
				"cooldown": 2.4 if evo else 3.4 - 0.25 * (lvl - 1),
				"count": 3 if evo else 1 + int(lvl >= 4),
				"damage": 5.0 + 2.5 * lvl + (4.0 if evo else 0.0),
				"radius": 70.0 + 8.0 * lvl, "life": 3.0 + 0.3 * lvl, "chain": evo,
			}
		"flask":
			return {
				"cooldown": 1.6 if evo else 2.2 - 0.15 * (lvl - 1),
				"count": 3 if evo else 1 + int(lvl >= 3),
				"damage": 5.0 + 2.5 * lvl + (4.0 if evo else 0.0),
				"radius": (55.0 + 6.0 * lvl) * (1.6 if evo else 1.0), "duration": 3.0,
			}
		"shuriken":
			return {
				"cooldown": 1.0 if evo else 1.4 - 0.1 * (lvl - 1),
				"count": 6 if evo else 1 + int(lvl >= 2) + int(lvl >= 4),
				"damage": 10.0 + 4.0 * lvl + (8.0 if evo else 0.0),
				"speed": 520.0, "spiral": evo,
			}
	return {}
