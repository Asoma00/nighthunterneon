extends RefCounted
## Свой облик глав героев: твари глав (cmob~герой~вид), владыки глав (новые тела, а не
## перекраска общих боссов) и пол края. Всё рисуется кодом в пиксель-арте.

const P := preload("res://scripts/pixel.gd")

## Мотив края: что носят твари главы на голове и как они окрашены.
const MOTIF := {"vega": "mortar", "rin": "kabuto", "bram": "lamp", "kira": "visor", "skyla": "owl", "orm": "chimney",
	"mora": "hood", "zephyr": "horns", "iris": "gasmask", "lyra": "jester", "sol": "halo", "volt": "coil", "kai": "oni"}
const BODY := {"vega": Color(0.24, 0.18, 0.32), "rin": Color(0.32, 0.14, 0.16), "bram": Color(0.3, 0.22, 0.16),
	"kira": Color(0.1, 0.2, 0.2), "skyla": Color(0.26, 0.28, 0.34), "orm": Color(0.4, 0.26, 0.14),
	"mora": Color(0.2, 0.14, 0.26), "zephyr": Color(0.16, 0.24, 0.32), "iris": Color(0.18, 0.26, 0.12),
	"lyra": Color(0.34, 0.14, 0.28), "sol": Color(0.4, 0.34, 0.22), "volt": Color(0.14, 0.2, 0.28), "kai": Color(0.16, 0.16, 0.26)}
const GLOW := {"vega": Color(0.75, 0.45, 1.0), "rin": Color(1.0, 0.32, 0.45), "bram": Color(1.0, 0.6, 0.2),
	"kira": Color(0.25, 1.0, 0.8), "skyla": Color(0.8, 0.9, 1.0), "orm": Color(1.0, 0.75, 0.3),
	"mora": Color(0.8, 0.3, 1.0), "zephyr": Color(0.5, 0.85, 1.0), "iris": Color(0.6, 1.0, 0.25),
	"lyra": Color(1.0, 0.45, 0.85), "sol": Color(1.0, 0.9, 0.4), "volt": Color(0.3, 0.9, 1.0), "kai": Color(0.6, 0.6, 1.0)}

## Владыки глав: тело, головной убор, оружие.
const BOSS_LOOK := {
	"h000": ["specter", "mortar", "staff"], "h001": ["arachne", "hood", "book"], "h002": ["specter", "halo", "staff"],
	"h010": ["golem", "kabuto", "katana"], "h011": ["golem", "kabuto", "spear"], "h012": ["wyrm", "horns", ""],
	"h020": ["engine", "visor", "drill"], "h021": ["golem", "visor", "hammer"], "h022": ["wyrm", "horns", "wings"],
	"h030": ["arachne", "visor", ""], "h031": ["specter", "visor", "blades"], "h032": ["idol", "eye", ""],
	"h040": ["beast", "owl", ""], "h041": ["beast", "horns", ""], "h042": ["golem", "crown", "spear"],
	"h050": ["engine", "chimney", ""], "h051": ["specter", "crown", "staff"], "h052": ["golem", "crown", "hammer"],
	"h060": ["specter", "hood", "scythe"], "h061": ["specter", "veil", ""], "h062": ["specter", "mask", "scythe"],
	"h070": ["beast", "horns", ""], "h071": ["wyrm", "", "wings"], "h072": ["idol", "crown", ""],
	"h080": ["golem", "gasmask", "claws"], "h081": ["arachne", "horns", "claws"], "h082": ["arachne", "crown", ""],
	"h090": ["specter", "tophat", "staff"], "h091": ["specter", "mask", "blades"], "h092": ["idol", "tophat", ""],
	"h100": ["idol", "eye", ""], "h101": ["beast", "horns", ""], "h102": ["specter", "halo", "staff"],
	"h110": ["engine", "coil", "claws"], "h111": ["arachne", "coil", ""], "h112": ["golem", "coil", "hammer"],
	"h120": ["specter", "mask", ""], "h121": ["arachne", "mask", ""], "h122": ["golem", "oni", "katana"],
}
## Стражи залов — другое тело, чем у владыки.
const GUARD_FORM := {"specter": "golem", "golem": "beast", "wyrm": "arachne", "beast": "golem", "arachne": "specter",
	"idol": "specter", "engine": "golem"}


static func look_of(d: Dictionary) -> Array:
	var id := str(d.get("id", ""))
	if id.begins_with("g"):
		var base: Array = BOSS_LOOK.get(id.substr(1).get_slice("-", 0), ["golem", "", ""])
		return [GUARD_FORM.get(base[0], "golem"), base[1], "spear" if base[0] != "golem" else "claws"]
	return BOSS_LOOK.get(id, [])


# ========================= Твари глав =========================

