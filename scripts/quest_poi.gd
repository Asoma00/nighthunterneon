extends Node2D
## Места для заданий на карте боя:
##  • cache   — Тайник: спрятан в стороне. Встаньте рядом на 1.2 с — внутри материалы.
##  • puzzle  — Рунная загадка: центральный камень и 4 рунных столба. Встаньте на камень —
##              он покажет порядок цветов. Пройдите по столбам в этом порядке.
##              Ошибка — столбы гаснут и зовут стражу. Камень можно перечитать.
##  • beacons — Сигнальные маяки: три маяка вокруг. Зажгите все (по 2 с в круге)
##              за 75 секунд после первого.

const Pixel := preload("res://scripts/pixel.gd")
const Fx := preload("res://scripts/fx.gd")
const Props3D := preload("res://scripts/props3d.gd")

const INFO := {
	"cache": {"name": "Тайник", "color": Color(1.0, 0.75, 0.35)},
	"puzzle": {"name": "Рунная загадка", "color": Color(0.55, 0.65, 1.0)},
	"beacons": {"name": "Сигнальные маяки", "color": Color(0.4, 1.0, 0.85)},
	"captive": {"name": "Пленник", "color": Color(1.0, 0.85, 0.5)},
	"part": {"name": "Часть оружия", "color": Color(1.0, 0.6, 0.25)},
}
const Meta := preload("res://scripts/meta.gd")
const Data := preload("res://scripts/data.gd")
const FREE_T := 3.0
var hid := ""              # чей герой (пленник / часть оружия)
var _hero_spr: Sprite3D
const RUNE_COLORS := [Color(1.0, 0.35, 0.35), Color(0.35, 1.0, 0.45), Color(0.4, 0.6, 1.0), Color(1.0, 0.85, 0.3), Color(0.85, 0.7, 1.0)]
const RUNE_NAMES := ["огонь", "лист", "вода", "солнце", "звезда"]
## Имена рун для загадок: [именительный, родительный]
const RUNE_WORDS := [["Пламя", "пламени"], ["Лист", "листа"], ["Вода", "воды"], ["Солнце", "солнца"], ["Звезда", "звезды"]]
const ORD := ["первым", "вторым", "третьим", "четвёртым"]
const ROMAN := ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ"]

# Загадка: 5 столбов, верный порядок — 4 руны из 5, одна лишняя.
# Порядок нигде не показан: его выводят из подсказок — у камня, у духа-странника,
# на скрижали в округе. Подсказки подбираются так, чтобы решение было единственным.
var _clues: Array = []        # [тип, a, b] — все подсказки загадки
var _clue_src: Array = []     # откуда каждая: "stone" / "spirit" / "tablet"
var _found: Array = []        # какие найдены
var _spirit_pos := Vector2.ZERO
var _tablet_pos := Vector2.ZERO
var _spirit_say := 0.0
var _spirit_label: Label3D
var _tablet_label: Label3D

var main: Node2D
var kind := "cache"
var state := "idle"      # idle → active → done
var life := 150.0
var found := false       # тайник замечен (подошли близко) — показываем стрелку
var _t := 0.0
var _hold := 0.0
var _models: Array = []
var _labels: Array = []        # Label3D над столбами/маяками
var _seq_labels: Array = []    # порядок над камнем
const GLYPHS := ["▲", "◆", "●", "✚", "★"]

# Загадка
var _pillars: Array = []     # позиции столбов (локальные)
var _pillar_rune: Array = [] # какой цвет на каком столбе
var _seq: Array = []         # нужный порядок цветов
var _step := 0
var _show_t := 0.0           # сколько ещё показывать порядок над камнем
var _stand := -1             # на каком столбе стоит герой
var _fail_flash := 0.0

# Маяки
var _beacons: Array = []     # позиции
var _lit: Array = []
var _bhold: Array = []
var _timer := 0.0


func color() -> Color:
	return INFO[kind]["color"]


func title() -> String:
	if kind == "captive":
		return "Пленник: " + str(Data.CHARACTERS[hid]["name"])
	if kind == "part":
		return "Часть: " + str(Data.WEAPONS[Data.CHARACTERS[hid]["weapon"]]["name"])
	return INFO[kind]["name"]


