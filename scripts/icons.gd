extends RefCounted
## Иконки оружия и модулей 36×36.
## Каждая деталь рисуется своим слоем и получает объём: светлая кромка сверху-слева,
## тень снизу-справа, мягкий диагональный градиент. Неоновые части дают ореол,
## вся иконка обводится тёмным контуром. Остальные (старые 18×18) иконки
## увеличиваются вдвое и проходят ту же обработку — стиль един.

const N := 36
const OUT := Color(0.035, 0.02, 0.07)

const METAL := Color(0.56, 0.6, 0.7)
const METAL_D := Color(0.27, 0.29, 0.38)
const STEEL := Color(0.8, 0.84, 0.92)
const GOLD := Color(0.96, 0.72, 0.28)
const WOOD := Color(0.48, 0.3, 0.18)
const CYAN := Color(0.3, 0.9, 1.0)
const PINK := Color(1.0, 0.3, 0.75)
const WHITE := Color(1, 1, 1)

const IDS := ["bolt", "blades", "aura", "lightning", "katana", "quake", "drones", "railbow", "sunbeam",
	"spirits", "ball", "flask", "shuriken", "hp", "speed", "magnet", "regen", "armor", "vamp", "luck",
	"damage", "cooldown", "area", "crit", "multi", "duration"]


static func has(id: String) -> bool:
	return id in IDS


# ---------- Примитивы (свои, чтобы не было циклической загрузки с pixel.gd) ----------

static func blank(w: int, h: int) -> Image:
	return Image.create_empty(w, h, false, Image.FORMAT_RGBA8)


static func px(im: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < im.get_width() and y < im.get_height():
		im.set_pixel(x, y, c)


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



# ---------- Слои ----------

static func _l() -> Image:
	return blank(N, N)


## Толстая линия с круглыми концами.
static func _tl(im: Image, a: Vector2, b: Vector2, w: float, c: Color) -> void:
	var r := w * 0.5
	var x0 := int(floor(minf(a.x, b.x) - r - 1))
	var x1 := int(ceil(maxf(a.x, b.x) + r + 1))
	var y0 := int(floor(minf(a.y, b.y) - r - 1))
	var y1 := int(ceil(maxf(a.y, b.y) + r + 1))
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) <= r:
				px(im, x, y, c)


static func _ring(im: Image, cx: float, cy: float, ro: float, ri: float, c: Color) -> void:
	for x in range(int(cx - ro) - 1, int(cx + ro) + 2):
		for y in range(int(cy - ro) - 1, int(cy + ro) + 2):
			var d := Vector2(x + 0.5 - cx, y + 0.5 - cy).length()
			if d <= ro and d >= ri:
				px(im, x, y, c)


## Дуга кольца от угла a0 до a1.
static func _arc(im: Image, cx: float, cy: float, ro: float, ri: float, a0: float, a1: float, c: Color) -> void:
	for x in range(int(cx - ro) - 1, int(cx + ro) + 2):
		for y in range(int(cy - ro) - 1, int(cy + ro) + 2):
			var v := Vector2(x + 0.5 - cx, y + 0.5 - cy)
			var d := v.length()
			if d > ro or d < ri:
				continue
			var a := fposmod(v.angle() - a0, TAU)
			if a <= fposmod(a1 - a0, TAU):
				px(im, x, y, c)


static func _pts(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, arr.size(), 2):
		out.append(Vector2(arr[i], arr[i + 1]))
	return out


static func _rot(pts: PackedVector2Array, c: Vector2, a: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + (p - c).rotated(a))
	return out


## Объём слоя и наложение на иконку.
static func _put(dst: Image, l: Image, hi := 0.3, lo := 0.34) -> void:
	var src := l.duplicate() as Image
	var used := l.get_used_rect()
	if used.size == Vector2i.ZERO:
		return
	var span := float(used.size.x + used.size.y)
	for x in range(used.position.x, used.end.x):
		for y in range(used.position.y, used.end.y):
			var c := src.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var t := float(x - used.position.x + y - used.position.y) / span
			var o := c.lightened(0.14 * (1.0 - t)).darkened(0.2 * t)
			if alpha_at(src, x, y - 1) < 0.5 or alpha_at(src, x - 1, y) < 0.5:
				o = c.lightened(hi)
			elif alpha_at(src, x, y + 1) < 0.5 or alpha_at(src, x + 1, y) < 0.5:
				o = c.darkened(lo)
			o.a = c.a
			l.set_pixel(x, y, o)
	dst.blend_rect(l, Rect2i(0, 0, N, N), Vector2i.ZERO)


## Неоновый слой: почти без объёма, зато со свечением.
static func _neon(dst: Image, g: Image, l: Image) -> void:
	g.blend_rect(l, Rect2i(0, 0, N, N), Vector2i.ZERO)
	_put(dst, l, 0.35, 0.12)


## Плоские детали поверх (блики, руны) — без обработки.
static func _flat(dst: Image, l: Image) -> void:
	dst.blend_rect(l, Rect2i(0, 0, N, N), Vector2i.ZERO)


