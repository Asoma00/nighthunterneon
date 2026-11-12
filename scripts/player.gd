extends Node2D
## Герой: выбранный персонаж, движение, здоровье, опыт, активная способность,
## оружие (с эволюциями и синергиями) и все визуальные слои.

const Data := preload("res://scripts/data.gd")
const Pixel := preload("res://scripts/pixel.gd")
const Fx := preload("res://scripts/fx.gd")
const Drawer := preload("res://scripts/drawer.gd")
const ProjectileScript := preload("res://scripts/projectile.gd")

var main: Node2D
var pid := 0          # 0 — Игрок 1, 1 — Игрок 2 (кооператив)
var profile := {}      # прокачка из чужого сохранения (сетевой игрок); пусто — своё
var choosing := false  # сетевая игра: выбирает улучшение — неуязвим и стоит на месте
var pending_lv := 0
var input              # DevInput: своё устройство в кооперативе (иначе общие действия)
var remote := false   # хост: герой клиента — симулируется у клиента, здесь только показ
var _heal_acc := 0.0
var _heal_t := 0.0
var net_controlled := false  # управляется по сети (герой клиента на хосте)
var puppet := false          # клиент: только показывает состояние, присланное хостом
var net_pos := Vector2.ZERO
var net_vec := Vector2.ZERO
var net_ability := false
var _revive := 0.0
var _marker: Node2D
var char_id := "vega"
var char_data: Dictionary

var radius := 14.0
var base_speed := 210.0
var max_hp := 100.0
var hp := 100.0
var regen := 0.0
var armor := 0.0
var magnet := 90.0
var damage_mult := 1.0
var cooldown_mult := 1.0
var area_mult := 1.0
var xp_mult := 1.0
var crit_chance := 0.0
var status_mult := 1.0
var kill_heal := 0.0
var heal_mult := 1.0
var dmg_taken_k := 1.0   # испытание «Стеклянная пушка»
var dodge := 0.0
var chest_bonus := 0.0
var power := 1.0
var extra_proj := 0
var _src := ""
var _wmods := {}
# Модули оружия (действуют только на оружие)
var weapon_dmg := 1.0
var weapon_cd := 1.0
var weapon_area := 1.0
var weapon_crit := 0.0
var weapon_status := 1.0
var _speed0 := 0.0
var _magnet0 := 0.0

# Связки: импульс способности и вторые грани модулей
var infuse_status := ""
var infuse_t := 0.0
var chain_bonus := 0
var proj_speed := 1.0
var react_mult := 1.0
var dot_mult := 1.0
var _armor_cd := 0.0
var _overflow_t := 0.0
var _spirit_splits := 0

# Аспекты модулей
var _aspect_cache := {}
var _aspect_guard := false
var _bastion := 0.0
var _leech := 0.0

var level := 1
var xp := 0.0
var xp_to_next := 6

var weapons := {}
var evolved := {}      # аспекты оружия: id -> [модуль, ...] (до 3)
var aspect_due: Array = []  # оружие, которому положен выбор аспекта
var passives := {}
var buffs := {}            # баффы алтарей: имя -> оставшееся время
var _buff_d := {}
var fusions: Array = []     # Слияния: [[основа, второе], ...] — до 2 за бой

var ability_cd := 5.0
var ability_left := 0.0

var facing := Vector2.RIGHT
var moving := false
var _invuln := 0.0
var _flash := 0.0
var _anim_t := 0.0
var _dust_t := 0.0
var _cooldowns := {}
var _orbit_angle := 0.0
var _blade_hits := {}
var _aura_timer := 0.0
var _blades_charged := 0.0
var _dead := false

# Способности
var _dash_t := 0.0
var _dash_dir := Vector2.ZERO
var _dash_hit := {}
var _spin_t := 0.0
var _spin_hits := 0
var _shield_t := 0.0

# Визуальные слои
var _frames: Dictionary
var _shadow: Sprite2D
var _body: Sprite2D
var _emit: Sprite2D
var _halo: Sprite2D
var _gear: Node3D
var _idle_t := 0.0
var _gear_key := ""
var _gear_w: Array = []   # [Sprite3D, слот]
var _gear_m: Array = []   # [Sprite3D, фаза]
var _light: PointLight2D
var _aura_glow: Sprite2D
var _aura_ring: Sprite2D
var _aura_embers: Node2D
var _blades: Node2D
var _blade_tex: Texture2D
var _overlay: Node2D
var _drones: Array[Sprite2D] = []
var _swords: Array[Sprite3D] = []
var _drone_t: Array[float] = []
var _drone_shadows: Array[Sprite2D] = []


func setup(id: String) -> void:
	char_id = id
	char_data = Data.CHARACTERS[id]
	max_hp = char_data["hp"]
	hp = max_hp
	base_speed = char_data["speed"]
	ability_cd = char_data["active_cd"]
	match id:
		"vega":
			cooldown_mult = 0.9
		"rin":
			base_speed *= 1.15
			damage_mult = 1.1
		"bram":
			armor = 2.0
		"kira":
			magnet *= 1.4
			xp_mult = 1.15
		"skyla":
			crit_chance = 0.15
		"orm":
			armor = 3.0
			max_hp += 20.0
		"mora":
			kill_heal = 0.5
		"zephyr":
			status_mult = 1.3
		"iris":
			regen = 1.0
			heal_mult = 1.25
		"kai":
			dodge = 0.12
		"lyra":
			damage_mult = 1.1
			area_mult *= 1.1
		"sol":
			max_hp += 30.0
			regen = 0.5
		"volt":
			cooldown_mult = 0.92
			status_mult = 1.15
	# Бонусы зданий Неонового убежища
	var m: Dictionary = _m_run()
	damage_mult *= m["damage"]
	max_hp += m["hp"]
	hp = max_hp
	cooldown_mult *= m["cooldown"]
	magnet *= m["magnet"]
	xp_mult *= m["xp"]
	# Дерево героя из Академии
	var hm: Dictionary = _m_hero()
	max_hp += hm["hp"]
	hp = max_hp
	base_speed *= hm["speed"]
	ability_cd *= hm["ability_cd"]
	power = hm["power"]
	armor += hm["armor"]
	regen += float(hm.get("regen", 0.0))
	magnet *= float(hm.get("magnet", 1.0))
	xp_mult *= float(hm.get("xp", 1.0))
	dodge += float(hm.get("dodge", 0.0))
	damage_mult *= float(hm.get("damage", 1.0))
	laststand = bool(hm.get("laststand", false))


func _ready() -> void:
	if char_data.is_empty():
		setup(char_id)
	_frames = Pixel.frames(char_data["sprite"])
	var size: Vector2 = _frames["size"]

	_shadow = Sprite2D.new()
	_shadow.texture = Pixel.shadow()
	_shadow.scale = Vector2(Pixel.PX * 1.1, Pixel.PX)
	_shadow.position = Vector2(0, 2)
	_shadow.z_index = -5
	add_child(_shadow)
	if not Settings.is_mobile():
		_aim_draw = Drawer.new()
		_aim_draw.draw_fn = _draw_aim
		_aim_draw.material = Pixel.mat_add()
		_aim_draw.z_index = -4
		add_child(_aim_draw)
	if main.coop:
		_marker = Drawer.new()
		_marker.draw_fn = _draw_marker
		_marker.material = Pixel.mat_add()
		_marker.z_index = -4
		add_child(_marker)

	_aura_glow = Sprite2D.new()
	_aura_glow.texture = Pixel.glow()
	_aura_glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_aura_glow.material = Pixel.mat_add()
	_aura_glow.z_index = -6
	_aura_glow.visible = false
	add_child(_aura_glow)
	_aura_ring = Sprite2D.new()
	_aura_ring.texture = Pixel.rune_ring()
	_aura_ring.material = Pixel.mat_add()
	_aura_ring.z_index = -6
	_aura_ring.visible = false
	add_child(_aura_ring)

	_body = Sprite2D.new()
	_body.texture = _frames["base"][0]
	_body.scale = Vector2(Pixel.PX, Pixel.PX * Pixel.STAND) * float(_frames.get("k", 1.0))
	_body.offset = Vector2(0, -size.y / 2.0 + 3.0)
	add_child(_body)
	_emit = Sprite2D.new()
	_emit.texture = _frames["emit"][0]
	_emit.scale = _body.scale
	_emit.offset = _body.offset
	_emit.material = Pixel.mat_unshaded()
	_emit.modulate = Pixel.hdr(Color.WHITE, 1.8)
	add_child(_emit)

	_halo = Sprite2D.new()
	_halo.texture = Pixel.glow()
	_halo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_halo.material = Pixel.mat_add()
	_halo.modulate = Color(char_data["color"], 0.3)
	_halo.scale = Vector2.ONE * 0.6
	_halo.position = Vector2(0, -40)
	add_child(_halo)

	_light = PointLight2D.new()
	_light.texture = Pixel.glow()
	_light.texture_scale = 7.5
	_light.color = Color(0.75, 0.85, 1.0).lerp(char_data["color"], 0.2)
	_light.energy = 1.25
	# Тени от света героя — по настройке качества теней
	_light.shadow_enabled = Settings.shadows > 0
	_light.shadow_filter = [Light2D.SHADOW_FILTER_NONE, Light2D.SHADOW_FILTER_NONE, Light2D.SHADOW_FILTER_PCF5, Light2D.SHADOW_FILTER_PCF13][clampi(Settings.shadows, 0, 3)]
	_light.shadow_filter_smooth = 2.0
	_light.shadow_color = Color(0, 0, 0, 0.85)
	_light.position = Vector2(0, -30)
	add_child(_light)
	main.mirror(_body, self, false)
	main.mirror(_emit, self, true)
	main.mirror_light(_light, self, 1.4)

	_blade_tex = Pixel.frames("blade")["emit"][0]
	_blades = Drawer.new()
	_blades.draw_fn = _draw_blades
	_blades.material = Pixel.mat_add()
	_blades.z_index = 3
	add_child(_blades)

	_overlay = Drawer.new()
	_overlay.draw_fn = _draw_overlay
	_overlay.material = Pixel.mat_add()
	_overlay.z_index = 4
	add_child(_overlay)

	add_weapon(char_data["weapon"])
	if _m_weapon(char_data["weapon"])["master"]:
		add_weapon(char_data["weapon"])
	for mid in Data.PASSIVES:
		if _m_pre(mid):
			add_passive(mid)
	if _m_hero()["awaken"]:
		var keys := Data.PASSIVES.keys()
		add_passive(keys[randi() % keys.size()])


## Клиент: плавно следуем за присланной позицией, только анимация и визуал оружия.
func _puppet_tick(delta: float) -> void:
	if remote:
		_heal_t -= delta
		if _heal_t <= 0.0 and _heal_acc > 0.0:
			_heal_t = 0.3
			Net.event("p_heal", _heal_acc)
			_heal_acc = 0.0
	position = position.lerp(net_pos, 1.0 - exp(-18.0 * delta))
	_flash = maxf(0.0, _flash - delta)
	_invuln = maxf(0.0, _invuln - delta)
	if _dead:
		_anim_t += delta
		return
	_animate(delta)
	if weapons.has("drones"):
		_sync_drones()


## Клиент: применить строку состояния героя из снимка хоста.
func net_state(d: Array, own_progress := false) -> void:
	net_pos = d[0]
	if position.distance_to(net_pos) > 600.0:
		position = net_pos
	facing = d[1]
	if d[2] < hp - 0.5:
		_flash = 0.15
		_hurt_t = 0.3
	hp = d[2]
	max_hp = d[3]
	moving = d[5]
	ability_left = d[6]
	ability_cd = d[7]
	cooldown_mult = 1.0
	_revive = d[8]
	_orbit_angle = d[9]
	_blades_charged = d[10]
	area_mult = d[11]
	if not own_progress:
		level = d[12]
		xp = d[13]
		xp_to_next = d[14]
		choosing = d[15]
	var dead: bool = d[4]
	if dead != _dead:
		_dead = dead
		if dead and remote:
			main.on_player_down(self)   # хост: герой клиента пал
		modulate = Color(0.6, 0.6, 0.9, 0.65) if dead else Color.WHITE
		for n in [_blades, _aura_ring, _aura_glow]:
			n.visible = not dead
		for dr in _drones:
			dr.visible = not dead