static func paint_mob(key: String, b: Image, e: Image, f: int) -> void:
	var hero := key.get_slice("~", 1)
	var kind := key.get_slice("~", 2)
	var Ps := P._beast_pose(f)
	var s: float = Ps["s"]
	var a: float = Ps["a"]
	var hu: float = Ps["h"]
	var body: Color = BODY.get(hero, Color(0.25, 0.2, 0.3))
	var gl: Color = GLOW.get(hero, Color(1, 0.4, 0.8))
	var mo: String = MOTIF.get(hero, "")
	var w := b.get_width()
	var h := b.get_height()
	var cx := w * 0.5 + a * 1.5 - hu * 1.5
	var g := h - 2.0
	match kind:
		"imp", "bat":
			# Летун: тельце, машущие крылья, лапки
			var cy := h * 0.5 + s * 1.5
			var r := minf(w, h) * 0.2
			var wing := 3.0 + s * 4.0
			for d: float in [-1.0, 1.0]:
				P.poly(b, PackedVector2Array([Vector2(cx + d * r * 0.6, cy - 2), Vector2(cx + d * w * 0.48, cy - r - wing), Vector2(cx + d * w * 0.42, cy + 2), Vector2(cx + d * r, cy + r * 0.6)]), body.darkened(0.2))
				P.line(e, int(cx + d * r), int(cy - 1), int(cx + d * w * 0.46), int(cy - r - wing), Color(gl, 0.75))
			P.ellipse(b, cx, cy, r, r * 1.1, body)
			P.ellipse(b, cx, cy + r * 0.3, r * 0.6, r * 0.5, body.lightened(0.15))
			P._limb(b, Vector2(cx - 2, cy + r), Vector2(cx - 3, cy + r + 4), 1, body.darkened(0.3))
			P._limb(b, Vector2(cx + 2, cy + r), Vector2(cx + 3, cy + r + 4), 1, body.darkened(0.3))
			_eyes(e, cx + 1, cy - r * 0.2, gl)
			motif(b, e, mo, cx, cy - r * 0.7, r * 0.8, body, gl)
		"slime", "slimelet":
			var sq := 1.0 + s * 0.08 + hu * 0.1
			var rx := w * 0.42 * sq
			var ry := h * 0.32 / sq
			P.ellipse(b, cx, g - ry, rx, ry, body)
			P.ellipse(b, cx - rx * 0.3, g - ry * 1.3, rx * 0.35, ry * 0.3, body.lightened(0.25))
			P.ellipse(e, cx, g - ry, rx * 0.35, ry * 0.35, Color(gl, 0.5))
			_eyes(e, cx + 2, g - ry * 1.2, gl)
			motif(b, e, mo, cx, g - ry * 2.0, rx * 0.5, body, gl)
		"spider", "spiderling":
			var cy2 := g - h * 0.35
			for i in 3:
				for d: float in [-1.0, 1.0]:
					var ph := s * (1.0 if i % 2 == 0 else -1.0)
					var hip := Vector2(cx + d * 3, cy2)
					var knee := Vector2(cx + d * (w * 0.28 + i * 2), cy2 - 4 - i + ph * 1.5)
					var foot := Vector2(cx + d * (w * 0.42 + i), g - ph)
					P._limb(b, hip, knee, 1, body.darkened(0.2))
					P._limb(b, knee, foot, 1, body.darkened(0.3))
			P.ellipse(b, cx - 4, cy2, w * 0.2, h * 0.22, body)
			P.ellipse(e, cx - 4, cy2, w * 0.08, h * 0.08, Color(gl, 0.7))
			P.ellipse(b, cx + w * 0.12, cy2 - 1, w * 0.12, h * 0.15, body.lightened(0.1))
			_eyes(e, cx + w * 0.16, cy2 - 2, gl)
			motif(b, e, mo, cx + w * 0.12, cy2 - h * 0.15, w * 0.12, body, gl)
		"caster", "wraith":
			# Балахон, парит; руки с огнём
			var bob := s * 1.5
			var top := h * 0.32 + bob
			var hem := g - 2 + bob * 0.5
			var pts := PackedVector2Array([Vector2(cx - w * 0.16, top), Vector2(cx + w * 0.16, top), Vector2(cx + w * 0.3, hem)])
			for k in 5:
				pts.append(Vector2(cx + w * (0.3 - k * 0.15), hem - (3.0 if k % 2 == 1 else 0.0)))
			P.poly(b, pts, body)
			P.line(e, int(cx - w * 0.28), int(hem - 1), int(cx + w * 0.28), int(hem - 1), Color(gl, 0.6))
			P.ellipse(b, cx, top - 3, w * 0.15, w * 0.15, body.lightened(0.12))
			_eyes(e, cx + 1, top - 3, gl)
			var hand := Vector2(cx + w * 0.3, top + 6 - a * 6)
			P._limb(b, Vector2(cx + w * 0.12, top + 3), hand, 2, body.darkened(0.15))
			P.ellipse(e, hand.x, hand.y - 2, 2.0 + absf(a) * 1.5, 2.0 + absf(a) * 1.5, gl)
			motif(b, e, mo, cx, top - 6, w * 0.17, body, gl)
		"bomber":
			var cy3 := g - h * 0.38 + s
			var r3 := minf(w, h) * 0.32
			P.ellipse(b, cx, cy3, r3, r3, body)
			P.ellipse(b, cx - r3 * 0.35, cy3 - r3 * 0.35, r3 * 0.3, r3 * 0.3, body.lightened(0.3))
			P.line(b, int(cx + r3 * 0.5), int(cy3 - r3 * 0.8), int(cx + r3 * 0.8), int(cy3 - r3 * 1.2), Color(0.3, 0.25, 0.2))
			P.ellipse(e, cx + r3 * 0.85, cy3 - r3 * 1.25, 1.6 + (f % 2), 1.6 + (f % 2), Color(1.0, 0.8, 0.3))
			_eyes(e, cx + 2, cy3, gl)
			P._limb(b, Vector2(cx - 3, cy3 + r3), Vector2(cx - 4 - s * 2, g), 1, body.darkened(0.3))
			P._limb(b, Vector2(cx + 3, cy3 + r3), Vector2(cx + 4 + s * 2, g), 1, body.darkened(0.3))
			motif(b, e, mo, cx - 2, cy3 - r3 * 0.9, r3 * 0.6, body, gl)
		_:
			# Ходоки: гоблин, упырь, рыцарь, громила
			var big := kind == "brute"
			var hip := g - h * (0.32 if not big else 0.3)
			var sh := g - h * 0.62
			var tw := w * (0.2 if not big else 0.28)
			var lean := 2.0 if kind == "goblin" else 0.0
			for d: float in [-1.0, 1.0]:
				var stp := s * d * 3.0
				P._limb(b, Vector2(cx + d * tw * 0.5, hip), Vector2(cx + d * tw * 0.6 + stp, g), 2 if not big else 4, body.darkened(0.25))
			P.poly(b, PackedVector2Array([Vector2(cx - tw + lean, sh), Vector2(cx + tw + lean, sh), Vector2(cx + tw * 0.8, hip + 1), Vector2(cx - tw * 0.8, hip + 1)]), body)
			P.line(e, int(cx - tw * 0.5), int((sh + hip) * 0.5), int(cx + tw * 0.5), int((sh + hip) * 0.5), Color(gl, 0.7))
			var hr := w * (0.13 if not big else 0.12)
			var hx := cx + lean + 1
			var hy := sh - hr * 0.9
			P.ellipse(b, hx, hy, hr, hr, body.lightened(0.1))
			_eyes(e, hx + 1, hy, gl)
			# Руки: правая с оружием
			var hand := Vector2(cx + tw + 3 + a * 3, sh + 6 - a * 5)
			P._limb(b, Vector2(cx + tw * 0.8, sh + 2), hand, 2 if not big else 3, body.darkened(0.15))
			P._limb(b, Vector2(cx - tw * 0.8, sh + 2), Vector2(cx - tw - 1, sh + 8 + s), 2 if not big else 3, body.darkened(0.15))
			if kind == "knight":
				P.ellipse(b, cx - tw - 1, sh + 9, 4, 6, body.lightened(0.2))
				P.ellipse(e, cx - tw - 1, sh + 9, 1.5, 2.5, gl)
				P.line(e, int(hand.x), int(hand.y), int(hand.x + 2), int(hand.y - 10), gl)
			elif kind == "ghoul" or big:
				for k in 3:
					P.line(e, int(hand.x), int(hand.y), int(hand.x + 3), int(hand.y - 2 + k * 2), Color(gl, 0.8))
			else:
				P.line(b, int(hand.x), int(hand.y), int(hand.x + 4), int(hand.y - 5), Color(0.7, 0.7, 0.75))
			motif(b, e, mo, hx, hy - hr * 0.8, hr * 1.1, body, gl)