## Стрелка у края экрана: тайник — только если его ищут по заданию или он уже замечен.
func arrow_visible() -> bool:
	if state == "done":
		return false
	if kind == "cache":
		return false   # тайник ищут глазами — стрелки нет
	return true


func _ready() -> void:
	z_index = -10
	match kind:
		"captive":
			life = 200.0
			_build_cage()
		"part":
			life = 90.0
			_build_part()
		"cache":
			# Тайник выглядит как обычный ящик среди декора — без вспышек и стрелок
			_add_model("crate%d" % (randi() % 2), Vector2.ZERO, 1.0)
		"puzzle":
			_add_model("obelisk1", Vector2(0, -40), 1.0)
			var order := [0, 1, 2, 3, 4]
			order.shuffle()
			_pillar_rune = order
			for i in 5:
				var p := Vector2.RIGHT.rotated(TAU * i / 5.0 - PI / 2.0) * Vector2(280, 215)
				_pillars.append(p)
				_add_model("pillar%d" % (i % 2), p + Vector2(0, -60), 0.8)
				var rc: Color = RUNE_COLORS[order[i]]
				_labels.append(_add_label(GLYPHS[order[i]], p, 2.3, rc, 140))
			var all := [0, 1, 2, 3, 4]
			all.shuffle()
			_seq = all.slice(0, 4)
			_make_clues()
			_labels.append(_add_label("РУННЫЙ КАМЕНЬ", Vector2.ZERO, 3.2, color(), 44))
			# Дух-странник и скрижаль — где-то в округе, без стрелок
			_spirit_pos = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(480.0, 720.0)
			_tablet_pos = (-_spirit_pos).rotated(randf_range(-1.0, 1.0)).normalized() * randf_range(520.0, 780.0)
			_add_model("statue0", _tablet_pos + Vector2(0, -40), 0.8)
			_tablet_label = _add_label("", _tablet_pos, 2.0, Color(0.85, 0.85, 0.95), 64)
			_tablet_label.visible = false
			_spirit_label = _add_label("", _spirit_pos, 2.6, Color(0.6, 0.95, 1.0), 40)
			_spirit_label.visible = false
			var sp := Sprite3D.new()
			sp.texture = Pixel.frames("villager_%d" % (randi() % 4))["base"][0]
			sp.pixel_size = 0.03
			sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			sp.modulate = Color(0.5, 0.95, 1.0, 0.55)
			sp.shaded = false
			main.place3d(sp, position + _spirit_pos)
			sp.position.y += 0.4
			_models.append(sp)
		"beacons":
			for i in 3:
				var p := Vector2.RIGHT.rotated(TAU * i / 3.0 + randf() * 0.6) * randf_range(420.0, 620.0)
				_beacons.append(p)
				_lit.append(false)
				_bhold.append(0.0)
				_add_model("lamp0" if i % 2 == 0 else "obelisk0", p + Vector2(0, -95), 1.2)
				_labels.append(_add_label("МАЯК %d\n○" % (i + 1), p, 3.0, color(), 56))


