extends Node2D
## Враг: появление из портала, движение, анимация, статусы (огонь/ток/холод/кровь)
## и реакции между ними. Боссы наследуют этот скрипт (boss.gd).

const Data := preload("res://scripts/data.gd")
const Pixel := preload("res://scripts/pixel.gd")
const Fx := preload("res://scripts/fx.gd")

const SPAWN_TIME := 0.45
const BulletScript := preload("res://scripts/enemy_bullet.gd")

var main: Node2D
var player: Node2D     # цель (ближайший живой герой)
var last_pl: Node2D    # последний, кто ударил — его модули и статы
var _retarget_t := 0.0
var kind := "imp"
var hp := 10.0
var max_hp := 10.0
var speed := 70.0
var damage := 8.0
var radius := 12.0
var color := Color.RED
var xp_value := 1
var is_elite := false
var is_boss := false
var dead := false
var statuses := {}
var last_src := ""
var stun_t := 0.0       # оглушение: не двигается и не бьёт
var frozen := false     # оглушение льдом (ледяная глыба) — другой цвет
var size_mult := 1.0    # супер-босс крупнее
var puppet := false
var net_pos := Vector2.ZERO
var ai := "chase"
var armor := 0.0
var split_kind := ""
var hell := false
var affixes: Array = []    # усиления: armored, swift, regen, berserk, shielded, explosive, giant
var _shield_hp := 0.0
var net_id := 0            # клиент: id врага у хоста
var _net_quiet := false    # хост: попадание клиента — цифру урона клиент уже показал          # адский моб бесконечного режима
var _base_tint := Color.WHITE
var _ai_t := 2.0
var _dash_t := 0.0
var _dash_dir := Vector2.ZERO

var _frames: Dictionary
var _shadow: Sprite2D
var _body: Sprite2D
var _emit: Sprite2D
var _hp_bar: Node2D
var _t := 0.0
var _flash := 0.0
var _knock := Vector2.ZERO
var _spawn := SPAWN_TIME
var _fps := 8.0
var _hover := false
var _dot_t := 0.0
var _sepsis := 0.0


func _apply_affixes() -> void:
	for a in affixes:
		match a:
			"armored":
				armor = maxf(armor, 0.4)
			"swift":
				speed *= 1.45
			"berserk":
				damage *= 1.6
			"shielded":
				_shield_hp = max_hp * 0.5
			"giant":
				max_hp *= 2.2
				hp = max_hp
				size_mult *= 1.35
				radius *= 1.3
				speed *= 0.85
				damage *= 1.3
	xp_value += affixes.size() * 2