func net_row() -> Array:
	return [position, facing, hp, max_hp, _dead, moving, ability_left, ability_cd * cooldown_mult,
		_revive, _orbit_angle, _blades_charged, area_mult, level, xp, xp_to_next, choosing]


## Клиент: прогресс своего героя ведёт хост (опыт, уровень, выбор улучшений).
func net_progress(d: Array) -> void:
	level = d[12]
	xp = d[13]
	xp_to_next = d[14]
	choosing = d[15]


## Клиент: применить к своему герою улучшения, выбранные у хоста (по-настоящему, со всеми эффектами).
func sync_owned_inventory(w: Dictionary, pa: Dictionary, ev: Dictionary, fu: Array) -> void:
	Net.local = true
	for id in w:
		var guard := 0
		while int(weapons.get(id, 0)) < int(w[id]) and guard < 12:
			guard += 1
			var before: int = weapons.get(id, 0)
			add_weapon(id)
			if int(weapons.get(id, 0)) == before:
				break
	for id in pa:
		var guard := 0
		while int(passives.get(id, 0)) < int(pa[id]) and guard < 12:
			guard += 1
			var before: int = passives.get(id, 0)
			add_passive(id)
			if int(passives.get(id, 0)) == before:
				break
	for id in ev:
		for m in ev[id]:
			if not (m in evolved.get(id, [])):
				evolve(id, m)
	aspect_due.clear()
	for pair in fu:
		if pair is Array and pair.size() == 2 and fusion_of(pair[0]).is_empty():
			fuse(pair[0], pair[1])
	Net.local = false


func net_inventory(w: Dictionary, pa: Dictionary, ev: Dictionary) -> void:
	for id in w:
		if not weapons.has(id):
			weapons[id] = 0
			add_weapon(id)
		weapons[id] = w[id]
	passives = pa
	evolved = ev
	_aspect_cache.clear()
	_wmods.clear()


# ---------- Прокачка: своё сохранение или присланный профиль ----------

func _m_run() -> Dictionary:
	return profile["run"] if profile.has("run") else preload("res://scripts/meta.gd").run_mods()


func _m_hero() -> Dictionary:
	return profile["hero"] if profile.has("hero") else preload("res://scripts/meta.gd").hero_mods(char_id)


func _m_weapon(id: String) -> Dictionary:
	if profile.has("weapons") and profile["weapons"].has(id):
		return profile["weapons"][id]
	return preload("res://scripts/meta.gd").weapon_mods(id)


func _m_boost(id: String) -> float:
	if profile.has("boost"):
		return float(profile["boost"].get(id, 1.0))
	return preload("res://scripts/meta.gd").module_boost(id)


func _m_pre(id: String) -> bool:
	if profile.has("pre"):
		return id in profile["pre"]
	return preload("res://scripts/meta.gd").module_preinstalled(id)


func player_color() -> Color:
	return Color(0.3, 0.95, 1.0) if pid == 0 else Color(1.0, 0.4, 0.75)


## Кольцо игрока на полу, а у павшего — круг воскрешения.
func _draw_marker(c: Node2D) -> void:
	var col := player_color()
	if _dead:
		c.draw_arc(Vector2.ZERO, 70.0, 0.0, TAU, 40, Color(col, 0.35 + 0.3 * sin(_anim_t * 5.0) ** 2), 3.0)
		if _revive > 0.0:
			c.draw_arc(Vector2.ZERO, 70.0, -PI / 2, -PI / 2 + TAU * _revive / 2.5, 40, Pixel.hdr(col, 1.5), 5.0)
		return
	var pulse := 0.7 + 0.3 * sin(_anim_t * 4.0)
	c.draw_arc(Vector2(0, 4), 26.0, 0.0, TAU, 28, Color(col, 0.55 * pulse), 2.5)
	# Сетевая игра: стрелка к напарнику, если он далеко
	if main.net_mode != "" and main.players.size() > 1 and main.hud != null and self == main.hud._me():
		var other: Node2D = main.hud._other()
		var to := other.position - position
		if to.length() > 600.0:
			var d := to.normalized()
			var oc: Color = other.player_color()
			var base := d * 70.0
			var sd := d.orthogonal() * 9.0
			c.draw_colored_polygon(PackedVector2Array([base + d * 22.0, base + sd, base - sd]), Color(oc, 0.85 if not other._dead else 0.5 + 0.5 * sin(_anim_t * 8.0)))
	var tip := Vector2(0, 4) + facing * 34.0
	var side := facing.orthogonal() * 6.0
	c.draw_colored_polygon(PackedVector2Array([tip, tip - facing * 9.0 + side, tip - facing * 9.0 - side]), Color(col, 0.8))


## Кооператив: герой пал — лежит призраком, напарник рядом поднимает его.
func _go_down() -> void:
	_dead = true
	_revive = 0.0
	modulate = Color(0.6, 0.6, 0.9, 0.65)
	for n in [_blades, _aura_ring, _aura_glow]:
		n.visible = false
	for d in _drones:
		d.visible = false
	Fx.death(main, position + Vector2(0, -20), player_color(), false)
	main.on_player_down(self)


func _downed_tick(delta: float) -> void:
	var near := false
	for p in main.players:
		if p != self and not p._dead and p.position.distance_to(position) < 90.0:
			near = true
	_revive = clampf(_revive + (delta if near else -delta * 0.5), 0.0, 2.5)
	if _revive >= 2.5:
		_dead = false
		_revive = 0.0
		hp = max_hp * 0.5
		_invuln = 2.0
		modulate = Color.WHITE
		_blades.visible = true
		for d in _drones:
			d.visible = true
		Fx.ring(main, position, 10.0, 160.0, Pixel.hdr(player_color(), 2.0), 0.5, 6.0)
		Fx.text_pop(main, position + Vector2(0, -60), "ВОЗВРАЩЕНИЕ!", Pixel.hdr(player_color(), 1.5), 24)
		Sound.play("ability", -4.0, 1.3)


func _process(delta: float) -> void:
	# Клиент: свой герой считается здесь же, эффекты показываются и у хоста
	var loc: bool = not puppet and main.net_mode == "client"
	if loc:
		Net.local = true
	_process_body(delta)
	if loc:
		Net.local = false


## Отложенное действие оружия (у клиента — тоже локальная симуляция).
func _later(t: float, f: Callable) -> void:
	main.get_tree().create_timer(t, false).timeout.connect(func():
		var loc: bool = not puppet and main.net_mode == "client"
		if loc:
			Net.local = true
		f.call()
		if loc:
			Net.local = false)


func _process_body(delta: float) -> void:
	if puppet:
		_puppet_tick(delta)
		return
	main.attacker = self
	if _dead:
		if main.coop and not main.game_over:
			_anim_t += delta
			_downed_tick(delta)
		elif _death_t >= 0.0:
			# Анимация гибели: оседает, падает и тает
			_death_t += delta
			if _death_t < 1.2 and _frames["base"].size() >= Pixel.HERO_FRAMES:
				var f := Pixel.hero_frame_k("death", _death_t / 1.0)
				_body.texture = _frames["base"][f]
				_emit.texture = _frames["emit"][f]
			else:
				_body.visible = false
				_emit.visible = false
				_death_t = -1.0
		return
	if input != null:
		input.poll()
	if choosing:
		_invuln = maxf(_invuln, 0.2)
	_move(delta)
	_invuln = maxf(0.0, _invuln - delta)
	_flash = maxf(0.0, _flash - delta)
	_blades_charged = maxf(0.0, _blades_charged - delta)
	_shield_t = maxf(0.0, _shield_t - delta)
	if regen > 0.0:
		hp = minf(max_hp, hp + regen * delta)
	infuse_t = maxf(0.0, infuse_t - delta)
	_bastion = maxf(0.0, _bastion - delta * 0.8)
	_leech = maxf(0.0, _leech - delta * 5.0)
	_armor_cd = maxf(0.0, _armor_cd - delta)
	ability_left = maxf(0.0, ability_left - delta)
	_tick_buffs(delta)
	_src = ""
	if _ability_pressed() and ability_left <= 0.0:
		_use_ability()
	_src = ""
	_update_ability(delta)
	_check_contact()
	_update_weapons(delta)
	_animate(delta)


func _ability_pressed() -> bool:
	if net_controlled:
		var p := net_ability
		net_ability = false
		return p
	if input != null:
		return input.just("ability")
	return Input.is_action_just_pressed("ability")


func _move(delta: float) -> void:
	var dir: Vector2
	if choosing:
		dir = Vector2.ZERO
	elif net_controlled:
		dir = net_vec.limit_length(1.0)
	elif input != null:
		dir = input.vector()
	else:
		dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	moving = dir != Vector2.ZERO
	if moving:
		facing = dir.normalized()
	_update_aim(delta)
	if aim != Vector2.ZERO:
		facing = aim
	if _aim_draw != null:
		_aim_shown = _aim_shown.slerp(aim, 1.0 - exp(-18.0 * delta)) if (aim != Vector2.ZERO and _aim_shown != Vector2.ZERO) else aim
		_aim_draw.queue_redraw()
	if _dash_t > 0.0:
		return
	position += dir * base_speed * delta
	position = main.push_out(position, radius)


## Взгляд героя (ПК / Steam Deck): мышь или правый стик. Ноль — автоприцел по ближайшим.
var aim := Vector2.ZERO
var _aim_draw: Node2D
var _aim_shown := Vector2.ZERO


## Прицел: точка взгляда и пунктир к ней (рисуется, только когда герой смотрит вручную).
func _draw_aim(c: Node2D) -> void:
	if _aim_shown == Vector2.ZERO or _dead:
		return
	var col := Color(0.3, 0.95, 1.0) if pid == 0 else Color(1.0, 0.4, 0.75)
	var a := _aim_shown
	for k in 4:
		var a0 := Vector2(0, 4) + a * (46.0 + k * 22.0)
		c.draw_line(a0, a0 + a * 10.0, Color(col, 0.3 + 0.12 * k), 2.5)
	var rp := Vector2(0, 4) + a * 140.0
	c.draw_arc(rp, 12.0, 0.0, TAU, 20, Color(col, 0.9), 2.5)
	c.draw_circle(rp, 3.0, Color(col, 0.95))
var _aim_in: RefCounted
var _aim_hold := 0.0


func _update_aim(_delta: float) -> void:
	# Ручное прицеливание убрано совсем: оружие всегда бьёт по автоприцелу
	aim = Vector2.ZERO


func in_aura(pos: Vector2) -> bool:
	if not has_active("aura"):
		return false
	var s := stats("aura")
	return pos.distance_to(position) < s["radius"] * area_mult


