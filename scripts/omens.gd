extends Node2D
## Знамения — особые события боя, которые случаются только при условиях:
## нужен определённый билд, герой, серия, место или состояние. Знамение даёт
## испытание на время; справились — щедрая награда, опыт ранга и мастерства.
##
##  • blades    — Знамение клинков: ближний бой (герой или 2+ клинковых оружия).
##                70 убийств за 30 с.
##  • choir     — Хор стихий: оружие трёх разных стихий. 12 реакций за 35 с.
##  • echo      — Эхо прошлого: герой с мастерством 1+. Появляется тень его прошлого —
##                сразите её за 50 с. Первая победа открывает страницу «Эхо».
##  • rune      — Отмеченная земля: после 2,5 мин. В соседнем квадрате вспыхивает
##                руна — простойте в ней 10 с (за 60 с), твари лезут на свет.
##  • champion  — Охота на чемпиона: 250+ убийств за вылазку. Чемпион орды — 60 с.
##  • shadow    — Испытание тени: здоровье выше 70%. 20 с без единой раны,
##                враги лезут вдвое чаще.
##  • brink     — Ритуал на грани: здоровье ниже 40%. 20 убийств, не поднимаясь выше 40%.
##  • feast     — Пир кристаллов: уровень героя 12+. 120 кристаллов за 25 с.

const Pixel := preload("res://scripts/pixel.gd")
const Fx := preload("res://scripts/fx.gd")
const Data := preload("res://scripts/data.gd")
const Meta := preload("res://scripts/meta.gd")
const Lore := preload("res://scripts/lore.gd")

const MELEE_HEROES := ["rin", "bram", "orm", "mora", "lyra", "kai"]
const MELEE_WEAPONS := ["katana", "blades", "quake", "scythe", "shuriken"]

const INFO := {
	"blades": {"name": "Знамение клинков", "color": Color(1.0, 0.35, 0.55), "time": 30.0, "goal": 70,
		"cond": "ближний бой", "text": "ЗНАМЕНИЕ КЛИНКОВ: клинки поют — 70 убийств за 30 секунд!"},
	"choir": {"name": "Хор стихий", "color": Color(0.6, 0.8, 1.0), "time": 35.0, "goal": 12,
		"cond": "три стихии в арсенале", "text": "ХОР СТИХИЙ: стихии зовут друг друга — 12 реакций за 35 секунд!"},
	"echo": {"name": "Эхо прошлого", "color": Color(0.85, 0.6, 1.0), "time": 50.0, "goal": 1,
		"cond": "мастерство героя 1+", "text": "ЭХО ПРОШЛОГО: тень из истории героя вышла из Врат!"},
	"rune": {"name": "Отмеченная земля", "color": Color(0.4, 1.0, 0.7), "time": 60.0, "goal": 10,
		"cond": "дольше 2,5 мин в бою", "text": "ОТМЕЧЕННАЯ ЗЕМЛЯ: в соседнем квадрате вспыхнула руна — займите её!"},
	"champion": {"name": "Охота на чемпиона", "color": Color(1.0, 0.75, 0.25), "time": 60.0, "goal": 1,
		"cond": "250+ убийств", "text": "ОХОТА НА ЧЕМПИОНА: чемпион орды учуял вас. Сразите его!"},
	"shadow": {"name": "Испытание тени", "color": Color(0.7, 0.7, 0.95), "time": 20.0, "goal": 20,
		"cond": "здоровье выше 70%", "text": "ИСПЫТАНИЕ ТЕНИ: 20 секунд без единой раны!"},
	"brink": {"name": "Ритуал на грани", "color": Color(1.0, 0.3, 0.3), "time": 30.0, "goal": 20,
		"cond": "здоровье ниже 40%", "text": "РИТУАЛ НА ГРАНИ: 20 убийств, пока здоровье ниже 40%!"},
	"feast": {"name": "Пир кристаллов", "color": Color(0.5, 1.0, 1.0), "time": 25.0, "goal": 120,
		"cond": "уровень героя 12+", "text": "ПИР КРИСТАЛЛОВ: соберите 120 кристаллов за 25 секунд!"},
}