func _ready() -> void:
	if not affixes.is_empty() and not puppet:
		_apply_affixes()
	var info: Dictionary = Data.ENEMIES.get(kind, {})
	var sk: String = info.get("sprite", kind)   # адские мобы используют облик обычных
	hell = info.get("hell", false)
	_frames = Pixel.frames(sk)
	var size: Vector2 = _frames["size"]
	_t = randf() * 10.0
	_hover = sk in ["imp", "bat", "wraith", "lich", "queen", "bomber", "omega"]
	_fps = {"imp": 8.0, "bat": 12.0, "ghoul": 6.0, "wraith": 7.0, "brute": 4.0,
		"lich": 5.0, "colossus": 4.0, "queen": 10.0, "goblin": 10.0, "slime": 6.0, "slimelet": 9.0,
		"spider": 10.0, "spiderling": 14.0, "caster": 5.0, "bomber": 12.0, "knight": 5.0, "omega": 5.0}.get(sk, 8.0) * (1.5 if hell else 1.0)
	_ai_t = randf_range(1.0, 3.0)

	_shadow = Sprite2D.new()
	_shadow.texture = Pixel.shadow()
	var sw := size.x * Pixel.PX / 14.0 * (0.7 if sk in ["bat", "queen"] else 0.9)
	_shadow.scale = Vector2(sw, Pixel.PX * (0.8 if _hover else 1.0) * (1.6 if is_boss else 1.0))
	_shadow.position = Vector2(0, 1)
	_shadow.z_index = -5
	add_child(_shadow)

	_body = Sprite2D.new()
	_body.texture = _frames["base"][0]
	_body.scale = Vector2(Pixel.PX, Pixel.PX * Pixel.STAND) * size_mult
	_body.offset = Vector2(0, -size.y / 2.0 + 2.0)
	add_child(_body)
	_emit = Sprite2D.new()
	_emit.texture = _frames["emit"][0]
	_emit.scale = _body.scale
	_emit.offset = _body.offset
	_emit.material = Pixel.mat_unshaded()
	_emit.modulate = Pixel.hdr(Color.WHITE, 1.3)
	add_child(_emit)

	main.mirror(_body, self, false)
	main.mirror(_emit, self, true)
	if not affixes.is_empty():
		# Цветное сияние под врагом — видно, что он усилен
		var aura := Sprite2D.new()
		aura.texture = Pixel.glow()
		aura.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		aura.material = Pixel.mat_add()
		aura.modulate = Color(Data.AFFIXES[affixes[0]]["color"], 0.55)
		aura.scale = Vector2(1.3, 0.7) * size_mult * maxf(1.0, size.x / 16.0)
		aura.z_index = -4
		add_child(aura)
		if affixes.size() > 1:
			var aura2 := aura.duplicate() as Sprite2D
			aura2.modulate = Color(Data.AFFIXES[affixes[1]]["color"], 0.45)
			aura2.scale *= 1.35
			add_child(aura2)
		if "berserk" in affixes:
			_base_tint = _base_tint * Color(1.4, 0.7, 0.7)
	if sk == "wraith":
		_body.modulate = Color(1, 1, 1, 0.75)
	if hell:
		# Адский облик: раскалённый оттенок, огненные глаза и искры
		_base_tint = Color(1.45, 0.55, 0.4)
		var embers := CPUParticles2D.new()
		embers.amount = 5
		embers.lifetime = 0.7
		embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		embers.emission_sphere_radius = size.x * Pixel.PX * 0.3
		embers.position = Vector2(0, -size.y * Pixel.PX * 0.5)
		embers.gravity = Vector2(0, -90)
		embers.initial_velocity_min = 5.0
		embers.initial_velocity_max = 25.0
		embers.scale_amount_min = 2.0
		embers.scale_amount_max = 4.0
		embers.color_ramp = Fx._ramp([Pixel.hdr(Color(1.0, 0.6, 0.2), 2.0), Color(1.0, 0.2, 0.1, 0.0)])
		embers.material = Pixel.mat_add()
		embers.z_index = 2
		add_child(Fx.gpu2d(embers, "hell_embers_%d" % int(embers.emission_sphere_radius)))
	if is_elite or is_boss:
		var halo := Sprite2D.new()
		halo.texture = Pixel.glow()
		halo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		halo.material = Pixel.mat_add()
		halo.modulate = Color(color, 0.35)
		halo.scale = Vector2.ONE * (2.4 if is_boss else 1.6)
		halo.position = Vector2(0, -size.y * Pixel.PX * 0.45)
		halo.z_index = -1
		add_child(halo)
		var light := PointLight2D.new()
		light.texture = Pixel.glow()
		light.color = color
		light.energy = 1.1
		light.texture_scale = 3.5 if is_boss else 2.5
		light.position = halo.position
		add_child(light)
		main.mirror_light(light, self, 1.5 if is_boss else 1.0)
	if is_elite:
		_hp_bar = preload("res://scripts/drawer.gd").new()
		_hp_bar.draw_fn = _draw_hp
		_hp_bar.material = Pixel.mat_unshaded()
		_hp_bar.z_index = 10
		add_child(_hp_bar)

	Fx.portal(main, position, color, 3.0 if is_boss else (2.2 if is_elite else 1.0))
	_set_spawn_visual(0.0)


func can_hurt() -> bool:
	return not dead and _spawn <= 0.0 and stun_t <= 0.0 and ai != "altar"


## Оглушить (боссы — гораздо короче).
func stun(t: float, ice := false) -> void:
	if dead:
		return
	stun_t = maxf(stun_t, t * (0.25 if is_boss else 1.0))
	frozen = ice


