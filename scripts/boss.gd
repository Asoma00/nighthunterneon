extends "res://scripts/enemy.gd"
## Боссы с тремя фазами. Фаза меняется на 66% и 33% здоровья: короткая
## неуязвимость, ударная волна, босс ускоряется и получает новые приёмы.
##  • Нейро-Лич — кольца, спирали, метеоры, лучи, телепорт, призыв нежити.
##  • Железный Колосс — таран, ударные волны, мины, каменный дождь, щит, серия таранов.
##  • Королева Роя — самонаводящиеся сферы, рой, телепорт, притяжение, кладки яиц.
##  • Архимаг Омега — приёмы всех боссов, в третьей фазе — по два сразу.

var boss_name := ""
var is_super := false     # супер-босс: крупнее, сильнее, атакует чаще
var phase := 1
var _attack_t := 2.0
var _summon_t := 6.0
var _special_t := 5.0
var _charge_t := 0.0
var _charge_dir := Vector2.ZERO
var _charges_left := 0
var _telegraph := 0.0
var _spiral := 0.0
var _stream_t := 0.0      # непрерывная спираль снарядов
var _phase_t := 0.0       # неуязвимость при смене фазы
var _shield_t := 0.0      # щит: урон по боссу ×0.3
var _pull_t := 0.0        # притяжение героев к боссу
var _beam_t := 0.0        # луч: <0 — предупреждение, >0 — бьёт
var _beam_warn := 0.0
var _beam_dir := Vector2.ZERO
var _beam_rot := 0.0
var _marks: Array = []    # метки на земле: {pos, t, r, kind}
var _ability_i := 0
var _tele_node: Node2D
var spc_anim := 0.0   # кадры особого приёма

const PHASE_NAMES := {
	"lich": ["", "Пробуждение", "Буря душ", "Последний ритуал"],
	"colossus": ["", "Разгон", "Раскалённый корпус", "Сердце вразнос"],
	"queen": ["", "Охота", "Рой поднимается", "Матка гнева"],
	"omega": ["", "Испытание", "Сплав стихий", "Конец главы"],
}

## Приёмы по фазам (каждая фаза добавляет новые к старым).
const ABILITIES := {
	"lich": [[], ["ring", "summon_imp"], ["meteors", "skulls", "teleport"], ["stream", "beam", "summon_wraith"]],
	"colossus": [[], ["charge"], ["waves", "mines", "stomp"], ["multi_charge", "shield", "rockfall"]],
	"queen": [[], ["fan", "summon_bat", "teleport"], ["swirl", "summon_spider", "pull"], ["eggs", "homing_burst", "beam"]],
	"omega": [[], ["ring", "fan", "charge"], ["beam", "meteors", "summon_guard"], ["stream", "shield", "pull", "rockfall"]],
}


func _ready() -> void:
	is_boss = true
	super._ready()
	_tele_node = preload("res://scripts/drawer.gd").new()
	_tele_node.draw_fn = _draw_telegraph
	_tele_node.material = Pixel.mat_add()
	_tele_node.z_index = -3
	add_child(_tele_node)


func can_be_hit() -> bool:
	return _phase_t <= 0.0 and super.can_be_hit()


func _take(amount: float, col := Color(1.0, 0.95, 0.6), size := 14) -> void:
	if _phase_t > 0.0 or dead:
		return   # смена фазы: босс неуязвим
	if _shield_t > 0.0:
		amount *= 0.3
		col = Color(0.6, 0.8, 1.0)
	# Плотный босс: срезает часть урона и не даёт снять больше 2.5% здоровья за удар
	amount = minf(amount * 0.8, max_hp * 0.025)
	# Порог фазы нельзя «перепрыгнуть»: урон останавливается на 66% / 33%,
	# и босс сразу переходит в следующую фазу (с неуязвимостью)
	var floor_hp := max_hp * (0.66 if phase == 1 else (0.33 if phase == 2 else 0.0))
	if phase < 3 and hp - amount <= floor_hp:
		super._take(maxf(0.0, hp - floor_hp), col, size)
		hp = floor_hp
		_enter_phase(phase + 1)
		return
	super._take(amount, col, size)