func _add_label(text: String, at: Vector2, h: float, col: Color, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = size
	l.outline_size = 14
	l.pixel_size = 0.006
	l.modulate = Color(col.lerp(Color(0.82, 0.82, 0.88), 0.45), 0.7)   # без свечения — не бросается в глаза
	l.outline_modulate = Color(0.04, 0.02, 0.08)
	l.no_depth_test = true
	main.place3d(l, position + at)
	l.position.y += h
	_models.append(l)
	return l


func _add_model(key: String, at: Vector2, k: float) -> void:
	var m: Node3D = Props3D.build(key, RandomNumberGenerator.new())
	if m == null:
		return
	m.scale *= k
	main.place3d(m, position + at)
	_models.append(m)


func _exit_tree() -> void:
	for m in _models:
		if is_instance_valid(m):
			m.queue_free()


func _near(p: Vector2, r: float) -> bool:
	for pl in main.players:
		if not pl._dead and pl.position.distance_to(position + p) < r:
			return true
	return false


func _far_from_all(d: float) -> bool:
	for pl in main.players:
		if pl.position.distance_to(position) < d:
			return false
	return true


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if main.game_over:
		return
	if state == "done":
		life -= delta
		if life <= 0.0:
			queue_free()
		return
	life -= delta
	if life <= 0.0 or _far_from_all(3200.0):
		queue_free()
		return
	match kind:
		"captive":
			_tick_captive(delta)
		"part":
			_tick_part(delta)
		"cache":
			_tick_cache(delta)
		"puzzle":
			_tick_puzzle(delta)
		"beacons":
			_tick_beacons(delta)


# ---------- Тайник ----------

func _tick_cache(delta: float) -> void:
	if not found and _near(Vector2.ZERO, 260.0):
		found = true
	var inside := _near(Vector2.ZERO, 70.0)
	_hold = minf(1.2, _hold + delta) if inside else maxf(0.0, _hold - delta * 2.0)
	if _hold >= 1.2:
		Sound.play("chest", 0.0)
		main.run["caches"] = int(main.run["caches"]) + 1
		main.drop_material(position, "scrap", randi_range(4, 7))
		if randf() < 0.6:
			main.drop_material(position + Vector2(24, 0), "chips", randi_range(1, 2))
		if randf() < 0.12:
			main.drop_material(position + Vector2(-24, 0), "cores", 1)
		for i in 6:
			main.drop_gem_at(position + Vector2.RIGHT.rotated(TAU * i / 6.0) * 60.0, 4)
		# Изредка в тайнике — часть оружия спасённого героя
		if randf() < 0.05:
			main.spawn_part(position + Vector2(0, 50))
		main.combo_pop(position + Vector2(0, -90), "ТАЙНИК ОТКРЫТ", Pixel.hdr(color(), 1.4))
		Fx.ring(main, position, 10.0, 160.0, Pixel.hdr(color(), 2.0), 0.4, 5.0)
		_done()


# ---------- Рунная загадка ----------

# ---- Подсказки ----

static func _sat(seq: Array, c: Array) -> bool:
	var a: int = c[1]
	var b: int = c[2]
	var pa := seq.find(a)
	var pb := seq.find(b)
	match c[0]:
		"before":
			return pa >= 0 and pb >= 0 and pa < pb
		"adjacent":
			return pa >= 0 and pb >= 0 and absi(pa - pb) == 1
		"first":
			return pa == 0
		"last":
			return pa == 3
		"silent":
			return pa < 0
		"pos":
			return pa == b
		"notpos":
			return pa >= 0 and pa != b
	return false


static func _all_seqs() -> Array:
	var out: Array = []
	for a in 5:
		for b in 5:
			for c in 5:
				for d in 5:
					var s := [a, b, c, d]
					var u := {}
					for x in s:
						u[x] = true
					if u.size() == 4:
						out.append(s)
	return out


func _random_clue() -> Array:
	var r := randf()
	var used: Array = _seq
	var silent: int = [0, 1, 2, 3, 4].filter(func(x): return not (x in used))[0]
	if r < 0.32:
		var i := randi() % 3
		var j := randi_range(i + 1, 3)
		return ["before", used[i], used[j]]
	if r < 0.5:
		var i := randi() % 3
		return ["adjacent", used[i], used[i + 1]] if randf() < 0.5 else ["adjacent", used[i + 1], used[i]]
	if r < 0.6:
		return ["first", used[0], 0]
	if r < 0.7:
		return ["last", used[3], 0]
	if r < 0.8:
		return ["silent", silent, 0]
	if r < 0.9:
		var k := randi() % 4
		return ["pos", used[k], k]
	var k2 := randi() % 4
	var bad := (k2 + randi_range(1, 3)) % 4
	return ["notpos", used[k2], bad]


## Подсказки до единственного решения (без прямого «первым идёт X» как можно дольше).
func _make_clues() -> void:
	var cands := _all_seqs()
	_clues = []
	var guard := 0
	while cands.size() > 1 and guard < 200:
		guard += 1
		var c := _random_clue()
		var left := cands.filter(func(s): return _sat(s, c))
		if left.size() < cands.size():
			_clues.append(c)
			cands = left
	# Распределяем: 1 — камень, 2 — дух, остальное — скрижаль
	_clue_src = []
	_found = []
	for i in _clues.size():
		_clue_src.append("stone" if i == 0 else ("spirit" if i <= 2 else "tablet"))
		_found.append(false)


func _clue_text(c: Array) -> String:
	var A: String = RUNE_WORDS[c[1]][0]
	match c[0]:
		"before":
			return "%s просыпается раньше %s." % [A, RUNE_WORDS[c[2]][1]]
		"adjacent":
			return "%s и %s идут рука об руку." % [A, RUNE_WORDS[c[2]][0].to_lower()]
		"first":
			return "Первым говорит %s." % A.to_lower()
		"last":
			return "%s замыкает круг." % A
		"silent":
			return "%s в эту ночь молчит." % A
		"pos":
			return "%s звучит %s." % [A, ORD[c[2]]]
		"notpos":
			return "%s никогда не звучит %s." % [A, ORD[c[2]]]
	return ""


## Скрижаль — пиктограммы, а не слова.
func _clue_glyph(c: Array) -> String:
	var A: String = GLYPHS[c[1]]
	match c[0]:
		"before":
			return "%s  ⋯  %s" % [A, GLYPHS[c[2]]]
		"adjacent":
			return "%s═%s" % [A, GLYPHS[c[2]]]
		"first":
			return "▸%s" % A
		"last":
			return "%s◂" % A
		"silent":
			return "%s ✕" % A
		"pos":
			return "%s %s" % [A, ROMAN[c[2]]]
		"notpos":
			return "%s ≠%s" % [A, ROMAN[c[2]]]
	return ""


func _find_clues(src: String) -> void:
	var newly := false
	for i in _clues.size():
		if _clue_src[i] == src and not _found[i]:
			_found[i] = true
			newly = true
	if newly:
		Sound.play("gem", -4.0, 1.4)
		main.combo_pop(main.player.position + Vector2(0, -120), "Подсказка найдена (%d / %d)" % [_found.count(true), _found.size()], color())


## Найденные подсказки — для журнала в углу экрана.
func found_clues() -> Array:
	var out: Array = []
	for i in _clues.size():
		if _found[i]:
			out.append(_clue_glyph(_clues[i]) if _clue_src[i] == "tablet" else _clue_text(_clues[i]))
	return out


func _tick_puzzle(delta: float) -> void:
	_fail_flash = maxf(0.0, _fail_flash - delta)
	# Камень: постоять — он отзовётся одной подсказкой
	if _near(Vector2.ZERO, 70.0):
		_hold = minf(1.0, _hold + delta)
		if _hold >= 1.0 and not _found[0]:
			Sound.play("zap", -6.0, 1.6)
			main.combo_pop(position + Vector2(0, -150), _clue_text(_clues[0]), color())
			_find_clues("stone")
	else:
		_hold = maxf(0.0, _hold - delta * 2.0)
	# Дух-странник: подойти — шепчет загадки
	if _near(_spirit_pos, 140.0):
		if _spirit_say <= 0.0:
			var lines: Array = []
			for i in _clues.size():
				if _clue_src[i] == "spirit":
					lines.append(_clue_text(_clues[i]))
			_spirit_label.text = "«" + " ".join(lines) + "»"
			_spirit_label.visible = true
			Sound.play("zap", -12.0, 0.7)
			_find_clues("spirit")
		_spirit_say = 6.0
	else:
		_spirit_say = maxf(0.0, _spirit_say - delta)
		if _spirit_say <= 0.0 and _spirit_label:
			_spirit_label.visible = false
	# Скрижаль: пиктограммы видны, только если подойти
	if _near(_tablet_pos, 170.0):
		var g: Array = []
		for i in _clues.size():
			if _clue_src[i] == "tablet":
				g.append(_clue_glyph(_clues[i]))
		_tablet_label.text = "\n".join(g) if not g.is_empty() else "◇"
		_tablet_label.visible = true
		_find_clues("tablet")
	elif _tablet_label:
		_tablet_label.visible = false
	var on := -1
	for i in 5:
		if _near(_pillars[i], 70.0):
			on = i
	if on != _stand:
		_stand = on
		if on >= 0:
			_press(on)


func _press(i: int) -> void:
	var rune: int = _pillar_rune[i]
	if rune == _seq[_step]:
		_step += 1
		Sound.play("gem", -2.0, 0.8 + 0.15 * _step)
		Fx.ring(main, position + _pillars[i], 10.0, 90.0, Pixel.hdr(RUNE_COLORS[rune], 2.0), 0.35, 4.0)
		if _step >= 4:
			_solve()
	else:
		# Ошибка: руны гаснут, вспышка бьёт по героям, приходит стража
		_step = 0
		_fail_flash = 0.8
		Sound.play("hurt", -4.0, 0.6)
		main.shake(5.0)
		main.combo_pop(position + Vector2(0, -150), "НЕВЕРНО — РУНЫ ПОГАСЛИ", Color(1.0, 0.4, 0.4))
		for pl in main.players:
			if not pl._dead and pl.position.distance_to(position) < 420.0:
				pl.take_damage(pl.max_hp * 0.12)
		for k in 8:
			main.spawn_enemy(main.pick_enemy_kind(), position + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(320.0, 420.0))


func _solve() -> void:
	Sound.play("evolve", 0.0)
	main.screen_flash(0.25)
	main.run["puzzles"] = int(main.run["puzzles"]) + 1
	main.drop_material(position, "cores", 1)
	main.drop_material(position + Vector2(30, 0), "chips", 2)
	main.drop_chest(position + Vector2(0, 70))
	main.combo_pop(position + Vector2(0, -150), "ЗАГАДКА РЕШЕНА!", Pixel.hdr(Color(1.0, 0.85, 0.3), 1.5))
	for i in 5:
		Fx.ring(main, position + _pillars[i], 10.0, 140.0, Pixel.hdr(RUNE_COLORS[_pillar_rune[i]], 2.2), 0.5, 5.0)
	_done()


# ---------- Маяки ----------

func _tick_beacons(delta: float) -> void:
	var lit_n := 0
	for i in _beacons.size():
		if _lit[i]:
			lit_n += 1
			continue
		if _near(_beacons[i], 80.0):
			_bhold[i] = minf(2.0, float(_bhold[i]) + delta)
			if _bhold[i] >= 2.0:
				_lit[i] = true
				lit_n += 1
				_labels[i].text = "МАЯК %d\n✔" % (i + 1)
				_labels[i].modulate = Pixel.hdr(Color(1.0, 1.0, 0.7), 1.8)
				Sound.play("zap", -2.0, 1.3)
				Fx.ring(main, position + _beacons[i], 10.0, 180.0, Pixel.hdr(color(), 2.2), 0.5, 5.0)
				if _timer <= 0.0:
					_timer = 75.0
					main.combo_pop(position + _beacons[i] + Vector2(0, -100), "МАЯК ЗАЖЖЁН — ЗАЖГИТЕ ОСТАЛЬНЫЕ ЗА 75 С", color())
		else:
			_bhold[i] = maxf(0.0, float(_bhold[i]) - delta)
	if lit_n >= _beacons.size():
		Sound.play("evolve", 0.0)
		main.run["beacons"] = int(main.run["beacons"]) + 1
		main.drop_material(position, "chips", 3)
		main.drop_material(position + Vector2(30, 0), "scrap", 6)
		main.drop_chest(position + Vector2(0, 60))
		main.combo_pop(position + Vector2(0, -120), "ВСЕ МАЯКИ ГОРЯТ!", Pixel.hdr(color(), 1.6))
		_done()
		return
	if _timer > 0.0:
		_timer -= delta
		if _timer <= 0.0:
			for i in _lit.size():
				_lit[i] = false
				_bhold[i] = 0.0
				_labels[i].text = "МАЯК %d\n○" % (i + 1)
				_labels[i].modulate = Color(color().lerp(Color(0.82, 0.82, 0.88), 0.45), 0.7)
			main.combo_pop(position + Vector2(0, -120), "МАЯКИ ПОГАСЛИ", Color(0.7, 0.7, 0.8))


func _done() -> void:
	state = "done"
	life = 3.0
	for l in _labels + _seq_labels:
		if is_instance_valid(l):
			l.visible = false


## Строка задания сверху экрана, пока идёт загадка или маяки.
func quest_text() -> String:
	if state == "done":
		return ""
	if kind == "captive" and _hold > 0.0:
		return "Освобождение: %d%%  •  стойте у клетки" % int(_hold / FREE_T * 100.0)
	if kind == "puzzle" and _found.count(true) > 0:
		return "Рунная загадка: подсказки %d / %d — ищите духа и скрижаль в округе  •  руны %d / 4" % [_found.count(true), _found.size(), _step]
	if kind == "beacons" and _timer > 0.0:
		var n := 0
		for l in _lit:
			n += int(l)
		return "Маяки: %d / %d  •  осталось %d с" % [n, _beacons.size(), ceili(_timer)]
	return ""


func _glyph(at: Vector2, rune: int, r: float, col: Color, w := 3.0) -> void:
	match rune:
		0:   # треугольник — огонь
			draw_polyline(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r * 0.9, r * 0.7), at + Vector2(-r * 0.9, r * 0.7), at + Vector2(0, -r)]), col, w)
		1:   # ромб — лист
			draw_polyline(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0), at + Vector2(0, -r)]), col, w)
		2:   # круг — вода
			draw_arc(at, r * 0.85, 0.0, TAU, 20, col, w)
		3:   # крест — солнце
			draw_line(at + Vector2(-r, 0), at + Vector2(r, 0), col, w)
			draw_line(at + Vector2(0, -r), at + Vector2(0, r), col, w)