static func _eyes(e: Image, x: float, y: float, gl: Color) -> void:
	P.px(e, int(x) - 1, int(y), gl)
	P.px(e, int(x) + 2, int(y), gl)
	P.px(e, int(x) - 1, int(y) - 1, Color(gl, 0.5))
	P.px(e, int(x) + 2, int(y) - 1, Color(gl, 0.5))


## Головной убор / мотиф края. (x, y) — верх головы, r — радиус головы.
static func motif(b: Image, e: Image, mo: String, x: float, y: float, r: float, body: Color, gl: Color) -> void:
	r = maxf(r, 2.0)
	match mo:
		"mortar":  # шапочка Академии с кисточкой
			P.rect(b, int(x - r * 1.3), int(y - 1), int(r * 2.6) + 1, 2, Color(0.12, 0.1, 0.16))
			P.rect(b, int(x - r * 0.6), int(y - 1), int(r * 1.2) + 1, int(r * 0.6) + 2, Color(0.12, 0.1, 0.16))
			P.line(e, int(x + r * 1.2), int(y - 1), int(x + r * 1.3), int(y + r * 0.8), gl)
		"kabuto":  # шлем с рогами-кувагата
			P.ellipse(b, x, y + r * 0.3, r * 1.15, r * 0.6, Color(0.18, 0.12, 0.12))
			P.line(e, int(x - r * 0.3), int(y), int(x - r * 1.0), int(y - r * 1.2), gl)
			P.line(e, int(x + r * 0.3), int(y), int(x + r * 1.0), int(y - r * 1.2), gl)
		"lamp":  # каска рудокопа с фонарём
			P.ellipse(b, x, y + r * 0.3, r * 1.1, r * 0.6, Color(0.6, 0.48, 0.2))
			P.ellipse(e, x + r * 0.6, y + r * 0.1, maxf(1.0, r * 0.3), maxf(1.0, r * 0.3), Color(1.0, 0.95, 0.6))
		"visor":  # визор-экран
			P.rect(b, int(x - r), int(y + r * 0.5), int(r * 2) + 1, maxi(2, int(r * 0.6)), Color(0.05, 0.08, 0.08))
			P.line(e, int(x - r + 1), int(y + r * 0.7), int(x + r - 1), int(y + r * 0.7), gl)
		"owl":  # совиные ушки и большие глаза
			P.poly(b, PackedVector2Array([Vector2(x - r, y + r * 0.4), Vector2(x - r * 0.9, y - r * 0.8), Vector2(x - r * 0.3, y + r * 0.2)]), body.lightened(0.25))
			P.poly(b, PackedVector2Array([Vector2(x + r, y + r * 0.4), Vector2(x + r * 0.9, y - r * 0.8), Vector2(x + r * 0.3, y + r * 0.2)]), body.lightened(0.25))
			P.ellipse(e, x - r * 0.4, y + r * 0.8, maxf(1.0, r * 0.3), maxf(1.0, r * 0.3), Color(gl, 0.8))
			P.ellipse(e, x + r * 0.4, y + r * 0.8, maxf(1.0, r * 0.3), maxf(1.0, r * 0.3), Color(gl, 0.8))
		"chimney":  # медная труба с паром
			P.rect(b, int(x + r * 0.2), int(y - r * 1.1), maxi(2, int(r * 0.5)), int(r * 1.3), Color(0.6, 0.36, 0.18))
			P.px(e, int(x + r * 0.4), int(y - r * 1.4), Color(1.0, 0.8, 0.5, 0.7))
			P.ellipse(b, x, y + r * 0.35, r * 1.05, r * 0.45, Color(0.55, 0.34, 0.18))
		"hood":  # капюшон
			P.poly(b, PackedVector2Array([Vector2(x - r * 1.2, y + r * 1.6), Vector2(x, y - r * 0.9), Vector2(x + r * 1.2, y + r * 1.6), Vector2(x + r * 0.6, y + r * 0.6), Vector2(x - r * 0.6, y + r * 0.6)]), body.darkened(0.35))
		"horns":
			P.line(b, int(x - r * 0.6), int(y + r * 0.3), int(x - r * 1.3), int(y - r * 0.9), Color(0.75, 0.72, 0.65))
			P.line(b, int(x + r * 0.6), int(y + r * 0.3), int(x + r * 1.3), int(y - r * 0.9), Color(0.75, 0.72, 0.65))
			P.px(e, int(x - r * 1.3), int(y - r * 0.9), gl)
			P.px(e, int(x + r * 1.3), int(y - r * 0.9), gl)
		"gasmask":
			P.ellipse(b, x + r * 0.2, y + r * 1.3, r * 0.6, r * 0.5, Color(0.12, 0.14, 0.1))
			P.ellipse(e, x - r * 0.2, y + r * 0.8, maxf(1.0, r * 0.3), maxf(1.0, r * 0.25), gl)
			P.ellipse(e, x + r * 0.6, y + r * 0.8, maxf(1.0, r * 0.3), maxf(1.0, r * 0.25), gl)
		"jester", "tophat":
			if mo == "tophat":
				P.rect(b, int(x - r * 1.1), int(y), int(r * 2.2) + 1, 2, Color(0.1, 0.06, 0.1))
				P.rect(b, int(x - r * 0.65), int(y - r * 1.4), int(r * 1.3) + 1, int(r * 1.4) + 1, Color(0.12, 0.06, 0.12))
				P.line(e, int(x - r * 0.65), int(y - r * 0.3), int(x + r * 0.65), int(y - r * 0.3), gl)
			else:
				P.poly(b, PackedVector2Array([Vector2(x - r, y + r * 0.4), Vector2(x - r * 1.5, y - r * 0.8), Vector2(x, y), Vector2(x + r * 1.5, y - r * 0.8), Vector2(x + r, y + r * 0.4)]), Color(0.6, 0.12, 0.3))
				P.px(e, int(x - r * 1.5), int(y - r * 0.8), Color(1.0, 0.85, 0.3))
				P.px(e, int(x + r * 1.5), int(y - r * 0.8), Color(1.0, 0.85, 0.3))
		"halo":
			P.ellipse(e, x, y - r * 0.4, r * 1.3, r * 0.4, Color(gl, 0.8))
			P.ellipse(e, x, y - r * 0.4, r * 0.9, r * 0.2, Color(0, 0, 0, 0))
		"coil":
			P.line(b, int(x), int(y + r * 0.2), int(x), int(y - r * 1.3), Color(0.5, 0.5, 0.55))
			for k in 3:
				P.line(e, int(x - r * 0.4), int(y - r * 0.3 * k), int(x + r * 0.4), int(y - r * 0.3 * k - 1), gl)
			P.px(e, int(x), int(y - r * 1.5), Color(1, 1, 1))
		"oni":
			P.ellipse(b, x, y + r * 0.9, r * 0.95, r * 0.8, Color(0.85, 0.82, 0.78))
			P.line(b, int(x - r * 0.5), int(y + r * 0.2), int(x - r * 0.8), int(y - r * 0.4), Color(0.85, 0.82, 0.78))
			P.line(b, int(x + r * 0.5), int(y + r * 0.2), int(x + r * 0.8), int(y - r * 0.4), Color(0.85, 0.82, 0.78))
			P.px(e, int(x - r * 0.35), int(y + r * 0.8), Color(1.0, 0.25, 0.3))
			P.px(e, int(x + r * 0.35), int(y + r * 0.8), Color(1.0, 0.25, 0.3))
		"crown":
			for k in 4:
				var xx := x - r * 0.9 + k * r * 0.6
				P.line(b, int(xx), int(y + r * 0.2), int(xx), int(y - r * 0.6), Color(0.8, 0.65, 0.25))
				P.px(e, int(xx), int(y - r * 0.7), gl)
			P.line(b, int(x - r), int(y + r * 0.2), int(x + r), int(y + r * 0.2), Color(0.8, 0.65, 0.25))
		"mask":
			P.ellipse(b, x, y + r * 0.9, r * 0.9, r * 0.75, Color(0.9, 0.9, 0.92))
			P.line(e, int(x - r * 0.5), int(y + r * 0.8), int(x - r * 0.2), int(y + r * 0.8), gl)
			P.line(e, int(x + r * 0.2), int(y + r * 0.8), int(x + r * 0.5), int(y + r * 0.8), gl)
		"veil":
			P.poly(b, PackedVector2Array([Vector2(x - r * 0.9, y), Vector2(x + r * 0.9, y), Vector2(x + r * 2.0, y + r * 4.0), Vector2(x - r * 2.0, y + r * 4.0)]), Color(0.85, 0.8, 0.95, 0.85))
			P.line(e, int(x - r * 0.9), int(y), int(x + r * 0.9), int(y), gl)
		"eye":
			P.ellipse(b, x, y + r, r * 1.1, r * 0.7, Color(0.95, 0.92, 0.9))
			P.ellipse(e, x, y + r, r * 0.45, r * 0.45, gl)
			P.px(e, int(x), int(y + r), Color(0, 0, 0))