## Оглушение не действует, пока босс меняет фазу.
func stun(t: float, ice := false) -> void:
	if _phase_t > 0.0:
		return
	super.stun(t, ice)


func _process(delta: float) -> void:
	# Таймер неуязвимости идёт всегда — даже если босс оглушён
	if not puppet and _phase_t > 0.0:
		_phase_t = maxf(0.0, _phase_t - delta)
		_tele_node.queue_redraw()
	super._process(delta)


func _speed_k() -> float:
	return [1.0, 1.0, 1.2, 1.45][phase]


func _ai(delta: float) -> Vector2:
	player = main.nearest_player(position)
	var k: float = (1.4 if is_super else 1.0) * float([1.0, 1.0, 1.25, 1.55][phase])
	var to_player: Vector2 = player.position - position
	var dist := to_player.length()
	var dir := to_player / maxf(dist, 0.001)
	_check_phase()
	_tick_marks(delta)
	_shield_t = maxf(0.0, _shield_t - delta)
	# Ушли далеко — босс телепортируется ближе к герою
	if dist > 1000.0 and _telegraph <= 0.0 and _charge_t <= 0.0:
		Fx.portal(main, position, color, 3.0)
		position = player.position + Vector2.RIGHT.rotated(randf() * TAU) * 430.0
		Fx.portal(main, position, color, 3.0)
		Sound.play("ability", -4.0, 0.5)
		main.combo_pop(position + Vector2(0, -110), "БОСС НАСТИГАЕТ!", Pixel.hdr(color, 1.4))
	if _phase_t > 0.0:
		_tele_node.queue_redraw()
		return dir
	_attack_t -= delta * k
	_summon_t -= delta * k
	_special_t -= delta * k
	_tick_stream(delta)
	_tick_beam(delta)
	_tick_pull(delta)
	# Таран и его предупреждение — общие для всех
	if _telegraph > 0.0:
		_telegraph -= delta
		if _telegraph <= 0.0:
			_charge_t = 0.6
			Sound.play("slam", 0.0, 0.7)
		_tele_node.queue_redraw()
		return dir
	if _charge_t > 0.0:
		_charge_t -= delta
		position += _charge_dir * 680.0 * delta
		if randf() < 0.5:
			Fx.burst(main, position, [Color(0.5, 0.4, 0.4, 0.8), Color(0.3, 0.2, 0.2, 0.0)], 3, 80.0, 0.5, 5.0, false)
		if _charge_t <= 0.0:
			_slam()
			if _charges_left > 0:
				_charges_left -= 1
				_charge(dir, 0.45)
		_tele_node.queue_redraw()
		return dir
	_move(delta, dir, dist)
	# Основная атака — своя у каждого
	if _attack_t <= 0.0:
		_attack_t = [0, 2.0, 1.6, 1.25][phase]
		atk_anim = 0.55
		_basic(dir)
	# Особые приёмы — по кругу из доступных в этой фазе
	if _special_t <= 0.0:
		_special_t = [0, 5.0, 4.0, 3.0][phase]
		var pool := _pool()
		var ab: String = pool[_ability_i % pool.size()]
		_ability_i += 1 + randi() % 2
		spc_anim = 0.7
		_use(ab, dir)
		# Омега в третьей фазе применяет два приёма сразу
		if kind == "omega" and phase == 3:
			_use(pool[(_ability_i + 1) % pool.size()], dir)
	_tele_node.queue_redraw()
	return dir


