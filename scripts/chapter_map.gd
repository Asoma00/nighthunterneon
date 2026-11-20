extends RefCounted
## Собранные вручную карты глав героев: путь-коридор с залами и арена владыки в конце.
## Карта неизменна (одни и те же точки при каждом заходе), стены — свои объекты главы.
## Таймер на такой карте — ограничение: дойти до арены и победить владыку, пока не вышло время.

const HeroCh := preload("res://scripts/hero_chapters.gd")

const MAPS := {
	"vega_0": {"pts": [Vector2(0, 0), Vector2(151, -868), Vector2(593, -1423), Vector2(1280, -1670), Vector2(1982, -1137), Vector2(2260, -203), Vector2(3044, 29)], "w": 300, "rooms": [[2, 340], [4, 461]], "arena": 680},
	"vega_1": {"pts": [Vector2(0, 0), Vector2(903, -321), Vector2(1587, -235), Vector2(1891, -847), Vector2(2725, -854), Vector2(3100, -182), Vector2(2638, 473), Vector2(2514, 1359)], "w": 290, "rooms": [[3, 340], [4, 359]], "arena": 680},
	"vega_2": {"pts": [Vector2(0, 0), Vector2(266, 696), Vector2(-35, 1433), Vector2(-678, 1757), Vector2(-1376, 1271), Vector2(-2034, 1743), Vector2(-2237, 2438), Vector2(-2913, 2878), Vector2(-3512, 2496), Vector2(-3623, 1804)], "w": 280, "rooms": [[3, 340], [4, 410], [6, 340]], "arena": 680},
	"rin_0": {"pts": [Vector2(0, 0), Vector2(568, -724), Vector2(1418, -606), Vector2(2107, -1220), Vector2(2069, -1916), Vector2(2746, -2368), Vector2(2903, -3221)], "w": 300, "rooms": [[2, 438], [4, 340]], "arena": 680},
	"rin_1": {"pts": [Vector2(0, 0), Vector2(-203, 818), Vector2(207, 1471), Vector2(974, 1735), Vector2(1127, 2640), Vector2(1908, 3154), Vector2(2535, 2875), Vector2(2628, 1924)], "w": 290, "rooms": [[3, 401], [4, 508]], "arena": 680},
	"rin_2": {"pts": [Vector2(0, 0), Vector2(-65, -919), Vector2(217, -1619), Vector2(1006, -1794), Vector2(1487, -2527), Vector2(1194, -3144), Vector2(592, -3464), Vector2(-101, -3254), Vector2(-839, -3485), Vector2(-1280, -4064)], "w": 280, "rooms": [[3, 408], [4, 340], [6, 340]], "arena": 680},
	"bram_0": {"pts": [Vector2(0, 0), Vector2(-748, -73), Vector2(-1068, -685), Vector2(-1904, -912), Vector2(-2076, -1727), Vector2(-1821, -2491), Vector2(-2120, -3380)], "w": 300, "rooms": [[2, 340], [4, 385]], "arena": 680},
	"bram_1": {"pts": [Vector2(0, 0), Vector2(260, 726), Vector2(1026, 879), Vector2(1616, 392), Vector2(1820, -527), Vector2(1339, -1231), Vector2(462, -1351), Vector2(-287, -1907)], "w": 290, "rooms": [[3, 355], [4, 442]], "arena": 680},
	"bram_2": {"pts": [Vector2(0, 0), Vector2(6, 925), Vector2(729, 1242), Vector2(760, 1952), Vector2(395, 2698), Vector2(-376, 3181), Vector2(-602, 4011), Vector2(-1457, 4171), Vector2(-2093, 3773)], "w": 280, "rooms": [[2, 340], [4, 431], [6, 459]], "arena": 680},
	"kira_0": {"pts": [Vector2(0, 0), Vector2(-720, -143), Vector2(-1079, -805), Vector2(-891, -1644), Vector2(-345, -2099), Vector2(-209, -2895), Vector2(323, -3321)], "w": 300, "rooms": [[2, 340], [4, 340]], "arena": 680},
	"kira_1": {"pts": [Vector2(0, 0), Vector2(-800, -334), Vector2(-1400, -1082), Vector2(-1287, -1984), Vector2(-504, -2556), Vector2(212, -2155), Vector2(521, -1398)], "w": 290, "rooms": [[2, 499], [4, 409]], "arena": 680},
	"kira_2": {"pts": [Vector2(0, 0), Vector2(-318, 605), Vector2(-1213, 488), Vector2(-1539, -126), Vector2(-2412, -135), Vector2(-3046, 555), Vector2(-2711, 1245), Vector2(-1980, 1584), Vector2(-1773, 2520)], "w": 280, "rooms": [[2, 340], [4, 472], [6, 367]], "arena": 680},
	"skyla_0": {"pts": [Vector2(0, 0), Vector2(-776, 186), Vector2(-1359, -459), Vector2(-1247, -1189), Vector2(-1540, -2077), Vector2(-2418, -2168), Vector2(-3298, -1788)], "w": 300, "rooms": [[2, 340], [4, 462]], "arena": 680},
	"skyla_1": {"pts": [Vector2(0, 0), Vector2(330, 810), Vector2(-231, 1418), Vector2(-122, 2379), Vector2(320, 2915), Vector2(-14, 3549), Vector2(-819, 3982), Vector2(-1629, 3715)], "w": 290, "rooms": [[3, 340], [4, 340]], "arena": 680},
	"skyla_2": {"pts": [Vector2(0, 0), Vector2(582, -787), Vector2(1336, -801), Vector2(1921, -1367), Vector2(2830, -1289), Vector2(3358, -589), Vector2(4191, -598), Vector2(4572, 160), Vector2(4569, 1053)], "w": 280, "rooms": [[2, 354], [4, 477], [6, 432]], "arena": 680},
	"orm_0": {"pts": [Vector2(0, 0), Vector2(63, -945), Vector2(550, -1596), Vector2(398, -2274), Vector2(-70, -2858), Vector2(-98, -3660), Vector2(429, -4161)], "w": 300, "rooms": [[2, 340], [4, 340]], "arena": 680},
	"orm_1": {"pts": [Vector2(0, 0), Vector2(-549, -794), Vector2(-1388, -905), Vector2(-1813, -281), Vector2(-2696, 73), Vector2(-2664, 980), Vector2(-2150, 1533), Vector2(-1308, 1352)], "w": 290, "rooms": [[3, 344], [4, 498]], "arena": 680},
	"orm_2": {"pts": [Vector2(0, 0), Vector2(-880, 354), Vector2(-1674, 209), Vector2(-2044, -404), Vector2(-2086, -1223), Vector2(-1469, -1732), Vector2(-710, -1492), Vector2(72, -1945), Vector2(448, -2721)], "w": 280, "rooms": [[2, 340], [4, 399], [6, 395]], "arena": 680},
	"mora_0": {"pts": [Vector2(0, 0), Vector2(2, 787), Vector2(-712, 1429), Vector2(-715, 2408), Vector2(-86, 2780), Vector2(422, 3576)], "w": 300, "rooms": [[2, 520], [3, 340]], "arena": 680},
	"mora_1": {"pts": [Vector2(0, 0), Vector2(-636, 364), Vector2(-889, 1118), Vector2(-1415, 1549), Vector2(-1631, 2289), Vector2(-2283, 2548), Vector2(-2722, 3385), Vector2(-2254, 4092)], "w": 290, "rooms": [[3, 340], [4, 340]], "arena": 680},
	"mora_2": {"pts": [Vector2(0, 0), Vector2(-745, 564), Vector2(-833, 1425), Vector2(-1263, 2062), Vector2(-2124, 1831), Vector2(-2207, 1048), Vector2(-2783, 378), Vector2(-3479, 385), Vector2(-3815, -461)], "w": 280, "rooms": [[2, 368], [4, 387], [6, 340]], "arena": 680},
	"zephyr_0": {"pts": [Vector2(0, 0), Vector2(881, -9), Vector2(1642, -588), Vector2(2395, -386), Vector2(3063, -577), Vector2(3136, -1346), Vector2(3729, -1690)], "w": 300, "rooms": [[2, 360], [4, 340]], "arena": 680},
	"zephyr_1": {"pts": [Vector2(0, 0), Vector2(-602, 530), Vector2(-1359, 424), Vector2(-1933, 1091), Vector2(-2805, 1068), Vector2(-3523, 625), Vector2(-4212, 768), Vector2(-4469, 1475)], "w": 290, "rooms": [[3, 462], [4, 433]], "arena": 680},
	"zephyr_2": {"pts": [Vector2(0, 0), Vector2(-514, 610), Vector2(-1381, 773), Vector2(-1908, 1597), Vector2(-2798, 1998), Vector2(-3125, 2848), Vector2(-2869, 3783), Vector2(-3339, 4320), Vector2(-4044, 4129)], "w": 280, "rooms": [[2, 481], [4, 511], [6, 340]], "arena": 680},
	"iris_0": {"pts": [Vector2(0, 0), Vector2(717, 607), Vector2(1635, 578), Vector2(2179, -206), Vector2(2925, -576), Vector2(3092, -1437)], "w": 300, "rooms": [[2, 497], [3, 412]], "arena": 680},
	"iris_1": {"pts": [Vector2(0, 0), Vector2(-136, -902), Vector2(220, -1552), Vector2(1175, -1450), Vector2(1761, -1949), Vector2(2505, -1938), Vector2(3208, -1449), Vector2(3045, -757)], "w": 290, "rooms": [[3, 359], [4, 340]], "arena": 680},
	"iris_2": {"pts": [Vector2(0, 0), Vector2(475, -598), Vector2(1291, -616), Vector2(1951, 5), Vector2(2630, -194), Vector2(3147, 516), Vector2(4004, 720), Vector2(4590, 254), Vector2(4421, -428)], "w": 280, "rooms": [[2, 415], [4, 340], [6, 349]], "arena": 680},
	"lyra_0": {"pts": [Vector2(0, 0), Vector2(307, 926), Vector2(-256, 1552), Vector2(-73, 2460), Vector2(-473, 3149), Vector2(24, 3837)], "w": 300, "rooms": [[2, 422], [3, 377]], "arena": 680},
	"lyra_1": {"pts": [Vector2(0, 0), Vector2(-593, -599), Vector2(-1266, -762), Vector2(-1946, -505), Vector2(-2848, -796), Vector2(-3766, -500), Vector2(-4305, -1221), Vector2(-4237, -1994)], "w": 290, "rooms": [[3, 340], [4, 520]], "arena": 680},
	"lyra_2": {"pts": [Vector2(0, 0), Vector2(877, -375), Vector2(892, -1111), Vector2(1351, -1782), Vector2(1969, -2097), Vector2(2922, -2006), Vector2(3243, -1216), Vector2(2818, -548), Vector2(2094, -669)], "w": 280, "rooms": [[2, 340], [4, 340], [6, 391]], "arena": 680},
	"sol_0": {"pts": [Vector2(0, 0), Vector2(-407, 578), Vector2(-1070, 410), Vector2(-1601, -85), Vector2(-1530, -914), Vector2(-2023, -1443), Vector2(-2803, -1150)], "w": 300, "rooms": [[2, 340], [4, 340]], "arena": 680},
	"sol_1": {"pts": [Vector2(0, 0), Vector2(273, 742), Vector2(995, 1079), Vector2(930, 1766), Vector2(267, 2091), Vector2(205, 2949), Vector2(-396, 3436), Vector2(-1253, 3406)], "w": 290, "rooms": [[3, 340], [4, 340]], "arena": 680},
	"sol_2": {"pts": [Vector2(0, 0), Vector2(760, 232), Vector2(1508, -35), Vector2(1582, -782), Vector2(1172, -1452), Vector2(404, -1447), Vector2(31, -2062), Vector2(-784, -2313), Vector2(-1589, -1787)], "w": 280, "rooms": [[2, 350], [4, 368], [6, 340]], "arena": 680},
	"volt_0": {"pts": [Vector2(0, 0), Vector2(-345, -661), Vector2(-232, -1436), Vector2(322, -2017), Vector2(134, -2819), Vector2(656, -3536), Vector2(1521, -3775)], "w": 300, "rooms": [[2, 363], [4, 403]], "arena": 680},
	"volt_1": {"pts": [Vector2(0, 0), Vector2(862, 155), Vector2(1473, 853), Vector2(1378, 1717), Vector2(485, 2080), Vector2(151, 2782), Vector2(-690, 2719), Vector2(-1270, 3425)], "w": 290, "rooms": [[3, 458], [4, 367]], "arena": 680},
	"volt_2": {"pts": [Vector2(0, 0), Vector2(-530, -548), Vector2(-632, -1233), Vector2(-1434, -1746), Vector2(-1671, -2610), Vector2(-1120, -3204), Vector2(-1287, -3913), Vector2(-2065, -4138), Vector2(-2600, -4671)], "w": 280, "rooms": [[2, 340], [4, 410], [6, 340]], "arena": 680},
	"kai_0": {"pts": [Vector2(0, 0), Vector2(-551, -714), Vector2(-142, -1409), Vector2(-156, -2255), Vector2(409, -2973), Vector2(1225, -3136)], "w": 300, "rooms": [[2, 385], [3, 426]], "arena": 680},
	"kai_1": {"pts": [Vector2(0, 0), Vector2(-860, 334), Vector2(-1472, -180), Vector2(-2393, 1), Vector2(-3053, -465), Vector2(-3037, -1294), Vector2(-3774, -1607), Vector2(-4197, -2214)], "w": 290, "rooms": [[3, 397], [4, 397]], "arena": 680},
	"kai_2": {"pts": [Vector2(0, 0), Vector2(-268, 840), Vector2(-61, 1703), Vector2(-441, 2544), Vector2(-34, 3348), Vector2(-419, 4093), Vector2(-185, 4943), Vector2(-795, 5511), Vector2(-1023, 6257)], "w": 280, "rooms": [[2, 487], [4, 438], [6, 433]], "arena": 680},
}

