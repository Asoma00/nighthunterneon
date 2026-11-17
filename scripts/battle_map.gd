extends Control
## Карта боя: найденные тайники, загадки, алтари и прочие места — у каждого свой значок.
## Режим «pause» — плотная, игра стоит; «overlay» — полупрозрачная поверх боя, бой идёт.

var main: Node
var marks: Dictionary = {}     # id -> {pos, kind, title, color, done}
var overlay := false
var _font: Font

const CYAN := Color(0.3, 0.95, 1.0)
const GOLD := Color(1.0, 0.8, 0.3)

## Группы для легенды: какие виды в какую строку
const GROUPS := [
	["Тайники", ["cache"]],
	["Загадки", ["puzzle", "lamps", "simon"]],
	["Алтари", ["power", "trial", "spring", "mob_altar"]],
	["Маяки", ["beacons"]],
	["Пленники", ["captive"]],
	["Части оружия", ["part"]],
	["Память", ["memory"]],
]
const KIND_COLOR := {
	"cache": Color(1.0, 0.78, 0.3), "puzzle": Color(0.55, 0.7, 1.0), "lamps": Color(1.0, 0.65, 0.3),
	"simon": Color(0.45, 0.9, 1.0), "power": Color(1.0, 0.45, 0.2), "trial": Color(0.8, 0.5, 1.0),
	"spring": Color(0.35, 1.0, 0.6), "mob_altar": Color(1.0, 0.25, 0.3), "beacons": Color(0.4, 1.0, 0.85),
	"captive": Color(1.0, 0.85, 0.5), "part": Color(1.0, 0.6, 0.25), "memory": Color(0.75, 0.6, 1.0),
}


func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_d: float) -> void:
	if visible:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# Касание или щелчок по плотной карте — закрыть (на телефоне это главный способ)
	if not overlay and ((event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed)):
		accept_event()
		var hud = get_parent()
		if hud != null and hud.has_method("toggle_map"):
			hud.toggle_map()


func _me() -> Node2D:
	if main.net_mode == "client" and main.my_idx < main.players.size():
		return main.players[main.my_idx]
	return main.player