func _pool() -> Array:
	var out: Array = []
	var list: Array = ABILITIES.get(kind, ABILITIES["lich"])
	for p in range(1, phase + 1):
		for a in list[p]:
			if not (a in ["ring", "fan"]) or kind == "omega":
				out.append(a)
	if out.is_empty():
		out = ["teleport"]
	return out


func _move(delta: float, dir: Vector2, dist: float) -> void:
	var spd: float = speed * speed_mult() * _speed_k()
	match kind:
		"lich":
			var tangent := Vector2(-dir.y, dir.x)
			position += (tangent * 0.8 + dir * clampf((dist - 280.0) / 100.0, -1.0, 1.0)).normalized() * spd * delta
		"colossus":
			position += dir * spd * delta
		"queen":
			var wobble := Vector2(sin(_t * 1.7), cos(_t * 1.3)) * 0.6
			position += (dir * clampf((dist - 220.0) / 120.0, -1.0, 1.0) + wobble).normalized() * spd * delta
		_:
			position += (dir * clampf((dist - 240.0) / 120.0, -1.0, 1.0) + Vector2(-dir.y, dir.x) * 0.5).normalized() * spd * delta


func _basic(dir: Vector2) -> void:
	match kind:
		"lich":
			_ring([12, 12, 16, 20][phase], 170.0, Color(0.7, 0.4, 1.0))
		"colossus":
			_charge(dir, 0.85)
		"queen":
			for i in [3, 3, 5, 7][phase]:
				_fire(dir.angle() + (i - ([3, 3, 5, 7][phase] - 1) / 2.0) * 0.4, 150.0, Color(1.0, 0.3, 0.75), true)
			Sound.play("zap", -4.0, 0.8)
		_:
			_ring([14, 14, 18, 22][phase], 180.0, Color(0.3, 1.0, 0.9))


# ================= Фазы =================

func _check_phase() -> void:
	var want := 1 if hp > max_hp * 0.66 else (2 if hp > max_hp * 0.33 else 3)
	if want > phase:
		_enter_phase(want)


func _enter_phase(want: int) -> void:
	phase = want
	if want == 2 and not puppet:
		main.boss_say(self, "half")
	_phase_t = 2.0
	stun_t = 0.0
	frozen = false
	statuses.clear()
	_shield_t = 0.0
	_marks.clear()
	_telegraph = 0.0
	_charge_t = 0.0
	_charges_left = 0
	_special_t = 1.6
	_attack_t = 2.0
	var pname: String = PHASE_NAMES.get(kind, PHASE_NAMES["lich"])[phase]
	var c := color.lerp(Color(1.0, 0.25, 0.2), 0.25 * (phase - 1))
	Fx.text_pop(main, position + Vector2(0, -120), "ФАЗА %d — %s" % [phase, pname.to_upper()], Pixel.hdr(c, 1.6), 30)
	Fx.text_pop(main, position + Vector2(0, -80), "НЕУЯЗВИМ", Pixel.hdr(Color(0.6, 0.85, 1.0), 1.4), 20)
	Fx.ring(main, position, 10.0, 420.0, Pixel.hdr(c, 2.2), 0.7, 10.0)
	Fx.light_flash(main, position, c, 4.0, 8.0, 0.8)
	main.shake(14.0)
	main.screen_flash(0.3)
	Sound.play("siren", -4.0, 0.8 + 0.15 * phase)
	Sound.play("boom", 0.0, 0.6)
	# Ударная волна отталкивает и ранит героев рядом
	for p in main.players:
		var d: Vector2 = p.position - position
		if d.length() < 220.0:
			p.take_damage(damage * 0.5)
			p.position += d.normalized() * 120.0
	if main.hud and main.hud.has_method("boss_phase"):
		main.hud.boss_phase(phase, pname)
	# Свита в новой фазе
	var guard: String = {"lich": "wraith", "colossus": "knight", "queen": "spider"}.get(kind, "caster")
	for i in 2 + phase:
		main.spawn_enemy(guard, position + Vector2.RIGHT.rotated(TAU * i / (2 + phase)) * 110.0)


