extends Node3D
## Персонаж кат-сцен: стилизованная 3D-модель «как в анимационных роликах» —
## крупные кисти и сапоги, выразительная голова с большими глазами, яркие
## силуэты, светящиеся неоновые детали. Собирается из примитивов по описанию
## (цвета героев берутся из их пиксельной внешности), анимируется процедурно:
## дыхание, моргание, разговор, жесты, ходьба, стойка, каст, ликование, колено.

const T := preload("res://scripts/cine_toon.gd")
const Pixel := preload("res://scripts/pixel.gd")

var key := ""
var spec := {}
var mode := "idle"
var talking := 0.0
var walking := false
var floating := false
var flying := false

var hips: Node3D
var spine: Node3D
var head: Node3D
var sh := [null, null]     # плечи L, R
var el := [null, null]     # локти
var hip := [null, null]    # тазобедренные
var kn := [null, null]     # колени
var hand_r: Node3D
var hand_l: Node3D
var mouth: Node3D
var lids: Array = []
var back_part: Node3D
var wings: Array = []
var spin: Array = []       # вращающиеся детали [узел, скорость]
var legs_extra: Array = [] # лапы паука
var _t := 0.0
var _blink := 2.0
var _hips_y := 0.9
var _look := Vector2.ZERO  # куда повёрнута голова (yaw, pitch)
var look_target = null     # Vector3 или null
var _cur := {}
var _last_pos := Vector3.ZERO
var _seed := 0.0


# ================= Сборка =================

static func make(id: String) -> Node3D:
	var a: Node3D = load("res://scripts/cine_actor.gd").new()
	a.key = id
	a.spec = spec_for(id)
	a._build()
	return a


## Описание внешности по ключу: герой, житель, тварь или босс.
static func spec_for(id: String) -> Dictionary:
	if Pixel.LOOKS.has(id):
		var L: Dictionary = Pixel.LOOKS[id]
		var b: int = L["build"]
		var skin: Color = L["skin"]
		var face := "human"
		if L["head"] in ["hood", "great_helm", "ninja"] or skin.get_luminance() < 0.2:
			face = "visor"
		if L["head"] == "skull":
			face = "skull"
		return {"kind": "biped", "scale": 1.0, "tw": [0.21, 0.17, 0.29][b], "td": [0.14, 0.12, 0.19][b],
			"arm": [0.065, 0.055, 0.09][b], "leg": [0.08, 0.07, 0.105][b], "head_r": 0.19,
			"skin": skin if skin.get_luminance() > 0.2 else Color(0.85, 0.7, 0.6), "main": L["main"], "trim": L["trim"],
			"legs": L["legs"], "boots": L["boots"], "neon": L["neon"], "neon2": L["neon2"], "gem": L["gem"],
			"hair": L.get("hair", L["head_c"]), "head": L["head"], "head_c": L["head_c"], "back": L["back"],
			"back_c": L["back_c"], "weapon": L["weapon"], "w_c": L["w_c"], "face": face}
	match id:
		"voron":
			return {"kind": "biped", "scale": 1.05, "tw": 0.25, "td": 0.16, "arm": 0.075, "leg": 0.09, "head_r": 0.19,
				"skin": Color(0.78, 0.6, 0.5), "main": Color(0.22, 0.24, 0.3), "trim": Color(0.85, 0.65, 0.3),
				"legs": Color(0.16, 0.16, 0.2), "boots": Color(0.12, 0.1, 0.1), "neon": Color(0.4, 0.9, 1.0),
				"neon2": Color(1.0, 0.6, 0.2), "gem": Color(0.4, 0.9, 1.0), "hair": Color(0.15, 0.13, 0.15),
				"head": "voron", "head_c": Color(0.15, 0.13, 0.15), "back": "coat", "back_c": Color(0.1, 0.1, 0.13),
				"weapon": "none", "w_c": Color(0.5, 0.5, 0.6), "face": "human", "beard": Color(0.4, 0.38, 0.4), "scar": true}
		"villager":
			return {"kind": "biped", "scale": 0.95, "tw": 0.22, "td": 0.15, "arm": 0.065, "leg": 0.08, "head_r": 0.19,
				"skin": Color(0.9, 0.74, 0.62), "main": Color(0.5, 0.32, 0.25), "trim": Color(0.85, 0.75, 0.5),
				"legs": Color(0.3, 0.25, 0.22), "boots": Color(0.25, 0.18, 0.12), "neon": Color(1.0, 0.75, 0.35),
				"neon2": Color(0.4, 0.9, 1.0), "gem": Color(1.0, 0.8, 0.4), "hair": Color(0.55, 0.3, 0.15),
				"head": "plain", "head_c": Color(0.55, 0.3, 0.15), "back": "none", "back_c": Color(0.3, 0.2, 0.15),
				"weapon": "none", "w_c": Color(0.5, 0.5, 0.6), "face": "human"}
		"villager2":
			var v := spec_for("villager")
			v["skin"] = Color(0.6, 0.42, 0.32)
			v["main"] = Color(0.25, 0.45, 0.4)
			v["hair"] = Color(0.9, 0.85, 0.8)
			v["head_c"] = v["hair"]
			v["scale"] = 0.9
			return v
		# ---------- Твари ----------
		"imp":
			return _mob(0.72, Color(0.42, 0.22, 0.36), Color(1.0, 0.2, 0.2), {"horns": true, "tail": true, "hunch": 0.35, "claws": true, "eye1": true})
		"goblin":
			return _mob(0.68, Color(0.35, 0.55, 0.3), Color(1.0, 0.75, 0.2), {"ears": true, "goggles": true, "hunch": 0.25, "weapon": "blade"})
		"ghoul":
			return _mob(0.95, Color(0.4, 0.46, 0.36), Color(0.5, 1.0, 0.4), {"hunch": 0.5, "claws": true, "jaw": true})
		"brute":
			return _mob(1.45, Color(0.45, 0.25, 0.3), Color(1.0, 0.45, 0.1), {"hunch": 0.3, "plates": true, "horns": true, "wide": true})
		"knight":
			return _mob(1.08, Color(0.3, 0.32, 0.42), Color(1.0, 0.25, 0.3), {"helm": true, "weapon": "katana", "plates": true})
		"caster":
			return _mob(0.95, Color(0.3, 0.18, 0.4), Color(0.75, 0.4, 1.0), {"robe": true, "hood": true, "orb": true})
		"bomber":
			return _mob(0.85, Color(0.45, 0.35, 0.25), Color(1.0, 0.6, 0.1), {"belly": true, "goggles": true})
		"bat", "wraith", "slime", "spider", "slimelet", "spiderling":
			return {"kind": id.trim_suffix("let").trim_suffix("ling"), "scale": 1.0 if not id.ends_with("ling") and not id.ends_with("let") else 0.6}
		# ---------- Боссы ----------
		"lich":
			return {"kind": "boss_lich", "scale": 1.5, "main": Color(0.2, 0.12, 0.3), "neon": Color(0.65, 0.4, 1.0), "neon2": Color(0.4, 1.0, 0.6)}
		"colossus":
			return {"kind": "boss_colossus", "scale": 2.6, "main": Color(0.38, 0.36, 0.42), "neon": Color(1.0, 0.5, 0.15)}
		"queen":
			return {"kind": "boss_queen", "scale": 1.9, "main": Color(0.28, 0.12, 0.25), "neon": Color(1.0, 0.3, 0.7)}
		"omega":
			return {"kind": "boss_omega", "scale": 1.35, "main": Color(0.12, 0.14, 0.22), "neon": Color(0.3, 1.0, 0.9), "neon2": Color(1.0, 0.85, 0.4)}
		"omega_ash":
			return {"kind": "boss_omega", "scale": 1.45, "main": Color(0.2, 0.1, 0.08), "neon": Color(1.0, 0.45, 0.1), "neon2": Color(1.0, 0.85, 0.3)}
		"chorus":
			return {"kind": "boss_omega", "scale": 1.8, "main": Color(0.85, 0.88, 0.95), "neon": Color(0.6, 0.95, 1.0), "neon2": Color(1.0, 0.5, 0.9), "chorus": true}
	return spec_for("villager")


static func _mob(s: float, skin: Color, eye: Color, extra: Dictionary) -> Dictionary:
	var d := {"kind": "biped", "scale": s, "tw": 0.22 if not extra.get("wide", false) else 0.3, "td": 0.16,
		"arm": 0.07, "leg": 0.085, "head_r": 0.2, "skin": skin, "main": skin.darkened(0.25), "trim": Color(0.42, 0.45, 0.55),
		"legs": skin.darkened(0.35), "boots": Color(0.24, 0.25, 0.32), "neon": eye, "neon2": eye.lightened(0.3), "gem": eye,
		"hair": skin.darkened(0.4), "head": "mob", "head_c": skin, "back": "none", "back_c": skin, "weapon": "none",
		"w_c": Color(0.45, 0.45, 0.55), "face": "mob", "mob": true}
	d.merge(extra, true)
	return d


