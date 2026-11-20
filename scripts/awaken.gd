extends RefCounted
## Пробуждение героя: после главы героя открывается выбор одного из трёх подклассов.
## Подкласс навсегда даёт герою свои бонусы и особый эффект в бою.
## stats: damage/cooldown/area/speed — множители; hp/armor/regen/magnet/crit/dodge/status/kill_heal — прибавка.

const Meta := preload("res://scripts/meta.gd")
const Fx := preload("res://scripts/fx.gd")
const Pixel := preload("res://scripts/pixel.gd")

## Эффекты: nova (взрыв каждые N убийств), chain (молния с убитого), pulse (волна вокруг),
## aura (стихийная аура), thorns (ответный удар), shield (щит раз в N секунд),
## rage (сила при низком здоровье), orbit (вращающиеся клинки), trail (след стихии), blink (уклон взрывом).
const SUBS := {
	"vega": [
		{"id": "archmage", "name": "Архимаг кода", "desc": "Ученица превзошла учителя. Чары быстрее, каждые 25 убийств — кодовый взрыв.", "stats": {"cooldown": 0.88, "area": 1.1}, "fx": "nova", "n": 25, "el": "shock", "col": Color(0.7, 0.45, 1.0)},
		{"id": "astral", "name": "Звездочёт", "desc": "Расчёт Омеги завершён. Вокруг кружат три звёздных осколка.", "stats": {"damage": 1.1, "magnet": 30.0}, "fx": "orbit", "n": 3, "el": "", "col": Color(0.62, 0.82, 1.0)},
		{"id": "pyre", "name": "Пепельная ведьма", "desc": "Пепел Академии помнит огонь. За героиней тянется горящий след.", "stats": {"damage": 1.08, "status": 0.25}, "fx": "trail", "n": 0, "el": "burn", "col": Color(1.0, 0.5, 0.25)}],
	"rin": [
		{"id": "kensei", "name": "Кэнсэй", "desc": "Святой меч клана. +15% урона и шанс крита.", "stats": {"damage": 1.15, "crit": 0.08}, "fx": "rage", "n": 0, "el": "", "col": Color(1.0, 0.3, 0.42)},
		{"id": "storm_blade", "name": "Клинок грозы", "desc": "Дракон-хранитель отдал искру. Убийства бьют молнией по соседям.", "stats": {"speed": 1.06, "status": 0.15}, "fx": "chain", "n": 2, "el": "shock", "col": Color(1.0, 0.45, 0.5)},
		{"id": "shadow_step", "name": "Тень Тэцу", "desc": "Шаг брата. +уклонение, уклон оставляет взрыв клинков.", "stats": {"dodge": 0.08, "speed": 1.08}, "fx": "blink", "n": 0, "el": "", "col": Color(1.0, 0.65, 0.7)}],
	"bram": [
		{"id": "runesmith", "name": "Рунный мастер", "desc": "Руны горы под рукой. Каждые 8 секунд — щит из рун.", "stats": {"armor": 2.0, "hp": 30.0}, "fx": "shield", "n": 8, "el": "", "col": Color(1.0, 0.7, 0.3)},
		{"id": "forgeheart", "name": "Сердце горна", "desc": "Жар горнодракона. Огненная аура жжёт всех рядом.", "stats": {"hp": 20.0, "status": 0.2}, "fx": "aura", "n": 0, "el": "burn", "col": Color(1.0, 0.5, 0.15)},
		{"id": "quake", "name": "Камнелом", "desc": "Удар молота сотрясает землю: волна каждые 4 секунды.", "stats": {"damage": 1.08, "area": 1.1}, "fx": "pulse", "n": 4, "el": "", "col": Color(1.0, 0.75, 0.4)}],
	"kira": [
		{"id": "netqueen", "name": "Королева сети", "desc": "Сеть растёт с каждым убитым: молнии перескакивают на троих.", "stats": {"cooldown": 0.92, "magnet": 40.0}, "fx": "chain", "n": 3, "el": "shock", "col": Color(0.3, 1.0, 0.8)},
		{"id": "lullaby", "name": "Колыбельная", "desc": "Песня Хора усыпляет: ледяная аура замедляет врагов.", "stats": {"status": 0.3, "regen": 0.5}, "fx": "aura", "n": 0, "el": "chill", "col": Color(0.55, 0.9, 1.0)},
		{"id": "swarm", "name": "Рой дронов", "desc": "Четыре дрона кружат рядом и режут тварей.", "stats": {"damage": 1.06, "xp": 0.1}, "fx": "orbit", "n": 4, "el": "", "col": Color(0.4, 1.0, 0.85)}],
	"skyla": [
		{"id": "hawkeye", "name": "Соколиный глаз", "desc": "Крит +12%, урон по дальним целям выше.", "stats": {"crit": 0.12, "damage": 1.06}, "fx": "rage", "n": 0, "el": "", "col": Color(0.8, 0.9, 1.0)},
		{"id": "silver_owl", "name": "Серебряная сова", "desc": "Крылья ордена: каждые 20 убийств — вихрь перьев.", "stats": {"speed": 1.08, "area": 1.08}, "fx": "nova", "n": 20, "el": "", "col": Color(0.85, 0.92, 1.0)},
		{"id": "fogwalker", "name": "Ходящая в тумане", "desc": "Туман прячет: уклонение +10%, уклон ослепляет врагов вокруг.", "stats": {"dodge": 0.1}, "fx": "blink", "n": 0, "el": "chill", "col": Color(0.7, 0.8, 0.95)}],
	"orm": [
		{"id": "bastion", "name": "Живой бастион", "desc": "Броня +3, щит каждые 7 секунд.", "stats": {"armor": 3.0, "hp": 40.0}, "fx": "shield", "n": 7, "el": "", "col": Color(1.0, 0.8, 0.4)},
		{"id": "steam_knight", "name": "Паровой рыцарь", "desc": "Удар по Орму выпускает обжигающий пар.", "stats": {"hp": 30.0, "damage": 1.05}, "fx": "thorns", "n": 0, "el": "burn", "col": Color(1.0, 0.7, 0.35)},
		{"id": "sunhymn", "name": "Гимн Медного Солнца", "desc": "Гимн ордена: волна света каждые 5 секунд и регенерация.", "stats": {"regen": 1.0}, "fx": "pulse", "n": 5, "el": "", "col": Color(1.0, 0.85, 0.45)}],
	"mora": [
		{"id": "reaper", "name": "Жнец", "desc": "Каждое убийство лечит сильнее, каждые 30 — взрыв душ.", "stats": {"kill_heal": 0.5, "damage": 1.05}, "fx": "nova", "n": 30, "el": "poison", "col": Color(0.8, 0.35, 1.0)},
		{"id": "mirror", "name": "Мора-из-Зеркала", "desc": "Зеркальная сестра рядом: две души-клинка кружат вокруг.", "stats": {"damage": 1.08}, "fx": "orbit", "n": 2, "el": "", "col": Color(0.7, 0.3, 1.0)},
		{"id": "undying", "name": "Неупокоенная", "desc": "Смерть уже была. При низком здоровье урон растёт вдвое быстрее.", "stats": {"hp": 30.0, "regen": 0.6}, "fx": "rage", "n": 0, "el": "", "col": Color(0.9, 0.5, 1.0)}],
	"zephyr": [
		{"id": "thunder", "name": "Громовержец", "desc": "Молнии с каждого убитого бьют двоих.", "stats": {"status": 0.25}, "fx": "chain", "n": 2, "el": "shock", "col": Color(0.5, 0.85, 1.0)},
		{"id": "galewind", "name": "Сын ветра", "desc": "Ветер под ногами: скорость +12% и ледяной след.", "stats": {"speed": 1.12}, "fx": "trail", "n": 0, "el": "chill", "col": Color(0.6, 0.95, 1.0)},
		{"id": "eye", "name": "Око бури", "desc": "Буря кружит вокруг: волна каждые 4 секунды.", "stats": {"area": 1.12, "cooldown": 0.95}, "fx": "pulse", "n": 4, "el": "shock", "col": Color(0.4, 0.8, 1.0)}],
	"iris": [
		{"id": "plague_doctor", "name": "Чумной доктор", "desc": "Ядовитая аура, яды сильнее.", "stats": {"status": 0.3}, "fx": "aura", "n": 0, "el": "poison", "col": Color(0.55, 1.0, 0.25)},
		{"id": "medic", "name": "Полевой медик", "desc": "Лечение +30%, щит из сыворотки каждые 9 секунд.", "stats": {"regen": 1.0, "heal": 0.3}, "fx": "shield", "n": 9, "el": "", "col": Color(0.7, 1.0, 0.5)},
		{"id": "alchemist", "name": "Алхимик", "desc": "Каждые 22 убийства — взрыв колбы.", "stats": {"damage": 1.08, "area": 1.08}, "fx": "nova", "n": 22, "el": "poison", "col": Color(0.6, 1.0, 0.35)}],
	"lyra": [
		{"id": "bladedancer", "name": "Танцовщица клинков", "desc": "Пять клинков вращаются вокруг.", "stats": {"damage": 1.06, "speed": 1.05}, "fx": "orbit", "n": 5, "el": "", "col": Color(1.0, 0.45, 0.85)},
		{"id": "acrobat", "name": "Акробатка", "desc": "Уклонение +10%, сальто взрывает клинками.", "stats": {"dodge": 0.1, "speed": 1.06}, "fx": "blink", "n": 0, "el": "", "col": Color(1.0, 0.6, 0.9)},
		{"id": "ringmaster", "name": "Хозяйка арены", "desc": "Публика ревёт: каждые 18 убийств — фейерверк.", "stats": {"area": 1.12}, "fx": "nova", "n": 18, "el": "burn", "col": Color(1.0, 0.5, 0.7)}],
	"sol": [
		{"id": "dawn", "name": "Вестник рассвета", "desc": "Волна света каждые 4 секунды, обжигает.", "stats": {"hp": 20.0}, "fx": "pulse", "n": 4, "el": "burn", "col": Color(1.0, 0.9, 0.45)},
		{"id": "paladin", "name": "Паладин полудня", "desc": "Броня +2, щит света каждые 8 секунд.", "stats": {"armor": 2.0, "hp": 40.0}, "fx": "shield", "n": 8, "el": "", "col": Color(1.0, 0.95, 0.6)},
		{"id": "solar_aura", "name": "Солнечный венец", "desc": "Венец жжёт всех вокруг, регенерация +0.5.", "stats": {"regen": 0.5}, "fx": "aura", "n": 0, "el": "burn", "col": Color(1.0, 0.8, 0.3)}],
	"volt": [
		{"id": "overload", "name": "Перегрузка", "desc": "Молния с каждого убитого бьёт троих.", "stats": {"cooldown": 0.92}, "fx": "chain", "n": 3, "el": "shock", "col": Color(0.3, 0.9, 1.0)},
		{"id": "grounding", "name": "Заземление", "desc": "Удар по Вольту бьёт током в ответ.", "stats": {"armor": 1.5, "hp": 25.0}, "fx": "thorns", "n": 0, "el": "shock", "col": Color(0.45, 0.9, 1.0)},
		{"id": "tesla", "name": "Катушка Теслы", "desc": "Электрическая аура жалит всё рядом.", "stats": {"status": 0.25}, "fx": "aura", "n": 0, "el": "shock", "col": Color(0.4, 0.85, 1.0)}],
	"kai": [
		{"id": "moonless", "name": "Безлунный", "desc": "Уклонение +12%, уклон оставляет теневой взрыв.", "stats": {"dodge": 0.12}, "fx": "blink", "n": 0, "el": "", "col": Color(0.6, 0.6, 1.0)},
		{"id": "assassin", "name": "Ассасин", "desc": "Крит +12%, урон при низком здоровье растёт.", "stats": {"crit": 0.12, "damage": 1.05}, "fx": "rage", "n": 0, "el": "", "col": Color(0.7, 0.55, 1.0)},
		{"id": "scrollkeeper", "name": "Хранитель свитков", "desc": "Свитки кружат вокруг и режут тварей.", "stats": {"area": 1.08}, "fx": "orbit", "n": 3, "el": "", "col": Color(0.75, 0.75, 1.0)}],
}