# ========================= Владыки глав =========================

static func paint_boss(d: Dictionary, b: Image, e: Image, f: int) -> void:
	var lk := look_of(d)
	if lk.is_empty():
		return
	var Ps: Dictionary = P._boss_pose(f)
	var body: Color = d.get("body", Color(0.25, 0.2, 0.3))
	var gl: Color = d.get("glow", Color(1, 0.4, 0.8))
	if str(d.get("id", "")).begins_with("g"):
		body = body.lightened(0.18)
		gl = Color.from_hsv(fposmod(gl.h + 0.08, 1.0), gl.s * 0.8, 1.0)
	match str(lk[0]):
		"specter":
			_b_specter(b, e, Ps, body, gl, lk)
		"golem":
			_b_golem(b, e, Ps, body, gl, lk)
		"wyrm":
			_b_wyrm(b, e, Ps, body, gl, lk, f)
		"beast":
			_b_beast(b, e, Ps, body, gl, lk)
		"arachne":
			_b_arachne(b, e, Ps, body, gl, lk)
		"idol":
			_b_idol(b, e, Ps, body, gl, lk, f)
		"engine":
			_b_engine(b, e, Ps, body, gl, lk, f)


static func _rage_glow(gl: Color, Ps: Dictionary) -> Color:
	return gl.lerp(Color(1.0, 0.25, 0.2), float(Ps["rg"]) * 0.5)


