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
}
const RUNE_COLORS := [Color(1.0, 0.35, 0.35), Color(0.35, 1.0, 0.45), Color(0.4, 0.6, 1.0), Color(1.0, 0.85, 0.3)]
const RUNE_NAMES := ["огонь", "лист", "вода", "солнце"]

var main: Node2D
var kind := "cache"
var state := "idle"      # idle → active → done
var life := 150.0
var found := false       # тайник замечен (подошли близко) — показываем стрелку
var _t := 0.0
var _hold := 0.0
var _models: Array = []

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
	return INFO[kind]["name"]


## Стрелка у края экрана: тайник — только если его ищут по заданию или он уже замечен.
func arrow_visible() -> bool:
	if state == "done":
		return false
	if kind == "cache":
		return found or main.quest_wants("caches")
	return true


func _ready() -> void:
	z_index = -10
	match kind:
		"cache":
			_add_model("crate0", Vector2.ZERO, 1.1)
		"puzzle":
			_add_model("obelisk1", Vector2(0, -40), 1.0)
			var order := [0, 1, 2, 3]
			order.shuffle()
			_pillar_rune = order
			for i in 4:
				var p := Vector2.RIGHT.rotated(TAU * i / 4.0 + PI / 4.0) * Vector2(260, 200)
				_pillars.append(p)
				_add_model("pillar%d" % (i % 2), p + Vector2(0, -30), 0.9)
			_seq = [0, 1, 2, 3]
			_seq.shuffle()
		"beacons":
			for i in 3:
				var p := Vector2.RIGHT.rotated(TAU * i / 3.0 + randf() * 0.6) * randf_range(420.0, 620.0)
				_beacons.append(p)
				_lit.append(false)
				_bhold.append(0.0)
				_add_model("lamp0" if i % 2 == 0 else "obelisk0", p + Vector2(0, -40), 1.2)
	Fx.portal(main, position, color(), 1.2)


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
		Fx.portal(main, position, color(), 1.0)
		queue_free()
		return
	match kind:
		"cache":
			_tick_cache(delta)
		"puzzle":
			_tick_puzzle(delta)
		"beacons":
			_tick_beacons(delta)


# ---------- Тайник ----------

func _tick_cache(delta: float) -> void:
	if not found and _near(Vector2.ZERO, 650.0):
		found = true
		main.combo_pop(position + Vector2(0, -80), "ВЫ ЗАМЕТИЛИ ТАЙНИК", color())
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
		main.combo_pop(position + Vector2(0, -90), "ТАЙНИК ОТКРЫТ", Pixel.hdr(color(), 1.4))
		Fx.ring(main, position, 10.0, 160.0, Pixel.hdr(color(), 2.0), 0.4, 5.0)
		_done()


# ---------- Рунная загадка ----------

func _tick_puzzle(delta: float) -> void:
	_fail_flash = maxf(0.0, _fail_flash - delta)
	_show_t = maxf(0.0, _show_t - delta)
	# Камень в центре: постоять — он покажет порядок
	if _near(Vector2.ZERO, 70.0):
		_hold = minf(1.0, _hold + delta)
		if _hold >= 1.0 and _show_t <= 0.0:
			_show_t = 7.0
			_step = 0
			Sound.play("zap", -6.0, 1.6)
			main.combo_pop(position + Vector2(0, -150), "ЗАПОМНИТЕ ПОРЯДОК ЦВЕТОВ", color())
	else:
		_hold = maxf(0.0, _hold - delta * 2.0)
	var on := -1
	for i in 4:
		if _near(_pillars[i], 55.0):
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
		# Ошибка: руны гаснут, приходит стража
		_step = 0
		_fail_flash = 0.8
		Sound.play("hurt", -4.0, 0.6)
		main.shake(5.0)
		main.combo_pop(position + Vector2(0, -150), "НЕВЕРНО — РУНЫ ПОГАСЛИ", Color(1.0, 0.4, 0.4))
		for k in 6:
			main.spawn_enemy(main.pick_enemy_kind(), position + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(320.0, 420.0))