func _draw() -> void:
	var c := color()
	var a := 0.3 if state == "done" else 0.85
	match kind:
		"captive", "part":
			if state != "done":
				var rr := 90.0 if kind == "captive" else 50.0
				draw_arc(Vector2.ZERO, rr, 0.0, TAU, 40, Color(c, 0.28), 1.5)
				if _hold > 0.0:
					draw_arc(Vector2.ZERO, rr + 12.0, -PI / 2.0, -PI / 2.0 + TAU * _hold / FREE_T, 32, Pixel.hdr(Color.WHITE, 1.5), 5.0)
		"cache":
			if state != "done" and found:
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				draw_arc(Vector2.ZERO, 70.0, _t, _t + TAU * 0.8, 32, Color(c, a * (0.5 + 0.3 * sin(_t * 3.0))), 2.5)
				if _hold > 0.0:
					draw_arc(Vector2.ZERO, 80.0, -PI / 2.0, -PI / 2.0 + TAU * _hold / 1.2, 32, Pixel.hdr(Color.WHITE, 1.5), 5.0)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"puzzle":
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_arc(Vector2.ZERO, 70.0, 0.0, TAU, 40, Color(c, 0.28), 1.5)
			if _hold > 0.0 and not _found[0]:
				draw_arc(Vector2.ZERO, 80.0, -PI / 2.0, -PI / 2.0 + TAU * _hold, 32, Pixel.hdr(Color.WHITE, 1.5), 5.0)
			# Едва заметное мерцание у духа (его ещё надо заметить)
			draw_circle(_spirit_pos, 30.0 + 6.0 * sin(_t * 2.0), Color(0.5, 0.95, 1.0, 0.07))
			for i in 5:
				var p: Vector2 = _pillars[i]
				var rc: Color = RUNE_COLORS[_pillar_rune[i]]
				var used := _step > 0 and _seq.slice(0, _step).has(_pillar_rune[i])
				if used:
					draw_circle(p, 70.0, Color(rc, 0.12))
				draw_arc(p, 70.0, 0.0, TAU, 40, Color(rc, 0.8) if used else Color(rc, 0.3), 2.5 if used else 1.5)
				if _fail_flash > 0.0:
					draw_arc(p, 78.0, 0.0, TAU, 32, Color(1.0, 0.2, 0.2, _fail_flash), 5.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"beacons":
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			for i in _beacons.size():
				var p: Vector2 = _beacons[i]
				if _lit[i]:
					draw_circle(p, 80.0, Color(c, 0.12))
					draw_arc(p, 80.0, 0.0, TAU, 32, Pixel.hdr(c, 1.6), 4.0)
				else:
					draw_arc(p, 80.0, 0.0, TAU, 40, Color(c, 0.28), 1.5)
					if _bhold[i] > 0.0:
						draw_arc(p, 90.0, -PI / 2.0, -PI / 2.0 + TAU * _bhold[i] / 2.0, 32, Pixel.hdr(Color.WHITE, 1.5), 5.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------- Пленник-герой ----------
# Клетка с закованным героем. Встаньте рядом на 3 секунды (враги мешают) — герой спасён
# и ждёт в таверне. После этого в бою начинают попадаться части его оружия.

func _build_cage() -> void:
	var cage := Node3D.new()
	var bar := Props3D.mat(Color(0.32, 0.3, 0.36), "panel", 3.0, 0.5)
	var dark := Props3D.mat(Color(0.2, 0.19, 0.26), "panel", 2.0)
	Props3D._add(cage, Props3D._cyl(0.62, 0.66, 0.14, 12), dark, Vector3(0, 0.07, 0))
	Props3D._add(cage, Props3D._cyl(0.6, 0.6, 0.1, 12), dark, Vector3(0, 1.62, 0))
	for k in 10:
		var a := TAU * k / 10.0
		Props3D._add(cage, Props3D._cyl(0.025, 0.025, 1.5, 4), bar, Vector3(cos(a) * 0.56, 0.85, sin(a) * 0.56), Vector3.ZERO, false)
	Props3D._add(cage, Props3D._cyl(0.0, 0.62, 0.3, 12), dark, Vector3(0, 1.82, 0))
	main.place3d(cage, position)
	_models.append(cage)
	var fr := Pixel.frames(str(Data.CHARACTERS[hid]["sprite"]))
	_hero_spr = Sprite3D.new()
	_hero_spr.texture = fr["base"][0]
	_hero_spr.pixel_size = 0.03 * float(fr.get("k", 1.0))
	_hero_spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_hero_spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_hero_spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_hero_spr.modulate = Color(0.55, 0.52, 0.65)
	main.place3d(_hero_spr, position)
	_hero_spr.position.y += fr["size"].y * _hero_spr.pixel_size / 2.0 + 0.1
	_models.append(_hero_spr)
	_labels.append(_add_label("ПОМОГИТЕ!", Vector2.ZERO, 2.4, color(), 40))


func _tick_captive(delta: float) -> void:
	if is_instance_valid(_hero_spr):
		# Пленник мечется в клетке
		var fr := Pixel.frames(str(Data.CHARACTERS[hid]["sprite"]))
		var f := Pixel.hero_frame(fr, "hurt" if fmod(_t, 3.0) < 0.6 else "idle", _t) if fr["base"].size() >= Pixel.HERO_FRAMES else 0
		_hero_spr.texture = fr["base"][f]
		_hero_spr.flip_h = fmod(_t, 4.0) < 2.0
	var inside := _near(Vector2.ZERO, 100.0)
	_hold = minf(FREE_T, _hold + delta) if inside else maxf(0.0, _hold - delta)
	if _hold >= FREE_T:
		Meta.rescue(hid)
		var c: Dictionary = Data.CHARACTERS[hid]
		Sound.play("levelup", 0.0)
		main.combo_pop(position + Vector2(0, -150), "СПАСЁН: %s!" % str(c["name"]).to_upper(), Pixel.hdr(c["color"], 1.5))
		Fx.text_pop(main, position + Vector2(0, -110), "Ждёт вас в таверне", Pixel.hdr(Color(1.0, 0.85, 0.5), 1.3), 18)
		Fx.ring(main, position, 10.0, 220.0, Pixel.hdr(c["color"], 2.0), 0.5, 6.0)
		if is_instance_valid(_hero_spr):
			_hero_spr.modulate = Color(1, 1, 1)
		_done()


# ---------- Часть оружия ----------

func _build_part() -> void:
	var w: String = Data.CHARACTERS[hid]["weapon"]
	var sp := Sprite3D.new()
	sp.texture = Pixel.icon(w)
	sp.pixel_size = 0.022
	sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.shaded = false
	sp.modulate = Color(0.85, 0.82, 0.78)
	main.place3d(sp, position)
	sp.position.y += 0.55
	_models.append(sp)
	_hero_spr = sp



func _tick_part(_delta: float) -> void:
	if is_instance_valid(_hero_spr):
		_hero_spr.position.y = 0.55 + sin(_t * 3.0) * 0.08
	if _near(Vector2.ZERO, 60.0):
		var n := Meta.add_part(hid)
		var w: String = Data.CHARACTERS[hid]["weapon"]
		Sound.play("evolve", -2.0)
		var txt := "Найден обломок: «%s»" % Data.WEAPONS[w]["name"]
		if n >= Meta.PARTS_NEED:
			txt = "Оружие «%s» собрано!" % Data.WEAPONS[w]["name"]
		main.combo_pop(position + Vector2(0, -120), txt, Pixel.hdr(color(), 1.4))
		Fx.ring(main, position, 10.0, 160.0, Pixel.hdr(color(), 2.0), 0.4, 5.0)
		_done()
		life = 0.5