# ================= Приёмы =================

func _use(ab: String, dir: Vector2) -> void:
	match ab:
		"ring":
			_ring(16, 180.0, color)
		"fan":
			for i in 5:
				_fire(dir.angle() + (i - 2) * 0.35, 160.0, color, true)
		"summon_imp":
			for i in 4:
				main.spawn_enemy("imp", position + Vector2.RIGHT.rotated(TAU * i / 4.0) * 70.0)
		"summon_wraith":
			for i in 5:
				main.spawn_enemy("wraith", position + Vector2.RIGHT.rotated(TAU * i / 5.0) * 90.0)
		"summon_bat":
			for i in 8:
				main.spawn_enemy("bat", position + Vector2.RIGHT.rotated(TAU * i / 8.0) * 90.0)
		"summon_spider":
			for i in 5:
				main.spawn_enemy("spider", position + Vector2.RIGHT.rotated(TAU * i / 5.0) * 90.0)
		"summon_guard":
			for i in 3:
				main.spawn_enemy(["knight", "caster", "bomber"][i], position + Vector2.RIGHT.rotated(TAU * i / 3.0) * 90.0)
		"teleport":
			Fx.portal(main, position, color, 3.0)
			position = player.position + Vector2.RIGHT.rotated(randf() * TAU) * 320.0
			Fx.portal(main, position, color, 3.0)
			Sound.play("ability", -4.0, 0.6)
			_ring(10, 150.0, color)
		"skulls":
			# Медленные самонаводящиеся черепа со всех сторон
			for i in 6:
				_fire(TAU * i / 6.0, 110.0, Color(0.8, 0.5, 1.0), true)
			Sound.play("zap", -4.0, 0.5)
		"meteors":
			# Метки на земле под героями и вокруг — через секунду взрываются
			for p in main.players:
				for i in 3:
					_mark(p.position + Vector2(randf_range(-160, 160), randf_range(-120, 120)) * (0.0 if i == 0 else 1.0), 90.0, 1.1 + i * 0.25, "meteor")
			Sound.play("siren", -12.0, 1.8)
		"rockfall":
			for i in 8:
				_mark(player.position + Vector2(randf_range(-260, 260), randf_range(-200, 200)), 70.0, 0.9 + randf() * 0.8, "meteor")
		"stomp":
			# Кольцо меток вокруг себя
			for i in 8:
				_mark(position + Vector2.RIGHT.rotated(TAU * i / 8.0) * 170.0, 80.0, 0.9, "meteor")
			_mark(position, 110.0, 1.2, "meteor")
		"stream":
			_stream_t = 2.6
		"beam":
			_beam_dir = (player.position - position).normalized()
			_beam_warn = 0.9
			_beam_t = 0.0
			_beam_rot = (1.0 if randf() < 0.5 else -1.0) * 0.9
			Sound.play("siren", -10.0, 2.0)
		"waves":
			for w in 3:
				get_tree().create_timer(w * 0.35).timeout.connect(func():
					if not dead:
						_ring(18, 200.0 + w * 30.0, Color(1.0, 0.55, 0.2), w * 0.1))
			main.shake(8.0)
		"mines":
			for i in 6:
				var b = _fire(TAU * i / 6.0 + randf(), 60.0, Color(1.0, 0.8, 0.2))
				b.life = 9.0
				b.radius = 13.0
		"charge":
			_charge(dir, 0.8)
		"multi_charge":
			_charges_left = 2
			_charge(dir, 0.7)
		"shield":
			_shield_t = 4.0
			Fx.ring(main, position, 20.0, 120.0, Pixel.hdr(Color(0.5, 0.8, 1.0), 2.0), 0.5, 6.0)
			Sound.play("ability", -2.0, 0.5)
		"pull":
			_pull_t = 2.2
			Sound.play("ability", -4.0, 0.4)
		"eggs":
			# Кладки: метки, из которых вылупляются пауки
			for i in 4:
				_mark(position + Vector2.RIGHT.rotated(TAU * i / 4.0 + randf()) * randf_range(120, 220), 50.0, 1.6, "egg")
		"swirl":
			_spiral += 0.5
			for i in 24:
				var b = _fire(TAU * i / 24.0 + _spiral, 120.0, Color(1.0, 0.4, 0.8))
				b.velocity = b.velocity.rotated(0.6)
		"homing_burst":
			for i in 8:
				_fire(TAU * i / 8.0, 140.0, Color(1.0, 0.3, 0.75), true)