var hero := ""
var step := 0
var pts: Array = []
var w := 300.0
var rooms: Array = []      # [индекс точки, радиус]
var arena_r := 680.0
var cum: Array = []        # длина пути до каждой точки
var total := 0.0
var locked := false        # арена запечатана: бой с владыкой
var _shapes: Array = []    # ["c", центр, r] / ["s", a, b, w]
var _place := {}           # чанк -> [[pos, kind, rot, light], ...]


static func for_level(i: int):
	if not HeroCh.is_hero_level(i):
		return null
	var key := "%s_%d" % [HeroCh.hero_of(i), HeroCh.step_of(i)]
	if not MAPS.has(key):
		return null
	var m = load("res://scripts/chapter_map.gd").new()
	m._setup(HeroCh.hero_of(i), HeroCh.step_of(i), MAPS[key])
	return m


func _setup(h: String, st: int, d: Dictionary) -> void:
	hero = h
	step = st
	pts = d["pts"]
	w = float(d["w"])
	rooms = d["rooms"]
	arena_r = float(d["arena"])
	cum = [0.0]
	for i in range(1, pts.size()):
		cum.append(float(cum[-1]) + (pts[i] - pts[i - 1]).length())
	total = cum[-1]
	for i in range(pts.size() - 1):
		_shapes.append(["s", pts[i], pts[i + 1], w])
	_shapes.append(["c", pts[0], w])
	for r in rooms:
		_shapes.append(["c", pts[int(r[0])], float(r[1])])
	_shapes.append(["c", arena_center(), arena_r])
	_build_layout()