static func _weapon(b: Image, e: Image, wpn: String, hand: Vector2, ang: float, k: float, gl: Color, body: Color) -> void:
	var dir := Vector2.UP.rotated(ang)
	match wpn:
		"staff":
			P._limb(b, hand - dir * 14 * k, hand + dir * 26 * k, maxi(1, int(2 * k)), Color(0.3, 0.22, 0.18))
			P.ellipse(e, hand.x + dir.x * 29 * k, hand.y + dir.y * 29 * k, 4 * k, 4 * k, gl)
		"scythe":
			P._limb(b, hand - dir * 14 * k, hand + dir * 28 * k, maxi(1, int(2 * k)), Color(0.25, 0.2, 0.2))
			var tip := hand + dir * 28 * k
			var side := dir.orthogonal()
			P.poly(b, PackedVector2Array([tip, tip + side * 20 * k + dir * 4 * k, tip + side * 14 * k - dir * 3 * k]), Color(0.75, 0.75, 0.8))
			P.line(e, int(tip.x), int(tip.y), int(tip.x + side.x * 20 * k), int(tip.y + side.y * 20 * k), gl)
		"katana", "blades":
			P._limb(b, hand, hand + dir * 6 * k, maxi(1, int(2 * k)), Color(0.15, 0.1, 0.1))
			P._limb(e, hand + dir * 6 * k, hand + dir * 34 * k, maxi(1, int(1.5 * k)), Color(gl.lerp(Color.WHITE, 0.4), 1.0))
			if wpn == "blades":
				P._limb(e, hand + Vector2(-6, 4) * k, hand + Vector2(-6, 4) * k + dir.rotated(-0.5) * 24 * k, 1, gl)
		"spear":
			P._limb(b, hand - dir * 20 * k, hand + dir * 30 * k, maxi(1, int(2 * k)), Color(0.3, 0.25, 0.2))
			var t2 := hand + dir * 30 * k
			P.poly(e, PackedVector2Array([t2 + dir * 10 * k, t2 + dir.orthogonal() * 3 * k, t2 - dir.orthogonal() * 3 * k]), gl)
		"hammer":
			P._limb(b, hand - dir * 6 * k, hand + dir * 22 * k, maxi(2, int(3 * k)), Color(0.3, 0.22, 0.16))
			var hd := hand + dir * 24 * k
			P.ellipse(b, hd.x, hd.y, 11 * k, 7 * k, body.lightened(0.3))
			P.ellipse(e, hd.x, hd.y, 4 * k, 2 * k, gl)
		"drill":
			var t3 := hand + Vector2(30, -2) * k
			P.poly(b, PackedVector2Array([hand + Vector2(0, -8) * k, hand + Vector2(0, 8) * k, t3]), Color(0.55, 0.55, 0.6))
			for i in 3:
				var xx := hand.x + (6 + i * 7) * k
				P.line(e, int(xx), int(hand.y - (7 - i * 2) * k), int(xx + 3 * k), int(hand.y + (7 - i * 2) * k), gl)
		"claws":
			for i in 3:
				P._limb(e, hand, hand + dir.rotated(-0.4 + i * 0.4) * 12 * k, 1, gl)
		"book":
			P.rect(b, int(hand.x - 6 * k), int(hand.y - 8 * k), int(12 * k), int(9 * k), Color(0.35, 0.15, 0.2))
			P.line(e, int(hand.x - 4 * k), int(hand.y - 4 * k), int(hand.x + 4 * k), int(hand.y - 4 * k), gl)


static func _b_specter(b: Image, e: Image, Ps: Dictionary, body: Color, gl: Color, lk: Array) -> void:
	var w := float(b.get_width())
	var h := float(b.get_height())
	var k := h / 92.0
	var s: float = Ps["s"]
	var a: float = Ps["a"]
	var hu: float = Ps["hu"]
	var sp: float = Ps["sp"]
	gl = _rage_glow(gl, Ps)
	var cx := w * 0.46 - hu * 3.0
	var bob := s * 2.0 * k
	var sy := 34.0 * k + bob + hu * 2.0
	var hem := h - 10.0 * k + bob * 0.5
	# Шлейф-лохмотья
	var pts := PackedVector2Array([Vector2(cx - 13 * k, sy), Vector2(cx + 13 * k, sy), Vector2(cx + 24 * k, hem)])
	for i in 7:
		var x := cx + (24.0 - i * 8.0) * k
		pts.append(Vector2(x, hem + (6.0 if i % 2 == 1 else 0.0) * k + s * (1.0 if i % 2 == 0 else -1.0) * 2.0))
	pts.append(Vector2(cx - 24 * k, hem))
	P.poly(b, pts, body)
	P.poly(b, PackedVector2Array([Vector2(cx - 6 * k, sy + 2 * k), Vector2(cx + 6 * k, sy + 2 * k), Vector2(cx + 10 * k, hem - 4 * k), Vector2(cx - 10 * k, hem - 4 * k)]), body.lightened(0.12))
	P.line(e, int(cx - 22 * k), int(hem - 1), int(cx + 22 * k), int(hem - 1), Color(gl, 0.7))
	P.ellipse(e, cx, sy + 16 * k, 4 * k + sp * 3 * k, 4 * k + sp * 3 * k, gl)
	# Плечи и руки
	P.ellipse(b, cx - 12 * k, sy + 2 * k, 6 * k, 4 * k, body.lightened(0.2))
	P.ellipse(b, cx + 12 * k, sy + 2 * k, 6 * k, 4 * k, body.lightened(0.2))
	var hand := Vector2(cx + 24 * k + a * 4 * k, sy + 14 * k - a * 14 * k - sp * 10 * k)
	P._limb(b, Vector2(cx + 13 * k, sy + 3 * k), hand, maxi(2, int(3 * k)), body.darkened(0.1))
	var lhand := Vector2(cx - 22 * k, sy + 16 * k - sp * 16 * k)
	P._limb(b, Vector2(cx - 13 * k, sy + 3 * k), lhand, maxi(2, int(3 * k)), body.darkened(0.1))
	if sp > 0.3:
		P.ellipse(e, lhand.x, lhand.y, 3 * k * sp, 3 * k * sp, gl)
	_weapon(b, e, str(lk[2]), hand, 0.25 + a * 0.6, k, gl, body)
	# Голова
	var hx := cx + 2 * k
	var hy := sy - 9 * k
	P.ellipse(b, hx, hy, 8 * k, 9 * k, body.darkened(0.25))
	P.ellipse(b, hx + 1 * k, hy + 1 * k, 5.5 * k, 6 * k, Color(0.05, 0.04, 0.07))
	P.px(e, int(hx - 1 * k), int(hy), gl)
	P.px(e, int(hx + 3 * k), int(hy), gl)
	P.px(e, int(hx - 1 * k) + 1, int(hy), gl)
	P.px(e, int(hx + 3 * k) + 1, int(hy), gl)
	motif(b, e, str(lk[1]), hx, hy - 9 * k, 7 * k, body, gl)