func _build() -> void:
	_seed = randf() * 10.0
	var k: String = spec["kind"]
	match k:
		"biped":
			_build_biped()
		"bat":
			_build_bat()
		"wraith":
			_build_wraith()
		"slime":
			_build_slime()
		"spider":
			_build_spider()
		"boss_lich":
			_build_lich()
		"boss_colossus":
			_build_colossus()
		"boss_queen":
			_build_queen()
		"boss_omega":
			_build_omega()
	scale = Vector3.ONE * float(spec.get("scale", 1.0))


func _node(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


# ---------- Двуногий (герои, жители, гуманоидные твари) ----------

func _build_biped() -> void:
	var S := spec
	var tw: float = S["tw"]
	var td: float = S["td"]
	var arm: float = S["arm"]
	var leg: float = S["leg"]
	var hr: float = S["head_r"]
	var main_c: Color = S["main"]
	var trim: Color = S["trim"]
	var neon: Color = S["neon"]
	var thigh := 0.4
	var shin := 0.4
	_hips_y = thigh + shin + 0.08
	hips = _node(self, Vector3(0, _hips_y, 0))
	# Таз
	T.mi(T.sphere(1.0), T.mat(S["legs"]), hips, Vector3(0, 0.02, 0), Vector3(tw * 0.95, 0.13, td * 1.05))
	# Ноги
	for i in 2:
		var sx := -1.0 if i == 0 else 1.0
		hip[i] = _node(hips, Vector3(sx * tw * 0.5, -0.02, 0))
		T.mi(T.capsule(leg, thigh + leg), T.mat(S["legs"]), hip[i], Vector3(0, -thigh * 0.5, 0))
		kn[i] = _node(hip[i], Vector3(0, -thigh, 0))
		T.mi(T.capsule(leg * 0.92, shin + leg), T.mat(S["boots"]), kn[i], Vector3(0, -shin * 0.5, 0))
		# Крупный сапог с отворотом и неоновой подошвой
		T.mi(T.capsule(leg * 1.15, 0.3), T.mat(S["boots"], 0.0, 0.4), kn[i], Vector3(0, -shin - 0.02, 0.06), Vector3(1.1, 1.0, 1.0), Vector3(PI / 2.0, 0, 0))
		T.mi(T.cyl(leg * 1.25, leg * 1.25, 0.06), T.mat(trim), kn[i], Vector3(0, -shin * 0.45, 0))
		T.mi(T.box(leg * 2.0, 0.025, 0.3), T.neon(neon, 2.0), kn[i], Vector3(0, -shin - 0.075, 0.06))
	# Корпус
	spine = _node(hips, Vector3(0, 0.06, 0))
	var hunch: float = S.get("hunch", 0.0)
	spine.rotation.x = hunch
	if S.get("robe", false):
		T.mi(T.cyl(tw * 0.9, tw * 1.6, 0.85), T.mat(main_c.darkened(0.1)), hips, Vector3(0, -0.38, 0))
	T.mi(T.capsule(0.17, 0.62), T.mat(main_c, 0.0, 0.3), spine, Vector3(0, 0.27, 0), Vector3(tw / 0.17, 1.0, td / 0.17))
	if S.get("belly", false):
		T.mi(T.sphere(0.3), T.mat(S["skin"]), spine, Vector3(0, 0.15, 0.08))
		T.mi(T.sphere(0.12), T.neon(neon, 3.0), spine, Vector3(0, 0.16, 0.36))
	# Пояс с пряжкой
	T.mi(T.cyl(1.0, 1.0, 0.07, 20), T.mat(trim.darkened(0.25), 0.0, 0.4), spine, Vector3(0, 0.0, 0), Vector3(tw * 1.04, 1, td * 1.08))
	T.mi(T.box(0.07, 0.06, 0.03), T.mat(trim.lightened(0.3), 0.0, 0.8), spine, Vector3(0, 0.0, td + 0.01))
	# Нагрудная полоса-неон и воротник
	T.mi(T.box(0.025, 0.36, 0.02), T.neon(neon, 2.2), spine, Vector3(tw * 0.45, 0.27, td * 0.98))
	T.mi(T.box(tw * 1.4, 0.045, 0.02), T.mat(trim), spine, Vector3(0, 0.36, td * 0.96))
	T.mi(T.cyl(0.075, 0.09, 0.12), T.mat(S["skin"] if not S.get("mob", false) else main_c), spine, Vector3(0, 0.6, 0))
	if S.get("plates", false):
		for i in 3:
			T.mi(T.box(tw * 1.8, 0.07, 0.04), T.mat(Color(0.5, 0.53, 0.62), 0.0, 0.6), spine, Vector3(0, 0.12 + i * 0.12, td + 0.02))
	# Руки
	for i in 2:
		var sx := -1.0 if i == 0 else 1.0
		sh[i] = _node(spine, Vector3(sx * (tw + arm * 0.6), 0.5, 0))
		# Наплечник
		T.mi(T.sphere(arm * 1.9), T.mat(trim if S.get("mob", false) == false else main_c, 0.0, 0.5), sh[i], Vector3(sx * 0.02, 0.03, 0), Vector3(1.15, 0.8, 1.05))
		T.mi(T.capsule(arm, 0.34), T.mat(main_c.lightened(0.05)), sh[i], Vector3(0, -0.15, 0))
		el[i] = _node(sh[i], Vector3(0, -0.3, 0))
		T.mi(T.capsule(arm * 0.95, 0.32), T.mat(S["skin"] if S.get("mob", false) else main_c.darkened(0.08)), el[i], Vector3(0, -0.14, 0))
		T.mi(T.cyl(arm * 1.3, arm * 1.15, 0.12), T.mat(trim.darkened(0.1), 0.0, 0.4), el[i], Vector3(0, -0.2, 0))
		var hnd := _node(el[i], Vector3(0, -0.32, 0))
		# Крупная кисть-перчатка
		T.mi(T.sphere(arm * 1.45), T.mat(S["skin"] if S.get("mob", false) else main_c.darkened(0.3)), hnd, Vector3.ZERO, Vector3(1.0, 1.15, 0.9))
		if S.get("claws", false):
			for c in 3:
				T.mi(T.cyl(0.0, 0.018, 0.1, 6), T.mat(Color(0.9, 0.88, 0.8)), hnd, Vector3((c - 1) * 0.03, -0.1, 0.03), Vector3.ONE, Vector3(0.3, 0, 0))
		if i == 1:
			hand_r = hnd
		else:
			hand_l = hnd
	# Голова
	head = _node(spine, Vector3(0, 0.72, 0.0))
	_build_head(hr)
	_build_back()
	_build_weapon()
	if S.get("tail", false):
		var tail := _node(hips, Vector3(0, 0.0, -td))
		for i in 4:
			T.mi(T.sphere(0.05 - i * 0.008), T.mat(S["skin"]), tail, Vector3(0, -0.05 - i * 0.04, -0.08 - i * 0.09))
		T.mi(T.cyl(0.0, 0.05, 0.12, 6), T.neon(neon, 2.0), tail, Vector3(0, -0.22, -0.46), Vector3.ONE, Vector3(-1.3, 0, 0))
		spin.append([tail, 0.0])


func _eye(at: Vector3, r: float, iris: Color, glow_eye := false) -> void:
	if glow_eye:
		T.mi(T.sphere(r), T.neon(iris, 3.5), head, at, Vector3(1.0, 1.1, 0.6))
		return
	T.mi(T.sphere(r), T.mat(Color(0.97, 0.97, 1.0), 0.15, 0.6, 0.0), head, at, Vector3(1.0, 1.25, 0.55))
	T.mi(T.sphere(r * 0.62), T.mat(iris, 0.6, 0.5, 0.0), head, at + Vector3(0, -r * 0.05, r * 0.32), Vector3(1.0, 1.2, 0.5))
	T.mi(T.sphere(r * 0.32), T.mat(Color(0.05, 0.03, 0.08)), head, at + Vector3(0, -r * 0.05, r * 0.45), Vector3(1.0, 1.2, 0.4))
	T.mi(T.sphere(r * 0.18), T.neon(Color.WHITE, 2.0), head, at + Vector3(-r * 0.3, r * 0.35, r * 0.5))
	# Веко для моргания
	var lid := T.mi(T.sphere(r * 1.12), T.mat(spec["skin"]), head, at + Vector3(0, r * 0.15, 0.0), Vector3(1.0, 0.05, 0.62))
	lids.append(lid)


func _build_head(hr: float) -> void:
	var S := spec
	var skin: Color = S["skin"]
	var neon: Color = S["neon"]
	var hc: Color = S["head_c"]
	var face: String = S["face"]
	var htype: String = S["head"]
	# Череп: чуть вытянут вниз, подбородок
	if face != "skull":
		T.mi(T.sphere(hr, 24), T.mat(skin, 0.0, 0.2, 0.3), head, Vector3(0, 0.0, 0), Vector3(0.95, 1.05, 0.98))
		T.mi(T.sphere(hr * 0.7), T.mat(skin), head, Vector3(0, -hr * 0.42, hr * 0.18), Vector3(0.9, 0.65, 0.8))
		# Нос и уши
		T.mi(T.sphere(hr * 0.16), T.mat(skin.darkened(0.06)), head, Vector3(0, -hr * 0.12, hr * 0.95))
		if S.get("ears", false):
			for sx in [-1.0, 1.0]:
				T.mi(T.cyl(0.0, 0.06, 0.22, 8), T.mat(skin), head, Vector3(sx * hr * 0.95, hr * 0.15, 0), Vector3.ONE, Vector3(0, 0, -sx * 1.3))
		else:
			for sx in [-1.0, 1.0]:
				T.mi(T.sphere(hr * 0.2), T.mat(skin.darkened(0.08)), head, Vector3(sx * hr * 0.93, -hr * 0.05, 0), Vector3(0.5, 1.0, 0.8))
	var ey := hr * 0.12
	var ez := hr * 0.8
	match face:
		"human":
			_eye(Vector3(-hr * 0.36, ey, ez), hr * 0.2, neon.darkened(0.2))
			_eye(Vector3(hr * 0.36, ey, ez), hr * 0.2, neon.darkened(0.2))
			# Брови
			for sx in [-1.0, 1.0]:
				T.mi(T.box(hr * 0.42, hr * 0.07, hr * 0.08), T.mat(S["hair"].darkened(0.2)), head, Vector3(sx * hr * 0.36, hr * 0.42, hr * 0.85), Vector3.ONE, Vector3(0, 0, sx * -0.12))
			mouth = _node(head, Vector3(0, -hr * 0.48, hr * 0.84))
			T.mi(T.box(hr * 0.36, hr * 0.1, hr * 0.06), T.mat(Color(0.35, 0.1, 0.12)), mouth, Vector3.ZERO)
			if S.has("beard"):
				T.mi(T.sphere(hr * 0.75), T.mat(S["beard"]), head, Vector3(0, -hr * 0.55, hr * 0.35), Vector3(1.0, 0.75, 0.7))
				T.mi(T.box(hr * 0.5, hr * 0.12, hr * 0.12), T.mat(S["beard"].darkened(0.2)), head, Vector3(0, -hr * 0.3, hr * 0.85))
			if S.get("scar", false):
				T.mi(T.box(hr * 0.06, hr * 0.5, 0.01), T.mat(Color(0.6, 0.35, 0.35)), head, Vector3(hr * 0.36, hr * 0.15, hr * 0.97), Vector3.ONE, Vector3(0, 0, 0.3))
		"visor":
			T.mi(T.box(hr * 1.5, hr * 0.22, hr * 0.3), T.neon(neon, 3.2), head, Vector3(0, ey, hr * 0.82))
		"skull":
			T.mi(T.sphere(hr, 20), T.mat(Color(0.88, 0.86, 0.8), 0.0, 0.4), head, Vector3.ZERO, Vector3(0.95, 1.05, 1.0))
			T.mi(T.box(hr * 1.0, hr * 0.4, hr * 0.5), T.mat(Color(0.85, 0.83, 0.77)), head, Vector3(0, -hr * 0.65, hr * 0.3))
			for sx in [-1.0, 1.0]:
				T.mi(T.sphere(hr * 0.25), T.mat(Color(0.05, 0.03, 0.08)), head, Vector3(sx * hr * 0.36, ey, hr * 0.78))
				T.mi(T.sphere(hr * 0.11), T.neon(neon, 4.0), head, Vector3(sx * hr * 0.36, ey, hr * 0.92))
			mouth = _node(head, Vector3(0, -hr * 0.7, hr * 0.6))
		"mob":
			if S.get("eye1", false):
				T.mi(T.sphere(hr * 0.34), T.mat(Color(0.3, 0.32, 0.4), 0.0, 0.7), head, Vector3(hr * 0.3, ey, ez * 0.95))
				T.mi(T.sphere(hr * 0.22), T.neon(neon, 4.0), head, Vector3(hr * 0.3, ey, ez * 1.15))
				T.mi(T.sphere(hr * 0.12), T.neon(neon, 3.0), head, Vector3(-hr * 0.35, ey + 0.02, ez))
			else:
				for sx in [-1.0, 1.0]:
					T.mi(T.sphere(hr * 0.15), T.neon(neon, 3.5), head, Vector3(sx * hr * 0.35, ey, ez), Vector3(1.3, 0.8, 0.6), Vector3(0, 0, sx * 0.3))
			mouth = _node(head, Vector3(0, -hr * 0.5, hr * 0.8))
			T.mi(T.box(hr * 0.8, hr * 0.14, hr * 0.1), T.mat(Color(0.12, 0.04, 0.06)), mouth, Vector3.ZERO)
			for i in 4:
				T.mi(T.cyl(0.0, 0.018, 0.05, 5), T.mat(Color(0.95, 0.92, 0.85)), mouth, Vector3(-hr * 0.3 + i * hr * 0.2, 0.02, 0.02), Vector3.ONE, Vector3(PI, 0, 0))
			if S.get("jaw", false):
				T.mi(T.box(hr * 1.0, hr * 0.25, hr * 0.5), T.mat(Color(0.45, 0.48, 0.58), 0.0, 0.7), head, Vector3(0, -hr * 0.75, hr * 0.35))
	# Причёски и шлемы
	match htype:
		"hood", "hood_white":
			T.mi(T.sphere(hr * 1.22, 24), T.mat(hc), head, Vector3(0, hr * 0.12, -hr * 0.12), Vector3(1.0, 1.05, 1.05))
			T.mi(T.cyl(0.0, hr * 0.7, hr * 1.2, 12), T.mat(hc), head, Vector3(0, hr * 0.3, -hr * 1.05), Vector3.ONE, Vector3(-1.9, 0, 0))
			# Вырез капюшона: лицо в тени
			T.mi(T.sphere(hr * 0.98), T.mat(Color(0.05, 0.04, 0.1) if htype == "hood" else skin, 0.0, 0.0, 0.0), head, Vector3(0, -hr * 0.05, hr * 0.62), Vector3(0.82, 0.85, 0.7))
			if htype == "hood":
				T.mi(T.box(hr * 1.0, hr * 0.16, hr * 0.12), T.neon(neon, 3.5), head, Vector3(0, ey, hr * 1.28))
				T.mi(T.box(hr * 2.0, 0.03, 0.03), T.neon(S["neon2"], 2.0), head, Vector3(0, hr * 0.55, hr * 0.75), Vector3.ONE, Vector3(-0.4, 0, 0))
			else:
				_eye(Vector3(-hr * 0.3, ey, hr * 1.22), hr * 0.17, neon)
				_eye(Vector3(hr * 0.3, ey, hr * 1.22), hr * 0.17, neon)
				for sx in [-1.0, 1.0]:
					T.mi(T.cyl(0.0, hr * 0.3, hr * 0.9, 8), T.mat(S["hair"]), head, Vector3(sx * hr * 0.5, -hr * 0.4, hr * 0.6), Vector3.ONE, Vector3(0, 0, sx * 0.1))
		"samurai":
			T.mi(T.sphere(hr * 1.1, 20), T.mat(hc, 0.0, 0.6), head, Vector3(0, hr * 0.25, -hr * 0.05), Vector3(1.05, 0.75, 1.05))
			T.mi(T.cyl(hr * 1.35, hr * 1.45, hr * 0.12, 20), T.mat(hc.darkened(0.2), 0.0, 0.6), head, Vector3(0, hr * 0.12, -hr * 0.1))
			T.mi(T.prism(hr * 1.4, hr * 0.8, 0.04), T.mat(trim_or(S)), head, Vector3(0, hr * 1.0, hr * 0.55), Vector3.ONE, Vector3(0, 0, 0))
			T.mi(T.box(hr * 1.3, hr * 0.12, hr * 0.12), T.neon(neon, 2.5), head, Vector3(0, hr * 0.38, hr * 0.85))
			if S.has("hair") and S["hair"] != hc:
				T.mi(T.capsule(hr * 0.25, hr * 1.6), T.mat(S["hair"]), head, Vector3(0, -hr * 0.2, -hr * 1.0), Vector3.ONE, Vector3(0.5, 0, 0))
		"dwarf":
			T.mi(T.sphere(hr * 1.08, 20), T.mat(hc, 0.0, 0.6), head, Vector3(0, hr * 0.35, 0), Vector3(1.05, 0.7, 1.05))
			T.mi(T.cyl(hr * 1.15, hr * 1.15, hr * 0.14), T.mat(hc.darkened(0.25), 0.0, 0.6), head, Vector3(0, hr * 0.15, 0))
			for sx in [-1.0, 1.0]:
				T.mi(T.cyl(0.0, 0.05, 0.28, 8), T.mat(Color(0.92, 0.88, 0.78)), head, Vector3(sx * hr * 1.0, hr * 0.6, 0), Vector3.ONE, Vector3(0, 0, -sx * 0.9))
			T.mi(T.sphere(hr * 0.85), T.mat(S["hair"]), head, Vector3(0, -hr * 0.65, hr * 0.42), Vector3(1.05, 1.2, 0.75))
			T.mi(T.cyl(hr * 0.2, hr * 0.32, hr * 0.7, 8), T.mat(S["hair"]), head, Vector3(0, -hr * 1.35, hr * 0.5))
			T.mi(T.sphere(hr * 0.12), T.neon(S["neon2"], 3.0), head, Vector3(0, hr * 0.5, hr * 0.95))
		"witch":
			T.mi(T.sphere(hr * 1.05, 20), T.mat(S["hair"]), head, Vector3(0, hr * 0.15, -hr * 0.15), Vector3(1.05, 1.0, 1.0))
			T.mi(T.capsule(hr * 0.35, hr * 2.2), T.mat(S["hair"]), head, Vector3(0, -hr * 0.9, -hr * 0.55))
			T.mi(T.cyl(hr * 2.0, hr * 2.0, 0.03, 24), T.mat(hc), head, Vector3(0, hr * 0.7, 0))
			T.mi(T.cyl(0.0, hr * 0.85, hr * 2.6, 16), T.mat(hc), head, Vector3(-hr * 0.2, hr * 1.9, -hr * 0.2), Vector3.ONE, Vector3(-0.25, 0, 0.2))
			T.mi(T.cyl(hr * 0.86, hr * 0.86, 0.06, 20), T.neon(neon, 2.5), head, Vector3(0, hr * 0.82, 0))
		"great_helm":
			T.mi(T.cyl(hr * 1.1, hr * 1.1, hr * 2.2, 20), T.mat(hc, 0.0, 0.7), head, Vector3(0, hr * 0.1, 0))
			T.mi(T.sphere(hr * 1.1, 20), T.mat(hc, 0.0, 0.7), head, Vector3(0, hr * 1.2, 0), Vector3(1, 0.4, 1))
			T.mi(T.box(hr * 1.6, hr * 0.16, hr * 0.3), T.neon(neon, 3.5), head, Vector3(0, ey, hr * 1.0))
			T.mi(T.box(hr * 0.12, hr * 1.4, hr * 0.12), T.mat(trim_or(S), 0.0, 0.7), head, Vector3(0, hr * 0.3, hr * 1.08))
			var halo_n := _node(head, Vector3(0, hr * 1.6, 0))
			T.mi(T.torus(hr * 0.9, hr * 1.0), T.neon(neon, 2.5), halo_n, Vector3.ZERO)
			spin.append([halo_n, 0.8])
		"feathers":
			T.mi(T.sphere(hr * 1.02, 20), T.mat(Color(0.12, 0.1, 0.1)), head, Vector3(0, hr * 0.2, -hr * 0.12))
			T.mi(T.cyl(hr * 1.05, hr * 1.05, hr * 0.25, 20), T.mat(hc), head, Vector3(0, hr * 0.42, 0))
			var fc := [Color(0.9, 0.3, 0.3), Color(0.3, 0.6, 1.0), Color(0.95, 0.85, 0.3), Color(0.3, 0.9, 0.5), Color(0.95, 0.95, 0.95)]
			for i in 5:
				var a := -0.9 + i * 0.45
				T.mi(T.capsule(0.04, hr * 1.6), T.mat(fc[i], 0.3), head, Vector3(sin(a) * hr * 0.9, hr * 1.2, -hr * 0.5 + cos(a) * 0.05), Vector3(1.0, 1.0, 0.4), Vector3(-0.3, 0, -a * 0.5))
		"goggles":
			T.mi(T.sphere(hr * 1.06, 20), T.mat(S["hair"]), head, Vector3(0, hr * 0.25, -hr * 0.12), Vector3(1.05, 0.95, 1.0))
			for i in 3:
				T.mi(T.cyl(0.0, hr * 0.35, hr * 1.0, 8), T.mat(S["hair"]), head, Vector3(-0.5 * hr + i * 0.5 * hr, hr * 0.9, -hr * 0.3), Vector3.ONE, Vector3(-0.6, 0, (1 - i) * 0.5))
			T.mi(T.cyl(hr * 1.07, hr * 1.07, hr * 0.2, 20), T.mat(hc), head, Vector3(0, hr * 0.48, 0))
			for sx in [-1.0, 1.0]:
				T.mi(T.cyl(hr * 0.3, hr * 0.3, hr * 0.25, 14), T.mat(Color(0.5, 0.45, 0.4), 0.0, 0.8), head, Vector3(sx * hr * 0.38, hr * 0.55, hr * 0.92), Vector3.ONE, Vector3(PI / 2.0 - 0.3, 0, 0))
				T.mi(T.sphere(hr * 0.24), T.glass(Color(neon, 0.6), 1.2), head, Vector3(sx * hr * 0.38, hr * 0.58, hr * 1.04), Vector3(1, 1, 0.4))
		"ninja":
			T.mi(T.sphere(hr * 1.06, 20), T.mat(hc), head, Vector3(0, hr * 0.03, 0), Vector3(1.0, 1.05, 1.0))
			T.mi(T.cyl(hr * 1.08, hr * 1.08, hr * 0.2, 20), T.mat(trim_or(S)), head, Vector3(0, hr * 0.4, 0))
			T.mi(T.capsule(0.03, hr * 1.4), T.mat(trim_or(S)), head, Vector3(0, hr * 0.35, -hr * 1.3), Vector3.ONE, Vector3(1.2, 0, 0))
		"skull":
			T.mi(T.sphere(hr * 1.25, 20), T.mat(hc), head, Vector3(0, hr * 0.15, -hr * 0.15), Vector3(1.0, 1.05, 1.05))
		"voron":
			T.mi(T.sphere(hr * 1.02, 20), T.mat(S["hair"]), head, Vector3(0, hr * 0.32, -hr * 0.12), Vector3(1.0, 0.8, 1.0))
			T.mi(T.box(hr * 0.5, hr * 0.32, 0.03), T.mat(Color(0.08, 0.08, 0.1)), head, Vector3(-hr * 0.36, hr * 0.12, hr * 0.97))
			T.mi(T.box(hr * 2.0, 0.02, 0.02), T.mat(Color(0.08, 0.08, 0.1)), head, Vector3(0, hr * 0.28, hr * 0.7), Vector3.ONE, Vector3(0, 0, 0.12))
		"plain":
			T.mi(T.sphere(hr * 1.04, 20), T.mat(S["hair"]), head, Vector3(0, hr * 0.28, -hr * 0.14), Vector3(1.0, 0.85, 1.0))
		"mob":
			if S.get("horns", false):
				for sx in [-1.0, 1.0]:
					T.mi(T.cyl(0.0, hr * 0.28, hr * 1.1, 8), T.mat(Color(0.85, 0.8, 0.7), 0.0, 0.5), head, Vector3(sx * hr * 0.6, hr * 0.85, -hr * 0.1), Vector3.ONE, Vector3(-0.3, 0, -sx * 0.5))
			if S.get("helm", false):
				T.mi(T.sphere(hr * 1.15, 20), T.mat(Color(0.32, 0.34, 0.44), 0.0, 0.8), head, Vector3(0, hr * 0.1, 0), Vector3(1.0, 1.1, 1.05))
				T.mi(T.box(hr * 1.4, hr * 0.14, hr * 0.2), T.neon(neon, 3.5), head, Vector3(0, ey, hr * 1.02))
				T.mi(T.box(0.04, hr * 0.9, hr * 1.6), T.neon(neon, 1.5), head, Vector3(0, hr * 1.2, 0))
			if S.get("hood", false):
				T.mi(T.sphere(hr * 1.25, 20), T.mat(S["main"]), head, Vector3(0, hr * 0.15, -hr * 0.15))
				T.mi(T.cyl(0.0, hr * 0.8, hr * 1.4, 10), T.mat(S["main"]), head, Vector3(0, hr * 1.2, -hr * 0.4), Vector3.ONE, Vector3(-0.6, 0, 0))
			if S.get("goggles", false):
				for sx in [-1.0, 1.0]:
					T.mi(T.sphere(hr * 0.26), T.glass(Color(neon, 0.6), 1.5), head, Vector3(sx * hr * 0.36, hr * 0.3, hr * 0.92), Vector3(1, 1, 0.5))
				T.mi(T.cyl(hr * 1.04, hr * 1.04, hr * 0.14), T.mat(Color(0.3, 0.22, 0.15)), head, Vector3(0, hr * 0.3, 0))


static func trim_or(S: Dictionary) -> Color:
	return S.get("trim", Color(0.9, 0.7, 0.3))


func _build_back() -> void:
	var S := spec
	var b: String = S["back"]
	var bc: Color = S["back_c"]
	var tw: float = S["tw"]
	var td: float = S["td"]
	if b == "none" or b == "":
		return
	back_part = _node(spine, Vector3(0, 0.52, -td - 0.02))
	match b:
		"cloak", "cape", "robe", "coat":
			var ln := 1.1 if b != "coat" else 0.85
			T.mi(T.box(tw * 2.4, ln, 0.04), T.mat(bc, 0.0, 0.2), back_part, Vector3(0, -ln * 0.5, -0.03), Vector3.ONE, Vector3(-0.08, 0, 0))
			if b == "cloak":
				T.mi(T.box(tw * 2.4, 0.04, 0.05), T.neon(S["neon2"], 2.5), back_part, Vector3(0, -ln + 0.02, -0.08))
			if b == "coat":
				for sx in [-1.0, 1.0]:
					T.mi(T.box(0.12, 0.7, 0.04), T.mat(bc), spine, Vector3(sx * tw * 0.9, -0.15, td * 0.9), Vector3.ONE, Vector3(0.05, 0, sx * 0.08))
		"cape_short":
			T.mi(T.box(tw * 2.2, 0.55, 0.04), T.mat(bc), back_part, Vector3(0, -0.27, -0.03))
			T.mi(T.box(tw * 2.2, 0.03, 0.05), T.neon(S["neon"], 2.5), back_part, Vector3(0, -0.53, -0.06))
		"scarf":
			T.mi(T.torus(0.11, 0.17), T.mat(bc), spine, Vector3(0, 0.6, 0), Vector3(1.2, 1.4, 1.1))
			T.mi(T.box(0.14, 0.6, 0.03), T.mat(bc), back_part, Vector3(0.1, -0.1, -0.05), Vector3.ONE, Vector3(-0.9, 0.3, 0.2))
			T.mi(T.box(0.12, 0.45, 0.03), T.mat(bc.darkened(0.15)), back_part, Vector3(-0.08, -0.05, -0.05), Vector3.ONE, Vector3(-0.7, -0.3, -0.2))
		"quiver":
			T.mi(T.cyl(0.07, 0.06, 0.55), T.mat(bc), back_part, Vector3(0.05, -0.2, -0.05), Vector3.ONE, Vector3(0, 0, 0.4))
			for i in 3:
				T.mi(T.box(0.015, 0.2, 0.015), T.mat(Color(0.85, 0.85, 0.8)), back_part, Vector3(0.12 + i * 0.03, 0.1, -0.05), Vector3.ONE, Vector3(0, 0, 0.4))
				T.mi(T.sphere(0.025), T.neon(S["neon"], 3.0), back_part, Vector3(0.17 + i * 0.03, 0.2, -0.05))


func _build_weapon() -> void:
	var S := spec
	var w: String = S["weapon"]
	var wc: Color = S["w_c"]
	var gem: Color = S["gem"]
	var neon: Color = S["neon"]
	if w == "none":
		if S.get("orb", false):
			var o := _node(hand_r, Vector3(0, -0.05, 0.18))
			T.mi(T.sphere(0.1), T.neon(neon, 3.0), o, Vector3.ZERO)
			T.mi(T.sphere(0.2), T.halo(Color(neon, 0.5), 1.5), o, Vector3.ZERO)
		return
	var g := _node(hand_r, Vector3.ZERO)
	match w:
		"staff", "orbstaff", "scythe":
			T.mi(T.cyl(0.025, 0.03, 1.75), T.mat(wc, 0.0, 0.5), g, Vector3(0, 0.25, 0))
			T.mi(T.cyl(0.04, 0.04, 0.08), T.mat(S["trim"], 0.0, 0.7), g, Vector3(0, 0.9, 0))
			var top := _node(g, Vector3(0, 1.12, 0))
			if w == "staff":
				for sx in [-1.0, 1.0]:
					T.mi(T.cyl(0.0, 0.025, 0.25, 6), T.mat(wc), top, Vector3(sx * 0.08, 0.0, 0), Vector3.ONE, Vector3(0, 0, -sx * 0.35))
				T.mi(T.sphere(0.075, 4), T.neon(gem, 3.0), top, Vector3(0, 0.06, 0), Vector3(1, 1.6, 1))
				T.mi(T.sphere(0.22), T.halo(Color(gem, 0.45), 1.5), top, Vector3(0, 0.06, 0))
				spin.append([top, 1.2])
			elif w == "orbstaff":
				T.mi(T.sphere(0.11), T.neon(gem, 3.0), top, Vector3(0, 0.08, 0))
				T.mi(T.torus(0.14, 0.16), T.neon(gem.lightened(0.3), 2.0), top, Vector3(0, 0.08, 0), Vector3.ONE, Vector3(0.6, 0, 0.3))
				T.mi(T.sphere(0.28), T.halo(Color(gem, 0.4), 1.5), top, Vector3(0, 0.08, 0))
				spin.append([top, 1.5])
			else:
				for i in 5:
					T.mi(T.box(0.04, 0.16, 0.02), T.neon(neon, 2.5), top, Vector3(-0.08 - i * 0.11, -0.02 - i * i * 0.012, 0), Vector3.ONE, Vector3(0, 0, 1.2 + i * 0.12))
		"katana", "blade":
			var ln := 0.95 if w == "katana" else 0.7
			g.rotation = Vector3(-1.2, 0, 0)
			T.mi(T.cyl(0.025, 0.025, 0.24), T.mat(Color(0.15, 0.1, 0.15)), g, Vector3(0, 0.0, 0))
			T.mi(T.cyl(0.07, 0.07, 0.025, 12), T.mat(S["trim"], 0.0, 0.8), g, Vector3(0, -0.13, 0))
			T.mi(T.box(0.018, ln, 0.06), T.mat(Color(0.88, 0.9, 0.96), 0.1, 0.9), g, Vector3(0, -0.15 - ln * 0.5, 0))
			T.mi(T.box(0.022, ln * 0.92, 0.012), T.neon(neon, 3.0), g, Vector3(0, -0.15 - ln * 0.5, 0.032))
		"hammer":
			g.rotation = Vector3(-0.3, 0, 0)
			T.mi(T.cyl(0.03, 0.035, 0.85), T.mat(Color(0.45, 0.3, 0.18)), g, Vector3(0, 0.25, 0))
			T.mi(T.box(0.42, 0.24, 0.24), T.mat(wc, 0.0, 0.7), g, Vector3(0, 0.68, 0))
			T.mi(T.box(0.44, 0.04, 0.26), T.neon(neon, 2.5), g, Vector3(0, 0.68, 0))
			T.mi(T.box(0.06, 0.18, 0.26), T.neon(S["neon2"], 2.0), g, Vector3(0, 0.68, 0))
		"mace":
			T.mi(T.cyl(0.03, 0.03, 0.6), T.mat(Color(0.5, 0.5, 0.58), 0.0, 0.6), g, Vector3(0, 0.25, 0))
			T.mi(T.sphere(0.12), T.mat(S["trim"], 0.0, 0.8), g, Vector3(0, 0.6, 0))
			for i in 6:
				var a := TAU * i / 6.0
				T.mi(T.cyl(0.0, 0.03, 0.09, 6), T.mat(S["trim"], 0.0, 0.8), g, Vector3(cos(a) * 0.12, 0.6, sin(a) * 0.12), Vector3.ONE, Vector3(0, -a, PI / 2.0))
			var sh_n := _node(hand_l, Vector3(0, 0.05, 0.12))
			T.mi(T.cyl(0.28, 0.28, 0.05, 6), T.mat(wc, 0.0, 0.7), sh_n, Vector3.ZERO, Vector3(1, 1, 1.25), Vector3(PI / 2.0, 0, 0))
			T.mi(T.box(0.04, 0.5, 0.06), T.neon(neon, 2.5), sh_n, Vector3(0, 0, 0.03))
		"wand":
			T.mi(T.cyl(0.015, 0.02, 0.4), T.mat(wc), g, Vector3(0, 0.12, 0.05), Vector3.ONE, Vector3(0.6, 0, 0))
			T.mi(T.sphere(0.05), T.neon(gem, 3.5), g, Vector3(0, 0.3, 0.17))
			var dr := _node(self, Vector3(-0.45, 2.0, -0.1))
			T.mi(T.sphere(0.1), T.mat(Color(0.3, 0.32, 0.4), 0.0, 0.8), dr, Vector3.ZERO, Vector3(1.4, 0.7, 1.0))
			T.mi(T.sphere(0.04), T.neon(gem, 4.0), dr, Vector3(0, 0, 0.12))
			spin.append([dr, -0.01])
		"bow":
			var bw := _node(hand_l, Vector3(0, 0, 0.05))
			for i in 7:
				var a := -1.1 + i * (2.2 / 6.0)
				T.mi(T.capsule(0.022, 0.24), T.mat(wc, 0.0, 0.6), bw, Vector3(0, sin(a) * 0.6, cos(a) * 0.22 - 0.22), Vector3.ONE, Vector3(-a + PI / 2.0 - PI / 2.0, 0, 0))
			T.mi(T.cyl(0.006, 0.006, 1.06), T.neon(neon, 3.0), bw, Vector3(0, 0, -0.22))
		"flask":
			T.mi(T.sphere(0.09), T.glass(Color(0.6, 0.8, 0.9, 0.35), 0.3), g, Vector3(0, -0.02, 0.1))
			T.mi(T.sphere(0.07), T.neon(gem, 2.5), g, Vector3(0, -0.04, 0.1))
			T.mi(T.cyl(0.03, 0.03, 0.1), T.mat(Color(0.5, 0.4, 0.3)), g, Vector3(0, 0.1, 0.1))


# ---------- Особые тела ----------

func _build_bat() -> void:
	hips = _node(self, Vector3(0, 1.4, 0))
	flying = true
	var c := Color(0.3, 0.22, 0.35)
	T.mi(T.sphere(0.22), T.mat(c), hips, Vector3.ZERO, Vector3(1.0, 1.1, 0.9))
	head = _node(hips, Vector3(0, 0.2, 0.1))
	T.mi(T.sphere(0.15), T.mat(c), head, Vector3.ZERO)
	for sx in [-1.0, 1.0]:
		T.mi(T.cyl(0.0, 0.07, 0.2, 6), T.mat(c), head, Vector3(sx * 0.09, 0.17, 0), Vector3.ONE, Vector3(0, 0, -sx * 0.3))
		T.mi(T.sphere(0.04), T.neon(Color(1.0, 0.3, 0.3), 4.0), head, Vector3(sx * 0.06, 0.02, 0.13))
		var w := _node(hips, Vector3(sx * 0.15, 0.05, 0))
		T.mi(T.box(0.7, 0.02, 0.4), T.mat(Color(0.4, 0.2, 0.35)), w, Vector3(sx * 0.35, 0, 0), Vector3.ONE, Vector3(0, 0, 0))
		T.mi(T.box(0.7, 0.03, 0.03), T.neon(Color(0.8, 0.3, 1.0), 1.5), w, Vector3(sx * 0.35, 0.01, 0.2))
		wings.append([w, sx])


func _build_wraith() -> void:
	hips = _node(self, Vector3(0, 0.9, 0))
	floating = true
	var c := Color(0.15, 0.2, 0.3)
	T.mi(T.cyl(0.18, 0.45, 1.3, 16), T.glass(Color(0.3, 0.55, 0.8, 0.55), 0.6), hips, Vector3(0, 0.0, 0))
	head = _node(hips, Vector3(0, 0.8, 0))
	T.mi(T.sphere(0.22), T.mat(c), head, Vector3.ZERO)
	T.mi(T.sphere(0.24), T.mat(Color(0.12, 0.15, 0.22)), head, Vector3(0, 0.05, -0.06), Vector3(1.05, 1.1, 1.0))
	for sx in [-1.0, 1.0]:
		T.mi(T.sphere(0.05), T.neon(Color(0.5, 0.9, 1.0), 4.0), head, Vector3(sx * 0.08, 0.0, 0.19))
	for i in 2:
		var sx := -1.0 if i == 0 else 1.0
		sh[i] = _node(hips, Vector3(sx * 0.28, 0.55, 0))
		T.mi(T.capsule(0.05, 0.6), T.glass(Color(0.3, 0.55, 0.8, 0.6), 0.6), sh[i], Vector3(0, -0.28, 0))
		el[i] = _node(sh[i], Vector3(0, -0.55, 0))
	T.mi(T.torus(0.3, 0.34), T.neon(Color(0.5, 0.9, 1.0), 1.5), hips, Vector3(0, -0.3, 0), Vector3(1, 0.5, 1))


func _build_slime() -> void:
	hips = _node(self, Vector3(0, 0.0, 0))
	var c := Color(0.35, 1.0, 0.45, 0.6)
	var body := T.mi(T.sphere(0.55, 24), T.glass(c, 0.6), hips, Vector3(0, 0.45, 0), Vector3(1.0, 0.8, 1.0))
	spin.append([body, 0.0])
	T.mi(T.sphere(0.2), T.neon(Color(0.6, 1.0, 0.3), 2.0), hips, Vector3(0.05, 0.4, 0))
	head = _node(hips, Vector3(0, 0.55, 0.38))
	for sx in [-1.0, 1.0]:
		T.mi(T.sphere(0.09), T.mat(Color(1, 1, 1)), head, Vector3(sx * 0.14, 0, 0))
		T.mi(T.sphere(0.05), T.mat(Color(0.05, 0.05, 0.08)), head, Vector3(sx * 0.14, 0, 0.06))


func _build_spider() -> void:
	hips = _node(self, Vector3(0, 0.55, 0))
	var c := Color(0.2, 0.18, 0.22)
	T.mi(T.sphere(0.35), T.mat(c, 0.0, 0.5), hips, Vector3(0, 0.05, -0.4), Vector3(1.0, 0.85, 1.2))
	T.mi(T.box(0.06, 0.04, 0.6), T.neon(Color(1.0, 0.25, 0.3), 2.0), hips, Vector3(0, 0.33, -0.4))
	T.mi(T.sphere(0.22), T.mat(Color(0.35, 0.36, 0.44), 0.0, 0.7), hips, Vector3(0, 0, 0.05))
	head = _node(hips, Vector3(0, 0.02, 0.25))
	for i in 6:
		T.mi(T.sphere(0.035), T.neon(Color(1.0, 0.2, 0.25), 4.0), head, Vector3(-0.08 + (i % 3) * 0.08, 0.04 + (i / 3) * 0.06, 0.08))
	for i in 8:
		var sx := -1.0 if i < 4 else 1.0
		var j := i % 4
		var p := _node(hips, Vector3(sx * 0.15, 0, 0.1 - j * 0.14))
		p.rotation = Vector3(0, sx * (0.3 - j * 0.35), sx * -0.8)
		T.mi(T.capsule(0.03, 0.55), T.mat(c), p, Vector3(0, -0.25, 0))
		var k2 := _node(p, Vector3(0, -0.5, 0))
		k2.rotation.z = sx * 1.6
		T.mi(T.capsule(0.025, 0.6), T.mat(Color(0.35, 0.36, 0.44), 0.0, 0.6), k2, Vector3(0, -0.28, 0))
		legs_extra.append([p, sx, j])


func _robed(c: Color, neon: Color, tall := 1.0) -> void:
	hips = _node(self, Vector3(0, 1.0 * tall, 0))
	floating = true
	T.mi(T.cyl(0.25, 0.6, 1.5 * tall, 20), T.mat(c, 0.0, 0.3), hips, Vector3(0, -0.4 * tall, 0))
	T.mi(T.cyl(0.62, 0.62, 0.05, 20), T.neon(neon, 2.5), hips, Vector3(0, -1.13 * tall, 0))
	spine = _node(hips, Vector3(0, 0.3, 0))
	T.mi(T.capsule(0.24, 0.7), T.mat(c.lightened(0.05), 0.0, 0.3), spine, Vector3(0, 0.2, 0), Vector3(1.15, 1, 0.8))
	T.mi(T.box(0.04, 0.6, 0.03), T.neon(neon, 2.5), spine, Vector3(0, 0.1, 0.2))
	for i in 2:
		var sx := -1.0 if i == 0 else 1.0
		sh[i] = _node(spine, Vector3(sx * 0.33, 0.45, 0))
		T.mi(T.sphere(0.16), T.mat(c.lightened(0.1), 0.0, 0.5), sh[i], Vector3(0, 0.03, 0), Vector3(1.2, 0.8, 1.1))
		T.mi(T.cyl(0.08, 0.14, 0.55), T.mat(c), sh[i], Vector3(0, -0.25, 0))
		el[i] = _node(sh[i], Vector3(0, -0.5, 0))
		T.mi(T.cyl(0.09, 0.12, 0.45), T.mat(c.darkened(0.1)), el[i], Vector3(0, -0.2, 0))
		var hnd := _node(el[i], Vector3(0, -0.45, 0))
		T.mi(T.sphere(0.07), T.mat(Color(0.75, 0.75, 0.7)), hnd, Vector3.ZERO)
		if i == 1:
			hand_r = hnd
		else:
			hand_l = hnd
	head = _node(spine, Vector3(0, 0.75, 0))


func _build_lich() -> void:
	var c: Color = spec["main"]
	var neon: Color = spec["neon"]
	_robed(c, neon, 1.0)
	T.mi(T.sphere(0.2), T.mat(Color(0.86, 0.84, 0.78), 0.0, 0.4), head, Vector3.ZERO, Vector3(0.95, 1.1, 1.0))
	T.mi(T.box(0.2, 0.08, 0.12), T.mat(Color(0.8, 0.78, 0.72)), head, Vector3(0, -0.16, 0.08))
	for sx in [-1.0, 1.0]:
		T.mi(T.sphere(0.055), T.mat(Color(0.03, 0.02, 0.05)), head, Vector3(sx * 0.075, 0.02, 0.16))
		T.mi(T.sphere(0.03), T.neon(neon, 5.0), head, Vector3(sx * 0.075, 0.02, 0.19))
	T.mi(T.sphere(0.27), T.mat(c), head, Vector3(0, 0.05, -0.08), Vector3(1.05, 1.1, 1.0))
	var crown := _node(head, Vector3(0, 0.2, 0))
	T.mi(T.cyl(0.17, 0.17, 0.06, 16), T.mat(Color(0.9, 0.75, 0.3), 0.0, 0.8), crown, Vector3.ZERO)
	for i in 7:
		var a := TAU * i / 7.0
		T.mi(T.cyl(0.0, 0.03, 0.18, 5), T.mat(Color(0.9, 0.75, 0.3), 0.0, 0.8), crown, Vector3(cos(a) * 0.16, 0.1, sin(a) * 0.16))
	T.mi(T.sphere(0.05, 4), T.neon(spec["neon2"], 4.0), crown, Vector3(0, 0.05, 0.17))
	var st := _node(hand_r, Vector3.ZERO)
	T.mi(T.cyl(0.03, 0.03, 2.0), T.mat(Color(0.25, 0.22, 0.28)), st, Vector3(0, 0.3, 0))
	T.mi(T.sphere(0.14), T.neon(spec["neon2"], 3.5), st, Vector3(0, 1.38, 0))
	T.mi(T.sphere(0.35), T.halo(Color(spec["neon2"], 0.5), 1.5), st, Vector3(0, 1.38, 0))
	for i in 3:
		var ring := _node(self, Vector3(0, 1.6, 0))
		T.mi(T.torus(0.9 + i * 0.25, 0.93 + i * 0.25), T.neon(neon, 1.5), ring, Vector3.ZERO, Vector3.ONE, Vector3(0.3 * i, 0, 0.2))
		spin.append([ring, 0.4 + i * 0.25])


func _build_omega() -> void:
	var c: Color = spec["main"]
	var neon: Color = spec["neon"]
	var n2: Color = spec["neon2"]
	_robed(c, neon, 1.0)
	# Капюшон с маской Ω
	T.mi(T.sphere(0.27), T.mat(c.lightened(0.05)), head, Vector3(0, 0.03, -0.05), Vector3(1.0, 1.15, 1.05))
	T.mi(T.cyl(0.0, 0.2, 0.45, 10), T.mat(c.lightened(0.05)), head, Vector3(0, 0.25, -0.22), Vector3.ONE, Vector3(-1.0, 0, 0))
	T.mi(T.sphere(0.21), T.mat(Color(0.02, 0.02, 0.05)), head, Vector3(0, -0.02, 0.1), Vector3(0.9, 1.0, 0.75))
	T.mi(T.torus(0.07, 0.095), T.neon(neon, 4.0), head, Vector3(0, 0.0, 0.25), Vector3(1, 1, 1), Vector3(PI / 2.0, 0, 0))
	for sx in [-1.0, 1.0]:
		T.mi(T.box(0.05, 0.025, 0.02), T.neon(neon, 4.0), head, Vector3(sx * 0.08, -0.09, 0.25))
	# Наплечники-шипы
	for i in 2:
		var sx := -1.0 if i == 0 else 1.0
		T.mi(T.cyl(0.0, 0.12, 0.4, 6), T.mat(n2.darkened(0.3), 0.3, 0.8), sh[i], Vector3(sx * 0.08, 0.2, 0), Vector3.ONE, Vector3(0, 0, -sx * 0.5))
	T.mi(T.sphere(0.12), T.neon(neon, 3.0), spine, Vector3(0, 0.35, 0.22))
	# Парящие кольца-руны и осколки
	for i in 3:
		var ring := _node(self, Vector3(0, 1.4 + i * 0.25, 0))
		T.mi(T.torus(1.0 + i * 0.3, 1.05 + i * 0.3), T.neon(neon if i != 1 else n2, 2.0), ring, Vector3.ZERO, Vector3.ONE, Vector3(0.4 * (i - 1), 0, 0.25 * i))
		spin.append([ring, (0.5 + i * 0.3) * (-1.0 if i % 2 else 1.0)])
	var orb := _node(self, Vector3(0, 1.5, 0))
	for i in 6:
		var a := TAU * i / 6.0
		T.mi(T.sphere(0.07, 4), T.neon(n2, 3.0), orb, Vector3(cos(a) * 1.25, sin(a * 2.0) * 0.2, sin(a) * 1.25), Vector3(1, 1.8, 1))
	spin.append([orb, 0.7])
	if spec.get("chorus", false):
		# Хор: за спиной — нимб из множества ликов-огоньков
		var hal := _node(self, Vector3(0, 2.0, -0.6))
		for i in 14:
			var a := TAU * i / 14.0
			T.mi(T.sphere(0.09), T.neon(Color(1, 1, 1), 3.0), hal, Vector3(cos(a) * 1.4, sin(a) * 1.4, 0))
		T.mi(T.torus(1.35, 1.45), T.neon(n2, 2.5), hal, Vector3.ZERO, Vector3.ONE, Vector3(PI / 2.0, 0, 0))
		spin.append([hal, 0.0])


func _build_colossus() -> void:
	var c: Color = spec["main"]
	var neon: Color = spec["neon"]
	hips = _node(self, Vector3(0, 0.9, 0))
	T.mi(T.box(0.55, 0.25, 0.35), T.mat(c.darkened(0.2), 0.0, 0.7), hips, Vector3.ZERO)
	for i in 2:
		var sx := -1.0 if i == 0 else 1.0
		hip[i] = _node(hips, Vector3(sx * 0.2, -0.05, 0))
		T.mi(T.cyl(0.11, 0.09, 0.42), T.mat(c, 0.0, 0.7), hip[i], Vector3(0, -0.2, 0))
		kn[i] = _node(hip[i], Vector3(0, -0.4, 0))
		T.mi(T.sphere(0.12), T.mat(c.darkened(0.3), 0.0, 0.7), kn[i], Vector3.ZERO)
		T.mi(T.cyl(0.1, 0.14, 0.4), T.mat(c, 0.0, 0.7), kn[i], Vector3(0, -0.2, 0))
		T.mi(T.box(0.28, 0.1, 0.4), T.mat(c.darkened(0.2), 0.0, 0.7), kn[i], Vector3(0, -0.42, 0.06))
	spine = _node(hips, Vector3(0, 0.1, 0))
	T.mi(T.box(0.8, 0.6, 0.5), T.mat(c, 0.0, 0.7), spine, Vector3(0, 0.38, 0))
	T.mi(T.box(0.6, 0.25, 0.45), T.mat(c.darkened(0.15), 0.0, 0.7), spine, Vector3(0, 0.05, 0))
	T.mi(T.sphere(0.14), T.neon(neon, 4.0), spine, Vector3(0, 0.4, 0.25))
	T.mi(T.sphere(0.35), T.halo(Color(neon, 0.5), 1.5), spine, Vector3(0, 0.4, 0.3))
	T.mi(T.torus(0.15, 0.2), T.mat(Color(0.6, 0.6, 0.7), 0.0, 0.9), spine, Vector3(0, 0.4, 0.25), Vector3.ONE, Vector3(PI / 2.0, 0, 0))
	for i in 3:
		T.mi(T.box(0.06, 0.4, 0.04), T.neon(neon, 1.8), spine, Vector3(-0.3 + i * 0.3, 0.38, -0.26))
	for i in 2:
		var sx := -1.0 if i == 0 else 1.0
		sh[i] = _node(spine, Vector3(sx * 0.55, 0.55, 0))
		T.mi(T.sphere(0.24), T.mat(c.lightened(0.1), 0.0, 0.8), sh[i], Vector3.ZERO, Vector3(1.1, 0.9, 1.0))
		T.mi(T.box(0.06, 0.06, 0.3), T.neon(neon, 2.0), sh[i], Vector3(sx * 0.12, 0.18, 0))
		T.mi(T.cyl(0.1, 0.12, 0.45), T.mat(c, 0.0, 0.7), sh[i], Vector3(0, -0.25, 0))
		el[i] = _node(sh[i], Vector3(0, -0.45, 0))
		T.mi(T.cyl(0.18, 0.13, 0.5), T.mat(c.darkened(0.1), 0.0, 0.7), el[i], Vector3(0, -0.22, 0))
		var hnd := _node(el[i], Vector3(0, -0.52, 0))
		T.mi(T.box(0.3, 0.28, 0.3), T.mat(c.darkened(0.25), 0.0, 0.8), hnd, Vector3.ZERO)
		if i == 1:
			hand_r = hnd
		else:
			hand_l = hnd
	head = _node(spine, Vector3(0, 0.78, 0.08))
	T.mi(T.box(0.3, 0.22, 0.3), T.mat(c.lightened(0.05), 0.0, 0.8), head, Vector3.ZERO)
	T.mi(T.box(0.26, 0.05, 0.05), T.neon(neon, 4.0), head, Vector3(0, 0.02, 0.15))
	T.mi(T.cyl(0.0, 0.015, 0.3, 4), T.mat(Color(0.6, 0.6, 0.7)), head, Vector3(0.1, 0.25, 0))


func _build_queen() -> void:
	var c: Color = spec["main"]
	var neon: Color = spec["neon"]
	_build_spider()
	scale = Vector3.ONE
	var torso := _node(hips, Vector3(0, 0.25, 0.15))
	spine = torso
	T.mi(T.capsule(0.16, 0.6), T.mat(c.lightened(0.15), 0.0, 0.5), torso, Vector3(0, 0.25, 0), Vector3(1.1, 1, 0.8))
	T.mi(T.box(0.04, 0.4, 0.03), T.neon(neon, 2.5), torso, Vector3(0, 0.25, 0.13))
	for i in 2:
		var sx := -1.0 if i == 0 else 1.0
		sh[i] = _node(torso, Vector3(sx * 0.2, 0.45, 0))
		T.mi(T.capsule(0.045, 0.4), T.mat(c), sh[i], Vector3(0, -0.18, 0))
		el[i] = _node(sh[i], Vector3(0, -0.35, 0))
		T.mi(T.cyl(0.0, 0.05, 0.45, 6), T.mat(Color(0.35, 0.36, 0.44), 0.0, 0.7), el[i], Vector3(0, -0.22, 0))
		var w := _node(torso, Vector3(sx * 0.08, 0.4, -0.1))
		T.mi(T.box(0.9, 0.02, 0.35), T.glass(Color(neon.lightened(0.3), 0.3), 1.0), w, Vector3(sx * 0.45, 0.1, 0), Vector3.ONE, Vector3(0, 0, sx * 0.4))
		wings.append([w, sx])
	head = _node(torso, Vector3(0, 0.68, 0))
	T.mi(T.sphere(0.15), T.mat(Color(0.8, 0.7, 0.75), 0.0, 0.4), head, Vector3.ZERO, Vector3(0.9, 1.1, 0.95))
	for sx in [-1.0, 1.0]:
		T.mi(T.sphere(0.04), T.neon(neon, 4.0), head, Vector3(sx * 0.06, 0.02, 0.12), Vector3(1.3, 0.8, 0.6))
		T.mi(T.cyl(0.0, 0.03, 0.35, 6), T.mat(c), head, Vector3(sx * 0.08, 0.25, -0.05), Vector3.ONE, Vector3(-0.4, 0, -sx * 0.4))
	T.mi(T.cyl(0.13, 0.15, 0.08, 10), T.neon(neon, 2.0), head, Vector3(0, 0.14, 0))


# ================= Анимация =================

func set_mode(m: String) -> void:
	mode = m


func say(seconds: float) -> void:
	talking = seconds


func face(target: Vector3) -> void:
	var d := target - global_position
	rotation.y = atan2(d.x, d.z)


func _process(delta: float) -> void:
	_t += delta
	talking = maxf(0.0, talking - delta)
	walking = (global_position - _last_pos).length() / maxf(delta, 0.0001) > 0.25
	_last_pos = global_position
	# Моргание
	_blink -= delta
	var closed := _blink < 0.12
	if _blink < 0.0:
		_blink = randf_range(2.0, 4.5)
	for l in lids:
		(l as Node3D).scale.y = 1.15 if closed else 0.05
	# Рот при разговоре
	if mouth:
		var open := 0.0
		if talking > 0.0:
			open = absf(sin(_t * 13.0 + sin(_t * 5.0) * 2.0))
		mouth.scale.y = lerpf(mouth.scale.y, 0.6 + open * 2.6, 1.0 - exp(-20.0 * delta))
	for s in spin:
		var n: Node3D = s[0]
		if float(s[1]) != 0.0:
			n.rotation.y += float(s[1]) * delta
		else:
			n.scale = Vector3(1.0 + sin(_t * 3.0) * 0.06, 1.0 - sin(_t * 3.0) * 0.05, 1.0 + sin(_t * 3.0) * 0.06)
	for w in wings:
		var flap := sin(_t * (14.0 if flying else 3.0)) * (0.9 if flying else 0.25)
		(w[0] as Node3D).rotation.z = float(w[1]) * flap
	if flying and hips:
		hips.position.y = 1.4 + sin(_t * 3.0) * 0.1
	if floating and hips:
		hips.position.y = _hips_y_float() + sin(_t * 1.6 + _seed) * 0.08
	for lg in legs_extra:
		var p: Node3D = lg[0]
		var sx: float = lg[1]
		var j: int = lg[2]
		var ph := _t * (9.0 if walking else 1.5) + j * 1.3 + (0.0 if sx < 0 else PI)
		p.rotation.x = sin(ph) * (0.35 if walking else 0.05)
	_pose(delta)


func _hips_y_float() -> float:
	return 1.0 if spec["kind"] != "wraith" else 0.9


func _pose(delta: float) -> void:
	if hips == null:
		return
	var tg := {"sh0x": 0.1, "sh0z": -0.12, "sh1x": 0.1, "sh1z": 0.12, "el0": -0.2, "el1": -0.25,
		"hp0": 0.0, "hp1": 0.0, "kn0": 0.05, "kn1": 0.05, "spx": 0.0, "spy": 0.0, "hx": 0.0, "hy": 0.0, "dy": 0.0, "hz": 0.0}
	var br := sin(_t * 2.0 + _seed)
	tg["spx"] = br * 0.015
	tg["dy"] = br * 0.008
	match mode:
		"talk":
			tg["sh1x"] = -0.55 + sin(_t * 2.3) * 0.25
			tg["sh1z"] = 0.35
			tg["el1"] = -1.1 + sin(_t * 3.1) * 0.25
			tg["hy"] = sin(_t * 1.3) * 0.12
			tg["hx"] = sin(_t * 2.7) * 0.05
		"point":
			tg["sh1x"] = -1.5
			tg["sh1z"] = 0.1
			tg["el1"] = -0.05
			tg["spy"] = -0.2
		"stance":
			tg["sh1x"] = -0.9
			tg["sh1z"] = 0.3
			tg["el1"] = -1.3
			tg["sh0x"] = -0.6
			tg["sh0z"] = -0.35
			tg["el0"] = -1.1
			tg["hp0"] = -0.45
			tg["kn0"] = 0.6
			tg["hp1"] = 0.25
			tg["kn1"] = 0.35
			tg["dy"] = -0.08 + br * 0.01
			tg["spx"] = 0.12
		"cast":
			tg["sh0x"] = -2.4
			tg["sh1x"] = -2.4
			tg["sh0z"] = -0.4
			tg["sh1z"] = 0.4
			tg["el0"] = -0.3
			tg["el1"] = -0.3
			tg["hx"] = -0.25
			tg["spx"] = -0.1
		"cheer":
			var bo := absf(sin(_t * 6.0))
			tg["sh0x"] = -2.9
			tg["sh1x"] = -2.9
			tg["sh0z"] = -0.5
			tg["sh1z"] = 0.5
			tg["el0"] = -0.3
			tg["el1"] = -0.3
			tg["dy"] = bo * 0.12
			tg["hx"] = -0.3
		"kneel":
			tg["hp0"] = -1.55
			tg["kn0"] = 1.55
			tg["hp1"] = 0.15
			tg["kn1"] = 1.75
			tg["dy"] = -0.42
			tg["spx"] = 0.3
			tg["hx"] = 0.35
			tg["sh0x"] = -0.3
			tg["sh1x"] = -0.6
			tg["el1"] = -0.8
		"hurt":
			tg["spx"] = 0.5
			tg["hx"] = 0.4
			tg["sh0x"] = 0.4
			tg["sh1x"] = -0.8
			tg["el1"] = -1.6
			tg["dy"] = -0.1
		"roar":
			tg["spx"] = -0.25
			tg["hx"] = -0.45
			tg["sh0x"] = -0.6
			tg["sh1x"] = -0.6
			tg["sh0z"] = -1.1
			tg["sh1z"] = 1.1
			tg["el0"] = -0.9
			tg["el1"] = -0.9
			if mouth:
				mouth.scale.y = 3.0
		"look":
			tg["hy"] = 0.5
			tg["spy"] = 0.15
	if walking:
		var ph := _t * 9.0
		tg["hp0"] = sin(ph) * 0.55
		tg["hp1"] = -sin(ph) * 0.55
		tg["kn0"] = maxf(0.0, -sin(ph)) * 0.9 + 0.1
		tg["kn1"] = maxf(0.0, sin(ph)) * 0.9 + 0.1
		if mode != "stance":
			tg["sh0x"] = -sin(ph) * 0.45
			tg["sh1x"] = sin(ph) * 0.45 if mode != "point" else tg["sh1x"]
		tg["dy"] = absf(cos(ph)) * 0.05 - 0.02
		tg["spx"] = 0.08
	# Взгляд на цель
	if look_target != null and head:
		var lp: Vector3 = look_target
		var local := global_transform.affine_inverse() * lp
		var hp := head.global_position
		var lh := global_transform.affine_inverse() * hp
		var d: Vector3 = local - lh
		tg["hy"] = clampf(atan2(d.x, d.z), -0.9, 0.9)
		tg["hx"] = clampf(-atan2(d.y, Vector2(d.x, d.z).length()), -0.5, 0.5) + float(tg["hx"]) * 0.3
	var kk := 1.0 - exp(-9.0 * delta)
	for key2 in tg:
		_cur[key2] = lerpf(float(_cur.get(key2, tg[key2])), float(tg[key2]), kk)
	var C := _cur
	for i in 2:
		if sh[i]:
			(sh[i] as Node3D).rotation = Vector3(C["sh%dx" % i], 0, C["sh%dz" % i])
		if el[i]:
			(el[i] as Node3D).rotation.x = C["el%d" % i]
		if hip[i]:
			(hip[i] as Node3D).rotation.x = C["hp%d" % i]
		if kn[i]:
			(kn[i] as Node3D).rotation.x = C["kn%d" % i]
	if spine and spec["kind"] == "biped":
		spine.rotation.x = float(spec.get("hunch", 0.0)) + C["spx"]
		spine.rotation.y = C["spy"]
	if head:
		head.rotation = Vector3(C["hx"], C["hy"], 0)
	if not floating and not flying and spec["kind"] in ["biped", "boss_colossus"]:
		hips.position.y = _hips_y + C["dy"]
	if back_part:
		back_part.rotation.x = 0.05 + sin(_t * 1.7 + _seed) * 0.05 + (0.35 if walking else 0.0)