func arena_center() -> Vector2:
	return pts[-1]


func room_center(k: int) -> Vector2:
	return pts[int(rooms[k][0])]


func room_radius(k: int) -> float:
	return float(rooms[k][1])


# ---------------- Геометрия ----------------

static func _closest_on_seg(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.001:
		return a
	return a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0)


func _sd_shape(p: Vector2, s: Array) -> float:
	if s[0] == "c":
		return p.distance_to(s[1]) - float(s[2])
	return p.distance_to(_closest_on_seg(p, s[1], s[2])) - float(s[3])


## Расстояние со знаком до края карты (меньше нуля — внутри).
func sd(p: Vector2) -> float:
	if locked:
		return p.distance_to(arena_center()) - arena_r
	var best := INF
	for s in _shapes:
		best = minf(best, _sd_shape(p, s))
	return best


func inside(p: Vector2, margin := 0.0) -> bool:
	return sd(p) <= -margin


## Удержать круг радиуса r внутри карты.
func clamp_pos(p: Vector2, r: float) -> Vector2:
	if locked:
		var c := arena_center()
		var lim := maxf(arena_r - r, 0.0)
		var d := p - c
		return p if d.length() <= lim else c + d.normalized() * lim
	var best := INF
	var bs: Array = []
	for s in _shapes:
		var v := _sd_shape(p, s)
		if v < best:
			best = v
			bs = s
		if v <= -r:
			return p
	var q: Vector2 = bs[1] if bs[0] == "c" else _closest_on_seg(p, bs[1], bs[2])
	var lim2: float = maxf(float(bs[2] if bs[0] == "c" else bs[3]) - r, 0.0)
	var dd := p - q
	if dd.length() < 0.01:
		return q
	return q + dd.normalized() * lim2