func can_be_hit() -> bool:
	return not dead and _spawn < SPAWN_TIME * 0.5


func _set_spawn_visual(k: float) -> void:
	_body.scale = Vector2(Pixel.PX * (1.0 + (1.0 - k) * 0.6), Pixel.PX * Pixel.STAND * maxf(0.05, k)) * size_mult
	_emit.scale = _body.scale
	_body.modulate.a = k * (0.75 if kind == "wraith" else 1.0)
	_emit.modulate = Color(color, 0.25 + 0.35 * k) if k < 0.6 else Pixel.hdr(Color.WHITE, 1.3)
	_emit.texture = _frames["flash"][0] if k < 0.6 else _frames["emit"][0]


## Оптимизация: за пределами поля зрения враг думает в 4 раза реже и не анимируется
var vis := true
var _off_acc := 0.0
var _phase := randi() % 4


func _process(delta: float) -> void:
	_t += delta
	if puppet:
		_puppet_tick(delta)
		return
	if _spawn > 0.0:
		_spawn -= delta
		_set_spawn_visual(clampf(1.0 - _spawn / SPAWN_TIME, 0.0, 1.0))
		return
	if not is_boss:
		var fr: int = main._frame + _phase
		if fr % 4 == 0:
			vis = main._on_view(position)
		if not vis:
			_off_acc += delta
			if fr % 4 != 0:
				return
			delta = minf(_off_acc, 0.2)
			_off_acc = 0.0
			_tick_statuses(delta)
			if dead:
				return
			if stun_t > 0.0:
				stun_t -= delta
				if stun_t <= 0.0:
					frozen = false
				return
			_retarget_t -= delta
			if _retarget_t <= 0.0:
				_retarget_t = 0.4
				player = main.nearest_player(position)
			_ai(delta)
			_knock = Vector2.ZERO
			_flash = 0.0
			return
	_tick_statuses(delta)
	if dead:
		return
	if "regen" in affixes and hp < max_hp:
		hp = minf(max_hp, hp + max_hp * 0.025 * delta)
	if stun_t > 0.0:
		stun_t -= delta
		_flash = maxf(0.0, _flash - delta)
		_knock = _knock.move_toward(Vector2.ZERO, 900.0 * delta)
		position += _knock * delta
		if stun_t <= 0.0:
			frozen = false
		_animate(Vector2.ZERO)
		return
	_retarget_t -= delta
	if _retarget_t <= 0.0:
		_retarget_t = 0.4
		player = main.nearest_player(position)
	var dir := _ai(delta)
	position = main.push_out(position, radius * 0.8, 1)
	_knock = _knock.move_toward(Vector2.ZERO, 900.0 * delta)
	_flash = maxf(0.0, _flash - delta)
	_animate(dir)


func _puppet_tick(delta: float) -> void:
	if _spawn > 0.0:
		_spawn -= delta
		_set_spawn_visual(clampf(1.0 - _spawn / SPAWN_TIME, 0.0, 1.0))
	var prev := position
	position = position.lerp(net_pos, 1.0 - exp(-14.0 * delta))
	_flash = maxf(0.0, _flash - delta)
	var dir := position - prev
	if _spawn <= 0.0:
		_animate(dir if dir.length() > 0.05 else Vector2.ZERO)


## Клиент: состояние из снимка хоста.
func net_state(pos: Vector2, hpr: float, st: int) -> void:
	net_pos = pos
	var nh := hpr * max_hp
	if nh < hp - 0.01:
		_flash = 0.1
	hp = nh
	statuses.clear()
	var names := ["burn", "shock", "chill", "bleed", "poison", "wet"]
	for i in 6:
		if st & (1 << i):
			statuses[names[i]] = 1.0


func net_bits() -> int:
	var b := 0
	var names := ["burn", "shock", "chill", "bleed", "poison", "wet"]
	for i in 6:
		if statuses.has(names[i]):
			b |= 1 << i
	return b