func stats(id: String) -> Dictionary:
	var s := _fused_base(id, Data.weapon_stats(id, weapons.get(id, 1), false))
	if not _wmods.has(id):
		_wmods[id] = _m_weapon(id)
	var m: Dictionary = _wmods[id]
	s["damage"] = float(s.get("damage", 0.0)) * m["damage"]
	if not fusion_of(id).is_empty():
		s["damage"] = float(s["damage"]) * float(m.get("fusion", 1.0))
	if s.has("cooldown"):
		s["cooldown"] = float(s["cooldown"]) * m["cooldown"]
	if s.has("interval"):
		s["interval"] = float(s["interval"]) * m["cooldown"]
	if s.has("count"):
		s["count"] = int(s["count"]) + m["count"]
	for key in ["radius", "range", "length"]:
		if s.has(key):
			s[key] = float(s[key]) * m["area"]
	if s.has("duration"):
		s["duration"] = float(s["duration"]) * float(m.get("duration", 1.0))
	if s.has("speed") and (s["speed"] is float or s["speed"] is int):
		s["speed"] = float(s["speed"]) * float(m.get("speed", 1.0))
	# ---- Модули оружия ----
	s["damage"] = float(s["damage"]) * weapon_dmg
	for key in ["cooldown", "interval", "tick"]:
		if s.has(key):
			s[key] = float(s[key]) * weapon_cd
	for key in ["radius", "range", "length", "width"]:
		if s.has(key):
			s[key] = float(s[key]) * weapon_area
	if s.has("duration"):
		s["duration"] = float(s["duration"]) * weapon_status
	# Мультиядро: +1 к количеству у любого оружия
	s["extra"] = extra_proj
	if extra_proj > 0:
		if s.has("count"):
			s["count"] = int(s["count"]) + extra_proj
		if s.has("strikes"):
			s["strikes"] = int(s["strikes"]) + extra_proj
		if s.has("beams"):
			s["beams"] = int(s["beams"]) + extra_proj
		if id == "aura":
			s["tick"] = float(s["tick"]) / (1.0 + 0.5 * extra_proj)
	# Аспекты модулей: Стремительность, Эхо (для постоянного оружия), Ударная волна
	var k_spd := aspect_k(id, "speed")
	var k_cd := aspect_k(id, "cooldown")
	var k_area := aspect_k(id, "area")
	if s.has("cooldown"):
		s["cooldown"] = float(s["cooldown"]) * (1.0 - 0.25 * k_spd)
	for key in ["interval", "tick", "hit_cd"]:
		if s.has(key):
			s[key] = float(s[key]) * (1.0 - 0.25 * k_spd) * (1.0 - 0.3 * k_cd)
	if s.has("spin"):
		s["spin"] = float(s["spin"]) * (1.0 + 0.3 * k_spd + 0.3 * k_cd)
	if s.has("speed"):
		s["speed"] = float(s["speed"]) * (1.0 + 0.4 * k_spd)
	for key in ["radius", "range", "length", "width"]:
		if s.has(key):
			s[key] = float(s[key]) * (1.0 + 0.3 * k_area)
	return s


# ================= Баффы алтарей =================

## Неуязвимость (у героя клиента — отправляется ему).
func give_invuln(t: float) -> void:
	if remote:
		Net.event("p_inv", t)
		return
	_invuln = maxf(_invuln, t)


func add_buff(kind: String, t: float) -> void:
	if remote:
		Net.event("p_buff", [kind, t])
		buffs[kind] = t
		return
	if not buffs.has(kind):
		_buff_apply(kind, true)
	buffs[kind] = t


func _buff_apply(kind: String, on: bool) -> void:
	match kind:
		"rage":
			damage_mult = damage_mult * 1.5 if on else damage_mult / 1.5
		"haste":
			# Прибавка запоминается и вычитается ровно та же — модули по ходу не сбиваются
			if on:
				_buff_d["speed"] = base_speed * 0.3
			base_speed += _buff_d.get("speed", 0.0) * (1.0 if on else -1.0)
			cooldown_mult = cooldown_mult * 0.75 if on else cooldown_mult / 0.75
		"crit":
			crit_chance += 0.25 if on else -0.25
		"magnet":
			if on:
				_buff_d["magnet"] = magnet * 3.0
				heal(40.0)
			magnet += _buff_d.get("magnet", 0.0) * (1.0 if on else -1.0)
	_wmods.clear()


func _tick_buffs(delta: float) -> void:
	if buffs.is_empty():
		return
	for k in buffs.keys():
		buffs[k] -= delta
		if buffs[k] <= 0.0:
			buffs.erase(k)
			_buff_apply(k, false)
	if randf() < 0.15:
		Fx.burst(main, position + Vector2(0, -20), [Pixel.hdr(Color(1.0, 0.6, 0.3), 1.5), Color(1.0, 0.3, 0.2, 0.0)], 1, 40.0, 0.5, 3.0, true, Vector2(0, -60))


# ================= Эволюция: слияние двух оружий 10 уровня =================

## Занятые слоты оружия: слитая пара — одно оружие.
func weapon_slots() -> int:
	return weapons.size() - fusions.size()


## Слияние, в котором участвует оружие ([основа, второе]) или пустой массив.
func fusion_of(id: String) -> Array:
	for f in fusions:
		if id in f:
			return f
	return []


func is_secondary(id: String) -> bool:
	var f := fusion_of(id)
	return not f.is_empty() and f[1] == id


## Пары оружий, которые можно слить: оба 10 уровня, ещё не слиты, слияний меньше двух.
func fusion_pairs() -> Array:
	var out: Array = []
	if fusions.size() >= Data.MAX_FUSIONS:
		return out
	var maxed: Array = []
	for id in weapons:
		if int(weapons[id]) >= Data.MAX_WEAPON_LEVEL and fusion_of(id).is_empty():
			maxed.append(id)
	for i in maxed.size():
		for j in range(i + 1, maxed.size()):
			out.append([maxed[i], maxed[j]])
	return out


func partner(id: String) -> String:
	var f := fusion_of(id)
	if f.is_empty():
		return ""
	return f[1] if f[0] == id else f[0]


## Слияние: base — чьё поведение и имя основное, other — второе оружие.
## Аспекты складываются (и освобождаются для других оружий), стихии обе,
## характеристики усредняются, атака — совмещённый залп обоих.
func fuse(base: String, other: String) -> void:
	if fusions.size() >= Data.MAX_FUSIONS or not weapons.has(base) or not weapons.has(other):
		return
	if not fusion_of(base).is_empty() or not fusion_of(other).is_empty():
		return
	fusions.append([base, other])
	var asp: Array = []
	for m in evolved.get(base, []) + evolved.get(other, []):
		if not (m in asp):
			asp.append(m)
	evolved[base] = asp.duplicate()
	evolved[other] = asp.duplicate()
	aspect_due.erase(base)
	aspect_due.erase(other)
	_aspect_cache.clear()
	_wmods.clear()
	preload("res://scripts/meta.gd").discover("f:" + base + "+" + other)
	var ca: Color = Data.STATUSES[Data.WEAPONS[base]["status"]]["color"]
	var cb: Color = Data.STATUSES[Data.WEAPONS[other]["status"]]["color"]
	Sound.play("evolve", 0.0)
	Sound.play("boom", -4.0, 0.6)
	main.shake(14.0)
	main.screen_flash(0.4)
	Fx.ring(main, position, 10.0, 360.0, Pixel.hdr(ca, 2.2), 0.6, 10.0)
	Fx.ring(main, position, 10.0, 300.0, Pixel.hdr(cb, 2.2), 0.8, 8.0)
	Fx.light_flash(main, position, ca.lerp(cb, 0.5), 4.0, 8.0, 0.8)
	Fx.text_pop(main, position + Vector2(0, -110), "СЛИЯНИЕ: " + Data.fused_name(base, other).to_upper(), Pixel.hdr(ca.lerp(cb, 0.5), 1.8), 30)
	# Взрыв слияния: обе стихии по всем врагам рядом
	main.attacker = self
	_src = base
	main.damage_area(position, 320.0 * area_mult, 60.0 * damage_mult, null, Data.WEAPONS[base]["status"])
	_src = other
	main.damage_area(position, 320.0 * area_mult, 60.0 * damage_mult, null, Data.WEAPONS[other]["status"])
	if other == "drones":
		# Дроны второго оружия улетают — дальше они появляются только в ударах основы
		for d in _drones:
			d.queue_free()
		for sh in _drone_shadows:
			sh.queue_free()
		_drones.clear()
		_drone_shadows.clear()
		_drone_t.clear()
	elif base == "drones":
		_sync_drones()


var _fus_cd := {}


## Атака второго оружия слияния из точки попадания основы: снаряды вылетают
## из места удара, а «постоянные» оружия (клинки, круг, дроны) дают вспышку там же.
func _fus_fire(other: String, at: Vector2) -> void:
	if _dead or not weapons.has(other):
		return
	var s := stats(other)
	var col: Color = Data.STATUSES[Data.WEAPONS[other]["status"]]["color"]
	var st: String = Data.WEAPONS[other]["status"]
	main.attacker = self
	_src = other
	match other:
		"blades":
			# Вихрь клинков вокруг точки удара
			for i in 4:
				Fx.slash(main, at, TAU * i / 4.0 + _anim_t, 1.2, 70.0 * area_mult, Pixel.hdr(col, 1.6))
			main.damage_area(at, 80.0 * area_mult, float(s["damage"]) * damage_mult * 1.5, null, st)
		"aura":
			Fx.ring(main, at, 10.0, 110.0 * area_mult, Pixel.hdr(col, 1.8), 0.4, 6.0)
			main.damage_area(at, 110.0 * area_mult, float(s["damage"]) * damage_mult * 3.0, null, st)
		"drones":
			# Залп дронов: лучи из воздуха по врагам вокруг точки
			for t in main.nearest_enemies_to(at, int(s.get("count", 2)), 260.0, null):
				Fx.beam(main, at + Vector2(0, -120), t.position, Pixel.hdr(col, 1.6))
				main.damage_area(t.position, 30.0, float(s["damage"]) * damage_mult, null, st)
		_:
			# Остальные: настоящая атака второго оружия, но из точки попадания
			var old := position
			position = at
			_fire_once(other, s)
			position = old
	Fx.burst(main, at + Vector2(0, -12), [Pixel.hdr(col, 2.0), Color(col, 0.0)], 6, 140.0, 0.3, 2.5)


func has_active(id: String) -> bool:
	return weapons.has(id) and not is_secondary(id)


## Грубая «мощность» оружия (урон в секунду по одной цели) — для усреднения при слиянии.
static func _power(s: Dictionary) -> float:
	var n := maxf(1.0, float(s.get("count", 1))) * maxf(1.0, float(s.get("strikes", 1))) * maxf(1.0, float(s.get("beams", 1)))
	var per := 0.5
	for k in ["cooldown", "interval", "tick"]:
		if s.has(k) and float(s[k]) > 0.0:
			per = float(s[k])
			break
	return float(s.get("damage", 1.0)) * n / maxf(per, 0.05)


## Характеристики слитого оружия: общие (количество, пробивание, область, скорость, длительность)
## складываются и делятся пополам; урон приводится к средней мощности обоих.
func _fused_base(id: String, s: Dictionary) -> Dictionary:
	var pt := partner(id)
	if pt == "":
		return s
	var o := Data.weapon_stats(pt, weapons.get(pt, 1), false)
	for k in ["count", "pierce", "strikes", "beams"]:
		if s.has(k) and o.has(k) and (s[k] is int or s[k] is float):
			s[k] = int(ceil((float(s[k]) + float(o[k])) / 2.0))
	for k in ["radius", "range", "length", "width", "speed", "duration"]:
		if s.has(k) and o.has(k) and (s[k] is float or s[k] is int):
			s[k] = (float(s[k]) + float(o[k])) / 2.0
	var ps := _power(s)
	if ps > 0.0:
		s["damage"] = float(s.get("damage", 0.0)) * ((ps + _power(o)) / 2.0) / ps
	# Второе оружие слияния срабатывает из ударов основы
	if is_secondary(id):
		s["damage"] = float(s["damage"]) * 0.8
	return s




## Сила аспекта модуля для оружия: 1.0 у оружия, эволюционировавшего с этим модулем, иначе 0.
## У слитой пары аспекты общие.
func aspect_k(weapon: String, module: String) -> float:
	if weapon == "" or not Data.WEAPONS.has(weapon):
		return 0.0
	var key := weapon + ":" + module
	if _aspect_cache.has(key):
		return _aspect_cache[key]
	var k := 0.0
	if module in evolved.get(weapon, []) or module in evolved.get(partner(weapon), []):
		k = 1.0
	_aspect_cache[key] = k
	return k


## Цвет эволюции: оружие окрашивается в цвет своего модуля, слитое — ещё и в стихию напарника.
func evo_tint(weapon: String, base: Color) -> Color:
	var pt := partner(weapon)
	if pt != "":
		base = base.lerp(Data.STATUSES[Data.WEAPONS[pt]["status"]]["color"], 0.45)
	var list: Array = evolved.get(weapon, [])
	if not list.is_empty() and Data.ASPECTS.has(list[-1]):
		return base.lerp(Data.ASPECTS[list[-1]]["color"], 0.5)
	return base