## Пройденная часть пути (по ближайшей точке на линии пути).
func progress(p: Vector2) -> float:
	var best := INF
	var out := 0.0
	for i in range(pts.size() - 1):
		var q := _closest_on_seg(p, pts[i], pts[i + 1])
		var d := p.distance_squared_to(q)
		if d < best:
			best = d
			out = float(cum[i]) + q.distance_to(pts[i])
	return out


func point_at(s: float) -> Vector2:
	s = clampf(s, 0.0, total)
	for i in range(pts.size() - 1):
		if s <= float(cum[i + 1]) or i == pts.size() - 2:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			return a + (b - a).normalized() * (s - float(cum[i]))
	return pts[-1]


func dir_at(s: float) -> Vector2:
	s = clampf(s, 0.0, total)
	for i in range(pts.size() - 1):
		if s <= float(cum[i + 1]) or i == pts.size() - 2:
			return (pts[i + 1] - pts[i]).normalized()
	return Vector2.RIGHT


## Точка появления врага: вдоль пути впереди или позади героя, вне его взгляда в упор.
func spawn_point(anchor: Vector2, rng: RandomNumberGenerator, avoid: Array) -> Vector2:
	if locked:
		for t in 6:
			var p := arena_center() + Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(arena_r * 0.55, arena_r - 40.0)
			if _far(p, avoid, 330.0):
				return p
		return arena_center() + Vector2.RIGHT.rotated(rng.randf() * TAU) * (arena_r - 40.0)
	var s0 := progress(anchor)
	var p2 := anchor
	for t in 6:
		var sgn := 1.0 if rng.randf() < 0.65 else -1.0
		var s := s0 + sgn * rng.randf_range(520.0, 900.0)
		if s < 0.0 or s > total:
			s = s0 - sgn * rng.randf_range(520.0, 900.0)
		s = clampf(s, 0.0, total)
		var d := dir_at(s)
		p2 = point_at(s) + d.orthogonal() * rng.randf_range(-0.7, 0.7) * w
		if _far(p2, avoid, 420.0):
			return p2
	return p2