## Движение. Возвращает направление взгляда. Боссы переопределяют.
func _ai(delta: float) -> Vector2:
	if ai == "altar":
		# Алтарь мобов: не двигается, раз в несколько секунд призывает свиту
		_ai_t -= delta
		if _ai_t <= 0.0:
			_ai_t = 3.2
			if player.position.distance_to(position) < 1400.0:
				for i in 3:
					main.spawn_enemy(main.pick_enemy_kind(), position + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(70.0, 120.0))
				Fx.ring(main, position, 10.0, 140.0, Pixel.hdr(color, 1.6), 0.4, 4.0)
		return Vector2.ZERO
	var to_player: Vector2 = player.position - position
	var dist := to_player.length()
	if dist > 1700.0:
		position = player.position + to_player.normalized() * 1000.0
		return Vector2.RIGHT
	var dir := to_player / maxf(dist, 0.001)
	var move := dir
	_ai_t -= delta
	match ai:
		"dash":  # кибер-гоблин: время от времени делает рывок
			if _dash_t > 0.0:
				_dash_t -= delta
				position += _dash_dir * speed * 3.2 * delta
				if randf() < 0.4:
					Fx.burst(main, position, [Color(color, 0.6), Color(color, 0.0)], 1, 20.0, 0.3, 3.0)
				return _dash_dir
			if _ai_t <= 0.0 and dist < 420.0:
				_ai_t = randf_range(2.5, 4.0)
				_dash_t = 0.38
				_dash_dir = dir
		"ranged":  # техномант: держит дистанцию и стреляет
			var want := 270.0
			move = dir * clampf((dist - want) / 80.0, -1.0, 1.0) + Vector2(-dir.y, dir.x) * 0.4
			if _ai_t <= 0.0 and dist < 520.0:
				_ai_t = randf_range(2.6, 3.4)
				var b := BulletScript.new()
				b.main = main
				b.player = player
				b.position = position + Vector2(0, -30)
				b.velocity = (player.position - position).normalized() * 190.0
				b.damage = damage
				b.color = Color(0.85, 0.45, 1.0)
				b.radius = 7.0
				main.projectiles_node.add_child(b)
				Sound.play("zap", -12.0, 1.4, 0.1, 0.1)
		"bomber":  # дрон-камикадзе: взрывается рядом с героем
			if dist < 55.0 and _spawn <= 0.0:
				_explode()
				return dir
	position += (move.normalized() * speed * speed_mult() + _knock) * delta
	return dir


func _explode() -> void:
	if dead:
		return
	var c := position + Vector2(0, -20)
	Fx.explosion(main, c, Color(1.0, 0.6, 0.15), Color(1.0, 0.25, 0.1), 90.0)
	Sound.play("boom", -4.0, 1.2)
	for p in main.players:
		if p.position.distance_to(position) < 95.0:
			p.take_damage(damage)
	hp = 0.0
	_die()


func speed_mult() -> float:
	var m := 1.0
	if statuses.has("chill"):
		m *= 0.8 if is_boss else 0.45
	if statuses.has("wet"):
		m *= 0.9 if is_boss else 0.75
	return m


