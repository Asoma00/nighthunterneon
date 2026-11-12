extends Node2D
## Случайные события боя. В каждой вылазке их может не быть вовсе, а может быть до трёх.
##  • meteors  — Метеоритный дождь: камни падают с неба (видно, куда), бьют всех; в воронках лом.
##  • goblin   — Золотой гоблин: удирает от героя. Догоните — щедрая добыча.
##  • bloodmoon— Кровавая луна: врагов вдвое больше, опыта вдвое больше.
##  • storm    — Неоновый шторм: молнии бьют по врагам, изредка — рядом с героем.
##  • ambush   — Засада: кольцо врагов вокруг. Перебейте всех — получите микросхемы.
##  • supply   — Сброс припасов: контейнер падает неподалёку. Успейте забрать.

const Pixel := preload("res://scripts/pixel.gd")
const Fx := preload("res://scripts/fx.gd")

const INFO := {
	"meteors": {"name": "Метеоритный дождь", "color": Color(1.0, 0.55, 0.25), "time": 25.0,
		"text": "МЕТЕОРИТНЫЙ ДОЖДЬ! Уходите из красных кругов"},
	"goblin": {"name": "Золотой гоблин", "color": Color(1.0, 0.85, 0.3), "time": 30.0,
		"text": "ЗОЛОТОЙ ГОБЛИН! Догоните, пока не сбежал"},
	"bloodmoon": {"name": "Кровавая луна", "color": Color(1.0, 0.2, 0.25), "time": 40.0,
		"text": "КРОВАВАЯ ЛУНА: врагов вдвое больше — и опыта тоже"},
	"storm": {"name": "Неоновый шторм", "color": Color(0.5, 0.8, 1.0), "time": 30.0,
		"text": "НЕОНОВЫЙ ШТОРМ: молнии бьют по врагам — и иногда рядом с вами"},
	"ambush": {"name": "Засада", "color": Color(0.85, 0.4, 1.0), "time": 35.0,
		"text": "ЗАСАДА! Перебейте окруживших врагов"},
	"supply": {"name": "Сброс припасов", "color": Color(0.4, 1.0, 0.7), "time": 45.0,
		"text": "СБРОС ПРИПАСОВ: контейнер упал неподалёку — успейте забрать"},
}

var main: Node2D
var schedule: Array = []      # [время, вид]
var kind := ""                # текущее событие
var time_left := 0.0
var spawn_k := 1.0            # множитель частоты появления врагов (кровавая луна)
var xp_k := 1.0               # множитель опыта
var _tick := 0.0
var _meteors: Array = []      # [позиция, осталось до удара]
var _bolts: Array = []        # [позиция, осталось до удара]
var _goblin: Node2D
var _ambush: Array = []
var _supply_pos := Vector2.INF
var _supply_hold := 0.0
var _t := 0.0


func _ready() -> void:
	z_index = 5
	# Сколько событий в этой вылазке: может не быть ни одного
	var roll := randf()
	var n := 0 if roll < 0.2 else (1 if roll < 0.6 else (2 if roll < 0.9 else 3))
	var total: float = float(main.level["time"])
	var kinds: Array = INFO.keys()
	kinds.shuffle()
	for i in n:
		var at := randf_range(50.0, maxf(60.0, total - 40.0))
		schedule.append([at, kinds[i]])
	schedule.sort_custom(func(a, b): return a[0] < b[0])


func color() -> Color:
	return INFO[kind]["color"] if kind != "" else Color.WHITE


func title() -> String:
	return INFO[kind]["name"] if kind != "" else ""


func quest_text() -> String:
	if kind == "":
		return ""
	match kind:
		"ambush":
			var alive := _ambush.filter(func(e): return is_instance_valid(e) and not e.dead).size()
			return "Засада: осталось врагов %d  •  %d с" % [alive, ceili(time_left)]
		"goblin":
			return "Золотой гоблин сбежит через %d с" % ceili(time_left)
		"supply":
			return "Сброс припасов: заберите контейнер  •  %d с" % ceili(time_left)
	return "%s  •  %d с" % [title(), ceili(time_left)]


func arrow_visible() -> bool:
	return kind == "supply" or (kind == "goblin" and is_instance_valid(_goblin))