static func options(hero: String) -> Array:
	return SUBS.get(hero, [])


static func chosen(hero: String) -> Dictionary:
	Meta.ensure_loaded()
	var id := str(Meta.subclass.get(hero, ""))
	for s in options(hero):
		if s["id"] == id:
			return s
	return {}


## Глава пройдена, а подкласс ещё не выбран.
static func pending(hero: String) -> bool:
	Meta.ensure_loaded()
	return int(Meta.hero_ch.get(hero, 0)) >= 3 and not Meta.subclass.has(hero) and not options(hero).is_empty()


static func stats_text(st: Dictionary) -> String:
	var parts: Array = []
	var names := {"damage": "урон", "cooldown": "перезарядка", "area": "область", "speed": "скорость"}
	for k in st:
		var v := float(st[k])
		match k:
			"damage", "area", "speed":
				parts.append("%s +%d%%" % [names[k], int(round((v - 1.0) * 100.0))])
			"cooldown":
				parts.append("перезарядка −%d%%" % int(round((1.0 - v) * 100.0)))
			"hp":
				parts.append("здоровье +%d" % int(v))
			"armor":
				parts.append("броня +%s" % str(v))
			"regen":
				parts.append("реген +%s/с" % str(v))
			"magnet":
				parts.append("притяжение +%d" % int(v))
			"crit":
				parts.append("крит +%d%%" % int(v * 100.0))
			"dodge":
				parts.append("уклон +%d%%" % int(v * 100.0))
			"status":
				parts.append("стихии +%d%%" % int(v * 100.0))
			"kill_heal":
				parts.append("лечение за убийство +%s" % str(v))
			"xp":
				parts.append("опыт +%d%%" % int(v * 100.0))
			"heal":
				parts.append("лечение +%d%%" % int(v * 100.0))
	return ", ".join(parts)