## Сборка: ореол → контур → тело.
static func _finish(im: Image, g: Image) -> Image:
	var out := _l()
	# Ореол: размытый на 3 пикселя слой неона, полупрозрачный (раскладываем каждый
	# светящийся пиксель по соседям — быстрее, чем собирать в каждой точке)
	var acc := PackedFloat32Array()
	acc.resize(N * N * 4)
	for x in N:
		for y in N:
			var c := g.get_pixel(x, y)
			if c.a < 0.1:
				continue
			for dx in range(-3, 4):
				for dy in range(-3, 4):
					var xx := x + dx
					var yy := y + dy
					if xx < 0 or yy < 0 or xx >= N or yy >= N:
						continue
					var w := 1.0 / (1.0 + float(dx * dx + dy * dy))
					var i := (yy * N + xx) * 4
					acc[i] += c.r * w
					acc[i + 1] += c.g * w
					acc[i + 2] += c.b * w
					acc[i + 3] += w
	for x in N:
		for y in N:
			var i := (y * N + x) * 4
			var wsum := acc[i + 3]
			if wsum > 0.0:
				out.set_pixel(x, y, Color(acc[i] / wsum, acc[i + 1] / wsum, acc[i + 2] / wsum, clampf(wsum / 5.0, 0.0, 0.55)))
	# Контур тела
	for x in N:
		for y in N:
			if im.get_pixel(x, y).a >= 0.5:
				continue
			if alpha_at(im, x + 1, y) >= 0.5 or alpha_at(im, x - 1, y) >= 0.5 \
					or alpha_at(im, x, y + 1) >= 0.5 or alpha_at(im, x, y - 1) >= 0.5:
				out.set_pixel(x, y, OUT)
	out.blend_rect(im, Rect2i(0, 0, N, N), Vector2i.ZERO)
	return out


## Старая иконка 18×18 → 36×36 в общем стиле.
static func upgrade(old: Image) -> Image:
	var big := old.duplicate() as Image
	big.resize(N, N, Image.INTERPOLATE_NEAREST)
	var im := _l()
	var g := _l()
	# Яркие насыщенные пиксели считаем неоном — им ореол
	for x in N:
		for y in N:
			var c := big.get_pixel(x, y)
			if c.a > 0.5 and c.get_luminance() > 0.55 and c.s > 0.35:
				g.set_pixel(x, y, c)
	_put(im, big, 0.22, 0.3)
	return _finish(im, g)


# ---------- Иконки ----------