static func _far(p: Vector2, avoid: Array, r: float) -> bool:
	for a in avoid:
		if p.distance_to(a) < r:
			return false
	return true


# ---------------- Стены и убранство (один раз, неизменно) ----------------

func _kind(k: String) -> String:
	return "c_%s_%s" % [hero, k]


func _add_place(p: Vector2, kind: String, rot: float, light := false) -> void:
	var key := Vector2i(floori(p.x / 768.0), floori(p.y / 768.0))
	if not _place.has(key):
		_place[key] = []
	_place[key].append([p, kind, rot, light])


func _ring_row(off: float, min_sd: float, spacing: float, kinds: Array, light_every: int) -> void:
	var acc: Array = []
	var n := 0
	for s in _shapes:
		var cands: Array = []
		if s[0] == "s":
			var a: Vector2 = s[1]
			var b: Vector2 = s[2]
			var dir := (b - a).normalized()
			var ln := a.distance_to(b)
			var cnt := maxi(1, int(ln / spacing))
			for i in cnt + 1:
				var c := a + dir * (ln * i / cnt)
				for sg in [-1.0, 1.0]:
					cands.append([c + dir.orthogonal() * sg * (float(s[3]) + off), -dir.angle()])
		else:
			var rr: float = float(s[2]) + off
			var cnt2 := maxi(6, int(TAU * rr / spacing))
			for i in cnt2:
				var an := TAU * i / cnt2
				cands.append([s[1] + Vector2.RIGHT.rotated(an) * rr, -(an + PI / 2.0)])
		for c in cands:
			var p: Vector2 = c[0]
			var lock_save := locked
			locked = false
			var v := sd(p)
			locked = lock_save
			if v < min_sd:
				continue
			var near := false
			for q in acc:
				if p.distance_squared_to(q) < spacing * spacing * 0.55:
					near = true
					break
			if near:
				continue
			acc.append(p)
			n += 1
			var kind: String = kinds[n % kinds.size()]
			_add_place(p, kind, c[1], light_every > 0 and n % light_every == 0)


