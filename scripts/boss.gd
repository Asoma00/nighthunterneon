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
## Читаемые позы: по ним видно, что босс сейчас сделает
## windup — замах (таран, удар о землю), run — рывок, cast — заклинание (снаряды, луч),
## summon — призыв свиты, vanish — сейчас исчезнет (место появления отмечено)
var pose := ""
var _pend := ""            # приём, который босс готовит (сработает по окончании позы)
var _pend_t := 0.0
var _pend_t0 := 1.0
var _pend_dir := Vector2.ZERO
var _pend_dest := Vector2.ZERO
var _pend_basic := false
var _hold := ""            # поза держится чуть после приёма
var _hold_t := 0.0
var _step_f := -1

const POSE_OF := {"ring": "cast", "fan": "cast", "skulls": "cast", "meteors": "cast", "stream": "cast",
	"beam": "cast", "swirl": "cast", "homing_burst": "cast", "shield": "cast", "pull": "cast",
	"summon_imp": "summon", "summon_wraith": "summon", "summon_bat": "summon", "summon_spider": "summon",
	"summon_guard": "summon", "eggs": "summon",
	"stomp": "windup", "waves": "windup", "rockfall": "windup", "mines": "windup",
	"teleport": "vanish"}
const POSE_COLOR := {"cast": Color(0.75, 0.4, 1.0), "summon": Color(0.4, 1.0, 0.55),
	"windup": Color(1.0, 0.3, 0.2), "vanish": Color(0.35, 0.9, 1.0)}
const POSE_WORD := {"cast": "заклинание", "summon": "призыв", "windup": "удар", "vanish": "исчезает"}

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


const BOSS_SCALE := 1.4          # боссы крупнее обычного
const OUTLINE_COL := Color(1.0, 0.08, 0.06)
var _outline: Sprite2D


func _ready() -> void:
	is_boss = true
	size_mult *= BOSS_SCALE
	radius *= 1.25
	super._ready()
	_tele_node = preload("res://scripts/drawer.gd").new()
	_tele_node.draw_fn = _draw_telegraph
	_tele_node.material = Pixel.mat_add()
	_tele_node.z_index = 3   # знаки атак — поверх луж и прочих эффектов на земле
	add_child(_tele_node)
	# Яркая красная обводка — босса видно сквозь любые эффекты
	if _body != null:
		_outline = Sprite2D.new()
		_outline.material = Pixel.mat_unshaded()
		_outline.modulate = Pixel.hdr(OUTLINE_COL, 2.6)
		_outline.offset = _body.offset
		add_child(_outline)
		main.mirror(_outline, self, true)
		_sync_outline()


func _sync_outline() -> void:
	if _outline == null or _body == null:
		return
	_outline.visible = _body.visible and not dead
	var t := Pixel.ring_outline(_body.texture, 2)
	if _outline.texture != t:
		_outline.texture = t
	_outline.flip_h = _body.flip_h
	_outline.scale = _body.scale
	_outline.position = _body.position
	_outline.offset = _body.offset
	_outline.modulate.a = 0.75 + 0.25 * sin(_t * 6.0)


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
	if not dead and _body != null and _spawn <= 0.0:
		_pose_body(delta)
	_sync_outline()