## Применить подкласс к герою в начале боя.
static func apply(p: Node2D) -> void:
	var s := chosen(str(p.char_id))
	if s.is_empty():
		return
	var st: Dictionary = s["stats"]
	p.damage_mult *= float(st.get("damage", 1.0))
	p.cooldown_mult *= float(st.get("cooldown", 1.0))
	p.area_mult *= float(st.get("area", 1.0))
	p.base_speed *= float(st.get("speed", 1.0))
	p.max_hp += float(st.get("hp", 0.0))
	p.hp = p.max_hp
	p.armor += float(st.get("armor", 0.0))
	p.regen += float(st.get("regen", 0.0))
	p.magnet += float(st.get("magnet", 0.0))
	p.crit_chance += float(st.get("crit", 0.0))
	p.dodge += float(st.get("dodge", 0.0))
	p.status_mult += float(st.get("status", 0.0))
	p.kill_heal += float(st.get("kill_heal", 0.0))
	p.xp_mult += float(st.get("xp", 0.0))
	p.heal_mult += float(st.get("heal", 0.0))
	p.set_meta("awaken", s)


static func _dmg(p: Node2D, k: float) -> float:
	return (8.0 + 2.2 * float(p.level)) * float(p.damage_mult) * float(p.power) * k


static func tick(p: Node2D, delta: float) -> void:
	if not p.has_meta("awaken") or p._dead or p.main.game_over:
		return
	var s: Dictionary = p.get_meta("awaken")
	var m: Node2D = p.main
	var col: Color = s["col"]
	var t: float = float(p.get_meta("aw_t", 0.0)) + delta
	p.set_meta("aw_t", t)
	match str(s["fx"]):
		"pulse":
			if t >= float(s["n"]) * float(p.cooldown_mult):
				p.set_meta("aw_t", 0.0)
				var r := 190.0 * float(p.area_mult)
				Fx.ring(m, p.position, 20.0, r, Pixel.hdr(col, 1.6), 0.45, 6.0)
				m.damage_area(p.position, r, _dmg(p, 1.6), null, str(s["el"]))
		"aura":
			if t >= 0.6:
				p.set_meta("aw_t", 0.0)
				var r2 := 130.0 * float(p.area_mult)
				m.damage_area(p.position, r2, _dmg(p, 0.35), null, str(s["el"]))
				Fx.ring(m, p.position, r2 * 0.8, r2, Color(col, 0.35), 0.5, 2.0)
		"orbit":
			if t >= 0.2:
				p.set_meta("aw_t", 0.0)
				var n := int(s["n"])
				var base := float(m.time_alive) * 3.0
				for i in n:
					var pos: Vector2 = p.position + Vector2.RIGHT.rotated(base + TAU * i / n) * 95.0 * float(p.area_mult)
					m.damage_area(pos, 28.0, _dmg(p, 0.45), null, str(s["el"]))
					Fx.burst(m, pos + Vector2(0, -20), [Pixel.hdr(col, 1.6)], 2, 40.0, 0.4, 3.0)
		"trail":
			var lp: Vector2 = p.get_meta("aw_lp", p.position)
			if t >= 0.35 and lp.distance_to(p.position) > 25.0:
				p.set_meta("aw_t", 0.0)
				p.set_meta("aw_lp", p.position)
				var at: Vector2 = p.position
				Fx.burst(m, at, [Pixel.hdr(col, 1.5)], 4, 50.0, 0.4, 3.0)
				m.get_tree().create_timer(0.3, false).timeout.connect(func():
					if is_instance_valid(m) and not m.game_over:
						m.damage_area(at, 60.0 * float(p.area_mult), _dmg(p, 0.7), null, str(s["el"])))
		"rage":
			if t >= 0.25:
				p.set_meta("aw_t", 0.0)
				var nk := dmg_k(p)
				var ok: float = float(p.get_meta("aw_rk", 1.0))
				p.damage_mult = float(p.damage_mult) / ok * nk
				p.set_meta("aw_rk", nk)
		"shield":
			if t >= float(s["n"]) and not p.get_meta("aw_sh", false):
				p.set_meta("aw_sh", true)
				Fx.ring(m, p.position + Vector2(0, -20), 10.0, 70.0, Pixel.hdr(col, 1.8), 0.4, 4.0)