func _animate(dir: Vector2) -> void:
	var count: int = _frames["base"].size()
	var f := int(_t * _fps * speed_mult()) % count
	_body.texture = _frames["base"][f]
	if _flash > 0.0:
		_emit.texture = _frames["flash"][f]
		_emit.modulate = Color(1, 1, 1, 0.7)
	else:
		_emit.texture = _frames["emit"][f]
		_emit.modulate = Pixel.hdr(Color(1.0, 0.45, 0.2), 2.2) if hell else Pixel.hdr(Color.WHITE, 1.3)
	if absf(dir.x) > 0.05:
		_body.flip_h = dir.x < 0.0
		_emit.flip_h = _body.flip_h

	var squash := _flash * (1.0 if is_boss else 2.5)
	var sc := Vector2(1.0 + squash, (1.0 - squash) * Pixel.STAND) * Pixel.PX * size_mult
	_body.scale = sc
	_emit.scale = sc
	if _hover:
		var hy := (sin(_t * 5.0) * 4.0 - (16.0 if is_boss else 10.0)) * Pixel.STAND
		_body.position.y = hy
		_emit.position.y = hy
	if kind == "wraith":
		_body.position.x = randf_range(-6, 6) if randf() < 0.03 else 0.0
		_emit.position.x = _body.position.x

	# Окраска по статусу
	var tint := _base_tint
	if statuses.has("burn"):
		tint = Color(1.5, 0.85, 0.55)
	if statuses.has("chill"):
		tint = Color(0.65, 1.1, 1.5)
	if statuses.has("bleed"):
		tint = tint * Color(1.3, 0.65, 0.75)
	if statuses.has("poison"):
		tint = tint * Color(0.8, 1.45, 0.6)
	if statuses.has("wet"):
		tint = tint * Color(0.7, 0.85, 1.4)
	if stun_t > 0.0:
		tint = Color(1.4, 1.8, 2.2) if frozen else (Color(1.6, 1.6, 0.8) if int(_t * 8.0) % 2 == 0 else tint)
	if statuses.has("shock") and int(_t * 20.0) % 3 == 0:
		tint = Color(0.9, 1.0, 1.9)
	_body.modulate = Color(tint, _body.modulate.a)


# ---------- Статусы ----------

func _tick_statuses(delta: float) -> void:
	if statuses.is_empty():
		return
	for st in statuses.keys():
		statuses[st] -= delta
		if statuses[st] <= 0.0:
			statuses.erase(st)
	_dot_t -= delta
	if _dot_t <= 0.0:
		_dot_t = 0.5
		var ap: Node2D = _atk()
		var mult: float = ap.damage_mult * ap.dot_mult
		if statuses.has("burn"):
			_take(4.0 * mult, Color(1.0, 0.6, 0.2))
		if statuses.has("bleed"):
			_take(3.0 * mult, Color(1.0, 0.25, 0.35))
		if statuses.has("poison"):
			_take(3.5 * mult * (3.0 if _sepsis > 0.0 else 1.0), Color(0.55, 1.0, 0.3))
	_sepsis = maxf(0.0, _sepsis - delta)
	# Немного частиц, но с общим бюджетом на кадр
	if not statuses.is_empty() and main.status_fx_budget > 0 and randf() < 0.08:
		main.status_fx_budget -= 1
		var st: String = statuses.keys()[randi() % statuses.size()]
		var c: Color = Data.STATUSES[st]["color"]
		var top := position + Vector2(randf_range(-radius, radius), -_frames["size"].y * Pixel.PX * 0.5)
		match st:
			"burn":
				Fx.burst(main, top, [Pixel.hdr(c, 2.0), Color(1.0, 0.2, 0.1, 0.0)], 3, 40.0, 0.5, 3.0, true, Vector2(0, -60))
			"chill":
				Fx.burst(main, top, [Pixel.hdr(c, 1.5), Color(c, 0.0)], 2, 20.0, 0.6, 2.5, true, Vector2(0, 20))
			"shock":
				Fx.sparks(main, top, c, 3)
			"bleed":
				Fx.burst(main, top, [Color(0.9, 0.1, 0.2, 1.0), Color(0.5, 0.0, 0.1, 0.0)], 2, 30.0, 0.5, 2.5, false, Vector2(0, 160))
			"poison":
				Fx.burst(main, top, [Pixel.hdr(c, 1.5), Color(0.2, 0.6, 0.1, 0.0)], 3, 25.0, 0.8, 3.0, true, Vector2(0, -30))
			"wet":
				Fx.burst(main, top, [Color(0.5, 0.7, 1.0, 0.9), Color(0.3, 0.5, 1.0, 0.0)], 2, 15.0, 0.5, 2.0, false, Vector2(0, 220))