func _draw() -> void:
	if main == null or not is_instance_valid(main):
		return
	var vs := size
	var portrait := vs.y > vs.x
	var a_bg := 0.6 if overlay else 0.93
	if not overlay:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.0, 0.06, 0.88))
	# Окно карты
	var pad := 28.0 if portrait else 60.0
	var top := 92.0 if portrait else 70.0
	var legend_h := 170.0 if portrait else 96.0
	var r := Rect2(Vector2(pad, top), Vector2(vs.x - pad * 2.0, vs.y - top - legend_h - 24.0))
	if overlay:
		# Поверх боя — компактнее и в стороне от центра, где герой
		var w := minf(vs.x * (0.9 if portrait else 0.46), 760.0)
		var h := minf(vs.y * (0.5 if portrait else 0.62), 560.0)
		r = Rect2(Vector2(vs.x - w - (16.0 if portrait else 24.0), (130.0 if portrait else 90.0)), Vector2(w, h))
		legend_h = 0.0
	draw_rect(r, Color(0.03, 0.02, 0.09, a_bg))
	draw_rect(r, Color(CYAN, 0.85 if not overlay else 0.6), false, 2.0)
	# Заголовок
	var title := "КАРТА"
	var hint := _hint()
	var tfs := 34 if not overlay else 20
	var ty := r.position.y - 14.0 if not overlay else r.position.y + 24.0
	var tx := r.position.x + (0.0 if not overlay else 12.0)
	_text(Vector2(tx, ty), title, tfs, Color.WHITE, CYAN)
	_text(Vector2(tx + _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x + 18.0, ty - 2.0), hint, 15 if not overlay else 12, Color(0.8, 0.85, 1.0))
	# Масштаб: герой в центре, все найденные места помещаются
	var me := _me()
	if me == null or not is_instance_valid(me):
		return
	var c: Vector2 = me.position
	var span := 2600.0
	for id in marks:
		var d: Vector2 = (marks[id]["pos"] as Vector2) - c
		span = maxf(span, maxf(absf(d.x) * r.size.y / maxf(r.size.x, 1.0), absf(d.y)) * 2.0 * 1.18)
	var inner := r.grow(-18.0)
	if overlay:
		inner.position.y += 22.0
		inner.size.y -= 22.0
	var k := inner.size.y / span
	var mc := inner.get_center()
	# Сетка: клетка 10 м
	var step := 1000.0
	while step * k < 46.0:
		step *= 2.0
	var gcol := Color(CYAN, 0.10 if overlay else 0.14)
	var x0 := floorf((c.x - inner.size.x / k / 2.0) / step) * step
	var x := x0
	while x < c.x + inner.size.x / k / 2.0:
		var sx := mc.x + (x - c.x) * k
		if sx > inner.position.x and sx < inner.end.x:
			draw_line(Vector2(sx, inner.position.y), Vector2(sx, inner.end.y), gcol, 1.0)
		x += step
	var y := floorf((c.y - inner.size.y / k / 2.0) / step) * step
	while y < c.y + inner.size.y / k / 2.0:
		var sy := mc.y + (y - c.y) * k
		if sy > inner.position.y and sy < inner.end.y:
			draw_line(Vector2(inner.position.x, sy), Vector2(inner.end.x, sy), gcol, 1.0)
		y += step
	_text(Vector2(inner.end.x - 90.0, inner.end.y - 6.0), "клетка %d м" % int(step / 100.0), 12, Color(0.7, 0.8, 0.95))
	# Отметки: сначала значки, потом подписи — подпись ставим туда, где она ни с чем не
	# пересекается (справа, слева, сверху, снизу); не влезла — остаётся только значок
	var isz := 15.0 if not overlay else 12.0
	var fs_l := 13 if not overlay else 11
	var ids := marks.keys()
	ids.sort_custom(func(a, b): return (marks[a]["pos"] as Vector2).distance_squared_to(c) < (marks[b]["pos"] as Vector2).distance_squared_to(c))
	var taken: Array = []
	var spots := {}
	for id in ids:
		var p: Vector2 = mc + ((marks[id]["pos"] as Vector2) - c) * k
		p = Vector2(clampf(p.x, inner.position.x + isz, inner.end.x - isz), clampf(p.y, inner.position.y + isz, inner.end.y - isz))
		spots[id] = p
		taken.append(Rect2(p - Vector2(isz + 3, isz + 3), Vector2(isz + 3, isz + 3) * 2.0))
	taken.append(Rect2(mc - Vector2(14, 14), Vector2(28, 28)))   # герой в центре
	for id in ids:
		var m: Dictionary = marks[id]
		var p: Vector2 = spots[id]
		_icon(p, str(m["kind"]), isz, bool(m["done"]))
		var lbl: String = str(m["title"]) + ("  ✓" if m["done"] else "  %dм" % int(((m["pos"] as Vector2) - c).length() / 100.0))
		var tw := _font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_l).x
		var th := float(fs_l) + 4.0
		var opts := [Vector2(isz + 6.0, -th * 0.5), Vector2(-isz - 6.0 - tw, -th * 0.5),
			Vector2(-tw * 0.5, -isz - 6.0 - th), Vector2(-tw * 0.5, isz + 6.0)]
		for o in opts:
			var rr := Rect2(p + o, Vector2(tw, th))
			if not inner.encloses(rr):
				continue
			var hit := false
			for t in taken:
				if t.intersects(rr) and not t.has_point(p):
					hit = true
					break
			if hit:
				continue
			taken.append(rr)
			_text(rr.position + Vector2(0, th - 4.0), lbl, fs_l, Color(_kcol(str(m["kind"])), 0.6 if m["done"] else 1.0))
			break
	# Герои
	for i in main.players.size():
		var pl: Node2D = main.players[i]
		if not is_instance_valid(pl):
			continue
		var pp: Vector2 = mc + (pl.position - c) * k
		pp = Vector2(clampf(pp.x, inner.position.x + 8, inner.end.x - 8), clampf(pp.y, inner.position.y + 8, inner.end.y - 8))
		var col: Color = pl.player_color() if pl.has_method("player_color") else CYAN
		var aim: Vector2 = pl.get("aim") if pl.get("aim") != null and (pl.get("aim") as Vector2) != Vector2.ZERO else Vector2.UP
		var dir := aim.normalized()
		var tri := PackedVector2Array([pp + dir * 13.0, pp + dir.rotated(2.45) * 10.0, pp + dir.rotated(-2.45) * 10.0])
		draw_colored_polygon(tri, Color(0.02, 0.0, 0.05))
		var tri2 := PackedVector2Array([pp + dir * 10.0, pp + dir.rotated(2.45) * 7.5, pp + dir.rotated(-2.45) * 7.5])
		draw_colored_polygon(tri2, col)
	if marks.is_empty():
		var msg := "Пока ничего не найдено — тайники, загадки и алтари появятся здесь"
		var fs := 15 if not overlay else 12
		var w := _font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_text(Vector2(mc.x - minf(w, inner.size.x - 20) / 2.0, inner.end.y - 34.0), msg, fs, Color(0.75, 0.75, 0.9), Color(0, 0, 0, 0), inner.size.x - 20)
	if not overlay:
		var lr := Rect2(Vector2(pad, r.end.y + 12.0), Vector2(vs.x - pad * 2.0, legend_h))
		draw_rect(lr, Color(0.03, 0.02, 0.09, 0.93))
		draw_rect(lr, Color(CYAN, 0.35), false, 1.0)
		_legend(lr, portrait)


