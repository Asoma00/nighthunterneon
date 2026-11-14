extends RefCounted
## Облики (скины) охотников.
##
## В мире игры: тело охотника в Ночи — это «световая оболочка», сотканная Маяком из
## памяти и неона. Ткачиха Сета в таверне умеет перешить оболочку — цвет, доспех,
## знаки. Но новый облик держится, только если охотник «заслужил» его образ: поэтому
## у каждого облика есть условие (подвиг, после которого образ закрепляется в памяти
## Маяка) и цена — осколки и материалы, из которых ткётся оболочка.

const Meta := preload("res://scripts/meta.gd")

## Редкость: имя, цвет рамки, цена.
const RARITY := [
	{"id": "common", "name": "Обычный", "color": Color(0.72, 0.74, 0.8), "cost": {"shards": 120}},
	{"id": "rare", "name": "Редкий", "color": Color(0.35, 0.65, 1.0), "cost": {"shards": 350, "scrap": 6}},
	{"id": "epic", "name": "Эпический", "color": Color(0.72, 0.4, 1.0), "cost": {"shards": 800, "chips": 6}},
	{"id": "legend", "name": "Легендарный", "color": Color(1.0, 0.75, 0.25), "cost": {"shards": 1600, "chips": 10, "cores": 2}},
	{"id": "myth", "name": "Мифический", "color": Color(1.0, 0.3, 0.65), "cost": {"shards": 3000, "cores": 6}},
]