func aspect_damage(weapon: String) -> float:
	return 1.0 + 0.45 * aspect_k(weapon, "damage")


func aspect_crit(weapon: String) -> float:
	return 0.25 * aspect_k(weapon, "crit")


## Попадание оружием: срабатывают аспекты всех модулей.
func on_weapon_hit(src: String, e: Node2D, amount: float, crit: bool) -> void:
	if _aspect_guard or src == "" or not Data.WEAPONS.has(src):
		return
	# Слияние: попадание основы запускает атаку второго оружия прямо из точки удара
	var fu := fusion_of(src)
	if not fu.is_empty() and fu[0] == src and float(_fus_cd.get(src, 0.0)) <= 0.0 and e != null:
		var other: String = fu[1]
		var os := stats(other)
		_fus_cd[src] = maxf(0.35, float(os.get("cooldown", os.get("interval", os.get("tick", 1.0))))) * 0.8
		var at: Vector2 = e.position
		_fus_fire.call_deferred(other, at)
	_aspect_guard = true
	var k: float
	k = aspect_k(src, "hp")
	if k > 0.0 and _leech < 4.0:
		var h := minf(amount * 0.05 * k, 4.0 - _leech)
		_leech += h
		hp = minf(max_hp, hp + h)
	k = aspect_k(src, "armor")
	if k > 0.0:
		_bastion = minf(6.0, _bastion + 0.2 * k)
	# Эволюция: удар несёт и стихию слитого напарника
	var pt := partner(src)
	if pt != "" and not e.dead and randf() < 0.5:
		e.apply_status(Data.WEAPONS[pt]["status"])
	if not e.dead:
		k = aspect_k(src, "vamp")
		if k > 0.0 and randf() < 0.5 * k:
			e.apply_status("bleed")
		k = aspect_k(src, "duration")
		if k > 0.0 and randf() < 0.25 * k:
			var sts := ["burn", "shock", "chill", "bleed", "poison"]
			e.apply_status(sts[randi() % sts.size()])
	k = aspect_k(src, "magnet")
	if k > 0.0 and randf() < 0.4 * k:
		var pulled := 0
		for n in main.nearest_enemies_to(e.position, 4, 150.0 * area_mult, e):
			if not n.is_boss:
				n.position = n.position.lerp(e.position, 0.45)
				pulled += 1
		if pulled > 0 and k >= 1.0:
			Fx.ring(main, e.position, 120.0, 10.0, Color(0.7, 0.5, 1.0, 0.5), 0.25, 2.0)
	k = aspect_k(src, "area")
	if k > 0.0 and randf() < 0.3 * k:
		var r := 60.0 * area_mult
		Fx.ring(main, e.position, 6.0, r, Color(1.0, 0.75, 0.3, 0.5), 0.25, 2.5)
		main.damage_area(e.position, r, amount * 0.35, e)
	k = aspect_k(src, "crit")
	if crit and k > 0.0 and randf() < k:
		Fx.explosion(main, e.position + Vector2(0, -15), Color(1.0, 0.3, 0.35), Color(1.0, 0.8, 0.4), 55.0 * area_mult)
		main.damage_area(e.position, 55.0 * area_mult, amount * 0.45, e)
	k = aspect_k(src, "multi")
	if k > 0.0 and randf() < 0.4 * k:
		var others: Array = main.nearest_enemies_to(e.position, 1, 230.0, e)
		if not others.is_empty():
			var o: Node2D = others[0]
			main.beam3d(PackedVector3Array([main.to3d(e.position, 0.5), main.to3d(o.position, 0.5)]), Color(0.9, 0.5, 1.0), 0.025, 0.15, 0.05)
			o.hit(amount * 0.5, e.position, 60.0)
	_aspect_guard = false


## Убийство оружием: Цветение, Жажда, Фортуна.
func on_weapon_kill(src: String, e: Node2D) -> void:
	if src == "" or not Data.WEAPONS.has(src) or _aspect_guard:
		return
	_aspect_guard = true
	var k: float
	k = aspect_k(src, "regen")
	if k > 0.0:
		hp = minf(max_hp, hp + 0.8 * k)
		if randf() < k:
			Fx.burst(main, e.position + Vector2(0, -10), [Pixel.hdr(Color(0.5, 1.0, 0.6), 1.6), Color(0.3, 1.0, 0.5, 0.0)], 6, 120.0, 0.5, 3.0, true, Vector2(0, -40))
			main.damage_area(e.position, 70.0 * area_mult, 12.0 * damage_mult * k, e, "chill")
	k = aspect_k(src, "vamp")
	if k > 0.0:
		hp = minf(max_hp, hp + 1.0 * k)
	k = aspect_k(src, "luck")
	if k > 0.0:
		if randf() < 0.6 * k:
			main.drop_gem_at(e.position + Vector2(randf_range(-20, 20), randf_range(-15, 15)), 1)
		if randf() < 0.006 * k:
			main.drop_chest(e.position)
	_aspect_guard = false


## Источник урона — для бонуса «Стихийный резонанс» из Арсенала.
func set_source(id: String) -> void:
	_src = id


var laststand := false


## Бонусы дерева оружия для конкретного источника урона ({} — не оружие).
func wmods_for(src: String) -> Dictionary:
	if src == "" or not Data.WEAPONS.has(src):
		return {}
	if not _wmods.has(src):
		_wmods[src] = _m_weapon(src)
	return _wmods[src]


func hit_mult(target: Node) -> float:
	if _src != "" and not target.statuses.is_empty():
		if not _wmods.has(_src):
			_wmods[_src] = _m_weapon(_src)
		return _wmods[_src]["status"]
	return 1.0


func plvl(id: String) -> int:
	return passives.get(id, 0)


func infuse_for(status: String) -> String:
	if infuse_t > 0.0 and infuse_status != status:
		return infuse_status
	return ""


## Импульс способности: оружие перезаряжается, поля подпитываются,
## все удары 4 секунды несут стихию героя.
func _pulse() -> void:
	infuse_status = Data.ABILITY_ELEMENT.get(char_id, "shock")
	infuse_t = 4.0
	var k := 0.35
	for id in _cooldowns:
		_cooldowns[id] = _cooldowns[id] * (1.0 - minf(k, 0.85))
	for i in _drone_t.size():
		_drone_t[i] = 0.0
	main.energize(position, 900.0, "pulse", infuse_status)
	var c: Color = Data.STATUSES[infuse_status]["color"]
	Fx.ring(main, position, 20.0, 260.0, Pixel.hdr(c, 1.6), 0.4, 4.0)
	main.combo_pop(position + Vector2(0, -70), "ИМПУЛЬС: " + Data.STATUSES[infuse_status]["name"].to_upper(), c)


## Катализатор оружия: есть ли на цели «чужой» статус, от которого оно усиливается.
func catalyzed(weapon: String, e: Node) -> bool:
	if not Data.CATALYSTS.has(weapon) or e == null or e.dead:
		return false
	if e.statuses.has(Data.CATALYSTS[weapon][0]):
		return true
	# Слитое оружие срабатывает и от катализатора напарника
	var pt := partner(weapon)
	return pt != "" and Data.CATALYSTS.has(pt) and e.statuses.has(Data.CATALYSTS[pt][0])


func combo(weapon: String, pos: Vector2) -> void:
	var c: Array = Data.CATALYSTS[weapon]
	main.combo_pop(pos + Vector2(0, -50), c[1], Data.STATUSES[c[0]]["color"])


# ================= Активные способности =================

func _use_ability() -> void:
	_cast_t = CAST_T
	ability_left = ability_cd * cooldown_mult
	Sound.play("ability", -4.0, 1.0 + randf_range(-0.05, 0.05))
	main.screen_flash(0.12)
	_pulse()
	# Эволюция: способность сразу даёт залп обоих слитых оружий
	for fpair in fusions:
		for fid in fpair:
			if fid in ["blades", "aura", "drones"]:
				continue
			_src = fid
			_fire_once(fid, stats(fid))
	match char_id:
		"vega":
			_dash_t = 0.18
			_dash_dir = facing
			_dash_hit.clear()
			_invuln = maxf(_invuln, 0.4)
		"rin":
			_spin_t = 0.6
			_spin_hits = 0
		"bram":
			_shield_t = 3.0
			_invuln = maxf(_invuln, 3.0)
			Fx.ring(main, position, 10.0, 220.0 * area_mult, Pixel.hdr(Color(0.5, 0.95, 1.0), 2.0), 0.45, 8.0)
			Fx.burst(main, position + Vector2(0, -20), [Pixel.hdr(Color(0.6, 1.0, 1.0), 2.0), Color(1.0, 0.7, 0.3, 0.0)], 30, 340.0, 0.7, 4.0)
			main.shake(6.0)
			for e in main.get_enemies():
				if e.can_be_hit() and e.position.distance_to(position) < 220.0 * area_mult:
					e.hit(15.0 * damage_mult, position, 420.0, "chill")
		"skyla":
			for i in 16:
				var p := position + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(40.0, 280.0)
				_later(i * 0.04, func():
					var g: Vector3 = main.to3d(p, 0.0)
					main.beam3d(PackedVector3Array([g + Vector3(0.4, 4.0, -0.3), g]), Color(0.5, 1.0, 0.8), 0.03, 0.18)
					Fx.sparks(main, p, Color(0.5, 1.0, 0.8), 4)
					set_source("railbow")
					main.attacker = self
					main.damage_area(p, 45.0, 26.0 * damage_mult * power, null, "bleed"))
		"orm":
			_shield_t = 2.0
			_invuln = maxf(_invuln, 2.0)
			heal(30.0 * power)
			Fx.ring(main, position, 10.0, 160.0, Pixel.hdr(Color(1.0, 0.85, 0.4), 1.5), 0.5, 6.0)
		"mora":
			_spawn_spirits(10, 20.0 * damage_mult * power, 40.0)
		"zephyr":
			var z = preload("res://scripts/zone.gd").new()
			z.main = main
			z.position = position + facing * 40.0
			z.velocity = facing * 150.0
			z.radius = 90.0 * area_mult
			z.damage = 9.0 * damage_mult * power
			z.tick = 0.3
			z.duration = 3.0
			z.status = "shock"
			z.color = Color(0.5, 0.85, 1.0)
			z.pull = 140.0
			z.tornado = true
			z.source = "ball"
			main.zones_node.add_child(z)
		"iris":
			heal(40.0 * power)
			var z = preload("res://scripts/zone.gd").new()
			z.main = main
			z.position = position
			z.radius = 200.0 * area_mult
			z.damage = 3.0 * damage_mult * power
			z.duration = 3.0
			z.status = "chill"
			z.color = Color(0.5, 1.0, 0.7)
			main.zones_node.add_child(z)
		"lyra":
			# Три волны лезвий, каждая шире предыдущей
			for w in 3:
				_later(w * 0.18, func():
					var r := (120.0 + w * 70.0) * area_mult
					Fx.ring(main, position, 10.0, r, Pixel.hdr(Color(0.35, 1.0, 0.95), 2.0), 0.35, 5.0)
					Fx.burst(main, position, [Pixel.hdr(Color(0.6, 1.0, 1.0), 2.0), Color(0.3, 0.9, 1.0, 0.0)], 14, r * 1.6, 0.4, 3.0)
					set_source("blades")
					main.attacker = self
					main.damage_area(position, r, 16.0 * damage_mult * power, null, "bleed"))
		"sol":
			heal(20.0 * power)
			Fx.ring(main, position, 10.0, 240.0 * area_mult, Pixel.hdr(Color(1.0, 0.8, 0.35), 2.2), 0.5, 8.0)
			Fx.burst(main, position + Vector2(0, -20), [Pixel.hdr(Color(1.0, 0.9, 0.5), 2.2), Color(1.0, 0.4, 0.1, 0.0)], 30, 360.0, 0.6, 4.0)
			main.shake(5.0)
			for e in main.get_enemies():
				if e.can_be_hit() and e.position.distance_to(position) < 240.0 * area_mult:
					e.hit(22.0 * damage_mult * power, position, 380.0, "burn")
		"volt":
			var ts: Array = main.nearest_enemies_to(position, 8, 700.0, null)
			for i in ts.size():
				var e: Node2D = ts[i]
				_later(i * 0.06, func():
					if not is_instance_valid(e):
						return
					var g: Vector3 = main.to3d(e.position, 0.0)
					main.beam3d(PackedVector3Array([g + Vector3(randf_range(-0.4, 0.4), 4.5, -0.3), g + Vector3(0.2, 2.0, 0), g]), Color(0.6, 0.8, 1.0), 0.04, 0.2, 0.15)
					Fx.sparks(main, e.position, Color(0.6, 0.85, 1.0), 6)
					if e.can_be_hit():
						set_source("lightning")
						main.attacker = self
						e.hit(30.0 * damage_mult * power, position, 0.0, "shock"))
		"kai":
			_invuln = maxf(_invuln, 0.8)
			Fx.afterimage(main, position, _body.texture, _body.offset, _body.flip_h, Color(1.0, 0.3, 0.3), float(_frames.get("k", 1.0)))
			_shurikens(12, 18.0 * damage_mult * power, 520.0, false, true)
		"kira":
			main.glitch_flash()
			var n := 0
			for e in main.get_enemies():
				if e.can_be_hit() and e.position.distance_to(position) < 720.0:
					e.hit(20.0 * damage_mult, position, 0.0, "chill")
					n += 1
					if n % 4 == 0:
						Fx.burst(main, e.position + Vector2(0, -20), [Pixel.hdr(Color(0.4, 1.0, 0.5), 2.0), Color(1.0, 0.3, 0.8, 0.0)], 4, 80.0, 0.4, 4.0)