func _hint() -> String:
	if Settings.input_mode() == "touch":
		return "коснитесь, чтобы закрыть" if not overlay else "КАРТА — скрыть"
	return "%s — закрыть" % Settings.key("map")


func _kcol(kind: String) -> Color:
	return KIND_COLOR.get(kind, Color.WHITE)


func _legend(r: Rect2, portrait: bool) -> void:
	var cols := 2 if portrait else 4
	var cw := r.size.x / cols
	var i := 0
	for g in GROUPS:
		var n := 0
		var done := 0
		for id in marks:
			if str(marks[id]["kind"]) in g[1]:
				n += 1
				if marks[id]["done"]:
					done += 1
		var p := r.position + Vector2(cw * (i % cols) + 16.0, 22.0 + 38.0 * (i / cols))
		_icon(p, g[1][0], 12.0, false)
		var txt := "%s: %d" % [g[0], n] + ("  (✓ %d)" % done if done > 0 else "")
		_text(p + Vector2(20.0, 6.0), txt, 15, Color(0.88, 0.9, 1.0) if n > 0 else Color(0.55, 0.55, 0.7))
		i += 1


func _text(p: Vector2, s: String, fs: int, col: Color, glow := Color(0, 0, 0, 0), w := -1.0) -> void:
	# Тёмная обводка — текст читается и поверх боя
	draw_string_outline(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, w, fs, 6, Color(0.02, 0.0, 0.06, 0.95))
	if glow.a > 0.0:
		draw_string_outline(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, w, fs, 10, Color(glow, 0.35))
	draw_string(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, w, fs, col)