## Облики по героям. look — что меняется в оболочке (цвета #rrggbb, «head»/«back» — тип),
## fx — особые знаки: halo, crown, horns, mask, eyes, antenna, ears, visor, flames, stars,
## petals, runes, wings, glitch.
const SKINS := {
	"vega": [
		{"id": "ash", "name": "Пепельная странница", "r": 0, "c": [["hero_runs", 3]], "look": {"main": "4a4a52", "back_c": "3a3a44", "head_c": "55555f", "neon": "ffb347", "neon2": "ff7a3d"},
			"desc": "Оболочка тех, кто первым прошёл через Пепельный предел и вернулся пропахшим гарью."},
		{"id": "frost", "name": "Морозный контур", "r": 1, "c": [["hkills", 1500]], "look": {"main": "2a5a8a", "back_c": "cfe8ff", "head_c": "e8f4ff", "neon": "9ff3ff", "neon2": "ffffff", "trim": "bfe6ff"},
			"desc": "Сета соткала её из инея, что намерзает на Маяке в самые длинные ночи."},
		{"id": "void", "name": "Королева пустоты", "r": 2, "c": [["bosses", 3]], "look": {"main": "1a0f2e", "back_c": "2b0a3d", "head_c": "0f0820", "neon": "b84dff", "neon2": "ff3dd8"}, "fx": ["halo"],
			"desc": "Говорят, в этом облике Вега однажды посмотрела в Разлом — и Разлом отвёл взгляд."},
		{"id": "star", "name": "Звёздная архимагиня", "r": 3, "c": [["level", 8]], "look": {"main": "10204a", "trim": "ffd66b", "back_c": "0b1638", "head_c": "1c2e66", "neon": "ffd66b", "neon2": "7fdcff"}, "fx": ["crown", "stars"],
			"desc": "Регалии последней архимагини Старого Города, найденные в архивах Библиотеки."},
		{"id": "glitch", "name": "Сбой реальности", "r": 4, "c": [["achievements", 25]], "look": {"main": "0a0a0a", "trim": "ff00ff", "back_c": "050505", "head_c": "111111", "neon": "00ffcc", "neon2": "ff00aa"}, "fx": ["glitch", "halo"],
			"desc": "Оболочка, которую Маяк не смог дописать до конца. Она мерцает между «есть» и «нет»."},
	],
	"rin": [
		{"id": "lantern", "name": "Бумажный фонарь", "r": 0, "c": [["hero_runs", 3]], "look": {"main": "6b2020", "trim": "f2d27a", "back_c": "f2e6c8", "neon": "ffcc66"},
			"desc": "Праздничный наряд с фестиваля фонарей — того, что был ещё до Ночи."},
		{"id": "rain", "name": "Ронин дождя", "r": 1, "c": [["hkills", 1500]], "look": {"main": "1f2a33", "trim": "5fa8d3", "back_c": "2f4f6f", "head_c": "2a3540", "neon": "66d9ff", "neon2": "c8f0ff"},
			"desc": "Рин бродила под кислотным дождём три ночи подряд, пока не нашла Убежище."},
		{"id": "oni", "name": "Они", "r": 2, "c": [["elites", 40]], "look": {"main": "3a0d0d", "trim": "ff3d3d", "back_c": "1a0505", "head_c": "5a1010", "neon": "ff2a2a", "neon2": "ffb0b0"}, "fx": ["horns", "mask"],
			"desc": "Маска демона, снятая с элитного стража Хора. Теперь она пугает их самих."},
		{"id": "sakura", "name": "Сакура-сёгун", "r": 3, "c": [["nodmg_best", 60]], "look": {"main": "f5d0e0", "trim": "ffd700", "back_c": "ff8fb8", "head_c": "fff0f6", "neon": "ff69b4", "neon2": "ffffff"}, "fx": ["petals", "crown"],
			"desc": "Облик для той, кого не может коснуться ни один удар. Лепестки — память о саде клана."},
		{"id": "nova", "name": "Клинок сверхновой", "r": 4, "c": [["bosses", 25]], "look": {"main": "0b0b1a", "trim": "ffffff", "back_c": "ffcf3d", "neon": "fff27a", "neon2": "ff7b00"}, "fx": ["flames", "halo"],
			"desc": "Катана, закалённая в сердцевинах двадцати пяти владык. Свет звезды в стали."},
	],
	"bram": [
		{"id": "appr", "name": "Подмастерье", "r": 0, "c": [["hero_runs", 3]], "look": {"main": "6b5a45", "trim": "b08a5a", "neon": "ffd27a"},
			"desc": "Рабочий фартук времён, когда Брам ещё учился у старого мастера кузни."},
		{"id": "ice", "name": "Ледяная кузня", "r": 1, "c": [["hkills", 1500]], "look": {"main": "4d6b85", "trim": "bfe9ff", "hair": "e8f6ff", "head_c": "6d8fa8", "neon": "8fe8ff", "neon2": "ffffff"},
			"desc": "Северная школа рун: металл куют на морозе, и он звенит, как стекло."},
		{"id": "lava", "name": "Лавовое сердце", "r": 2, "c": [["forged", 4]], "look": {"main": "2e1a12", "trim": "ff6a00", "hair": "ff4500", "head_c": "3d2316", "neon": "ff7b1a", "neon2": "ffd000"}, "fx": ["flames"],
			"desc": "Кто выковал четыре оружия из обломков, тот носит огонь горна на плечах."},
		{"id": "king", "name": "Рунный король", "r": 3, "c": [["forged", 9]], "look": {"main": "20304a", "trim": "ffd36b", "hair": "f0f0f0", "head_c": "c9a43a", "neon": "7fe0ff", "neon2": "ffd36b"}, "fx": ["crown", "runes"],
			"desc": "Венец подгорных королей. Руны на нём старше, чем сама Ночь."},
	],
	"kira": [
		{"id": "swamp", "name": "Болотная травница", "r": 0, "c": [["hero_runs", 3]], "look": {"main": "3a4a2a", "trim": "8fb35a", "hair": "6b8f3a", "neon": "b8ff6b"},
			"desc": "Облик деревенской знахарки — Кира прячется в нём от старых знакомых по сети."},
		{"id": "virus", "name": "Вирусная", "r": 1, "c": [["hkills", 1500]], "look": {"main": "1a1a1a", "trim": "ff2bd6", "hair": "ff2bd6", "head_c": "0f0f12", "neon": "ff2bd6", "neon2": "ffd0f5"},
			"desc": "Её подпись в сети: розовый код, который нельзя удалить."},
		{"id": "spider", "name": "Хозяйка пауков", "r": 2, "c": [["reactions", 300]], "look": {"main": "160c1f", "trim": "9b4dff", "hair": "ececec", "head_c": "0b0610", "neon": "a46bff", "neon2": "6bffb8"}, "fx": ["eyes"],
			"desc": "Шесть лишних глаз — шесть открытых потоков. Кира видит реакции раньше, чем они случаются."},
		{"id": "queen", "name": "Королева сети", "r": 3, "c": [["modules", 14]], "look": {"main": "0a1a2a", "trim": "00f0ff", "hair": "00f0ff", "head_c": "0c2236", "neon": "00f0ff", "neon2": "ffffff"}, "fx": ["halo", "antenna"],
			"desc": "Корона из антенн связывает её со всеми модулями Убежища сразу."},
	],
	"skyla": [
		{"id": "trail", "name": "Лесная тропа", "r": 0, "c": [["hero_runs", 3]], "look": {"main": "2f4a2a", "back_c": "5a3d22", "head_c": "4a6b3a", "neon": "9cff6b"},
			"desc": "Охотничий плащ из Техно-чащи — с ним лучница сливается с ветвями."},
		{"id": "owl", "name": "Полярная сова", "r": 1, "c": [["hkills", 1500]], "look": {"main": "dfe9f2", "trim": "9bb8d3", "head_c": "ffffff", "hair": "ffffff", "neon": "9fe8ff"},
			"desc": "Белое перо видно в темноте только тогда, когда уже поздно."},
		{"id": "hawk", "name": "Солнечный ястреб", "r": 2, "c": [["caches", 15]], "look": {"main": "7a3d0f", "trim": "ffb000", "head_c": "ffcf6b", "back_c": "8a4d1a", "neon": "ffcf3d", "neon2": "ff6a00"}, "fx": ["wings"],
			"desc": "Крылья из тайников Старого Города — лётные плащи курьеров Маяка."},
		{"id": "moon", "name": "Лунная охотница", "r": 3, "c": [["puzzles", 15]], "look": {"main": "141a3a", "trim": "c8d6ff", "head_c": "e6ecff", "hair": "c8d6ff", "back_c": "20285a", "neon": "b8c8ff", "neon2": "ffffff"}, "fx": ["wings", "stars"],
			"desc": "Облик для разгадавшей пятнадцать рунных загадок: звёзды Луны подсказывают ей путь."},
	],
	"orm": [
		{"id": "rust", "name": "Ржавый страж", "r": 0, "c": [["hero_runs", 3]], "look": {"main": "6b4a32", "head_c": "7a5a3a", "back_c": "4a2a1a", "neon": "ffb36b"},
			"desc": "Доспех, который Орм носил в паровых катакомбах, пока его не нашли охотники."},
		{"id": "black", "name": "Чёрный орден", "r": 1, "c": [["hkills", 1500]], "look": {"main": "1f1f24", "head_c": "2a2a30", "back_c": "5a0a0a", "trim": "a0a0a8", "neon": "ff3d3d"},
			"desc": "Цвета ордена, который клялся стоять у ворот, даже когда ворот уже нет."},
		{"id": "templar", "name": "Ледяной храмовник", "r": 2, "c": [["bosses", 5]], "look": {"main": "a8c8e0", "head_c": "dff0ff", "back_c": "3d6b9a", "trim": "ffffff", "neon": "9ff3ff", "neon2": "ffffff"}, "fx": ["halo"],
			"desc": "Холодный свет святого контура — он не греет, но и не гаснет."},
		{"id": "dawn", "name": "Паладин зари", "r": 3, "c": [["level", 10]], "look": {"main": "f2e2b8", "head_c": "ffe08a", "back_c": "ffffff", "trim": "ffd700", "neon": "fff0a0", "neon2": "ffb000"}, "fx": ["wings", "halo"],
			"desc": "Обещание рассвета. Носить его можно только тому, кто дошёл до середины Ночи."},
	],
	"mora": [
		{"id": "keeper", "name": "Кладбищенский сторож", "r": 0, "c": [["hero_runs", 3]], "look": {"main": "2a2a24", "back_c": "3a3a30", "head_c": "4a4a40", "neon": "c8ff8f"},
			"desc": "Мора когда-то сторожила серверное кладбище — там хранили удалённые души."},
		{"id": "bride", "name": "Костяная невеста", "r": 1, "c": [["hkills", 1500]], "look": {"main": "e8e0e8", "back_c": "f5f0f5", "head_c": "ffffff", "trim": "d0a0d0", "neon": "ff9fe8"},
			"desc": "Платье из резервных копий. Каждая нитка — чьё-то сохранённое воспоминание."},
		{"id": "reaper", "name": "Жнец данных", "r": 2, "c": [["events", 15]], "look": {"main": "001a10", "back_c": "00281a", "head_c": "002a1a", "trim": "00ff88", "neon": "00ff88", "neon2": "b0ffd8"}, "fx": ["eyes", "runes"],
			"desc": "Зелёный код смерти. Жнец пришёл за ошибками, а не за людьми."},
		{"id": "deadnet", "name": "Королева мёртвых сетей", "r": 3, "c": [["elites", 150]], "look": {"main": "1a0a2a", "back_c": "2a0f40", "head_c": "e8e0f0", "trim": "ffd36b", "neon": "c060ff", "neon2": "ffd36b"}, "fx": ["crown", "halo"],
			"desc": "Ей подчиняются все отключённые машины Старого Города."},
		{"id": "eclipse", "name": "Затмение", "r": 4, "c": [["kills", 50000]], "look": {"main": "000000", "back_c": "050008", "head_c": "0a0010", "trim": "ff2a6a", "neon": "ff2a6a", "neon2": "ffffff"}, "fx": ["glitch", "eyes", "stars"],
			"desc": "Пятьдесят тысяч угасших теней. Их пустота стала её плащом."},
	],
	"zephyr": [
		{"id": "nomad", "name": "Пыльный кочевник", "r": 0, "c": [["hero_runs", 3]], "look": {"main": "6b5a3a", "back_c": "8a6b3a", "neon": "ffd27a"},
			"desc": "Наряд степных шаманов, что слушали ветер ещё до неона."},
		{"id": "raven", "name": "Грозовой ворон", "r": 1, "c": [["hkills", 1500]], "look": {"main": "1a1f2a", "back_c": "12161f", "head_c": "0f1218", "neon": "9fb8ff", "neon2": "ffffff"},
			"desc": "Чёрные перья, по которым бежит молния."},
		{"id": "sand", "name": "Песчаная буря", "r": 2, "c": [["reactions", 500]], "look": {"main": "c9a26b", "back_c": "e0bf86", "head_c": "8a6b3a", "trim": "ff8a3d", "neon": "ffb347", "neon2": "fff0c0"}, "fx": ["runes"],
			"desc": "Пятьсот реакций стихий — и ветер начал отвечать на его песни."},
		{"id": "dragon", "name": "Небесный дракон", "r": 3, "c": [["endless", 15]], "look": {"main": "0f3a4a", "back_c": "1a5a6b", "head_c": "ffd36b", "trim": "ffd36b", "neon": "6bfff0", "neon2": "ffd36b"}, "fx": ["wings", "horns"],
			"desc": "Облик того, кто выстоял пятнадцать минут Бесконечной ночи. Ветер стал ему крыльями."},
	],
	"iris": [
		{"id": "lab", "name": "Лаборантка", "r": 0, "c": [["hero_runs", 3]], "look": {"main": "e0e8e8", "back_c": "c8d0d0", "hair": "3a2a1a", "neon": "6bd6ff"},
			"desc": "Чистый халат первого дня в Лаборатории модулей."},
		{"id": "toxic", "name": "Токсичная", "r": 1, "c": [["hkills", 1500]], "look": {"main": "2a3a10", "back_c": "3a4a18", "hair": "b8ff2a", "head_c": "1a1a1a", "neon": "b8ff2a", "neon2": "ffef3d"},
			"desc": "Неудачный опыт, который Ирис решила считать удачным."},
		{"id": "plague", "name": "Чумной доктор", "r": 2, "c": [["fusions", 2]], "look": {"main": "141414", "back_c": "0a0a0a", "head_c": "2a2a2a", "hair": "141414", "trim": "8a6b3a", "neon": "7dff4a"}, "fx": ["mask"],
			"desc": "Старые врачи лечили мор, новые — порчу Хора. Маска одна и та же."},
		{"id": "elixir", "name": "Алхимик бессмертия", "r": 3, "c": [["modules", 18]], "look": {"main": "f5e6c8", "back_c": "ffffff", "hair": "ffd36b", "trim": "ffd36b", "neon": "ffd36b", "neon2": "ff6bd6"}, "fx": ["halo", "stars"],
			"desc": "Восемнадцать чертежей модулей — почти формула вечной жизни."},
	],
	"kai": [
		{"id": "alley", "name": "Тень переулка", "r": 0, "c": [["hero_runs", 3]], "look": {"main": "2a2a30", "back_c": "4a4a55", "trim": "6b6b78", "neon": "9fa8ff"},
			"desc": "Неприметный облик курьера нижнего города."},
		{"id": "ghost", "name": "Белый призрак", "r": 1, "c": [["hkills", 1500]], "look": {"main": "e6e6ee", "trim": "ff3d6a", "back_c": "ff3d6a", "head_c": "f0f0f5", "skin": "f0f0f5", "neon": "ff3d6a"},
			"desc": "Белый — дерзость. Кай хочет, чтобы его видели. За миг до удара."},
		{"id": "fox", "name": "Кибер-лис", "r": 2, "c": [["nodmg_best", 45]], "look": {"main": "3a1a0a", "trim": "ff7a1a", "back_c": "ff7a1a", "head_c": "ff7a1a", "neon": "ffb347", "neon2": "ffffff"}, "fx": ["ears"],
			"desc": "Лис-оборотень из городских сказок. Неуловим, как и обещано."},
		{"id": "shadow", "name": "Повелитель теней", "r": 3, "c": [["best_kills", 3000]], "look": {"main": "050508", "trim": "8a2be2", "back_c": "2a0a4a", "head_c": "08080c", "neon": "b06bff", "neon2": "ff6bd6"}, "fx": ["eyes", "flames"],
			"desc": "Три тысячи теней за одну ночь — и они начали подчиняться."},
		{"id": "null", "name": "Нулевой протокол", "r": 4, "c": [["nodmg_best", 180]], "look": {"main": "000000", "trim": "00ff66", "back_c": "00ff66", "head_c": "000000", "neon": "00ff66", "neon2": "ccffdd"}, "fx": ["glitch", "visor"],
			"desc": "Три минуты без единой царапины. Для Хора Кай просто перестаёт существовать."},
	],
	"lyra": [
		{"id": "street", "name": "Уличная танцовщица", "r": 0, "c": [["hero_runs", 3]], "look": {"main": "5a2a4a", "trim": "ffb0d0", "back_c": "ff7ab0", "neon": "ff9fd0"},
			"desc": "В этом наряде Лира танцевала на площади, когда погас свет."},
		{"id": "veil", "name": "Лунная вуаль", "r": 1, "c": [["hkills", 1500]], "look": {"main": "1a2050", "trim": "c8d6ff", "back_c": "e6ecff", "hair": "ffffff", "neon": "c8d6ff"},
			"desc": "Вуаль отражает свет клинков, и враги видят десять Лир вместо одной."},
		{"id": "fan", "name": "Огненный веер", "r": 2, "c": [["chests", 60]], "look": {"main": "4a0a0a", "trim": "ffb000", "back_c": "ff4500", "hair": "ff6a00", "head_c": "ffd36b", "neon": "ff6a00", "neon2": "ffd000"}, "fx": ["flames"],
			"desc": "Шестьдесят открытых сундуков: среди трофеев нашёлся веер из живого огня."},
		{"id": "crystal", "name": "Принцесса кристаллов", "r": 3, "c": [["fusions", 5]], "look": {"main": "6bd6ff", "trim": "ffffff", "back_c": "c8f6ff", "head_c": "e0fbff", "hair": "b0f0ff", "neon": "ffffff", "neon2": "6bd6ff"}, "fx": ["crown", "stars"],
			"desc": "Пять слияний оружия — кристаллы Разлома признали её своей."},
	],
	"sol": [
		{"id": "sand", "name": "Песочный жрец", "r": 0, "c": [["hero_runs", 3]], "look": {"main": "7a5a3a", "back_c": "5a3d22", "head_c": "c8a06b", "trim": "e0c080", "neon": "ffe08a"},
			"desc": "Облачение пустынных храмов, где солнце ещё помнят."},
		{"id": "moon", "name": "Затмение луны", "r": 1, "c": [["hkills", 1500]], "look": {"main": "2a2a40", "back_c": "1a1a2a", "head_c": "8a8aa8", "trim": "c8c8e0", "neon": "c8d6ff"},
			"desc": "Даже солнечный жрец иногда хочет побыть в тени."},
		{"id": "forge", "name": "Хранитель горна", "r": 2, "c": [["bosses", 10]], "look": {"main": "5a1a0a", "back_c": "8a2a0a", "head_c": "ff8a3d", "trim": "ffd000", "neon": "ff6a00", "neon2": "ffd000"}, "fx": ["flames"],
			"desc": "Огонь, которым Сол разжёг горн Рунной кузницы."},
		{"id": "nova", "name": "Сверхновая", "r": 3, "c": [["level", 15]], "look": {"main": "fff5d6", "back_c": "ffd36b", "head_c": "ffffff", "trim": "ffb000", "neon": "ffffff", "neon2": "ffd000"}, "fx": ["halo", "wings"],
			"desc": "Половина пути к Рассвету — и солнце внутри Сола впервые засияло в полную силу."},
		{"id": "black", "name": "Чёрное солнце", "r": 4, "c": [["level", 30]], "look": {"main": "0a0505", "back_c": "1a0a00", "head_c": "0a0a0a", "trim": "ff4500", "neon": "ff4500", "neon2": "ffd000"}, "fx": ["halo", "glitch", "flames"],
			"desc": "Облик того, кто прошёл всю Ночь до конца и увидел, что за ней."},
	],
	"volt": [
		{"id": "lineman", "name": "Монтёр", "r": 0, "c": [["hero_runs", 3]], "look": {"main": "2a4a8a", "back_c": "3a5a9a", "trim": "ffcc00", "neon": "ffcc00"},
			"desc": "Рабочая роба городской электросети. Вольт чинил её, пока она не стала оружием."},
		{"id": "diesel", "name": "Ржавый дизель", "r": 1, "c": [["hkills", 1500]], "look": {"main": "5a3a1a", "back_c": "6b4a2a", "trim": "c87a3a", "hair": "2a2a2a", "neon": "ff9f3d"},
			"desc": "Пахнет маслом и озоном. Механики Убежища одобряют."},
		{"id": "tesla", "name": "Тесла-панк", "r": 2, "c": [["reactions", 400]], "look": {"main": "1a1a2a", "back_c": "2a1a3a", "trim": "b06bff", "hair": "ffffff", "neon": "b06bff", "neon2": "6bd6ff"}, "fx": ["antenna"],
			"desc": "Катушка на спине звенит от каждой реакции стихий."},
		{"id": "thunder", "name": "Бог грома", "r": 3, "c": [["bosses", 20]], "look": {"main": "0a1a3a", "back_c": "ffffff", "head_c": "ffd36b", "hair": "ffffff", "trim": "ffd36b", "neon": "9fe8ff", "neon2": "ffffff"}, "fx": ["crown", "stars"],
			"desc": "Двадцать павших владык. Молнии теперь приходят сами, когда он их зовёт."},
	],
}