## Наложить статус. Если на враге уже есть другой — срабатывает реакция.
func apply_status(st: String) -> void:
	if dead or st == "":
		return
	if puppet:
		Net.client_hit(net_id, 0.0, st, false, "")
		return
	for other in statuses.keys():
		if other == st:
			continue
		var key := Data.reaction_key(st, other)
		if Data.REACTIONS.has(key):
			statuses.erase(other)
			_react(key)
			return
	preload("res://scripts/meta.gd").discover("s:" + st)
	var ap: Node2D = _atk()
	var wst: float = ap.weapon_status if Data.WEAPONS.has(ap._src) else 1.0
	statuses[st] = Data.STATUSES[st]["time"] * ap.status_mult * wst * (1.0 + 0.6 * ap.aspect_k(ap._src, "duration"))


func _react(key: String) -> void:
	preload("res://scripts/meta.gd").discover("r:" + key)
	var center := position + Vector2(0, -_frames["size"].y * Pixel.PX * 0.4)
	main.on_reaction(key, center)
	_react_effect(key, center)


func _react_effect(key: String, center: Vector2) -> void:
	var r: Dictionary = Data.REACTIONS[key]
	var c: Color = r["color"]
	var pl = _atk()
	var mult: float = pl.damage_mult * pl.react_mult
	var ar: float = maxf(1.0, pl.area_mult)
	match key:
		"burn+shock":  # Перегрузка: взрыв по области
			Fx.explosion(main, center, Color(1.0, 0.5, 0.15), Color(0.8, 0.4, 1.0), 85.0 * ar)
			main.damage_area(center, 85.0 * ar, 28.0 * mult, self)
			_take(28.0 * mult, c)
		"chill+shock":  # Сверхпроводник: цепь к соседям
			var targets: Array = main.nearest_enemies_to(center, 4 + pl.chain_bonus, 240.0 * ar, self)
			var pts := PackedVector2Array([center])
			for t in targets:
				pts.append(t.position + Vector2(0, -15))
				t.hit(18.0 * mult, center, 60.0)
			if pts.size() > 1:
				Fx.chain(main, pts, Color(0.5, 0.9, 1.0))
			_take(18.0 * mult, c)
		"burn+chill":  # Мокрый: лёд тает
			Fx.burst(main, center, [Color(0.5, 0.75, 1.0, 0.9), Color(0.3, 0.5, 1.0, 0.0)], 10, 120.0, 0.6, 3.0, false, Vector2(0, 200))
			statuses["wet"] = Data.STATUSES["wet"]["time"] * pl.status_mult
			_take(8.0 * mult, c)
		"shock+wet":  # Электрошок: сильный удар, оглушение, разряд по мокрым рядом
			Fx.explosion(main, center, Color(0.6, 0.85, 1.0), Color(1.0, 1.0, 1.0), 70.0)
			Fx.light_flash(main, center, Color(0.6, 0.8, 1.0), 1.5, 4.0, 0.3)
			main.beam3d(PackedVector3Array([main.to3d(position, 3.5), main.to3d(position, 0.2)]), Color(0.7, 0.9, 1.0), 0.06, 0.3, 0.25)
			stun(1.6)
			_take(minf(max_hp * 0.25, 120.0) * mult + 30.0 * mult, Color(0.7, 0.9, 1.0), 22)
			var pts := PackedVector2Array([center])
			for t in main.nearest_enemies_to(center, 6, 260.0, self):
				if t.statuses.has("wet"):
					pts.append(t.position + Vector2(0, -15))
					t.statuses.erase("wet")
					t.stun(1.0)
					t.hit(30.0 * mult, center, 60.0)
			if pts.size() > 1:
				Fx.chain(main, pts, Color(0.6, 0.85, 1.0))
		"chill+wet":  # Ледяная глыба: вмерзает и оглушён
			Fx.ring(main, center, 6.0, 55.0, Color(0.8, 0.95, 1.0, 0.8), 0.35, 4.0)
			Fx.burst(main, center, [Color(0.9, 1.0, 1.0, 0.9), Color(0.6, 0.9, 1.0, 0.0)], 12, 90.0, 0.6, 4.0)
			stun(2.2, true)
			statuses["chill"] = 2.2
			_take(15.0 * mult, c)
		"burn+wet":  # Пар: облако обжигающего пара
			_cloud(center, 95.0, 6.0 * mult, "", Color(0.85, 0.85, 0.95), 2.5)
			_take(12.0 * mult, c)
		"burn+poison":  # Токсичный взрыв + ядовитое облако
			Fx.explosion(main, center, Color(0.7, 1.0, 0.2), Color(0.3, 0.8, 0.1), 80.0)
			main.damage_area(center, 80.0, 22.0 * mult, self)
			_cloud(center, 85.0, 4.0 * mult, "poison", Color(0.5, 1.0, 0.2), 3.0)
			_take(22.0 * mult, c)
		"chill+poison":  # Оцепенение
			Fx.burst(main, center, [Pixel.hdr(c, 1.4), Color(c, 0.0)], 8, 80.0, 0.6, 3.0)
			stun(1.4)
			statuses["poison"] = 4.0
			_take(10.0 * mult, c)
		"poison+shock":  # Нейротоксин: ток разносит яд
			var pts2 := PackedVector2Array([center])
			for t in main.nearest_enemies_to(center, 5, 230.0, self):
				pts2.append(t.position + Vector2(0, -15))
				t.statuses["poison"] = 4.0
				t.hit(10.0 * mult, center, 30.0)
			if pts2.size() > 1:
				Fx.chain(main, pts2, Color(0.6, 1.0, 0.4))
			statuses["poison"] = 4.0
			_take(16.0 * mult, c)
		"bleed+poison":  # Заражение: тройной урон яда
			Fx.burst(main, center, [Pixel.hdr(c, 1.5), Color(0.4, 0.1, 0.1, 0.0)], 8, 70.0, 0.7, 3.0, false, Vector2(0, 80))
			statuses["poison"] = 5.0
			_sepsis = 5.0
			_take(14.0 * mult, c)
		"bleed+burn":  # Прижигание: урон + лечение героя
			Fx.burst(main, center, [Color(1.0, 0.4, 0.2, 0.8), Color(0.6, 0.0, 0.1, 0.0)], 8, 120.0, 0.5, 3.5)
			pl.heal(2.0, false)
			_take(35.0 * mult, c)
		"bleed+chill":  # Ледяные осколки
			main.spawn_shards(center, 6 + pl.chain_bonus, 12.0 * mult)
			_take(12.0 * mult, c)
		"bleed+shock":  # Разряд крови
			Fx.ring(main, center, 6.0, 70.0 * ar, Color(1.0, 0.3, 0.7, 0.6), 0.3, 3.0)
			Fx.sparks(main, center, Color(1.0, 0.3, 0.7), 12)
			main.damage_area(center, 70.0 * ar, 12.0 * mult, self)
			_take(25.0 * mult, c)