func _solve() -> void:
	Sound.play("evolve", 0.0)
	main.screen_flash(0.25)
	main.run["puzzles"] = int(main.run["puzzles"]) + 1
	main.drop_material(position, "cores", 1)
	main.drop_material(position + Vector2(30, 0), "chips", 2)
	main.drop_chest(position + Vector2(0, 70))
	main.combo_pop(position + Vector2(0, -150), "ЗАГАДКА РЕШЕНА!", Pixel.hdr(Color(1.0, 0.85, 0.3), 1.5))
	for i in 4:
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
			main.combo_pop(position + Vector2(0, -120), "МАЯКИ ПОГАСЛИ", Color(0.7, 0.7, 0.8))


func _done() -> void:
	state = "done"
	life = 3.0


## Строка задания сверху экрана, пока идёт загадка или маяки.
func quest_text() -> String:
	if state == "done":
		return ""
	if kind == "puzzle" and (_show_t > 0.0 or _step > 0):
		return "Рунная загадка: пройдите по столбам в порядке цветов  •  %d / 4" % _step
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
		"cache":
			if state != "done":
				draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.6))
				draw_arc(Vector2.ZERO, 70.0, _t, _t + TAU * 0.8, 32, Color(c, a * (0.5 + 0.3 * sin(_t * 3.0))), 2.5)
				if _hold > 0.0:
					draw_arc(Vector2.ZERO, 80.0, -PI / 2.0, -PI / 2.0 + TAU * _hold / 1.2, 32, Pixel.hdr(Color.WHITE, 1.5), 5.0)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"puzzle":
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.6))
			draw_arc(Vector2.ZERO, 70.0, 0.0, TAU, 32, Color(c, a), 3.0)
			if _hold > 0.0 and _show_t <= 0.0:
				draw_arc(Vector2.ZERO, 80.0, -PI / 2.0, -PI / 2.0 + TAU * _hold, 32, Pixel.hdr(Color.WHITE, 1.5), 5.0)
			for i in 4:
				var p: Vector2 = Vector2(_pillars[i].x, _pillars[i].y / 0.6)
				var rc: Color = RUNE_COLORS[_pillar_rune[i]]
				var used := _step > 0 and _seq.slice(0, _step).has(_pillar_rune[i])
				draw_arc(p, 55.0, 0.0, TAU, 28, Color(rc, 0.9 if used else 0.45), 4.0 if used else 2.5)
				if _fail_flash > 0.0:
					draw_arc(p, 62.0, 0.0, TAU, 28, Color(1.0, 0.2, 0.2, _fail_flash), 4.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			for i in 4:
				var rc: Color = RUNE_COLORS[_pillar_rune[i]]
				_glyph(_pillars[i] + Vector2(0, -95), _pillar_rune[i], 13.0, Pixel.hdr(rc, 1.5))
			# Над камнем — порядок (пока его показывают)
			if _show_t > 0.0:
				for i in 4:
					var rc: Color = RUNE_COLORS[_seq[i]]
					var x := (i - 1.5) * 44.0
					_glyph(Vector2(x, -190), _seq[i], 15.0, Pixel.hdr(rc, 1.6 if i >= _step else 0.6), 4.0)
		"beacons":
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.6))
			for i in _beacons.size():
				var p: Vector2 = Vector2(_beacons[i].x, _beacons[i].y / 0.6)
				if _lit[i]:
					draw_circle(p, 80.0, Color(c, 0.12))
					draw_arc(p, 80.0, 0.0, TAU, 32, Pixel.hdr(c, 1.6), 4.0)
				else:
					draw_arc(p, 80.0, _t, _t + TAU * 0.75, 32, Color(c, 0.5), 2.5)
					if _bhold[i] > 0.0:
						draw_arc(p, 90.0, -PI / 2.0, -PI / 2.0 + TAU * _bhold[i] / 2.0, 32, Pixel.hdr(Color.WHITE, 1.5), 5.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