## Ярость: множитель урона от недостающего здоровья.
static func dmg_k(p: Node2D) -> float:
	if not p.has_meta("awaken"):
		return 1.0
	var s: Dictionary = p.get_meta("awaken")
	if str(s["fx"]) != "rage":
		return 1.0
	var miss := 1.0 - clampf(float(p.hp) / maxf(float(p.max_hp), 1.0), 0.0, 1.0)
	return 1.0 + miss * (0.8 if s["id"] == "undying" else 0.5)


static func on_kill(p: Node2D, e: Node2D) -> void:
	if not p.has_meta("awaken") or p._dead:
		return
	var s: Dictionary = p.get_meta("awaken")
	var m: Node2D = p.main
	var col: Color = s["col"]
	match str(s["fx"]):
		"nova":
			var k := int(p.get_meta("aw_k", 0)) + 1
			if k >= int(s["n"]):
				k = 0
				var r := 240.0 * float(p.area_mult)
				Fx.explosion(m, p.position, Pixel.hdr(col, 1.8), col, r * 0.6)
				Fx.ring(m, p.position, 20.0, r, Pixel.hdr(col, 1.8), 0.5, 7.0)
				m.damage_area(p.position, r, _dmg(p, 3.0), null, str(s["el"]))
			p.set_meta("aw_k", k)
		"chain":
			if randf() < 0.5:
				var tg: Array = m.nearest_enemies_to(e.position, int(s["n"]), 260.0, e)
				var pts := PackedVector2Array([e.position + Vector2(0, -20)])
				for t in tg:
					pts.append(t.position + Vector2(0, -20))
					t.hit(_dmg(p, 0.9), e.position, 60.0, str(s["el"]))
				if pts.size() > 1:
					Fx.chain(m, pts, Pixel.hdr(col, 1.8))


