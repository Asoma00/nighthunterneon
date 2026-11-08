extends Control
## Дерево прокачки сверху вниз: ярус 1 — верхний ряд, ниже — более сильные узлы.
## Состояния узла: изучен, доступен, дорого, закрыт предыдущими, нужен уровень здания,
## не выполнено условие (достижение).

const Meta := preload("res://scripts/meta.gd")
const Pixel := preload("res://scripts/pixel.gd")

signal bought
signal info(text: String)

var tree_key := ""
var accent := Color(0.3, 0.95, 1.0)
var compact := false
var _buttons := {}
var _nodes: Array = []
var cell := Vector2(206, 82)
var btn := Vector2(190, 62)


func setup(key: String, color: Color, narrow := false) -> void:
	tree_key = key
	accent = color
	compact = narrow
	if narrow:
		cell = Vector2(150, 82)
		btn = Vector2(142, 62)
	for c in get_children():
		c.queue_free()
	_buttons.clear()
	_nodes = Meta.tree_nodes(key)
	var max_pos := Vector2.ZERO
	for n in _nodes:
		max_pos = max_pos.max(n["pos"])
	custom_minimum_size = Vector2((max_pos.x + 1.0) * cell.x - (cell.x - btn.x), (max_pos.y + 1.0) * cell.y - (cell.y - btn.y))
	for n in _nodes:
		var b := Button.new()
		b.position = _npos(n)
		b.size = btn
		b.custom_minimum_size = btn
		b.add_theme_font_size_override("font_size", 12 if narrow else 13)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.clip_text = true
		b.icon = Pixel.icon(_node_icon(key, n["id"]))
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 22 if narrow else 28)
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var node: Dictionary = n
		b.pressed.connect(func():
			info.emit(_info_text(node))
			if Meta.buy_node(tree_key, node):
				Sound.play("chest", -4.0)
				refresh()
				bought.emit()
			else:
				Sound.play("hurt", -14.0, 1.6))
		b.mouse_entered.connect(func():
			Sound.play("hover", -12.0)
			info.emit(_info_text(node)))
		b.focus_entered.connect(func(): info.emit(_info_text(node)))
		add_child(b)
		_buttons[n["id"]] = b
	refresh()


func _npos(n: Dictionary) -> Vector2:
	return Vector2(n["pos"].x * cell.x, n["pos"].y * cell.y)


## Полное описание узла: эффект, цена, ярус и условия.
func _info_text(n: Dictionary) -> String:
	var hero := Meta.tree_hero(tree_key)
	var t := "%s — %s.  Цена %d ◆, ярус %d." % [n["name"], n["desc"], int(n["cost"]), int(n["tier"])]
	var conds: Array = n.get("conds", [])
	if not conds.is_empty():
		var parts: Array = []
		for c in conds:
			parts.append(("✓ " if Meta.cond_met(c, hero) else "✗ ") + Meta.cond_text(c, hero))
		t += "\nУсловия: " + ";  ".join(parts)
	return t


func _node_icon(key: String, id: String) -> String:
	var subj := key.substr(2)
	match id:
		"dmg1", "dmg2", "dmg3", "legend", "hunter", "legacy", "legend_tale", "myth", "elite", "execute":
			return "damage"
		"crit1", "critdmg":
			return "crit"
		"leech":
			return "vamp"
		"salvage", "mats1", "favor":
			return "luck"
		"resonance", "fusion", "mythic":
			return "duration"
		"laststand":
			return "armor"
		"cd1", "cd2", "cd":
			return "cooldown"
		"status", "dur":
			return "duration"
		"count", "overcharge":
			return "multi"
		"area1":
			return "area"
		"speed1", "spd1":
			return "speed"
		"master", "preinstall":
			return subj
		"hp1", "hp2":
			return "hp"
		"regen1":
			return "regen"
		"magnet1":
			return "magnet"
		"xp1", "awaken":
			return "luck"
		"dodge1", "armor":
			return "armor"
		"power", "ascend":
			return "ab_" + subj
		"boost1", "boost2", "boost3", "boost4", "boost5", "tune":
			return "area"
	return subj


func _box(border: Color, bg: Color, glow: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(6)
	s.shadow_color = Color(border, 0.4)
	s.shadow_size = glow
	s.set_content_margin_all(4)
	return s


func refresh() -> void:
	var hero := Meta.tree_hero(tree_key)
	for n in _nodes:
		var b: Button = _buttons[n["id"]]
		var st := Meta.node_state(tree_key, n)
		var bg := Color(0.05, 0.03, 0.1, 0.95)
		var border := Color(0.35, 0.35, 0.45)
		var line2 := "%d ◆" % int(n["cost"])
		match st:
			"owned":
				border = Color(1.0, 0.8, 0.3)
				bg = Color(0.2, 0.14, 0.05, 0.95)
				line2 = "✓ изучено"
			"open":
				border = accent
			"expensive":
				border = accent.darkened(0.5)
				line2 = "%d ◆ мало" % int(n["cost"])
			"locked":
				line2 = "нужны верхние"
			"tier":
				line2 = "здание ур. %d" % int(n["tier"])
			"cond":
				border = Color(0.75, 0.4, 0.9)
				line2 = "⊘ " + Meta.cond_short(Meta.first_unmet(n.get("conds", []), hero), hero)
		b.text = "%s\n%s" % [n["name"], line2]
		b.tooltip_text = _info_text(n)
		b.add_theme_stylebox_override("normal", _box(border, bg, 8 if st in ["owned", "open"] else 0))
		b.add_theme_stylebox_override("hover", _box(border.lightened(0.3), bg.lightened(0.05), 14))
		b.add_theme_stylebox_override("pressed", _box(Color.WHITE, bg, 14))
		b.add_theme_stylebox_override("focus", _box(border, bg, 8))
		b.add_theme_color_override("font_color", Color.WHITE if st in ["owned", "open"] else Color(0.65, 0.65, 0.75))
	queue_redraw()


func _draw() -> void:
	# Связи: от нижнего края «родителя» к верхнему краю узла, ступенькой
	for n in _nodes:
		var to: Vector2 = _npos(n) + Vector2(btn.x / 2.0, 0)
		for r in n["req"]:
			for m in _nodes:
				if m["id"] == r:
					var from: Vector2 = _npos(m) + Vector2(btn.x / 2.0, btn.y)
					var owned := Meta.has_node(tree_key, r)
					var col := Color(1.0, 0.8, 0.3, 0.9) if owned else Color(0.4, 0.4, 0.55, 0.6)
					var mid := (from.y + to.y) / 2.0
					draw_polyline(PackedVector2Array([from, Vector2(from.x, mid), Vector2(to.x, mid), to]), col, 3.0)