func _update_ability(delta: float) -> void:
	if _dash_t > 0.0:
		_dash_t -= delta
		var prev := position
		position += _dash_dir * 1400.0 * delta
		Fx.afterimage(main, prev, _body.texture, _body.offset, _body.flip_h, Color(0.3, 0.9, 1.0), float(_frames.get("k", 1.0)))
		for e in main.get_enemies():
			if not e.can_be_hit() or _dash_hit.has(e.get_instance_id()):
				continue
			var closest := Geometry2D.get_closest_point_to_segment(e.position, prev, position)
			if closest.distance_to(e.position) < 40.0 + e.radius:
				_dash_hit[e.get_instance_id()] = true
				e.hit(22.0 * damage_mult, position, 250.0, "shock")
				Fx.sparks(main, e.position + Vector2(0, -15), Color(0.4, 0.8, 1.0), 6)
	if _spin_t > 0.0:
		_spin_t -= delta
		var due := 3 - int(ceil(_spin_t / 0.2))
		while _spin_hits < due and _spin_hits < 3:
			_spin_hits += 1
			var r := 150.0 * area_mult
			Fx.slash(main, position, randf() * TAU, TAU * 0.9, r, Color(1.0, 0.3, 0.6), self)
			Sound.play("slash", -2.0, 1.2 + _spin_hits * 0.1)
			main.shake(3.0)
			for e in main.get_enemies():
				if e.can_be_hit() and e.position.distance_to(position) < r + e.radius:
					e.hit(26.0 * damage_mult, position, 200.0, "bleed")


# ================= Анимация =================

func _animate(delta: float) -> void:
	_anim_t += delta
	var f: int
	_attack_t = maxf(0.0, _attack_t - delta)
	_cast_t = maxf(0.0, _cast_t - delta)
	_hurt_t = maxf(0.0, _hurt_t - delta)
	var rich: bool = _frames["base"].size() >= Pixel.HERO_FRAMES
	if rich and _hurt_t > 0.0:
		f = Pixel.hero_frame_k("hurt", 1.0 - _hurt_t / 0.3)
	elif rich and _cast_t > 0.0:
		f = Pixel.hero_frame_k("cast", 1.0 - _cast_t / CAST_T)
	elif rich and _attack_t > 0.0:
		f = Pixel.hero_frame_k("attack", 1.0 - _attack_t / ATTACK_T)
	elif rich and _dash_t > 0.0:
		f = Pixel.hero_frame(_frames, "dash", _anim_t)
	elif moving:
		f = Pixel.hero_frame(_frames, "run", _anim_t)
		_dust_t -= delta
		if _dust_t <= 0.0:
			_dust_t = 0.3
			Fx.burst(main, position + Vector2(0, 8), [Color(0.45, 0.42, 0.55, 0.35), Color(0.3, 0.25, 0.4, 0.0)],
				2, 30.0, 0.35, 2.0, false, Vector2(0, -10), -facing, 40.0)
	else:
		f = Pixel.hero_frame(_frames, "idle", _anim_t)
	_body.texture = _frames["base"][f]
	_emit.texture = _frames["flash"][f] if _flash > 0.0 else _frames["emit"][f]
	_emit.modulate = Pixel.hdr(Color(1.0, 0.4, 0.45), 2.5) if _flash > 0.0 else Pixel.hdr(Color.WHITE, 1.8)
	if absf(facing.x) > 0.1:
		_body.flip_h = facing.x < 0.0
		_emit.flip_h = _body.flip_h
	# Стоит без дела — время от времени оглядывается по сторонам
	_idle_t = (_idle_t + delta) if (not moving and _attack_t <= 0.0 and _cast_t <= 0.0 and _hurt_t <= 0.0) else 0.0
	if _idle_t > 2.5 and fmod(_idle_t - 2.5, 5.0) < 0.9:
		_body.flip_h = not _body.flip_h
		_emit.flip_h = _body.flip_h
	var vis := _shield_t > 0.0 or not (_invuln > 0.0 and int(_invuln * 20.0) % 2 == 0)
	_body.visible = vis
	_emit.visible = vis
	# Живость: дыхание в покое, пружинящий шаг на бегу, рывок при ударе и касте
	var sq := 0.0
	if _hurt_t > 0.0:
		sq = -0.1 * (_hurt_t / 0.3)
	elif _attack_t > 0.0 or _cast_t > 0.0:
		sq = 0.06 * sin(PI * (1.0 - maxf(_attack_t / ATTACK_T, _cast_t / CAST_T)))
	elif moving:
		sq = 0.045 * absf(sin(_anim_t * 9.5)) - 0.02
	else:
		sq = 0.018 * sin(_anim_t * 2.4)
	var bsc := Vector2(Pixel.PX * (1.0 - sq * 0.6), Pixel.PX * Pixel.STAND * (1.0 + sq)) * float(_frames.get("k", 1.0))
	_body.scale = bsc
	_emit.scale = bsc
	var pulse := 0.5 + 0.5 * sin(_anim_t * 3.0)
	_light.energy = 1.15 + 0.15 * pulse
	_update_gear(vis)
	_halo.modulate.a = 0.2 + 0.15 * pulse

	if not has_active("aura") and _aura_ring:
		_aura_ring.visible = false
		_aura_glow.visible = false
		if _aura_embers:
			_aura_embers.visible = false
	if has_active("aura"):
		var s := stats("aura")
		var r: float = s["radius"] * area_mult
		var col := Color(1.0, 0.5, 0.15) if not evolved.has("aura") else Color(1.0, 0.3, 0.6)
		_aura_ring.visible = true
		_aura_glow.visible = true
		_aura_ring.rotation += delta * 0.8
		_aura_ring.scale = Vector2.ONE * r / 22.0
		_aura_ring.modulate = Color(col, 0.55 + 0.2 * pulse)
		_aura_glow.scale = Vector2.ONE * r / 64.0 * 1.15
		_aura_glow.modulate = Color(col, 0.1 + 0.05 * pulse)
		if _aura_embers:
			((_aura_embers as GPUParticles2D).process_material as ParticleProcessMaterial).emission_sphere_radius = r * 0.9

	# Голо-клинки стоят вертикально и кружат вокруг героя
	_sync_swords()

	# Дроны кружат вокруг героя
	var dfr := Pixel.frames("drone")
	for i in _drones.size():
		var a := _anim_t * 1.4 + TAU * i / _drones.size()
		# Дрон летает по кругу вокруг героя на высоте головы, покачиваясь
		var ground := Vector2(cos(a) * 75.0, sin(a) * 50.0)
		var hover := (95.0 + sin(_anim_t * 4.0 + i) * 6.0) * Pixel.STAND
		_drones[i].position = ground + Vector2(0, -hover)
		var df := int(_anim_t * 16.0 + i) % 2
		_drones[i].texture = dfr["base"][df]
		var glow: Sprite2D = _drones[i].get_child(0)
		glow.texture = dfr["emit"][df]
		_drones[i].flip_h = sin(a) < 0.0
		glow.flip_h = _drones[i].flip_h
		if i < _drone_shadows.size():
			_drone_shadows[i].position = ground


func _draw_blades(canvas: Node2D) -> void:
	if not has_active("blades"):
		return
	var s := stats("blades")
	var count: int = s["count"]
	var r := _blade_radius(s)
	var charged := _blades_charged > 0.0
	var trail_col := Color(0.4, 0.75, 1.0) if charged else Color(1.0, 0.3, 0.8)
	for i in count:
		var a := _orbit_angle + TAU * i / count
		for j in 4:
			var len := 0.9 - j * 0.2
			canvas.draw_arc(Vector2.ZERO, r, a - len, a, 10, Color(trail_col, 0.06 + j * 0.05), 10.0 - j * 2.0)
		var pos := Vector2(cos(a), sin(a)) * r
		if charged and randf() < 0.1:
			Fx.sparks(main, position + pos, Color(0.5, 0.8, 1.0), 2)


func _draw_overlay(canvas: Node2D) -> void:
	for fi in fusions.size():
		# Знак слияния: два кольца стихий вращаются навстречу друг другу
		var fpair: Array = fusions[fi]
		var ca: Color = Data.STATUSES[Data.WEAPONS[fpair[0]]["status"]]["color"]
		var cb: Color = Data.STATUSES[Data.WEAPONS[fpair[1]]["status"]]["color"]
		canvas.draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.5))
		for k in 3:
			var a0 := _anim_t * 2.2 + TAU * k / 3.0
			canvas.draw_arc(Vector2.ZERO, 34.0 + fi * 12.0, a0, a0 + 1.2, 12, Pixel.hdr(ca, 1.6), 3.0)
			var b0 := -_anim_t * 2.2 + TAU * k / 3.0 + 0.5
			canvas.draw_arc(Vector2.ZERO, 40.0 + fi * 12.0, b0, b0 + 1.2, 12, Pixel.hdr(cb, 1.6), 3.0)
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _shield_t > 0.0:
		# Гексагональный рунный щит
		var a := minf(1.0, _shield_t) * (0.7 + 0.3 * sin(_anim_t * 10.0))
		var r := 52.0
		var c := Vector2(0, -30)
		var pts := PackedVector2Array()
		for i in 7:
			pts.append(c + Vector2.RIGHT.rotated(TAU * i / 6.0 + _anim_t) * r)
		canvas.draw_colored_polygon(pts.slice(0, 6), Color(0.4, 0.8, 1.0, 0.12 * a))
		canvas.draw_polyline(pts, Color(1.2, 0.9, 0.4, a), 3.0)
		for i in 6:
			canvas.draw_line(c, pts[i], Color(0.5, 0.9, 1.2, 0.35 * a), 1.5)
	if _spin_t > 0.0:
		var r := 150.0 * area_mult
		canvas.draw_arc(Vector2(0, -25), r, _anim_t * 25.0, _anim_t * 25.0 + PI * 1.2, 32, Color(1.6, 0.4, 0.9, 0.6), 6.0)