var main: Node2D
var kind := ""
var time_left := 0.0
var done_kinds: Array = []
var _next := 75.0
var _base := 0
var _prog := 0.0
var _foe: Node2D
var _rune := Vector2.INF
var _last_hp := -1.0
var _t := 0.0
var _flash := 0.0
var _fail_text := ""


func _ready() -> void:
	z_index = 4
	_next = randf_range(70.0, 110.0) / (1.0 + 0.3 * Lore.perk("omen"))


func color() -> Color:
	return INFO[kind]["color"] if kind != "" else Color.WHITE


func title() -> String:
	return INFO[kind]["name"] if kind != "" else ""


func arrow_visible() -> bool:
	return (kind == "rune" and _rune.is_finite()) or (kind in ["echo", "champion"] and is_instance_valid(_foe))


func target_pos() -> Vector2:
	if kind in ["echo", "champion"] and is_instance_valid(_foe):
		return _foe.position
	return _rune


func quest_text() -> String:
	if kind == "":
		return ""
	var g: int = INFO[kind]["goal"]
	match kind:
		"echo", "champion":
			return "%s: сразите цель  •  %d с" % [title(), ceili(time_left)]
		"rune":
			return "%s: в круге %.1f / %d с  •  осталось %d с" % [title(), _prog, g, ceili(time_left)]
		"shadow":
			return "%s: без урона %d / %d с" % [title(), int(_prog), g]
	return "%s: %d / %d  •  %d с" % [title(), int(_prog), g, ceili(time_left)]


# ---------- Условия ----------

func _hero() -> String:
	return str(main.run.get("hero", ""))


func _statuses() -> Dictionary:
	var s := {}
	for w in main.player.weapons:
		var st: String = str(Data.WEAPONS.get(w, {}).get("status", ""))
		if st != "" and st != "bleed":
			s[st] = true
	return s


func eligible(k: String) -> bool:
	var p: Node2D = main.player
	match k:
		"blades":
			var n := 0
			for w in p.weapons:
				if w in MELEE_WEAPONS:
					n += 1
			return _hero() in MELEE_HEROES or n >= 2
		"choir":
			return _statuses().size() >= 3
		"echo":
			return Lore.mastery(_hero()) >= 1 and Lore.HERO_TALES.has(_hero())
		"rune":
			return main.time_alive > 150.0
		"champion":
			return main.kills >= 250
		"shadow":
			return p.hp >= p.max_hp * 0.7
		"brink":
			return p.hp < p.max_hp * 0.4 and p.hp > 0.0
		"feast":
			return int(p.level) >= 12
	return false


## Для экрана подготовки/библиотеки: какие знамения возможны и при каком условии.
static func conditions() -> Array:
	var out: Array = []
	for k in INFO:
		out.append([INFO[k]["name"], INFO[k]["cond"]])
	return out


# ---------- Ход ----------

func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta)
	queue_redraw()
	if main.game_over or main.net_mode == "client" or main.player == null:
		return
	if kind == "":
		_next -= delta
		if _next <= 0.0:
			_try_start()
		return
	time_left -= delta
	_tick(delta)
	if kind != "" and time_left <= 0.0:
		if kind == "shadow" and _prog >= float(INFO[kind]["goal"]) - 0.05:
			_win()
		else:
			_fail("Знамение угасло")


func _try_start() -> void:
	_next = randf_range(55.0, 95.0) / (1.0 + 0.3 * Lore.perk("omen"))
	if main.boss != null or (main.events != null and main.events.kind != ""):
		_next = 15.0
		return
	if done_kinds.size() >= 3 + Lore.perk("omen"):
		return
	if randf() > 0.6 + 0.15 * Lore.perk("omen"):
		return
	var cand: Array = []
	for k in INFO:
		if not (k in done_kinds) and eligible(k):
			cand.append(k)
	if cand.is_empty():
		_next = 20.0
		return
	_start(cand[randi() % cand.size()])