## Перед уроном по герою. true — удар поглощён.
static func on_hurt(p: Node2D) -> bool:
	if not p.has_meta("awaken"):
		return false
	var s: Dictionary = p.get_meta("awaken")
	var m: Node2D = p.main
	var col: Color = s["col"]
	match str(s["fx"]):
		"shield":
			if p.get_meta("aw_sh", false):
				p.set_meta("aw_sh", false)
				p.set_meta("aw_t", 0.0)
				Fx.ring(m, p.position + Vector2(0, -20), 10.0, 110.0, Pixel.hdr(col, 2.0), 0.35, 5.0)
				Fx.text_pop(m, p.position + Vector2(0, -40), str(s["name"]).to_lower(), col, 15)
				return true
		"thorns":
			m.damage_area(p.position, 150.0 * float(p.area_mult), _dmg(p, 1.4), null, str(s["el"]))
			Fx.ring(m, p.position, 10.0, 150.0, Pixel.hdr(col, 1.6), 0.3, 4.0)
	return false


static func on_dodge(p: Node2D) -> void:
	if not p.has_meta("awaken"):
		return
	var s: Dictionary = p.get_meta("awaken")
	if str(s["fx"]) != "blink":
		return
	var m: Node2D = p.main
	var r := 170.0 * float(p.area_mult)
	Fx.ring(m, p.position, 10.0, r, Pixel.hdr(s["col"], 1.8), 0.35, 5.0)
	m.damage_area(p.position, r, _dmg(p, 2.0), null, str(s["el"]))