func _sync_swords() -> void:
	var count: int = stats("blades")["count"] if has_active("blades") else 0
	while _swords.size() < count:
		var sw := Sprite3D.new()
		sw.texture = Pixel.frames("blade")["emit"][0]
		sw.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sw.shaded = false
		sw.double_sided = true
		sw.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sw.pixel_size = 0.03
		main._bill_root.add_child(sw)
		_swords.append(sw)
	if count == 0:
		return
	var s := stats("blades")
	var r := _blade_radius(s)
	var charged := _blades_charged > 0.0
	for i in _swords.size():
		var sw: Sprite3D = _swords[i]
		sw.visible = not _dead and i < count
		var a := _orbit_angle + TAU * i / count
		var out := Vector3(cos(a), 0.0, sin(a))
		var tangent := Vector3(-sin(a), 0.0, cos(a))
		# Клинок летит остриём вперёд по кругу, плоскостью к небу, с лёгким наклоном наружу
		var normal := (Vector3.UP * 0.85 + out * 0.5).normalized()
		var x_axis := tangent
		var y_axis := normal.cross(x_axis).normalized()
		sw.transform = Transform3D(Basis(x_axis, y_axis, normal).scaled(Vector3.ONE * area_mult),
			main.to3d(position + Vector2(cos(a), sin(a)) * r, 0.55 + sin(_anim_t * 5.0 + i) * 0.06))
		sw.modulate = Pixel.hdr(Color(0.6, 0.85, 1.0), 1.6) if charged else Pixel.hdr(Color.WHITE, 1.5)


func _exit_tree() -> void:
	if is_instance_valid(_gear):
		_gear.queue_free()
	for sw in _swords:
		if is_instance_valid(sw):
			sw.queue_free()


func _blade_radius(s: Dictionary) -> float:
	var r: float = s["radius"] * area_mult
	if s["pulse"]:
		r *= 1.0 + 0.3 * sin(_anim_t * 2.5)
	return r


# ================= Урон и опыт =================

func _check_contact() -> void:
	# Касания врагов у сетевого клиента считает хост (там враги настоящие)
	if _invuln > 0.0 or (main.net_mode == "client" and not remote):
		return
	for e in main.get_enemies():
		if not e.can_hurt():
			continue
		var r: float = radius + e.radius - 2.0
		if position.distance_squared_to(e.position) < r * r:
			take_damage(e.damage)
			return


func take_damage(amount: float) -> void:
	if remote:
		# Хост: урон по герою клиента — отправляем клиенту, броня и уклонение считаются у него
		if _invuln <= 0.0 and not _dead and not main.game_over:
			Net.event("p_dmg", amount)
			_invuln = 0.45
		return
	if _invuln > 0.0 or _dead or main.game_over:
		return
	if dodge > 0.0 and randf() < dodge:
		_invuln = 0.3
		Fx.text_pop(main, position + Vector2(0, -20), "уклон", Color(1.0, 0.6, 0.6), 16)
		return
	amount = maxf(1.0, amount * dmg_taken_k - armor - floorf(_bastion))
	hp -= amount
	_invuln = 0.6
	_flash = 0.15
	_hurt_t = 0.3
	main.shake(7.0)
	main.hurt_flash_for(self)
	Sound.play("hurt", -2.0, 1.0, 0.1)
	Fx.sparks(main, position + Vector2(0, -25), Color(1.0, 0.25, 0.35), 10)
	Fx.number(main, position + Vector2(0, -30), amount, Color(1.0, 0.35, 0.4), 18)
	if hp <= 0.0:
		hp = 0.0
		if main.coop:
			_go_down()
			return
		_dead = true
		_death_t = 0.0
		for n in [_blades, _aura_ring, _aura_glow, _overlay]:
			n.visible = false
		for d in _drones:
			d.visible = false
		main.on_player_died()


func heal(amount: float, show := true) -> void:
	if remote:
		_heal_acc += amount   # копим и отправляем пачкой, чтобы не засорять сеть
		return
	amount *= heal_mult
	hp = minf(max_hp, hp + amount)
	if show:
		Fx.number(main, position + Vector2(0, -30), amount, Color(0.4, 1.0, 0.5), 16)
		Fx.burst(main, position + Vector2(0, -20), [Pixel.hdr(Color(0.4, 1.0, 0.5), 2.0), Color(0.3, 1.0, 0.4, 0.0)],
			14, 120.0, 0.7, 3.0, true, Vector2(0, -80))


func add_xp(amount: float) -> void:
	xp += amount * xp_mult
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = int(xp_to_next * 1.18) + 4
		main.queue_level_up(self)


func add_weapon(id: String) -> void:
	if not weapons.has(id) and weapon_slots() >= Data.MAX_WEAPONS:
		return
	weapons[id] = mini(weapons.get(id, 0) + 1, Data.MAX_WEAPON_LEVEL)
	preload("res://scripts/meta.gd").discover("w:" + id)
	# Аспект — один раз, на 6 уровне: выбор из модулей оружия, которые сейчас есть.
	# Нет подходящего модуля — аспект пропущен насовсем.
	if weapons[id] == Data.ASPECT_LEVEL and evolved.get(id, []).is_empty() and fusion_of(id).is_empty() and not (id in aspect_due) and has_aspect_module(id):
		aspect_due.append(id)
	if id == "aura" and _aura_embers == null:
		var ae := CPUParticles2D.new()
		ae.amount = 30
		ae.lifetime = 1.2
		ae.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		ae.emission_sphere_radius = 60.0
		ae.direction = Vector2.UP
		ae.spread = 20.0
		ae.gravity = Vector2(0, -40)
		ae.initial_velocity_min = 10.0
		ae.initial_velocity_max = 40.0
		ae.scale_amount_min = 2.0
		ae.scale_amount_max = 4.0
		ae.color_ramp = Fx._ramp([Color(1.0, 0.6, 0.2, 0.0), Color(1.0, 0.55, 0.15, 0.8), Color(1.0, 0.2, 0.4, 0.0)])
		ae.material = Pixel.mat_add()
		ae.local_coords = false
		_aura_embers = Fx.gpu2d(ae)   # считает видеокарта (свой материал — радиус меняется)
		add_child(_aura_embers)
	if id == "drones":
		_sync_drones()


func evolve(id: String, module := "") -> void:
	if not evolved.has(id):
		evolved[id] = []
	if module != "" and not (module in evolved[id]):
		evolved[id].append(module)
		preload("res://scripts/meta.gd").discover("a:" + module)
	aspect_due.erase(id)
	_aspect_cache.clear()
	if id == "drones":
		_sync_drones()
	Fx.ring(main, position, 10.0, 300.0, Pixel.hdr(Color(1.0, 0.85, 0.3), 2.5), 0.8, 8.0)
	Fx.burst(main, position + Vector2(0, -30), [Pixel.hdr(Color.WHITE, 3.0), Pixel.hdr(Color(1.0, 0.8, 0.3), 2.0), Color(1.0, 0.3, 0.8, 0.0)], 60, 500.0, 1.2, 5.0)
	Fx.light_flash(main, position, Color(1.0, 0.85, 0.4), 3.0, 8.0, 1.0)


func _sync_drones() -> void:
	if is_secondary("drones"):
		return
	var count: int = stats("drones")["count"]
	while _drones.size() < count:
		var d := Sprite2D.new()
		d.texture = Pixel.frames("drone")["emit"][0]
		d.material = Pixel.mat_unshaded()
		d.modulate = Pixel.hdr(Color.WHITE, 1.8)
		d.scale = Vector2(Pixel.PX, Pixel.PX * Pixel.STAND) * 0.8
		add_child(d)
		main.mirror(d, self, false)
		var glow := Sprite2D.new()
		glow.texture = Pixel.frames("drone")["emit"][0]
		glow.material = Pixel.mat_unshaded()
		glow.modulate = Pixel.hdr(Color.WHITE, 1.4)
		d.add_child(glow)
		main.mirror(glow, self, true)
		var sh := Sprite2D.new()
		sh.texture = Pixel.shadow()
		sh.scale = Vector2(1.6, 1.2)
		sh.modulate = Color(1, 1, 1, 0.6)
		sh.z_index = -5
		add_child(sh)
		_drone_shadows.append(sh)
		_drones.append(d)
		_drone_t.append(randf())


## Сколько модулей данного вида (weapon / hero) уже установлено.
func module_count(kind: String) -> int:
	var n := 0
	for m in passives:
		if Data.PASSIVES[m]["kind"] == kind:
			n += 1
	return n


## Аспекты, уже занятые другим (не слитым) оружием: один аспект — одно оружие.
## Слитые оружия освобождают свои аспекты для остальных.
func taken_aspects(except := "") -> Array:
	var out: Array = []
	for w in evolved:
		if w == except or not weapons.has(w) or not fusion_of(w).is_empty():
			continue
		for m in evolved[w]:
			out.append(m)
	return out


## Аспекты на выбор для оружия: модули оружия игрока, не занятые другими оружиями (до трёх).
func aspect_options(id: String) -> Array:
	var taken := taken_aspects(id)
	var out: Array = []
	for m in passives:
		if Data.PASSIVES[m]["kind"] == "weapon" and not (m in taken) and Data.ASPECTS.has(m):
			out.append(m)
	out.sort_custom(func(a, b): return passives[a] > passives[b])
	return out.slice(0, 3)


## Есть ли модуль оружия, который может дать аспект этому оружию.
func has_aspect_module(id: String) -> bool:
	return not aspect_options(id).is_empty()


func add_passive(id: String) -> void:
	if passives.get(id, 0) >= Data.MAX_PASSIVE_LEVEL:
		return
	if not passives.has(id) and module_count(Data.PASSIVES[id]["kind"]) >= Data.module_cap(Data.PASSIVES[id]["kind"]):
		return
	if _speed0 <= 0.0:
		_speed0 = base_speed
		_magnet0 = magnet
	passives[id] = passives.get(id, 0) + 1
	preload("res://scripts/meta.gd").discover("m:" + id)
	_aspect_cache.clear()
	var k: float = _m_boost(id)
	match id:
		"hp":
			max_hp += 20.0 * k
			hp += 20.0 * k
		# ---- Модули героя ----
		"speed":
			base_speed += _speed0 * 0.10 * k    # +10% от исходной скорости за уровень
		"magnet":
			magnet += _magnet0 * 0.35 * k       # +35% от исходного радиуса за уровень
		"regen":
			regen += 0.5 * k
		"armor":
			armor += 1.0 * k
		# ---- Модули оружия ----
		"damage":
			weapon_dmg += 0.12 * k
		"cooldown":
			weapon_cd *= 1.0 - 0.08 * k
		"area":
			weapon_area += 0.12 * k
		"crit":
			weapon_crit += 0.08 * k
		"multi":
			extra_proj += 1
			if weapons.has("drones"):
				_sync_drones()
		"duration":
			weapon_status += 0.2 * k
		"vamp":
			kill_heal += 0.4 * k
		"luck":
			xp_mult += 0.08 * k
			chest_bonus += 0.08 * k


# ================= Оружие =================

func _update_weapons(delta: float) -> void:
	for k in _fus_cd.keys():
		_fus_cd[k] -= delta
	for id in weapons:
		# Слияние: второе оружие само не атакует — его атака рождается из ударов основы
		if is_secondary(id):
			continue
		var s := stats(id)
		_src = id
		match id:
			"blades":
				_update_blades(delta, s)
			"aura":
				_update_aura(delta, s)
			"drones":
				_update_drones(delta, s)
			_:
				if _tick_cooldown(id, delta, s["cooldown"]):
					_fire_once(id, s)
					# Аспект «Эхо»: залп может повториться
					var ke := aspect_k(id, "cooldown")
					if ke > 0.0 and randf() < 0.35 * ke:
						var wid: String = id
						_later(0.22, func():
							if not _dead and weapons.has(wid):
								_src = wid
								_fire_once(wid, stats(wid)))


## Анимация атаки: замах — удар — доводка — возврат.
const ATTACK_T := 0.28
const CAST_T := 0.36
var _attack_t := 0.0
var _cast_t := 0.0
var _hurt_t := 0.0
var _death_t := -1.0