func _start(k: String) -> void:
	kind = k
	done_kinds.append(k)
	time_left = INFO[k]["time"]
	_prog = 0.0
	_last_hp = main.player.hp
	Sound.play("siren", -4.0, 1.25)
	main.glitch_flash()
	Fx.text_pop(main, main.player.position + Vector2(0, -150), INFO[k]["text"], Pixel.hdr(color(), 1.7), 24)
	Fx.ring(main, main.player.position, 10.0, 260.0, Pixel.hdr(color(), 2.0), 0.6, 6.0)
	var c: Vector2 = main.view_center()
	match k:
		"blades":
			_base = main.kills
		"choir":
			_base = main.reactions_count
		"feast":
			_base = int(main.run.get("gems", 0))
		"brink":
			_base = int(main.run.get("lowhp", 0))
		"echo", "champion":
			var ek: String = "knight" if k == "echo" else ["brute", "knight", "ghoul"][randi() % 3]
			main.spawn_enemy(ek, c + Vector2.RIGHT.rotated(randf() * TAU) * 520.0)
			_foe = main.enemies_node.get_child(main.enemies_node.get_child_count() - 1)
			_foe.max_hp *= 22.0 if k == "champion" else 16.0
			_foe.hp = _foe.max_hp
			_foe.is_elite = true
			_foe.size_mult *= 1.6
			var hc: Color = Data.CHARACTERS.get(_hero(), {}).get("color", color())
			_foe._base_tint = Color(hc.r * 1.4, hc.g * 1.4, hc.b * 1.4) if k == "echo" else Color(1.6, 1.3, 0.6)
			_foe.set_meta("omen", true)
			var nm: String = ("ЭХО: " + str(Data.CHARACTERS.get(_hero(), {}).get("name", "ГЕРОЙ")).to_upper()) if k == "echo" else "ЧЕМПИОН ОРДЫ"
			Fx.text_pop(main, _foe.position + Vector2(0, -90), nm, Pixel.hdr(color(), 1.6), 22)
			if k == "echo":
				var tale: Array = Lore.HERO_TALES[_hero()]
				main.combo_pop(main.player.position + Vector2(0, -190), str(tale[3]).trim_prefix("Эхо: "), Pixel.hdr(color(), 1.3))
		"rune":
			for tries in 10:
				_rune = c + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(650.0, 900.0)
				if main.ground_node == null or main.ground_node.is_free(_rune, 140.0):
					break
			Fx.portal(main, _rune, color(), 1.4)
		"shadow":
			main.events.spawn_k = 2.0


func _tick(delta: float) -> void:
	var p: Node2D = main.player
	var g: float = float(INFO[kind]["goal"])
	match kind:
		"blades":
			_prog = main.kills - _base
		"choir":
			_prog = main.reactions_count - _base
		"feast":
			_prog = int(main.run.get("gems", 0)) - _base
		"brink":
			_prog = int(main.run.get("lowhp", 0)) - _base
			if p.hp >= p.max_hp * 0.4:
				_fail("Здоровье поднялось выше 40% — ритуал прерван")
				return
		"echo", "champion":
			if not is_instance_valid(_foe) or _foe.dead:
				_prog = 1.0
		"rune":
			var inside := false
			for pl in main.players:
				if not pl._dead and pl.position.distance_to(_rune) < 130.0:
					inside = true
			if inside:
				_prog += delta
				# Руна манит тварей
				if randf() < delta * 1.6:
					main.spawn_enemy(main.pick_enemy_kind(), _rune + Vector2.RIGHT.rotated(randf() * TAU) * 520.0)
		"shadow":
			if p.hp < _last_hp - 0.01:
				_fail("Рана — испытание провалено")
				return
			_prog = minf(g, _prog + delta)
	if kind != "":
		_last_hp = p.hp
	if kind != "" and _prog >= g and kind != "shadow":
		_win()
	elif kind == "shadow" and _prog >= g:
		_win()