static func _b_golem(b: Image, e: Image, Ps: Dictionary, body: Color, gl: Color, lk: Array) -> void:
	var w := float(b.get_width())
	var h := float(b.get_height())
	var k := h / 92.0
	var s: float = Ps["s"]
	var a: float = Ps["a"]
	var hu: float = Ps["hu"]
	var sp: float = Ps["sp"]
	gl = _rage_glow(gl, Ps)
	var cx := w * 0.48 - hu * 3.0
	var g := h - 3.0
	var hip := g - 26.0 * k
	var sh := hip - 30.0 * k + absf(s) * k
	var metal := body.lightened(0.18)
	# Ноги
	for d: float in [-1.0, 1.0]:
		var stp := s * d * 6.0 * k
		var knee := Vector2(cx + d * 10 * k + stp * 0.5, hip + 13 * k)
		P._limb(b, Vector2(cx + d * 9 * k, hip), knee, maxi(3, int(7 * k)), body.darkened(0.15))
		P._limb(b, knee, Vector2(cx + d * 11 * k + stp, g - 3 * k), maxi(3, int(6 * k)), body.darkened(0.25))
		P.ellipse(b, cx + d * 12 * k + stp, g - 2 * k, 7 * k, 3 * k, metal.darkened(0.2))
	# Торс
	P.poly(b, PackedVector2Array([Vector2(cx - 20 * k, sh), Vector2(cx + 20 * k, sh), Vector2(cx + 14 * k, hip), Vector2(cx - 14 * k, hip)]), body)
	P.rect(b, int(cx - 13 * k), int(hip - 4 * k), int(26 * k), int(6 * k), metal.darkened(0.1))
	P.ellipse(e, cx, sh + 12 * k, 5 * k + sp * 2 * k, 5 * k + sp * 2 * k, gl)
	P.ellipse(e, cx, sh + 12 * k, 2 * k, 2 * k, Color(1, 1, 0.9))
	for i in 3:
		P.line(e, int(cx - 12 * k), int(sh + (4 + i * 8) * k), int(cx - 7 * k), int(sh + (4 + i * 8) * k), Color(gl, 0.6))
	# Наплечники
	P.ellipse(b, cx - 21 * k, sh + 2 * k, 9 * k, 7 * k, metal)
	P.ellipse(b, cx + 21 * k, sh + 2 * k, 9 * k, 7 * k, metal)
	P.line(e, int(cx - 28 * k), int(sh + 3 * k), int(cx - 15 * k), int(sh + 3 * k), Color(gl, 0.7))
	P.line(e, int(cx + 15 * k), int(sh + 3 * k), int(cx + 28 * k), int(sh + 3 * k), Color(gl, 0.7))
	# Руки
	var hand := Vector2(cx + 28 * k + a * 6 * k, sh + 26 * k - a * 20 * k - sp * 8 * k)
	P._limb(b, Vector2(cx + 22 * k, sh + 6 * k), hand, maxi(3, int(7 * k)), body.darkened(0.1))
	P.ellipse(b, hand.x, hand.y, 5 * k, 5 * k, metal)
	var lh := Vector2(cx - 28 * k, sh + 28 * k - sp * 22 * k)
	P._limb(b, Vector2(cx - 22 * k, sh + 6 * k), lh, maxi(3, int(7 * k)), body.darkened(0.1))
	P.ellipse(b, lh.x, lh.y, 5 * k, 5 * k, metal)
	_weapon(b, e, str(lk[2]), hand, 0.3 + a * 0.7, k, gl, body)
	# Голова
	var hx := cx + 1 * k
	var hy := sh - 6 * k
	P.rect(b, int(hx - 7 * k), int(hy - 7 * k), int(14 * k), int(12 * k), body.lightened(0.08))
	P.line(e, int(hx - 4 * k), int(hy - 1 * k), int(hx + 5 * k), int(hy - 1 * k), gl)
	motif(b, e, str(lk[1]), hx, hy - 9 * k, 7 * k, body, gl)


static func _b_wyrm(b: Image, e: Image, Ps: Dictionary, body: Color, gl: Color, lk: Array, f: int) -> void:
	var w := float(b.get_width())
	var h := float(b.get_height())
	var k := h / 84.0
	var s: float = Ps["s"]
	var a: float = Ps["a"]
	var hu: float = Ps["hu"]
	var sp: float = Ps["sp"]
	gl = _rage_glow(gl, Ps)
	var ph := float(f) * 0.6
	if str(lk[2]) == "wings":
		var wf := s * 8.0 * k
		for d: float in [0.0, 1.0]:
			var root := Vector2(w * 0.45, h * 0.45)
			P.poly(b, PackedVector2Array([root, Vector2(w * (0.15 + d * 0.15), h * 0.08 - wf), Vector2(w * (0.05 + d * 0.2), h * 0.4 - wf * 0.5), Vector2(w * 0.35, h * 0.55)]), body.darkened(0.3 + d * 0.15))
			P.line(e, int(root.x), int(root.y), int(w * (0.15 + d * 0.15)), int(h * 0.08 - wf), Color(gl, 0.6))
	# Кольца тела: от хвоста (слева внизу) к голове (справа вверху)
	var n := 12
	var head := Vector2(w * 0.74 + a * 4 * k - hu * 4 * k, h * 0.34 - sp * 6 * k)
	for i in n:
		var t := float(i) / (n - 1)
		var p := Vector2(lerpf(w * 0.08, head.x - 10 * k, t), lerpf(h * 0.86, head.y + 14 * k, t * t) + sin(ph + t * 6.0) * 4.0 * k * (1.0 - t))
		var r := lerpf(4.0, 11.0, t) * k
		P.ellipse(b, p.x, p.y, r, r * 0.9, body if i % 2 == 0 else body.lightened(0.08))
		P.px(e, int(p.x), int(p.y - r * 0.8), gl)
		if i % 3 == 0:
			P.line(b, int(p.x), int(p.y - r), int(p.x - 2 * k), int(p.y - r - 4 * k), body.lightened(0.3))
	# Голова и пасть
	var jaw := maxf(a, sp) * 6.0 * k
	P.ellipse(b, head.x, head.y, 12 * k, 8 * k, body.lightened(0.1))
	P.poly(b, PackedVector2Array([head + Vector2(4, -3) * k, head + Vector2(20, 0) * k, head + Vector2(6, 4) * k]), body.lightened(0.15))
	P.poly(b, PackedVector2Array([head + Vector2(2, 4) * k, head + Vector2(18, 6) * k + Vector2(0, jaw), head + Vector2(4, 8) * k]), body)
	if jaw > 1.0:
		P.ellipse(e, head.x + 14 * k, head.y + 4 * k + jaw * 0.5, 4 * k, jaw * 0.5, gl)
	P.ellipse(e, head.x + 3 * k, head.y - 3 * k, 2 * k, 1.5 * k, gl)
	motif(b, e, str(lk[1]) if str(lk[1]) != "" else "horns", head.x - 2 * k, head.y - 6 * k, 7 * k, body, gl)
	# Лапы
	for d: float in [0.35, 0.6]:
		var lp := Vector2(w * d, h * 0.7)
		P._limb(b, lp, lp + Vector2(2 + s * 3, 18) * k, maxi(2, int(3 * k)), body.darkened(0.2))