## Значок вида места. Рисуется векторами — не зависит от шрифта.
func _icon(p: Vector2, kind: String, s: float, done: bool) -> void:
	var col := _kcol(kind)
	var a := 0.5 if done else 1.0
	draw_circle(p, s + 3.0, Color(0.02, 0.0, 0.06, 0.92 * (0.8 if done else 1.0)))
	draw_arc(p, s + 3.0, 0.0, TAU, 28, Color(col, 0.9 * a), 2.0, true)
	var c := Color(col, a)
	var dk := Color(0.02, 0.0, 0.06, a)
	match kind:
		"cache":   # сундучок
			draw_rect(Rect2(p + Vector2(-s * 0.62, -s * 0.2), Vector2(s * 1.24, s * 0.72)), c)
			draw_rect(Rect2(p + Vector2(-s * 0.62, -s * 0.55), Vector2(s * 1.24, s * 0.32)), c.lightened(0.25))
			draw_line(p + Vector2(-s * 0.62, -s * 0.2), p + Vector2(s * 0.62, -s * 0.2), dk, 1.5)
			draw_rect(Rect2(p + Vector2(-s * 0.12, -s * 0.3), Vector2(s * 0.24, s * 0.3)), dk)
		"puzzle", "lamps", "simon":   # рунный ромб со знаком вопроса
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s * 0.8), p + Vector2(s * 0.7, 0), p + Vector2(0, s * 0.8), p + Vector2(-s * 0.7, 0)]), c)
			var q := "?"
			var fs := int(s * 1.1)
			var w := _font.get_string_size(q, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(_font, p + Vector2(-w / 2.0, fs * 0.36), q, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dk)
		"power", "trial", "spring":   # алтарь: постамент и огонь/звезда/капля
			draw_rect(Rect2(p + Vector2(-s * 0.6, s * 0.25), Vector2(s * 1.2, s * 0.35)), c.darkened(0.2))
			draw_rect(Rect2(p + Vector2(-s * 0.35, -s * 0.05), Vector2(s * 0.7, s * 0.32)), c.darkened(0.1))
			if kind == "power":
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s * 0.85), p + Vector2(s * 0.32, -s * 0.15), p + Vector2(-s * 0.32, -s * 0.15)]), c.lightened(0.3))
			elif kind == "trial":
				for i in 5:
					var ang := -PI / 2.0 + TAU * i / 5.0
					draw_line(p + Vector2(0, -s * 0.45), p + Vector2(0, -s * 0.45) + Vector2.RIGHT.rotated(ang) * s * 0.42, c.lightened(0.3), 2.0)
			else:
				draw_circle(p + Vector2(0, -s * 0.35), s * 0.24, c.lightened(0.3))
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s * 0.85), p + Vector2(s * 0.22, -s * 0.42), p + Vector2(-s * 0.22, -s * 0.42)]), c.lightened(0.3))
		"mob_altar":   # тёмный обелиск с шипами
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s * 0.85), p + Vector2(s * 0.35, s * 0.6), p + Vector2(-s * 0.35, s * 0.6)]), c)
			draw_line(p + Vector2(-s * 0.6, -s * 0.2), p + Vector2(-s * 0.25, 0), c, 2.0)
			draw_line(p + Vector2(s * 0.6, -s * 0.2), p + Vector2(s * 0.25, 0), c, 2.0)
			draw_circle(p + Vector2(0, s * 0.05), s * 0.13, dk)
		"beacons":   # маяк с волнами
			draw_colored_polygon(PackedVector2Array([p + Vector2(-s * 0.18, -s * 0.4), p + Vector2(s * 0.18, -s * 0.4), p + Vector2(s * 0.3, s * 0.7), p + Vector2(-s * 0.3, s * 0.7)]), c)
			draw_arc(p + Vector2(0, -s * 0.45), s * 0.45, -PI * 0.85, -PI * 0.15, 10, c, 2.0)
		"captive":   # фигурка
			draw_circle(p + Vector2(0, -s * 0.45), s * 0.26, c)
			draw_colored_polygon(PackedVector2Array([p + Vector2(-s * 0.4, s * 0.65), p + Vector2(s * 0.4, s * 0.65), p + Vector2(s * 0.22, -s * 0.12), p + Vector2(-s * 0.22, -s * 0.12)]), c)
		"part":   # шестерня
			for i in 8:
				var ang := TAU * i / 8.0
				draw_line(p, p + Vector2.RIGHT.rotated(ang) * s * 0.72, c, 3.0)
			draw_circle(p, s * 0.48, c)
			draw_circle(p, s * 0.2, dk)
		"memory":   # кристалл
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s * 0.85), p + Vector2(s * 0.42, -s * 0.1), p + Vector2(0, s * 0.8), p + Vector2(-s * 0.42, -s * 0.1)]), c)
			draw_line(p + Vector2(0, -s * 0.85), p + Vector2(0, s * 0.8), c.lightened(0.4), 1.0)
		_:
			draw_circle(p, s * 0.5, c)
	if done:
		draw_line(p + Vector2(-s * 0.45, 0), p + Vector2(-s * 0.1, s * 0.4), Color(0.4, 1.0, 0.5), 3.0)
		draw_line(p + Vector2(-s * 0.1, s * 0.4), p + Vector2(s * 0.55, -s * 0.45), Color(0.4, 1.0, 0.5), 3.0)
