extends Node2D
## Точка интереса в бою — алтарь. Появляется в случайном месте недалеко от героя.
## Герой встаёт в круг и держится 1.5 с — алтарь срабатывает:
##  • power  — Алтарь силы: временный бафф на 30 с;
##  • trial  — Алтарь испытания: задание (убить N врагов за время / продержаться в круге),
##             за успех — сундук и россыпь кристаллов;
##  • spring — Источник жизни: лечит и даёт щит-неуязвимость на 3 с.
## (Алтарь мобов — отдельный разрушаемый «враг», см. ai "altar" в enemy.gd.)

const Pixel := preload("res://scripts/pixel.gd")
const Fx := preload("res://scripts/fx.gd")
const Props3D := preload("res://scripts/props3d.gd")

const INFO := {
	"power": {"name": "Алтарь силы", "color": Color(1.0, 0.45, 0.2)},
	"trial": {"name": "Алтарь испытания", "color": Color(0.75, 0.45, 1.0)},
	"spring": {"name": "Источник жизни", "color": Color(0.35, 1.0, 0.6)},
}
const BUFFS := [
	["rage", "ЯРОСТЬ: +50% урона"],
	["haste", "СТРЕМИТЕЛЬНОСТЬ: +30% скорости, -25% перезарядки"],
	["crit", "ОКО ОХОТНИКА: +25% шанс крита"],
	["magnet", "ПРИТЯЖЕНИЕ: огромный радиус сбора, +40 здоровья"],
]

var main: Node2D
var kind := "power"
var radius := 95.0
var state := "idle"       # idle → active (испытание) → done
var task := ""            # kills / hold
var goal := 0
var progress := 0.0
var time_left := 0.0
var life := 120.0         # исчезает, если к нему долго не подходят
var _hold := 0.0
var _t := 0.0
var _kills0 := 0
var _surge_t := 0.0
var _model: Node3D


func color() -> Color:
	return INFO[kind]["color"]


func title() -> String:
	return INFO[kind]["name"]


func _ready() -> void:
	z_index = -10
	_model = Props3D.build("obelisk%d" % (randi() % 3), RandomNumberGenerator.new())
	_model.scale *= 1.4
	main.place3d(_model, position + Vector2(0, -radius - 25.0))   # обелиск за кругом — не загораживает героя



func _exit_tree() -> void:
	if is_instance_valid(_model):
		_model.queue_free()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if main.game_over:
		return
	match state:
		"idle":
			life -= delta
			var inside := _anyone_inside(radius)
			_hold = minf(1.5, _hold + delta) if inside else maxf(0.0, _hold - delta * 2.0)
			if _hold >= 1.5:
				_activate()
			elif life <= 0.0 or _far_from_all(2600.0):
				_vanish()
		"active":
			_tick_trial(delta)
		"done":
			life -= delta
			if life <= 0.0:
				_vanish()


func _anyone_inside(r: float) -> bool:
	for p in main.players:
		if not p._dead and p.position.distance_to(position) < r:
			return true
	return false


func _far_from_all(d: float) -> bool:
	for p in main.players:
		if p.position.distance_to(position) < d:
			return false
	return true


func _activate() -> void:
	Sound.play("evolve", -4.0)
	main.shake(6.0)
	Fx.ring(main, position, 10.0, 260.0, Pixel.hdr(color(), 2.0), 0.5, 6.0)
	main.run["altars"] = int(main.run.get("altars", 0)) + 1
	match kind:
		"power":
			var b: Array = BUFFS[randi() % BUFFS.size()]
			for p in main.players:
				if not p._dead:
					main.apply_buff(p, b[0], 30.0)
			main.combo_pop(position + Vector2(0, -90), b[1] + "  (30 с)", color())
			_finish(false)
		"spring":
			for p in main.players:
				if not p._dead:
					p.heal(p.max_hp * 0.6)
					p.give_invuln(3.0)
			main.combo_pop(position + Vector2(0, -90), "ИСЦЕЛЕНИЕ  •  неуязвимость 3 с", color())
			_finish(false)
		"trial":
			state = "active"
			if randf() < 0.5:
				task = "kills"
				goal = 35 + 10 * mini(int(main.time_alive / 60.0), 6)
				time_left = 30.0
				_kills0 = main.kills
			else:
				task = "hold"
				goal = 15
				progress = 0.0
				time_left = 40.0
			Sound.play("siren", -8.0, 1.4)


func _tick_trial(delta: float) -> void:
	time_left -= delta
	if task == "kills":
		progress = main.kills - _kills0
		if progress >= goal:
			_win()
			return
	else:
		# Держаться в круге: враги стягиваются к алтарю
		if _anyone_inside(260.0):
			progress += delta
		_surge_t -= delta
		if _surge_t <= 0.0:
			_surge_t = 1.4
			for i in 3:
				main.spawn_enemy(main.pick_enemy_kind(), position + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(380.0, 480.0))
		if progress >= goal:
			_win()
			return
	if time_left <= 0.0:
		main.combo_pop(position + Vector2(0, -90), "ИСПЫТАНИЕ ПРОВАЛЕНО", Color(0.7, 0.7, 0.8))
		Sound.play("hurt", -6.0, 0.7)
		_finish(false)


func quest_text() -> String:
	if state != "active":
		return ""
	if task == "kills":
		return "Испытание: убейте врагов  %d / %d  •  %d с" % [int(progress), goal, ceili(time_left)]
	return "Испытание: держитесь у алтаря  %d / %d с  •  осталось %d с" % [int(progress), goal, ceili(time_left)]


func _win() -> void:
	main.run["trials"] = int(main.run.get("trials", 0)) + 1
	main.combo_pop(position + Vector2(0, -90), "ИСПЫТАНИЕ ПРОЙДЕНО!", Pixel.hdr(Color(1.0, 0.85, 0.3), 1.4))
	Sound.play("chest", 0.0)
	main.drop_chest(position + Vector2(0, 60))
	for i in 12:
		main.drop_gem_at(position + Vector2.RIGHT.rotated(TAU * i / 12.0) * 90.0, 5)
	_finish(true)


func _finish(_won: bool) -> void:
	state = "done"
	life = 4.0


func _vanish() -> void:
	queue_free()


func _draw() -> void:
	var c := color()
	var a := 0.35 if state == "done" else 0.8
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Лёгкая обводка без свечения — алтарь не бросается в глаза
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(c, 0.12 if state == "done" else 0.3), 1.5)
	if state == "idle" and _hold > 0.0:
		draw_arc(Vector2.ZERO, radius + 10.0, -PI / 2.0, -PI / 2.0 + TAU * _hold / 1.5, 48, Pixel.hdr(Color.WHITE, 1.5), 6.0)
	if state == "active" and task == "hold":
		draw_arc(Vector2.ZERO, 260.0, 0.0, TAU, 64, Color(c, 0.5 + 0.3 * sin(_t * 6.0)), 3.0)
		draw_arc(Vector2.ZERO, 270.0, -PI / 2.0, -PI / 2.0 + TAU * progress / goal, 64, Pixel.hdr(Color(1.0, 0.85, 0.3), 1.4), 6.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