static func draw(id: String) -> Image:
	var im := _l()
	var g := _l()
	match id:
		# ===== Оружие =====
		"bolt":
			var l := _l()
			_tl(l, Vector2(4, 32), Vector2(12, 24), 5.0, METAL_D)
			_tl(l, Vector2(11, 25), Vector2(13, 17), 2.4, METAL)
			_tl(l, Vector2(11, 25), Vector2(19, 23), 2.4, METAL)
			rect(l, 6, 27, 3, 2, GOLD)
			_put(im, l)
			var t := _l()
			_tl(t, Vector2(9, 27), Vector2(20, 15), 4.0, Color(0.15, 0.5, 1.0, 0.85))
			_tl(t, Vector2(14, 28), Vector2(22, 19), 1.6, Color(0.4, 0.85, 1.0, 0.8))
			_tl(t, Vector2(8, 22), Vector2(18, 13), 1.4, Color(0.4, 0.85, 1.0, 0.8))
			_neon(im, g, t)
			var o := _l()
			ellipse(o, 23, 12, 9, 9, Color(0.12, 0.45, 1.0))
			ellipse(o, 22.5, 11.5, 6.5, 6.5, Color(0.3, 0.82, 1.0))
			ellipse(o, 21.5, 10.5, 3.5, 3.5, Color(0.88, 1.0, 1.0))
			_neon(im, g, o)
			var sw := _l()
			_arc(sw, 23, 12, 7.5, 6.6, 3.4, 5.2, Color(0.9, 1.0, 1.0, 0.85))
			_arc(sw, 23, 12, 5.0, 4.2, 0.3, 1.8, Color(0.9, 1.0, 1.0, 0.7))
			_flat(im, sw)
			var s := _l()
			for seg in [[23, 12, 29, 7, 33, 9], [24, 13, 31, 17, 34, 15], [22, 11, 18, 4, 21, 1]]:
				line(s, seg[0], seg[1], seg[2], seg[3], Color(0.75, 0.95, 1.0))
				line(s, seg[2], seg[3], seg[4], seg[5], Color(0.75, 0.95, 1.0))
			px(s, 19, 8, WHITE)
			px(s, 20, 8, WHITE)
			px(s, 19, 9, WHITE)
			g.blend_rect(s, Rect2i(0, 0, N, N), Vector2i.ZERO)
			_flat(im, s)
		"blades":
			var c := Vector2(18, 18)
			for i in 3:
				var a := TAU * i / 3.0 - 0.5
				var col := PINK if i % 2 == 0 else CYAN
				var b := _l()
				var blade := _rot(_pts([18, 0.5, 22, 8, 18, 13.5, 14, 8]), c, a)
				poly(b, blade, col)
				_neon(im, g, b)
				var e := _l()
				var edge := _rot(_pts([18, 3, 18, 12]), c, a)
				line(e, int(edge[0].x), int(edge[0].y), int(edge[1].x), int(edge[1].y), WHITE)
				_flat(im, e)
			var h := _l()
			_ring(h, 18, 18, 6.5, 3.5, METAL)
			for i in 3:
				var a := TAU * i / 3.0 - 0.5 + PI / 3.0
				var p := c + Vector2.UP.rotated(a) * 5.0
				ellipse(h, p.x, p.y, 1.6, 1.6, GOLD)
			_put(im, h)
			var core := _l()
			ellipse(core, 18, 18, 2.6, 2.6, Color(0.95, 0.6, 1.0))
			_neon(im, g, core)
			var arcs := _l()
			_arc(arcs, 18, 18, 17, 16, 0.3, 1.2, Color(1.0, 0.5, 0.9, 0.7))
			_arc(arcs, 18, 18, 17, 16, 2.4, 3.3, Color(0.4, 0.95, 1.0, 0.7))
			_arc(arcs, 18, 18, 17, 16, 4.5, 5.4, Color(1.0, 0.5, 0.9, 0.7))
			g.blend_rect(arcs, Rect2i(0, 0, N, N), Vector2i.ZERO)
			_flat(im, arcs)
		"aura":
			var r := _l()
			_ring(r, 18, 18, 15.5, 11.5, Color(0.95, 0.42, 0.08))
			_neon(im, g, r)
			var runes := _l()
			for i in 8:
				var a := TAU * i / 8.0
				var p := Vector2(18, 18) + Vector2.RIGHT.rotated(a) * 13.5
				var t := Vector2.RIGHT.rotated(a + PI / 2.0)
				line(runes, int(p.x - t.x * 1.5), int(p.y - t.y * 1.5), int(p.x + t.x * 1.5), int(p.y + t.y * 1.5), Color(1.0, 0.95, 0.6))
				px(runes, int(p.x + cos(a) * 1.0), int(p.y + sin(a) * 1.0), Color(1.0, 0.95, 0.6))
			_flat(im, runes)
			var fl := _l()
			for i in 6:
				var a := TAU * i / 6.0 + 0.25
				var base := Vector2(18, 18) + Vector2.RIGHT.rotated(a) * 10.5
				var tip := Vector2(18, 18) + Vector2.RIGHT.rotated(a + 0.25) * 6.0
				var side := Vector2.RIGHT.rotated(a + PI / 2.0) * 2.2
				poly(fl, PackedVector2Array([base - side, tip, base + side]), Color(1.0, 0.7, 0.2, 0.9))
			_neon(im, g, fl)
			var c := _l()
			poly(c, _pts([18, 12, 22, 18, 18, 24, 14, 18]), Color(1.0, 0.82, 0.3))
			poly(c, _pts([18, 15, 20, 18, 18, 21, 16, 18]), Color(1.0, 1.0, 0.85))
			_neon(im, g, c)
		"lightning":
			var cl := _l()
			ellipse(cl, 12, 9, 7, 5, Color(0.36, 0.4, 0.56))
			ellipse(cl, 21, 7, 8, 6, Color(0.42, 0.46, 0.62))
			ellipse(cl, 27, 10, 6, 4.5, Color(0.36, 0.4, 0.56))
			rect(cl, 7, 9, 25, 4, Color(0.34, 0.38, 0.52))
			_put(im, cl, 0.32, 0.3)
			var bo := _l()
			poly(bo, _pts([20, 12, 13, 22, 18, 22, 12, 34, 25, 18, 19.5, 18, 24, 12]), Color(0.65, 0.85, 1.0))
			_neon(im, g, bo)
			var core := _l()
			line(core, 21, 13, 16, 21, Color(1, 1, 1))
			line(core, 16, 21, 19, 21, Color(1, 1, 1))
			line(core, 19, 21, 14, 31, Color(1, 1, 1))
			for p in [Vector2i(8, 16), Vector2i(29, 15), Vector2i(27, 24), Vector2i(7, 26)]:
				px(core, p.x, p.y, Color(0.7, 0.9, 1.0))
				px(core, p.x + 1, p.y + 1, Color(0.7, 0.9, 1.0))
			g.blend_rect(core, Rect2i(0, 0, N, N), Vector2i.ZERO)
			_flat(im, core)
		"katana":
			var bl := _l()
			poly(bl, _pts([9.5, 24.5, 20, 13, 30, 4.5, 34, 1.5, 33, 6, 22, 16.5, 12.5, 28]), STEEL)
			_put(im, bl, 0.25, 0.3)
			var hm := _l()
			_tl(hm, Vector2(13.5, 25.5), Vector2(31, 6.5), 1.3, PINK)
			_neon(im, g, hm)
			var ts := _l()
			poly(ts, _rot(_pts([7, 23, 14, 23, 14, 27, 7, 27]), Vector2(10.5, 25), -0.785), GOLD)
			_put(im, ts)
			var hd := _l()
			_tl(hd, Vector2(3, 33), Vector2(9.5, 26.5), 3.6, Color(0.14, 0.1, 0.16))
			_put(im, hd)
			var wr := _l()
			for i in 4:
				var p := Vector2(4, 32).lerp(Vector2(9, 27), i / 3.0)
				px(wr, int(p.x), int(p.y), Color(0.85, 0.15, 0.3))
				px(wr, int(p.x) + 1, int(p.y) - 1, Color(0.85, 0.15, 0.3))
			px(wr, 2, 34, GOLD)
			px(wr, 3, 34, GOLD)
			line(wr, 13, 22, 29, 5, Color(1, 1, 1, 0.9))
			_flat(im, wr)
		"quake":
			var hd := _l()
			_tl(hd, Vector2(9, 33), Vector2(20, 14), 3.4, WOOD)
			_put(im, hd)
			var wr := _l()
			for i in 3:
				var p := Vector2(10, 31).lerp(Vector2(14, 24), i / 2.0)
				_tl(wr, p + Vector2(-2, -1), p + Vector2(2, 1), 1.2, Color(0.25, 0.2, 0.3))
			_flat(im, wr)
			var head := _l()
			poly(head, _rot(_pts([8, 5, 30, 5, 30, 17, 8, 17]), Vector2(19, 11), 0.52), Color(0.5, 0.62, 0.78))
			_put(im, head, 0.32, 0.36)
			var band := _l()
			poly(band, _rot(_pts([17, 4, 21, 4, 21, 18, 17, 18]), Vector2(19, 11), 0.52), METAL_D)
			_put(im, band)
			var ice := _l()
			for c in [[9, 4, 3.0], [27, 17, 3.0], [13, 2, 2.0], [30, 13, 2.0]]:
				poly(ice, _pts([c[0], c[1] - c[2] * 1.6, c[0] + c[2], c[1], c[0], c[1] + c[2] * 1.6, c[0] - c[2], c[1]]), Color(0.7, 0.97, 1.0))
			_neon(im, g, ice)
			var rune := _l()
			var rc := Vector2(19, 11)
			line(rune, int(rc.x - 1), int(rc.y - 3), int(rc.x + 1), int(rc.y + 3), Color(0.55, 1.0, 1.0))
			line(rune, int(rc.x - 2), int(rc.y), int(rc.x + 2), int(rc.y), Color(0.55, 1.0, 1.0))
			g.blend_rect(rune, Rect2i(0, 0, N, N), Vector2i.ZERO)
			_flat(im, rune)
			var cr := _l()
			line(cr, 2, 34, 8, 33, Color(0.6, 0.95, 1.0))
			line(cr, 26, 33, 34, 34, Color(0.6, 0.95, 1.0))
			line(cr, 4, 30, 6, 33, Color(0.6, 0.95, 1.0))
			g.blend_rect(cr, Rect2i(0, 0, N, N), Vector2i.ZERO)
			_flat(im, cr)
		"drones":
			var arms := _l()
			_tl(arms, Vector2(6, 11), Vector2(30, 11), 2.0, METAL_D)
			_put(im, arms)
			var pr := _l()
			ellipse(pr, 6, 9, 5.5, 1.4, Color(0.75, 0.8, 0.9, 0.85))
			ellipse(pr, 30, 9, 5.5, 1.4, Color(0.75, 0.8, 0.9, 0.85))
			rect(pr, 5, 9, 2, 3, METAL)
			rect(pr, 29, 9, 2, 3, METAL)
			_put(im, pr, 0.3, 0.2)
			var body := _l()
			ellipse(body, 18, 15, 8.5, 6.5, Color(0.36, 0.4, 0.52))
			rect(body, 11, 17, 14, 3, Color(0.3, 0.33, 0.44))
			_put(im, body, 0.35, 0.36)
			var eye := _l()
			ellipse(eye, 18, 15, 3.6, 3.6, Color(1.0, 0.25, 0.35))
			ellipse(eye, 18, 15, 1.8, 1.8, Color(1.0, 0.85, 0.85))
			_neon(im, g, eye)
			var bm := _l()
			_tl(bm, Vector2(18, 20), Vector2(25, 34), 2.4, Color(1.0, 0.3, 0.45, 0.9))
			_tl(bm, Vector2(18, 20), Vector2(25, 34), 0.8, Color(1.0, 0.9, 0.9))
			ellipse(bm, 25.5, 33.5, 2.2, 1.2, Color(1.0, 0.7, 0.3))
			_neon(im, g, bm)
			var hl := _l()
			px(hl, 14, 11, WHITE)
			px(hl, 15, 10, WHITE)
			px(hl, 17, 14, WHITE)
			_flat(im, hl)
		"railbow":
			var bow := _l()
			_arc(bow, 8, 18, 16, 13, -1.25, 1.25, METAL)
			_put(im, bow, 0.32, 0.36)
			var rails := _l()
			_arc(rails, 8, 18, 14.6, 14.0, -1.15, -0.35, CYAN)
			_arc(rails, 8, 18, 14.6, 14.0, 0.35, 1.15, CYAN)
			_neon(im, g, rails)
			var grip := _l()
			rect(grip, 21, 15, 4, 6, Color(0.2, 0.18, 0.26))
			rect(grip, 21, 14, 4, 1, GOLD)
			rect(grip, 21, 21, 4, 1, GOLD)
			_put(im, grip)
			var st := _l()
			var ta := Vector2(8, 18) + Vector2.RIGHT.rotated(-1.25) * 14.5
			var tb := Vector2(8, 18) + Vector2.RIGHT.rotated(1.25) * 14.5
			line(st, int(ta.x), int(ta.y), 9, 18, Color(0.6, 1.0, 0.95))
			line(st, 9, 18, int(tb.x), int(tb.y), Color(0.6, 1.0, 0.95))
			g.blend_rect(st, Rect2i(0, 0, N, N), Vector2i.ZERO)
			_flat(im, st)
			var ar := _l()
			_tl(ar, Vector2(9, 18), Vector2(30, 18), 1.2, Color(0.85, 0.95, 1.0))
			poly(ar, _pts([29, 15, 35, 18, 29, 21]), Color(0.5, 1.0, 0.85))
			poly(ar, _pts([8, 15, 12, 18, 8, 21, 10, 18]), PINK)
			_neon(im, g, ar)
		"sunbeam":
			var rays := _l()
			for i in 12:
				var a := TAU * i / 12.0
				var p0 := Vector2(12, 12) + Vector2.RIGHT.rotated(a) * 8.0
				var p1 := Vector2(12, 12) + Vector2.RIGHT.rotated(a) * (11.5 if i % 2 == 0 else 10.0)
				_tl(rays, p0, p1, 1.6, Color(1.0, 0.8, 0.3))
			_neon(im, g, rays)
			var sun := _l()
			ellipse(sun, 12, 12, 7, 7, Color(1.0, 0.66, 0.15))
			ellipse(sun, 11, 11, 4.5, 4.5, Color(1.0, 0.9, 0.45))
			ellipse(sun, 10, 10, 2, 2, Color(1.0, 1.0, 0.9))
			_neon(im, g, sun)
			var bm := _l()
			poly(bm, _pts([15, 18, 18, 15, 35, 25, 35, 35, 25, 35]), Color(1.0, 0.78, 0.3, 0.7))
			poly(bm, _pts([16, 18, 18, 16, 35, 29, 29, 35]), Color(1.0, 0.92, 0.55, 0.9))
			_tl(bm, Vector2(17, 17), Vector2(34, 34), 1.4, Color(1.0, 1.0, 0.92))
			_neon(im, g, bm)
		"spirits":
			var gh := _l()
			ellipse(gh, 17, 13, 9, 9, Color(0.55, 0.85, 1.0, 0.95))
			poly(gh, _pts([8, 13, 26, 13, 27, 25, 23, 22, 21, 28, 17, 23, 13, 29, 11, 23, 7, 26]), Color(0.55, 0.85, 1.0, 0.95))
			_neon(im, g, gh)
			var face := _l()
			ellipse(face, 14, 12, 1.8, 2.4, Color(0.06, 0.05, 0.16))
			ellipse(face, 21, 12, 1.8, 2.4, Color(0.06, 0.05, 0.16))
			px(face, 14, 11, Color(0.6, 1.0, 1.0))
			px(face, 21, 11, Color(0.6, 1.0, 1.0))
			rect(face, 16, 17, 3, 1, Color(0.06, 0.05, 0.16))
			_flat(im, face)
			var bits := _l()
			for p in [Vector2i(28, 27), Vector2i(31, 22), Vector2i(26, 32), Vector2i(31, 30), Vector2i(4, 30), Vector2i(29, 9), Vector2i(33, 26)]:
				rect(bits, p.x, p.y, 2, 2, Color(0.5, 1.0, 0.95))
			_neon(im, g, bits)
		"ball":
			var o := _l()
			ellipse(o, 18, 18, 10, 10, Color(0.32, 0.48, 1.0))
			ellipse(o, 17, 17, 7, 7, Color(0.5, 0.72, 1.0))
			ellipse(o, 16, 16, 3.5, 3.5, Color(0.92, 0.97, 1.0))
			_neon(im, g, o)
			var arcs := _l()
			var segs := [[18, 8, 14, 3, 17, 0], [28, 18, 33, 14, 35, 17], [18, 28, 22, 33, 19, 35], [8, 18, 3, 22, 1, 19],
				[25, 11, 30, 6, 32, 8], [11, 25, 6, 30, 4, 28]]
			for s in segs:
				line(arcs, s[0], s[1], s[2], s[3], Color(0.8, 0.92, 1.0))
				line(arcs, s[2], s[3], s[4], s[5], Color(0.8, 0.92, 1.0))
			_arc(arcs, 18, 18, 13.5, 12.8, 0.4, 1.5, Color(0.6, 0.8, 1.0, 0.8))
			_arc(arcs, 18, 18, 13.5, 12.8, 3.5, 4.6, Color(0.6, 0.8, 1.0, 0.8))
			g.blend_rect(arcs, Rect2i(0, 0, N, N), Vector2i.ZERO)
			_flat(im, arcs)
		"flask":
			var gl := _l()
			ellipse(gl, 18, 23, 10, 10, Color(0.62, 0.78, 0.88, 0.9))
			rect(gl, 15, 6, 6, 10, Color(0.62, 0.78, 0.88, 0.9))
			_put(im, gl, 0.4, 0.2)
			var liq := _l()
			ellipse(liq, 18, 23.5, 8.5, 8.5, Color(0.45, 1.0, 0.25))
			rect(liq, 9, 15, 19, 5, Color(0, 0, 0, 0))
			rect(liq, 10, 19, 17, 1, Color(0, 0, 0, 0))
			_neon(im, g, liq)
			var bub := _l()
			for p in [Vector3(15, 25, 1.6), Vector3(21, 22, 1.2), Vector3(19, 28, 1.0), Vector3(17, 12, 1.0), Vector3(19, 9, 0.8)]:
				ellipse(bub, p.x, p.y, p.z, p.z, Color(0.85, 1.0, 0.7))
			_flat(im, bub)
			var ck := _l()
			rect(ck, 14, 3, 8, 4, WOOD)
			rect(ck, 13, 6, 10, 1, Color(0.4, 0.35, 0.3))
			_put(im, ck)
			var lb := _l()
			rect(lb, 14, 21, 8, 6, Color(0.9, 0.85, 0.7))
			ellipse(lb, 18, 23.5, 2, 1.8, Color(0.15, 0.12, 0.12))
			px(lb, 17, 26, Color(0.15, 0.12, 0.12))
			px(lb, 19, 26, Color(0.15, 0.12, 0.12))
			_put(im, lb, 0.15, 0.2)
			var hl := _l()
			line(hl, 11, 20, 12, 17, Color(1, 1, 1, 0.9))
			line(hl, 16, 8, 16, 13, Color(1, 1, 1, 0.8))
			_flat(im, hl)
		"shuriken":
			var tr := _l()
			_arc(tr, 18, 18, 17.5, 16.6, 3.7, 4.6, Color(1.0, 0.45, 0.45, 0.45))
			_arc(tr, 18, 18, 17.5, 16.6, 0.6, 1.5, Color(1.0, 0.45, 0.45, 0.45))
			_flat(im, tr)
			var st := _l()
			var c := Vector2(18, 18)
			for i in 4:
				var a := TAU * i / 4.0 + 0.3
				poly(st, _rot(_pts([18, 1.5, 21.5, 13, 18, 18, 14.5, 13]), c, a), STEEL)
			_put(im, st, 0.32, 0.4)
			var edge := _l()
			for i in 4:
				var a := TAU * i / 4.0 + 0.3
				var p := _rot(_pts([18, 3, 18, 12]), c, a)
				line(edge, int(p[0].x), int(p[0].y), int(p[1].x), int(p[1].y), Color(1.0, 0.35, 0.35))
			_neon(im, g, edge)
			var hub := _l()
			_ring(hub, 18, 18, 4.5, 2.2, Color(0.25, 0.22, 0.3))
			_put(im, hub)
			var hole := _l()
			ellipse(hole, 18, 18, 1.6, 1.6, Color(1.0, 0.4, 0.4))
			_neon(im, g, hole)

		# ===== Модули героя =====
		"hp":
			var h := _l()
			ellipse(h, 12, 13, 7, 7, Color(0.86, 0.12, 0.3))
			ellipse(h, 24, 13, 7, 7, Color(0.86, 0.12, 0.3))
			poly(h, _pts([5, 15, 31, 15, 18, 32]), Color(0.86, 0.12, 0.3))
			_put(im, h, 0.32, 0.38)
			var pl := _l()
			poly(pl, _pts([19, 7, 30, 10, 31, 16, 19, 14]), METAL)
			rect(pl, 19, 15, 9, 3, METAL_D)
			_put(im, pl)
			var tb := _l()
			_tl(tb, Vector2(14, 6), Vector2(13, 1), 2.2, METAL_D)
			_tl(tb, Vector2(21, 6), Vector2(24, 1), 2.2, METAL_D)
			_put(im, tb)
			var ln := _l()
			var pts := [Vector2(6, 19), Vector2(12, 19), Vector2(14, 15), Vector2(17, 24), Vector2(20, 13), Vector2(23, 19), Vector2(30, 19)]
			for i in pts.size() - 1:
				_tl(ln, pts[i], pts[i + 1], 1.3, Color(0.4, 1.0, 1.0))
			_neon(im, g, ln)
			var hl := _l()
			ellipse(hl, 10, 10, 2, 1.5, Color(1.0, 0.7, 0.8))
			px(hl, 25, 11, Color(0.4, 1.0, 1.0))
			px(hl, 28, 12, Color(1.0, 0.4, 0.4))
			_flat(im, hl)
		"speed":
			var bt := _l()
			poly(bt, _pts([10, 4, 20, 4, 20, 20, 30, 23, 31, 28, 10, 28]), Color(0.3, 0.32, 0.55))
			_put(im, bt, 0.3, 0.38)
			var cuff := _l()
			rect(cuff, 9, 3, 12, 4, Color(0.42, 0.44, 0.7))
			rect(cuff, 11, 12, 9, 2, Color(0.2, 0.22, 0.4))
			_put(im, cuff)
			var sole := _l()
			rect(sole, 9, 28, 23, 3, PINK)
			_tl(sole, Vector2(12, 20), Vector2(19, 20), 1.2, CYAN)
			_neon(im, g, sole)
			var wing := _l()
			poly(wing, _pts([10, 10, 2, 5, 4, 10, 1, 12, 5, 15, 3, 18, 10, 17]), Color(0.85, 0.92, 1.0))
			_put(im, wing, 0.3, 0.3)
			var sp := _l()
			for i in 3:
				_tl(sp, Vector2(1, 22 + i * 4), Vector2(6 - i, 22 + i * 4), 1.0, Color(0.4, 0.95, 1.0))
			_neon(im, g, sp)
		"magnet":
			var m := _l()
			_arc(m, 18, 16, 13, 6.5, PI, TAU, Color(0.88, 0.16, 0.24))
			rect(m, 5, 16, 7, 9, Color(0.88, 0.16, 0.24))
			rect(m, 24, 16, 7, 9, Color(0.88, 0.16, 0.24))
			_put(im, m, 0.32, 0.38)
			var tips := _l()
			rect(tips, 5, 25, 7, 5, STEEL)
			rect(tips, 24, 25, 7, 5, STEEL)
			_put(im, tips)
			var fld := _l()
			_arc(fld, 18, 30, 10, 9, PI + 0.3, TAU - 0.3, Color(0.7, 0.45, 1.0))
			_arc(fld, 18, 30, 6, 5, PI + 0.3, TAU - 0.3, Color(0.7, 0.45, 1.0))
			for p in [Vector2i(17, 33), Vector2i(14, 34), Vector2i(21, 34)]:
				rect(fld, p.x, p.y, 2, 2, Color(0.75, 0.4, 1.0))
			_neon(im, g, fld)
			var hl := _l()
			line(hl, 8, 8, 12, 5, Color(1.0, 0.6, 0.6))
			_flat(im, hl)
		"regen":
			var cap := _l()
			poly(cap, _rot(_pts([12, 6, 24, 6, 24, 30, 12, 30]), Vector2(18, 18), 0.6), Color(0.85, 0.9, 0.95))
			_put(im, cap, 0.3, 0.32)
			var half := _l()
			poly(half, _rot(_pts([12.5, 18, 23.5, 18, 23.5, 29.5, 12.5, 29.5]), Vector2(18, 18), 0.6), Color(0.25, 0.85, 0.4))
			_neon(im, g, half)
			var cr := _l()
			rect(cr, 23, 3, 4, 12, Color(0.35, 1.0, 0.5))
			rect(cr, 19, 7, 12, 4, Color(0.35, 1.0, 0.5))
			_neon(im, g, cr)
			var bots := _l()
			for p in [Vector2i(6, 26), Vector2i(9, 31), Vector2i(4, 21), Vector2i(29, 22), Vector2i(31, 27)]:
				rect(bots, p.x, p.y, 2, 2, Color(0.6, 1.0, 0.7))
			_neon(im, g, bots)
			var hl := _l()
			rect(hl, 24, 4, 1, 4, WHITE)
			_flat(im, hl)
		"armor":
			var sh := _l()
			poly(sh, _pts([6, 5, 30, 5, 30, 18, 18, 33, 6, 18]), Color(0.56, 0.62, 0.74))
			_put(im, sh, 0.32, 0.4)
			var rim := _l()
			poly(rim, _pts([6, 5, 30, 5, 30, 8, 6, 8]), GOLD)
			_put(im, rim)
			var inner := _l()
			poly(inner, _pts([10, 10, 26, 10, 26, 18, 18, 28, 10, 18]), Color(0.38, 0.42, 0.55))
			_put(im, inner, 0.15, 0.25)
			var rune := _l()
			_tl(rune, Vector2(18, 12), Vector2(18, 25), 1.6, Color(0.45, 0.85, 1.0))
			_tl(rune, Vector2(18, 15), Vector2(23, 12), 1.4, Color(0.45, 0.85, 1.0))
			_tl(rune, Vector2(18, 15), Vector2(13, 12), 1.4, Color(0.45, 0.85, 1.0))
			_tl(rune, Vector2(18, 20), Vector2(22, 17), 1.2, Color(0.45, 0.85, 1.0))
			_neon(im, g, rune)
			var rv := _l()
			for p in [Vector2i(8, 11), Vector2i(27, 11), Vector2i(9, 17), Vector2i(26, 17)]:
				px(rv, p.x, p.y, Color(0.95, 0.85, 0.6))
			_flat(im, rv)
		"vamp":
			var ch := _l()
			rect(ch, 8, 6, 20, 18, Color(0.18, 0.16, 0.22))
			_put(im, ch, 0.3, 0.35)
			var pins := _l()
			for i in 4:
				rect(pins, 10 + i * 5, 3, 2, 3, GOLD)
				rect(pins, 10 + i * 5, 24, 2, 3, GOLD)
				rect(pins, 5, 8 + i * 4, 3, 2, GOLD)
				rect(pins, 28, 8 + i * 4, 3, 2, GOLD)
			_put(im, pins)
			var core := _l()
			rect(core, 12, 10, 12, 10, Color(0.55, 0.05, 0.15))
			_put(im, core, 0.2, 0.3)
			var fang := _l()
			poly(fang, _pts([13, 10, 17, 10, 15, 17]), Color(0.98, 0.95, 0.92))
			poly(fang, _pts([19, 10, 23, 10, 21, 17]), Color(0.98, 0.95, 0.92))
			_put(im, fang, 0.2, 0.25)
			var drop := _l()
			ellipse(drop, 21, 30, 3, 3.2, Color(1.0, 0.12, 0.25))
			poly(drop, _pts([18.2, 29.5, 21, 24, 23.8, 29.5]), Color(1.0, 0.12, 0.25))
			px(drop, 15, 18, Color(1.0, 0.12, 0.25))
			px(drop, 15, 19, Color(1.0, 0.12, 0.25))
			_neon(im, g, drop)
			var tr := _l()
			line(tr, 12, 21, 24, 21, Color(1.0, 0.3, 0.4))
			_neon(im, g, tr)
		"luck":
			var top := _l()
			poly(top, _pts([18, 3, 31, 10, 18, 17, 5, 10]), Color(0.98, 0.95, 0.88))
			_put(im, top, 0.15, 0.2)
			var lf := _l()
			poly(lf, _pts([5, 10, 18, 17, 18, 33, 5, 25]), Color(0.82, 0.78, 0.7))
			_put(im, lf, 0.1, 0.25)
			var rt := _l()
			poly(rt, _pts([18, 17, 31, 10, 31, 25, 18, 33]), Color(0.62, 0.58, 0.52))
			_put(im, rt, 0.1, 0.25)
			var pips := _l()
			ellipse(pips, 18, 10, 1.8, 1.2, Color(1.0, 0.8, 0.2))
			for p in [Vector2(9, 16), Vector2(14, 25), Vector2(11.5, 20.5)]:
				ellipse(pips, p.x, p.y, 1.3, 1.5, Color(1.0, 0.8, 0.2))
			for p in [Vector2(22, 19), Vector2(27, 16), Vector2(22, 27), Vector2(27, 24)]:
				ellipse(pips, p.x, p.y, 1.3, 1.5, Color(1.0, 0.8, 0.2))
			_neon(im, g, pips)
			var sp := _l()
			for c in [Vector2i(31, 3), Vector2i(4, 30)]:
				line(sp, c.x - 2, c.y, c.x + 2, c.y, Color(1.0, 0.95, 0.6))
				line(sp, c.x, c.y - 2, c.x, c.y + 2, Color(1.0, 0.95, 0.6))
			_neon(im, g, sp)

		# ===== Модули оружия =====
		"damage":
			var st := _l()
			poly(st, _pts([18, 2, 29, 10, 30, 25, 18, 34, 6, 25, 7, 10]), Color(0.35, 0.16, 0.18))
			_put(im, st, 0.3, 0.4)
			var fl := _l()
			poly(fl, _pts([18, 7, 24, 16, 23, 24, 18, 29, 13, 24, 12, 17, 15, 19]), Color(1.0, 0.35, 0.1))
			_neon(im, g, fl)
			var in2 := _l()
			poly(in2, _pts([18, 15, 21, 21, 18, 26, 15, 21]), Color(1.0, 0.85, 0.3))
			_neon(im, g, in2)
			var cr := _l()
			line(cr, 8, 12, 11, 15, Color(1.0, 0.45, 0.2))
			line(cr, 28, 13, 26, 17, Color(1.0, 0.45, 0.2))
			line(cr, 10, 26, 13, 28, Color(1.0, 0.45, 0.2))
			_neon(im, g, cr)
		"cooldown":
			var cyl := _l()
			rect(cyl, 11, 5, 14, 26, Color(0.3, 0.34, 0.46))
			_put(im, cyl, 0.3, 0.35)
			var fins := _l()
			for i in 5:
				rect(fins, 7, 8 + i * 5, 22, 2, METAL)
			_put(im, fins, 0.3, 0.3)
			var core := _l()
			rect(core, 15, 7, 6, 22, Color(0.25, 0.85, 1.0))
			_neon(im, g, core)
			var cap := _l()
			rect(cap, 10, 2, 16, 3, GOLD)
			rect(cap, 10, 31, 16, 3, GOLD)
			_put(im, cap)
			var ar := _l()
			_arc(ar, 18, 18, 17, 15.6, -2.6, -0.9, Color(0.5, 0.95, 1.0))
			poly(ar, _pts([26, 2, 31, 6, 26, 8]), Color(0.5, 0.95, 1.0))
			_arc(ar, 18, 18, 17, 15.6, 0.55, 2.2, Color(0.5, 0.95, 1.0))
			poly(ar, _pts([10, 34, 5, 30, 10, 28]), Color(0.5, 0.95, 1.0))
			_neon(im, g, ar)
			var hl := _l()
			rect(hl, 16, 9, 1, 18, Color(0.85, 1.0, 1.0))
			_flat(im, hl)
		"area":
			var w := _l()
			_arc(w, 18, 22, 17, 15.5, PI + 0.35, TAU - 0.35, Color(1.0, 0.75, 0.3))
			_arc(w, 18, 22, 12.5, 11, PI + 0.3, TAU - 0.3, Color(0.85, 0.45, 1.0))
			_neon(im, g, w)
			var dish := _l()
			ellipse(dish, 18, 22, 8, 3.6, Color(0.62, 0.66, 0.78))
			_put(im, dish, 0.3, 0.3)
			var base := _l()
			poly(base, _pts([14, 24, 22, 24, 25, 33, 11, 33]), METAL_D)
			_put(im, base)
			var em := _l()
			ellipse(em, 18, 20, 2.6, 2.6, Color(0.9, 0.55, 1.0))
			ellipse(em, 17.5, 19.5, 1.2, 1.2, WHITE)
			_neon(im, g, em)
			var dots := _l()
			for p in [Vector2i(3, 15), Vector2i(32, 15), Vector2i(10, 6), Vector2i(26, 6)]:
				rect(dots, p.x, p.y, 2, 2, Color(1.0, 0.85, 0.45))
			_neon(im, g, dots)
		"crit":
			var r := _l()
			_ring(r, 18, 18, 14, 11.5, Color(0.25, 0.26, 0.34))
			_put(im, r, 0.35, 0.4)
			var lens := _l()
			ellipse(lens, 18, 18, 11, 11, Color(0.12, 0.2, 0.32, 0.92))
			_put(im, lens, 0.25, 0.2)
			var cr := _l()
			rect(cr, 17, 2, 2, 11, Color(1.0, 0.25, 0.3))
			rect(cr, 17, 23, 2, 11, Color(1.0, 0.25, 0.3))
			rect(cr, 2, 17, 11, 2, Color(1.0, 0.25, 0.3))
			rect(cr, 23, 17, 11, 2, Color(1.0, 0.25, 0.3))
			_ring(cr, 18, 18, 6.5, 5.5, Color(1.0, 0.3, 0.35))
			_neon(im, g, cr)
			var dot := _l()
			ellipse(dot, 18, 18, 2, 2, Color(1.0, 0.85, 0.85))
			_neon(im, g, dot)
			var gl := _l()
			_arc(gl, 18, 18, 9.5, 8.5, 3.6, 4.4, Color(0.6, 0.85, 1.0, 0.8))
			_flat(im, gl)
		"multi":
			for i in 3:
				var o := Vector2(i * 6, i * 6)
				var chip := _l()
				rect(chip, 4 + int(o.x), 4 + int(o.y), 16, 16, Color(0.22, 0.2, 0.3).lightened(i * 0.08))
				_put(im, chip, 0.3, 0.38)
				var c := _l()
				var col: Color = [Color(1.0, 0.4, 0.8), Color(0.75, 0.45, 1.0), Color(0.4, 0.9, 1.0)][i]
				rect(c, 8 + int(o.x), 8 + int(o.y), 8, 8, col)
				_neon(im, g, c)
				var pins := _l()
				for k in 3:
					px(pins, 7 + k * 4 + int(o.x), 3 + int(o.y), GOLD)
					px(pins, 3 + int(o.x), 7 + k * 4 + int(o.y), GOLD)
				_flat(im, pins)
			var hl := _l()
			rect(hl, 21, 21, 2, 2, WHITE)
			_flat(im, hl)
		"duration":
			var fr := _l()
			rect(fr, 7, 2, 22, 4, WOOD)
			rect(fr, 7, 30, 22, 4, WOOD)
			rect(fr, 8, 6, 2, 24, Color(0.4, 0.26, 0.16))
			rect(fr, 26, 6, 2, 24, Color(0.4, 0.26, 0.16))
			_put(im, fr)
			var gl := _l()
			poly(gl, _pts([11, 6, 25, 6, 25, 9, 19.5, 18, 25, 27, 25, 30, 11, 30, 11, 27, 16.5, 18, 11, 9]), Color(0.65, 0.85, 0.95, 0.55))
			_put(im, gl, 0.3, 0.1)
			var sand := _l()
			poly(sand, _pts([13, 9, 23, 9, 18.5, 16, 17.5, 16]), Color(0.5, 0.95, 1.0))
			poly(sand, _pts([12, 29, 24, 29, 22, 25, 18, 22, 14, 25]), Color(0.5, 0.95, 1.0))
			rect(sand, 17, 16, 2, 7, Color(0.6, 1.0, 1.0))
			_neon(im, g, sand)
			var st := _l()
			for c in [Vector2i(3, 14), Vector2i(32, 22)]:
				line(st, c.x - 2, c.y, c.x + 2, c.y, Color(0.7, 1.0, 1.0))
				line(st, c.x, c.y - 2, c.x, c.y + 2, Color(0.7, 1.0, 1.0))
			_neon(im, g, st)
	return _finish(im, g)
