extends CanvasLayer
## Кат-сцена появления босса прямо в бою.
## Время почти замирает, по краям выезжают кинополосы, камера летит к боссу,
## он выходит из портала с ударной волной, а через экран проносится косая
## плашка с именем, титулом и первой репликой. Потом камера возвращается к герою.
## Работает в реальном времени (не зависит от Engine.time_scale).

const Pixel := preload("res://scripts/pixel.gd")
const Story := preload("res://scripts/story.gd")
const Fx := preload("res://scripts/fx.gd")

const TITLES := {
	"lich": "Повелитель мёртвого кода",
	"colossus": "Страж из стали и рун",
	"queen": "Мать бесконечного роя",
	"omega": "Хозяин Врат",
}
const DUR := 3.6

var main: Node
var boss: Node2D
var _t := 0.0
var _last_us := 0
var _from := Vector2.ZERO
var _bars: Array = []
var _band: Control
var _flash: ColorRect
var _fx_done := false
var _line := ""
var _was_smooth := true
var _hud_vis := true


static func font(size_k := 1.0) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	fv.variation_embolden = 0.9
	fv.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.22, 1), Vector2.ZERO)   # наклон, как у курсива
	fv.spacing_glyph = int(2 * size_k)
	return fv


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_us = Time.get_ticks_usec()
	_from = main._cam_anchor.position
	_was_smooth = main.camera.position_smoothing_enabled
	main.camera.position_smoothing_enabled = false
	_hud_vis = main.hud.visible
	main.hud.visible = false
	Engine.time_scale = 0.08
	for p in main.players:
		p._invuln = maxf(p._invuln, 3.0)
	var lines: Array = Story.BOSS_LINES.get(str(boss.get("kind")), {}).get("intro", [])
	if not lines.is_empty():
		_line = lines[randi() % lines.size()]
	_build()