static func _b_beast(b: Image, e: Image, Ps: Dictionary, body: Color, gl: Color, lk: Array) -> void:
	var w := float(b.get_width())
	var h := float(b.get_height())
	var k := h / 92.0
	var s: float = Ps["s"]
	var a: float = Ps["a"]
	var hu: float = Ps["hu"]
	var sp: float = Ps["sp"]
	gl = _rage_glow(gl, Ps)
	var g := h - 3.0
	var cy := g - 36.0 * k + absf(s) * 2 * k
	var cx := w * 0.46 - hu * 3 * k
	# Хвост
	P._limb(b, Vector2(cx - 26 * k, cy - 4 * k), Vector2(cx - 40 * k, cy - 14 * k + s * 4 * k), maxi(2, int(3 * k)), body.darkened(0.2))
	# Ноги (дальние темнее)
	for i in 4:
		var front := i >= 2
		var far := i % 2 == 0
		var ph := s * (1.0 if (i == 0 or i == 3) else -1.0)
		var hip := Vector2(cx + (18.0 if front else -18.0) * k, cy + 6 * k)
		var foot := Vector2(hip.x + ph * 7 * k, g - (1.0 if far else 0.0))
		P._limb(b, hip, (hip + foot) * 0.5 + Vector2(-3 * k, 0), maxi(3, int(6 * k)), body.darkened(0.3 if far else 0.12))
		P._limb(b, (hip + foot) * 0.5 + Vector2(-3 * k, 0), foot, maxi(2, int(5 * k)), body.darkened(0.35 if far else 0.18))
	# Тело
	P.ellipse(b, cx, cy, 30 * k, 15 * k, body)
	P.ellipse(b, cx + 10 * k, cy - 6 * k, 18 * k, 10 * k, body.lightened(0.1))
	for i in 4:
		P.line(e, int(cx - 18 * k + i * 9 * k), int(cy - 12 * k), int(cx - 14 * k + i * 9 * k), int(cy - 4 * k), Color(gl, 0.65))
	# Голова
	var hx := cx + 34 * k + a * 6 * k
	var hy := cy - 10 * k + a * 4 * k - sp * 6 * k
	P.ellipse(b, hx, hy, 12 * k, 10 * k, body.lightened(0.05))
	P.ellipse(b, hx + 9 * k, hy + 4 * k, 7 * k, 5 * k, body.lightened(0.15))
	P.ellipse(e, hx + 3 * k, hy - 3 * k, 2 * k, 1.5 * k, gl)
	if a > 0.5 or sp > 0.5:
		P.line(e, int(hx + 6 * k), int(hy + 7 * k), int(hx + 15 * k), int(hy + 7 * k), gl)
	motif(b, e, str(lk[1]), hx, hy - 9 * k, 9 * k, body, gl)


static func _b_arachne(b: Image, e: Image, Ps: Dictionary, body: Color, gl: Color, lk: Array) -> void:
	var w := float(b.get_width())
	var h := float(b.get_height())
	var k := h / 84.0
	var s: float = Ps["s"]
	var a: float = Ps["a"]
	var hu: float = Ps["hu"]
	var sp: float = Ps["sp"]
	gl = _rage_glow(gl, Ps)
	var g := h - 3.0
	var cx := w * 0.42 - hu * 3 * k
	var cy := g - 26 * k
	# Ноги: по 4 с каждой стороны
	for i in 4:
		for d: float in [-1.0, 1.0]:
			var ph := s * (1.0 if (i % 2 == 0) == (d > 0) else -1.0)
			var hip := Vector2(cx + (i - 1.5) * 6 * k, cy)
			var knee := Vector2(hip.x + d * (12 + i * 3) * k, cy - 16 * k + ph * 3 * k)
			var foot := Vector2(hip.x + d * (24 + i * 4) * k + ph * 3 * k, g - (2.0 if d < 0 else 0.0))
			var c := body.darkened(0.3 if d < 0 else 0.12)
			P._limb(b, hip, knee, maxi(2, int(3 * k)), c)
			P._limb(b, knee, foot, maxi(1, int(2 * k)), c.darkened(0.1))
	# Брюшко
	P.ellipse(b, cx - 14 * k, cy - 2 * k, 18 * k, 13 * k, body)
	for i in 3:
		P.ellipse(e, cx - 18 * k + i * 5 * k, cy - 4 * k + (i % 2) * 4 * k, 2 * k, 2 * k, Color(gl, 0.8))
	# Торс
	var tx := cx + 12 * k
	var ty := cy - 22 * k - sp * 4 * k
	P.poly(b, PackedVector2Array([Vector2(tx - 8 * k, cy - 2 * k), Vector2(tx + 8 * k, cy - 2 * k), Vector2(tx + 10 * k, ty), Vector2(tx - 9 * k, ty)]), body.lightened(0.1))
	P.ellipse(e, tx, ty + 10 * k, 3 * k, 3 * k, gl)
	var hand := Vector2(tx + 18 * k + a * 4 * k, ty + 8 * k - a * 12 * k)
	P._limb(b, Vector2(tx + 8 * k, ty + 2 * k), hand, maxi(2, int(3 * k)), body)
	P._limb(b, Vector2(tx - 8 * k, ty + 2 * k), Vector2(tx - 16 * k, ty + 10 * k - sp * 12 * k), maxi(2, int(3 * k)), body.darkened(0.1))
	_weapon(b, e, str(lk[2]), hand, 0.4 + a * 0.6, k, gl, body)
	var hx := tx + 1 * k
	var hy := ty - 6 * k
	P.ellipse(b, hx, hy, 7 * k, 7 * k, body.lightened(0.15))
	for i in 3:
		P.px(e, int(hx - 2 * k + i * 2 * k), int(hy), gl)
	motif(b, e, str(lk[1]), hx, hy - 7 * k, 7 * k, body, gl)