static func list_for(hero: String) -> Array:
	return SKINS.get(hero, [])


static func get_skin(hero: String, id: String) -> Dictionary:
	for s in list_for(hero):
		if s["id"] == id:
			return s
	return {}


## Ключ спрайта героя с обликом: «rin~oni»; без облика — базовый ключ.
static func sprite_key(hero: String, base_sprite: String, id: String) -> String:
	if id == "" or get_skin(hero, id).is_empty():
		return base_sprite
	return base_sprite + "~" + id


## Внешность для Pixel.look(): базовая + изменения облика.
static func look_for(key: String, base_looks: Dictionary) -> Dictionary:
	var parts := key.split("~")
	var base_sprite: String = parts[0]
	var L: Dictionary = (base_looks.get(base_sprite, {}) as Dictionary).duplicate()
	var hero := hero_of_sprite(base_sprite)
	var sk := get_skin(hero, parts[1] if parts.size() > 1 else "")
	for k in sk.get("look", {}):
		var v = sk["look"][k]
		L[k] = Color("#" + str(v)) if str(v).length() == 6 and str(v).is_valid_hex_number() else v
	# Цвета, что не заданы явно, подстраиваются под новый основной
	var lk: Dictionary = sk.get("look", {})
	if lk.has("main") and not lk.has("legs"):
		L["legs"] = (L["main"] as Color).darkened(0.4)
	if lk.has("neon") and not lk.has("gem"):
		L["gem"] = L["neon"]
	L["fx"] = sk.get("fx", [])
	return L