func _fire_once(id: String, s: Dictionary) -> void:
	if _attack_t <= 0.0:
		_attack_t = ATTACK_T
	main.attacker = self
	_src = id
	match id:
		"bolt":
			_fire_bolts(s)
		"lightning":
			_cast_lightning(s)
		"katana":
			_katana(s)
		"quake":
			_quake(s, 1.0)
			if s["double"]:
				_later(0.35, func(): _quake(s, 1.5))
			# Мультиядро: дополнительные волны молота
			for i in int(s.get("extra", 0)):
				_later(0.3 * (i + 1) + (0.35 if s["double"] else 0.0), func(): _quake(s, 1.25 + 0.2 * i))
		"railbow":
			_fire_arrows(s)
		"sunbeam":
			_sunbeam(s)
		"spirits":
			_spawn_spirits(s["count"], s["damage"] * damage_mult, s["explode"])
		"ball":
			_ball(s)
		"flask":
			_flasks(s)
		"shuriken":
			_shurikens(s["count"], s["damage"] * damage_mult, s["speed"], s["spiral"])


func _tick_cooldown(id: String, delta: float, cooldown: float) -> bool:
	var t: float = _cooldowns.get(id, 0.0) - delta
	if t <= 0.0:
		_cooldowns[id] = cooldown * cooldown_mult
		return true
	_cooldowns[id] = t
	return false


func _fire_bolts(s: Dictionary) -> void:
	var targets: Array = main.nearest_enemies_to(position, s["count"], 700.0, null, aim)
	var shots: int = s["count"]
	var origin := position + Vector2(-18.0 if _body.flip_h else 18.0, -60.0)
	for i in shots:
		var dir: Vector2
		if targets.is_empty():
			dir = facing.rotated((i - (shots - 1) / 2.0) * 0.2)
		else:
			var t: Node2D = targets[i % targets.size()]
			dir = (t.position + Vector2(0, -15) - origin).normalized()
		var p := ProjectileScript.new()
		p.main = main
		p.position = origin
		p.velocity = dir.rotated(randf_range(-0.05, 0.05)) * s["speed"]
		p.damage = s["damage"] * damage_mult
		p.pierce = s["pierce"]
		p.homing = s["homing"]
		p.explode = s["explode"]
		p.life = 2.2 if s["homing"] else 1.6
		p.status = "shock" if randf() < 0.5 else ""
		p.source = "bolt"
		if evolved.has("bolt"):
			p.color = Color(0.7, 0.5, 1.0)
		main.projectiles_node.add_child(p)
	Sound.play("shoot", -10.0, 1.0, 0.1, 0.05)
	Fx.burst(main, origin, [Pixel.hdr(Color(0.6, 0.9, 1.0), 2.0), Color(0.5, 0.3, 1.0, 0.0)], 5, 90.0, 0.3, 3.0)


func _update_blades(delta: float, s: Dictionary) -> void:
	_orbit_angle = wrapf(_orbit_angle + s["spin"] * delta, 0.0, TAU)
	for key in _blade_hits.keys():
		_blade_hits[key] -= delta
		if _blade_hits[key] <= 0.0:
			_blade_hits.erase(key)
	var count: int = s["count"]
	var r := _blade_radius(s)
	var blade_r := 14.0 * area_mult
	var status := "shock" if _blades_charged > 0.0 else "bleed"
	for i in count:
		var a := _orbit_angle + TAU * i / count
		var bp: Vector2 = position + Vector2(cos(a), sin(a)) * r
		for e in main.get_enemies():
			if not e.can_be_hit():
				continue
			var id: int = e.get_instance_id()
			if _blade_hits.has(id):
				continue
			var rr: float = blade_r + e.radius
			if bp.distance_squared_to(e.position) < rr * rr:
				_blade_hits[id] = s["hit_cd"]
				if _blades_charged <= 0.0 and catalyzed("blades", e):
					_blades_charged = 3.0
					combo("blades", e.position)
				e.hit(s["damage"] * damage_mult, position, 160.0, status)
				Fx.sparks(main, bp, Color(0.5, 0.8, 1.0) if status == "shock" else Color(1.0, 0.3, 0.8), 4)


func _update_aura(delta: float, s: Dictionary) -> void:
	_aura_timer -= delta
	if _aura_timer > 0.0:
		return
	_aura_timer = s["tick"]
	var r: float = s["radius"] * area_mult
	var healed := 0.0
	for e in main.get_enemies():
		if not e.can_be_hit():
			continue
		var rr: float = r + e.radius
		if position.distance_squared_to(e.position) < rr * rr:
			e.hit(s["damage"] * damage_mult, position, 40.0, "burn")
			if s["slow"]:
				e.statuses["chill"] = 0.6 if not e.statuses.has("burn") else e.statuses.get("chill", 0.0)
			if (s["lifesteal"] or catalyzed("aura", e)) and healed < 3.0:
				healed += 0.3
	if healed > 0.0:
		heal(healed, false)
		if not s["lifesteal"] and randf() < 0.15:
			combo("aura", position)


func _cast_lightning(s: Dictionary) -> void:
	var candidates: Array = []
	for e in main.get_enemies():
		if e.can_be_hit() and position.distance_squared_to(e.position) < 560.0 * 560.0:
			candidates.append(e)
	candidates.shuffle()
	var r: float = s["radius"] * area_mult
	var strikes := mini(s["strikes"], candidates.size())
	for i in strikes:
		var target_pos: Vector2 = candidates[i].position
		var cat := catalyzed("lightning", candidates[i])
		Fx.lightning(main, target_pos, r)
		main.damage_area(target_pos, r, s["damage"] * damage_mult, null, "shock")
		main.energize(target_pos, r + 60.0, "light", "shock")
		var chains: int = s["chain"] + chain_bonus + (2 if cat else 0)
		if cat:
			combo("lightning", target_pos)
			_later(0.15, func():
				Fx.lightning(main, target_pos, r * 0.7)
				_src = "lightning"
				main.attacker = self
				main.damage_area(target_pos, r * 0.7, s["damage"] * 0.7 * damage_mult, null, "shock"))
		if chains > 0:
			var pts := PackedVector2Array([target_pos + Vector2(0, -15)])
			for t in main.nearest_enemies_to(target_pos, chains, 260.0, candidates[i]):
				pts.append(t.position + Vector2(0, -15))
				t.hit(s["damage"] * 0.5 * damage_mult, target_pos, 60.0, "shock")
			if pts.size() > 1:
				Fx.chain(main, pts, Color(0.6, 0.8, 1.0))
	if strikes > 0:
		Sound.play("thunder", -4.0, 1.0, 0.15, 0.1)
		main.shake(3.0)
		# Синергия: молния заряжает Голо-клинки током
		if weapons.has("blades"):
			_blades_charged = 3.0


func _katana(s: Dictionary) -> void:
	var range_r: float = s["range"] * area_mult
	var dirs: Array[Vector2] = [facing]
	if s["waves"]:
		dirs = [facing, -facing, Vector2(-facing.y, facing.x), Vector2(facing.y, -facing.x)]
	# Мультиядро: дополнительные взмахи в других направлениях
	var extra_dirs := [-facing, Vector2(-facing.y, facing.x), Vector2(facing.y, -facing.x),
		facing.rotated(PI * 0.75), facing.rotated(-PI * 0.75)]
	for i in mini(int(s.get("extra", 0)), extra_dirs.size()):
		if not (extra_dirs[i] in dirs):
			dirs.append(extra_dirs[i])
	var half: float = (s["arc"] if not s["waves"] else deg_to_rad(120.0)) / 2.0
	var origin := position + Vector2(0, -25)
	for d in dirs:
		Fx.slash(main, origin, d.angle(), half * 2.0, range_r, Color(1.0, 0.3, 0.6), self)
		if s["waves"]:
			var p := ProjectileScript.new()
			p.main = main
			p.style = "wave"
			p.position = origin
			p.velocity = d * 480.0
			p.damage = s["damage"] * 0.6 * damage_mult
			p.pierce = 6
			p.life = 0.8
			p.status = "bleed"
			p.source = "katana"
			p.color = Color(1.0, 0.35, 0.7)
			p.can_ignite = false
			main.projectiles_node.add_child(p)
	for e in main.get_enemies():
		if not e.can_be_hit():
			continue
		var to: Vector2 = e.position - position
		if to.length() > range_r + e.radius:
			continue
		for d in dirs:
			if absf(d.angle_to(to)) <= half + 0.15:
				if catalyzed("katana", e) and e.hp < e.max_hp * 0.2 and not e.is_boss:
					combo("katana", e.position)
					Fx.sparks(main, e.position + Vector2(0, -20), Color(1.0, 0.2, 0.4), 10)
					e.hit(e.hp + 1.0, position, 300.0)
				else:
					e.hit(s["damage"] * damage_mult, position, 220.0, "bleed")
				break
	main.energize(position, range_r, "cut", "bleed")
	Sound.play("slash", -3.0, 1.0, 0.15)


func _quake(s: Dictionary, scale_k: float) -> void:
	if _dead:
		return
	_src = "quake"
	main.attacker = self
	var r: float = s["radius"] * area_mult * scale_k
	Fx.ring(main, position, 10.0, r, Pixel.hdr(Color(0.5, 0.95, 1.0), 2.0), 0.45, 7.0)
	Fx.ring(main, position, 6.0, r * 0.7, Pixel.hdr(Color(1.0, 0.7, 0.3), 1.6), 0.35, 4.0)
	Fx.burst(main, position, [Pixel.hdr(Color(0.7, 1.0, 1.0), 1.8), Color(0.4, 0.7, 1.0, 0.0)], 24, r * 2.2, 0.6, 4.0, true, Vector2.ZERO, Vector2.UP, 180.0)
	Fx.burst(main, position, [Color(0.4, 0.38, 0.45, 0.9), Color(0.2, 0.2, 0.25, 0.0)], 14, r * 1.5, 0.7, 5.0, false, Vector2(0, 200))
	main.shake(5.0)
	Sound.play("slam", -2.0, 1.0 / scale_k, 0.08)
	main.energize(position, r, "quake", "chill")
	var shattered := 0
	for e in main.get_enemies():
		if not e.can_be_hit() or e.position.distance_to(position) > r + e.radius:
			continue
		var dmg: float = s["damage"] * damage_mult
		# Синергия: двойной урон по замороженным — «Раскол»
		if e.statuses.has("chill"):
			dmg *= 2.0
			shattered += 1
			Fx.burst(main, e.position + Vector2(0, -15), [Pixel.hdr(Color(0.7, 1.0, 1.0), 2.0), Color(0.5, 0.9, 1.0, 0.0)], 6, 150.0, 0.4, 3.0)
		e.hit(dmg, position, 320.0, "chill")
	if shattered >= 3:
		main.combo_pop(position + Vector2(0, -40), "РАСКОЛ ×%d" % shattered, Color(0.6, 1.0, 1.0))


func _update_drones(delta: float, s: Dictionary) -> void:
	for i in _drones.size():
		_drone_t[i] -= delta
		if _drone_t[i] > 0.0:
			continue
		_drone_t[i] = s["interval"] * cooldown_mult
		var from: Vector2 = position + (_drone_shadows[i].position if i < _drone_shadows.size() else Vector2.ZERO)
		var targets: Array = main.nearest_enemies_to(from, 1, s["range"], null)
		if targets.is_empty():
			continue
		var t: Node2D = targets[0]
		var to: Vector2 = t.position + Vector2(0, -15)
		var col := Color(0.4, 1.0, 0.5) if not evolved.has("drones") else evo_tint("drones", Color(1.0, 0.5, 0.2))
		Fx.beam(main, from, to, col, 1.0, 0.4)
		var cat := catalyzed("drones", t)
		t.hit(s["damage"] * damage_mult, from, 60.0, "burn")
		var chains: int = s["chain"] + (chain_bonus if s["chain"] > 0 else 0) + (2 if cat else 0)
		if cat and randf() < 0.3:
			combo("drones", t.position)
		if chains > 0:
			var pts := PackedVector2Array([to])
			for n in main.nearest_enemies_to(t.position, chains, 200.0, t):
				pts.append(n.position + Vector2(0, -15))
				n.hit(s["damage"] * 0.6 * damage_mult, to, 40.0, "burn")
			if pts.size() > 1:
				Fx.chain(main, pts, col)
		Sound.play("zap", -14.0, 1.4, 0.15, 0.06)