## Облако (пар, яд) — зона на земле вокруг цели.
func _cloud(center: Vector2, r: float, dmg: float, st: String, col: Color, dur: float) -> void:
	var z = preload("res://scripts/zone.gd").new()
	z.main = main
	z.owner_pl = _atk()
	z.position = position
	z.radius = r
	z.damage = dmg
	z.tick = 0.4
	z.duration = dur
	z.status = st
	z.color = col
	z.cloud = true
	main.zones_node.add_child(z)


# ---------- Урон ----------

func _draw_hp(canvas: Node2D) -> void:
	var w := 70.0
	var y: float = -_frames["size"].y * Pixel.PX * Pixel.STAND - 10.0
	canvas.draw_rect(Rect2(-w / 2 - 1, y - 1, w + 2, 7), Color(0.05, 0.02, 0.08))
	canvas.draw_rect(Rect2(-w / 2, y, w * hp / max_hp, 5), Pixel.hdr(Color(1.0, 0.5, 0.1), 1.5))


func _atk() -> Node2D:
	if last_pl != null and is_instance_valid(last_pl):
		return last_pl
	return main.player


## Удар оружием: урон, отбрасывание, статус.
func hit(amount: float, from: Vector2, knockback: float = 160.0, status := "") -> void:
	if not can_be_hit():
		return
	var crit := false
	var atk: Node2D = main.attacker if main.attacker != null else main.player
	last_pl = atk
	var src: String = atk._src
	last_src = src
	amount *= atk.hit_mult(self) * atk.aspect_damage(src)
	var wcrit: float = atk.weapon_crit if Data.WEAPONS.has(src) else 0.0
	if randf() < atk.crit_chance + wcrit + atk.aspect_crit(src):
		amount *= 2.0
		crit = true
	# Рунная броня рыцаря: ток пробивает броню
	if armor > 0.0 and not statuses.has("shock"):
		amount *= 1.0 - armor
	if crit:
		Fx.number(main, position + Vector2(0, -_frames["size"].y * Pixel.PX * 0.8), amount, Color(1.0, 0.3, 0.3), 22)
	_flash = 0.1
	if puppet:
		# Клиент: урон посчитан здесь, хост только применяет его к настоящему врагу
		if not crit:
			Fx.number(main, position + Vector2(0, -_frames["size"].y * Pixel.PX * 0.6), amount, Color(1.0, 0.95, 0.6) if amount < 30.0 else Color(1.0, 0.5, 0.3), 14 if amount < 30.0 else 18)
		var inf2: String = atk.infuse_for(status) if status != "" else ""
		Net.client_hit(net_id, amount, status, crit, src)
		if inf2 != "" and randf() < 0.4:
			Net.client_hit(net_id, 0.0, inf2, false, src)
		atk.on_weapon_hit(src, self, amount, crit)
		return
	if not is_elite and not is_boss:
		_knock = (position - from).normalized() * knockback
	_take(amount, Color(1.0, 0.95, 0.6) if amount < 30.0 else Color(1.0, 0.5, 0.3), 14 if amount < 30.0 else 18)
	if not dead and status != "":
		apply_status(status)
	atk.on_weapon_hit(src, self, amount, crit)
	# Импульс способности: удар несёт и стихию героя
	if not dead and status != "":
		var inf: String = atk.infuse_for(status)
		if inf != "" and randf() < 0.4:
			apply_status(inf)