## Поза меняет силуэт: присед перед ударом, наклон в рывке, подъём при заклинании,
## присед с зелёным свечением при призыве, мерцание перед исчезновением.
var _pk := {"sx": 1.0, "sy": 1.0, "ox": 0.0, "oy": 0.0, "glow": 0.0}
func _pose_body(delta: float) -> void:
	var face := -1.0 if _body.flip_h else 1.0
	var want := {"sx": 1.0, "sy": 1.0, "ox": 0.0, "oy": 0.0, "glow": 0.0}
	var pulse := 0.5 + 0.5 * sin(_t * 14.0)
	match pose:
		"windup":
			want = {"sx": 1.1, "sy": 0.86, "ox": -10.0 * face, "oy": 0.0, "glow": 0.6 + 0.4 * pulse}
		"run":
			want = {"sx": 1.14, "sy": 0.93, "ox": 12.0 * face, "oy": 0.0, "glow": 0.4}
		"cast":
			want = {"sx": 0.96, "sy": 1.08, "ox": 0.0, "oy": -16.0, "glow": 0.5 + 0.5 * pulse}
		"summon":
			want = {"sx": 1.12, "sy": 0.84, "ox": 0.0, "oy": 0.0, "glow": 0.5 + 0.5 * pulse}
		"vanish":
			want = {"sx": 0.9, "sy": 1.12, "ox": 0.0, "oy": -10.0, "glow": 1.0}
	var k := 1.0 - exp(-14.0 * delta)
	for key in _pk:
		_pk[key] = lerpf(float(_pk[key]), float(want[key]), k)
	var sc := Vector2(float(_pk["sx"]), float(_pk["sy"]))
	_body.scale *= sc
	_emit.scale = _body.scale
	var base_y := _body.position.y if _hover else 0.0
	_body.position = Vector2(float(_pk["ox"]), base_y + float(_pk["oy"]) * Pixel.STAND)
	_emit.position = _body.position
	var g := float(_pk["glow"])
	if g > 0.02 and pose != "":
		var pc: Color = POSE_COLOR.get(pose, color)
		_emit.modulate = Pixel.hdr(Color.WHITE.lerp(pc, 0.7), 1.3 + 1.6 * g)
	if pose == "vanish":
		var fade := clampf(_pend_t / maxf(0.01, _pend_t0), 0.15, 1.0)
		_body.modulate.a = fade if int(_t * 18.0) % 3 != 0 else fade * 0.4
		_emit.modulate.a = _body.modulate.a
	elif _body.modulate.a < 1.0 and _flash <= 0.0:
		_body.modulate.a = minf(1.0, _body.modulate.a + delta * 3.0)


func _speed_k() -> float:
	return [1.0, 1.0, 1.2, 1.45][phase]


func _ai(delta: float) -> Vector2:
	player = main.nearest_player(position)
	var k: float = (1.4 if is_super else 1.0) * float([1.0, 1.0, 1.25, 1.55][phase])
	var to_player: Vector2 = player.position - position
	var dist := to_player.length()
	var dir := to_player / maxf(dist, 0.001)
	_check_phase()
	_update_pose()
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
	# Подготовка приёма: босс стоит в позе, по которой видно, что будет дальше
	if _pend != "" or _pend_basic:
		_pend_t -= delta
		if _pend_t <= 0.0:
			_release(dir)
		_tele_node.queue_redraw()
		return dir
	_move(delta, dir, dist)
	# Основная атака — своя у каждого (таран Колосса предупреждает сам)
	if _attack_t <= 0.0:
		_attack_t = [0, 2.0, 1.6, 1.25][phase]
		if kind == "colossus":
			atk_anim = 0.55
			_basic(dir)
		else:
			_prepare("", dir, true)
	# Особые приёмы — по кругу из доступных в этой фазе
	elif _special_t <= 0.0:
		_special_t = [0, 5.0, 4.0, 3.0][phase]
		var pool := _pool()
		var ab: String = pool[_ability_i % pool.size()]
		_ability_i += 1 + randi() % 2
		if ab in ["charge", "multi_charge"]:
			spc_anim = 0.7
			_use(ab, dir)
		else:
			_prepare(ab, dir, false)
	_tele_node.queue_redraw()
	return dir


## Начать подготовку приёма: поза + знак на земле. Сам приём — через _pend_t.
func _prepare(ab: String, dir: Vector2, basic: bool) -> void:
	_pend = ab
	_pend_basic = basic
	_pend_dir = dir
	_pend_t0 = [0.0, 0.6, 0.5, 0.4][phase] * (0.8 if is_super else 1.0)
	if basic:
		_pend_t0 *= 0.75
	_pend_t = _pend_t0
	if ab == "teleport":
		_pend_dest = player.position + Vector2.RIGHT.rotated(randf() * TAU) * 320.0
		_pend_t = _pend_t0 + 0.25
		_pend_t0 = _pend_t
	var ps := _pend_pose()
	Sound.play({"cast": "zap", "summon": "ability", "windup": "slam", "vanish": "ability"}.get(ps, "zap"), -14.0, 0.5)