static func _b_idol(b: Image, e: Image, Ps: Dictionary, body: Color, gl: Color, lk: Array, f: int) -> void:
	var w := float(b.get_width())
	var h := float(b.get_height())
	var k := h / 108.0
	var s: float = Ps["s"]
	var a: float = Ps["a"]
	var sp: float = Ps["sp"]
	gl = _rage_glow(gl, Ps)
	var cx := w * 0.5
	var cy := h * 0.45 + s * 3 * k
	var rot := float(f) * 0.35
	# Кабели-щупальца внизу
	for i in 5:
		var x0 := cx + (i - 2) * 8 * k
		var pts: Array = []
		for j in 6:
			pts.append(Vector2(x0 + sin(rot + i + j * 0.8) * 4 * k, cy + 22 * k + j * 7 * k))
		for j in 5:
			P._limb(b, pts[j], pts[j + 1], maxi(1, int(3 * k) - j / 2), body.darkened(0.2))
		P.px(e, int(pts[5].x), int(pts[5].y), gl)
	# Пластины вокруг
	for i in 6:
		var an := rot + TAU * i / 6.0
		var r := (32.0 + sp * 8.0 + a * 3.0) * k
		var p := Vector2(cx + cos(an) * r, cy + sin(an) * r * 0.55)
		P.poly(b, PackedVector2Array([p + Vector2(-5, -7) * k, p + Vector2(5, -7) * k, p + Vector2(7, 6) * k, p + Vector2(-7, 6) * k]), body.lightened(0.15))
		P.line(e, int(p.x - 3 * k), int(p.y), int(p.x + 3 * k), int(p.y), Color(gl, 0.75))
	# Ядро
	P.ellipse(b, cx, cy, 22 * k, 22 * k, body)
	P.ellipse(b, cx - 6 * k, cy - 7 * k, 8 * k, 6 * k, body.lightened(0.18))
	P.ellipse(e, cx, cy, 22 * k, 22 * k, Color(gl, 0.18))
	P.ellipse(e, cx, cy, (9.0 + sp * 3.0) * k, (9.0 + sp * 3.0) * k, gl)
	P.ellipse(e, cx, cy, 3 * k, 5 * k, Color(0.05, 0.02, 0.05))
	motif(b, e, str(lk[1]) if str(lk[1]) != "eye" else "halo", cx, cy - 26 * k, 12 * k, body, gl)


static func _b_engine(b: Image, e: Image, Ps: Dictionary, body: Color, gl: Color, lk: Array, f: int) -> void:
	var w := float(b.get_width())
	var h := float(b.get_height())
	var k := h / 92.0
	var s: float = Ps["s"]
	var a: float = Ps["a"]
	var hu: float = Ps["hu"]
	var sp: float = Ps["sp"]
	gl = _rage_glow(gl, Ps)
	var g := h - 3.0
	var cx := w * 0.46 - hu * 3 * k
	# Гусеницы
	P.rect(b, int(cx - 34 * k), int(g - 14 * k), int(66 * k), int(13 * k), Color(0.12, 0.11, 0.12))
	for i in 6:
		P.ellipse(b, cx - 28 * k + i * 11 * k, g - 7 * k, 4.5 * k, 4.5 * k, Color(0.3, 0.3, 0.32))
		P.px(e, int(cx - 28 * k + i * 11 * k + ((f + i) % 3) - 1), int(g - 7 * k), Color(gl, 0.6))
	# Котёл-корпус
	var top := g - 58 * k + s * k
	P.ellipse(b, cx, g - 34 * k, 30 * k, 24 * k, body)
	P.rect(b, int(cx - 30 * k), int(g - 34 * k), int(60 * k), int(20 * k), body)
	P.ellipse(b, cx - 8 * k, g - 46 * k, 12 * k, 8 * k, body.lightened(0.2))
	for i in 5:
		P.px(b, int(cx - 24 * k + i * 12 * k), int(g - 22 * k), body.lightened(0.4))
	# Манометр-лицо
	P.ellipse(b, cx + 12 * k, g - 36 * k, 9 * k, 9 * k, Color(0.85, 0.8, 0.7))
	P.ellipse(e, cx + 12 * k, g - 36 * k, 6 * k, 6 * k, Color(gl, 0.6))
	var nd := Vector2.UP.rotated(-1.0 + float(Ps["rg"]) * 2.0 + a * 0.5) * 6 * k
	P.line(e, int(cx + 12 * k), int(g - 36 * k), int(cx + 12 * k + nd.x), int(g - 36 * k + nd.y), Color(1, 0.3, 0.2))
	# Труба с паром/огнём
	P.rect(b, int(cx - 18 * k), int(top - 10 * k), int(8 * k), int(16 * k), body.darkened(0.2))
	P.ellipse(e, cx - 14 * k, top - 12 * k - (f % 3) * 2 * k, (3.0 + sp * 3.0) * k, (3.0 + sp * 3.0) * k, Color(gl, 0.8))
	# Рука-орудие спереди
	var hand := Vector2(cx + 34 * k + a * 6 * k, g - 30 * k - a * 6 * k)
	P._limb(b, Vector2(cx + 24 * k, g - 30 * k), hand, maxi(3, int(6 * k)), body.darkened(0.1))
	_weapon(b, e, str(lk[2]) if str(lk[2]) != "" else "claws", hand, 1.4 + a * 0.4, k, gl, body)
	motif(b, e, str(lk[1]), cx + 2 * k, g - 60 * k + s * k, 9 * k, body, gl)


# ========================= Пол края =========================

## Плитка пола главы: свой рисунок для каждого героя.
static func ground(hero: String) -> Dictionary:
	return P.EnvironmentArt.floor_art(P.EnvironmentArt.CHAPTER_FLOOR.get(hero, "slate"))