func _win() -> void:
	var at: Vector2 = main.player.position
	if kind in ["echo", "champion"] and is_instance_valid(_foe):
		at = _foe.position
	elif kind == "rune":
		at = _rune
	Sound.play("evolve", 0.0, 1.1)
	main.screen_flash(0.3)
	main.shake(6.0)
	main.run["omens"] = int(main.run.get("omens", 0)) + 1
	main.drop_chest(at + Vector2(0, 60))
	main.drop_material(at, "chips", randi_range(2, 3))
	main.drop_material(at + Vector2(30, 0), "scrap", randi_range(5, 8))
	if kind in ["echo", "champion"] or randf() < 0.35:
		main.drop_material(at + Vector2(-30, 0), "cores", 1)
	for i in 8:
		main.drop_gem_at(at + Vector2.RIGHT.rotated(TAU * i / 8.0) * 90.0, 8)
	main.combo_pop(at + Vector2(0, -120), "ЗНАМЕНИЕ ИСПОЛНЕНО: %s" % title().to_upper(), Pixel.hdr(color(), 1.7))
	Fx.ring(main, at, 10.0, 300.0, Pixel.hdr(color(), 2.4), 0.7, 8.0)
	if kind == "echo":
		var h := _hero()
		var e: Dictionary = Meta.stats.get("echo", {})
		if not bool(e.get(h, false)):
			e[h] = true
			Meta.stats["echo"] = e
			Fx.text_pop(main, at + Vector2(0, -170), "Открыта страница «Эхо» в истории героя", Pixel.hdr(Color(1.0, 0.9, 0.6), 1.4), 18)
		Meta.mastery[h] = Lore.mastery_xp(h) + 150
	_end()


func _fail(why: String) -> void:
	Sound.play("hurt", -8.0, 0.7)
	main.combo_pop(main.player.position + Vector2(0, -130), why, Color(0.75, 0.7, 0.85))
	if kind in ["echo", "champion"] and is_instance_valid(_foe) and not _foe.dead:
		Fx.portal(main, _foe.position, color(), 1.2)
		_foe.queue_free()
	_end()


func _end() -> void:
	if kind == "shadow" and main.events != null and main.events.kind != "bloodmoon":
		main.events.spawn_k = 1.0
	kind = ""
	_foe = null
	_rune = Vector2.INF


func _draw() -> void:
	if kind == "rune" and _rune.is_finite():
		var c := color()
		var p := _rune
		draw_circle(p, 130.0, Color(c, 0.08 + 0.04 * sin(_t * 3.0)))
		draw_arc(p, 130.0, 0.0, TAU, 48, Pixel.hdr(c, 1.4), 3.0)
		draw_arc(p, 100.0, -_t, -_t + TAU * 0.75, 40, Color(c, 0.6), 2.0)
		for i in 6:
			var a := _t * 0.6 + TAU * i / 6.0
			var q := p + Vector2.RIGHT.rotated(a) * 115.0
			draw_polyline(PackedVector2Array([q + Vector2(0, -9), q + Vector2(7, 6), q + Vector2(-7, 6), q + Vector2(0, -9)]), Pixel.hdr(c, 1.6), 2.0)
		var g: float = float(INFO["rune"]["goal"])
		if _prog > 0.0:
			draw_arc(p, 145.0, -PI / 2.0, -PI / 2.0 + TAU * _prog / g, 40, Pixel.hdr(Color.WHITE, 1.6), 6.0)
	elif kind in ["echo", "champion"] and is_instance_valid(_foe):
		var c := color()
		draw_arc(_foe.position, 70.0 + 6.0 * sin(_t * 5.0), 0.0, TAU, 32, Pixel.hdr(c, 1.5), 3.0)