func _build_layout() -> void:
	# Три ряда: стена вплотную к краю, за ней крупные объекты, дальше — плотная чаща
	_ring_row(55.0, 35.0, 125.0, [_kind("w"), _kind("w"), _kind("w"), _kind("b")], 7)
	_ring_row(210.0, 150.0, 175.0, [_kind("b"), _kind("w")], 0)
	_ring_row(380.0, 300.0, 230.0, [_kind("b")], 0)
	# Убранство внутри: у стен коридора и по краю залов
	var k := 0
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var dir := (b - a).normalized()
		var ln := a.distance_to(b)
		var cnt := int(ln / 520.0)
		for j in cnt:
			k += 1
			var p := a + dir * (ln * (j + 0.5) / cnt) + dir.orthogonal() * (w - 55.0) * (1.0 if k % 2 == 0 else -1.0)
			if p.distance_to(pts[0]) > 260.0:
				_add_place(p, _kind("d"), -dir.angle(), k % 3 == 0)
	for r in rooms:
		var c: Vector2 = pts[int(r[0])]
		var rr := float(r[1]) - 70.0
		for j in 5:
			var an := TAU * j / 5.0 + 0.4
			var p := c + Vector2.RIGHT.rotated(an) * rr
			_add_place(p, _kind("d"), -an, j == 0)
	var ac := arena_center()
	for j in 8:
		var an := TAU * j / 8.0
		_add_place(ac + Vector2.RIGHT.rotated(an) * (arena_r - 60.0), _kind("d"), -an, j % 2 == 0)


func placements(key: Vector2i) -> Array:
	return _place.get(key, [])