# ================= Новое оружие =================

func _make_proj(style: String, origin: Vector2, vel: Vector2, dmg: float, status: String, src: String) -> Node2D:
	var p := ProjectileScript.new()
	p.main = main
	p.style = style
	p.position = origin
	p.velocity = vel
	p.damage = dmg
	p.status = status
	p.source = src
	p.can_ignite = style in ["orb", "arrow"]
	return p


func _fire_arrows(s: Dictionary) -> void:
	var count: int = s["count"]
	var targets: Array = main.nearest_enemies_to(position, 1, 800.0, null, aim)
	var base: Vector2 = facing if targets.is_empty() else (targets[0].position - position).normalized()
	for i in count:
		var dir: Vector2 = base.rotated((i - (count - 1) / 2.0) * 0.12)
		var p := _make_proj("arrow", position + dir * 20.0, dir * s["speed"], s["damage"] * damage_mult, "bleed", "railbow")
		p.pierce = s["pierce"]
		p.color = Color(0.5, 1.0, 0.8)
		p.life = 1.0
		main.projectiles_node.add_child(p)
	Sound.play("shoot", -10.0, 1.4, 0.1, 0.05)


func _sunbeam(s: Dictionary) -> void:
	var beams: int = s["beams"]
	var length: float = s["length"]
	var width: float = s["width"]
	var targets: Array = main.nearest_enemies_to(position, 1, length, null, aim)
	var base: Vector2 = facing if targets.is_empty() else (targets[0].position - position).normalized()
	var evo: bool = evolved.has("sunbeam")
	for b in beams:
		var dir: Vector2 = base.rotated((b - (beams - 1) / 2.0) * 0.5)
		var ray = preload("res://scripts/sunray3d.gd").new()
		ray.main = main
		ray.anchor = self
		ray.dir = dir
		ray.length_px = length
		ray.width_px = width
		ray.color = evo_tint("sunbeam", Color(1.0, 0.55, 0.85)) if evo else Color(1.0, 0.8, 0.35)
		# Лимит видимых лучей: урон считается всегда, а картинка — только если лучей не слишком много
		if main.vfx_ok("vfx_ray", 6):
			ray.add_to_group("vfx_ray")
			main._bill_root.add_child(ray)
		else:
			ray.free()
			continue
		if main.net_mode == "host" and not Net.replaying:
			Net.fx("sunray", [pid, dir, length, width, ray.color])
		elif main.net_mode == "client" and Net.local:
			Net.cfx("sunray", [pid, dir, length, width, ray.color])
	Sound.play("ability", -12.0, 2.2, 0.1, 0.05)
	# Луч набирает силу и бьёт через мгновение
	_later(0.14, func():
		if _dead:
			return
		Sound.play("ability", -9.0, 1.6, 0.1, 0.1)
		for b in beams:
			var dir: Vector2 = base.rotated((b - (beams - 1) / 2.0) * 0.5)
			_sunbeam_hit(s, dir, length, width))


func _sunbeam_hit(s: Dictionary, dir: Vector2, length: float, width: float) -> void:
	var start := position
	var end: Vector2 = start + dir * length
	_src = "sunbeam"
	main.attacker = self
	var prism := 0
	for e in main.get_enemies():
		if not e.can_be_hit():
			continue
		var c: Vector2 = Geometry2D.get_closest_point_to_segment(e.position, start, end)
		if c.distance_to(e.position) < width / 2.0 + e.radius:
			# Призма: врага под током луч преломляет в соседей
			if prism < 3 and catalyzed("sunbeam", e):
				prism += 1
				var from3: Vector3 = main.to3d(e.position, 0.6)
				for n in main.nearest_enemies_to(e.position, 2 + chain_bonus, 260.0, e):
					main.beam3d(PackedVector3Array([from3, main.to3d(n.position, 0.5)]), Color(1.0, 0.9, 0.6), 0.05, 0.25)
					n.hit(s["damage"] * 0.6 * damage_mult, e.position, 60.0, "burn")
				if prism == 1:
					combo("sunbeam", e.position)
			e.hit(s["damage"] * damage_mult, start, 120.0, "burn")
	# Луч перезаряжает шаровые молнии на своём пути
	for p in main.projectiles_node.get_children():
		if p.get("style") != "ball":
			continue
		var c2: Vector2 = Geometry2D.get_closest_point_to_segment(p.position, start, end)
		if c2.distance_to(p.position) < width / 2.0 + 30.0:
			p.overcharge(1.5)
			main.combo_pop(p.position + Vector2(0, -60), "СОЛНЕЧНЫЙ ЗАРЯД", Color(1.0, 0.85, 0.4))
	Fx.light_flash(main, start + dir * length * 0.5, Color(1.0, 0.8, 0.4), 1.2, length / 60.0, 0.35)
	for i in 4:
		var p := start + dir * length * (0.2 + 0.25 * i)
		Fx.burst(main, p, [Pixel.hdr(Color(1.0, 0.85, 0.4), 1.6), Color(1.0, 0.4, 0.1, 0.0)], 3, 70.0, 0.6, 3.0, true, Vector2(0, -60))
	Fx.burst(main, end, [Pixel.hdr(Color(1.0, 0.95, 0.7), 2.0), Color(1.0, 0.5, 0.1, 0.0)], 10, 180.0, 0.5, 3.5)


## Клиент: солнечный луч, выпущенный героем на хосте.
func net_sunray(dir: Vector2, length: float, width: float, col: Color) -> void:
	var ray = preload("res://scripts/sunray3d.gd").new()
	ray.main = main
	ray.anchor = self
	ray.dir = dir
	ray.length_px = length
	ray.width_px = width
	ray.color = col
	if not main.vfx_ok("vfx_ray", 6):
		ray.free()
		return
	ray.add_to_group("vfx_ray")
	main._bill_root.add_child(ray)


## Гравимагнит: искра из подобранного кристалла.
func magnet_spark() -> void:
	main.attacker = self
	var t: Array = main.nearest_enemies_to(position, 1, 600.0, null, aim)
	if t.is_empty():
		return
	var dir: Vector2 = (t[0].position - position).normalized()
	var p := _make_proj("orb", position + Vector2(0, -40), dir * 600.0, 14.0 * damage_mult, "shock", "")
	p.color = Color(0.5, 1.0, 0.9)
	p.homing = true
	p.life = 1.5
	main.projectiles_node.add_child(p)


func _spawn_spirits(count: int, dmg: float, explode: float) -> void:
	for i in count:
		var dir := Vector2.RIGHT.rotated(TAU * i / maxi(count, 1) + randf() * 0.3)
		var p := _make_proj("spirit", position + dir * 25.0, dir * 260.0, dmg, "chill", "spirits")
		p.homing = true
		p.life = 3.0
		p.explode = explode
		p.color = Color(0.75, 0.6, 1.0)
		main.projectiles_node.add_child(p)


func _ball(s: Dictionary) -> void:
	for i in int(s["count"]):
		var targets: Array = main.nearest_enemies_to(position, 3, 500.0, null, aim)
		var dir: Vector2 = facing.rotated(randf_range(-0.6, 0.6)) if targets.is_empty() else (targets[i % targets.size()].position - position).normalized()
		var p := _make_proj("ball", position + dir * 20.0, dir * 110.0, 0.0, "", "ball")
		p.pierce = 9999
		p.life = s["life"]
		p.zap_radius = s["radius"] * area_mult
		p.zap_damage = s["damage"] * damage_mult
		p.zap_chain = s["chain"]
		p.color = Color(0.5, 0.8, 1.0)
		main.projectiles_node.add_child(p)


func _flasks(s: Dictionary) -> void:
	var targets: Array = main.nearest_enemies_to(position, 6, 420.0, null, aim)
	for i in int(s["count"]):
		var dest: Vector2 = position + facing * 200.0 if targets.is_empty() else targets[randi() % targets.size()].position
		var to := dest - position
		var flight := 0.55
		var p := _make_proj("flask", position, to / flight, 0.0, "", "flask")
		p.pierce = 9999
		p.life = flight
		p.color = Color(0.6, 1.0, 0.3)
		p.pool = {"radius": s["radius"] * area_mult, "damage": s["damage"] * damage_mult, "duration": s["duration"] * status_mult}
		main.projectiles_node.add_child(p)


func _shurikens(count: int, dmg: float, speed: float, spiral: bool, radial := false) -> void:
	var targets: Array = main.nearest_enemies_to(position, 1, 600.0, null, aim)
	var base: Vector2 = facing if targets.is_empty() else (targets[0].position - position).normalized()
	for i in count:
		var dir: Vector2
		if radial or spiral:
			dir = Vector2.RIGHT.rotated(TAU * i / count + _anim_t)
		else:
			dir = base.rotated((i - (count - 1) / 2.0) * 0.3)
		var p := _make_proj("shuriken", position + dir * 20.0, dir * speed, dmg, "bleed", "shuriken")
		p.pierce = 9999
		p.boomerang = true
		p.life = 1.2
		p.color = Color(1.0, 0.4, 0.4)
		main.projectiles_node.add_child(p)
	Sound.play("slash", -12.0, 1.8, 0.1, 0.05)


# ---------- Снаряжение на герое ----------
# Каждое оружие видно на персонаже: дополнительные стволы и клинки закреплены
# за спиной и на поясе (выглядывают из-за силуэта). Модули встроены в сам
# спрайт героя (Pixel.hero_frames): сердце в груди, сапоги, прицел на оружии.

const GEAR_SLOTS := [Vector3(-0.24, 0.62, -0.07), Vector3(0.25, 0.66, -0.07), Vector3(-0.27, 0.36, -0.05),
	Vector3(0.28, 0.4, -0.05), Vector3(0.0, 0.86, -0.09), Vector3(-0.12, 0.2, 0.05)]


func _gear_sprite(tex: Texture2D, px: float, unshaded: bool) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.pixel_size = px
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = not unshaded
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gear.add_child(s)
	return s


func _rebuild_gear() -> void:
	for c in _gear.get_children():
		c.queue_free()
	_gear_w.clear()
	_gear_m.clear()
	# Первое оружие герой держит в руках (оно уже на спрайте), остальные — на снаряжении
	var ws: Array = weapons.keys()
	for i in range(1, ws.size()):
		if i - 1 >= GEAR_SLOTS.size():
			break
		var s := _gear_sprite(Pixel.icon(str(ws[i])), 0.00825, true)
		s.modulate = Color(0.92, 0.92, 1.0)
		_gear_w.append([s, GEAR_SLOTS[i - 1]])
	# Модули больше не кружат вокруг: они нарисованы прямо на герое и оружии
	_refresh_mod_frames()


## Ступени модулей для внешности: с 5-го уровня модуль выглядит мощнее.
func _mod_tiers() -> Dictionary:
	var m := {}
	for id in passives:
		m[id] = 2 if int(passives[id]) >= 5 else 1
	return m


func _refresh_mod_frames() -> void:
	var spr: String = char_data["sprite"]
	if not (spr in Pixel.HERO_KEYS):
		return
	_frames = Pixel.hero_frames(spr, _mod_tiers())


func _update_gear(vis: bool) -> void:
	if main == null or main._mirror_root == null:
		return
	if not is_instance_valid(_gear):
		_gear = Node3D.new()
		main._mirror_root.add_child(_gear)
		_gear_key = ""
	var key := str(weapons.keys()) + "|" + str(_mod_tiers())
	if key != _gear_key:
		_gear_key = key
		_rebuild_gear()
	var show := vis and _body.visible and not _dead
	_gear.visible = show
	if not show:
		return
	_gear.position = main._bl(global_position, 0.0)
	var flip := -1.0 if _body.flip_h else 1.0
	var bob := sin(_anim_t * (11.0 if moving else 2.2)) * (0.025 if moving else 0.01)
	for g in _gear_w:
		var p: Vector3 = g[1]
		(g[0] as Sprite3D).position = Vector3(p.x * flip, p.y + bob, p.z)
		(g[0] as Sprite3D).flip_h = _body.flip_h