static func hero_of_sprite(sprite: String) -> String:
	var D = preload("res://scripts/data.gd")
	for h in D.CHARACTERS:
		if str(D.CHARACTERS[h]["sprite"]) == sprite:
			return h
	return sprite


# ---------------- Состояние облика ----------------

## Условие облика выполнено (облик можно соткать).
static func cond_ok(hero: String, s: Dictionary) -> bool:
	return Meta.conds_met(s.get("c", []), hero)


static func owned(hero: String, id: String) -> bool:
	Meta.ensure_loaded()
	return id == "" or (hero + ":" + id) in Meta.skins_owned


static func equipped(hero: String) -> String:
	Meta.ensure_loaded()
	var id := str(Meta.skin_on.get(hero, ""))
	return id if owned(hero, id) else ""


static func cost(s: Dictionary) -> Dictionary:
	return RARITY[int(s["r"])]["cost"]


## Почему нельзя купить ("" — можно).
static func buy_block(hero: String, s: Dictionary) -> String:
	if owned(hero, s["id"]):
		return "уже ваш"
	if not Meta.hero_unlocked(hero):
		return "сначала наймите героя"
	if not cond_ok(hero, s):
		return "условие не выполнено"
	if not Meta.can_afford(cost(s)):
		return "не хватает: " + Meta.cost_text(cost(s))
	return ""


static func buy(hero: String, s: Dictionary) -> bool:
	if buy_block(hero, s) != "":
		return false
	Meta.pay(cost(s))
	Meta.skins_owned.append(hero + ":" + str(s["id"]))
	Meta.skin_on[hero] = s["id"]
	Meta.save()
	return true


static func equip(hero: String, id: String) -> void:
	if owned(hero, id):
		Meta.skin_on[hero] = id
		Meta.save()


static func owned_count() -> int:
	Meta.ensure_loaded()
	return Meta.skins_owned.size()


static func total() -> int:
	var n := 0
	for h in SKINS:
		n += SKINS[h].size()
	return n