## Где стрелка у края экрана (гоблин или контейнер)
func target_pos() -> Vector2:
	if kind == "goblin" and is_instance_valid(_goblin):
		return _goblin.position
	return _supply_pos


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if main.game_over or main.net_mode == "client":
		return
	if kind == "":
		if not schedule.is_empty() and main.time_alive >= schedule[0][0] and main.boss == null:
			_start(schedule.pop_front()[1])
		return
	time_left -= delta
	match kind:
		"meteors":
			_tick_meteors(delta)
		"storm":
			_tick_storm(delta)
		"goblin":
			if not is_instance_valid(_goblin) or _goblin.dead:
				_end(true)
				return
		"ambush":
			if _ambush.filter(func(e): return is_instance_valid(e) and not e.dead).is_empty():
				main.drop_material(main.player.position + Vector2(40, 0), "chips", 2)
				main.drop_material(main.player.position + Vector2(-40, 0), "scrap", 5)
				main.combo_pop(main.player.position + Vector2(0, -110), "ЗАСАДА ОТБИТА!", Pixel.hdr(color(), 1.5))
				_end(true)
				return
		"supply":
			_tick_supply(delta)
			if kind == "":
				return
	if time_left <= 0.0:
		if kind == "goblin" and is_instance_valid(_goblin):
			Fx.portal(main, _goblin.position, color(), 1.2)
			main.combo_pop(_goblin.position + Vector2(0, -80), "ГОБЛИН СБЕЖАЛ", Color(0.7, 0.7, 0.8))
			_goblin.queue_free()
		_end(kind in ["meteors", "storm", "bloodmoon"])


func _start(k: String) -> void:
	kind = k
	time_left = INFO[k]["time"]
	Sound.play("siren", -2.0, 0.9)
	main.shake(6.0)
	main.glitch_flash()
	Fx.text_pop(main, main.player.position + Vector2(0, -140), INFO[k]["text"], Pixel.hdr(color(), 1.6), 24)
	var c: Vector2 = main.view_center()
	match k:
		"bloodmoon":
			spawn_k = 2.0
			xp_k = 2.0
		"goblin":
			main.spawn_enemy("goblin", c + Vector2.RIGHT.rotated(randf() * TAU) * 380.0)
			_goblin = main.enemies_node.get_child(main.enemies_node.get_child_count() - 1)
			_goblin.ai = "flee"
			_goblin.max_hp *= 14.0
			_goblin.hp = _goblin.max_hp
			_goblin.speed *= 1.25
			_goblin.size_mult = 1.4
			_goblin._base_tint = Color(1.6, 1.3, 0.4)
			_goblin.set_meta("golden", true)
		"ambush":
			for i in 24:
				main.spawn_enemy(main.pick_enemy_kind(), c + Vector2.RIGHT.rotated(TAU * i / 24.0) * 430.0)
				_ambush.append(main.enemies_node.get_child(main.enemies_node.get_child_count() - 1))
		"supply":
			for tries in 8:
				_supply_pos = c + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(550.0, 800.0)
				if main.ground_node == null or main.ground_node.is_free(_supply_pos, 80.0):
					break
			Fx.portal(main, _supply_pos, color(), 1.5)


func _end(survived: bool) -> void:
	if survived and not main.player._dead:
		main.run["events"] = int(main.run["events"]) + 1
	kind = ""
	spawn_k = 1.0
	xp_k = 1.0
	_meteors.clear()
	_bolts.clear()
	_ambush.clear()
	_supply_pos = Vector2.INF


func _tick_meteors(delta: float) -> void:
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.45
		var c: Vector2 = main.view_center()
		var p := c + Vector2(randf_range(-700, 700), randf_range(-450, 450))
		if randf() < 0.25:
			p = main.player.position + Vector2(randf_range(-120, 120), randf_range(-90, 90))
		_meteors.append([p, 1.4])
	for m in _meteors:
		m[1] -= delta
		if m[1] <= 0.0:
			var p: Vector2 = m[0]
			main.attacker = main.player
			main.damage_area(p, 110.0, 40.0 + main.time_alive * 0.1, null, "burn")
			for pl in main.players:
				if not pl._dead and pl.position.distance_to(p) < 95.0:
					pl.take_damage(14.0)
			Fx.ring(main, p, 10.0, 130.0, Pixel.hdr(color(), 2.0), 0.4, 6.0)
			Fx.burst(main, p, [Pixel.hdr(color(), 2.4), Color(0.4, 0.3, 0.3, 0.0)], 14, 260.0, 0.6, 4.0)
			main.shake(3.0)
			Sound.play("boom", -8.0, 1.2, 0.2, 0.08)
			if randf() < 0.3:
				main.drop_material(p, "scrap", 1)
	_meteors = _meteors.filter(func(m): return m[1] > 0.0)