func _ring(n: int, spd: float, col: Color, offset := 0.0) -> void:
	_spiral += 0.35
	for i in n:
		_fire(TAU * i / n + _spiral + offset, spd, col)
	Sound.play("zap", -4.0, 0.6)


func _charge(dir: Vector2, warn: float) -> void:
	_telegraph = warn
	_charge_dir = dir
	Sound.play("siren", -10.0, 1.6)


func _mark(pos: Vector2, r: float, t: float, mkind: String) -> void:
	_marks.append({"pos": pos, "t": t, "t0": t, "r": r, "kind": mkind})


func _tick_marks(delta: float) -> void:
	var i := _marks.size() - 1
	while i >= 0:
		var m: Dictionary = _marks[i]
		m["t"] -= delta
		if m["t"] <= 0.0:
			var p: Vector2 = m["pos"]
			if m["kind"] == "egg":
				for k in 2:
					main.spawn_enemy("spider", p + Vector2(randf_range(-20, 20), randf_range(-20, 20)))
				Fx.burst(main, p, [Pixel.hdr(Color(1.0, 0.4, 0.8), 1.5), Color(0.5, 0.2, 0.4, 0.0)], 14, 140.0, 0.5, 4.0)
			else:
				Fx.ring(main, p, 10.0, m["r"] * 1.2, Pixel.hdr(color, 2.0), 0.4, 6.0)
				Fx.burst(main, p, [Pixel.hdr(Color(1.0, 0.6, 0.3), 2.0), Color(0.4, 0.2, 0.2, 0.0)], 18, 200.0, 0.6, 5.0)
				Sound.play("boom", -8.0, 1.2, 0.2, 0.08)
				for pl in main.players:
					if pl.position.distance_to(p) < float(m["r"]):
						pl.take_damage(damage * 0.8)
			_marks.remove_at(i)
		i -= 1


func _tick_stream(delta: float) -> void:
	if _stream_t <= 0.0:
		return
	_stream_t -= delta
	_spiral += delta * 4.0
	if int(_stream_t * 20.0) % 2 == 0:
		for k in 3:
			_fire(_spiral + TAU * k / 3.0, 190.0, color)


func _tick_beam(delta: float) -> void:
	if _beam_warn > 0.0:
		_beam_warn -= delta
		if _beam_warn <= 0.0:
			_beam_t = 1.4
			Sound.play("thunder", -2.0, 0.7)
		return
	if _beam_t <= 0.0:
		return
	_beam_t -= delta
	_beam_dir = _beam_dir.rotated(_beam_rot * delta)
	main.shake(3.0)
	for p in main.players:
		var rel: Vector2 = p.position - position
		var along := rel.dot(_beam_dir)
		if along > 0.0 and along < 760.0 and absf(rel.cross(_beam_dir)) < 34.0:
			p.take_damage(damage * 0.4)


func _tick_pull(delta: float) -> void:
	if _pull_t <= 0.0:
		return
	_pull_t -= delta
	for p in main.players:
		var d: Vector2 = position - p.position
		if d.length() > 90.0:
			p.position += d.normalized() * 150.0 * delta
	if randf() < 0.4:
		Fx.ring(main, position, 300.0, 20.0, Color(color, 0.5), 0.5, 3.0)