func _take(amount: float, col := Color(1.0, 0.95, 0.6), size := 14) -> void:
	if dead:
		return
	if _shield_hp > 0.0:
		# Щит усиления поглощает урон первым
		var ab := minf(_shield_hp, amount)
		_shield_hp -= ab
		amount -= ab
		if _shield_hp <= 0.0:
			Fx.ring(main, position, 10.0, 60.0, Color(0.5, 0.7, 1.0, 0.8), 0.3, 3.0)
		if amount <= 0.0:
			return
	hp -= amount
	if _net_quiet:
		Net.replaying = true   # цифру уже показал клиент — у него не дублируем
		Fx.number(main, position + Vector2(0, -_frames["size"].y * Pixel.PX * 0.6), amount, col, size)
		Net.replaying = false
	else:
		Fx.number(main, position + Vector2(0, -_frames["size"].y * Pixel.PX * 0.6), amount, col, size)
	Sound.play("hit", -14.0, 1.0, 0.2, 0.05)
	if hp <= 0.0:
		_die()


func _die() -> void:
	dead = true
	if "explosive" in affixes and not puppet:
		# Взрывной: детонирует при смерти — держитесь подальше
		var c0 := position + Vector2(0, -15)
		Fx.explosion(main, c0, Color(1.0, 0.6, 0.15), Color(1.0, 0.25, 0.1), 110.0)
		for p in main.players:
			if p.position.distance_to(position) < 110.0:
				p.take_damage(damage * 1.5)
	var center: Vector2 = position + Vector2(0, -_frames["size"].y * Pixel.PX * 0.4)
	Fx.death(main, center, color, is_elite or is_boss)
	if is_elite or is_boss:
		Fx.light_flash(main, center, color, 3.0, 6.0, 0.6)
		Sound.play("boom", 0.0)
	else:
		Sound.play("kill", -10.0, 1.0, 0.25, 0.04)
	main.on_enemy_killed(self)
	_atk().on_weapon_kill(last_src, self)
	if split_kind != "":
		var n := 2 if split_kind == "slimelet" else 3
		for i in n:
			main.spawn_enemy(split_kind, position + Vector2.RIGHT.rotated(TAU * i / n + randf()) * 25.0)
	queue_free()
