extends RefCounted
## Процедурная пиксель-графика: рисование в Image, объём, обводка,
## генерация анимированных спрайтов, тайлов, иконок и текстур свечения.
## Каждый спрайт состоит из двух слоёв: base (освещается светом сцены)
## и emit (неоновые детали, светятся сами и дают bloom).

const PX := 3.0
## Растяжение «стоящих» спрайтов по высоте: компенсирует наклон камеры в 2.5D
const STAND := 1.45
const OUT := Color(0.04, 0.02, 0.08)

static var _cache := {}
const Icons := preload("res://scripts/icons.gd")


# ============ Примитивы ============

static func blank(w: int, h: int) -> Image:
	return Image.create_empty(w, h, false, Image.FORMAT_RGBA8)


static func px(im: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < im.get_width() and y < im.get_height():
		im.set_pixel(x, y, c)


static func pxw(im: Image, x: int, y: int, c: Color) -> void:
	im.set_pixel(posmod(x, im.get_width()), posmod(y, im.get_height()), c)


static func rect(im: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for i in range(x, x + w):
		for j in range(y, y + h):
			px(im, i, j, c)


static func ellipse(im: Image, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for x in range(int(floor(cx - rx)) - 1, int(ceil(cx + rx)) + 1):
		for y in range(int(floor(cy - ry)) - 1, int(ceil(cy + ry)) + 1):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				px(im, x, y, c)


static func line(im: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	var guard := 0
	while guard < 500:
		guard += 1
		px(im, x0, y0, c)
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy


static func poly(im: Image, pts: PackedVector2Array, c: Color) -> void:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	for x in range(int(floor(r.position.x)), int(ceil(r.end.x)) + 1):
		for y in range(int(floor(r.position.y)), int(ceil(r.end.y)) + 1):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts):
				px(im, x, y, c)


static func alpha_at(im: Image, x: int, y: int) -> float:
	if x < 0 or y < 0 or x >= im.get_width() or y >= im.get_height():
		return 0.0
	return im.get_pixel(x, y).a


# ============ Обработка ============

## Вертикальный градиент: низ темнее — даёт объём.
static func vshade(im: Image, amount: float) -> void:
	var h := float(im.get_height())
	for x in im.get_width():
		for y in im.get_height():
			var c := im.get_pixel(x, y)
			if c.a > 0.5:
				im.set_pixel(x, y, c.darkened(amount * y / h))


## Свет сверху-слева: светлая кромка сверху/слева, тёмная снизу/справа.
static func shade(im: Image, hi := 0.25, lo := 0.32) -> void:
	var src := im.duplicate() as Image
	for x in im.get_width():
		for y in im.get_height():
			var c := src.get_pixel(x, y)
			if c.a < 0.5:
				continue
			if alpha_at(src, x, y - 1) < 0.5 or alpha_at(src, x - 1, y) < 0.5:
				im.set_pixel(x, y, c.lightened(hi))
			elif alpha_at(src, x, y + 1) < 0.5 or alpha_at(src, x + 1, y) < 0.5:
				im.set_pixel(x, y, c.darkened(lo))


static func outline(im: Image, c := OUT) -> void:
	var src := im.duplicate() as Image
	for x in im.get_width():
		for y in im.get_height():
			if src.get_pixel(x, y).a >= 0.5:
				continue
			if alpha_at(src, x + 1, y) >= 0.5 or alpha_at(src, x - 1, y) >= 0.5 \
					or alpha_at(src, x, y + 1) >= 0.5 or alpha_at(src, x, y - 1) >= 0.5:
				im.set_pixel(x, y, c)


static func silhouette(im: Image) -> Image:
	var s := blank(im.get_width(), im.get_height())
	for x in im.get_width():
		for y in im.get_height():
			if im.get_pixel(x, y).a >= 0.5:
				s.set_pixel(x, y, Color.WHITE)
	return s


static func tex(im: Image) -> ImageTexture:
	return ImageTexture.create_from_image(im)


static func hdr(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)


# ============ Анимированные спрайты ============

const SPECS := {
	# ключ: [ширина, высота, кадров, тень/объём, цвет обводки]
	# Герои: детальный риг 32×40, 16 кадров; на экране — в масштабе 0.7 (тот же размер, больше деталей)
	"hero": [48, 60, 35, true, 0.56],
	"rin": [48, 60, 35, true, 0.56],
	"bram": [48, 60, 35, true, 0.56],
	"kira": [48, 60, 35, true, 0.56],
	"skyla": [48, 60, 35, true, 0.56],
	"orm": [48, 60, 35, true, 0.56],
	"mora": [48, 60, 35, true, 0.56],
	"zephyr": [48, 60, 35, true, 0.56],
	"iris": [48, 60, 35, true, 0.56],
	"kai": [48, 60, 35, true, 0.56],
	"lyra": [48, 60, 35, true, 0.56],
	"sol": [48, 60, 35, true, 0.56],
	"volt": [48, 60, 35, true, 0.56],
	"goblin": [24, 24, 12, true, 0.667],
	"slime": [30, 24, 12, true, 0.667],
	"slimelet": [18, 15, 12, true, 0.667],
	"spider": [36, 24, 12, true, 0.667],
	"spiderling": [21, 15, 12, true, 0.667],
	"caster": [27, 36, 12, true, 0.667],
	"bomber": [24, 24, 12, true, 0.667],
	"knight": [30, 40, 12, true, 0.667],
	"omega": [100, 108, 20, true, 0.5],
	"arrow": [16, 5, 1, false],
	"spirit": [11, 13, 2, false],
	"shuriken": [11, 11, 2, false],
	"flaskp": [7, 10, 1, true],
	"lich": [80, 92, 20, true, 0.5],
	"colossus": [100, 92, 20, true, 0.5],
	"queen": [104, 84, 20, true, 0.5],
	"chest": [18, 16, 2, true],
	"drone": [22, 16, 2, true],
	"shard": [9, 5, 1, false],
	"sword": [9, 20, 1, false],
	"imp": [28, 30, 12, true, 0.667],
	"bat": [38, 24, 12, true, 0.667],
	"ghoul": [30, 40, 12, true, 0.667],
	"wraith": [30, 40, 12, false, 0.667],
	"brute": [54, 57, 12, true, 0.667],
	"gem1": [11, 13, 1, true],
	"gem3": [11, 13, 1, true],
	"gem5": [11, 13, 1, true],
	"gem9": [13, 15, 1, true],
	"gemx": [19, 23, 1, true],
	"heal": [11, 11, 1, true],
	"res_scrap": [13, 13, 1, true],
	"res_chips": [13, 13, 1, true],
	"res_cores": [13, 13, 1, true],
	"orb": [9, 9, 1, false],
	"blade": [18, 7, 1, false],
	"lamp0": [14, 44, 1, true],
	"lamp1": [14, 44, 1, true],
	"obelisk0": [16, 34, 1, true],
	"obelisk1": [16, 34, 1, true],
	"obelisk2": [16, 34, 1, true],
	"crystal0": [20, 18, 1, true],
	"crystal1": [20, 18, 1, true],
	"crate0": [18, 16, 1, true],
	"crate1": [18, 16, 1, true],
	"puddle0": [28, 12, 1, false],
	"sign0": [18, 34, 1, true],
	"sign1": [18, 34, 1, true],
	"barrel0": [12, 15, 1, true],
	"barrel1": [12, 15, 1, true],
	"rock0": [20, 14, 1, true],
	"rock1": [16, 12, 1, true],
	"crystal_big0": [22, 34, 1, true],
	"crystal_big1": [22, 34, 1, true],
	"pillar0": [14, 36, 1, true],
	"pillar1": [14, 24, 1, true],
	"statue0": [18, 38, 1, true],
	"tree0": [40, 54, 1, false],
	"tree1": [40, 54, 1, false],
	"tree2": [32, 44, 1, false],
	"tree3": [40, 52, 1, false],
	"pine2": [30, 58, 1, false],
	"mushroom0": [16, 14, 1, true],
	"mushroom1": [20, 18, 1, true],
	"wreck0": [30, 18, 1, true],
	"wreck1": [24, 22, 1, true],
	"house0": [74, 88, 1, true],
	"house1": [74, 88, 1, true],
	"house2": [64, 106, 1, true],
	"manor0": [124, 134, 1, true],
	"keep0": [80, 120, 1, true],
	"tower0": [42, 96, 1, true],
	"wall0": [48, 30, 1, true],
	"gate0": [48, 50, 1, true],
	"stall0": [32, 28, 1, true],
	"stall1": [32, 28, 1, true],
	"well0": [22, 24, 1, true],
	"banner0": [14, 42, 1, true],
	"banner1": [14, 42, 1, true],
	"lantern0": [12, 34, 1, true],
	"pine0": [32, 62, 1, false],
	"pine1": [26, 48, 1, false],
	"bush0": [22, 15, 1, false],
	"bush1": [18, 13, 1, false],
	"cart0": [30, 20, 1, true],
	"fence0": [32, 14, 1, true],
	"decal_cobble": [48, 26, 1, false],
	"decal_road": [64, 22, 1, false],
	"decal_rune": [48, 48, 1, false],
	"decal_grate": [24, 16, 1, false],
	"decal_moss": [30, 18, 1, false],
	"decal_cable": [40, 14, 1, false],
	"decal_crater": [34, 20, 1, false],
	"puddle1": [28, 12, 1, false],
}


## Возвращает {"base": [ImageTexture], "emit": [...], "flash": [...], "size": Vector2}
static func frames(key: String, cache_key := "") -> Dictionary:
	if cache_key == "":
		cache_key = key
	if _cache.has(cache_key):
		return _cache[cache_key]
	var spec: Array = SPECS[key] if SPECS.has(key) else ([48, 60, CITIZEN_FRAMES, true, 0.5] if key.begins_with("citizen_") else [18, 24, 8, true])
	var w: int = spec[0]
	var h: int = spec[1]
	var count: int = spec[2]
	var volume: bool = spec[3]
	var result := {"base": [], "emit": [], "flash": [], "size": Vector2(w, h), "k": float(spec[4]) if spec.size() > 4 else 1.0}
	for f in count:
		var base := blank(w, h)
		var emit := blank(w, h)
		_paint(key, base, emit, f)
		# Неоновые пиксели тоже часть силуэта
		for x in w:
			for y in h:
				var ec := emit.get_pixel(x, y)
				if ec.a > 0.3 and base.get_pixel(x, y).a < 0.5:
					base.set_pixel(x, y, Color(ec.r * 0.35, ec.g * 0.35, ec.b * 0.35, 1.0))
		if volume:
			vshade(base, 0.35)
			shade(base)
		if not key.begins_with("puddle") and not key.begins_with("decal_"):
			outline(base, Color(0.08, 0.2, 0.3) if key == "wraith" else OUT)
		result["base"].append(tex(base))
		result["emit"].append(tex(emit))
		result["flash"].append(tex(silhouette(base)))
	_cache[cache_key] = result
	return result


# ---------- Модули на герое ----------
# Модули не кружат вокруг, а становятся частью персонажа: кибер-сердце светится
# в груди, неоновые сапоги — на ногах, прицел и охладитель крепятся к оружию.
# Спрайт героя перерисовывается под набор модулей (кэш по набору и «ступени»).

static var _mods := {}
static var _anc := {}


## Кадры героя с модулями: mods = {id: ступень 1..2}.
static func hero_frames(key: String, mods: Dictionary) -> Dictionary:
	if mods.is_empty():
		return frames(key)
	var ids: Array = mods.keys()
	ids.sort()
	var sig := ""
	for id in ids:
		sig += "%s%d," % [id, int(mods[id])]
	var ck := key + "|m:" + sig
	if _cache.has(ck):
		return _cache[ck]
	_mods = mods
	var r := frames(key, ck)
	_mods = {}
	return r


## Конец оружия в кадре (логические координаты рига).
static func _weapon_tip(weapon: String, h: Vector2, dir: Vector2, st: String) -> Vector2:
	var at := st == "attack"
	match weapon:
		"staff", "orbstaff":
			return h + dir * 12.0 if at else Vector2(h.x + 1, h.y - 13)
		"scythe":
			return h + dir * 12.0 if at else Vector2(h.x + 1, h.y - 14)
		"katana":
			return h + dir * 13.0 if at else Vector2(h.x + 3, h.y - 10)
		"blade":
			return h + dir * 9.0 if at else Vector2(h.x + 3, h.y - 10)
		"hammer":
			return h + (dir if at else Vector2(0.35, -1).normalized()) * 10.0
		"mace":
			return h + (dir if at else Vector2(0.2, -1).normalized()) * 9.0
		"wand":
			return h + (dir if at else Vector2(0.4, -1).normalized()) * 6.0
		"bow":
			return h + Vector2(2, -8)
		"flask":
			return h + (dir if at else Vector2(0.3, 1).normalized()) * 3.0
	return h + dir * 6.0


static func _paint_mods(b: Image, e: Image, L: Dictionary, f: int) -> void:
	if _anc.is_empty():
		return
	var cx: float = _anc["cx"]
	var sh: float = _anc["sh"]
	var hip: float = _anc["hip"]
	var tw: float = _anc["tw"]
	var hand: Vector2 = _anc["hand"]
	var tip: Vector2 = _anc["tip"]
	var hx: float = _anc["hx"]
	var hy: float = _anc["hy"]
	var ff: Vector2 = _anc["ff"]
	var fb: Vector2 = _anc["fb"]
	var sway: float = _anc["sway"]
	var st: String = _anc["st"]
	var wd := (tip - hand).normalized() if tip.distance_to(hand) > 0.5 else Vector2.UP
	var side := Vector2(-wd.y, wd.x)
	var pulse := f % 4 < 2
	for id in _mods:
		var t2: bool = int(_mods[id]) >= 2
		match id:
			"hp":
				# Кибер-сердце в груди
				sell(b, cx + 0.5, sh + 4.5, 2.2, 2.0, Color(0.3, 0.32, 0.4))
				sell(e, cx + 0.5, sh + 4.5, 1.3 if pulse else 1.0, 1.2 if pulse else 0.9, Color(1.0, 0.2, 0.35))
				if t2:
					sline(e, int(cx - tw + 1), int(sh + 4), int(cx - 1), int(sh + 4), Color(0.4, 1.0, 1.0, 0.8))
			"speed":
				# Неоновые подошвы и крылышко у щиколотки
				for ft in [ff, fb]:
					sline(e, int(ft.x) - 1, int(ft.y) + 1, int(ft.x) + 2, int(ft.y) + 1, Color(1.0, 0.3, 0.8))
				spoly(b, PackedVector2Array([ff + Vector2(-1, -3), ff + Vector2(-4, -5), ff + Vector2(-3, -2)]), Color(0.85, 0.92, 1.0))
				if st == "run" or t2:
					spx(e, int(fb.x) - 3, int(fb.y), Color(0.4, 0.95, 1.0, 0.7))
					spx(e, int(fb.x) - 5, int(fb.y), Color(0.4, 0.95, 1.0, 0.45))
			"magnet":
				# Гравимагнит-ранец за спиной
				var bx := cx - tw - 1.5
				srect(b, int(bx - 1), int(sh + 1), 3, 5, Color(0.85, 0.16, 0.24))
				srect(b, int(bx - 1), int(sh + 5), 1, 2, Color(0.85, 0.88, 0.95))
				srect(b, int(bx + 1), int(sh + 5), 1, 2, Color(0.85, 0.88, 0.95))
				var ph := f * 0.7
				for i in (3 if t2 else 2):
					spx(e, int(bx - 2 - i + sin(ph + i) * 0.6), int(sh + 8 + i), Color(0.75, 0.45, 1.0, 0.85 - i * 0.2))
			"regen":
				# Перевязь с капсулами нано-лечения
				sline(b, int(cx - tw + 1), int(sh + 1), int(cx + tw - 1), int(hip - 3), Color(0.25, 0.3, 0.28))
				for i in (3 if t2 else 2):
					var p := Vector2(cx - tw + 1, sh + 1).lerp(Vector2(cx + tw - 1, hip - 3), 0.25 + i * 0.3)
					spx(e, int(p.x), int(p.y), Color(0.35, 1.0, 0.5))
			"armor":
				# Рунные наплечники
				sell(b, cx + tw - 1.0, sh - 0.2, 3.4, 2.2, Color(0.58, 0.64, 0.76))
				srect(b, int(cx + tw - 4), int(sh - 2), 6, 1, Color(0.96, 0.72, 0.28))
				spx(e, int(cx + tw - 1), int(sh), Color(0.45, 0.85, 1.0))
				sell(b, cx - tw + 0.5, sh + 0.5, 2.4, 1.8, Color(0.46, 0.5, 0.62))
				if t2:
					srect(b, int(cx - tw + 1), int(sh + 6), int(tw * 2 - 2), 2, Color(0.5, 0.55, 0.66))
					spx(e, int(cx), int(sh + 6), Color(0.45, 0.85, 1.0))
			"vamp":
				# Вампирский чип на виске и алая метка
				srect(b, int(hx - 3), int(hy - 1), 2, 2, Color(0.16, 0.14, 0.2))
				spx(e, int(hx - 3), int(hy - 1), Color(1.0, 0.12, 0.3))
				if t2:
					sline(e, int(hx - 3), int(hy + 1), int(hx - 2), int(hy + 3), Color(1.0, 0.15, 0.3, 0.8))
			"luck":
				# Кубик-талисман на поясе
				var d := Vector2(cx - tw + 1.5 - sway * 0.3, hip + 1)
				sline(b, int(cx - tw + 2), int(hip - 1), int(d.x), int(d.y), Color(0.96, 0.72, 0.28))
				srect(b, int(d.x) - 1, int(d.y), 2, 2, Color(0.95, 0.92, 0.85))
				spx(e, int(d.x), int(d.y) + (1 if pulse else 0), Color(1.0, 0.82, 0.25))
			"damage":
				# Руна ярости: оружие тлеет у острия
				spx(e, int(tip.x), int(tip.y), Color(1.0, 0.4, 0.1))
				spx(e, int(tip.x + side.x * 1.5), int(tip.y + side.y * 1.5 - (1 if pulse else 0)), Color(1.0, 0.65, 0.2, 0.9))
				spx(e, int(tip.x - side.x * 1.5), int(tip.y - side.y * 1.5 - (0 if pulse else 1)), Color(1.0, 0.3, 0.1, 0.8))
				if t2:
					var m := hand.lerp(tip, 0.6)
					spx(e, int(m.x), int(m.y), Color(1.0, 0.35, 0.15))
			"cooldown":
				# Охладитель ядра на древке над кистью
				var p := hand.lerp(tip, 0.35) + side * 1.2
				srect(b, int(p.x) - 1, int(p.y) - 1, 2, 3, Color(0.5, 0.55, 0.66))
				spx(e, int(p.x), int(p.y), Color(0.3, 0.9, 1.0))
				if t2:
					spx(e, int(p.x), int(p.y) + 1, Color(0.3, 0.9, 1.0, 0.8))
			"area":
				# Кольцо-излучатель вокруг острия
				for i in 6:
					var a := TAU * i / 6.0 + f * 0.4
					var r := 2.6 if not t2 else 3.2
					spx(e, int(tip.x + cos(a) * r), int(tip.y + sin(a) * r * 0.7), Color(0.85, 0.5, 1.0, 0.8))
			"crit":
				# Прицел-имплант на оружии и лазерная точка
				var p := hand.lerp(tip, 0.6) - side * 1.5
				srect(b, int(p.x) - 1, int(p.y) - 1, 3, 2, Color(0.2, 0.2, 0.26))
				spx(e, int(p.x) + 1, int(p.y), Color(1.0, 0.25, 0.3))
				if st == "attack" or t2:
					for i in 4:
						spx(e, int(p.x + wd.x * (3 + i * 2)), int(p.y + wd.y * (3 + i * 2)), Color(1.0, 0.2, 0.3, 0.75 - i * 0.15))
			"multi":
				# Второй ствол/лезвие вдоль оружия
				var a0 := hand.lerp(tip, 0.45) + side * 1.6
				var a1 := tip + side * 1.6 - wd * 1.0
				sline(b, int(a0.x), int(a0.y), int(a1.x), int(a1.y), Color(0.55, 0.58, 0.7))
				spx(e, int(a1.x), int(a1.y), Color(0.9, 0.5, 1.0))
				if t2:
					var b0 := hand.lerp(tip, 0.5) - side * 1.6
					var b1 := tip - side * 1.6 - wd * 1.5
					sline(b, int(b0.x), int(b0.y), int(b1.x), int(b1.y), Color(0.55, 0.58, 0.7))
					spx(e, int(b1.x), int(b1.y), Color(0.9, 0.5, 1.0))
			"duration":
				# Колба-катализатор на навершии
				var p := hand - wd * 2.0
				srect(b, int(p.x) - 1, int(p.y) - 1, 2, 2, Color(0.6, 0.75, 0.85))
				spx(e, int(p.x), int(p.y), Color(0.5, 0.95, 1.0))


static func _paint(key: String, b: Image, e: Image, f: int) -> void:
	if key.begins_with("tree") or key.begins_with("pine") or key.begins_with("bush"):
		_paint_tree(key, b, e)
		return
	if key in ["house0", "house1", "house2", "tower0", "wall0", "gate0", "stall0", "stall1", "well0",
			"banner0", "banner1", "lantern0", "pine0", "pine1", "bush0", "bush1", "cart0", "fence0",
			"decal_cobble", "decal_road"]:
		_paint_medieval(key, b, e)
		return
	if key.begins_with("decal_") or key in ["sign0", "sign1", "barrel0", "barrel1", "rock0", "rock1",
			"crystal_big0", "crystal_big1", "pillar0", "pillar1", "statue0", "tree0", "tree1", "tree2",
			"mushroom0", "mushroom1", "wreck0", "wreck1"]:
		_paint_env(key, b, e)
		return
	if key.begins_with("villager_"):
		_paint_villager(b, e, f, int(key.substr(9)))
		return
	if key.begins_with("citizen_"):
		_paint_hero_rig(key, b, e, f)
		_citizen_extras(b, e, look(key), f)
		_hero_detail(b, e, look(key))
		return
	if key in HERO_KEYS:
		_paint_hero48(key, b, e, f)
		return
	if key in BEAST_KEYS:
		_paint_beast(key, b, e, f)
		return
	if key in BOSS_KEYS:
		_paint_boss(key, b, e, f)
		return
	match key:
		"hero":
			_paint_hero(b, e, f)
		"rin":
			_paint_rin(b, e, f)
		"bram":
			_paint_bram(b, e, f)
		"kira":
			_paint_kira(b, e, f)
		"lich":
			_paint_lich(b, e, f)
		"skyla", "orm", "mora", "zephyr", "iris", "kai":
			_paint_hero2(key, b, e, f)
		"goblin", "slime", "slimelet", "spider", "spiderling", "caster", "bomber", "knight":
			_paint_mob2(key, b, e, f)
		"omega":
			_paint_omega(b, e, f)
		"arrow":
			line(e, 1, 2, 13, 2, Color(0.6, 1.0, 0.85))
			poly(e, PackedVector2Array([Vector2(12, 0), Vector2(16, 2.5), Vector2(12, 5)]), Color(1, 1, 1))
			line(b, 0, 1, 3, 1, Color(0.3, 0.8, 0.6))
			line(b, 0, 3, 3, 3, Color(0.3, 0.8, 0.6))
		"spirit":
			var c := Color(0.75, 0.6, 1.0)
			ellipse(e, 5.5, 5, 4, 4, Color(c, 0.85))
			poly(e, PackedVector2Array([Vector2(1.5, 5), Vector2(9.5, 5), Vector2(7 + f, 12), Vector2(5, 9), Vector2(3 - f, 12)]), Color(c, 0.7))
			px(e, 4, 4, Color(0.1, 0.05, 0.2))
			px(e, 7, 4, Color(0.1, 0.05, 0.2))
		"shuriken":
			var c := Color(0.85, 0.88, 0.95)
			if f == 0:
				poly(b, PackedVector2Array([Vector2(5.5, 0), Vector2(7, 4), Vector2(11, 5.5), Vector2(7, 7), Vector2(5.5, 11), Vector2(4, 7), Vector2(0, 5.5), Vector2(4, 4)]), c)
			else:
				poly(b, PackedVector2Array([Vector2(1.5, 1.5), Vector2(6.5, 4), Vector2(9.5, 1.5), Vector2(7, 6.5), Vector2(9.5, 9.5), Vector2(4.5, 7), Vector2(1.5, 9.5), Vector2(4, 4.5)]), c)
			ellipse(e, 5.5, 5.5, 1.3, 1.3, Color(1.0, 0.35, 0.35))
		"flaskp":
			rect(b, 3, 0, 2, 3, Color(0.6, 0.45, 0.3))
			ellipse(b, 3.5, 6, 3.2, 3.5, Color(0.5, 0.7, 0.4, 0.9))
			ellipse(e, 3.5, 6.5, 2, 2.2, Color(0.6, 1.0, 0.3))
		"colossus":
			_paint_colossus(b, e, f)
		"queen":
			_paint_queen(b, e, f)
		"chest":
			_paint_chest(b, e, f)
		"drone":
			_paint_drone(b, e, f)
		"sword":
			poly(e, PackedVector2Array([Vector2(4.5, 1), Vector2(6.5, 4), Vector2(6, 15), Vector2(3, 15), Vector2(2.5, 4)]), Color(1.0, 0.3, 0.75))
			line(e, 4, 3, 4, 14, Color(1.0, 0.85, 1.0))
			rect(b, 1, 15, 7, 1, Color(0.85, 0.65, 0.3))
			rect(b, 4, 16, 1, 3, Color(0.4, 0.3, 0.3))
		"shard":
			poly(e, PackedVector2Array([Vector2(0, 2.5), Vector2(3, 0.5), Vector2(9, 2.5), Vector2(3, 4.5)]), Color(0.6, 0.95, 1.0))
			line(e, 3, 2, 8, 2, Color(1, 1, 1))
		"imp":
			_paint_imp(b, e, f)
		"bat":
			_paint_bat(b, e, f)
		"ghoul":
			_paint_ghoul(b, e, f)
		"wraith":
			_paint_wraith(b, e, f)
		"brute":
			_paint_brute(b, e, f)
		"gem1":
			_paint_gem(b, e, Color(0.25, 0.6, 1.0))
		"gem3":
			_paint_gem(b, e, Color(0.3, 1.0, 0.55))
		"gem5":
			_paint_gem(b, e, Color(1.0, 0.75, 0.25))
		"gemx":
			# Мега-кристалл: крупная огранённая друза, алая с золотом
			poly(b, PackedVector2Array([Vector2(9.5, 0), Vector2(18, 7), Vector2(15, 18), Vector2(9.5, 22), Vector2(4, 18), Vector2(1, 7)]), Color(0.85, 0.12, 0.25))
			poly(b, PackedVector2Array([Vector2(9.5, 2), Vector2(15, 7), Vector2(9.5, 19), Vector2(4, 7)]), Color(1.0, 0.3, 0.4))
			line(b, 1, 7, 18, 7, Color(1.0, 0.75, 0.4))
			line(b, 9, 1, 9, 21, Color(1.0, 0.55, 0.5))
			rect(e, 9, 4, 1, 12, Color(1.0, 0.85, 0.6))
			rect(e, 6, 7, 7, 1, Color(1.0, 0.8, 0.5))
			px(e, 6, 5, Color(1, 1, 1))
			px(e, 13, 5, Color(1, 1, 1))
			px(e, 9, 10, Color(1, 1, 1))
		"gem9":
			# Красный — самый крупный, с огранкой
			poly(b, PackedVector2Array([Vector2(6.5, 0), Vector2(12, 5), Vector2(6.5, 14), Vector2(1, 5)]), Color(1.0, 0.2, 0.3).darkened(0.2))
			line(b, 2, 5, 11, 5, Color(1.0, 0.5, 0.55))
			line(b, 6, 1, 6, 12, Color(1.0, 0.35, 0.4))
			rect(e, 6, 3, 1, 7, Color(1.0, 0.7, 0.75))
			px(e, 4, 4, Color(1, 1, 1))
			px(e, 8, 4, Color(1, 1, 1))
		"res_scrap", "res_chips", "res_cores":
			_paint_res(key, b, e)
		"heal":
			_paint_heart(b, e)
		"orb":
			ellipse(e, 4.5, 4.5, 3.6, 3.6, Color(0.25, 0.75, 1.0))
			ellipse(e, 4.5, 4.5, 2.2, 2.2, Color(0.8, 1.0, 1.0))
		"blade":
			poly(e, PackedVector2Array([Vector2(1, 3.5), Vector2(4, 1), Vector2(17.5, 3.5), Vector2(4, 6)]), Color(1.0, 0.25, 0.75))
			line(e, 4, 3, 16, 3, Color(1.0, 0.85, 1.0))
			rect(b, 0, 2, 2, 3, Color(0.8, 0.65, 0.3))
		"lamp0", "lamp1":
			_paint_lamp(b, e, Color(0.2, 0.95, 1.0) if key == "lamp0" else Color(1.0, 0.25, 0.75))
		"obelisk0", "obelisk1", "obelisk2":
			_paint_obelisk(b, e, int(key.right(1)))
		"crystal0", "crystal1":
			_paint_crystal(b, e, int(key.right(1)))
		"crate0", "crate1":
			_paint_crate(b, e, int(key.right(1)))
		"puddle0", "puddle1":
			ellipse(b, 14, 6, 12.5, 4.5, Color(0.06, 0.08, 0.15, 0.9))
			ellipse(b, 14, 6, 10, 3, Color(0.08, 0.11, 0.2, 0.9))
			var c1 := Color(0.2, 0.9, 1.0, 0.55) if key == "puddle0" else Color(1.0, 0.3, 0.8, 0.55)
			line(e, 7, 5, 12, 5, c1)
			line(e, 15, 7, 21, 7, Color(c1, 0.35))
			px(e, 18, 4, Color(1, 1, 1, 0.5))


# ---------- Герой: техномаг в капюшоне с посохом ----------

static func _paint_hero(b: Image, e: Image, f: int) -> void:
	var walk := f >= 4
	var k := f % 4
	var oy: int = ([0, 1, 0, 1] if walk else [0, 0, 1, 1])[k]
	var step: int = ([1, 0, -1, 0] if walk else [0, 0, 0, 0])[k]
	var fl: int = ([0, 1, 0, -1] if walk else [0, 0, 1, 0])[k]

	var boot := Color(0.1, 0.09, 0.17)
	var cloak := Color(0.17, 0.21, 0.5)
	var cloak2 := Color(0.25, 0.32, 0.66)
	var hood := Color(0.32, 0.18, 0.55)
	var metal := Color(0.45, 0.48, 0.64)
	var gold := Color(0.9, 0.68, 0.27)
	var neon_m := Color(1.0, 0.25, 0.72)
	var neon_c := Color(0.3, 1.0, 1.0)

	# Ноги
	var la := 3 if walk and k == 0 else 4
	var lb := 3 if walk and k == 2 else 4
	rect(b, 8 + step, 21 + (4 - la), 2, la, boot)
	rect(b, 12 - step, 21 + (4 - lb), 2, lb, boot)
	px(b, 9 + step, 24, metal)
	px(b, 13 - step, 24, metal)

	# Плащ
	poly(b, PackedVector2Array([Vector2(8, 11 + oy), Vector2(15, 11 + oy),
		Vector2(17.5, 22.5 + fl), Vector2(4.5, 22.5 - fl)]), cloak)
	line(b, 11, 13 + oy, 10, 21, cloak2)
	line(b, 12, 13 + oy, 12, 21, cloak2)
	rect(b, 8, 16 + oy, 8, 1, gold)
	# Неоновая кайма плаща
	line(e, 15, 12 + oy, 17, 22 + fl, neon_m)
	line(e, 5, 22 - fl, 17, 22 + fl, Color(neon_m, 0.85))
	if k % 2 == 0:
		px(e, 9, 19 + oy, Color(neon_c, 0.9))
		px(e, 10, 19 + oy, Color(neon_c, 0.6))

	# Наплечник и рука
	ellipse(b, 10, 12 + oy, 3.2, 1.8, metal)
	rect(b, 15, 14 + oy, 2, 3, cloak)
	rect(b, 16, 16 + oy, 2, 2, Color(0.22, 0.16, 0.24))

	# Капюшон и тёмное лицо
	poly(b, PackedVector2Array([Vector2(7, 7 + oy), Vector2(4.5, 12 + oy), Vector2(9, 10 + oy)]), hood)
	ellipse(b, 11.5, 8.5 + oy, 5, 5, hood)
	ellipse(b, 13.2, 9.5 + oy, 2.7, 2.5, Color(0.05, 0.03, 0.1))
	# Визор
	rect(e, 12, 9 + oy, 4, 1, neon_c)
	px(e, 15, 9 + oy, Color(1, 1, 1))

	# Посох и кристалл
	line(b, 18, 7 + oy, 18, 25, metal)
	px(b, 17, 6 + oy, metal)
	px(b, 19, 6 + oy, metal)
	var cb: int = [0, -1, -1, 0][k]
	ellipse(e, 18.5, 4 + oy + cb, 1.6, 2.3, Color(0.75, 0.4, 1.0))
	px(e, 18, 4 + oy + cb, Color(1, 0.9, 1))


# ---------- Рин: кибер-самурай ----------

static func _hero_pose(f: int) -> Dictionary:
	var walk := f >= 4
	var k := f % 4
	return {
		"walk": walk, "k": k,
		"oy": ([0, 1, 0, 1] if walk else [0, 0, 1, 1])[k],
		"step": ([1, 0, -1, 0] if walk else [0, 0, 0, 0])[k],
		"fl": ([0, 1, 0, -1] if walk else [0, 0, 1, 0])[k],
	}


static func _legs(b: Image, pose: Dictionary, x1: int, x2: int, y: int, c: Color, w := 2) -> void:
	var step: int = pose["step"]
	var k: int = pose["k"]
	var la := 3 if pose["walk"] and k == 0 else 4
	var lb := 3 if pose["walk"] and k == 2 else 4
	rect(b, x1 + step, y + (4 - la), w, la, c)
	rect(b, x2 - step, y + (4 - lb), w, lb, c)


static func _paint_rin(b: Image, e: Image, f: int) -> void:
	var p := _hero_pose(f)
	var oy: int = p["oy"]
	var fl: int = p["fl"]
	var armor := Color(0.16, 0.14, 0.22)
	var plate := Color(0.42, 0.4, 0.5)
	var red := Color(0.75, 0.1, 0.25)
	var neon := Color(1.0, 0.25, 0.6)
	_legs(b, p, 8, 12, 21, Color(0.12, 0.1, 0.16))
	# Шарф развевается
	poly(b, PackedVector2Array([Vector2(8, 11 + oy), Vector2(3, 12 + oy + fl), Vector2(2, 15 + oy - fl), Vector2(8, 13 + oy)]), red)
	# Корпус с пластинами
	poly(b, PackedVector2Array([Vector2(8, 11 + oy), Vector2(15, 11 + oy), Vector2(15.5, 21.5), Vector2(7.5, 21.5)]), armor)
	rect(b, 8, 13 + oy, 7, 2, plate)
	rect(b, 8, 18, 3, 3, plate.darkened(0.2))
	rect(b, 12, 18, 3, 3, plate.darkened(0.2))
	rect(b, 8, 16 + oy, 7, 1, red)
	line(e, 9, 15 + oy, 14, 15 + oy, Color(neon, 0.8))
	# Катана за спиной
	line(b, 5, 21, 13, 6 + oy, Color(0.7, 0.72, 0.8))
	rect(b, 4, 21, 2, 2, Color(0.8, 0.6, 0.25))
	# Шлем
	ellipse(b, 11.5, 8 + oy, 4.6, 4.4, armor.lightened(0.1))
	rect(b, 7, 4 + oy, 9, 2, plate)
	poly(b, PackedVector2Array([Vector2(13, 4 + oy), Vector2(17, 1 + oy), Vector2(15, 5 + oy)]), red)
	rect(e, 11, 8 + oy, 5, 1, neon)
	px(e, 15, 8 + oy, Color(1, 0.8, 0.9))
	# Рука
	rect(b, 15, 13 + oy, 2, 4, armor)
	px(b, 16, 17 + oy, plate)


# ---------- Брам: рунный кузнец ----------

static func _paint_bram(b: Image, e: Image, f: int) -> void:
	var p := _hero_pose(f)
	var oy: int = p["oy"]
	var k: int = p["k"]
	var iron := Color(0.36, 0.34, 0.4)
	var leather := Color(0.35, 0.22, 0.14)
	var beard := Color(0.75, 0.4, 0.15)
	var rune := Color(1.0, 0.7, 0.2)
	var ice := Color(0.5, 0.95, 1.0)
	_legs(b, p, 7, 13, 22, Color(0.2, 0.15, 0.12), 3)
	# Широкий корпус
	ellipse(b, 11.5, 16 + oy, 7, 6.5, iron)
	rect(b, 6, 18 + oy, 12, 4, leather)
	rect(b, 6, 19 + oy, 12, 1, Color(0.8, 0.6, 0.25))
	ellipse(b, 5.5, 12 + oy, 3, 2.5, iron.lightened(0.1))
	ellipse(b, 17.5, 12 + oy, 3, 2.5, iron.lightened(0.1))
	line(e, 10, 14 + oy, 13, 17 + oy, rune)
	line(e, 13, 14 + oy, 10, 17 + oy, rune)
	# Голова, шлем, борода
	ellipse(b, 12, 8 + oy, 4.2, 4, Color(0.85, 0.65, 0.5))
	ellipse(b, 12, 5.5 + oy, 4.8, 3, iron)
	rect(b, 7, 6 + oy, 10, 1, iron.darkened(0.3))
	poly(b, PackedVector2Array([Vector2(8, 9 + oy), Vector2(16, 9 + oy), Vector2(14, 15 + oy), Vector2(12, 16 + oy), Vector2(10, 15 + oy)]), beard)
	px(e, 10, 8 + oy, rune)
	px(e, 14, 8 + oy, rune)
	# Молот с ледяным бойком
	var hy: int = [0, 0, -1, -1][k]
	line(b, 20, 9 + oy + hy, 20, 22, Color(0.45, 0.3, 0.2))
	rect(b, 17, 5 + oy + hy, 7, 5, iron)
	rect(e, 18, 6 + oy + hy, 5, 1, ice)
	px(e, 18, 8 + oy + hy, ice)
	px(e, 22, 8 + oy + hy, ice)


# ---------- Кира: ведьма сети ----------

static func _paint_kira(b: Image, e: Image, f: int) -> void:
	var p := _hero_pose(f)
	var oy: int = p["oy"]
	var fl: int = p["fl"]
	var k: int = p["k"]
	var dress := Color(0.12, 0.22, 0.18)
	var hat := Color(0.1, 0.12, 0.16)
	var hair := Color(0.55, 0.2, 0.6)
	var neon := Color(0.35, 1.0, 0.5)
	_legs(b, p, 9, 12, 23, Color(0.08, 0.08, 0.12))
	# Волосы за спиной
	poly(b, PackedVector2Array([Vector2(7, 9 + oy), Vector2(5, 18 + oy + fl), Vector2(9, 16 + oy)]), hair)
	# Платье-плащ
	poly(b, PackedVector2Array([Vector2(8, 13 + oy), Vector2(14, 13 + oy), Vector2(17, 24 + fl), Vector2(5, 24 - fl)]), dress)
	line(e, 6, 23 - fl, 16, 23 + fl, neon)
	for y in range(15, 22, 3):
		px(e, 11, y + oy, Color(neon, 0.8))
		px(e, 12, y + oy + 1, Color(neon, 0.6))
	# Лицо и волосы
	ellipse(b, 11.5, 11 + oy, 3.4, 3.2, Color(0.9, 0.75, 0.7))
	rect(b, 8, 9 + oy, 7, 2, hair)
	rect(e, 11, 11 + oy, 1, 1, neon)
	rect(e, 13, 11 + oy, 1, 1, neon)
	# Шляпа ведьмы с неоновой лентой
	rect(b, 5, 8 + oy, 14, 2, hat)
	poly(b, PackedVector2Array([Vector2(8, 8 + oy), Vector2(15, 8 + oy), Vector2(13, 2 + oy), Vector2(10 + fl, 0.5 + oy)]), hat)
	rect(e, 8, 7 + oy, 7, 1, Color(1.0, 0.3, 0.8))
	# Парящий голо-кристалл в руке
	var cb: int = [0, -1, -1, 0][k]
	rect(b, 15, 15 + oy, 2, 3, dress)
	ellipse(e, 18.5, 14 + oy + cb, 1.6, 1.6, neon)
	px(e, 18, 14 + oy + cb, Color(1, 1, 1))


# ---------- Боссы ----------

static func _paint_lich(b: Image, e: Image, f: int) -> void:
	var bob: int = [0, -1, -1, 0][f]
	var robe := Color(0.18, 0.1, 0.3)
	var bone := Color(0.85, 0.85, 0.8)
	var neon := Color(0.6, 0.4, 1.0)
	var cyan := Color(0.3, 1.0, 1.0)
	var pts := PackedVector2Array([Vector2(12, 14 + bob), Vector2(28, 14 + bob)])
	var x := 32.0
	while x >= 8.0:
		pts.append(Vector2(x, 41.0 + sin(x * 0.7 + f * 1.5) * 2.0 + bob))
		x -= 3.0
	poly(b, pts, robe)
	line(b, 20, 18 + bob, 20, 40 + bob, robe.lightened(0.15))
	for y in range(20, 40, 5):
		px(e, 20, y + bob, neon)
		px(e, 16, y + 2 + bob, Color(neon, 0.6))
		px(e, 24, y + 2 + bob, Color(neon, 0.6))
	# Руки-кости, парящие
	line(b, 10, 18 + bob, 4, 24 + bob - f % 2, bone)
	line(b, 30, 18 + bob, 36, 24 + bob - (f + 1) % 2, bone)
	ellipse(e, 4, 26 + bob, 2, 2, Color(neon, 0.9))
	ellipse(e, 36, 26 + bob, 2, 2, Color(neon, 0.9))
	# Череп
	ellipse(b, 20, 10 + bob, 6, 6, bone)
	rect(b, 16, 14 + bob, 8, 3, bone.darkened(0.15))
	ellipse(b, 17.5, 10 + bob, 1.8, 2, Color(0.05, 0.02, 0.08))
	ellipse(b, 22.5, 10 + bob, 1.8, 2, Color(0.05, 0.02, 0.08))
	px(e, 17, 10 + bob, cyan)
	px(e, 22, 10 + bob, cyan)
	# Корона из осколков данных
	for i in 5:
		var cx := 14 + i * 3
		var hgt: int = [3, 5, 7, 5, 3][i]
		line(e, cx, 4 + bob, cx, 4 + bob - hgt + (f + i) % 2, cyan if i % 2 == 0 else neon)


static func _paint_colossus(b: Image, e: Image, f: int) -> void:
	var bob: int = [0, 1, 0, 1][f]
	var step: int = [2, 0, -2, 0][f]
	var steel := Color(0.4, 0.38, 0.44)
	var dark := Color(0.2, 0.18, 0.24)
	var hot := Color(1.0, 0.5, 0.12)
	rect(b, 15 + step, 34, 7, 10, dark)
	rect(b, 28 - step, 34, 7, 10, dark)
	rect(b, 13 + step, 42, 10, 3, steel)
	rect(b, 27 - step, 42, 10, 3, steel)
	rect(b, 12, 14 + bob, 26, 21, steel)
	rect(b, 14, 30 + bob, 22, 5, dark)
	ellipse(b, 9, 15 + bob, 7, 6, steel.lightened(0.08))
	ellipse(b, 41, 15 + bob, 7, 6, steel.lightened(0.08))
	rect(b, 3, 18 + bob, 8, 16, steel.darkened(0.1))
	rect(b, 39, 18 + bob, 8, 16, steel.darkened(0.1))
	rect(b, 2, 33 + bob, 10, 6, dark)
	rect(b, 38, 33 + bob, 10, 6, dark)
	# Голова-кабина
	rect(b, 19, 6 + bob, 12, 9, dark)
	rect(e, 21, 9 + bob, 8, 2, hot)
	px(e, 25, 9 + bob, Color(1, 1, 0.8))
	# Реактор в груди
	ellipse(e, 25, 22 + bob, 4.5, 4.5, hot)
	ellipse(e, 25, 22 + bob, 2.2, 2.2, Color(1, 0.95, 0.7))
	for i in 3:
		px(e, 15 + i * 2, 31 + bob, hot)
		px(e, 31 + i * 2, 31 + bob, hot)
	line(b, 13, 16 + bob, 18, 28 + bob, dark)
	line(b, 37, 16 + bob, 32, 28 + bob, dark)
	if f % 2 == 0:
		px(e, 7, 12 + bob, Color(1.0, 0.2, 0.2))
		px(e, 43, 12 + bob, Color(1.0, 0.2, 0.2))


static func _paint_queen(b: Image, e: Image, f: int) -> void:
	var tip: int = [2, 8, 14, 8][f]
	var chitin := Color(0.28, 0.08, 0.22)
	var wing := Color(0.5, 0.2, 0.6, 0.85)
	var neon := Color(1.0, 0.3, 0.75)
	var gold := Color(1.0, 0.8, 0.3)
	poly(b, PackedVector2Array([Vector2(22, 16), Vector2(2, tip), Vector2(6, 22), Vector2(14, 24), Vector2(22, 22)]), wing)
	poly(b, PackedVector2Array([Vector2(30, 16), Vector2(50, tip), Vector2(46, 22), Vector2(38, 24), Vector2(30, 22)]), wing)
	line(e, 22, 18, 4, tip + 2, Color(neon, 0.8))
	line(e, 30, 18, 48, tip + 2, Color(neon, 0.8))
	# Брюшко
	ellipse(b, 26, 31, 6, 9, chitin)
	for y in [27, 31, 35]:
		line(e, 22, y, 30, y, Color(neon, 0.7))
	# Грудь и голова
	ellipse(b, 26, 18, 6, 5, chitin.lightened(0.1))
	ellipse(b, 26, 10, 5, 4.5, chitin.lightened(0.15))
	ellipse(e, 23.5, 10, 1.8, 1.4, neon)
	ellipse(e, 28.5, 10, 1.8, 1.4, neon)
	# Корона
	for i in 3:
		line(e, 23 + i * 3, 6, 23 + i * 3, 3 - (i % 2) * 2, gold)
	# Лапки
	for i in 3:
		line(b, 21, 17 + i * 3, 15, 21 + i * 4, chitin)
		line(b, 31, 17 + i * 3, 37, 21 + i * 4, chitin)


static func _paint_chest(b: Image, e: Image, f: int) -> void:
	var metal := Color(0.3, 0.3, 0.4)
	var trim := Color(0.85, 0.65, 0.25)
	var neon := Color(1.0, 0.75, 0.3)
	rect(b, 2, 7, 14, 8, metal)
	rect(b, 2, 7, 14, 1, trim)
	rect(b, 2, 14, 14, 1, trim)
	rect(b, 2, 7, 1, 8, trim)
	rect(b, 15, 7, 1, 8, trim)
	if f == 0:
		rect(b, 2, 3, 14, 4, metal.lightened(0.1))
		rect(b, 2, 3, 14, 1, trim)
		rect(e, 8, 6, 2, 3, neon)
		line(e, 4, 11, 13, 11, Color(0.3, 0.9, 1.0, 0.8))
	else:
		rect(b, 2, 1, 14, 3, metal.lightened(0.1))
		rect(e, 3, 6, 12, 2, Color(1.0, 0.95, 0.6))
		line(e, 4, 11, 13, 11, Color(0.3, 0.9, 1.0, 0.8))


# ---------- Бес-дрон ----------

static func _paint_imp(b: Image, e: Image, f: int) -> void:
	var bob: int = [0, -1, -1, 0][f]
	var body := Color(0.48, 0.12, 0.25)
	var horn := Color(0.24, 0.06, 0.14)
	poly(b, PackedVector2Array([Vector2(5, 8 + bob), Vector2(3, 2 + bob), Vector2(8, 5 + bob)]), horn)
	poly(b, PackedVector2Array([Vector2(13, 8 + bob), Vector2(15, 2 + bob), Vector2(10, 5 + bob)]), horn)
	ellipse(b, 9, 10 + bob, 5.5, 5, body)
	ellipse(b, 9, 13 + bob, 3, 1.6, Color(0.38, 0.36, 0.48))
	line(b, 4, 11 + bob, 2, 14 + bob, horn)
	line(b, 14, 11 + bob, 16, 14 + bob, horn)
	ellipse(b, 10, 9 + bob, 2.2, 2.2, Color(0.05, 0.02, 0.05))
	ellipse(e, 10, 9 + bob, 1.6, 1.6, Color(1.0, 0.3, 0.1))
	px(e, 10, 8 + bob, Color(1.0, 0.95, 0.6))
	rect(b, 7, 15 + bob, 1, 1, Color(0.25, 0.25, 0.3))
	rect(b, 11, 15 + bob, 1, 1, Color(0.25, 0.25, 0.3))
	var flame: int = [2, 3, 2, 1][f]
	for i in flame:
		var fc := Color(1.0, 0.9, 0.4) if i == 0 else Color(1.0, 0.45, 0.1, 0.8)
		px(e, 7, 16 + bob + i, fc)
		px(e, 11, 16 + bob + i, fc)


# ---------- Неоновый нетопырь ----------

static func _paint_bat(b: Image, e: Image, f: int) -> void:
	var tip: int = [2, 6, 11, 6][f]
	var wing := Color(0.32, 0.14, 0.5)
	poly(b, PackedVector2Array([Vector2(11, 7), Vector2(2, tip), Vector2(4, 11), Vector2(7, 10), Vector2(10, 11.5)]), wing)
	poly(b, PackedVector2Array([Vector2(15, 7), Vector2(24, tip), Vector2(22, 11), Vector2(19, 10), Vector2(16, 11.5)]), wing)
	ellipse(b, 13, 8.5, 3.2, 3.6, Color(0.2, 0.1, 0.3))
	px(b, 11, 4, Color(0.2, 0.1, 0.3))
	px(b, 15, 4, Color(0.2, 0.1, 0.3))
	px(b, 12, 11, Color(0.95, 0.95, 0.95))
	px(b, 14, 11, Color(0.95, 0.95, 0.95))
	var vein := Color(0.95, 0.3, 1.0, 0.9)
	line(e, 10, 8, 3, tip + 1, vein)
	line(e, 16, 8, 23, tip + 1, vein)
	px(e, 12, 7, Color(1.0, 0.4, 0.8))
	px(e, 14, 7, Color(1.0, 0.4, 0.8))


# ---------- Кибер-упырь ----------

static func _paint_ghoul(b: Image, e: Image, f: int) -> void:
	var bob: int = [0, 1, 0, 1][f]
	var step: int = [1, 0, -1, 0][f]
	var skin := Color(0.3, 0.44, 0.3)
	var metal := Color(0.46, 0.48, 0.58)
	var neon := Color(0.4, 1.0, 0.45)
	rect(b, 7 + step, 19, 2, 5, Color(0.2, 0.28, 0.22))
	rect(b, 11 - step, 19, 2, 5, Color(0.2, 0.28, 0.22))
	line(b, 7, 12 + bob, 4, 20 + bob, skin)
	line(b, 8, 12 + bob, 5, 20 + bob, skin)
	ellipse(b, 9.5, 14 + bob, 5, 5.5, skin)
	line(b, 7, 13 + bob, 10, 13 + bob, skin.darkened(0.35))
	line(b, 7, 15 + bob, 10, 15 + bob, skin.darkened(0.35))
	ellipse(b, 13, 8 + bob, 3.6, 3.3, Color(0.4, 0.53, 0.38))
	rect(b, 13, 10 + bob, 3, 1, Color(0.12, 0.06, 0.08))
	px(b, 14, 10 + bob, Color(0.9, 0.9, 0.8))
	rect(b, 13, 13 + bob, 2, 6, metal)
	px(b, 12, 19 + bob, metal)
	px(b, 15, 19 + bob, metal)
	px(b, 14, 20 + bob, metal)
	line(e, 14, 14 + bob, 14, 18 + bob, neon)
	px(e, 14, 7 + bob, neon)
	px(e, 15, 7 + bob, Color(0.85, 1.0, 0.85))
	px(e, 6, 11 + bob, Color(neon, 0.8))
	px(e, 6, 14 + bob, Color(neon, 0.8))


# ---------- Глитч-призрак (голограмма) ----------

static func _paint_wraith(b: Image, e: Image, f: int) -> void:
	var body := Color(0.18, 0.36, 0.56)
	var pts := PackedVector2Array([Vector2(5, 9), Vector2(10, 2), Vector2(15, 9), Vector2(16, 17)])
	var x := 16.0
	while x >= 4.0:
		pts.append(Vector2(x, 21.0 + sin(x * 0.9 + f * 1.6) * 2.0))
		x -= 2.0
	pts.append(Vector2(4, 17))
	poly(b, pts, body)
	ellipse(b, 10, 8, 3, 2.5, Color(0.04, 0.06, 0.12))
	px(e, 9, 8, Color(0.85, 1.0, 1.0))
	px(e, 11, 8, Color(0.85, 1.0, 1.0))
	for y in range(3, 25, 2):
		for xx in b.get_width():
			if b.get_pixel(xx, y).a > 0.5 and e.get_pixel(xx, y).a < 0.5:
				px(e, xx, y, Color(0.3, 0.9, 1.0, 0.35))
	# Глитч: сдвигаем пару строк
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + f * 13
	for i in 2:
		var row := rng.randi_range(4, 21)
		var dx := rng.randi_range(-2, 2)
		for im in [b, e]:
			var src := (im as Image).duplicate() as Image
			for xx in im.get_width():
				var sx: int = xx - dx
				var c: Color = src.get_pixel(sx, row) if sx >= 0 and sx < im.get_width() else Color(0, 0, 0, 0)
				(im as Image).set_pixel(xx, row, c)


# ---------- Рунный голем (элита) ----------

static func _paint_brute(b: Image, e: Image, f: int) -> void:
	var bob: int = [0, 1, 0, 1][f]
	var step: int = [1, 0, -1, 0][f]
	var stone := Color(0.38, 0.34, 0.42)
	var dark := Color(0.18, 0.16, 0.22)
	var rune := Color(1.0, 0.55, 0.1)
	rect(b, 11 + step, 28, 5, 8, stone.darkened(0.15))
	rect(b, 20 - step, 28, 5, 8, stone.darkened(0.15))
	ellipse(b, 18, 21 + bob, 10, 9, stone)
	rect(b, 4, 17 + bob, 6, 10, stone)
	rect(b, 26, 17 + bob, 6, 10, stone)
	ellipse(b, 8, 15 + bob, 5, 4.5, stone.lightened(0.05))
	ellipse(b, 28, 15 + bob, 5, 4.5, stone.lightened(0.05))
	ellipse(b, 7, 28 + bob, 3.6, 3, stone.darkened(0.1))
	ellipse(b, 29, 28 + bob, 3.6, 3, stone.darkened(0.1))
	ellipse(b, 18, 10 + bob, 5, 4, stone.darkened(0.08))
	rect(b, 13, 8 + bob, 10, 1, dark)
	line(b, 12, 19 + bob, 14, 25 + bob, dark)
	line(b, 24, 18 + bob, 22, 24 + bob, dark)
	rect(e, 15, 10 + bob, 2, 1, rune)
	rect(e, 20, 10 + bob, 2, 1, rune)
	line(e, 18, 15 + bob, 18, 25 + bob, rune)
	line(e, 15, 17 + bob, 21, 22 + bob, Color(rune, 0.85))
	line(e, 21, 17 + bob, 15, 22 + bob, Color(rune, 0.85))
	for y in [20, 23]:
		px(e, 6, y + bob, rune)
		px(e, 29, y + bob, rune)


# ---------- Кристаллы опыта и сердце ----------

static func _paint_gem(b: Image, e: Image, c: Color) -> void:
	poly(b, PackedVector2Array([Vector2(5.5, 1), Vector2(10, 5), Vector2(5.5, 12), Vector2(1, 5)]), c.darkened(0.2))
	line(b, 2, 5, 9, 5, c.lightened(0.2))
	rect(e, 5, 4, 1, 5, c.lightened(0.45))
	px(e, 4, 4, Color(1, 1, 1))


## Материалы для базы: шестерёнка-лом, микросхема, ядро.
static func _paint_res(key: String, b: Image, e: Image) -> void:
	match key:
		"res_scrap":
			var c := Color(0.62, 0.62, 0.72)
			for i in 8:
				var a := TAU * i / 8.0
				rect(b, int(6 + cos(a) * 5.0), int(6 + sin(a) * 5.0), 2, 2, c.darkened(0.15))
			ellipse(b, 6.5, 6.5, 4.2, 4.2, c)
			ellipse(b, 6.5, 6.5, 1.6, 1.6, Color(0.15, 0.13, 0.2))
			px(e, 4, 4, Color(1, 1, 1, 0.9))
			line(e, 9, 3, 10, 4, Color(1.0, 0.8, 0.4, 0.8))
		"res_chips":
			rect(b, 2, 3, 9, 7, Color(0.1, 0.25, 0.16))
			for i in 4:
				px(b, 3 + i * 2, 1, Color(0.8, 0.75, 0.5))
				px(b, 3 + i * 2, 2, Color(0.8, 0.75, 0.5))
				px(b, 3 + i * 2, 10, Color(0.8, 0.75, 0.5))
				px(b, 3 + i * 2, 11, Color(0.8, 0.75, 0.5))
			rect(b, 4, 5, 5, 3, Color(0.15, 0.15, 0.2))
			line(e, 3, 4, 9, 4, Color(0.35, 1.0, 0.6))
			px(e, 6, 6, Color(0.6, 1.0, 0.8))
			px(e, 9, 8, Color(0.35, 1.0, 0.6))
		"res_cores":
			ellipse(b, 6.5, 6.5, 5.0, 5.0, Color(0.35, 0.1, 0.4))
			ellipse(e, 6.5, 6.5, 3.4, 3.4, Color(1.0, 0.4, 0.9))
			ellipse(e, 6.0, 6.0, 1.5, 1.5, Color(1, 0.9, 1))
			px(e, 6, 0, Color(1.0, 0.5, 0.9, 0.8))
			px(e, 6, 12, Color(1.0, 0.5, 0.9, 0.8))
			px(e, 0, 6, Color(1.0, 0.5, 0.9, 0.8))
			px(e, 12, 6, Color(1.0, 0.5, 0.9, 0.8))


static func _paint_heart(b: Image, e: Image) -> void:
	var c := Color(0.9, 0.12, 0.3)
	ellipse(b, 3.5, 4, 2.6, 2.6, c)
	ellipse(b, 7.5, 4, 2.6, 2.6, c)
	poly(b, PackedVector2Array([Vector2(1, 5), Vector2(10, 5), Vector2(5.5, 10)]), c)
	px(e, 3, 3, Color(1, 0.8, 0.85))
	line(e, 3, 6, 7, 6, Color(1.0, 0.4, 0.6, 0.8))


# ---------- Окружение ----------

static func _paint_lamp(b: Image, e: Image, col: Color) -> void:
	var metal := Color(0.26, 0.27, 0.36)
	rect(b, 4, 10, 2, 31, metal)
	rect(b, 2, 40, 6, 3, metal.darkened(0.2))
	rect(b, 4, 8, 8, 2, metal)
	rect(b, 8, 9, 5, 3, metal.darkened(0.3))
	rect(e, 8, 12, 5, 1, col)
	px(e, 10, 13, Color(col, 0.6))
	for y in range(16, 38, 4):
		px(e, 5, y, Color(col, 0.7))


static func _paint_obelisk(b: Image, e: Image, v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + v
	var stone := Color(0.3, 0.28, 0.37)
	poly(b, PackedVector2Array([Vector2(4, 31), Vector2(12, 31), Vector2(11, 7),
		Vector2(9.5, 4 + rng.randi_range(0, 2)), Vector2(7, 6), Vector2(5, 5 + rng.randi_range(0, 3))]), stone)
	rect(b, 2, 30, 12, 3, stone.darkened(0.25))
	var col := [Color(0.7, 0.35, 1.0), Color(1.0, 0.5, 0.1), Color(0.3, 0.95, 1.0)][v % 3] as Color
	for y in range(9, 27, 5):
		for i in 3:
			for j in 3:
				if rng.randf() < 0.55:
					px(e, 7 + i, y + j, col)
	line(b, 5, 12, 6, 16, stone.darkened(0.4))


static func _paint_crystal(b: Image, e: Image, v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2000 + v
	var col := Color(0.3, 0.9, 1.0) if v == 0 else Color(0.75, 0.35, 1.0)
	ellipse(b, 10, 15, 8, 2.6, Color(0.2, 0.18, 0.25))
	for i in 4:
		var x := rng.randi_range(4, 15)
		var hgt := rng.randi_range(6, 12)
		var w := rng.randi_range(2, 3)
		poly(b, PackedVector2Array([Vector2(x - w, 15), Vector2(x + 0.5, 15 - hgt), Vector2(x + w + 1, 15)]), col.darkened(0.55))
		line(e, x, 16 - hgt, x, 14, col)
		px(e, x, 16 - hgt, Color(1, 1, 1))


static func _paint_crate(b: Image, e: Image, v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3000 + v
	rect(b, 2, 4, 14, 10, Color(0.24, 0.25, 0.33))
	rect(b, 2, 2, 14, 2, Color(0.33, 0.34, 0.44))
	for y in range(6, 12, 2):
		line(b, 4, y, 9, y, Color(0.12, 0.12, 0.17))
	var leds := [Color(0.3, 1.0, 0.4), Color(1.0, 0.25, 0.3), Color(0.3, 0.9, 1.0)]
	for i in 3:
		if rng.randf() < 0.75:
			px(e, 11 + i * 2, 6, leds[rng.randi_range(0, 2)])
	rect(e, 11, 9, 4, 2, Color(0.25, 0.9, 1.0, 0.8))


# ============ Земля ============

static func ground() -> Dictionary:
	if _cache.has("ground"):
		return _cache["ground"]
	var n := 128
	var b := blank(n, n)
	var e := blank(n, n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var slab_tone := {}
	for x in n:
		for y in n:
			var key := Vector2i(x / 16, y / 16)
			if not slab_tone.has(key):
				slab_tone[key] = rng.randf_range(-0.02, 0.025)
			var t: float = slab_tone[key] + rng.randf_range(-0.012, 0.012)
			var c := Color(0.115 + t, 0.105 + t, 0.155 + t)
			if x % 16 == 0 or y % 16 == 0:
				c = Color(0.06, 0.05, 0.09)
			elif x % 16 == 1 or y % 16 == 1:
				c = c.lightened(0.06)
			b.set_pixel(x, y, c)
	# Трещины
	for i in 28:
		var p := Vector2i(rng.randi_range(0, n - 1), rng.randi_range(0, n - 1))
		for s in rng.randi_range(5, 13):
			pxw(b, p.x, p.y, Color(0.05, 0.045, 0.08))
			p += Vector2i(rng.randi_range(-1, 1), rng.randi_range(0, 1))
	# Мох и мелкий мусор
	for i in 40:
		var p := Vector2i(rng.randi_range(0, n - 1), rng.randi_range(0, n - 1))
		for s in 4:
			pxw(b, p.x + rng.randi_range(-1, 1), p.y + rng.randi_range(-1, 1), Color(0.1, 0.17, 0.13))
	for i in 90:
		pxw(b, rng.randi_range(0, n - 1), rng.randi_range(0, n - 1), Color(0.2, 0.19, 0.25))
	# Неоновые дорожки-схемы
	for i in 9:
		var col := Color(0.2, 0.9, 1.0, 0.55) if rng.randf() < 0.6 else Color(1.0, 0.25, 0.75, 0.5)
		var p := Vector2i(rng.randi_range(0, 7) * 16 + 8, rng.randi_range(0, 7) * 16 + 8)
		var dir := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP][rng.randi_range(0, 3)] as Vector2i
		for s in rng.randi_range(20, 42):
			pxw(e, p.x, p.y, col)
			if rng.randf() < 0.12:
				dir = Vector2i(dir.y, dir.x) * (1 if rng.randf() < 0.5 else -1)
			p += dir
		pxw(e, p.x, p.y, Color(col, 1.0))
		pxw(e, p.x + 1, p.y, Color(col, 1.0))
		pxw(e, p.x, p.y + 1, Color(col, 1.0))
		pxw(e, p.x + 1, p.y + 1, Color(col, 1.0))
	# Руны на плитах
	for i in 7:
		var cx := rng.randi_range(0, 7) * 16 + 6
		var cy := rng.randi_range(0, 7) * 16 + 5
		for gx in 3:
			for gy in 5:
				if rng.randf() < 0.5:
					pxw(e, cx + gx, cy + gy, Color(0.7, 0.35, 1.0, 0.65))
	var result := {"base": tex(b), "emit": tex(e), "size": n}
	_cache["ground"] = result
	return result


# ============ Иконки для интерфейса ============

## Средний цвет непрозрачных пикселей иконки — «цвет» оружия.
static func _icon_color(im: Image) -> Color:
	var acc := Color(0, 0, 0, 0)
	var n := 0
	for y in im.get_height():
		for x in im.get_width():
			var c := im.get_pixel(x, y)
			if c.a > 0.5 and c.get_luminance() > 0.15:
				acc += c
				n += 1
	if n == 0:
		return Color(1, 1, 1)
	return Color(acc.r / n, acc.g / n, acc.b / n).lightened(0.15)


## Иконка слияния — своя для каждой пары и порядка (основа + второе оружие):
## неоновый ромб в цветах обоих, основа крупно в центре, второе — малой печатью
## в углу, золотые звёзды. «Голо-искры» и «Плазмо-клинки» выглядят по-разному.
static func fusion_icon(base: String, other: String) -> ImageTexture:
	var key := "ficon3_" + base + "+" + other
	if _cache.has(key):
		return _cache[key]
	var ib: Image = icon(base).get_image()
	var io: Image = icon(other).get_image()
	var cb := _icon_color(ib)
	var co := _icon_color(io)
	var n := 56
	var im := blank(n, n)
	var c0 := Vector2(27.5, 27.5)
	# Ромб: заливка — тёмная смесь, рамка — переход от цвета второго к цвету основы
	for y in n:
		for x in n:
			var d := absf(x - c0.x) + absf(y - c0.y)
			if d <= 27.0:
				var t := float(x + y) / float(2 * n)
				if d >= 24.0:
					im.set_pixel(x, y, co.lerp(cb, t).lightened(0.25 if d < 25.5 else 0.0))
				elif d >= 22.5:
					im.set_pixel(x, y, Color(0.05, 0.02, 0.1))
				else:
					im.set_pixel(x, y, Color(0.1, 0.05, 0.18).lerp(co.darkened(0.6), 0.35 * (1.0 - t)))
	# Основа — в центре
	im.blend_rect(ib, Rect2i(0, 0, 36, 36), Vector2i(10, 8))
	# Второе оружие — печать 18×18 в правом нижнем углу на кружке
	var small: Image = io.duplicate()
	small.resize(18, 18, Image.INTERPOLATE_NEAREST)
	for y in range(30, 56):
		for x in range(30, 56):
			var dd := Vector2(x + 0.5 - 43, y + 0.5 - 43).length()
			if dd <= 11.5:
				im.set_pixel(x, y, Color(0.04, 0.02, 0.08) if dd < 10.2 else co)
	im.blend_rect(small, Rect2i(0, 0, 18, 18), Vector2i(34, 34))
	# Золотые звёзды слияния
	var gold := Color(1.0, 0.85, 0.35)
	for c in [Vector2i(8, 8), Vector2i(47, 8)]:
		for i in range(-2, 3):
			im.set_pixel(c.x + i, c.y, gold)
			im.set_pixel(c.x, c.y + i, gold)
	var t2 := tex(im)
	t2.set_meta("icon2x", true)
	_cache[key] = t2
	return t2


static func icon(id: String) -> ImageTexture:
	var key := "icon_" + id
	if _cache.has(key):
		return _cache[key]
	if Icons.has(id):
		var ti := tex(Icons.draw(id))
		ti.set_meta("icon2x", true)
		_cache[key] = ti
		return ti
	var im := blank(18, 18)
	var clear := Color(0, 0, 0, 0)
	match id:
		"bolt":
			line(im, 2, 15, 9, 8, Color(0.2, 0.5, 1.0))
			line(im, 3, 15, 9, 9, Color(0.2, 0.5, 1.0))
			line(im, 2, 14, 8, 8, Color(0.3, 0.7, 1.0))
			ellipse(im, 11.5, 6.5, 4, 4, Color(0.3, 0.85, 1.0))
			ellipse(im, 11.5, 6.5, 2, 2, Color(0.9, 1.0, 1.0))
		"blades":
			for d in 2:
				line(im, 3 + d, 3, 14, 14 - d, Color(1.0, 0.3, 0.8))
				line(im, 14 - d, 3, 3, 14 - d, Color(0.4, 0.9, 1.0))
			rect(im, 2, 13, 3, 3, Color(0.9, 0.7, 0.3))
			rect(im, 13, 13, 3, 3, Color(0.9, 0.7, 0.3))
		"aura":
			ellipse(im, 9, 9, 7.5, 7.5, Color(1.0, 0.5, 0.1))
			ellipse(im, 9, 9, 5.5, 5.5, clear)
			for p in [Vector2i(9, 5), Vector2i(5, 9), Vector2i(13, 9), Vector2i(9, 13)]:
				rect(im, p.x - 1, p.y - 1, 2, 2, Color(1.0, 0.85, 0.3))
		"lightning":
			poly(im, PackedVector2Array([Vector2(11, 1), Vector2(4, 10), Vector2(8.5, 10), Vector2(6, 17),
				Vector2(14, 7), Vector2(9.5, 7), Vector2(12.5, 1)]), Color(0.75, 0.9, 1.0))
		"hp":
			ellipse(im, 6, 7, 3.6, 3.6, Color(0.95, 0.15, 0.35))
			ellipse(im, 12, 7, 3.6, 3.6, Color(0.95, 0.15, 0.35))
			poly(im, PackedVector2Array([Vector2(2.5, 8), Vector2(15.5, 8), Vector2(9, 15.5)]), Color(0.95, 0.15, 0.35))
			line(im, 4, 9, 7, 9, Color(0.4, 1.0, 1.0))
			line(im, 7, 9, 9, 6, Color(0.4, 1.0, 1.0))
			line(im, 9, 6, 11, 11, Color(0.4, 1.0, 1.0))
			line(im, 11, 11, 14, 9, Color(0.4, 1.0, 1.0))
		"speed":
			rect(im, 5, 4, 5, 9, Color(0.3, 0.35, 0.6))
			rect(im, 5, 11, 10, 4, Color(0.3, 0.35, 0.6))
			line(im, 5, 15, 14, 15, Color(1.0, 0.3, 0.8))
			for i in 3:
				line(im, 1, 6 + i * 3, 3, 6 + i * 3, Color(0.4, 0.95, 1.0))
		"magnet":
			ellipse(im, 9, 8, 6.5, 6.5, Color(0.9, 0.2, 0.3))
			ellipse(im, 9, 8, 3.5, 3.5, clear)
			rect(im, 2, 8, 14, 7, clear)
			rect(im, 3, 8, 3, 5, Color(0.9, 0.2, 0.3))
			rect(im, 12, 8, 3, 5, Color(0.9, 0.2, 0.3))
			rect(im, 3, 13, 3, 2, Color(0.85, 0.88, 0.95))
			rect(im, 12, 13, 3, 2, Color(0.85, 0.88, 0.95))
		"damage":
			poly(im, PackedVector2Array([Vector2(9, 1), Vector2(14, 9), Vector2(12, 16), Vector2(6, 16),
				Vector2(4, 10), Vector2(7, 7)]), Color(1.0, 0.35, 0.1))
			poly(im, PackedVector2Array([Vector2(9, 7), Vector2(11.5, 12), Vector2(9, 15.5), Vector2(6.5, 12)]), Color(1.0, 0.85, 0.3))
		"cooldown":
			poly(im, PackedVector2Array([Vector2(4, 2), Vector2(14, 2), Vector2(9, 9)]), Color(0.3, 0.9, 1.0))
			poly(im, PackedVector2Array([Vector2(9, 9), Vector2(14, 16), Vector2(4, 16)]), Color(0.3, 0.9, 1.0))
			rect(im, 3, 1, 12, 1, Color(0.9, 0.7, 0.3))
			rect(im, 3, 16, 12, 1, Color(0.9, 0.7, 0.3))
			rect(im, 6, 13, 6, 2, Color(1.0, 0.95, 0.6))
		"area":
			ellipse(im, 9, 9, 7.5, 7.5, Color(0.75, 0.35, 1.0))
			ellipse(im, 9, 9, 6, 6, clear)
			ellipse(im, 9, 9, 3.5, 3.5, Color(0.75, 0.35, 1.0))
			ellipse(im, 9, 9, 2, 2, clear)
		"regen", "heal":
			rect(im, 7, 3, 4, 12, Color(0.3, 1.0, 0.45))
			rect(im, 3, 7, 12, 4, Color(0.3, 1.0, 0.45))
			rect(im, 8, 4, 2, 10, Color(0.85, 1.0, 0.85))
		"katana":
			line(im, 3, 15, 15, 3, Color(0.85, 0.88, 0.95))
			line(im, 4, 15, 15, 4, Color(0.6, 0.62, 0.72))
			line(im, 8, 11, 14, 5, Color(1.0, 0.3, 0.7))
			rect(im, 2, 13, 3, 3, Color(0.8, 0.15, 0.3))
			line(im, 3, 11, 6, 14, Color(0.9, 0.7, 0.3))
		"quake":
			rect(im, 7, 7, 3, 9, Color(0.45, 0.3, 0.2))
			rect(im, 3, 2, 11, 6, Color(0.45, 0.45, 0.55))
			rect(im, 4, 4, 9, 2, Color(0.5, 1.0, 1.0))
			px(im, 1, 15, Color(0.5, 1.0, 1.0))
			px(im, 15, 15, Color(0.5, 1.0, 1.0))
			line(im, 2, 16, 15, 16, Color(0.4, 0.8, 1.0))
		"drones":
			line(im, 1, 5, 7, 5, Color(0.8, 0.85, 0.95))
			line(im, 11, 5, 17, 5, Color(0.8, 0.85, 0.95))
			rect(im, 3, 6, 2, 2, Color(0.35, 0.38, 0.48))
			rect(im, 13, 6, 2, 2, Color(0.35, 0.38, 0.48))
			ellipse(im, 9, 10, 5, 3.6, Color(0.35, 0.38, 0.48))
			ellipse(im, 9, 10, 2, 2, Color(0.4, 1.0, 0.5))
			line(im, 9, 14, 14, 17, Color(1.0, 0.5, 0.2))
		"ab_vega":
			for i in 3:
				ellipse(im, 5 + i * 3, 9, 3, 5, Color(0.3, 0.9, 1.0, 0.4 + i * 0.3))
			line(im, 2, 15, 15, 2, Color(1.0, 1.0, 1.0))
		"ab_rin":
			ellipse(im, 9, 9, 7.5, 7.5, Color(1.0, 0.3, 0.7))
			ellipse(im, 9, 9, 5.5, 5.5, clear)
			line(im, 3, 3, 15, 15, Color(0.9, 0.92, 1.0))
			line(im, 15, 3, 3, 15, Color(0.9, 0.92, 1.0))
		"ab_bram":
			poly(im, PackedVector2Array([Vector2(9, 1), Vector2(16, 4), Vector2(15, 11), Vector2(9, 17), Vector2(3, 11), Vector2(2, 4)]), Color(1.0, 0.7, 0.25))
			poly(im, PackedVector2Array([Vector2(9, 4), Vector2(13, 6), Vector2(12.5, 10.5), Vector2(9, 14), Vector2(5.5, 10.5), Vector2(5, 6)]), Color(0.5, 0.95, 1.0))
		"ab_kira":
			rect(im, 2, 3, 14, 11, Color(0.15, 0.2, 0.18))
			for y in [5, 8, 11]:
				line(im, 4, y, 4 + (y * 3) % 9, y, Color(0.4, 1.0, 0.5))
			rect(im, 10, 9, 4, 3, Color(1.0, 0.3, 0.7))
		"chest":
			rect(im, 2, 6, 14, 9, Color(0.35, 0.35, 0.45))
			rect(im, 2, 3, 14, 4, Color(0.45, 0.45, 0.55))
			rect(im, 2, 6, 14, 1, Color(0.9, 0.7, 0.3))
			rect(im, 8, 6, 2, 3, Color(1.0, 0.85, 0.4))
		"railbow":
			line(im, 4, 2, 7, 9, Color(0.5, 0.52, 0.6))
			line(im, 7, 9, 4, 16, Color(0.5, 0.52, 0.6))
			line(im, 4, 2, 4, 16, Color(0.5, 1.0, 0.8))
			line(im, 3, 9, 16, 9, Color(0.85, 1.0, 0.95))
			poly(im, PackedVector2Array([Vector2(13, 7), Vector2(17, 9), Vector2(13, 11)]), Color(1, 1, 1))
		"sunbeam":
			ellipse(im, 5, 9, 3.5, 3.5, Color(1.0, 0.85, 0.4))
			rect(im, 7, 7, 10, 4, Color(1.0, 0.75, 0.3))
			rect(im, 7, 8, 10, 2, Color(1.0, 1.0, 0.8))
		"spirits":
			ellipse(im, 9, 7, 5.5, 5, Color(0.75, 0.6, 1.0))
			poly(im, PackedVector2Array([Vector2(3.5, 8), Vector2(14.5, 8), Vector2(12, 16), Vector2(9, 12), Vector2(6, 16)]), Color(0.75, 0.6, 1.0))
			px(im, 7, 6, Color(0.1, 0.05, 0.2))
			px(im, 11, 6, Color(0.1, 0.05, 0.2))
		"ball":
			ellipse(im, 9, 9, 6, 6, Color(0.4, 0.75, 1.0))
			ellipse(im, 9, 9, 3, 3, Color(0.9, 1.0, 1.0))
			line(im, 1, 3, 5, 6, Color(0.8, 0.9, 1.0))
			line(im, 13, 13, 17, 16, Color(0.8, 0.9, 1.0))
		"flask":
			rect(im, 7, 1, 4, 5, Color(0.6, 0.45, 0.3))
			ellipse(im, 9, 11, 6, 6, Color(0.45, 0.65, 0.4))
			ellipse(im, 9, 12, 4, 4, Color(0.6, 1.0, 0.3))
		"shuriken":
			poly(im, PackedVector2Array([Vector2(9, 1), Vector2(11, 7), Vector2(17, 9), Vector2(11, 11), Vector2(9, 17), Vector2(7, 11), Vector2(1, 9), Vector2(7, 7)]), Color(0.85, 0.88, 0.95))
			ellipse(im, 9, 9, 2, 2, Color(1.0, 0.35, 0.35))
		"crit":
			ellipse(im, 9, 9, 7, 7, Color(1.0, 0.3, 0.3))
			ellipse(im, 9, 9, 5, 5, clear)
			line(im, 9, 1, 9, 17, Color(1.0, 0.9, 0.9))
			line(im, 1, 9, 17, 9, Color(1.0, 0.9, 0.9))
		"armor":
			poly(im, PackedVector2Array([Vector2(3, 3), Vector2(15, 3), Vector2(15, 10), Vector2(9, 16), Vector2(3, 10)]), Color(0.45, 0.5, 0.62))
			line(im, 9, 5, 9, 13, Color(0.6, 0.9, 1.0))
			line(im, 6, 8, 12, 8, Color(0.6, 0.9, 1.0))
		"multi":
			for i in 3:
				ellipse(im, 4 + i * 5, 9 - (i % 2) * 3, 2.5, 2.5, Color(0.4, 0.85, 1.0))
		"duration":
			ellipse(im, 9, 10, 6.5, 6.5, Color(0.8, 0.8, 0.9))
			ellipse(im, 9, 10, 5, 5, Color(0.2, 0.2, 0.3))
			line(im, 9, 10, 9, 6, Color(1.0, 0.85, 0.3))
			line(im, 9, 10, 12, 11, Color(1.0, 0.85, 0.3))
			rect(im, 7, 2, 4, 2, Color(0.8, 0.8, 0.9))
		"vamp":
			rect(im, 4, 4, 10, 10, Color(0.3, 0.32, 0.38))
			ellipse(im, 9, 9, 3, 3, Color(1.0, 0.15, 0.3))
			for i in 3:
				px(im, 5 + i * 4, 2, Color(0.8, 0.7, 0.3))
				px(im, 5 + i * 4, 15, Color(0.8, 0.7, 0.3))
		"luck":
			for c in [Vector2(6, 6), Vector2(12, 6), Vector2(6, 12), Vector2(12, 12)]:
				ellipse(im, c.x, c.y, 3, 3, Color(0.4, 1.0, 0.5))
			ellipse(im, 9, 9, 1.6, 1.6, Color(1.0, 0.9, 0.4))
		"ab_skyla":
			for i in 4:
				line(im, 3 + i * 4, 1, 3 + i * 4 - 2, 16, Color(0.5, 1.0, 0.8))
		"ab_orm":
			ellipse(im, 9, 9, 7, 7, Color(1.0, 0.85, 0.4))
			ellipse(im, 9, 9, 5, 5, clear)
			rect(im, 8, 4, 2, 10, Color(1.0, 1.0, 0.8))
			rect(im, 5, 7, 8, 2, Color(1.0, 1.0, 0.8))
		"ab_mora":
			for i in 3:
				ellipse(im, 4 + i * 5, 8 + (i % 2) * 3, 2.5, 3, Color(0.75, 0.6, 1.0))
		"ab_zephyr":
			for i in 4:
				line(im, 4 + i, 3 + i * 4, 14 - i, 3 + i * 4, Color(0.5, 0.85, 1.0))
		"ab_iris":
			ellipse(im, 9, 9, 7, 6, Color(0.6, 1.0, 0.3, 0.8))
			rect(im, 8, 5, 2, 8, Color(1, 1, 1))
			rect(im, 5, 8, 8, 2, Color(1, 1, 1))
		"ab_lyra":
			for i in 3:
				var a := i * TAU / 3.0
				line(im, 9, 9, int(9 + cos(a) * 8), int(9 + sin(a) * 8), Color(0.6, 1.0, 1.0))
			ellipse(im, 9, 9, 2.5, 2.5, Color(0.35, 1.0, 0.95))
		"ab_sol":
			ellipse(im, 9, 9, 5, 5, Color(1.0, 0.85, 0.35))
			for i in 8:
				var a := i * TAU / 8.0
				line(im, int(9 + cos(a) * 6), int(9 + sin(a) * 6), int(9 + cos(a) * 8.5), int(9 + sin(a) * 8.5), Color(1.0, 0.6, 0.2))
		"ab_volt":
			poly(im, PackedVector2Array([Vector2(10, 1), Vector2(4, 10), Vector2(8, 10), Vector2(6, 17), Vector2(14, 7), Vector2(10, 7), Vector2(12, 1)]), Color(0.6, 0.85, 1.0))
		"ab_kai":
			for i in 3:
				var a := -0.6 + i * 0.6
				line(im, 9, 15, int(9 + sin(a) * 8), int(15 - cos(a) * 12), Color(1.0, 0.35, 0.35))
		"academy":
			rect(im, 3, 7, 12, 9, Color(0.5, 0.4, 0.3))
			poly(im, PackedVector2Array([Vector2(1, 7), Vector2(9, 1), Vector2(17, 7)]), Color(1.0, 0.8, 0.3))
		"arsenal":
			line(im, 3, 15, 15, 3, Color(0.85, 0.88, 0.95))
			line(im, 15, 15, 3, 3, Color(0.85, 0.88, 0.95))
			ellipse(im, 9, 9, 3, 3, Color(1.0, 0.5, 0.2))
		"lab":
			rect(im, 7, 1, 4, 6, Color(0.6, 0.8, 0.9))
			poly(im, PackedVector2Array([Vector2(7, 7), Vector2(11, 7), Vector2(16, 16), Vector2(2, 16)]), Color(0.4, 0.9, 1.0))
		"skull":
			ellipse(im, 9, 7.5, 6, 5.5, Color(0.9, 0.9, 0.95))
			rect(im, 6, 11, 6, 4, Color(0.9, 0.9, 0.95))
			ellipse(im, 6.5, 8, 1.6, 1.8, Color(1.0, 0.2, 0.5))
			ellipse(im, 11.5, 8, 1.6, 1.8, Color(1.0, 0.2, 0.5))
			px(im, 8, 13, Color(0.1, 0.1, 0.1))
			px(im, 10, 13, Color(0.1, 0.1, 0.1))
		# ---- Статусы (для библиотеки) ----
		"st_burn":
			poly(im, PackedVector2Array([Vector2(9, 1), Vector2(15, 10), Vector2(13, 16), Vector2(5, 16), Vector2(3, 10), Vector2(6, 6), Vector2(7, 9)]), Color(1.0, 0.45, 0.1))
			poly(im, PackedVector2Array([Vector2(9, 7), Vector2(12, 12), Vector2(11, 16), Vector2(7, 16), Vector2(6, 12)]), Color(1.0, 0.85, 0.3))
		"st_shock":
			poly(im, PackedVector2Array([Vector2(11, 1), Vector2(4, 10), Vector2(8.5, 10), Vector2(6, 17), Vector2(14, 7), Vector2(9.5, 7), Vector2(12, 1)]), Color(0.45, 0.75, 1.0))
		"st_chill":
			for k in 3:
				var a := PI * k / 3.0
				line(im, int(9 - cos(a) * 7), int(9 - sin(a) * 7), int(9 + cos(a) * 7), int(9 + sin(a) * 7), Color(0.6, 0.95, 1.0))
			ellipse(im, 9, 9, 2, 2, Color(0.9, 1.0, 1.0))
		"st_bleed":
			poly(im, PackedVector2Array([Vector2(9, 1), Vector2(14, 10), Vector2(9, 16), Vector2(4, 10)]), Color(0.95, 0.12, 0.25))
			ellipse(im, 9, 11, 4.5, 4.5, Color(0.95, 0.12, 0.25))
			px(im, 7, 9, Color(1.0, 0.6, 0.7))
		"st_poison":
			ellipse(im, 9, 7, 5.5, 5, Color(0.5, 1.0, 0.2))
			rect(im, 6, 11, 6, 3, Color(0.5, 1.0, 0.2))
			ellipse(im, 7, 7, 1.4, 1.6, Color(0.1, 0.2, 0.05))
			ellipse(im, 11, 7, 1.4, 1.6, Color(0.1, 0.2, 0.05))
			line(im, 3, 16, 15, 15, Color(0.4, 0.8, 0.2))
		"st_wet":
			poly(im, PackedVector2Array([Vector2(9, 1), Vector2(14, 10), Vector2(9, 16), Vector2(4, 10)]), Color(0.3, 0.55, 1.0))
			ellipse(im, 9, 11, 4.5, 4.5, Color(0.3, 0.55, 1.0))
			px(im, 7, 9, Color(0.8, 0.9, 1.0))
		"book":
			rect(im, 3, 3, 12, 13, Color(0.5, 0.2, 0.6))
			rect(im, 5, 4, 9, 11, Color(0.95, 0.9, 0.8))
			line(im, 9, 4, 9, 14, Color(0.6, 0.5, 0.45))
			rect(im, 6, 6, 2, 1, Color(0.3, 0.9, 1.0))
			rect(im, 11, 8, 2, 1, Color(1.0, 0.3, 0.75))
	var t := tex(Icons.upgrade(im))
	t.set_meta("icon2x", true)
	_cache[key] = t
	return t


## Портрет героя одной картинкой: тело + неоновые детали (для кнопок и библиотеки).
static func portrait(sprite: String, dark := false) -> ImageTexture:
	var key := "portrait_" + sprite + ("_d" if dark else "")
	if _cache.has(key):
		return _cache[key]
	var fr := frames(sprite)
	var bi: Image = (fr["base"][0] as ImageTexture).get_image()
	var ei: Image = (fr["emit"][0] as ImageTexture).get_image()
	var im := bi.duplicate() as Image
	im.convert(Image.FORMAT_RGBA8)
	ei.convert(Image.FORMAT_RGBA8)
	for x in im.get_width():
		for y in im.get_height():
			var c := im.get_pixel(x, y)
			var e := ei.get_pixel(x, y)
			if e.a > 0.3:
				c = Color(e.r, e.g, e.b, 1.0)
			if dark and c.a > 0.1:
				c = Color(0.12, 0.1, 0.18, c.a)
			im.set_pixel(x, y, c)
	var t := tex(im)
	_cache[key] = t
	return t


## Кольцо с рунами для «Рунного круга».
static func rune_ring() -> ImageTexture:
	if _cache.has("rune_ring"):
		return _cache["rune_ring"]
	var s := 48
	var im := blank(s, s)
	var c := float(s) / 2.0
	for x in s:
		for y in s:
			var d := Vector2(x + 0.5 - c, y + 0.5 - c).length()
			if d >= 21.0 and d < 23.0:
				im.set_pixel(x, y, Color(1, 1, 1, 1))
			elif d >= 15.0 and d < 16.0:
				im.set_pixel(x, y, Color(1, 1, 1, 0.7))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 12:
		var a := TAU * i / 12.0
		var p := Vector2(c, c) + Vector2(cos(a), sin(a)) * 18.5
		for gx in 3:
			for gy in 3:
				if rng.randf() < 0.6:
					px(im, int(p.x) - 1 + gx, int(p.y) - 1 + gy, Color(1, 1, 1, 0.95))
	var t := tex(im)
	_cache["rune_ring"] = t
	return t


# ============ Мягкие текстуры (свет, свечение, тень) ============

static func glow() -> GradientTexture2D:
	if _cache.has("glow"):
		return _cache["glow"]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 128
	t.height = 128
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	_cache["glow"] = t
	return t


static func shadow() -> ImageTexture:
	if _cache.has("shadow"):
		return _cache["shadow"]
	var im := blank(14, 6)
	ellipse(im, 7, 3, 7, 3, Color(0, 0, 0, 0.35))
	ellipse(im, 7, 3, 5, 2, Color(0, 0, 0, 0.6))
	var t := tex(im)
	_cache["shadow"] = t
	return t


static func raindrop() -> ImageTexture:
	if _cache.has("rain"):
		return _cache["rain"]
	var im := blank(1, 6)
	for y in 6:
		im.set_pixel(0, y, Color(1, 1, 1, float(y + 1) / 6.0))
	var t := tex(im)
	_cache["rain"] = t
	return t


# ============ Материалы ============

static func mat_unshaded() -> CanvasItemMaterial:
	if not _cache.has("mat_u"):
		var m := CanvasItemMaterial.new()
		m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		_cache["mat_u"] = m
	return _cache["mat_u"]


static func mat_add() -> CanvasItemMaterial:
	if not _cache.has("mat_a"):
		var m := CanvasItemMaterial.new()
		m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_cache["mat_a"] = m
	return _cache["mat_a"]



# ---------- Жители убежища (процедурные, по зерну) ----------

static func _paint_villager(b: Image, e: Image, f: int, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var p := _hero_pose(f)
	var oy: int = p["oy"]
	var fl: int = p["fl"]
	var robes := [Color(0.22, 0.25, 0.5), Color(0.45, 0.18, 0.35), Color(0.18, 0.38, 0.32),
		Color(0.42, 0.32, 0.2), Color(0.3, 0.3, 0.36), Color(0.5, 0.25, 0.15)]
	var neons := [Color(0.3, 1.0, 1.0), Color(1.0, 0.3, 0.75), Color(0.4, 1.0, 0.5), Color(1.0, 0.75, 0.3), Color(0.7, 0.45, 1.0)]
	var skins := [Color(0.95, 0.8, 0.68), Color(0.75, 0.55, 0.42), Color(0.5, 0.35, 0.28), Color(0.6, 0.75, 0.9), Color(0.7, 0.9, 0.7)]
	var robe: Color = robes[rng.randi_range(0, robes.size() - 1)]
	var neon: Color = neons[rng.randi_range(0, neons.size() - 1)]
	var skin: Color = skins[rng.randi_range(0, skins.size() - 1)]
	var hat := rng.randi_range(0, 3)
	var plump := rng.randi_range(0, 1)
	_legs(b, p, 7, 10, 19, Color(0.1, 0.09, 0.14))
	# Тело
	poly(b, PackedVector2Array([Vector2(6 - plump, 11 + oy), Vector2(12 + plump, 11 + oy),
		Vector2(14 + plump, 20 + fl), Vector2(4 - plump, 20 - fl)]), robe)
	rect(b, 6, 15 + oy, 7, 1, robe.darkened(0.35))
	line(e, 5 - plump, 19 - fl, 13 + plump, 19 + fl, Color(neon, 0.8))
	# Голова
	ellipse(b, 9.5, 8 + oy, 3.4, 3.3, skin)
	px(b, 8, 8 + oy, Color(0.05, 0.03, 0.08))
	px(b, 11, 8 + oy, Color(0.05, 0.03, 0.08))
	match hat:
		0:  # капюшон
			ellipse(b, 9.5, 6.5 + oy, 4.2, 3.0, robe.lightened(0.1))
			rect(b, 6, 6 + oy, 7, 1, robe.lightened(0.1))
		1:  # кепка с антенной
			rect(b, 6, 4 + oy, 8, 2, Color(0.2, 0.2, 0.28))
			rect(b, 11, 5 + oy, 4, 1, Color(0.2, 0.2, 0.28))
			line(b, 8, 4 + oy, 7, 1 + oy, Color(0.5, 0.5, 0.6))
			px(e, 7, 1 + oy, neon)
		2:  # широкая шляпа
			rect(b, 4, 5 + oy, 12, 1, Color(0.25, 0.18, 0.12))
			rect(b, 7, 2 + oy, 6, 3, Color(0.25, 0.18, 0.12))
			rect(e, 7, 4 + oy, 6, 1, Color(neon, 0.8))
		3:  # визор
			rect(b, 6, 5 + oy, 7, 2, Color(0.2, 0.2, 0.28))
			rect(e, 7, 8 + oy, 6, 1, neon)
	# Инструмент в руке
	if rng.randf() < 0.5:
		line(b, 14, 12 + oy, 14, 18 + oy, Color(0.5, 0.45, 0.4))
		px(e, 14, 11 + oy, neon)



# ---------- Окружение биомов ----------

static func _paint_env(key: String, b: Image, e: Image) -> void:
	var v := int(key.right(1)) if key.right(1).is_valid_int() else 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var cy := Color(0.3, 0.95, 1.0)
	var mg := Color(1.0, 0.3, 0.75)
	var vi := Color(0.7, 0.4, 1.0)
	var gr := Color(0.4, 1.0, 0.5)
	var og := Color(1.0, 0.6, 0.2)
	match key:
		"sign0", "sign1":
			var col := mg if v == 0 else cy
			rect(b, 8, 14, 2, 19, Color(0.25, 0.25, 0.32))
			rect(b, 1, 2, 16, 12, Color(0.12, 0.1, 0.18))
			for i in 2:
				for j in 3:
					if rng.randf() < 0.75:
						rect(e, 3 + j * 4, 4 + i * 5, 3, 3, col)
			line(e, 1, 2, 16, 2, Color(col, 0.7))
			line(e, 1, 13, 16, 13, Color(col, 0.7))
		"barrel0", "barrel1":
			var col := Color(0.35, 0.3, 0.2) if v == 0 else Color(0.25, 0.32, 0.4)
			rect(b, 2, 2, 8, 12, col)
			rect(b, 2, 4, 8, 1, col.darkened(0.4))
			rect(b, 2, 10, 8, 1, col.darkened(0.4))
			if v == 0:
				rect(e, 4, 6, 4, 3, Color(0.5, 1.0, 0.3, 0.9))
			else:
				px(e, 5, 7, cy)
		"rock0", "rock1":
			var w := 18 if v == 0 else 14
			poly(b, PackedVector2Array([Vector2(1, w * 0.7), Vector2(3, 4), Vector2(w * 0.5, 1), Vector2(w - 2, 3), Vector2(w, w * 0.7)]), Color(0.24, 0.22, 0.3))
			line(b, w / 2, 3, w / 2 + 2, 8, Color(0.14, 0.13, 0.19))
			if rng.randf() < 0.6:
				px(e, w / 2 - 2, 6, Color(vi, 0.8))
		"crystal_big0", "crystal_big1":
			var col := cy if v == 0 else vi
			poly(b, PackedVector2Array([Vector2(7, 33), Vector2(11, 3), Vector2(15, 33)]), col.darkened(0.5))
			poly(b, PackedVector2Array([Vector2(2, 33), Vector2(5, 15), Vector2(9, 33)]), col.darkened(0.55))
			poly(b, PackedVector2Array([Vector2(13, 33), Vector2(18, 18), Vector2(21, 33)]), col.darkened(0.55))
			line(e, 11, 5, 11, 30, col)
			line(e, 5, 17, 6, 30, Color(col, 0.8))
			line(e, 18, 20, 17, 30, Color(col, 0.8))
			px(e, 11, 5, Color(1, 1, 1))
		"pillar0", "pillar1":
			var hgt := 34 if v == 0 else 22
			var stone := Color(0.32, 0.3, 0.38)
			rect(b, 3, 36 - hgt if v == 0 else 24 - hgt, 8, hgt - 3, stone)
			rect(b, 1, (33 if v == 0 else 21), 12, 3, stone.darkened(0.2))
			if v == 0:
				rect(b, 1, 2, 12, 3, stone.darkened(0.1))
			else:
				poly(b, PackedVector2Array([Vector2(3, 3), Vector2(6, 1), Vector2(9, 4), Vector2(11, 2), Vector2(11, 5), Vector2(3, 5)]), stone)
			for y in range(8 if v == 0 else 6, hgt - 4, 6):
				px(e, 7, y, og)
				px(e, 6, y + 1, Color(og, 0.7))
		"statue0":
			var stone := Color(0.34, 0.32, 0.4)
			rect(b, 2, 33, 14, 4, stone.darkened(0.2))
			poly(b, PackedVector2Array([Vector2(4, 33), Vector2(14, 33), Vector2(12, 12), Vector2(6, 12)]), stone)
			ellipse(b, 9, 8, 4, 4.5, stone)
			rect(e, 7, 8, 5, 1, cy)
			line(b, 4, 14, 1, 22, stone)
			line(b, 14, 14, 17, 22, stone)
			line(e, 9, 16, 9, 28, Color(vi, 0.8))
		"tree0", "tree1", "tree2":
			var leaf := [Color(0.15, 0.35, 0.3), Color(0.3, 0.15, 0.35), Color(0.12, 0.25, 0.4)][v] as Color
			var glow := [gr, mg, cy][v] as Color
			var w := b.get_width()
			var hgt := b.get_height()
			rect(b, w / 2 - 2, hgt / 2, 4, hgt / 2 - 1, Color(0.22, 0.17, 0.2))
			line(e, w / 2, hgt / 2 + 2, w / 2, hgt - 3, Color(glow, 0.5))
			for i in 5:
				ellipse(b, rng.randf_range(w * 0.25, w * 0.75), rng.randf_range(hgt * 0.15, hgt * 0.5), rng.randf_range(5, 8), rng.randf_range(4, 7), leaf)
			for i in 14:
				var x := rng.randi_range(3, w - 4)
				var y := rng.randi_range(3, int(hgt * 0.6))
				if b.get_pixel(x, y).a > 0.5:
					px(e, x, y, glow)
		"mushroom0", "mushroom1":
			var col := [cy, mg][v] as Color
			var n := 2 if v == 0 else 3
			for i in n:
				var x := 4 + i * 5 + rng.randi_range(0, 2)
				var hgt := rng.randi_range(5, b.get_height() - 4)
				rect(b, x, b.get_height() - hgt, 2, hgt - 1, Color(0.75, 0.72, 0.65))
				ellipse(b, x + 1, b.get_height() - hgt, 4, 2.5, col.darkened(0.5))
				line(e, x - 2, b.get_height() - hgt, x + 3, b.get_height() - hgt, col)
				px(e, x, b.get_height() - hgt - 1, Color(1, 1, 1, 0.8))
		"wreck0", "wreck1":
			var metal := Color(0.3, 0.28, 0.33)
			if v == 0:
				rect(b, 2, 6, 26, 9, metal)
				rect(b, 7, 2, 13, 5, metal.lightened(0.05))
				ellipse(b, 7, 15, 3, 2.5, Color(0.1, 0.1, 0.12))
				ellipse(b, 22, 15, 3, 2.5, Color(0.1, 0.1, 0.12))
				rect(b, 9, 3, 4, 3, Color(0.08, 0.1, 0.14))
				px(e, 27, 9, Color(1.0, 0.3, 0.2))
				line(b, 14, 6, 17, 13, metal.darkened(0.4))
			else:
				ellipse(b, 12, 14, 9, 6, metal)
				ellipse(b, 12, 7, 5, 4.5, metal.lightened(0.08))
				rect(e, 10, 7, 4, 1, Color(cy, 0.4))
				line(b, 4, 15, 1, 20, metal)
				line(b, 20, 15, 23, 21, metal)
				px(e, 6, 14, og)
		"decal_rune":
			var c := 24.0
			for x in 48:
				for y in 48:
					var d := Vector2(x + 0.5 - c, y + 0.5 - c).length()
					if d >= 21.0 and d < 22.5:
						e.set_pixel(x, y, Color(vi, 0.55))
					elif d >= 15.0 and d < 16.0:
						e.set_pixel(x, y, Color(vi, 0.35))
			for i in 8:
				var a := TAU * i / 8.0
				var p := Vector2(c, c) + Vector2(cos(a), sin(a)) * 18.5
				for gx in 2:
					for gy in 2:
						if rng.randf() < 0.7:
							px(e, int(p.x) + gx, int(p.y) + gy, Color(og, 0.7))
			for i in 3:
				var a := TAU * i / 3.0
				line(e, 24, 24, int(24 + cos(a) * 15), int(24 + sin(a) * 15), Color(vi, 0.3))
		"decal_grate":
			rect(b, 0, 0, 24, 16, Color(0.08, 0.08, 0.11, 0.95))
			for x in range(2, 23, 3):
				line(b, x, 1, x, 14, Color(0.2, 0.2, 0.26, 1.0))
			rect(e, 1, 6, 22, 4, Color(1.0, 0.45, 0.15, 0.25))
		"decal_moss":
			for i in 40:
				var p := Vector2(rng.randf_range(3, 27), rng.randf_range(2, 16))
				ellipse(b, p.x, p.y, rng.randf_range(1.0, 3.0), rng.randf_range(1.0, 2.0), Color(0.1, 0.22, 0.15, 0.8))
			for i in 8:
				px(e, rng.randi_range(4, 26), rng.randi_range(3, 15), Color(gr, 0.7))
		"decal_cable":
			var y := 7.0
			for x in 40:
				y = clampf(y + rng.randf_range(-0.8, 0.8), 2.0, 11.0)
				px(b, x, int(y), Color(0.06, 0.06, 0.09))
				px(b, x, int(y) + 1, Color(0.12, 0.12, 0.16))
				if x % 9 == 4:
					px(e, x, int(y), Color(cy, 0.9))
		"decal_crater":
			ellipse(b, 17, 10, 16, 9, Color(0.2, 0.14, 0.28, 0.22))
			ellipse(b, 17, 10, 12, 6.5, Color(0.12, 0.09, 0.18, 0.3))
			for i in 10:
				var a := rng.randf() * TAU
				px(e, int(17 + cos(a) * 9), int(10 + sin(a) * 5), Color(vi, 0.45))



# ============ Пиксельные текстуры поверхностей (для 3D-убежища) ============

## kind: panel — металлические панели, brick — кирпич, tile — плитка, wood — доски
static func surface(kind: String) -> ImageTexture:
	var key := "surf_" + kind
	if _cache.has(key):
		return _cache[key]
	var n := 16
	var im := blank(n, n)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	for x in n:
		for y in n:
			var v := 0.78 + rng.randf_range(-0.04, 0.04)
			match kind:
				"panel":
					if x == 0 or y == 0:
						v = 0.45
					elif x == 1 or y == 1:
						v = 0.92
					elif (x == 3 or x == n - 3) and (y == 3 or y == n - 3):
						v = 1.0
					elif y == 8 and x > 4 and x < 12:
						v = 0.55
				"brick":
					var row := y / 4
					var off := 4 if row % 2 == 1 else 0
					if y % 4 == 0 or (x + off) % 8 == 0:
						v = 0.4
					else:
						v += (hash(Vector2i((x + off) / 8, row)) % 7) * 0.02 - 0.06
				"tile":
					if x % 8 == 0 or y % 8 == 0:
						v = 0.5
					elif ((x / 8) + (y / 8)) % 2 == 0:
						v -= 0.06
				"wood":
					if y % 5 == 0:
						v = 0.45
					else:
						v += sin(x * 0.9 + y * 3.0) * 0.04
			im.set_pixel(x, y, Color(v, v, v))
	var t := tex(im)
	_cache[key] = t
	return t



# ---------- Дрон-фамильяр: корпус, два винта, глаз-камера, подсветка ----------

static func _paint_drone(b: Image, e: Image, f: int) -> void:
	var metal := Color(0.32, 0.34, 0.44)
	var dark := Color(0.16, 0.17, 0.24)
	var neon := Color(0.4, 1.0, 0.5)
	# Штанги к винтам
	line(b, 5, 6, 9, 8, dark)
	line(b, 16, 6, 12, 8, dark)
	rect(b, 3, 5, 3, 2, metal)
	rect(b, 16, 5, 3, 2, metal)
	# Винты: два кадра — размытый диск и лопасти
	var prop := Color(0.75, 0.8, 0.9, 0.85)
	if f == 0:
		line(b, 0, 4, 8, 4, prop)
		line(b, 13, 4, 21, 4, prop)
	else:
		line(b, 2, 3, 6, 5, prop)
		line(b, 15, 5, 19, 3, prop)
		px(b, 4, 4, prop)
		px(b, 17, 4, prop)
	# Корпус
	ellipse(b, 11, 9, 5.5, 4, metal)
	rect(b, 7, 6, 8, 2, metal.lightened(0.2))
	rect(b, 9, 12, 4, 2, dark)
	# Глаз-камера
	ellipse(b, 11, 9, 2.4, 2.4, Color(0.05, 0.05, 0.08))
	ellipse(e, 11, 9, 1.6, 1.6, neon)
	px(e, 10, 8, Color(0.9, 1.0, 0.9))
	# Подсветка снизу и антенна
	line(e, 9, 14, 13, 14, Color(neon, 0.8))
	line(b, 14, 5, 16, 1, dark)
	px(e, 16, 1, Color(1.0, 0.3, 0.3) if f == 0 else Color(1.0, 0.6, 0.6))



# ---------- Новые герои ----------

static func _paint_hero2(key: String, b: Image, e: Image, f: int) -> void:
	var p := _hero_pose(f)
	var oy: int = p["oy"]
	var fl: int = p["fl"]
	var k: int = p["k"]
	match key:
		"skyla":  # неоновая лучница: светлые волосы, капюшон-маска, лук-рельса
			var cloak := Color(0.15, 0.32, 0.3)
			var neon := Color(0.4, 1.0, 0.8)
			_legs(b, p, 8, 12, 21, Color(0.12, 0.14, 0.16))
			poly(b, PackedVector2Array([Vector2(8, 11 + oy), Vector2(14, 11 + oy), Vector2(16, 22 + fl), Vector2(6, 22 - fl)]), cloak)
			line(e, 7, 21 - fl, 15, 21 + fl, neon)
			rect(b, 8, 15 + oy, 7, 1, Color(0.7, 0.55, 0.3))
			ellipse(b, 11.5, 8 + oy, 3.6, 3.6, Color(0.92, 0.82, 0.72))
			poly(b, PackedVector2Array([Vector2(7, 6 + oy), Vector2(16, 6 + oy), Vector2(15, 4 + oy), Vector2(9, 3 + oy)]), Color(0.95, 0.95, 0.85))
			poly(b, PackedVector2Array([Vector2(7, 7 + oy), Vector2(4, 15 + oy + fl), Vector2(8, 13 + oy)]), Color(0.95, 0.95, 0.85))
			px(b, 15, 7 + oy, Color(0.92, 0.82, 0.72))
			poly(b, PackedVector2Array([Vector2(16, 6 + oy), Vector2(18, 4 + oy), Vector2(17, 7 + oy)]), Color(0.92, 0.82, 0.72))
			rect(e, 11, 8 + oy, 4, 1, neon)
			# лук-рельса
			line(b, 18, 5 + oy, 20, 13 + oy, Color(0.4, 0.42, 0.5))
			line(b, 20, 13 + oy, 18, 21, Color(0.4, 0.42, 0.5))
			line(e, 18, 6 + oy, 18, 20, Color(neon, 0.8))
		"orm":  # паровой паладин: массивный корпус, котёл, нимб-шестерня
			var brass := Color(0.62, 0.48, 0.25)
			var steel := Color(0.42, 0.42, 0.5)
			var holy := Color(1.0, 0.85, 0.4)
			_legs(b, p, 8, 14, 23, steel.darkened(0.3), 3)
			ellipse(b, 12.5, 17 + oy, 7.5, 7, steel)
			rect(b, 7, 15 + oy, 12, 4, brass)
			ellipse(e, 12.5, 17 + oy, 2.2, 2.2, Color(1.0, 0.6, 0.2))
			ellipse(b, 5, 12 + oy, 3.2, 3, brass)
			ellipse(b, 20, 12 + oy, 3.2, 3, brass)
			rect(b, 9, 5 + oy, 8, 7, steel.lightened(0.1))
			rect(e, 10, 8 + oy, 6, 1, holy)
			for i in 6:
				var a := TAU * i / 6.0 + k * 0.3
				px(e, int(13 + cos(a) * 6), int(4 + oy + sin(a) * 2), Color(holy, 0.85))
			rect(b, 1, 13 + oy, 3, 9, steel)
			rect(e, 2, 14 + oy, 1, 7, Color(holy, 0.7))
			if k % 2 == 0:
				px(e, 17, 3 + oy, Color(0.8, 0.8, 0.85, 0.7))
		"mora":  # некро-хакерша: тёмный балахон, череп-маска, голо-коса
			var robe := Color(0.14, 0.1, 0.2)
			var neon := Color(0.7, 0.5, 1.0)
			_legs(b, p, 8, 12, 21, Color(0.08, 0.06, 0.1))
			poly(b, PackedVector2Array([Vector2(7, 10 + oy), Vector2(15, 10 + oy), Vector2(17, 22 + fl), Vector2(5, 22 - fl)]), robe)
			for y in range(13, 21, 3):
				px(e, 10, y + oy, Color(neon, 0.8))
				px(e, 12, y + oy + 1, Color(0.3, 1.0, 0.6, 0.7))
			ellipse(b, 11, 7 + oy, 4.4, 4.2, robe.lightened(0.1))
			ellipse(b, 12, 8 + oy, 2.6, 2.6, Color(0.85, 0.85, 0.8))
			px(e, 11, 8 + oy, neon)
			px(e, 13, 8 + oy, neon)
			line(b, 18, 3 + oy, 18, 22, Color(0.3, 0.28, 0.35))
			poly(e, PackedVector2Array([Vector2(18, 3 + oy), Vector2(12, 2 + oy), Vector2(9, 5 + oy), Vector2(14, 4 + oy)]), Color(neon, 0.9))
		"zephyr":  # шторм-шаман: перья, маска, посох с вихрем
			var robe := Color(0.18, 0.25, 0.42)
			var neon := Color(0.5, 0.85, 1.0)
			_legs(b, p, 8, 12, 23, Color(0.15, 0.12, 0.1))
			poly(b, PackedVector2Array([Vector2(8, 12 + oy), Vector2(14, 12 + oy), Vector2(16, 24 + fl), Vector2(6, 24 - fl)]), robe)
			for x in [7, 9, 11, 13, 15]:
				px(b, x, 23 + (x % 2), Color(0.9, 0.85, 0.7))
			ellipse(b, 11, 9 + oy, 3.5, 3.5, Color(0.6, 0.45, 0.35))
			rect(b, 8, 8 + oy, 7, 2, Color(0.2, 0.2, 0.25))
			rect(e, 9, 9 + oy, 5, 1, neon)
			for i in 4:
				line(b, 9 + i * 2, 6 + oy, 8 + i * 3, 1 + oy - (i % 2), [Color(0.9, 0.3, 0.3), Color(0.3, 0.6, 1.0), Color(0.9, 0.85, 0.3), Color(0.3, 0.9, 0.5)][i])
			line(b, 18, 6 + oy, 18, 24, Color(0.45, 0.35, 0.25))
			ellipse(e, 18, 4 + oy + [0, -1, -1, 0][k], 2.2, 2.2, Color(neon, 0.8))
			px(e, 17 + k % 2, 3 + oy, Color(1, 1, 1))
		"iris":  # алхимик-биотех: очки-гоглы, фартук, пояс с колбами
			var coat := Color(0.82, 0.82, 0.78)
			var neon := Color(0.6, 1.0, 0.3)
			_legs(b, p, 8, 12, 21, Color(0.2, 0.18, 0.15))
			poly(b, PackedVector2Array([Vector2(8, 11 + oy), Vector2(14, 11 + oy), Vector2(16, 22 + fl), Vector2(6, 22 - fl)]), coat)
			rect(b, 9, 13 + oy, 5, 8, Color(0.35, 0.3, 0.25))
			for i in 3:
				rect(b, 7 + i * 3, 16 + oy, 2, 3, Color(0.3, 0.35, 0.3))
				px(e, 7 + i * 3, 17 + oy, [neon, Color(1.0, 0.4, 0.6), Color(0.4, 0.8, 1.0)][i])
			ellipse(b, 11, 8 + oy, 3.5, 3.5, Color(0.9, 0.75, 0.62))
			rect(b, 7, 4 + oy, 8, 3, Color(0.75, 0.3, 0.2))
			rect(b, 8, 7 + oy, 7, 2, Color(0.25, 0.25, 0.3))
			px(e, 9, 7 + oy, neon)
			px(e, 13, 7 + oy, neon)
			rect(b, 16, 13 + oy, 2, 3, coat)
			ellipse(e, 18, 12 + oy + [0, -1, -1, 0][k], 1.8, 2, neon)
		"kai":  # кибер-ниндзя: маска, красный визор, шарф, катана-тень
			var suit := Color(0.12, 0.12, 0.16)
			var red := Color(1.0, 0.3, 0.3)
			_legs(b, p, 8, 12, 19, suit.darkened(0.2))
			poly(b, PackedVector2Array([Vector2(8, 10 + oy), Vector2(14, 10 + oy), Vector2(14.5, 19.5), Vector2(7.5, 19.5)]), suit)
			line(e, 8, 15 + oy, 13, 15 + oy, Color(red, 0.7))
			poly(b, PackedVector2Array([Vector2(8, 10 + oy), Vector2(2, 9 + oy + fl), Vector2(1, 12 + oy - fl), Vector2(8, 12 + oy)]), Color(0.7, 0.12, 0.15))
			ellipse(b, 11, 6 + oy, 3.6, 3.6, suit.lightened(0.1))
			rect(e, 10, 6 + oy, 5, 1, red)
			px(e, 14, 6 + oy, Color(1, 0.8, 0.8))
			line(b, 4, 18, 15, 3 + oy, Color(0.25, 0.25, 0.3))
			px(e, 15, 3 + oy, red)


# ---------- Новые враги ----------

static func _paint_mob2(key: String, b: Image, e: Image, f: int) -> void:
	var bob: int = [0, -1, -1, 0][f]
	var step: int = [1, 0, -1, 0][f]
	match key:
		"goblin":  # кибер-гоблин с имплантом и ножом
			var skin := Color(0.35, 0.6, 0.25)
			rect(b, 5 + step, 12, 2, 3, skin.darkened(0.3))
			rect(b, 9 - step, 12, 2, 3, skin.darkened(0.3))
			ellipse(b, 8, 9 + bob, 4, 3.5, Color(0.4, 0.3, 0.2))
			ellipse(b, 8, 5 + bob, 4, 3.4, skin)
			poly(b, PackedVector2Array([Vector2(4, 4 + bob), Vector2(0, 2 + bob), Vector2(4, 6 + bob)]), skin)
			poly(b, PackedVector2Array([Vector2(12, 4 + bob), Vector2(16, 2 + bob), Vector2(12, 6 + bob)]), skin)
			px(e, 9, 5 + bob, Color(1.0, 0.3, 0.2))
			px(b, 6, 5 + bob, Color(0.1, 0.1, 0.1))
			line(b, 12, 9 + bob, 15, 7 + bob, Color(0.75, 0.78, 0.85))
		"slime", "slimelet":  # нано-слизь с ядром-чипом
			var w := b.get_width()
			var h := b.get_height()
			var squish: float = [0.0, 0.8, 1.2, 0.5][f]
			ellipse(b, w / 2.0, h - h * 0.4, w * 0.45 + squish, h * 0.38 - squish * 0.5, Color(0.15, 0.55, 0.45, 0.85))
			ellipse(e, w / 2.0, h - h * 0.4, w * 0.3, h * 0.22, Color(0.3, 1.0, 0.8, 0.35))
			rect(e, int(w / 2.0) - 1, int(h - h * 0.45), 2, 2, Color(1.0, 0.9, 0.4))
			px(b, int(w * 0.35), int(h * 0.45), Color(0.05, 0.05, 0.08))
			px(b, int(w * 0.62), int(h * 0.45), Color(0.05, 0.05, 0.08))
		"spider", "spiderling":  # мех-паук
			var w := b.get_width()
			var h := b.get_height()
			var body := Color(0.3, 0.12, 0.12)
			for i in 4:
				var lx := int(w * 0.2) + i * int(w * 0.18)
				var lift := (f + i) % 2
				line(b, lx, int(h * 0.5), lx - 3, h - 2 - lift, Color(0.45, 0.45, 0.5))
				line(b, w - lx, int(h * 0.5), w - lx + 3, h - 2 - lift, Color(0.45, 0.45, 0.5))
			ellipse(b, w / 2.0, h * 0.45 + bob * 0.5, w * 0.28, h * 0.28, body)
			ellipse(b, w / 2.0, h * 0.25 + bob * 0.5, w * 0.16, h * 0.18, body.lightened(0.1))
			for i in 3:
				px(e, int(w / 2.0) - 2 + i * 2, int(h * 0.25), Color(1.0, 0.3, 0.2))
		"caster":  # культист-техномант с парящей сферой
			var robe := Color(0.25, 0.12, 0.35)
			poly(b, PackedVector2Array([Vector2(5, 9), Vector2(13, 9), Vector2(15, 23), Vector2(3, 23)]), robe)
			ellipse(b, 9, 7 + bob, 4, 4, robe.lightened(0.15))
			ellipse(b, 9, 8 + bob, 2.4, 2.4, Color(0.05, 0.03, 0.08))
			px(e, 8, 8 + bob, Color(0.9, 0.5, 1.0))
			px(e, 10, 8 + bob, Color(0.9, 0.5, 1.0))
			for y in range(12, 22, 3):
				px(e, 9, y, Color(0.8, 0.4, 1.0, 0.8))
			ellipse(e, 15, 5 + bob * 2, 2.2, 2.2, Color(0.9, 0.5, 1.0))
			px(e, 15, 5 + bob * 2, Color(1, 1, 1))
		"bomber":  # бомба-дрон с мигающим таймером
			ellipse(b, 8, 9, 6, 5.5, Color(0.25, 0.25, 0.3))
			rect(b, 3, 3, 10, 2, Color(0.5, 0.5, 0.55))
			line(b, 0, 3 + f % 2, 5, 3, Color(0.8, 0.8, 0.9, 0.8))
			line(b, 11, 3, 16, 3 + (f + 1) % 2, Color(0.8, 0.8, 0.9, 0.8))
			rect(b, 5, 8, 6, 3, Color(0.85, 0.6, 0.1))
			rect(e, 6, 9, 4, 1, Color(1.0, 0.3, 0.1) if f % 2 == 0 else Color(1.0, 0.9, 0.3))
		"knight":  # рыцарь-призрак в рунных латах со щитом
			var plate := Color(0.4, 0.45, 0.55)
			rect(b, 6 + step, 20, 3, 5, plate.darkened(0.3))
			rect(b, 11 - step, 20, 3, 5, plate.darkened(0.3))
			rect(b, 5, 9 + bob, 10, 11, plate)
			ellipse(b, 10, 6 + bob, 4, 4, plate.lightened(0.1))
			rect(b, 7, 6 + bob, 6, 1, Color(0.05, 0.05, 0.08))
			rect(e, 8, 6 + bob, 4, 1, Color(0.6, 0.9, 1.0))
			poly(b, PackedVector2Array([Vector2(1, 10 + bob), Vector2(6, 10 + bob), Vector2(6, 18 + bob), Vector2(3.5, 21 + bob), Vector2(1, 18 + bob)]), Color(0.3, 0.32, 0.42))
			line(e, 3, 12 + bob, 3, 18 + bob, Color(0.6, 0.9, 1.0, 0.9))
			line(e, 2, 14 + bob, 5, 14 + bob, Color(0.6, 0.9, 1.0, 0.9))
			line(b, 15, 8 + bob, 18, 2 + bob, Color(0.75, 0.78, 0.85))


# ---------- Финальный босс: Архимаг Омега ----------

static func _paint_omega(b: Image, e: Image, f: int) -> void:
	var bob: int = [0, -1, -1, 0][f]
	var robe := Color(0.1, 0.15, 0.2)
	var metal := Color(0.4, 0.42, 0.5)
	var neon := Color(0.3, 1.0, 0.9)
	var mag := Color(1.0, 0.3, 0.75)
	# Мантия с проводами
	var pts := PackedVector2Array([Vector2(16, 18 + bob), Vector2(34, 18 + bob)])
	var x := 40.0
	while x >= 10.0:
		pts.append(Vector2(x, 50.0 + sin(x * 0.6 + f * 1.4) * 2.0 + bob))
		x -= 3.0
	poly(b, pts, robe)
	for i in 5:
		line(e, 18 + i * 3, 22 + bob, 15 + i * 5, 48 + bob, Color(neon if i % 2 == 0 else mag, 0.6))
	# Механические плечи и четыре руки
	ellipse(b, 13, 20 + bob, 6, 4.5, metal)
	ellipse(b, 37, 20 + bob, 6, 4.5, metal)
	for side in [-1, 1]:
		var cx: int = 25 + side * 14
		line(b, cx, 22 + bob, cx + side * 6, 30 + bob + f % 2, metal)
		line(b, cx, 22 + bob, cx + side * 9, 16 + bob - f % 2, metal)
		ellipse(e, cx + side * 6, 32 + bob, 2.2, 2.2, mag)
		ellipse(e, cx + side * 9, 14 + bob, 2.2, 2.2, neon)
	# Голова-маска с короной-нимбом
	ellipse(b, 25, 12 + bob, 6, 6.5, metal.lightened(0.1))
	rect(b, 20, 13 + bob, 11, 2, Color(0.05, 0.05, 0.08))
	rect(e, 21, 13 + bob, 9, 1, neon)
	px(e, 25, 9 + bob, mag)
	for i in 7:
		var a := PI + PI * i / 6.0
		px(e, int(25 + cos(a) * 10), int(10 + bob + sin(a) * 6), Color(neon, 0.9))
	# Ядро в груди
	ellipse(e, 25, 26 + bob, 3.5, 3.5, neon)
	ellipse(e, 25, 26 + bob, 1.6, 1.6, Color(1, 1, 1))



# ---------- Средневековье + неон ----------

static func _bricks(b: Image, x0: int, y0: int, w: int, h: int, c: Color, rng: RandomNumberGenerator) -> void:
	rect(b, x0, y0, w, h, c)
	for y in range(y0, y0 + h):
		var row := (y - y0) / 3
		for x in range(x0, x0 + w):
			if (y - y0) % 3 == 0 or (x + (row % 2) * 3) % 6 == 0:
				px(b, x, y, c.darkened(0.3))
			elif rng.randf() < 0.06:
				px(b, x, y, c.lightened(0.08))


static func _paint_medieval(key: String, b: Image, e: Image) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) + 7
	var stone := Color(0.36, 0.34, 0.42)
	var wood := Color(0.32, 0.2, 0.14)
	var plaster := Color(0.62, 0.56, 0.5)
	var roof := Color(0.42, 0.16, 0.2)
	var cy := Color(0.3, 0.95, 1.0)
	var mg := Color(1.0, 0.3, 0.75)
	var gd := Color(1.0, 0.75, 0.3)
	var gr := Color(0.4, 1.0, 0.5)
	match key:
		"house0", "house1", "house2":
			var v := int(key.right(1))
			var w := b.get_width()
			var h := b.get_height()
			var neon: Color = [mg, cy, gd][v]
			var roof_c: Color = [roof, Color(0.2, 0.25, 0.35), Color(0.3, 0.22, 0.15)][v]
			var base_y := h - 10
			_bricks(b, 2, base_y, w - 4, 9, stone, rng)
			var wall_top := int(h * 0.42)
			rect(b, 3, wall_top, w - 6, base_y - wall_top, plaster)
			# фахверк: тёмные балки
			for x in range(3, w - 3, 8):
				line(b, x, wall_top, x, base_y - 1, wood)
			line(b, 3, wall_top, w - 4, wall_top, wood)
			line(b, 3, (wall_top + base_y) / 2, w - 4, (wall_top + base_y) / 2, wood)
			line(b, 3, wall_top, 11, base_y - 1, wood)
			# крутая крыша из черепицы
			poly(b, PackedVector2Array([Vector2(0, wall_top + 1), Vector2(w / 2.0, 2), Vector2(w, wall_top + 1)]), roof_c)
			for y in range(6, wall_top, 3):
				line(b, int(w / 2.0 - (y - 2) * 0.85), y, int(w / 2.0 + (y - 2) * 0.85), y, roof_c.darkened(0.25))
			# окна с тёплым и неоновым светом
			for i in 2:
				var wx := 7 + i * (w - 18)
				rect(b, wx, wall_top + 5, 5, 6, Color(0.08, 0.06, 0.1))
				rect(e, wx + 1, wall_top + 6, 3, 4, Color(1.0, 0.8, 0.45) if (i + v) % 2 == 0 else neon)
			# дверь
			rect(b, w / 2 - 3, base_y - 9, 6, 9 + 8, wood.darkened(0.2))
			px(e, w / 2 + 1, base_y - 4, gd)
			# неоновая вывеска на кронштейне и антенна на крыше
			line(b, w - 5, wall_top + 2, w - 1, wall_top + 2, Color(0.3, 0.3, 0.35))
			rect(b, w - 6, wall_top + 3, 6, 5, Color(0.1, 0.08, 0.14))
			rect(e, w - 5, wall_top + 4, 4, 3, neon)
			line(b, w / 2 + 5, 8, w / 2 + 5, 1, Color(0.4, 0.4, 0.45))
			line(b, w / 2 + 3, 3, w / 2 + 8, 3, Color(0.4, 0.4, 0.45))
			px(e, w / 2 + 5, 1, Color(1.0, 0.25, 0.25))
			# кабель вдоль стены
			for x in range(4, w - 4):
				if x % 9 == 0:
					px(e, x, base_y - 1, Color(neon, 0.8))
		"tower0":
			var w := b.get_width()
			var h := b.get_height()
			_bricks(b, 3, 10, w - 6, h - 12, stone, rng)
			for x in range(2, w - 2, 5):
				rect(b, x, 6, 3, 5, stone.lightened(0.05))
			rect(b, 2, 9, w - 4, 2, stone.darkened(0.2))
			# бойницы с рунным светом
			for y in [20, 34, 48]:
				rect(b, w / 2 - 1, y, 2, 6, Color(0.05, 0.04, 0.08))
				rect(e, w / 2 - 1, y + 1, 2, 4, Color(0.7, 0.4, 1.0))
			# неоновое знамя и шпиль-антенна
			rect(b, 5, 14, 5, 14, Color(0.15, 0.1, 0.2))
			line(e, 6, 15, 6, 26, mg)
			line(e, 8, 15, 8, 23, Color(mg, 0.7))
			line(b, w / 2, 6, w / 2, 0, Color(0.45, 0.45, 0.5))
			px(e, w / 2, 0, Color(1.0, 0.25, 0.25))
			line(e, 3, h - 3, w - 4, h - 3, Color(cy, 0.6))
		"wall0":
			var w := b.get_width()
			var h := b.get_height()
			_bricks(b, 0, 7, w, h - 8, stone, rng)
			for x in range(0, w, 6):
				rect(b, x, 3, 4, 5, stone.lightened(0.05))
			for i in 3:
				var rx := 8 + i * 15
				for gx in 3:
					for gy in 3:
						if rng.randf() < 0.6:
							px(e, rx + gx, 14 + gy, Color(0.7, 0.4, 1.0, 0.9))
			line(e, 0, h - 3, w - 1, h - 3, Color(cy, 0.5))
		"gate0":
			var w := b.get_width()
			var h := b.get_height()
			_bricks(b, 0, 8, 14, h - 9, stone, rng)
			_bricks(b, w - 14, 8, 14, h - 9, stone, rng)
			_bricks(b, 14, 8, w - 28, 12, stone, rng)
			for x in [0, 5, 10, w - 14, w - 9, w - 4]:
				rect(b, x, 3, 4, 5, stone.lightened(0.05))
			ellipse(b, w / 2.0, 22, 10, 6, Color(0.05, 0.04, 0.08))
			rect(b, 14, 22, w - 28, h - 23, Color(0.05, 0.04, 0.08))
			# энергетическая решётка ворот
			for x in range(15, w - 14, 3):
				line(e, x, 20, x, h - 2, Color(cy, 0.55))
			for y in range(23, h - 1, 4):
				line(e, 15, y, w - 15, y, Color(cy, 0.35))
			px(e, 7, 20, gd)
			px(e, w - 7, 20, gd)
		"stall0", "stall1":
			var v := int(key.right(1))
			var w := b.get_width()
			var h := b.get_height()
			var cloth: Color = [Color(0.6, 0.15, 0.25), Color(0.15, 0.35, 0.55)][v]
			line(b, 3, 8, 3, h - 2, wood)
			line(b, w - 4, 8, w - 4, h - 2, wood)
			poly(b, PackedVector2Array([Vector2(0, 9), Vector2(4, 2), Vector2(w - 4, 2), Vector2(w, 9)]), cloth)
			for x in range(2, w - 2, 6):
				rect(b, x, 3, 3, 6, cloth.lightened(0.35))
			rect(b, 2, h - 10, w - 4, 8, wood)
			for i in 4:
				rect(b, 5 + i * 6, h - 13, 4, 3, [Color(0.8, 0.3, 0.2), Color(0.9, 0.8, 0.3), Color(0.4, 0.7, 0.3), Color(0.6, 0.4, 0.8)][i])
			rect(b, w / 2 - 5, 11, 10, 5, Color(0.08, 0.06, 0.12))
			rect(e, w / 2 - 4, 12, 8, 3, [mg, cy][v])
		"well0":
			var w := b.get_width()
			_bricks(b, 2, 12, w - 4, 10, stone, rng)
			ellipse(b, w / 2.0, 12, w / 2.0 - 2, 3, stone.darkened(0.1))
			ellipse(e, w / 2.0, 12, w / 2.0 - 4, 2, Color(0.3, 0.9, 1.0, 0.85))
			line(b, 3, 12, 3, 2, wood)
			line(b, w - 4, 12, w - 4, 2, wood)
			poly(b, PackedVector2Array([Vector2(1, 4), Vector2(w / 2.0, 0), Vector2(w - 1, 4)]), roof)
		"banner0", "banner1":
			var v := int(key.right(1))
			var col: Color = [mg, cy][v]
			line(b, 3, 2, 3, 41, Color(0.45, 0.45, 0.5))
			px(e, 3, 1, gd)
			poly(b, PackedVector2Array([Vector2(4, 4), Vector2(13, 4), Vector2(13, 22), Vector2(8.5, 19), Vector2(4, 22)]), Color(0.12, 0.08, 0.18))
			line(e, 6, 7, 11, 7, col)
			line(e, 8, 9, 8, 16, col)
			line(e, 6, 12, 11, 12, Color(col, 0.7))
		"lantern0":
			line(b, 5, 8, 5, 32, Color(0.25, 0.25, 0.3))
			rect(b, 3, 31, 5, 2, Color(0.25, 0.25, 0.3))
			line(b, 5, 8, 9, 8, Color(0.25, 0.25, 0.3))
			rect(b, 7, 9, 5, 6, Color(0.2, 0.18, 0.15))
			rect(e, 8, 10, 3, 4, Color(1.0, 0.7, 0.3))
			px(e, 9, 11, Color(0.4, 1.0, 1.0))
		"pine0", "pine1":
			var v := int(key.right(1))
			var w := b.get_width()
			var h := b.get_height()
			var needle: Color = [Color(0.1, 0.25, 0.22), Color(0.15, 0.18, 0.3)][v]
			var glow: Color = [gr, cy][v]
			rect(b, w / 2 - 1, h - 9, 3, 8, Color(0.25, 0.17, 0.14))
			for i in 4:
				var ty := 2 + i * int((h - 10) / 4.0)
				var tw := 4 + i * (w / 2 - 4) / 3
				poly(b, PackedVector2Array([Vector2(w / 2.0, ty), Vector2(w / 2.0 + tw, ty + (h - 10) / 3.0), Vector2(w / 2.0 - tw, ty + (h - 10) / 3.0)]), needle.lightened(i * 0.03))
			for i in 10:
				var x := rng.randi_range(3, w - 4)
				var y := rng.randi_range(4, h - 12)
				if b.get_pixel(x, y).a > 0.5:
					px(e, x, y, glow)
		"bush0", "bush1":
			var w := b.get_width()
			var h := b.get_height()
			for i in 4:
				ellipse(b, rng.randf_range(4, w - 4), rng.randf_range(h * 0.45, h - 4), rng.randf_range(3, 5), rng.randf_range(3, 4), Color(0.12, 0.26, 0.2))
			for i in 4:
				px(e, rng.randi_range(3, w - 4), rng.randi_range(3, h - 3), Color(mg, 0.9) if i % 2 == 0 else Color(gr, 0.9))
		"cart0":
			rect(b, 3, 7, 22, 7, wood)
			line(b, 25, 10, 29, 12, wood)
			ellipse(b, 8, 15, 3.5, 3.5, Color(0.2, 0.15, 0.12))
			ellipse(b, 20, 15, 3.5, 3.5, Color(0.2, 0.15, 0.12))
			rect(b, 5, 2, 6, 5, Color(0.4, 0.3, 0.2))
			rect(b, 12, 3, 6, 4, Color(0.3, 0.3, 0.36))
			px(e, 14, 4, gr)
			px(e, 16, 4, cy)
		"fence0":
			for x in range(1, 31, 5):
				rect(b, x, 2, 2, 11, wood)
			line(b, 0, 5, 31, 5, wood.lightened(0.1))
			line(b, 0, 10, 31, 10, wood.lightened(0.1))
			for x in range(3, 30, 10):
				px(e, x, 5, Color(cy, 0.7))
		"decal_cobble":
			for x in 48:
				for y in 26:
					var d := Vector2((x - 24) / 24.0, (y - 13) / 13.0).length()
					if d < 1.0 and rng.randf() < 0.9:
						var st := ((x / 4) + (y / 3)) % 2
						b.set_pixel(x, y, Color(0.22, 0.2, 0.26, 0.75 - d * 0.4) if st == 0 else Color(0.18, 0.16, 0.22, 0.75 - d * 0.4))
						if x % 4 == 0 or y % 3 == 0:
							b.set_pixel(x, y, Color(0.08, 0.07, 0.1, 0.7 - d * 0.4))
		"decal_road":
			for x in 64:
				for y in 22:
					if y < 2 or y > 19:
						b.set_pixel(x, y, Color(0.12, 0.1, 0.14, 0.8))
					else:
						var st := ((x / 4) + (y / 3)) % 2
						b.set_pixel(x, y, Color(0.2, 0.18, 0.24, 0.85) if st == 0 else Color(0.17, 0.15, 0.21, 0.85))
						if x % 4 == 0 or y % 3 == 2:
							b.set_pixel(x, y, Color(0.08, 0.07, 0.1, 0.8))
			for x in range(4, 64, 16):
				line(e, x, 11, x + 6, 11, Color(cy, 0.45))


# ================= Деревья: детальный пиксель-арт =================
## Свет падает слева сверху: три тона листвы, кора с прожилками, корни,
## неоновые светлячки, фонарики и кабели — фэнтези с киберпанком.

static func _leaf_blob(b: Image, cx: float, cy: float, rx: float, ry: float, dark: Color, mid: Color, light: Color) -> void:
	ellipse(b, cx, cy, rx, ry, dark)
	ellipse(b, cx - rx * 0.15, cy - ry * 0.2, rx * 0.78, ry * 0.7, mid)
	ellipse(b, cx - rx * 0.35, cy - ry * 0.42, rx * 0.38, ry * 0.32, light)


static func _leaf_texture(b: Image, rng: RandomNumberGenerator, dark: Color, x0: int, y0: int, x1: int, y1: int) -> void:
	# Резные края и «дыры» в кроне: шахматная крапинка тёмным тоном
	for i in (x1 - x0) * (y1 - y0) / 7:
		var x := rng.randi_range(x0, x1)
		var y := rng.randi_range(y0, y1)
		if b.get_pixel(x, y).a > 0.5 and b.get_pixel(x, y) != dark:
			px(b, x, y, dark)
			if rng.randf() < 0.4:
				px(b, x + 1, y + 1, dark)


static func _trunk(b: Image, cx: int, top: int, bottom: int, wd: int, bark: Color) -> void:
	for y in range(top, bottom):
		var k := float(y - top) / maxf(1.0, bottom - top)
		var hw := int(round(wd * 0.5 + k * k * 1.5))
		for x in range(cx - hw, cx + hw + 1):
			var c := bark
			if x == cx - hw:
				c = bark.lightened(0.18)
			elif x >= cx + hw - 1:
				c = bark.darkened(0.35)
			elif (x * 3 + y) % 5 == 0:
				c = bark.darkened(0.2)
			px(b, x, y, c)
	# Корни
	line(b, cx - wd, bottom - 1, cx - wd - 3, bottom, bark.darkened(0.1))
	line(b, cx + wd, bottom - 1, cx + wd + 3, bottom, bark.darkened(0.3))
	line(b, cx, bottom - 1, cx + 1, bottom, bark.darkened(0.2))


static func _paint_tree(key: String, b: Image, e: Image) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) + 4242
	var w := b.get_width()
	var h := b.get_height()
	var gr := Color(0.35, 1.0, 0.55)
	var mg := Color(1.0, 0.3, 0.75)
	var cy := Color(0.3, 0.95, 1.0)
	var gd := Color(1.0, 0.75, 0.35)
	var bark := Color(0.3, 0.21, 0.18)
	match key:
		"tree0", "tree1", "tree2":
			# Лиственное дерево: широкая крона из облаков листвы
			var v := int(key.right(1))
			var pal: Array = [
				[Color(0.07, 0.2, 0.17), Color(0.12, 0.34, 0.26), Color(0.26, 0.55, 0.36), gr],
				[Color(0.17, 0.08, 0.2), Color(0.32, 0.14, 0.36), Color(0.56, 0.26, 0.55), mg],
				[Color(0.06, 0.14, 0.26), Color(0.1, 0.26, 0.42), Color(0.22, 0.48, 0.66), cy]][v]
			var cx := w / 2
			var crown_y := h * 0.36
			_trunk(b, cx, int(h * 0.42), h - 2, 4 if v != 2 else 3, bark)
			# Ветви, уходящие в крону
			line(b, cx, int(h * 0.55), cx - 7, int(h * 0.4), bark)
			line(b, cx + 1, int(h * 0.5), cx + 8, int(h * 0.36), bark.darkened(0.2))
			var blobs := 9 if v != 2 else 7
			var order: Array = []
			for i in blobs:
				var a := TAU * i / blobs + rng.randf_range(-0.3, 0.3)
				var r := rng.randf_range(0.45, 0.85)
				order.append(Vector2(cx + cos(a) * w * 0.3 * r, crown_y + sin(a) * h * 0.2 * r))
			# Сначала нижние облака, потом верхние — верхние перекрывают
			order.sort_custom(func(p, q): return p.y > q.y)
			for p in order:
				_leaf_blob(b, p.x, p.y, rng.randf_range(w * 0.17, w * 0.24), rng.randf_range(h * 0.12, h * 0.16), pal[0], pal[1], pal[2])
			_leaf_blob(b, cx - 1, crown_y - h * 0.12, w * 0.22, h * 0.14, pal[0], pal[1], pal[2])
			_leaf_texture(b, rng, pal[0], 1, 1, w - 2, int(h * 0.62))
			# Неоновые плоды/светлячки в кроне
			for i in 12:
				var x := rng.randi_range(3, w - 4)
				var y := rng.randi_range(3, int(h * 0.6))
				if b.get_pixel(x, y).a > 0.5:
					px(e, x, y, pal[3])
					if i % 3 == 0:
						px(e, x + 1, y, Color(pal[3], 0.5))
			if v == 1:
				# Висящий фонарик на ветке
				line(b, cx - 7, int(h * 0.48), cx - 7, int(h * 0.56), Color(0.15, 0.12, 0.12))
				rect(b, cx - 9, int(h * 0.56), 4, 5, Color(0.2, 0.15, 0.12))
				rect(e, cx - 8, int(h * 0.57), 2, 3, gd)
			elif v == 0:
				# Кабель-лиана с огоньками вокруг ствола
				for y in range(int(h * 0.62), h - 4, 4):
					px(e, cx - 2 + (y / 4) % 2 * 4, y, Color(cy, 0.8))
			else:
				# Руна, вырезанная в коре
				line(e, cx, int(h * 0.7), cx, int(h * 0.78), Color(cy, 0.9))
				px(e, cx - 1, int(h * 0.72), Color(cy, 0.9))
				px(e, cx + 1, int(h * 0.75), Color(cy, 0.9))
		"tree3":
			# Плакучая неоновая ива: купол и свисающие светящиеся пряди
			var dark := Color(0.08, 0.16, 0.2)
			var mid := Color(0.13, 0.3, 0.32)
			var light := Color(0.3, 0.56, 0.5)
			var cx := w / 2
			_trunk(b, cx, int(h * 0.35), h - 2, 4, bark.darkened(0.1))
			for i in 6:
				var a := PI + PI * i / 5.0
				_leaf_blob(b, cx + cos(a) * w * 0.22, h * 0.26 + sin(a) * h * 0.1, w * 0.2, h * 0.11, dark, mid, light)
			_leaf_blob(b, cx, h * 0.2, w * 0.28, h * 0.13, dark, mid, light)
			for i in 14:
				var x := 3 + int((w - 6) * i / 13.0)
				var top := int(h * 0.28) + rng.randi_range(-2, 3)
				var bot := top + rng.randi_range(int(h * 0.22), int(h * 0.45))
				if absi(x - cx) < 3:
					bot = mini(bot, int(h * 0.4))
				line(b, x, top, x + rng.randi_range(-1, 1), bot, mid if i % 2 == 0 else dark)
				px(e, x, bot, Color(cy, 0.9) if i % 3 else Color(mg, 0.9))
				if rng.randf() < 0.5:
					px(e, x, bot - 3, Color(cy, 0.4))
			_leaf_texture(b, rng, dark, 1, 1, w - 2, int(h * 0.4))
		"pine0", "pine1", "pine2":
			# Ель: ярусы с зубчатым краем, свет слева
			var v := int(key.right(1))
			var dark: Color = [Color(0.05, 0.16, 0.14), Color(0.07, 0.1, 0.2), Color(0.12, 0.1, 0.22)][v]
			var mid: Color = [Color(0.1, 0.28, 0.22), Color(0.12, 0.2, 0.34), Color(0.18, 0.15, 0.32)][v]
			var light: Color = [Color(0.22, 0.46, 0.34), Color(0.24, 0.38, 0.56), Color(0.38, 0.4, 0.62)][v]
			var glow: Color = [gr, cy, Color(0.75, 0.6, 1.0)][v]
			var cx := w / 2.0
			var foot := h - 8
			rect(b, int(cx) - 2, foot - 2, 4, 9, bark)
			px(b, int(cx) + 1, foot + 2, bark.darkened(0.3))
			var tiers := 5 if v == 0 else 4
			for t in tiers:
				var ty := 1 + int(t * (foot - 6) / float(tiers + 0.6))
				var th := int((foot - ty) * 0.55) if t < tiers - 1 else foot - ty
				th = maxi(th, 8)
				var maxw := 3.0 + (w / 2.0 - 2.0) * (t + 1) / float(tiers)
				for y in th:
					var hw := maxw * (float(y) + 1.0) / th
					if y == th - 1:
						hw -= 1.0
					var jag := 1.0 if (y + t) % 3 == 0 else 0.0
					for x in range(int(cx - hw - jag), int(cx + hw + jag) + 1):
						var rel := (x - (cx - hw)) / maxf(1.0, hw * 2.0)
						var c := light if rel < 0.28 else (mid if rel < 0.72 else dark)
						if y > th - 3:
							c = dark
						px(b, x, ty + y, c)
				# Нижний край яруса — бахрома иголок
				for x in range(int(cx - maxw), int(cx + maxw) + 1, 2):
					px(b, x, ty + th, dark)
			for i in 14:
				var x := rng.randi_range(2, w - 3)
				var y := rng.randi_range(4, foot - 2)
				if b.get_pixel(x, y).a > 0.5:
					px(e, x, y, glow if i % 4 else Color(1, 1, 1, 0.8))
			if v == 2:
				# Кристальный иней на кончиках ярусов
				for t in tiers:
					var ty := 1 + int(t * (foot - 6) / float(tiers + 0.6))
					px(e, int(cx), ty, Color(0.9, 0.8, 1.0))
			# Неоновая звезда-маячок на макушке
			px(e, int(cx), 0, glow)
		"bush0", "bush1":
			var v := int(key.right(1))
			var dark := Color(0.06, 0.18, 0.14) if v == 0 else Color(0.14, 0.08, 0.2)
			var mid := Color(0.12, 0.32, 0.22) if v == 0 else Color(0.28, 0.14, 0.34)
			var light := Color(0.26, 0.52, 0.34) if v == 0 else Color(0.5, 0.26, 0.52)
			for i in 4:
				_leaf_blob(b, 4 + (w - 8) * i / 3.0, h - 5 - (2 if i % 3 else 4), rng.randf_range(4, 6), rng.randf_range(3.5, 5), dark, mid, light)
			_leaf_texture(b, rng, dark, 0, 0, w - 1, h - 1)
			for i in 5:
				var x := rng.randi_range(2, w - 3)
				var y := rng.randi_range(3, h - 3)
				if b.get_pixel(x, y).a > 0.5:
					px(e, x, y, mg if (i + v) % 2 == 0 else gr)


# ================= Герои: детальный риг 32×40, 16 кадров =================
# Кадры: 0–3 покой (дыхание), 4–9 бег, 10–13 атака (замах, удар, доводка, возврат),
# 14–15 получение урона. Герой смотрит вправо, отражение — flip_h.

const HERO_KEYS := ["hero", "rin", "bram", "kira", "skyla", "orm", "mora", "zephyr", "iris", "kai", "lyra", "sol", "volt"]
## 35 кадров: покой 6, бег 8, удар 5, способность 5, урон 2, смерть 6, рывок 3
const HERO_ANIM := {"idle": [0, 6], "run": [6, 8], "attack": [14, 5], "cast": [19, 5], "hurt": [24, 2],
	"death": [26, 6], "dash": [32, 3]}
const HERO_FRAMES := 35
## Риг героя рисуется в логических координатах 32×40, а на холсте 48×60 — в 1.5 раза
## крупнее: контуры, эллипсы и линии получаются плавнее, а детали дорисовываются
## отдельными проходами в полном разрешении.
const HS := 1.5

## Внешность: цвета и «детали» каждого героя.
const LOOKS := {
	"hero": {"skin": Color(0.05, 0.03, 0.1), "main": Color(0.2, 0.24, 0.55), "trim": Color(0.9, 0.68, 0.27),
		"legs": Color(0.14, 0.12, 0.25), "boots": Color(0.1, 0.09, 0.17), "back": "cloak", "back_c": Color(0.17, 0.2, 0.5),
		"head": "hood", "head_c": Color(0.32, 0.18, 0.55), "neon": Color(0.3, 1.0, 1.0), "neon2": Color(1.0, 0.25, 0.72),
		"weapon": "staff", "w_c": Color(0.45, 0.48, 0.64), "gem": Color(0.75, 0.4, 1.0), "build": 0},
	"rin": {"skin": Color(0.9, 0.75, 0.65), "main": Color(0.16, 0.14, 0.22), "trim": Color(0.75, 0.1, 0.25),
		"legs": Color(0.12, 0.1, 0.16), "boots": Color(0.3, 0.28, 0.36), "back": "scarf", "back_c": Color(0.78, 0.1, 0.25),
		"head": "samurai", "head_c": Color(0.3, 0.28, 0.36), "neon": Color(1.0, 0.25, 0.6), "neon2": Color(1.0, 0.7, 0.85),
		"weapon": "katana", "w_c": Color(0.78, 0.8, 0.88), "gem": Color(1.0, 0.25, 0.6), "build": 0},
	"bram": {"skin": Color(0.9, 0.68, 0.55), "main": Color(0.36, 0.34, 0.4), "trim": Color(0.9, 0.55, 0.2),
		"legs": Color(0.3, 0.2, 0.14), "boots": Color(0.2, 0.15, 0.1), "back": "none", "back_c": Color(0.35, 0.22, 0.14),
		"head": "dwarf", "head_c": Color(0.45, 0.44, 0.5), "hair": Color(0.8, 0.42, 0.15), "neon": Color(1.0, 0.65, 0.2),
		"neon2": Color(0.4, 0.85, 1.0), "weapon": "hammer", "w_c": Color(0.4, 0.4, 0.48), "gem": Color(1.0, 0.6, 0.2), "build": 2},
	"kira": {"skin": Color(0.88, 0.76, 0.68), "main": Color(0.12, 0.16, 0.14), "trim": Color(0.4, 1.0, 0.5),
		"legs": Color(0.1, 0.12, 0.12), "boots": Color(0.08, 0.1, 0.1), "back": "cape_short", "back_c": Color(0.1, 0.2, 0.15),
		"head": "witch", "head_c": Color(0.1, 0.12, 0.14), "hair": Color(0.3, 0.9, 0.55), "neon": Color(0.4, 1.0, 0.5),
		"neon2": Color(0.8, 1.0, 0.85), "weapon": "wand", "w_c": Color(0.3, 0.32, 0.4), "gem": Color(0.4, 1.0, 0.5), "build": 0},
	"skyla": {"skin": Color(0.92, 0.82, 0.72), "main": Color(0.16, 0.36, 0.34), "trim": Color(0.7, 0.55, 0.3),
		"legs": Color(0.12, 0.14, 0.16), "boots": Color(0.25, 0.2, 0.15), "back": "quiver", "back_c": Color(0.4, 0.3, 0.2),
		"head": "hood_white", "head_c": Color(0.92, 0.92, 0.86), "hair": Color(0.95, 0.95, 0.88), "neon": Color(0.45, 1.0, 0.8),
		"neon2": Color(0.8, 1.0, 0.95), "weapon": "bow", "w_c": Color(0.42, 0.44, 0.52), "gem": Color(0.45, 1.0, 0.8), "build": 0},
	"orm": {"skin": Color(0.85, 0.7, 0.6), "main": Color(0.45, 0.45, 0.52), "trim": Color(0.75, 0.58, 0.28),
		"legs": Color(0.32, 0.32, 0.4), "boots": Color(0.28, 0.26, 0.32), "back": "cape", "back_c": Color(0.6, 0.15, 0.15),
		"head": "great_helm", "head_c": Color(0.55, 0.55, 0.62), "neon": Color(1.0, 0.85, 0.4), "neon2": Color(1.0, 0.6, 0.2),
		"weapon": "mace", "w_c": Color(0.62, 0.48, 0.25), "gem": Color(1.0, 0.85, 0.4), "build": 2},
	"mora": {"skin": Color(0.85, 0.85, 0.8), "main": Color(0.14, 0.1, 0.2), "trim": Color(0.45, 0.3, 0.65),
		"legs": Color(0.08, 0.06, 0.1), "boots": Color(0.08, 0.06, 0.1), "back": "robe", "back_c": Color(0.12, 0.08, 0.18),
		"head": "skull", "head_c": Color(0.18, 0.12, 0.25), "neon": Color(0.7, 0.5, 1.0), "neon2": Color(0.3, 1.0, 0.6),
		"weapon": "scythe", "w_c": Color(0.3, 0.28, 0.35), "gem": Color(0.7, 0.5, 1.0), "build": 0},
	"zephyr": {"skin": Color(0.62, 0.46, 0.36), "main": Color(0.18, 0.26, 0.45), "trim": Color(0.9, 0.85, 0.7),
		"legs": Color(0.15, 0.12, 0.1), "boots": Color(0.25, 0.2, 0.16), "back": "robe", "back_c": Color(0.15, 0.22, 0.4),
		"head": "feathers", "head_c": Color(0.2, 0.2, 0.25), "neon": Color(0.5, 0.85, 1.0), "neon2": Color(1.0, 1.0, 1.0),
		"weapon": "orbstaff", "w_c": Color(0.45, 0.35, 0.25), "gem": Color(0.5, 0.85, 1.0), "build": 0},
	"iris": {"skin": Color(0.9, 0.75, 0.62), "main": Color(0.84, 0.84, 0.8), "trim": Color(0.35, 0.3, 0.25),
		"legs": Color(0.2, 0.18, 0.15), "boots": Color(0.3, 0.22, 0.16), "back": "coat", "back_c": Color(0.78, 0.78, 0.74),
		"head": "goggles", "head_c": Color(0.25, 0.25, 0.3), "hair": Color(0.8, 0.3, 0.2), "neon": Color(0.6, 1.0, 0.3),
		"neon2": Color(1.0, 0.4, 0.6), "weapon": "flask", "w_c": Color(0.6, 0.8, 0.9), "gem": Color(0.6, 1.0, 0.3), "build": 0},
	"lyra": {"skin": Color(0.92, 0.78, 0.7), "main": Color(0.12, 0.3, 0.36), "trim": Color(0.85, 0.85, 0.95),
		"legs": Color(0.1, 0.16, 0.2), "boots": Color(0.75, 0.75, 0.85), "back": "scarf", "back_c": Color(0.3, 0.95, 0.9),
		"head": "samurai", "head_c": Color(0.85, 0.85, 0.95), "hair": Color(0.25, 0.9, 0.85), "neon": Color(0.35, 1.0, 0.95),
		"neon2": Color(1.0, 0.85, 1.0), "weapon": "blade", "w_c": Color(0.85, 0.9, 1.0), "gem": Color(0.35, 1.0, 0.95), "build": 0},
	"sol": {"skin": Color(0.72, 0.52, 0.38), "main": Color(0.9, 0.8, 0.6), "trim": Color(0.95, 0.65, 0.2),
		"legs": Color(0.6, 0.5, 0.35), "boots": Color(0.4, 0.3, 0.2), "back": "robe", "back_c": Color(0.85, 0.55, 0.2),
		"head": "great_helm", "head_c": Color(0.95, 0.75, 0.35), "neon": Color(1.0, 0.8, 0.3), "neon2": Color(1.0, 1.0, 0.8),
		"weapon": "orbstaff", "w_c": Color(0.75, 0.6, 0.3), "gem": Color(1.0, 0.85, 0.35), "build": 1},
	"volt": {"skin": Color(0.88, 0.72, 0.6), "main": Color(0.22, 0.26, 0.36), "trim": Color(0.95, 0.8, 0.2),
		"legs": Color(0.18, 0.18, 0.24), "boots": Color(0.3, 0.25, 0.2), "back": "coat", "back_c": Color(0.3, 0.34, 0.45),
		"head": "goggles", "head_c": Color(0.3, 0.3, 0.36), "hair": Color(0.95, 0.95, 1.0), "neon": Color(0.55, 0.8, 1.0),
		"neon2": Color(1.0, 0.95, 0.4), "weapon": "hammer", "w_c": Color(0.45, 0.45, 0.55), "gem": Color(0.55, 0.8, 1.0), "build": 1},
	"kai": {"skin": Color(0.12, 0.12, 0.16), "main": Color(0.12, 0.12, 0.16), "trim": Color(0.7, 0.12, 0.15),
		"legs": Color(0.1, 0.1, 0.13), "boots": Color(0.08, 0.08, 0.1), "back": "scarf", "back_c": Color(0.72, 0.12, 0.15),
		"head": "ninja", "head_c": Color(0.15, 0.15, 0.2), "neon": Color(1.0, 0.3, 0.3), "neon2": Color(1.0, 0.8, 0.8),
		"weapon": "blade", "w_c": Color(0.35, 0.35, 0.42), "gem": Color(1.0, 0.3, 0.3), "build": 1},
}


## ===== Жители хаба на том же риге, что и герои =====
## Ключ: citizen_<роль>_<семя>. Внешность собирается из палитр по роли.
const CITIZEN_FRAMES := 14     # покой 0–5, ходьба 6–13
static var _gen_looks := {}


static func look(key: String) -> Dictionary:
	if LOOKS.has(key):
		return LOOKS[key]
	if not _gen_looks.has(key):
		var parts := key.split("_")
		_gen_looks[key] = citizen_look(parts[1] if parts.size() > 2 else "walker", int(parts[-1]))
	return _gen_looks[key]


static func citizen_look(role: String, seed: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed * 7919 + 13
	var pick := func(a: Array): return a[r.randi_range(0, a.size() - 1)]
	var skins := [Color(0.95, 0.8, 0.68), Color(0.86, 0.66, 0.52), Color(0.68, 0.48, 0.36), Color(0.48, 0.33, 0.25),
		Color(0.92, 0.76, 0.66), Color(0.62, 0.74, 0.86)]
	var cloth := [Color(0.22, 0.25, 0.5), Color(0.45, 0.18, 0.35), Color(0.18, 0.38, 0.32), Color(0.42, 0.32, 0.2),
		Color(0.3, 0.3, 0.36), Color(0.5, 0.25, 0.15), Color(0.55, 0.5, 0.42), Color(0.15, 0.3, 0.45), Color(0.4, 0.12, 0.14)]
	var hairs := [Color(0.12, 0.08, 0.06), Color(0.45, 0.25, 0.12), Color(0.85, 0.7, 0.35), Color(0.75, 0.75, 0.78),
		Color(0.7, 0.2, 0.15), Color(0.25, 0.75, 0.85), Color(0.85, 0.35, 0.7)]
	var neons := [Color(0.3, 1.0, 1.0), Color(1.0, 0.3, 0.75), Color(0.4, 1.0, 0.5), Color(1.0, 0.75, 0.3), Color(0.7, 0.45, 1.0)]
	var main: Color = pick.call(cloth)
	var L := {"skin": pick.call(skins), "main": main, "trim": (pick.call(cloth) as Color).lightened(0.35),
		"legs": main.darkened(0.45), "boots": Color(0.18, 0.13, 0.1), "back": "none", "back_c": main.darkened(0.2),
		"head": pick.call(["hair", "hair", "cap", "kerchief"]), "head_c": pick.call(cloth), "hair": pick.call(hairs),
		"neon": pick.call(neons), "neon2": pick.call(neons), "weapon": "none", "w_c": Color(0.45, 0.4, 0.35),
		"gem": pick.call(neons), "build": r.randi_range(0, 1), "citizen": role,
		"apron": false, "satchel": r.randf() < 0.4, "beard": r.randf() < 0.3, "lamp": r.randf() < 0.35}
	match role:
		"merchant":
			L["head"] = "kerchief"; L["back"] = "coat"; L["satchel"] = true; L["weapon"] = "flask"
		"guard":
			L["head"] = pick.call(["great_helm", "samurai"]); L["back"] = "cape"; L["weapon"] = pick.call(["mace", "katana"])
			L["main"] = Color(0.38, 0.4, 0.48); L["legs"] = Color(0.25, 0.26, 0.32); L["w_c"] = Color(0.6, 0.62, 0.7); L["build"] = 2
		"smith", "blacksmith":
			L["head"] = "dwarf" if role == "blacksmith" else "cap"; L["apron"] = true; L["weapon"] = "hammer"; L["build"] = 2
			L["beard"] = true; L["w_c"] = Color(0.42, 0.42, 0.5); L["neon"] = Color(1.0, 0.6, 0.2)
		"monk":
			L["head"] = "hood"; L["back"] = "robe"; L["weapon"] = "staff"; L["gem"] = Color(0.4, 0.9, 1.0)
		"priestess":
			L["head"] = "hood_white"; L["back"] = "robe"; L["weapon"] = "orbstaff"; L["main"] = Color(0.85, 0.84, 0.8)
			L["head_c"] = Color(0.92, 0.9, 0.86); L["gem"] = Color(1.0, 0.85, 0.4); L["build"] = 1
		"musician":
			L["head"] = "feathers"; L["back"] = "scarf"; L["lamp"] = true
		"elder":
			L["head"] = pick.call(["hood", "hair"]); L["back"] = "robe"; L["weapon"] = "staff"; L["hair"] = Color(0.85, 0.85, 0.88)
			L["beard"] = true; L["build"] = 1; L["w_c"] = Color(0.4, 0.28, 0.18)
		"trainee":
			L["head"] = "samurai"; L["weapon"] = "blade"; L["back"] = "scarf"
		"barkeep":
			L["head"] = "hair"; L["apron"] = true; L["weapon"] = "flask"; L["build"] = 2; L["beard"] = true
		"engineer":
			L["head"] = "goggles"; L["back"] = "coat"; L["weapon"] = "wand"; L["satchel"] = true; L["head_c"] = Color(0.3, 0.3, 0.36)
		"commander":
			L["head"] = "great_helm"; L["back"] = "cloak"; L["weapon"] = "katana"; L["main"] = Color(0.12, 0.12, 0.18)
			L["back_c"] = Color(0.45, 0.08, 0.12); L["trim"] = Color(0.9, 0.7, 0.3); L["build"] = 2
		"gardener":
			L["head"] = "kerchief"; L["apron"] = true; L["weapon"] = "staff"; L["head_c"] = Color(0.3, 0.6, 0.3)
		"kid":
			L["head"] = pick.call(["hair", "cap", "goggles"]); L["build"] = 1; L["beard"] = false
		_:
			L["back"] = pick.call(["none", "none", "scarf", "coat", "cape_short", "cloak"])
			if r.randf() < 0.2:
				L["head"] = pick.call(["hood", "goggles", "witch", "ninja"])
	return L


## Детали горожанина поверх рига: фартук, сумка, фонарик.
static func _citizen_extras(b: Image, e: Image, L: Dictionary, f: int) -> void:
	if _anc.is_empty():
		return
	var cx: float = _anc["cx"]
	var sh: float = _anc["sh"]
	var hip: float = _anc["hip"]
	var tw: float = _anc["tw"]
	if L.get("apron", false):
		var ac := Color(0.42, 0.3, 0.2) if L["citizen"] != "gardener" else Color(0.3, 0.45, 0.25)
		spoly(b, PackedVector2Array([Vector2(cx - tw + 1, sh + 3), Vector2(cx + tw, sh + 3), Vector2(cx + tw + 1, hip + 5), Vector2(cx - tw, hip + 5)]), ac)
		sline(b, int(cx - tw + 1), int(sh + 3), int(cx + 1), int(sh - 1), ac.darkened(0.3))
		srect(b, int(cx - 1), int(hip - 1), 3, 2, ac.lightened(0.2))
	if L.get("satchel", false):
		sline(b, int(cx + tw - 1), int(sh), int(cx - tw), int(hip), Color(0.35, 0.22, 0.14))
		sell(b, cx - tw, hip + 1, 2.4, 2.0, Color(0.45, 0.3, 0.18))
		spx(e, int(cx - tw), int(hip + 1), Color(L["neon"], 0.8))
	if L.get("lamp", false):
		var g: Color = L["gem"]
		var y := hip + 2 + sin(f * 0.8) * 0.6
		sell(e, cx - tw - 1, y, 1.3, 1.6, Color(g, 0.9))
		spx(e, int(cx - tw - 1), int(y), Color.WHITE)
	# Неоновая нашивка на плече у всех — «знак Ковчега»
	spx(e, int(cx + tw - 2), int(sh + 2), Color(L["neon2"], 0.85))


static func hero_frame(fr: Dictionary, state: String, t: float) -> int:
	var n: int = fr["base"].size()
	if n < HERO_FRAMES:
		# старые 8-кадровые спрайты: 0–3 покой, 4–7 ходьба
		return (4 + int(t * 10.0) % 4) if state == "run" else int(t * 4.0) % 4
	var a: Array = HERO_ANIM.get(state, HERO_ANIM["idle"])
	var spd := {"idle": 5.0, "run": 14.0, "attack": 18.0, "cast": 14.0, "hurt": 10.0, "death": 7.0, "dash": 16.0}.get(state, 5.0) as float
	if state == "death":
		return int(a[0]) + mini(int(t * spd), int(a[1]) - 1)   # смерть не зацикливается
	return int(a[0]) + int(t * spd) % int(a[1])


## Кадр анимации по доле (0..1) — для удара/способности/смерти, привязанных ко времени.
static func hero_frame_k(state: String, k: float) -> int:
	var a: Array = HERO_ANIM[state]
	return int(a[0]) + clampi(int(k * float(a[1])), 0, int(a[1]) - 1)


# ---- Масштабирующие примитивы рига (логические координаты × HS) ----
static func srect(im: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	rect(im, int(floor(x * HS)), int(floor(y * HS)), maxi(1, int(ceil(w * HS))), maxi(1, int(ceil(h * HS))), c)


static func sell(im: Image, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	ellipse(im, cx * HS, cy * HS, rx * HS, ry * HS, c)


static func sline(im: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	line(im, int(round(x0 * HS)), int(round(y0 * HS)), int(round(x1 * HS)), int(round(y1 * HS)), c)


static func spoly(im: Image, pts: PackedVector2Array, c: Color) -> void:
	var q := PackedVector2Array()
	for p in pts:
		q.append(p * HS)
	poly(im, q, c)


static func spx(im: Image, x: int, y: int, c: Color) -> void:
	px(im, int(round(x * HS)), int(round(y * HS)), c)


static func slimb(im: Image, a: Vector2, c: Vector2, w: int, col: Color) -> void:
	_limb(im, a * HS, c * HS, int(round(w * HS)), col)


## Кадр героя 48×60: поза рига + смерть/рывок/способность + проходы детализации.
static func _paint_hero48(key: String, b: Image, e: Image, f: int) -> void:
	var L: Dictionary = look(key)
	if f >= 26 and f < 32:
		# Смерть: оседает, падает навзничь, тает
		var k := f - 26
		var tb := blank(48, 60)
		var te := blank(48, 60)
		_paint_hero_rig(key, tb, te, 100 + mini(k, 2))   # 100+ — позы оседания
		_hero_detail(tb, te, L)
		if not _mods.is_empty():
			_paint_mods(tb, te, L, f)
		var ang: float = [0.0, 0.0, -0.25, -0.65, -0.95, -1.05][k]
		var fade: float = [1.0, 1.0, 1.0, 0.95, 0.7, 0.35][k]
		_rot_into(tb, b, ang, Vector2(30, 58), fade)
		_rot_into(te, e, ang, Vector2(30, 58), fade * (1.0 if k < 4 else 0.5))
		return
	_paint_hero_rig(key, b, e, f)
	_hero_detail(b, e, L)
	if not _mods.is_empty():
		_paint_mods(b, e, L, f)
	var st := _rig_state(f)
	if st[0] == "dash":
		# Полосы скорости за спиной
		var nc: Color = L["neon"]
		for i in 5:
			var y := 24 + i * 6 + (f % 2)
			var x0 := 2 + (i % 2) * 3
			line(e, x0, y, x0 + 9 - (i % 3) * 2, y, Color(nc, 0.55 - i * 0.06))
	elif st[0] == "cast" and st[1] >= 1 and st[1] <= 3:
		# Сгусток силы над головой
		var g: Color = L["gem"]
		var r: float = 2.5 + float(st[1]) * 1.6
		ellipse(e, 26.0, 9.0, r, r, Color(g, 0.75))
		ellipse(e, 26.0, 9.0, r * 0.45, r * 0.45, Color(1, 1, 1, 0.95))
		if st[1] == 3:
			for i in 8:
				var a := TAU * i / 8.0
				line(e, int(26 + cos(a) * (r + 1)), int(9 + sin(a) * (r + 1)), int(26 + cos(a) * (r + 5)), int(9 + sin(a) * (r + 5)), Color(g, 0.8))


## Проходы детализации в полном разрешении: свет сверху-слева, тень снизу-справа,
## неоновый контур со стороны города (справа), блики на металле.
static func _hero_detail(b: Image, e: Image, L: Dictionary) -> void:
	var w := b.get_width()
	var h := b.get_height()
	var neon: Color = L["neon"]
	var src := b.duplicate() as Image
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var c := src.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var up := src.get_pixel(x, y - 1).a < 0.5
			var left := src.get_pixel(x - 1, y).a < 0.5
			var right := src.get_pixel(x + 1, y).a < 0.5
			var down := src.get_pixel(x, y + 1).a < 0.5
			if up or left:
				b.set_pixel(x, y, c.lightened(0.16))
			elif down:
				b.set_pixel(x, y, c.darkened(0.22))
			if right and e.get_pixel(x, y).a < 0.3:
				e.set_pixel(x, y, Color(neon, 0.42))
			# Внутренние перепады цвета — мягкая тень складки
			elif not right and not up and not left and not down:
				var r := src.get_pixel(x + 1, y)
				if r.a > 0.5 and (c.get_luminance() - r.get_luminance()) > 0.18:
					b.set_pixel(x + 1, y, r.darkened(0.12))


## Поворот картинки вокруг точки (для падения героя), с прозрачностью.
static func _rot_into(src: Image, dst: Image, ang: float, pivot: Vector2, alpha: float) -> void:
	var w := dst.get_width()
	var h := dst.get_height()
	var ca := cos(-ang)
	var sa := sin(-ang)
	for y in h:
		for x in w:
			var d := Vector2(x, y) - pivot
			var s := pivot + Vector2(d.x * ca - d.y * sa, d.x * sa + d.y * ca)
			var sx := int(round(s.x))
			var sy := int(round(s.y))
			if sx < 0 or sy < 0 or sx >= w or sy >= h:
				continue
			var c := src.get_pixel(sx, sy)
			if c.a > 0.02:
				dst.set_pixel(x, y, Color(c.r, c.g, c.b, c.a * alpha))


## Состояние и номер кадра внутри него.
static func _rig_state(f: int) -> Array:
	if f >= 100:
		return ["fall", f - 100]
	for st in ["idle", "run", "attack", "cast", "hurt", "death", "dash"]:
		var a: Array = HERO_ANIM[st]
		if f >= int(a[0]) and f < int(a[0]) + int(a[1]):
			return [st, f - int(a[0])]
	return ["idle", 0]


## Поза кадра: смещения тела, ноги, руки, наклон.
static func _rig_pose(f: int, melee: bool) -> Dictionary:
	var p := {"bob": 0.0, "lean": 0.0, "fx": 0.0, "fl": 0.0, "bx": 0.0, "bl": 0.0,
		"af": 0.35, "ab": -0.25, "state": "idle", "k": 0, "sway": 0.0, "blink": false}
	var rs := _rig_state(f)
	var st: String = rs[0]
	var k: int = rs[1]
	match st:
		"idle":
			p["bob"] = [0.0, 0.0, 0.5, 1.0, 1.0, 0.5][k]
			p["af"] = 0.35 + [0.0, 0.04, 0.08, 0.1, 0.06, 0.02][k]
			p["ab"] = -0.25 - [0.0, 0.03, 0.06, 0.08, 0.05, 0.02][k]
			p["sway"] = [0.0, 0.5, 1.0, 1.0, 0.5, 0.0][k]
			p["blink"] = k == 5
		"run":
			var ph := TAU * k / 8.0
			p["state"] = "run"
			p["k"] = k
			p["bob"] = -absf(sin(ph)) * 1.5 + 1.0
			p["lean"] = 1.0
			p["fx"] = sin(ph) * 4.0
			p["fl"] = maxf(0.0, cos(ph)) * 2.5
			p["bx"] = -sin(ph) * 4.0
			p["bl"] = maxf(0.0, -cos(ph)) * 2.5
			p["af"] = -sin(ph) * 0.9 + 0.2
			p["ab"] = sin(ph) * 0.9
			p["sway"] = 2.0 + sin(ph)
		"attack":
			p["state"] = "attack"
			var kk: int = [0, 0, 1, 2, 3][k]   # двойной замах, удар, доводка, возврат
			p["k"] = kk
			if melee:
				p["af"] = [-2.2, -2.6, 1.5, 2.2, 0.9][k]
				p["lean"] = [-0.5, -1.0, 2.0, 2.0, 0.5][k]
			else:
				p["af"] = [0.7, 0.9, 1.57, 1.45, 0.9][k]
				p["lean"] = [0.0, -0.5, 1.0, 0.5, 0.0][k]
			p["ab"] = [-0.5, -0.6, 0.3, 0.4, -0.2][k]
			p["fx"] = [0.0, -1.0, 2.0, 2.0, 1.0][k]
			p["bx"] = [0.0, 1.0, -2.0, -2.0, -1.0][k]
			p["sway"] = [0.0, -0.5, 1.0, 2.0, 1.0][k]
		"cast":
			p["state"] = "cast"
			p["k"] = k
			p["af"] = [-0.5, -2.7, -2.9, -2.6, 0.2][k]
			p["ab"] = [-0.6, -2.9, -3.0, -2.8, -0.3][k]
			p["bob"] = [0.0, -0.5, -1.0, -0.5, 0.0][k]
			p["sway"] = [0.0, 1.5, 2.5, 2.0, 0.5][k]
		"hurt":
			p["state"] = "hurt"
			p["k"] = k
			p["lean"] = -2.0 - k
			p["bob"] = 1.0
			p["af"] = -1.2
			p["ab"] = -1.6
			p["fx"] = -1.0
			p["bx"] = -3.0
			p["sway"] = -1.0
			p["blink"] = true
		"fall":
			# Оседание перед падением: колени подгибаются
			p["state"] = "hurt"
			p["k"] = 1
			p["lean"] = -1.0 - k
			p["bob"] = [1.0, 3.0, 5.0][k]
			p["af"] = [-1.0, 0.6, 1.2][k]
			p["ab"] = [-1.4, 0.4, 1.0][k]
			p["fx"] = [0.0, 2.0, 3.0][k]
			p["bx"] = [-2.0, -3.0, -4.0][k]
			p["blink"] = true
		"dash":
			p["state"] = "run"
			p["k"] = k
			p["lean"] = 3.0
			p["bob"] = 1.0
			p["fx"] = 5.0
			p["fl"] = 1.0
			p["bx"] = -5.0
			p["bl"] = 2.0
			p["af"] = -1.1
			p["ab"] = -1.4
			p["sway"] = 3.5
	return p


static func _limb(im: Image, a: Vector2, c: Vector2, w: int, col: Color) -> void:
	for i in w:
		for j in w:
			line(im, int(round(a.x)) + i - w / 2, int(round(a.y)) + j - w / 2, int(round(c.x)) + i - w / 2, int(round(c.y)) + j - w / 2, col)


static func _paint_hero_rig(key: String, b: Image, e: Image, f: int) -> void:
	var L: Dictionary = look(key)
	var weapon: String = L["weapon"]
	var melee := weapon in ["katana", "hammer", "scythe", "blade", "mace"]
	var P := _rig_pose(f, melee)
	var build: int = L["build"]          # 0 — обычный, 1 — худой, 2 — массивный
	var bob: float = P["bob"]
	var lean: float = P["lean"]
	var cx := 15.0 + lean
	var ground := 38.0
	var hip_y := 29.0 + bob
	var sh_y := 19.0 + bob
	var tw := 4.0 + (1.5 if build == 2 else (-0.5 if build == 1 else 0.0))   # полуширина корпуса
	var neon: Color = L["neon"]
	var neon2: Color = L["neon2"]
	var main_c: Color = L["main"]
	var trim: Color = L["trim"]
	var st: String = P["state"]
	var k: int = P["k"]

	# --- Спина: плащ / шарф / колчан / роба ---
	var back: String = L["back"]
	var bc: Color = L["back_c"]
	var sway: float = P["sway"]
	match back:
		"cloak", "cape", "robe", "coat":
			var low := ground - (1.0 if back == "robe" else (4.0 if back == "coat" else 3.0))
			spoly(b, PackedVector2Array([Vector2(cx - tw + 1, sh_y - 1), Vector2(cx + tw - 1, sh_y - 1),
				Vector2(cx + tw - 2 - sway, low), Vector2(cx - tw - 4 - sway * 1.5, low + 1)]), bc)
			sline(b, int(cx - tw - 3 - sway), int(low), int(cx - 1), int(sh_y + 2), bc.lightened(0.15))
			if back == "cloak":
				sline(e, int(cx - tw - 4 - sway * 1.5), int(low + 1), int(cx + tw - 2 - sway), int(low), Color(neon2, 0.9))
		"cape_short":
			spoly(b, PackedVector2Array([Vector2(cx - tw, sh_y - 1), Vector2(cx + tw - 2, sh_y - 1),
				Vector2(cx - 1 - sway, hip_y + 1), Vector2(cx - tw - 3 - sway, hip_y)]), bc)
			sline(e, int(cx - tw - 3 - sway), int(hip_y), int(cx - 1 - sway), int(hip_y + 1), Color(neon, 0.8))
		"scarf":
			spoly(b, PackedVector2Array([Vector2(cx - 1, sh_y - 2), Vector2(cx - 8 - sway * 2.0, sh_y - 1 + sway * 0.5),
				Vector2(cx - 10 - sway * 2.0, sh_y + 3 - sway * 0.5), Vector2(cx - 1, sh_y + 1)]), bc)
			spx(b, int(cx - 10 - sway * 2.0), int(sh_y + 4), bc.darkened(0.2))
		"quiver":
			srect(b, int(cx - tw - 2), int(sh_y - 2), 3, 10, bc)
			for i in 3:
				sline(b, int(cx - tw - 2) + i, int(sh_y - 2), int(cx - tw - 3) + i, int(sh_y - 6), Color(0.85, 0.85, 0.8))
				spx(e, int(cx - tw - 3) + i, int(sh_y - 6), neon)

	# --- Задняя нога и рука ---
	var legs_c: Color = L["legs"]
	var boots_c: Color = L["boots"]
	var lw := 3 if build == 2 else 2
	var hb := Vector2(cx - 1.5, hip_y)
	var fb := Vector2(cx - 2 + float(P["bx"]), ground - float(P["bl"]))
	slimb(b, hb, fb, lw, legs_c.darkened(0.25))
	srect(b, int(fb.x) - 1, int(fb.y) - 1, 4, 2, boots_c.darkened(0.2))
	var sb := Vector2(cx - tw + 1, sh_y + 1)
	var ab: float = P["ab"]
	var hand_b := sb + Vector2(sin(ab), cos(ab)) * 7.0
	slimb(b, sb, hand_b, 2, main_c.darkened(0.3))
	spx(b, int(hand_b.x), int(hand_b.y), Color(L["skin"]).darkened(0.2))

	# --- Корпус ---
	spoly(b, PackedVector2Array([Vector2(cx - tw, sh_y), Vector2(cx + tw, sh_y),
		Vector2(cx + tw - 0.5, hip_y + 1), Vector2(cx - tw + 0.5, hip_y + 1)]), main_c)
	# юбка / полы одежды
	if back in ["robe", "coat", "cloak"] or key in ["kira", "iris", "mora", "zephyr"]:
		spoly(b, PackedVector2Array([Vector2(cx - tw, hip_y - 1), Vector2(cx + tw, hip_y - 1),
			Vector2(cx + tw + 1 + sway * 0.3, hip_y + 5), Vector2(cx - tw - 1 + sway * 0.3, hip_y + 5)]), main_c.darkened(0.1))
	# пояс и пряжка
	srect(b, int(cx - tw), int(hip_y - 2), int(tw * 2), 2, trim.darkened(0.2))
	spx(b, int(cx), int(hip_y - 2), trim.lightened(0.3))
	# нагрудник / детали
	match key:
		"rin", "orm", "kai":
			srect(b, int(cx - tw + 1), int(sh_y + 2), int(tw * 2 - 2), 2, Color(main_c).lightened(0.25))
			srect(b, int(cx - tw + 1), int(sh_y + 6), int(tw * 2 - 2), 1, trim)
		"bram":
			srect(b, int(cx - 2), int(sh_y + 2), 5, int(hip_y - sh_y - 3), Color(0.35, 0.22, 0.14))   # фартук
			spx(e, int(cx), int(sh_y + 5), neon)
		"iris":
			for i in 3:
				srect(b, int(cx - tw + 1 + i * 3), int(hip_y - 4), 2, 3, Color(0.3, 0.35, 0.3))
				spx(e, int(cx - tw + 1 + i * 3), int(hip_y - 3), [neon, neon2, Color(0.4, 0.8, 1.0)][i])
		"mora":
			for y in range(int(sh_y + 2), int(hip_y), 3):
				spx(e, int(cx - 1), y, Color(neon, 0.8))
				spx(e, int(cx + 1), y + 1, Color(neon2, 0.7))
		"hero":
			srect(b, int(cx - tw + 1), int(sh_y + 4), int(tw * 2 - 2), 1, trim)
			if f % 2 == 0:
				spx(e, int(cx - 1), int(sh_y + 7), Color(neon, 0.9))
		_:
			srect(b, int(cx - tw + 1), int(sh_y + 4), int(tw * 2 - 2), 1, trim)
	# неоновая кайма корпуса
	sline(e, int(cx + tw - 1), int(sh_y + 1), int(cx + tw - 1), int(hip_y - 3), Color(neon, 0.75))
	# наплечник
	sell(b, cx + tw - 1.5, sh_y + 0.5, 2.6 + (1.0 if build == 2 else 0.0), 1.8, trim if key in ["orm", "bram"] else main_c.lightened(0.2))

	# --- Передняя нога ---
	var hf := Vector2(cx + 1.5, hip_y)
	var ff := Vector2(cx + 2 + float(P["fx"]), ground - float(P["fl"]))
	slimb(b, hf, ff, lw, legs_c)
	srect(b, int(ff.x) - 1, int(ff.y) - 1, 4, 2, boots_c)
	spx(b, int(ff.x) + 2, int(ff.y), boots_c.lightened(0.2))

	# --- Голова ---
	var hx := cx + 1.0 + (0.5 if st == "attack" and k == 1 else 0.0)
	var hy := sh_y - 5.0
	var skin: Color = L["skin"]
	var head: String = L["head"]
	var hc: Color = L["head_c"]
	var blink: bool = P["blink"]
	match head:
		"hood":
			spoly(b, PackedVector2Array([Vector2(hx - 4, hy - 2), Vector2(hx - 7 - sway, hy + 4), Vector2(hx - 2, hy + 3)]), hc)
			sell(b, hx, hy, 5.2, 5.0, hc)
			sell(b, hx + 1.5, hy + 1.0, 3.0, 2.8, skin)
			if not blink:
				srect(e, int(hx), int(hy + 1), 4, 1, neon)
				spx(e, int(hx + 3), int(hy + 1), Color.WHITE)
		"samurai":
			sell(b, hx, hy, 4.6, 4.6, skin)
			srect(b, int(hx - 5), int(hy - 5), 10, 3, hc)
			sell(b, hx - 1, hy - 1, 4.8, 3.4, hc.darkened(0.2))
			spoly(b, PackedVector2Array([Vector2(hx + 1, hy - 5), Vector2(hx + 6, hy - 9), Vector2(hx + 4, hy - 4)]), trim)
			srect(b, int(hx - 1), int(hy + 2), 6, 2, hc)
			if not blink:
				srect(e, int(hx), int(hy), 4, 1, neon)
		"dwarf":
			sell(b, hx, hy + 0.5, 4.8, 4.6, skin)
			sell(b, hx - 0.5, hy - 2.5, 5.2, 3.0, hc)
			srect(b, int(hx - 5), int(hy - 2), 11, 1, hc.darkened(0.25))
			for i in 2:
				spx(b, int(hx - 5 + i * 10), int(hy - 5), Color(0.85, 0.8, 0.7))
			spoly(b, PackedVector2Array([Vector2(hx - 2, hy + 1), Vector2(hx + 5, hy + 1), Vector2(hx + 3, hy + 8 + bob * 0.5), Vector2(hx - 1, hy + 7)]), L["hair"])
			if not blink:
				spx(e, int(hx + 2), int(hy), neon)
			spx(e, int(hx), int(hy - 3), Color(neon2, 0.9))
		"witch":
			sell(b, hx, hy + 0.5, 4.4, 4.4, skin)
			spoly(b, PackedVector2Array([Vector2(hx - 4, hy + 2), Vector2(hx - 6 - sway, hy + 7), Vector2(hx - 2, hy + 4)]), L["hair"])
			srect(b, int(hx - 7), int(hy - 3), 14, 2, hc)
			spoly(b, PackedVector2Array([Vector2(hx - 4, hy - 3), Vector2(hx + 4, hy - 3), Vector2(hx - 3 - sway, hy - 12)]), hc)
			sline(e, int(hx - 4), int(hy - 4), int(hx + 3), int(hy - 4), neon)
			if not blink:
				spx(e, int(hx + 2), int(hy + 1), neon)
		"hood_white":
			sell(b, hx, hy, 5.0, 5.0, hc)
			sell(b, hx + 1.5, hy + 1.0, 3.0, 3.0, skin)
			spoly(b, PackedVector2Array([Vector2(hx - 4, hy), Vector2(hx - 7 - sway, hy + 8), Vector2(hx - 2, hy + 5)]), L["hair"])
			spoly(b, PackedVector2Array([Vector2(hx + 3, hy - 3), Vector2(hx + 6, hy - 6), Vector2(hx + 5, hy - 2)]), hc)
			if not blink:
				srect(e, int(hx + 1), int(hy + 1), 3, 1, neon)
		"great_helm":
			srect(b, int(hx - 4), int(hy - 4), 9, 9, hc)
			srect(b, int(hx - 4), int(hy - 5), 9, 1, hc.lightened(0.2))
			srect(b, int(hx), int(hy - 1), 5, 1, Color(0.1, 0.1, 0.12))
			if not blink:
				srect(e, int(hx + 1), int(hy - 1), 4, 1, neon)
			for i in 6:
				var a := TAU * i / 6.0 + f * 0.25
				spx(e, int(hx + cos(a) * 7.0), int(hy - 7 + sin(a) * 2.0), Color(neon, 0.85))
		"skull":
			sell(b, hx - 0.5, hy - 0.5, 5.4, 5.2, hc)
			sell(b, hx + 1, hy + 0.5, 3.0, 3.0, skin)
			spx(b, int(hx + 2), int(hy + 3), Color(0.2, 0.2, 0.2))
			if not blink:
				spx(e, int(hx), int(hy), neon)
				spx(e, int(hx + 2), int(hy), neon)
		"feathers":
			sell(b, hx, hy + 0.5, 4.2, 4.2, skin)
			srect(b, int(hx - 4), int(hy - 1), 9, 2, hc)
			if not blink:
				srect(e, int(hx - 1), int(hy), 5, 1, neon)
			var fc := [Color(0.9, 0.3, 0.3), Color(0.3, 0.6, 1.0), Color(0.9, 0.85, 0.3), Color(0.3, 0.9, 0.5), Color(0.9, 0.9, 0.9)]
			for i in 5:
				sline(b, int(hx - 3 + i * 2), int(hy - 3), int(hx - 5 + i * 3 - sway), int(hy - 9 - (i % 2) * 2), fc[i])
		"goggles":
			sell(b, hx, hy + 0.5, 4.4, 4.4, skin)
			sell(b, hx - 1, hy - 2.5, 5.0, 3.0, L["hair"])
			spoly(b, PackedVector2Array([Vector2(hx - 4, hy - 1), Vector2(hx - 7 - sway, hy + 4), Vector2(hx - 3, hy + 3)]), L["hair"])
			srect(b, int(hx - 2), int(hy - 1), 7, 2, hc)
			spx(e, int(hx), int(hy - 1), neon)
			spx(e, int(hx + 3), int(hy - 1), neon)
		"ninja":
			sell(b, hx, hy, 4.4, 4.4, hc)
			srect(b, int(hx - 4), int(hy - 1), 9, 1, Color(L["trim"]))
			sline(b, int(hx - 4), int(hy - 1), int(hx - 8 - sway), int(hy - 2 + sway), L["trim"])
			if not blink:
				srect(e, int(hx), int(hy + 1), 4, 1, neon)
				spx(e, int(hx + 3), int(hy + 1), neon2)
		"hair":
			sell(b, hx, hy + 0.5, 4.4, 4.4, skin)
			sell(b, hx - 1, hy - 2.0, 5.0, 3.2, L["hair"])
			spoly(b, PackedVector2Array([Vector2(hx - 4, hy - 1), Vector2(hx - 5 - sway * 0.5, hy + 4), Vector2(hx - 2, hy + 2)]), L["hair"])
			if L.get("beard", false):
				spoly(b, PackedVector2Array([Vector2(hx - 1, hy + 2), Vector2(hx + 5, hy + 2), Vector2(hx + 3, hy + 6), Vector2(hx, hy + 5)]), L["hair"].lightened(0.1))
			if not blink:
				spx(b, int(hx + 2), int(hy), Color(0.1, 0.08, 0.12))
				spx(e, int(hx + 3), int(hy), Color(neon, 0.5))
		"cap":
			sell(b, hx, hy + 0.5, 4.4, 4.4, skin)
			sell(b, hx - 0.5, hy - 2.5, 4.8, 2.6, hc)
			srect(b, int(hx), int(hy - 2), 7, 1, hc.darkened(0.25))
			spx(e, int(hx - 1), int(hy - 4), neon)
			if L.get("beard", false):
				spoly(b, PackedVector2Array([Vector2(hx - 1, hy + 2), Vector2(hx + 5, hy + 2), Vector2(hx + 2, hy + 6)]), L["hair"])
			if not blink:
				spx(b, int(hx + 2), int(hy), Color(0.1, 0.08, 0.12))
		"kerchief":
			sell(b, hx, hy + 0.5, 4.4, 4.4, skin)
			sell(b, hx - 0.5, hy - 1.8, 5.0, 3.0, hc)
			spoly(b, PackedVector2Array([Vector2(hx - 4, hy - 1), Vector2(hx - 8 - sway, hy + 1), Vector2(hx - 4, hy + 2)]), hc.darkened(0.15))
			for i in 3:
				spx(b, int(hx - 3 + i * 2), int(hy - 3), hc.lightened(0.35))
			if not blink:
				spx(b, int(hx + 2), int(hy), Color(0.1, 0.08, 0.12))
	if st == "hurt":
		# Зажмуренные глаза-«крестики»
		spx(b, int(hx + 1), int(hy), Color(0.95, 0.95, 1.0))
		spx(b, int(hx + 3), int(hy), Color(0.95, 0.95, 1.0))

	# --- Передняя рука и оружие ---
	var sf := Vector2(cx + tw - 1, sh_y + 1)
	var af: float = P["af"]
	var dir := Vector2(sin(af), cos(af))
	var hand := sf + dir * 7.0
	slimb(b, sf, hand, 2 if build != 2 else 3, main_c.lightened(0.05))
	srect(b, int(hand.x), int(hand.y), 2, 2, skin if key not in ["kai", "orm"] else main_c.lightened(0.3))
	_hero_weapon(weapon, L, b, e, hand, dir, st, k, f, hand_b)
	_anc = {"cx": cx, "sh": sh_y, "hip": hip_y, "tw": tw, "hand": hand, "tip": _weapon_tip(weapon, hand, dir, st),
		"hx": hx, "hy": hy, "ff": ff, "fb": fb, "sway": sway, "st": st}


static func _hero_weapon(weapon: String, L: Dictionary, b: Image, e: Image, h: Vector2, dir: Vector2, st: String, k: int, f: int, hb := Vector2.ZERO) -> void:
	var wc: Color = L["w_c"]
	var gem: Color = L["gem"]
	var neon: Color = L["neon"]
	var up := Vector2(0, -1)
	var attacking := st == "attack"
	var strike := attacking and (k == 1 or k == 2)
	match weapon:
		"staff", "orbstaff":
			var d := dir if attacking else up
			var a := h - d * 7.0
			var t := h + d * (12.0 if attacking else 13.0)
			if not attacking:
				a = Vector2(h.x + 1, 38)
				t = Vector2(h.x + 1, h.y - 13)
			sline(b, int(a.x), int(a.y), int(t.x), int(t.y), wc)
			sline(b, int(a.x) + 1, int(a.y), int(t.x) + 1, int(t.y), wc.darkened(0.3))
			var cb: int = [0, -1, -1, 0][f % 4]
			if weapon == "staff":
				spx(b, int(t.x) - 1, int(t.y) + 1, wc)
				spx(b, int(t.x) + 2, int(t.y) + 1, wc)
				sell(e, t.x + 0.5, t.y - 1.5 + cb, 2.0, 2.8, gem)
				spx(e, int(t.x), int(t.y) - 2 + cb, Color(1, 0.9, 1))
			else:
				sell(e, t.x + 0.5, t.y - 2 + cb, 2.6, 2.6, Color(gem, 0.85))
				spx(e, int(t.x) + (f % 2), int(t.y) - 3 + cb, Color.WHITE)
				for i in 3:
					var ang := TAU * i / 3.0 + f * 0.8
					spx(e, int(t.x + cos(ang) * 4.0), int(t.y - 2 + sin(ang) * 2.0), Color(gem, 0.7))
			if strike:
				sell(e, t.x + d.x * 3.0, t.y + d.y * 3.0, 3.5 - k, 3.5 - k, Color(gem, 0.9))
		"katana", "blade":
			var ln := 13.0 if weapon == "katana" else 9.0
			if attacking:
				var t := h + dir * ln
				sline(b, int(h.x), int(h.y), int(t.x), int(t.y), wc)
				sline(e, int(h.x + dir.x * 3), int(h.y + dir.y * 3), int(t.x), int(t.y), Color(neon, 0.85))
				srect(b, int(h.x) - 1, int(h.y) - 1, 2, 2, L["trim"])
				if k == 1:
					# Дуга удара
					for i in 7:
						var ang := -1.2 + i * 0.4
						var pp := h + Vector2(sin(ang + 0.6), -cos(ang + 0.6)) * (ln + 2.0)
						spx(e, int(pp.x), int(pp.y), Color(neon, 0.9 - i * 0.08))
			else:
				# В ножнах / за спиной по диагонали
				sline(b, int(h.x) - 8, int(h.y) + 2, int(h.x) + 3, int(h.y) - 10, wc.darkened(0.2))
				srect(b, int(h.x) - 9, int(h.y) + 2, 2, 2, L["trim"])
				if weapon == "blade":
					spx(e, int(h.x) + 3, int(h.y) - 10, neon)
		"hammer":
			var d := dir if attacking else Vector2(0.35, -1).normalized()
			var t := h + d * 10.0
			slimb(b, h - d * 3.0, t, 2, Color(0.45, 0.3, 0.18))
			var side := Vector2(-d.y, d.x)
			spoly(b, PackedVector2Array([t + side * 4 - d, t + side * 4 + d * 3, t - side * 4 + d * 3, t - side * 4 - d]), wc)
			spx(e, int(t.x + d.x), int(t.y + d.y), L["neon"])
			spx(e, int(t.x + side.x * 2), int(t.y + side.y * 2), L["neon2"])
			if strike and k == 1:
				for i in 5:
					spx(e, int(t.x) - 2 + i, 38, Color(L["neon"], 0.8))
		"mace":
			# щит на задней руке рисуем поверх корпуса
			# Щит — на задней руке, слева от корпуса
			var s0 := hb + Vector2(-3, -4)
			spoly(b, PackedVector2Array([s0 + Vector2(-3, -4), s0 + Vector2(3, -4), s0 + Vector2(3, 3), s0 + Vector2(0, 6), s0 + Vector2(-3, 3)]), wc)
			sline(e, int(s0.x), int(s0.y - 3), int(s0.x), int(s0.y + 4), Color(neon, 0.8))
			var d := dir if attacking else Vector2(0.2, -1).normalized()
			var t := h + d * 9.0
			slimb(b, h, t, 2, Color(0.5, 0.5, 0.58))
			sell(b, t.x, t.y, 2.5, 2.5, L["trim"])
			spx(e, int(t.x), int(t.y), neon)
		"scythe":
			var d := dir if attacking else up
			var a := h - d * 8.0
			var t := h + d * 12.0
			if not attacking:
				a = Vector2(h.x + 1, 38)
				t = Vector2(h.x + 1, h.y - 14)
			sline(b, int(a.x), int(a.y), int(t.x), int(t.y), wc)
			var side := Vector2(-d.y, d.x) if attacking else Vector2(-1, 0)
			spoly(e, PackedVector2Array([t, t + side * 8.0 + Vector2(0, 2), t + side * 5.0 + Vector2(0, 3), t + Vector2(0, 2)]), Color(L["neon"], 0.9))
		"wand":
			var d := dir if attacking else Vector2(0.4, -1).normalized()
			var t := h + d * 6.0
			sline(b, int(h.x), int(h.y), int(t.x), int(t.y), wc)
			sell(e, t.x, t.y, 1.5, 1.5, gem)
			if strike:
				for i in 4:
					spx(e, int(t.x + d.x * (3 + i * 2)), int(t.y + d.y * (3 + i * 2)), Color(gem, 0.9 - i * 0.2))
			# голо-дрон над плечом
			var dy: int = [0, -1, -1, 0][f % 4]
			srect(b, int(h.x) - 9, int(h.y) - 15 + dy, 4, 2, Color(0.3, 0.32, 0.4))
			spx(e, int(h.x) - 8, int(h.y) - 14 + dy, gem)
		"bow":
			var d := Vector2(1, 0)
			var side := Vector2(-d.y, d.x)
			var c := h + d * 2.0
			var tip_a := c - side * 8.0
			var tip_b := c + side * 8.0
			sline(b, int(c.x), int(c.y), int(tip_a.x), int(tip_a.y), wc)
			sline(b, int(c.x), int(c.y), int(tip_b.x), int(tip_b.y), wc)
			var pull := (3.0 if (attacking and k == 0) else (1.0 if attacking and k == 3 else 0.0))
			var mid := c - d * (2.0 + pull)
			sline(e, int(tip_a.x), int(tip_a.y), int(mid.x), int(mid.y), Color(neon, 0.8))
			sline(e, int(mid.x), int(mid.y), int(tip_b.x), int(tip_b.y), Color(neon, 0.8))
			if attacking and k <= 1:
				sline(e, int(mid.x), int(mid.y), int(c.x + d.x * 8.0), int(c.y + d.y * 8.0), Color(1, 1, 1, 0.9))
		"flask":
			var d := dir if attacking else Vector2(0.3, 1).normalized()
			var t := h + d * 2.0
			sell(b, t.x, t.y + 1, 2.4, 2.6, Color(0.6, 0.8, 0.9, 0.9))
			srect(b, int(t.x) - 1, int(t.y) - 3, 2, 2, Color(0.5, 0.4, 0.3))
			sell(e, t.x, t.y + 1.5, 1.6, 1.6, gem)
			if strike:
				for i in 3:
					spx(e, int(t.x + d.x * (4 + i * 2)), int(t.y + d.y * (4 + i * 2) - i), Color(gem, 0.8))


# ================= Враги: кибер-твари 1.5×, 12 кадров =================
# Помесь чудовищ и кибернетики: оптические импланты, металлические рёбра,
# кабели, поршни, светящиеся трубки. Кадры: 0–5 ходьба, 6–9 атака, 10–11 урон.

const BEAST_KEYS := ["imp", "bat", "ghoul", "wraith", "brute", "goblin", "slime", "slimelet", "spider",
	"spiderling", "caster", "bomber", "knight"]
const BEAST_ANIM := {"walk": [0, 6], "attack": [6, 4], "hurt": [10, 2]}
const FLESH := Color(0.36, 0.22, 0.34)
const FLESH2 := Color(0.28, 0.32, 0.26)
const METAL := Color(0.42, 0.45, 0.55)
const METAL_D := Color(0.24, 0.25, 0.32)
const RED_EYE := Color(1.0, 0.18, 0.15)


static func beast_frame(state: String, t: float, fps: float) -> int:
	var a: Array = BEAST_ANIM[state]
	return int(a[0]) + int(t * fps) % int(a[1])


static func _beast_pose(f: int) -> Dictionary:
	if f < 6:
		var ph := TAU * f / 6.0
		return {"st": "walk", "ph": ph, "s": sin(ph), "c": cos(ph), "a": 0.0, "h": 0.0}
	if f < 10:
		return {"st": "attack", "ph": 0.0, "s": 0.0, "c": 1.0, "a": [-0.6, 1.0, 0.7, 0.2][f - 6], "h": 0.0}
	return {"st": "hurt", "ph": 0.0, "s": 0.0, "c": 1.0, "a": 0.0, "h": [1.0, 0.6][f - 10]}


static func _optic(e: Image, x: float, y: float, r: float, c: Color) -> void:
	ellipse(e, x, y, r + 0.6, r + 0.6, Color(c, 0.35))
	ellipse(e, x, y, r, r, c)
	px(e, int(x), int(y), Color(1, 1, 0.9))


static func _leg2(b: Image, hip: Vector2, foot: Vector2, bend: float, w: int, c: Color) -> Vector2:
	var mid := (hip + foot) * 0.5
	var nrm := (foot - hip).orthogonal().normalized()
	var knee := mid + nrm * bend
	_limb(b, hip, knee, w, c)
	_limb(b, knee, foot, maxi(1, w - 1), c.darkened(0.1))
	return knee


static func _ribs(b: Image, x0: int, y0: int, n: int, w: int, c: Color) -> void:
	for i in n:
		line(b, x0, y0 + i * 2, x0 + w, y0 + i * 2 + 1, c)


static func _paint_beast(key: String, b: Image, e: Image, f: int) -> void:
	var P := _beast_pose(f)
	var s: float = P["s"]
	var a: float = P["a"]
	var hu: float = P["h"]
	var att: bool = P["st"] == "attack"
	match key:
		"imp":
			# Кибер-бес: рога, жвалы-челюсть из металла, имплант-глаз, крылья-платы, хвост-кабель
			var by := 18.5 + s * 1.2 - hu
			var cx := 14.0 + a * 2.0 - hu * 2.0
			var wing := 4.0 + s * 3.0
			for d in [-1.0, 1.0]:
				poly(b, PackedVector2Array([Vector2(cx + d * 3, by - 3), Vector2(cx + d * 13, by - 6 - wing), Vector2(cx + d * 11, by + 2), Vector2(cx + d * 6, by + 3)]), Color(0.25, 0.12, 0.22))
				line(e, int(cx + d * 4), int(by - 2), int(cx + d * 12), int(by - 5 - wing), Color(1.0, 0.3, 0.5, 0.7))
			sline_tail(b, e, Vector2(cx - 4, by + 4), s)
			ellipse(b, cx, by, 6.0, 6.5, FLESH)
			_ribs(b, int(cx - 3), int(by - 1), 3, 5, METAL_D)
			ellipse(b, cx + 2, by - 7, 5.0, 4.5, FLESH.lightened(0.08))
			poly(b, PackedVector2Array([Vector2(cx - 2, by - 10), Vector2(cx - 5, by - 16), Vector2(cx, by - 11)]), Color(0.75, 0.7, 0.6))
			poly(b, PackedVector2Array([Vector2(cx + 4, by - 10), Vector2(cx + 7, by - 16), Vector2(cx + 6, by - 10)]), Color(0.75, 0.7, 0.6))
			rect(b, int(cx + 1), int(by - 5), 6, 3, METAL)
			for i in 3:
				px(b, int(cx + 2 + i * 2), int(by - 3), Color(0.9, 0.9, 0.85))
			_optic(e, cx + 4, by - 8, 1.4, RED_EYE)
			px(e, int(cx), int(by - 8), Color(1.0, 0.5, 0.2))
			for d in [-1.0, 1.0]:
				_limb(b, Vector2(cx + d * 4, by + 4), Vector2(cx + d * 5 + a * 3, by + 10 - a * 2), 2, FLESH.darkened(0.2))
			if att and a > 0.5:
				line(e, int(cx + 7), int(by + 1), int(cx + 12), int(by + 6), Color(1.0, 0.5, 0.3, 0.9))
		"bat":
			# Нетопырь-дрон: крылья на металлических спицах, объектив вместо морды
			var cx := 19.0
			var cy := 11.0 - hu
			var fl := s * 6.0
			for d in [-1.0, 1.0]:
				var tip := Vector2(cx + d * 18, cy - 2 - fl)
				var mid := Vector2(cx + d * 10, cy - 5 - fl * 0.6)
				poly(b, PackedVector2Array([Vector2(cx + d * 3, cy - 2), mid, tip, Vector2(cx + d * 14, cy + 4 - fl * 0.3), Vector2(cx + d * 8, cy + 3)]), Color(0.2, 0.1, 0.2))
				_limb(b, Vector2(cx + d * 3, cy - 2), mid, 1, METAL)
				_limb(b, mid, tip, 1, METAL)
				for i in 3:
					var q := mid.lerp(Vector2(cx + d * (9 + i * 3), cy + 3), 0.9)
					line(b, int(mid.x), int(mid.y), int(q.x), int(q.y), METAL_D)
				px(e, int(tip.x), int(tip.y), Color(1.0, 0.3, 0.3))
			ellipse(b, cx, cy + 1, 4.5, 5.0, FLESH.darkened(0.1))
			ellipse(b, cx, cy - 3, 3.5, 3.0, METAL)
			poly(b, PackedVector2Array([Vector2(cx - 3, cy - 5), Vector2(cx - 4, cy - 9), Vector2(cx - 1, cy - 6)]), FLESH)
			poly(b, PackedVector2Array([Vector2(cx + 3, cy - 5), Vector2(cx + 4, cy - 9), Vector2(cx + 1, cy - 6)]), FLESH)
			_optic(e, cx, cy - 3, 1.6 + (0.6 if att else 0.0), RED_EYE)
			for i in 2:
				px(b, int(cx - 1 + i * 2), int(cy + 5), Color(0.9, 0.9, 0.8))
		"ghoul":
			# Гуль-киборг: сгорбленный, металлические рёбра наружу, трубки, когти-лезвия
			var cx := 14.0 + a * 2.0 - hu * 2.0
			var by := 22.0 + absf(s) * 1.0
			_leg2(b, Vector2(cx - 2, by + 6), Vector2(cx - 4 - s * 3, 39), 2.0, 3, FLESH2.darkened(0.25))
			_leg2(b, Vector2(cx + 2, by + 6), Vector2(cx + 3 + s * 3, 39), 2.0, 3, FLESH2)
			poly(b, PackedVector2Array([Vector2(cx - 6, by - 6), Vector2(cx + 6, by - 9), Vector2(cx + 7, by + 7), Vector2(cx - 5, by + 7)]), FLESH2)
			_ribs(b, int(cx - 3), int(by - 4), 5, 7, METAL.lightened(0.1))
			for i in 2:
				line(e, int(cx - 5 + i * 3), int(by - 7), int(cx - 7 + i * 3), int(by + 5), Color(0.4, 1.0, 0.5, 0.7))
			ellipse(b, cx + 6, by - 11, 4.5, 4.0, FLESH2.lightened(0.1))
			rect(b, int(cx + 6), int(by - 9), 5, 3, METAL)
			for i in 3:
				px(b, int(cx + 6 + i * 2), int(by - 7), Color(0.85, 0.85, 0.75))
			_optic(e, cx + 8, by - 12, 1.2, Color(0.5, 1.0, 0.4))
			var arm_a := -0.4 + s * 0.5 + a * 1.4
			var hand := Vector2(cx + 5, by - 4) + Vector2(sin(arm_a + 1.2), cos(arm_a + 1.2)) * 9.0
			_limb(b, Vector2(cx + 5, by - 4), hand, 2, FLESH2.darkened(0.1))
			for i in 3:
				line(b, int(hand.x), int(hand.y), int(hand.x + 3 + i), int(hand.y + 2 - i * 2), Color(0.8, 0.82, 0.9))
			if att and a > 0.5:
				for i in 3:
					line(e, int(hand.x + 2), int(hand.y - 4 + i * 3), int(hand.x + 7), int(hand.y - 2 + i * 3), Color(0.6, 1.0, 0.6, 0.85))
		"wraith":
			# Призрак кода: рваный саван, лицо из битых пикселей, цепи с данными
			var cx := 15.0 + a * 2.0
			var cy := 16.0 + s * 1.5 - hu
			var shroud := Color(0.25, 0.32, 0.42, 0.85)
			poly(b, PackedVector2Array([Vector2(cx - 6, cy - 6), Vector2(cx + 6, cy - 6), Vector2(cx + 10, cy + 18), Vector2(cx + 4, cy + 14 + s * 2), Vector2(cx, cy + 20), Vector2(cx - 4, cy + 14 - s * 2), Vector2(cx - 10, cy + 18)]), shroud)
			ellipse(b, cx, cy - 7, 6.0, 6.5, shroud.lightened(0.1))
			ellipse(b, cx + 1, cy - 6, 3.8, 4.5, Color(0.04, 0.03, 0.08))
			for i in 6:
				var gx := int(cx - 2 + (i * 37 + f * 11) % 5)
				var gy := int(cy - 9 + (i * 23 + f * 7) % 6)
				px(e, gx, gy, Color(1.0, 0.2, 0.3) if i % 2 == 0 else Color(0.4, 0.9, 1.0))
			for d in [-1.0, 1.0]:
				var hand := Vector2(cx + d * 9 + a * 4, cy + 2 - a * 3)
				line(b, int(cx + d * 4), int(cy - 2), int(hand.x), int(hand.y), shroud)
				for i in 4:
					px(e, int(hand.x - d * i), int(hand.y + 3 + i * 2), Color(0.5, 0.9, 1.0, 0.8 - i * 0.15))
		"brute":
			# Огр-механоид: гидравлические плечи, руки-поршни, череп-маска, шланги
			var cx := 27.0 + a * 3.0 - hu * 2.0
			var by := 30.0 + absf(s) * 1.0
			_leg2(b, Vector2(cx - 6, by + 10), Vector2(cx - 8 - s * 3, 55), 2.0, 6, METAL_D)
			_leg2(b, Vector2(cx + 6, by + 10), Vector2(cx + 8 + s * 3, 55), 2.0, 6, METAL_D.lightened(0.1))
			rect(b, int(cx - 11 - s * 3), 52, 7, 3, METAL)
			rect(b, int(cx + 5 + s * 3), 52, 7, 3, METAL)
			ellipse(b, cx, by, 15.0, 14.0, FLESH.lightened(0.05))
			ellipse(b, cx + 1, by + 3, 10.0, 8.0, FLESH.darkened(0.1))
			rect(b, int(cx - 6), int(by - 4), 12, 9, METAL)
			for i in 3:
				rect(b, int(cx - 5 + i * 4), int(by - 3), 2, 7, METAL_D)
			_optic(e, cx, by + 1, 2.0, Color(1.0, 0.55, 0.15))
			for d in [-1.0, 1.0]:
				ellipse(b, cx + d * 14, by - 10, 6.0, 5.0, METAL)
				px(b, int(cx + d * 14), int(by - 13), METAL.lightened(0.4))
				var arm := Vector2(cx + d * 18 + (a * 6.0 if d > 0 else 0.0), by + 10 - (a * 10.0 if d > 0 else 0.0))
				_limb(b, Vector2(cx + d * 15, by - 7), arm, 6, FLESH)
				_limb(b, arm, arm + Vector2(d * 2, 6), 7, METAL)
				line(e, int(cx + d * 12), int(by - 12), int(arm.x), int(arm.y), Color(1.0, 0.55, 0.15, 0.6))
			ellipse(b, cx + 2, by - 17, 7.0, 6.0, Color(0.85, 0.82, 0.75))
			rect(b, int(cx - 3), int(by - 14), 10, 3, METAL_D)
			_optic(e, cx + 1, by - 18, 1.3, RED_EYE)
			_optic(e, cx + 5, by - 18, 1.3, RED_EYE)
			if att and a > 0.5:
				for i in 7:
					px(e, int(cx + 18 + i), 54 - (i % 2), Color(1.0, 0.6, 0.2, 0.9))
		"goblin":
			# Гоблин-падальщик: очки-оптика, пила вместо ножа, рюкзак с антенной
			var cx := 11.0 + a * 2.0 - hu * 2.0
			var by := 14.0 + absf(s) * 1.0
			_leg2(b, Vector2(cx - 2, by + 4), Vector2(cx - 3 - s * 3, 23), 1.0, 2, Color(0.25, 0.3, 0.2))
			_leg2(b, Vector2(cx + 2, by + 4), Vector2(cx + 3 + s * 3, 23), 1.0, 2, Color(0.3, 0.36, 0.24))
			rect(b, int(cx - 8), int(by - 6), 5, 8, Color(0.4, 0.3, 0.2))
			line(b, int(cx - 7), int(by - 6), int(cx - 9), int(by - 13), METAL)
			px(e, int(cx - 9), int(by - 13), Color(1.0, 0.3, 0.3))
			ellipse(b, cx, by, 5.0, 5.5, Color(0.36, 0.45, 0.26))
			ellipse(b, cx + 2, by - 7, 5.5, 4.5, Color(0.4, 0.5, 0.28))
			poly(b, PackedVector2Array([Vector2(cx - 3, by - 8), Vector2(cx - 9, by - 11), Vector2(cx - 3, by - 6)]), Color(0.4, 0.5, 0.28))
			rect(b, int(cx + 1), int(by - 9), 6, 2, METAL_D)
			_optic(e, cx + 3, by - 8, 1.0, Color(1.0, 0.7, 0.2))
			_optic(e, cx + 6, by - 8, 1.0, Color(1.0, 0.7, 0.2))
			var hand := Vector2(cx + 6 + a * 3, by - 1 - a * 2)
			_limb(b, Vector2(cx + 3, by - 2), hand, 2, Color(0.36, 0.45, 0.26))
			ellipse(b, hand.x + 3, hand.y, 3.0, 3.0, METAL)
			for i in 4:
				var ang := TAU * i / 4.0 + f * 0.8
				px(b, int(hand.x + 3 + cos(ang) * 3.5), int(hand.y + sin(ang) * 3.5), Color(0.85, 0.85, 0.9))
		"slime", "slimelet":
			# Нано-слизень: прозрачная масса с плавающими деталями и глазами на стебельках
			var big := key == "slime"
			var k := 1.0 if big else 0.6
			var cx := (15.0 if big else 9.0)
			var hgt := 1.0 + s * 0.12 - hu * 0.15 + a * 0.15
			var w := (12.0 + a * 2.0) * k
			var hh := 9.0 * k * hgt
			var base := float(b.get_height() - 1)
			ellipse(b, cx, base - hh, w, hh, Color(0.2, 0.55, 0.45, 0.9))
			ellipse(b, cx - w * 0.3, base - hh * 1.4, w * 0.35, hh * 0.3, Color(0.6, 1.0, 0.85, 0.7))
			for i in (4 if big else 2):
				var gx := cx - w * 0.5 + i * w * 0.33
				var gy := base - hh + sin(f * 1.1 + i) * 2.0
				rect(b, int(gx), int(gy), 2, 2, METAL if i % 2 == 0 else Color(0.7, 0.55, 0.3))
				px(e, int(gx), int(gy), Color(0.4, 1.0, 0.6, 0.8))
			for d in [-1.0, 1.0]:
				var stalk := Vector2(cx + d * 3 * k, base - hh * 2.0 - 3 * k - s)
				line(b, int(cx + d * 2 * k), int(base - hh * 1.6), int(stalk.x), int(stalk.y), Color(0.2, 0.55, 0.45))
				_optic(e, stalk.x, stalk.y, 1.2 * k + 0.3, Color(1.0, 0.85, 0.2))
		"spider", "spiderling":
			# Паук-резак: металлические лапы-лезвия, гроздь лазерных глаз, реактор в брюхе
			var big := key == "spider"
			var k := 1.0 if big else 0.58
			var cx := 18.0 * k + a * 2.0 - hu * 2.0
			var cy := 13.0 * k + (1.0 if big else 0.6)
			for i in 4:
				for d in [-1.0, 1.0]:
					var ph := s * (1.0 if (i + int(d)) % 2 == 0 else -1.0)
					var hip := Vector2(cx + d * 3 * k, cy)
					var foot := Vector2(cx + d * (8 + i * 3) * k + ph * 2, b.get_height() - 1)
					var knee := Vector2(cx + d * (6 + i * 2.5) * k, cy - (6 - i) * k)
					line(b, int(hip.x), int(hip.y), int(knee.x), int(knee.y), METAL_D)
					line(b, int(knee.x), int(knee.y), int(foot.x), int(foot.y), METAL)
			ellipse(b, cx - 6 * k, cy - 1, 7.0 * k, 5.5 * k, FLESH.darkened(0.2))
			ellipse(e, cx - 6 * k, cy - 1, 2.5 * k, 2.0 * k, Color(0.4, 1.0, 0.5, 0.85))
			ellipse(b, cx + 3 * k, cy - 1, 4.5 * k, 4.0 * k, METAL_D)
			for i in 4:
				px(e, int(cx + (3 + (i % 2) * 2) * k), int(cy - 2 - (i / 2) * 2 * k), RED_EYE)
			if att and a > 0.5:
				line(e, int(cx + 6 * k), int(cy - 2), int(cx + 16 * k), int(cy + 1), Color(1.0, 0.3, 0.3, 0.9))
		"caster":
			# Культист сети: балахон, механические руки, глаз-дрон над плечом
			var cx := 13.0 - hu * 2.0
			var by := 20.0 + s * 0.6
			poly(b, PackedVector2Array([Vector2(cx - 5, by - 8), Vector2(cx + 5, by - 8), Vector2(cx + 9, 35), Vector2(cx - 9, 35)]), Color(0.22, 0.12, 0.3))
			line(e, int(cx - 9), 35, int(cx + 9), 35, Color(0.8, 0.3, 1.0, 0.8))
			line(e, int(cx), int(by - 6), int(cx), 33, Color(0.8, 0.3, 1.0, 0.5))
			ellipse(b, cx, by - 12, 5.5, 5.5, Color(0.25, 0.14, 0.34))
			ellipse(b, cx + 1, by - 11, 3.2, 3.5, Color(0.04, 0.03, 0.06))
			_optic(e, cx + 2, by - 11, 1.0, Color(0.85, 0.4, 1.0))
			for d in [-1.0, 1.0]:
				var hand := Vector2(cx + d * 8, by - 3 - a * 6)
				_limb(b, Vector2(cx + d * 4, by - 6), hand, 2, METAL)
				for i in 2:
					line(b, int(hand.x), int(hand.y), int(hand.x + d * 2), int(hand.y - 2 + i * 3), METAL.lightened(0.2))
			var dy := sin(f * 1.05) * 2.0
			ellipse(b, cx - 9, by - 18 + dy, 3.0, 3.0, METAL_D)
			_optic(e, cx - 9, by - 18 + dy, 1.4, Color(0.85, 0.4, 1.0))
			if att:
				ellipse(e, cx + 9, by - 4 - a * 6, 2.0 + a * 2.0, 2.0 + a * 2.0, Color(0.85, 0.4, 1.0, 0.85))
		"bomber":
			# Дрон-камикадзе: насекомое с бомбой-брюшком и мигалкой
			var cx := 12.0
			var cy := 10.0 - hu
			var wf := s * 3.0
			for d in [-1.0, 1.0]:
				ellipse(b, cx + d * 7, cy - 5 - wf * 0.3, 5.0, 2.0 + absf(wf) * 0.3, Color(0.6, 0.8, 0.9, 0.5))
			ellipse(b, cx, cy + 5, 6.0, 6.0, Color(0.25, 0.25, 0.28))
			for i in 3:
				line(b, int(cx - 5), int(cy + 3 + i * 2), int(cx + 5), int(cy + 3 + i * 2), Color(0.85, 0.7, 0.15))
			ellipse(b, cx, cy - 2, 4.0, 3.5, METAL)
			_optic(e, cx + 2, cy - 2, 1.2, RED_EYE)
			if f % 2 == 0 or att:
				ellipse(e, cx, cy + 5, 2.0 + a * 2.0, 2.0 + a * 2.0, Color(1.0, 0.3, 0.1, 0.9))
			for d in [-1.0, 1.0]:
				line(b, int(cx + d * 3), int(cy + 9), int(cx + d * 5), int(cy + 13), METAL_D)
		"knight":
			# Мёртвый рыцарь-экзо: латы с сервоприводами, щель визора, меч с энергокромкой
			var cx := 14.0 + a * 2.0 - hu * 2.0
			var by := 21.0 + absf(s) * 0.8
			_leg2(b, Vector2(cx - 3, by + 7), Vector2(cx - 4 - s * 3, 39), 1.5, 3, METAL_D)
			_leg2(b, Vector2(cx + 3, by + 7), Vector2(cx + 4 + s * 3, 39), 1.5, 3, METAL)
			px(e, int(cx - 3), int(by + 13), Color(0.4, 0.9, 1.0))
			rect(b, int(cx - 6), int(by - 6), 12, 13, METAL)
			rect(b, int(cx - 6), int(by - 6), 12, 2, METAL.lightened(0.25))
			rect(b, int(cx - 1), int(by - 4), 2, 10, METAL_D)
			poly(b, PackedVector2Array([Vector2(cx - 7, by + 6), Vector2(cx + 7, by + 6), Vector2(cx + 8, by + 11), Vector2(cx - 8, by + 11)]), Color(0.3, 0.15, 0.2))
			rect(b, int(cx - 4), int(by - 15), 9, 9, METAL.lightened(0.1))
			rect(b, int(cx - 1), int(by - 12), 7, 1, Color(0.05, 0.05, 0.08))
			line(e, int(cx), int(by - 12), int(cx + 5), int(by - 12), Color(0.4, 0.9, 1.0))
			poly(b, PackedVector2Array([Vector2(cx - 2, by - 15), Vector2(cx + 1, by - 20), Vector2(cx + 3, by - 15)]), Color(0.6, 0.15, 0.2))
			ellipse(b, cx - 7, by - 4, 3.0, 2.5, METAL.lightened(0.15))
			var swing := -1.6 + a * 2.8 + s * 0.2
			var hand := Vector2(cx + 6, by - 2) + Vector2(sin(swing + 1.6), -cos(swing + 1.6)) * 4.0
			_limb(b, Vector2(cx + 5, by - 4), hand, 2, METAL_D)
			var tip := hand + Vector2(cos(swing), sin(swing)) * 13.0
			line(b, int(hand.x), int(hand.y), int(tip.x), int(tip.y), Color(0.75, 0.78, 0.85))
			line(e, int(hand.x + cos(swing) * 3), int(hand.y + sin(swing) * 3), int(tip.x), int(tip.y), Color(0.4, 0.9, 1.0, 0.85))
			rect(b, int(hand.x) - 1, int(hand.y) - 1, 3, 2, Color(0.6, 0.5, 0.3))


static func sline_tail(b: Image, e: Image, root: Vector2, s: float) -> void:
	var p := root
	for i in 5:
		var q := p + Vector2(-2.0, 1.0 + sin(s * 2.0 + i) * 1.2)
		line(b, int(p.x), int(p.y), int(q.x), int(q.y), Color(0.2, 0.2, 0.25))
		p = q
	px(e, int(p.x), int(p.y), Color(1.0, 0.3, 0.3))


# ================= Боссы: 2× разрешение, 20 кадров =================
# 0–5 движение, 6–11 удар (замах, выпуск, возврат), 12–15 особый приём (призыв/канал),
# 16–17 урон, 18–19 ярость (смена фазы).

const BOSS_KEYS := ["lich", "colossus", "queen", "omega"]
const BOSS_ANIM := {"move": [0, 6], "attack": [6, 6], "special": [12, 4], "hurt": [16, 2], "rage": [18, 2]}


static func _boss_pose(f: int) -> Dictionary:
	var p := {"st": "move", "k": 0, "s": 0.0, "c": 1.0, "a": 0.0, "sp": 0.0, "hu": 0.0, "rg": 0.0}
	if f < 6:
		var ph := TAU * f / 6.0
		p["s"] = sin(ph)
		p["c"] = cos(ph)
	elif f < 12:
		p["st"] = "attack"
		p["k"] = f - 6
		p["a"] = [-0.5, -1.0, 1.0, 0.8, 0.4, 0.1][f - 6]
	elif f < 16:
		p["st"] = "special"
		p["k"] = f - 12
		p["sp"] = [0.4, 0.8, 1.0, 0.5][f - 12]
	elif f < 18:
		p["st"] = "hurt"
		p["hu"] = [1.0, 0.6][f - 16]
	else:
		p["st"] = "rage"
		p["rg"] = [0.7, 1.0][f - 18]
		p["s"] = 0.5 if f == 18 else -0.5
	return p


static func _paint_boss(key: String, b: Image, e: Image, f: int) -> void:
	var P := _boss_pose(f)
	var s: float = P["s"]
	var a: float = P["a"]
	var sp: float = P["sp"]
	var hu: float = P["hu"]
	var rg: float = P["rg"]
	match key:
		"lich":
			# Нейро-Лич: череп с открытым мозгом-схемой, корона из антенн, саван с узором плат,
			# позвоночник с проводами, посох с ядром
			var cx := 40.0 - hu * 4.0
			var cy := 44.0 + s * 2.0
			var robe := Color(0.18, 0.1, 0.26)
			var vio := Color(0.75, 0.4, 1.0)
			# позвоночник и провода под саваном
			for i in 7:
				var y := cy + 30 + i * 4
				ellipse(b, cx + sin(i * 0.8 + s) * 2.0, y, 3.0, 1.6, Color(0.8, 0.78, 0.7))
				px(e, int(cx + 4 + sin(i + s) * 2), int(y), Color(vio, 0.8))
			poly(b, PackedVector2Array([Vector2(cx - 15, cy - 2), Vector2(cx + 15, cy - 2), Vector2(cx + 24 + s * 2, cy + 40), Vector2(cx + 14, cy + 34 + s * 2), Vector2(cx + 6, cy + 44), Vector2(cx - 4, cy + 36), Vector2(cx - 12, cy + 44 - s * 2), Vector2(cx - 24 - s * 2, cy + 40)]), robe)
			for i in 5:
				var y := int(cy + 4 + i * 7)
				line(e, int(cx - 12 + i), y, int(cx - 4 + i), y, Color(vio, 0.6))
				line(e, int(cx - 4 + i), y, int(cx - 4 + i), y + 4, Color(vio, 0.6))
				line(e, int(cx + 6 - i), y + 2, int(cx + 13 - i), y + 2, Color(0.3, 1.0, 0.8, 0.5))
			# плечи-наплечники из костей
			for d in [-1.0, 1.0]:
				ellipse(b, cx + d * 14, cy, 6.0, 4.5, Color(0.8, 0.78, 0.7))
				for i in 3:
					px(b, int(cx + d * (10 + i * 3)), int(cy - 3), Color(0.55, 0.5, 0.45))
			# череп
			ellipse(b, cx + 1, cy - 14, 11.0, 12.0, Color(0.85, 0.83, 0.76))
			ellipse(b, cx + 1, cy - 20, 9.0, 6.0, Color(0.25, 0.12, 0.3))
			for i in 6:
				var x0 := int(cx - 6 + i * 2.5)
				line(e, x0, int(cy - 24 + (i % 2) * 2), x0 + 2, int(cy - 18), Color(vio, 0.9))
			rect(b, int(cx - 7), int(cy - 13), 6, 5, Color(0.06, 0.03, 0.1))
			rect(b, int(cx + 3), int(cy - 13), 6, 5, Color(0.06, 0.03, 0.1))
			var eyes := hdr(vio.lerp(Color(1, 0.3, 0.3), rg), 1.0 + rg)
			_optic(e, cx - 4, cy - 11, 1.8 + rg * 1.5 + sp, eyes)
			_optic(e, cx + 6, cy - 11, 1.8 + rg * 1.5 + sp, eyes)
			for i in 5:
				rect(b, int(cx - 5 + i * 3), int(cy - 4), 2, 3, Color(0.9, 0.88, 0.8))
			rect(b, int(cx - 6), int(cy - 2), 15, 2, Color(0.4, 0.42, 0.5))
			# корона-антенны
			for i in 5:
				var x := cx - 8 + i * 4.5
				var ht := 8.0 + (i % 2) * 5.0 + rg * 3.0
				line(b, int(x), int(cy - 24), int(x + (i - 2) * 1.5), int(cy - 24 - ht), Color(0.5, 0.5, 0.6))
				_optic(e, x + (i - 2) * 1.5, cy - 24 - ht, 1.0, Color(1.0, 0.3, 0.7) if i % 2 == 0 else vio)
			# руки и посох
			var arm_a := -0.3 + a * 1.1 - sp * 1.8
			var hand := Vector2(cx + 16, cy + 2) + Vector2(sin(arm_a + 1.3), -cos(arm_a + 1.3)) * 14.0
			_limb(b, Vector2(cx + 14, cy), hand, 2, Color(0.8, 0.78, 0.7))
			for i in 3:
				line(b, int(hand.x), int(hand.y), int(hand.x + 3), int(hand.y - 2 + i * 2), Color(0.5, 0.52, 0.6))
			var top := hand + Vector2(2, -28)
			line(b, int(hand.x + 1), int(hand.y + 22), int(top.x), int(top.y), Color(0.3, 0.26, 0.36))
			line(b, int(hand.x + 2), int(hand.y + 22), int(top.x + 1), int(top.y), Color(0.2, 0.16, 0.26))
			var orb_r := 4.0 + a * 2.0 + sp * 3.0 + rg * 2.0
			ellipse(e, top.x, top.y - 3, orb_r, orb_r, Color(vio, 0.85))
			ellipse(e, top.x, top.y - 3, orb_r * 0.4, orb_r * 0.4, Color(1, 1, 1))
			var hand2 := Vector2(cx - 16, cy + 2) + Vector2(-sin(0.3 + sp * 1.8), -cos(1.2 + sp * 1.5)) * 13.0
			_limb(b, Vector2(cx - 14, cy), hand2, 2, Color(0.8, 0.78, 0.7))
			if sp > 0.3:
				ellipse(e, hand2.x, hand2.y - 2, 3.0 * sp + 1.0, 3.0 * sp + 1.0, Color(0.3, 1.0, 0.8, 0.85))
			# парящие рунные осколки
			for i in 4:
				var ang := TAU * i / 4.0 + f * 0.35
				var q := Vector2(cx + cos(ang) * 30, cy + 10 + sin(ang) * 10)
				poly(e, PackedVector2Array([q + Vector2(0, -3), q + Vector2(2, 0), q + Vector2(0, 3), q + Vector2(-2, 0)]), Color(vio, 0.75))
		"colossus":
			# Железный Колосс: топка в груди, клёпаные наплечники, руки-молоты, ноги-колонны с поршнями, трубы
			var cx := 50.0 - hu * 4.0
			var by := 48.0 + absf(s) * 2.0
			var iron := Color(0.36, 0.36, 0.42)
			var iron_d := Color(0.22, 0.22, 0.27)
			var fire := Color(1.0, 0.5, 0.15).lerp(Color(1.0, 0.2, 0.1), rg)
			for d in [-1.0, 1.0]:
				var foot := Vector2(cx + d * 14 + d * s * 4, 90)
				var hip := Vector2(cx + d * 12, by + 18)
				_limb(b, hip, foot, 10, iron_d)
				rect(b, int(foot.x - 8), 84, 16, 6, iron)
				line(b, int(hip.x + d * 5), int(hip.y + 4), int(foot.x + d * 5), int(foot.y - 8), Color(0.7, 0.7, 0.75))
				px(e, int(hip.x), int(hip.y + 12), fire)
			for d in [-1.0, 1.0]:
				rect(b, int(cx + d * 12 - 3), int(by - 44), 6, 14, iron_d)
				if f % 3 == 0:
					ellipse(e, cx + d * 12, by - 46, 3.0, 2.0, Color(1.0, 0.6, 0.3, 0.6))
			poly(b, PackedVector2Array([Vector2(cx - 26, by - 30), Vector2(cx + 26, by - 30), Vector2(cx + 22, by + 20), Vector2(cx - 22, by + 20)]), iron)
			for y in range(int(by - 26), int(by + 18), 6):
				px(b, int(cx - 22), y, iron.lightened(0.35))
				px(b, int(cx + 21), y, iron.lightened(0.35))
			# топка
			var open := 0.4 + sp * 0.6 + rg * 0.5
			rect(b, int(cx - 12), int(by - 16), 24, 20, iron_d)
			rect(e, int(cx - 10), int(by - 14 + (1.0 - open) * 8), 20, int(16 * open), Color(fire, 0.95))
			for i in 4:
				rect(b, int(cx - 10 + i * 6), int(by - 14), 2, 16, Color(0.15, 0.14, 0.18))
			if rg > 0.0:
				for i in 6:
					line(e, int(cx - 20 + i * 7), int(by - 28 + (i % 3) * 9), int(cx - 17 + i * 7), int(by - 20 + (i % 2) * 9), Color(1.0, 0.3, 0.1, 0.8))
			# голова со щелью визора
			rect(b, int(cx - 8), int(by - 42), 16, 12, iron)
			rect(b, int(cx - 6), int(by - 37), 12, 2, Color(0.05, 0.05, 0.07))
			line(e, int(cx - 5), int(by - 37), int(cx + 6), int(by - 37), hdr(fire, 1.0 + rg))
			# наплечники и руки-молоты
			var raise := a
			for d in [-1.0, 1.0]:
				ellipse(b, cx + d * 28, by - 28, 11.0, 8.0, iron.lightened(0.08))
				for i in 4:
					px(b, int(cx + d * (22 + i * 4)), int(by - 33), iron.lightened(0.4))
				var up := raise if d > 0 else raise * 0.4
				var elbow := Vector2(cx + d * 32, by - 12 - up * 14)
				var fist := Vector2(cx + d * 34, by + 8 - up * 34)
				_limb(b, Vector2(cx + d * 28, by - 24), elbow, 8, iron_d)
				_limb(b, elbow, fist, 8, iron)
				rect(b, int(fist.x - 9), int(fist.y - 6), 18, 14, iron.lightened(0.1))
				rect(b, int(fist.x - 9), int(fist.y - 6), 18, 2, iron.lightened(0.35))
				px(e, int(fist.x), int(fist.y), fire)
			if P["st"] == "attack" and P["k"] == 2:
				for i in 12:
					px(e, int(cx + 22 + i * 2), 89 - (i % 2), Color(1.0, 0.6, 0.2, 0.9))
		"queen":
			# Королева Роя: брюшко с кладкой, хитиновые пластины, металлические жвала,
			# фасеточные глаза, четыре крыла с жилками-схемами, шесть лап
			var cx := 54.0 - hu * 4.0
			var cy := 40.0 + s * 2.0
			var chit := Color(0.18, 0.22, 0.16)
			var green := Color(0.5, 1.0, 0.35).lerp(Color(1.0, 0.3, 0.2), rg)
			var fl := s * 8.0 + (6.0 if rg > 0.0 else 0.0)
			for i in 2:
				for d in [-1.0, 1.0]:
					var root := Vector2(cx + 4, cy - 10)
					var tip := root + Vector2(d * (30 - i * 6), -16 - fl * (1.0 - i * 0.3) + i * 12)
					poly(b, PackedVector2Array([root, tip, tip + Vector2(-d * 4, 12), root + Vector2(0, 6)]), Color(0.55, 0.75, 0.85, 0.45))
					line(e, int(root.x), int(root.y), int(tip.x), int(tip.y), Color(green, 0.6))
					line(e, int(root.x), int(root.y + 3), int(tip.x - d * 3), int(tip.y + 8), Color(green, 0.35))
			# брюшко
			var pulse := 1.0 + sp * 0.15
			ellipse(b, cx - 22, cy + 8, 22.0 * pulse, 15.0 * pulse, chit.darkened(0.1))
			for i in 4:
				line(b, int(cx - 40 + i * 9), int(cy - 4), int(cx - 38 + i * 9), int(cy + 22), chit.lightened(0.15))
			for i in 6:
				var q := Vector2(cx - 34 + (i % 3) * 11, cy + 2 + (i / 3) * 10)
				ellipse(e, q.x, q.y, 2.5 + sp * 1.5, 2.0 + sp, Color(green, 0.75))
			# грудь и лапы
			ellipse(b, cx + 4, cy + 4, 11.0, 10.0, chit)
			for i in 3:
				for d in [-1.0, 1.0]:
					var ph := s * (1.0 if (i % 2 == 0) == (d > 0) else -1.0)
					var hip := Vector2(cx + i * 5 - 2, cy + 10)
					var foot := Vector2(cx - 6 + i * 12 + ph * 4 + d * 3, 82)
					_leg2(b, hip, foot, -d * 6.0, 3, Color(0.3, 0.32, 0.38))
			# голова
			ellipse(b, cx + 18, cy - 4, 9.0, 8.0, chit.lightened(0.05))
			for i in 7:
				px(e, int(cx + 18 + (i % 3) * 2), int(cy - 8 + (i / 3) * 2), hdr(Color(1.0, 0.25, 0.2), 1.0 + rg))
			var bite := a * 4.0
			for d in [-1.0, 1.0]:
				poly(b, PackedVector2Array([Vector2(cx + 24, cy + d * 2), Vector2(cx + 34 + bite, cy + d * (4 + bite)), Vector2(cx + 30, cy + d * 1)]), Color(0.6, 0.62, 0.7))
			for d in [-1.0, 1.0]:
				line(b, int(cx + 20), int(cy - 11), int(cx + 28 + d * 4), int(cy - 24), Color(0.45, 0.45, 0.55))
				px(e, int(cx + 28 + d * 4), int(cy - 24), green)
		"omega":
			# Архимаг Омега: латы-мантия, маска с тремя глазами, нимб-кольцо, плащ энергии,
			# перчатки со стихиями (огонь, лёд, буря), парящие геометрические осколки
			var cx := 50.0 - hu * 4.0
			var cy := 52.0 + s * 2.0
			var gold := Color(0.85, 0.65, 0.3)
			var armor := Color(0.3, 0.28, 0.4)
			var cape := Color(0.4, 0.2, 0.6, 0.85)
			poly(b, PackedVector2Array([Vector2(cx - 14, cy - 18), Vector2(cx + 14, cy - 18), Vector2(cx + 30 + s * 3, cy + 50), Vector2(cx - 30 - s * 3, cy + 50)]), cape)
			for i in 6:
				line(e, int(cx - 28 + i * 11), int(cy + 50), int(cx - 10 + i * 4), int(cy - 10), Color(0.8, 0.5, 1.0, 0.35))
			poly(b, PackedVector2Array([Vector2(cx - 16, cy - 20), Vector2(cx + 16, cy - 20), Vector2(cx + 12, cy + 20), Vector2(cx - 12, cy + 20)]), armor)
			rect(b, int(cx - 12), int(cy - 6), 24, 3, gold)
			poly(b, PackedVector2Array([Vector2(cx - 14, cy + 18), Vector2(cx + 14, cy + 18), Vector2(cx + 18, cy + 46), Vector2(cx - 18, cy + 46)]), armor.darkened(0.15))
			_optic(e, cx, cy + 4, 3.0 + sp * 2.0, Color(1.0, 0.85, 0.4))
			for d in [-1.0, 1.0]:
				ellipse(b, cx + d * 18, cy - 18, 8.0, 6.0, gold.darkened(0.1))
				px(b, int(cx + d * 18), int(cy - 22), gold.lightened(0.4))
			# голова-маска
			ellipse(b, cx, cy - 32, 9.0, 10.0, gold)
			rect(b, int(cx - 7), int(cy - 34), 14, 8, Color(0.12, 0.1, 0.16))
			var ec := hdr(Color(1.0, 0.85, 0.4).lerp(Color(1.0, 0.3, 0.3), rg), 1.0 + rg)
			_optic(e, cx - 4, cy - 31, 1.4, ec)
			_optic(e, cx + 4, cy - 31, 1.4, ec)
			_optic(e, cx, cy - 37, 1.6 + sp, ec)
			# нимб
			var hr := 16.0 + rg * 4.0
			for i in 24:
				var ang := TAU * i / 24.0 + f * 0.15
				if rg > 0.0 and i % 6 == 0:
					continue   # ярость: кольцо раскалывается
				px(e, int(cx + cos(ang) * hr), int(cy - 38 + sin(ang) * hr * 0.35), Color(1.0, 0.85, 0.4, 0.9))
			# руки со стихиями
			var els := [Color(1.0, 0.45, 0.15), Color(0.5, 0.85, 1.0), Color(0.75, 0.5, 1.0)]
			for d in [-1.0, 1.0]:
				var up := (a if d > 0 else 0.0) + sp
				var hand := Vector2(cx + d * (24 + sp * 8), cy - 4 - up * 16)
				_limb(b, Vector2(cx + d * 16, cy - 14), hand, 5, armor)
				rect(b, int(hand.x - 4), int(hand.y - 3), 8, 7, gold.darkened(0.15))
				var ecol: Color = els[0] if d > 0 else els[1]
				ellipse(e, hand.x, hand.y - 6, 3.5 + up * 3.0, 3.5 + up * 3.0, Color(ecol, 0.85))
				px(e, int(hand.x), int(hand.y - 6), Color(1, 1, 1))
			# осколки
			for i in 6:
				var ang := TAU * i / 6.0 + f * 0.3
				var q := Vector2(cx + cos(ang) * (38 + sp * 6), cy + 4 + sin(ang) * 14)
				var col: Color = els[i % 3]
				poly(e, PackedVector2Array([q + Vector2(0, -4), q + Vector2(3, 0), q + Vector2(0, 4), q + Vector2(-3, 0)]), Color(col, 0.8))
