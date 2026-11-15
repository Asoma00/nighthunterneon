extends CanvasLayer
## Уведомление о достижении: выезжает сверху справа — медаль с картинкой,
## «ДОСТИЖЕНИЕ», название, ранг и награда. Несколько подряд встают в очередь.
## Живёт в корне дерева, поэтому не пропадает при смене сцены.

const Arsenal := preload("res://scripts/arsenal.gd")
const Meta := preload("res://scripts/meta.gd")
const Pixel := preload("res://scripts/pixel.gd")

## Картинка по виду условия достижения
const ICON_OF := {"kills": "damage", "best_kills": "multi", "bosses": "execute", "elites": "giant",
	"chests": "luck", "caches": "luck", "forged": "bolt", "modules": "area", "heroes": "hp",
	"level": "speed", "max_level": "duration", "nodmg_best": "shield", "endless": "regen",
	"fusions": "crit", "puzzles": "pierce", "reactions": "toxin", "runs": "dash", "rank": "armor",
	"skins": "dodge", "secrets": "magnet", "achievements": "crit"}

var _queue: Array = []
var _busy := false


static func get_or_make() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var n := tree.root.get_node_or_null("AchToast")
	if n == null:
		n = load("res://scripts/ach_toast.gd").new()
		n.name = "AchToast"
		tree.root.add_child(n)
	return n


## Показать уведомления для новых открытий (["a", id] из Arsenal.refresh()).
static func show_unlocks(list: Array) -> void:
	for u in list:
		if str(u[0]) == "a":
			show_ach(str(u[1]))


static func show_ach(id: String) -> void:
	var a := Arsenal.ach_by_id(id)
	if a.is_empty():
		return
	var n = get_or_make()
	if n != null:
		n._queue.append(a)
		n._next()


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS


func _next() -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	var a: Dictionary = _queue.pop_front()
	var tier: Dictionary = Arsenal.TIERS[int(a.get("t", 0))]
	var col: Color = tier["color"]
	var vs := get_viewport().get_visible_rect().size
	var w := minf(460.0, vs.x - 24.0)
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.03, 0.1, 0.94)
	sb.border_color = col
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	sb.shadow_color = Color(col, 0.45)
	sb.shadow_size = 14
	sb.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(w, 0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	var medal := _Medal.new()
	medal.col = col
	medal.tex = Pixel.icon(str(ICON_OF.get(str((a["c"] as Array)[0]), "crit")))
	medal.custom_minimum_size = Vector2(84, 84)
	row.add_child(medal)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(v)
	v.add_child(_lbl("★ ДОСТИЖЕНИЕ  •  " + str(tier["name"]).to_upper(), 14, col))
	var nm := _lbl(str(a.get("name", "")), 24, Color.WHITE)
	nm.add_theme_color_override("font_shadow_color", Color(col, 0.8))
	nm.add_theme_constant_override("shadow_outline_size", 6)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(nm)
	v.add_child(_lbl(Meta.cond_text(a["c"], "", false), 13, Color(0.8, 0.8, 0.95)))
	v.add_child(_lbl("Награда: " + Meta.cost_text(Arsenal.ach_reward(a)), 14, Color(1.0, 0.85, 0.4)))
	await get_tree().process_frame
	if not is_instance_valid(card):
		_busy = false
		return
	var x := vs.x - card.size.x - 16.0
	card.position = Vector2(vs.x + 20.0, 16.0)
	card.modulate.a = 0.0
	Sound.play("levelup", -4.0, 1.25)
	var tw := card.create_tween()
	tw.tween_property(card, "position:x", x, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(card, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_method(func(t: float): medal.shine = t, 0.0, 1.0, 1.2).set_delay(0.3)
	tw.tween_interval(3.6)
	tw.tween_property(card, "position:y", -card.size.y - 30.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(card, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func():
		card.queue_free()
		_busy = false
		_next())


func _lbl(t: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Медаль: лента, кольцо цвета ранга, картинка внутри и пробегающий блик.
class _Medal extends Control:
	var col := Color.WHITE
	var tex: Texture2D
	var shine := 0.0:
		set(v):
			shine = v
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0 + Vector2(0, 4)
		var r := minf(size.x, size.y) * 0.4
		# лента
		draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.7, -r * 0.2), c + Vector2(-r * 0.15, -r * 0.2),
			c + Vector2(-r * 0.45, -r * 1.25), c + Vector2(-r * 1.0, -r * 1.25)]), col.darkened(0.45))
		draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.15, -r * 0.2), c + Vector2(r * 0.7, -r * 0.2),
			c + Vector2(r * 1.0, -r * 1.25), c + Vector2(r * 0.45, -r * 1.25)]), col.darkened(0.3))
		draw_circle(c, r + 6.0, Color(col, 0.25))
		draw_circle(c, r + 2.0, col.darkened(0.5))
		draw_circle(c, r, col)
		draw_circle(c + Vector2(-r * 0.12, -r * 0.12), r * 0.86, col.lightened(0.25))
		draw_circle(c, r * 0.74, Color(0.07, 0.04, 0.13))
		if tex != null:
			var s := r * 1.25
			draw_texture_rect(tex, Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s)), false)
		# зубцы по краю
		for i in 16:
			var a := TAU * float(i) / 16.0
			draw_circle(c + Vector2(cos(a), sin(a)) * (r + 1.0), 2.2, col.lightened(0.4))
		if shine > 0.0 and shine < 1.0:
			var x := lerpf(-r * 1.4, r * 1.4, shine)
			draw_line(c + Vector2(x - r * 0.3, r), c + Vector2(x + r * 0.3, -r), Color(1, 1, 1, 0.55 * sin(shine * PI)), 6.0)