func _pend_pose() -> String:
	if _pend_basic:
		return "windup" if kind == "queen" else "cast"
	return str(POSE_OF.get(_pend, "cast"))


## Приём сработал.
func _release(dir: Vector2) -> void:
	var was := _pend_pose()
	if _pend_basic:
		atk_anim = 0.55
		_basic(_pend_dir if _pend_dir != Vector2.ZERO else dir)
	if _pend != "":
		spc_anim = 0.7
		_use(_pend, dir)
		# Омега в третьей фазе применяет два приёма сразу
		if kind == "omega" and phase == 3:
			var pool := _pool()
			var second: String = pool[(_ability_i + 1) % pool.size()]
			if not (second in ["charge", "multi_charge"]):
				_use(second, dir)
	_pend = ""
	_pend_basic = false
	_hold = "" if was == "vanish" else was
	_hold_t = 0.35


func _update_pose() -> void:
	var dt := get_process_delta_time()
	_hold_t = maxf(0.0, _hold_t - dt)
	if _phase_t > 0.0:
		pose = ""
	elif _telegraph > 0.0:
		pose = "windup"
	elif _charge_t > 0.0:
		pose = "run"
	elif _pend != "" or _pend_basic:
		pose = _pend_pose()
	elif _beam_warn > 0.0 or _beam_t > 0.0 or _stream_t > 0.0 or _pull_t > 0.0:
		pose = "cast"
	elif _hold_t > 0.0:
		pose = _hold
	else:
		pose = ""
	# Тяжёлая поступь Колосса: пыль и дрожь на каждом шаге
	if kind == "colossus" and pose == "" and not puppet:
		var sf := int(_t * _fps * speed_mult()) % 6
		if sf != _step_f and (sf == 0 or sf == 3):
			Fx.burst(main, position + Vector2(randf_range(-30, 30), 4), [Color(0.6, 0.5, 0.45, 0.7), Color(0.3, 0.25, 0.2, 0.0)], 6, 90.0, 0.5, 5.0, false)
			main.shake(1.5)
			Sound.play("slam", -20.0, 0.6, 0.1)
		_step_f = sf



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
	_pend = ""
	_pend_basic = false
	_pend_dest = Vector2.ZERO
	pose = ""
	_special_t = 1.6
	_attack_t = 2.0
	var pname: String = PHASE_NAMES.get(kind, PHASE_NAMES["lich"])[phase]
	var c := color.lerp(Color(1.0, 0.25, 0.2), 0.25 * (phase - 1))
	Fx.text_pop(main, position + Vector2(0, -120), "ФАЗА %d — %s" % [phase, pname.to_upper()], Pixel.hdr(c, 1.6), 30)
	Fx.text_pop(main, position + Vector2(0, -80), "НЕУЯЗВИМ", Pixel.hdr(Color(0.6, 0.85, 1.0), 1.4), 20)
	_bring(position, 10.0, 420.0, Pixel.hdr(c, 2.2), 0.7, 10.0)
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
			position = _pend_dest if _pend_dest != Vector2.ZERO else player.position + Vector2.RIGHT.rotated(randf() * TAU) * 320.0
			_pend_dest = Vector2.ZERO
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
			_bring(position, 20.0, 120.0, Pixel.hdr(Color(0.5, 0.8, 1.0), 2.0), 0.5, 6.0)
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
				_bring(p, 10.0, m["r"] * 1.2, Pixel.hdr(color, 2.0), 0.4, 6.0)
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
		_bring(position, 300.0, 20.0, Color(color, 0.5), 0.5, 3.0)


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
	# Земля трескается, летят обломки
	main.cracks(position, 9, 230.0, Pixel.hdr(Color(1.0, 0.35, 0.12), 2.0))
	Fx.debris3d(main, position, Color(0.45, 0.38, 0.34), 14, 1.4)
	_bring(position, 10.0, 260.0, Pixel.hdr(Color(1.0, 0.5, 0.15), 2.0), 0.5, 8.0)
	Fx.burst(main, position, [Color(0.6, 0.5, 0.45, 0.9), Color(0.3, 0.25, 0.2, 0.0)], 30, 300.0, 0.8, 6.0, false)
	Sound.play("boom", 2.0, 0.7)
	var n: int = [10, 10, 14, 18][phase]
	for i in n:
		_fire(TAU * i / n, 210.0, Color(1.0, 0.55, 0.2))
	for p in main.players:
		if position.distance_to(p.position) < 140.0:
			p.take_damage(damage)