func _fire(angle: float, spd: float, col: Color, homing := false) -> Node2D:
	var b := BulletScript.new()
	b.main = main
	b.player = player
	b.position = position + Vector2(0, -_frames["size"].y * Pixel.PX * 0.45)
	b.velocity = Vector2.RIGHT.rotated(angle) * spd
	b.damage = damage * 0.7
	b.color = col
	b.homing = homing
	main.projectiles_node.add_child(b)
	return b


func _slam(_enraged := false) -> void:
	main.shake(12.0)
	Fx.ring(main, position, 10.0, 260.0, Pixel.hdr(Color(1.0, 0.5, 0.15), 2.0), 0.5, 8.0)
	Fx.burst(main, position, [Color(0.6, 0.5, 0.45, 0.9), Color(0.3, 0.25, 0.2, 0.0)], 30, 300.0, 0.8, 6.0, false)
	Sound.play("boom", 2.0, 0.7)
	var n: int = [10, 10, 14, 18][phase]
	for i in n:
		_fire(TAU * i / n, 210.0, Color(1.0, 0.55, 0.2))
	for p in main.players:
		if position.distance_to(p.position) < 140.0:
			p.take_damage(damage)


func _draw_telegraph(canvas: Node2D) -> void:
	var a := 0.3 + 0.5 * absf(sin(_t * 20.0))
	if _telegraph > 0.0:
		canvas.draw_line(Vector2.ZERO, _charge_dir * 420.0, Color(1.0, 0.2, 0.15, a), 26.0)
		canvas.draw_line(Vector2.ZERO, _charge_dir * 420.0, Color(1.5, 0.5, 0.3, a), 4.0)
	if _beam_warn > 0.0:
		canvas.draw_line(Vector2.ZERO, _beam_dir * 760.0, Color(1.0, 0.2, 0.3, a * 0.6), 8.0)
	elif _beam_t > 0.0:
		var w := 60.0 + 10.0 * sin(_t * 40.0)
		canvas.draw_line(Vector2.ZERO, _beam_dir * 760.0, Color(color, 0.35), w)
		canvas.draw_line(Vector2.ZERO, _beam_dir * 760.0, Pixel.hdr(Color.WHITE, 2.0), w * 0.25)
	if _shield_t > 0.0:
		canvas.draw_arc(Vector2(0, -40), 70.0 + 4.0 * sin(_t * 10.0), 0.0, TAU, 32, Color(0.5, 0.8, 1.0, 0.7), 4.0)
	if _phase_t > 0.0:
		# Купол неуязвимости при смене фазы
		var pk := 1.0 - _phase_t / 2.0
		canvas.draw_arc(Vector2(0, -40), 60.0 + 60.0 * pk, 0.0, TAU, 40, Pixel.hdr(color, 2.0), 6.0)
		canvas.draw_circle(Vector2(0, -40), 85.0, Color(0.5, 0.8, 1.0, 0.18 + 0.1 * sin(_t * 12.0)))
		canvas.draw_arc(Vector2(0, -40), 85.0, 0.0, TAU, 40, Color(0.6, 0.9, 1.0, 0.8), 3.0)
	for m in _marks:
		var p: Vector2 = m["pos"] - position
		var k := 1.0 - float(m["t"]) / float(m["t0"])
		var col := Color(1.0, 0.4, 0.8) if m["kind"] == "egg" else Color(1.0, 0.25, 0.15)
		canvas.draw_set_transform(p, 0.0, Vector2(1.0, 0.6))
		canvas.draw_arc(Vector2.ZERO, float(m["r"]), 0.0, TAU, 32, Color(col, 0.8), 3.0)
		canvas.draw_circle(Vector2.ZERO, float(m["r"]) * k, Color(col, 0.25))
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _die() -> void:
	super._die()
	main.on_boss_killed(self)