func _build() -> void:
	var vs := get_viewport().get_visible_rect().size
	for i in 2:
		var r := ColorRect.new()
		r.color = Color(0, 0, 0)
		r.size = Vector2(vs.x, vs.y * 0.12)
		r.position = Vector2(0, -r.size.y if i == 0 else vs.y)
		add_child(r)
		_bars.append(r)
	_flash = ColorRect.new()
	_flash.size = vs
	_flash.color = Color(boss.color, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	# Косая плашка с именем
	var k := clampf(vs.y / 720.0, 0.6, 1.6)
	_band = Control.new()
	_band.size = Vector2(vs.x * 1.3, 190 * k)
	_band.pivot_offset = _band.size * 0.5
	_band.rotation = deg_to_rad(-4.0)
	_band.position = Vector2(-vs.x * 1.6, vs.y * 0.6 - _band.size.y * 0.5)
	add_child(_band)
	var col: Color = boss.color
	var back := Polygon2D.new()
	var w := _band.size.x
	var h := _band.size.y
	back.polygon = PackedVector2Array([Vector2(40 * k, 0), Vector2(w, 0), Vector2(w - 40 * k, h), Vector2(0, h)])
	back.color = Color(0.03, 0.02, 0.07, 0.92)
	_band.add_child(back)
	var stripe := Polygon2D.new()
	stripe.polygon = PackedVector2Array([Vector2(40 * k, 0), Vector2(w, 0), Vector2(w - 2 * k, 10 * k), Vector2(38 * k, 10 * k)])
	stripe.color = Pixel.hdr(col, 1.3)
	_band.add_child(stripe)
	var stripe2 := Polygon2D.new()
	stripe2.polygon = PackedVector2Array([Vector2(2 * k, h - 8 * k), Vector2(w - 38 * k, h - 8 * k), Vector2(w - 40 * k, h), Vector2(0, h)])
	stripe2.color = Color(1.0, 0.85, 0.35)
	_band.add_child(stripe2)
	# Скошенный «шеврон» слева, цветом босса
	var chev := Polygon2D.new()
	var x0 := vs.x * 0.18
	chev.polygon = PackedVector2Array([Vector2(x0, 14 * k), Vector2(x0 + 34 * k, 14 * k), Vector2(x0 + 8 * k, h - 14 * k), Vector2(x0 - 26 * k, h - 14 * k)])
	chev.color = Pixel.hdr(col, 1.2)
	_band.add_child(chev)

	var name_l := Label.new()
	name_l.text = str(boss.get("boss_name"))
	name_l.add_theme_font_override("font", font(k))
	name_l.add_theme_font_size_override("font_size", int(64 * k))
	name_l.add_theme_color_override("font_color", Color(1, 1, 1))
	name_l.add_theme_color_override("font_shadow_color", Color(col, 0.9))
	name_l.add_theme_constant_override("shadow_offset_x", int(5 * k))
	name_l.add_theme_constant_override("shadow_offset_y", int(4 * k))
	name_l.position = Vector2(x0 + 60 * k, 18 * k)
	_band.add_child(name_l)
	var sub := Label.new()
	var kind := str(boss.get("kind"))
	sub.text = ("БОСС  •  " + TITLES.get(kind, "Страж Врат")).to_upper()
	sub.add_theme_font_override("font", font(k * 0.6))
	sub.add_theme_font_size_override("font_size", int(22 * k))
	sub.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	sub.position = Vector2(x0 + 64 * k, 100 * k)
	_band.add_child(sub)
	if _line != "":
		var q := Label.new()
		q.text = "«" + _line + "»"
		q.add_theme_font_size_override("font_size", int(20 * k))
		q.add_theme_color_override("font_color", Color(0.9, 0.85, 1.0))
		q.position = Vector2(x0 + 64 * k, 134 * k)
		_band.add_child(q)


func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := minf(float(now - _last_us) / 1000000.0, 0.25)
	_last_us = now
	_t += dt
	if not is_instance_valid(boss) or not is_instance_valid(main):
		_finish()
		return
	var vs := get_viewport().get_visible_rect().size
	# Кинополосы
	var bk := _ease(clampf(_t / 0.35, 0.0, 1.0)) * (1.0 - _ease(clampf((_t - (DUR - 0.4)) / 0.4, 0.0, 1.0)))
	var bh: float = (_bars[0] as ColorRect).size.y
	(_bars[0] as ColorRect).position.y = -bh + bh * bk
	(_bars[1] as ColorRect).position.y = vs.y - bh * bk
	# Камера: к боссу и обратно
	var target: Vector2 = boss.position
	var go := _ease(clampf((_t - 0.1) / 0.6, 0.0, 1.0))
	var back := _ease(clampf((_t - (DUR - 0.75)) / 0.6, 0.0, 1.0))
	var hero_pos: Vector2 = main.view_center()
	var p := _from.lerp(target, go).lerp(hero_pos, back)
	main.cine_focus = p
	main._cam_anchor.position = p
	# Выход босса
	if _t > 0.75 and not _fx_done:
		_fx_done = true
		Fx.portal(main, target, boss.color, 2.6)
		Fx.ring(main, target, 20.0, 420.0, Pixel.hdr(boss.color, 2.2), 0.25, 8.0)
		Fx.ring(main, target, 10.0, 260.0, Pixel.hdr(Color(1, 1, 1), 2.0), 0.18, 4.0)
		Sound.play("boom", 2.0, 0.55)
		Sound.play("thunder", -2.0, 0.7)
		main.shake(16.0)
	_flash.color.a = 0.0 if _t < 0.75 else maxf(0.0, 0.45 - (_t - 0.75) * 1.4)
	# Плашка: влетает с перелётом, стоит, улетает вправо
	var bx_in := -vs.x * 1.6
	var bx_mid := -vs.x * 0.15
	var bx_out := vs.x * 1.2
	var bt_in := clampf((_t - 0.85) / 0.35, 0.0, 1.0)
	var bt_out := clampf((_t - (DUR - 0.75)) / 0.3, 0.0, 1.0)
	var x := lerpf(bx_in, bx_mid, _back_out(bt_in))
	x = lerpf(x, bx_out, bt_out * bt_out)
	_band.position.x = x + (_t - 0.85) * 12.0
	if _t >= DUR:
		_finish()


func _input(event: InputEvent) -> void:
	if _t > 1.2 and (event.is_action_pressed("ui_accept") or event.is_action_pressed("pause")):
		_t = maxf(_t, DUR - 0.75)
		get_viewport().set_input_as_handled()


func _finish() -> void:
	if is_queued_for_deletion():
		return
	Engine.time_scale = 1.0
	if is_instance_valid(main):
		main.cine_focus = null
		main.camera.position_smoothing_enabled = _was_smooth
		main.camera.reset_smoothing()
		main.hud.visible = _hud_vis
	queue_free()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


static func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


static func _back_out(t: float) -> float:
	var c := 1.6
	return 1.0 + (c + 1.0) * pow(t - 1.0, 3.0) + c * pow(t - 1.0, 2.0)