func _tick_storm(delta: float) -> void:
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.35
		var targets: Array = main.nearest_enemies_to(main.view_center(), 12, 900.0, null)
		if not targets.is_empty() and randf() < 0.85:
			var e: Node2D = targets[randi() % targets.size()]
			_bolts.append([e.position, 0.35])
		else:
			_bolts.append([main.player.position + Vector2(randf_range(-160, 160), randf_range(-120, 120)), 1.0])
	for b in _bolts:
		b[1] -= delta
		if b[1] <= 0.0:
			var p: Vector2 = b[0]
			main.attacker = main.player
			main.damage_area(p, 80.0, 30.0 + main.time_alive * 0.08, null, "shock")
			for pl in main.players:
				if not pl._dead and pl.position.distance_to(p) < 60.0:
					pl.take_damage(10.0)
			Fx.light_flash(main, p, color(), 2.5, 4.0, 0.25)
			Fx.ring(main, p, 6.0, 90.0, Pixel.hdr(color(), 2.4), 0.25, 4.0)
			Sound.play("thunder", -10.0, 1.3, 0.2, 0.1)
	_bolts = _bolts.filter(func(b): return b[1] > 0.0)


func _tick_supply(delta: float) -> void:
	var near := false
	for pl in main.players:
		if not pl._dead and pl.position.distance_to(_supply_pos) < 75.0:
			near = true
	_supply_hold = minf(1.5, _supply_hold + delta) if near else maxf(0.0, _supply_hold - delta)
	if _supply_hold >= 1.5:
		Sound.play("chest", 0.0)
		main.drop_chest(_supply_pos + Vector2(0, 50))
		main.drop_material(_supply_pos, "scrap", randi_range(5, 8))
		main.drop_material(_supply_pos + Vector2(30, 0), "chips", randi_range(1, 3))
		if randf() < 0.25:
			main.drop_material(_supply_pos + Vector2(-30, 0), "cores", 1)
		main.combo_pop(_supply_pos + Vector2(0, -100), "ПРИПАСЫ ВАШИ!", Pixel.hdr(color(), 1.5))
		_end(true)


func _draw() -> void:
	if kind == "":
		return
	var c := color()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for m in _meteors:
		var p: Vector2 = m[0]
		var k: float = 1.0 - m[1] / 1.4
		draw_circle(p, 110.0, Color(1.0, 0.2, 0.15, 0.08 + 0.12 * k))
		draw_arc(p, 110.0, 0.0, TAU, 32, Color(1.0, 0.3, 0.2, 0.5 + 0.4 * k), 3.0)
		draw_arc(p, 110.0 * k, 0.0, TAU, 32, Color(1.0, 0.6, 0.3, 0.7), 2.0)
	for b in _bolts:
		var p: Vector2 = b[0]
		draw_arc(p, 70.0, 0.0, TAU, 24, Color(c, 0.7), 2.5)
	if _supply_pos.is_finite():
		var p := _supply_pos
		draw_circle(p, 75.0, Color(c, 0.1))
		draw_arc(p, 75.0, _t, _t + TAU * 0.8, 32, Color(c, 0.9), 3.0)
		if _supply_hold > 0.0:
			draw_arc(p, 85.0, -PI / 2.0, -PI / 2.0 + TAU * _supply_hold / 1.5, 32, Pixel.hdr(Color.WHITE, 1.5), 5.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _supply_pos.is_finite():
		# Контейнер: простая коробка с огоньком
		var p := _supply_pos
		draw_rect(Rect2(p + Vector2(-26, -40), Vector2(52, 40)), Color(0.15, 0.3, 0.25))
		draw_rect(Rect2(p + Vector2(-26, -40), Vector2(52, 40)), Pixel.hdr(c, 1.3), false, 3.0)
		draw_circle(p + Vector2(0, -50), 5.0 + 2.0 * sin(_t * 6.0), Pixel.hdr(c, 2.0))