## Яркая красная кромка знаков атак — видно поверх любых эффектов.
func _oarc(canvas: Node2D, c: Vector2, r: float) -> void:
	canvas.draw_arc(c, r + 3.0, 0.0, TAU, 48, Pixel.hdr(OUTLINE_COL, 2.4), 3.0)


func _oline(canvas: Node2D, from: Vector2, to: Vector2, w: float) -> void:
	var n := (to - from).normalized().orthogonal() * (w * 0.5 + 2.0)
	var oc := Pixel.hdr(OUTLINE_COL, 2.4)
	canvas.draw_line(from + n, to + n, oc, 3.0)
	canvas.draw_line(from - n, to - n, oc, 3.0)
	canvas.draw_line(to + n, to - n, oc, 3.0)


func _draw_telegraph(canvas: Node2D) -> void:
	var a := 0.3 + 0.5 * absf(sin(_t * 20.0))
	if _telegraph > 0.0:
		canvas.draw_line(Vector2.ZERO, _charge_dir * 420.0, Color(1.0, 0.2, 0.15, a), 26.0)
		canvas.draw_line(Vector2.ZERO, _charge_dir * 420.0, Color(1.5, 0.5, 0.3, a), 4.0)
		_oline(canvas, Vector2.ZERO, _charge_dir * 420.0, 26.0)
	if _beam_warn > 0.0:
		canvas.draw_line(Vector2.ZERO, _beam_dir * 760.0, Color(1.0, 0.2, 0.3, a * 0.6), 8.0)
		_oline(canvas, Vector2.ZERO, _beam_dir * 760.0, 8.0)
	elif _beam_t > 0.0:
		var w := 60.0 + 10.0 * sin(_t * 40.0)
		canvas.draw_line(Vector2.ZERO, _beam_dir * 760.0, Color(color, 0.35), w)
		canvas.draw_line(Vector2.ZERO, _beam_dir * 760.0, Pixel.hdr(Color.WHITE, 2.0), w * 0.25)
	if _pend != "" or _pend_basic:
		# Знак подготовки: сужающееся кольцо цвета приёма под ногами
		var ps := _pend_pose()
		var pc: Color = POSE_COLOR.get(ps, color)
		var pk := clampf(1.0 - _pend_t / maxf(0.01, _pend_t0), 0.0, 1.0)
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
		canvas.draw_arc(Vector2.ZERO, 150.0 - 90.0 * pk, 0.0, TAU, 40, Color(pc, 0.4 + 0.5 * pk), 5.0)
		canvas.draw_circle(Vector2.ZERO, 60.0 + 20.0 * pk, Color(pc, 0.12 + 0.18 * pk))
		_oarc(canvas, Vector2.ZERO, 150.0 - 90.0 * pk)
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if _pend == "teleport" and _pend_dest != Vector2.ZERO:
			var dp := _pend_dest - position
			canvas.draw_set_transform(dp, 0.0, Vector2(1.0, 0.55))
			canvas.draw_arc(Vector2.ZERO, 40.0 + 50.0 * pk, 0.0, TAU, 32, Color(pc, 0.8), 4.0)
			canvas.draw_circle(Vector2.ZERO, 90.0 * pk, Color(pc, 0.2))
			_oarc(canvas, Vector2.ZERO, 40.0 + 50.0 * pk)
			canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
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
		_oarc(canvas, Vector2.ZERO, float(m["r"]))
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _die() -> void:
	super._die()
	main.on_boss_killed(self)



## Круг атаки босса: сам круг и яркая красная кромка, чтобы читался поверх всего.
func _bring(at: Vector2, r0: float, r1: float, col: Color, dur: float, w: float) -> void:
	Fx.ring(main, at, r0, r1, col, dur, w)
	Fx.ring(main, at, r0 + 4.0, r1 + 6.0, Pixel.hdr(OUTLINE_COL, 2.2), dur, maxf(2.0, w * 0.4))
