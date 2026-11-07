extends Control
## Главное меню: заставка с неоновым городом, выбор героя, настройки громкости.

const Data := preload("res://scripts/data.gd")
const Pixel := preload("res://scripts/pixel.gd")
const Fx := preload("res://scripts/fx.gd")
const MainScript := preload("res://scripts/main.gd")
const UiFocus := preload("res://scripts/ui_focus.gd")
const DevInput := preload("res://scripts/devinput.gd")
const Meta := preload("res://scripts/meta.gd")

const CYAN := Color(0.3, 0.95, 1.0)
const MAGENTA := Color(1.0, 0.3, 0.75)
const GOLD := Color(1.0, 0.8, 0.3)
const PANEL_BG := Color(0.05, 0.03, 0.1, 0.88)

var _bg: Node2D
var _ground: Sprite2D
var _ground_emit: Sprite2D
var _title: Label
var _pages := {}
var _portraits: Array = []
var _selected := "vega"
var _cards := {}
var _info: Label
var _t := 0.0
var _focus := {}
var _page_name := "main"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_selected = Data.selected_character
	_build_background()
	_build_main_page()
	_build_select_page()
	_build_settings_page()
	_build_saves_page()
	_build_profile_page()
	Meta.ensure_loaded()
	_build_coop_page()
	_build_net_page()
	_show(Data.menu_page if Data.menu_page != "" and _pages.has(Data.menu_page) else "main")
	Data.menu_page = ""
	Settings.orientation_changed.connect(_on_orientation)
	Settings.apply_safe(self)
	Sound.set_track("menu")
	# Номер сборки — в левом нижнем углу; рядом — состояние автообновления
	var ver := _label("", 14, Color(0.6, 0.6, 0.75))
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	ver.offset_left = 12
	ver.offset_top = -30
	ver.offset_right = 900
	ver.offset_bottom = -8
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(ver)
	_ver_label = ver
	_on_upd_status()
	Updater.status_changed.connect(_on_upd_status)


var _ver_label: Label
var _hint_l: Label


## Подсказка управления в главном меню — только для своего устройства
func _controls_hint() -> String:
	match Settings.input_mode():
		"touch":
			return "Касание и сдвиг пальца — движение   •   двойное касание — способность   •   II — пауза   •   ≡ — характеристики"
		"pad":
			return "Левый стик — движение   •   A — способность   •   START — пауза   •   SELECT — характеристики   •   B — назад"
	return "WASD — движение   •   ПРОБЕЛ — способность   •   ESC — пауза   •   TAB — характеристики"


func _on_upd_status(_t := "") -> void:
	var s := "Сборка %s" % Updater.version
	if Updater.status != "":
		s += "   •   " + Updater.status
	_ver_label.text = s


## Телефон повернули — пересобрать меню под новый экран, оставшись на той же странице
func _on_orientation(_p: bool) -> void:
	Data.menu_page = _page_name
	get_tree().reload_current_scene.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _page_name not in ["main", "coop", "net"]:
		get_viewport().set_input_as_handled()
		Sound.play("click")
		if _page_name == "profile":
			_profile_back()
		else:
			_show("main")


# ---------- Фон ----------

func _build_background() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	RenderingServer.set_default_clear_color(Color(0.03, 0.02, 0.06))

	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	_bg = Node2D.new()
	_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.add_child(_bg)
	var g := Pixel.ground()
	for i in 2:
		var s := Sprite2D.new()
		s.texture = g["base"] if i == 0 else g["emit"]
		s.centered = false
		s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		s.region_enabled = true
		s.region_rect = Rect2(0, 0, 128 * 8, 128 * 6)
		s.scale = Vector2.ONE * Pixel.PX
		s.modulate = Color(0.45, 0.4, 0.65) if i == 0 else Color(1, 1, 1, 0.5)
		if i == 1:
			s.material = Pixel.mat_add()
		_bg.add_child(s)
		if i == 0:
			_ground = s
		else:
			_ground_emit = s
	# Дождь и светлячки
	var rain := CPUParticles2D.new()
	rain.amount = 300
	rain.lifetime = 1.0
	rain.preprocess = 1.0
	rain.texture = Pixel.raindrop()
	rain.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	rain.emission_rect_extents = Vector2(900, 10)
	rain.position = Vector2(500, -40)
	rain.direction = Vector2(0.25, 1.0)
	rain.spread = 2.0
	rain.gravity = Vector2.ZERO
	rain.initial_velocity_min = 750.0
	rain.initial_velocity_max = 900.0
	rain.scale_amount_min = 2.0
	rain.scale_amount_max = 3.0
	rain.color_ramp = Fx._ramp([Color(0.4, 0.8, 1.0, 0.0), Color(0.5, 0.85, 1.0, 0.35), Color(0.9, 0.5, 1.0, 0.25)])
	rain.material = Pixel.mat_add()
	_bg.add_child(Fx.gpu2d(rain))   # фон считает видеокарта
	var motes := CPUParticles2D.new()
	motes.amount = 60
	motes.lifetime = 6.0
	motes.preprocess = 6.0
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(700, 400)
	motes.position = Vector2(640, 360)
	motes.direction = Vector2(0.2, -1.0)
	motes.spread = 40.0
	motes.gravity = Vector2(0, -6)
	motes.initial_velocity_min = 5.0
	motes.initial_velocity_max = 25.0
	motes.scale_amount_min = 2.0
	motes.scale_amount_max = 5.0
	motes.color_ramp = Fx._ramp([Color(1.0, 0.3, 0.8, 0.0), Color(1.4, 0.5, 1.6, 0.9), Color(0.4, 1.2, 1.6, 0.8), Color(0.3, 0.9, 1.0, 0.0)])
	motes.material = Pixel.mat_add()
	_bg.add_child(Fx.gpu2d(motes))

	if DisplayServer.get_name() != "headless":
		var post_layer := CanvasLayer.new()
		post_layer.layer = 5
		add_child(post_layer)
		var rect := ColorRect.new()
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := Shader.new()
		sh.code = MainScript.POST_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		rect.material = m
		post_layer.add_child(rect)


func _process(delta: float) -> void:
	_t += delta
	if _pages.has(_page_name) and _page_name != "coop":
		UiFocus.keep(_pages[_page_name], _focus)
	_coop_tick(delta)
	_net_tick(delta)
	var off := Vector2(_t * 14.0, _t * 8.0)
	var period := 128.0 * Pixel.PX
	var p := -Vector2(fmod(off.x, period), fmod(off.y, period))
	_ground.position = p
	_ground_emit.position = p
	_ground_emit.modulate.a = 0.4 + 0.25 * sin(_t * 1.5)
	if _title:
		var pulse := 0.5 + 0.5 * sin(_t * 2.0)
		_title.add_theme_color_override("font_shadow_color", Color(MAGENTA.lerp(CYAN, pulse), 0.85))
		_title.rotation = sin(_t * 0.7) * 0.01
	# Анимация портретов героев
	for k in range(_portraits.size() - 1, -1, -1):
		if not is_instance_valid(_portraits[k][0]):
			_portraits.remove_at(k)
	for entry in _portraits:
		var fr: Dictionary = entry[1]
		var idx := int(_t * (10.0 if entry[3] else 4.0)) % 4 + (4 if entry[3] else 0)
		(entry[0] as TextureRect).texture = fr["base"][idx]
		(entry[2] as TextureRect).texture = fr["emit"][idx]


# ---------- Утилиты ----------

func _label(text: String, size: int, color := Color.WHITE, glow := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.08))
	l.add_theme_constant_override("outline_size", 6)
	if glow.a > 0.0:
		l.add_theme_color_override("font_shadow_color", glow)
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 0)
		l.add_theme_constant_override("shadow_outline_size", 16)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _box(border: Color, bg := PANEL_BG, width := 2, glow := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(6)
	s.shadow_color = Color(border, 0.45)
	s.shadow_size = glow
	s.set_content_margin_all(10)
	return s


func _button(text: String, accent: Color, w := 340) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 56)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_stylebox_override("normal", _box(accent.darkened(0.35), PANEL_BG, 2, 6))
	b.add_theme_stylebox_override("hover", _box(accent, Color(0.1, 0.05, 0.18, 0.95), 3, 18))
	b.add_theme_stylebox_override("pressed", _box(Color.WHITE, Color(0.15, 0.08, 0.25, 0.95), 3, 22))
	b.add_theme_stylebox_override("focus", _box(accent, Color(0.1, 0.05, 0.18, 0.95), 3, 18))
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.mouse_entered.connect(func(): Sound.play("hover", -10.0))
	return b


func _page(name: String) -> VBoxContainer:
	# Страница по центру экрана; если не помещается — прокручивается, а не вылезает за край
	var sc := ScrollContainer.new()
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size = get_viewport().get_visible_rect().size - Vector2(0, 2)
	sc.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	center.add_child(v)
	_pages[name] = sc
	return v


func _show(name: String) -> void:
	if name == "coop":
		_coop_reset()
	if name != "profile" and name != "main":
		Data.menu_return = ""
	if name == "profile":
		_fill_profile()
	if name == "saves":
		_fill_saves()
	if name == "net":
		var heroes := _unlocked_heroes()
		_net_hero = maxi(0, heroes.find(Data.selected_character))
		_net_level = clampi(Data.selected_level, 0, mini(Meta.levels_cleared, Data.LEVELS.size() - 1))
		_net_ready = false
		_net_sig = ""
		Net.listen(Net.mode == "")
		if Net.mode != "":
			_net_push()
	elif name != "net":
		Net.listen(false)
	_page_name = name
	_focus = {}
	for k in _pages:
		_pages[k].visible = k == name
	var page: Control = _pages[name]
	page.modulate.a = 0.0
	var tw := page.create_tween()
	tw.tween_property(page, "modulate:a", 1.0, 0.25)


func _sprite_stack(key: String, size: float, walking: bool) -> Control:
	var fr := Pixel.frames(key)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size, size)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base := TextureRect.new()
	var emit := TextureRect.new()
	for r in [base, emit]:
		r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(r)
	emit.modulate = Pixel.hdr(Color.WHITE, 1.6)
	_portraits.append([base, fr, emit, walking])
	return holder


# ---------- Главная ----------

func _build_main_page() -> void:
	var v := _page("main")
	_title = _label("НОЧЬ ОХОТНИКА", 72, Color(1.0, 0.95, 1.0), Color(MAGENTA, 0.85))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.pivot_offset = Vector2(300, 40)
	v.add_child(_title)
	var sub := _label("— Н Е О Н —", 26, CYAN, Color(CYAN, 0.7))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	v.add_child(spacer)
	var play := _button("ИГРАТЬ", CYAN)
	play.pressed.connect(func():
		Data.coop = false
		Data.world_seed = 0
		Sound.play("click")
		var tw := create_tween()
		tw.tween_property(self, "modulate", Color(0, 0, 0, 1), 0.35)
		tw.tween_callback(func(): Loader.go("res://hub.tscn")))
	v.add_child(play)
	var coop := _button("ИГРАТЬ ВДВОЁМ", Color(1.0, 0.4, 0.75))
	coop.pressed.connect(func():
		Sound.play("click")
		_show("coop"))
	v.add_child(coop)
	var net := _button("СЕТЕВАЯ ИГРА (LAN)", Color(0.4, 1.0, 0.6))
	net.pressed.connect(func():
		Sound.play("click")
		_show("net"))
	v.add_child(net)
	net.visible = not Settings.is_web()   # в браузере сеть по Wi-Fi (LAN) недоступна
	var saves := _button("СОХРАНЕНИЯ", GOLD)
	saves.pressed.connect(func():
		Sound.play("click")
		_show("saves"))
	v.add_child(saves)
	var settings := _button("НАСТРОЙКИ", MAGENTA)
	settings.pressed.connect(func():
		Sound.play("click")
		_show("settings"))
	v.add_child(settings)
	var quit := _button("ВЫХОД", Color(0.6, 0.6, 0.75))
	quit.pressed.connect(func(): get_tree().quit())
	v.add_child(quit)
	_add_profile_badge()
	if Settings.is_mobile():
		quit.visible = false
	var hint := _label(_controls_hint(), 15, Color(0.7, 0.7, 0.85))
	_hint_l = hint
	Settings.input_mode_changed.connect(func(_m): if is_instance_valid(_hint_l): _hint_l.text = _controls_hint())
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(minf(1100.0, get_viewport().get_visible_rect().size.x - 60.0), 0)
	v.add_child(hint)


# ---------- Выбор героя ----------

func _build_select_page() -> void:
	var v := _page("select")
	var title := _label("ВЫБЕРИТЕ ГЕРОЯ", 44, Color.WHITE, Color(CYAN, 0.8))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	for id in Data.CHARACTERS:
		var card := _char_card(id)
		_cards[id] = card
		row.add_child(card)
	_info = _label("", 15, Color(0.85, 0.85, 1.0))
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(1100, 0)
	v.add_child(_info)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	var back := _button("НАЗАД", Color(0.6, 0.6, 0.75), 200)
	back.pressed.connect(func():
		Sound.play("click")
		_show("main"))
	buttons.add_child(back)
	var start := _button("В БОЙ!", GOLD, 300)
	start.pressed.connect(_start_game)
	buttons.add_child(start)
	v.add_child(buttons)
	_select(_selected)


func _char_card(id: String) -> Button:
	var c: Dictionary = Data.CHARACTERS[id]
	var accent: Color = c["color"]
	var b := Button.new()
	b.custom_minimum_size = Vector2(268, 430)
	b.add_theme_stylebox_override("normal", _box(accent.darkened(0.45), PANEL_BG, 2, 4))
	b.add_theme_stylebox_override("hover", _box(accent.darkened(0.1), Color(0.08, 0.04, 0.15, 0.95), 3, 12))
	b.add_theme_stylebox_override("pressed", _box(accent, Color(0.1, 0.05, 0.18, 0.95), 3, 20))
	b.add_theme_stylebox_override("focus", _box(accent.darkened(0.1), Color(0.08, 0.04, 0.15, 0.95), 3, 12))
	b.mouse_entered.connect(func(): Sound.play("hover", -10.0))
	b.pressed.connect(func():
		Sound.play("click")
		_select(id))
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_right = -12
	v.offset_top = 10
	v.offset_bottom = -10
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var portrait := _sprite_stack(c["sprite"], 120, false)
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(portrait)
	var name_l := _label(c["name"], 28, Color.WHITE, Color(accent, 0.8))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_l)
	var title_l := _label(c["title"], 16, accent)
	title_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title_l)
	var stats := _label("❤ %d    ➤ %d" % [int(c["hp"]), int(c["speed"])], 15, Color(0.85, 0.85, 0.95))
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(stats)
	var wrow := HBoxContainer.new()
	wrow.alignment = BoxContainer.ALIGNMENT_CENTER
	wrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wi := TextureRect.new()
	wi.texture = Pixel.icon(c["weapon"])
	wi.custom_minimum_size = Vector2(32, 32)
	wi.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrow.add_child(wi)
	wrow.add_child(_label(Data.WEAPONS[c["weapon"]]["name"], 15, CYAN))
	v.add_child(wrow)
	for text in [c["trait"], "★ " + c["active"] + ": " + c["active_desc"]]:
		var l := _label(text, 13, Color(0.8, 0.8, 0.95) if not text.begins_with("★") else GOLD)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(240, 0)
		v.add_child(l)
	return b


func _select(id: String) -> void:
	_selected = id
	for k in _cards:
		var card: Button = _cards[k]
		var on: bool = k == id
		card.scale = Vector2(1.04, 1.04) if on else Vector2.ONE
		card.pivot_offset = card.custom_minimum_size / 2.0
		card.modulate = Color(1, 1, 1) if on else Color(0.7, 0.7, 0.8)
	var c: Dictionary = Data.CHARACTERS[id]
	_info.text = "Выбран: %s, %s.  Стартовое оружие — %s.\nСтатус оружия — %s" % [
		c["name"], c["title"].to_lower(), Data.WEAPONS[c["weapon"]]["name"],
		Data.synergy_text(Data.WEAPONS[c["weapon"]]["status"])]


func _start_game() -> void:
	Sound.play("levelup", 0.0)
	Data.selected_character = _selected
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(0, 0, 0, 1), 0.35)
	tw.tween_callback(func(): Loader.go("res://main.tscn"))


# ---------- Настройки ----------

func _build_settings_page() -> void:
	var v := _page("settings")
	var sp = preload("res://scripts/settings_panel.gd").new()
	sp.on_back = func(): _show("main")
	v.add_child(sp)


func _row_label(text: String) -> Label:
	var l := _label(text, 17, CYAN)
	l.custom_minimum_size = Vector2(170, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


# ---------- Сохранения: три слота ----------

var _saves_box: HFlowContainer
var _confirm_del := 0


func _build_saves_page() -> void:
	var v := _page("saves")
	var title := _label("СОХРАНЕНИЯ", 44, Color.WHITE, Color(GOLD, 0.8))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var hint := _label("Выберите слот, чтобы играть им. Пустой слот — новая игра с нуля.", 16, Color(0.8, 0.8, 0.95))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	_saves_box = HFlowContainer.new()
	_saves_box.alignment = FlowContainer.ALIGNMENT_CENTER
	_saves_box.add_theme_constant_override("h_separation", 22)
	_saves_box.add_theme_constant_override("v_separation", 14)
	_saves_box.custom_minimum_size = Vector2(minf(1100.0, get_viewport().get_visible_rect().size.x - 40.0), 0)
	v.add_child(_saves_box)
	var back := _button("НАЗАД", Color(0.6, 0.6, 0.75), 260)
	back.pressed.connect(func():
		Sound.play("click")
		_show("main"))
	v.add_child(back)


func _fill_saves() -> void:
	for c in _saves_box.get_children():
		c.queue_free()
	var cur := Meta.current_slot()
	for n in range(1, Meta.MAX_SLOTS + 1):
		var info := Meta.slot_info(n)
		var active := n == cur
		var accent := GOLD if active else (CYAN if not info.is_empty() else Color(0.5, 0.5, 0.65))
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(330, 330)
		card.add_theme_stylebox_override("panel", _box(accent, PANEL_BG, 3 if active else 2, 14 if active else 6))
		_saves_box.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 8)
		card.add_child(cv)
		var head := _label("СЛОТ %d%s" % [n, "  • ТЕКУЩИЙ" if active else ""], 22, Color.WHITE, Color(accent, 0.7))
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(head)
		if info.is_empty():
			var e := _label("— пусто —", 20, Color(0.6, 0.6, 0.75))
			e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			e.size_flags_vertical = Control.SIZE_EXPAND_FILL
			e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			cv.add_child(e)
		else:
			var nick := _label(str(info["nickname"]), 26, accent, Color(accent, 0.5))
			nick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			nick.clip_text = true
			nick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			cv.add_child(nick)
			var t := int(info["time"])
			for line in ["Забегов: %d" % int(info["runs"]),
					"Пройдено уровней: %d" % int(info["levels"]),
					"◆ Осколков: %d" % int(info["shards"]),
					"В игре: %d ч %02d мин" % [t / 3600, (t / 60) % 60],
					"Сохранено: %s" % str(info["saved"]).replace("T", " ") if str(info["saved"]) != "" else ""]:
				if line == "":
					continue
				var l := _label(line, 16, Color(0.88, 0.88, 1.0))
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				cv.add_child(l)
			var sp := Control.new()
			sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
			cv.add_child(sp)
		var pick_text := "ИГРАЕТЕ ЭТИМ" if active else ("ВЫБРАТЬ" if not info.is_empty() else "НОВАЯ ИГРА")
		var pick := _button(pick_text, accent, 280)
		pick.disabled = active
		pick.pressed.connect(func():
			Sound.play("click")
			_confirm_del = 0
			Meta.switch_slot(n)
			_refresh_badge()
			_fill_saves())
		cv.add_child(pick)
		if not info.is_empty():
			var del_text := "ТОЧНО УДАЛИТЬ?" if _confirm_del == n else "УДАЛИТЬ"
			var del := _button(del_text, Color(1.0, 0.3, 0.35), 280)
			del.pressed.connect(func():
				Sound.play("click")
				if _confirm_del == n:
					_confirm_del = 0
					Meta.delete_slot(n)
					_refresh_badge()
				else:
					_confirm_del = n
				_fill_saves())
			cv.add_child(del)


# ---------- Значок профиля в углу меню ----------

var _badge_name: Label
var _badge_pic: TextureRect


func _add_profile_badge() -> void:
	var b := Button.new()
	b.position = Vector2(16, 14)
	b.custom_minimum_size = Vector2(250, 64)
	b.add_theme_stylebox_override("normal", _box(Color(1.0, 0.8, 0.3).darkened(0.3), PANEL_BG, 2, 6))
	b.add_theme_stylebox_override("hover", _box(Color(1.0, 0.8, 0.3), PANEL_BG, 2, 12))
	b.add_theme_stylebox_override("focus", _box(Color(1.0, 0.8, 0.3), PANEL_BG, 2, 12))
	b.add_theme_stylebox_override("pressed", _box(Color.WHITE, PANEL_BG, 2, 12))
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func():
		Sound.play("click")
		_show("profile"))
	add_child(b)
	var h := HBoxContainer.new()
	h.position = Vector2(8, 6)
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	_badge_pic = TextureRect.new()
	_badge_pic.custom_minimum_size = Vector2(56, 56)
	_badge_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_badge_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_badge_pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_badge_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_badge_pic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	_badge_name = _label("", 20, Color(1.0, 0.9, 0.6))
	_badge_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_badge_name)
	var sub := _label("профиль", 13, Color(0.7, 0.7, 0.85))
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sub)
	_refresh_badge()


func _refresh_badge() -> void:
	if _badge_name == null:
		return
	Meta.ensure_loaded()
	_badge_name.text = Meta.nickname
	var hero: String = Data.selected_character if Data.CHARACTERS.has(Data.selected_character) else "vega"
	_badge_pic.texture = Pixel.portrait(Data.CHARACTERS[hero]["sprite"])


# ---------- Профиль игрока: ник и статистика ----------

var _nick_edit: LineEdit
var _stats_grid: GridContainer
var _prof_hero: Control


func _build_profile_page() -> void:
	var v := _page("profile")
	var title := _label("ПРОФИЛЬ", 44, Color.WHITE, Color(Color(1.0, 0.8, 0.3), 0.8))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var panel := PanelContainer.new()
	var pb := _box(Color(1.0, 0.8, 0.3).darkened(0.3), PANEL_BG, 2, 10)
	pb.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", pb)
	v.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	# Ник — его видит напарник в сетевой игре
	var nick_row := HBoxContainer.new()
	nick_row.add_theme_constant_override("separation", 14)
	box.add_child(nick_row)
	nick_row.add_child(_row_label("Ник"))
	_nick_edit = LineEdit.new()
	_nick_edit.max_length = 16
	_nick_edit.custom_minimum_size = Vector2(320, 44)
	_nick_edit.add_theme_font_size_override("font_size", 22)
	_nick_edit.placeholder_text = "Введите ник"
	_nick_edit.text_changed.connect(func(t: String):
		var clean := t.strip_edges()
		Meta.nickname = clean if clean != "" else "Охотник"
		Meta.save()
		_refresh_badge())
	nick_row.add_child(_nick_edit)
	_vk_field(_nick_edit, "НИК ОХОТНИКА", "", func(t: String):
		_nick_edit.text = t
		_nick_edit.text_changed.emit(t))
	var hint := _label("Ник виден напарнику над героем в сетевой игре", 14, Color(0.7, 0.7, 0.85))
	box.add_child(hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	box.add_child(row)
	_prof_hero = Control.new()
	_prof_hero.custom_minimum_size = Vector2(150, 150)
	row.add_child(_prof_hero)
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 2
	_stats_grid.add_theme_constant_override("h_separation", 40)
	_stats_grid.add_theme_constant_override("v_separation", 3)
	row.add_child(_stats_grid)
	var back := _button("НАЗАД", Color(0.6, 0.6, 0.75))
	back.pressed.connect(func():
		Sound.play("click")
		_profile_back())
	v.add_child(back)


## Поле ввода на ПК / Steam Deck / геймпаде: нажатие (мышь, тачскрин, A/Enter) открывает
## экранную клавиатуру — она же принимает и обычную клавиатуру. На телефоне — системная клавиатура.
func _vk_field(edit: LineEdit, title: String, allowed: String, on_done: Callable) -> void:
	if Settings.is_mobile():
		return
	edit.editable = false
	edit.focus_mode = Control.FOCUS_ALL
	edit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	edit.add_theme_color_override("font_uneditable_color", Color.WHITE)
	var foc := StyleBoxFlat.new()
	foc.bg_color = Color(0, 0, 0, 0)
	foc.draw_center = false
	foc.border_color = CYAN
	foc.set_border_width_all(3)
	foc.set_corner_radius_all(4)
	edit.add_theme_stylebox_override("focus", foc)
	var opening := [false]
	var open := func():
		if opening[0]:
			return
		opening[0] = true
		Sound.play("click")
		var start := edit.text
		if edit == _nick_edit and start == "Охотник":
			start = ""
		var vk = preload("res://scripts/vkeyboard.gd").open(self, title, start, edit.max_length if edit.max_length > 0 else 16, allowed)
		vk.done.connect(on_done)
		vk.tree_exited.connect(func():
			opening[0] = false
			if is_instance_valid(edit):
				edit.grab_focus())
	edit.gui_input.connect(func(ev: InputEvent):
		var hit: bool = (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) \
			or (ev is InputEventScreenTouch and ev.pressed) or ev.is_action_pressed("ui_accept")
		if hit:
			edit.accept_event()
			open.call())


## Назад из профиля: туда, откуда пришли (из убежища — обратно в убежище).
func _profile_back() -> void:
	if Data.menu_return == "hub":
		Data.menu_return = ""
		var tw := create_tween()
		tw.tween_property(self, "modulate", Color(0, 0, 0, 1), 0.25)
		tw.tween_callback(func(): Loader.go("res://hub.tscn"))
		return
	_show("main")


func _fill_profile() -> void:
	Meta.ensure_loaded()
	_nick_edit.text = Meta.nickname
	for c in _stats_grid.get_children():
		c.queue_free()
	for c in _prof_hero.get_children():
		c.queue_free()
	var s: Dictionary = Meta.stats
	# Любимый герой — с которым больше всего вылазок
	var fav := Data.selected_character
	var heroes: Dictionary = s.get("heroes", {})
	var best := -1
	for h in heroes:
		if int(heroes[h]) > best and Data.CHARACTERS.has(h):
			best = int(heroes[h])
			fav = h
	var st := _sprite_stack(Data.CHARACTERS[fav]["sprite"], 150, true)
	_prof_hero.add_child(st)
	var t: float = float(s.get("time", 0.0))
	var rows := [
		["Вылазок", str(Meta.total_runs)],
		["Победы / поражения", "%d / %d" % [int(s.get("wins", 0)), int(s.get("deaths", 0))]],
		["Время в бою", "%d ч %02d мин" % [int(t / 3600.0), int(t / 60.0) % 60]],
		["Лучшее время", "%02d:%02d" % [int(Meta.best_time / 60.0), int(Meta.best_time) % 60]],
		["Врагов повержено", str(int(s.get("kills", 0)))],
		["Рекорд убийств за вылазку", str(int(s.get("best_kills", 0)))],
		["Боссов повержено", str(int(s.get("bosses", 0)))],
		["Реакций стихий", str(int(s.get("reactions", 0)))],
		["Максимальный уровень героя", str(int(s.get("max_level", 0)))],
		["Рекорд бесконечного режима", "%d мин" % int(s.get("best_endless", 0))],
		["Пройдено уровней", "%d / %d" % [Meta.levels_cleared, Data.LEVELS.size()]],
		["Осколков заработано", str(int(s.get("shards", 0)))],
		["Любимый герой", "%s (%d)" % [Data.CHARACTERS[fav]["name"], maxi(best, 0)]],
	]
	for r in rows:
		_stats_grid.add_child(_label(r[0], 16, Color(0.8, 0.8, 0.95)))
		_stats_grid.add_child(_label(r[1], 16, Color(1.0, 0.85, 0.4)))


# ---------- Кооператив: лобби на одном экране ----------

var _coop_slots: Array = []   # [{dev, hero, ready, panel, ...}]
var _coop_level := 0
var _coop_level_l: Label
var _coop_level_d: Label
var _coop_hint: Label
var _coop_start: Button
var _join_block := true
var _coop_back_t := 0.0


func _unlocked_heroes() -> Array:
	var out: Array = []
	for id in Data.CHARACTERS:
		if Meta.hero_unlocked(id):
			out.append(id)
	return out


func _build_coop_page() -> void:
	var v := _page("coop")
	var title := _label("КООПЕРАТИВ", 48, Color.WHITE, Color(MAGENTA, 0.8))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := _label("Два героя на одном экране. Каждый игрок управляет своим устройством.", 16, Color(0.8, 0.8, 0.95))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	v.add_child(row)
	for i in 2:
		var slot := _coop_panel(i)
		_coop_slots.append(slot)
		if i == 0:
			row.add_child(slot["panel"])
			row.add_child(_coop_level_panel())
		else:
			row.add_child(slot["panel"])
	_coop_hint = _label("", 15, Color(0.75, 0.75, 0.9))
	_coop_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_coop_hint)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	var back := _button("НАЗАД", Color(0.6, 0.6, 0.75), 200)
	back.pressed.connect(func():
		Sound.play("click")
		_show("main"))
	buttons.add_child(back)
	_coop_start = _button("В БОЙ ВДВОЁМ!", GOLD, 320)
	_coop_start.pressed.connect(_coop_launch)
	buttons.add_child(_coop_start)
	v.add_child(buttons)


func _coop_panel(i: int) -> Dictionary:
	var col := CYAN if i == 0 else Color(1.0, 0.4, 0.75)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(330, 430)
	panel.add_theme_stylebox_override("panel", _box(col.darkened(0.3), PANEL_BG, 2, 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var head := _label("ИГРОК %d" % (i + 1), 26, col, Color(col, 0.7))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	var dev_l := _label("", 13, Color(0.75, 0.75, 0.9))
	dev_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dev_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(dev_l)
	var portrait := _sprite_stack("hero", 150, true)
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(portrait)
	var name_l := _label("", 28, Color.WHITE)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_l)
	var info_l := _label("", 14, Color(0.85, 0.85, 0.95))
	info_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_l.custom_minimum_size = Vector2(300, 0)
	v.add_child(info_l)
	var state_l := _label("", 18, GOLD, Color(GOLD, 0.5))
	state_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state_l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	state_l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	v.add_child(state_l)
	return {"panel": panel, "dev": null, "input": null, "hero": 0, "ready": false, "color": col,
		"dev_l": dev_l, "portrait": portrait, "name_l": name_l, "info_l": info_l, "state_l": state_l}


func _coop_level_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(330, 430)
	panel.add_theme_stylebox_override("panel", _box(GOLD.darkened(0.3), PANEL_BG, 2, 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var head := _label("УРОВЕНЬ", 26, GOLD, Color(GOLD, 0.6))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	var up := _button("▲", GOLD, 120)
	up.pressed.connect(func(): _coop_change_level(-1))
	v.add_child(up)
	_coop_level_l = _label("", 24, Color.WHITE, Color(GOLD, 0.5))
	_coop_level_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coop_level_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_coop_level_l.custom_minimum_size = Vector2(300, 0)
	v.add_child(_coop_level_l)
	_coop_level_d = _label("", 14, Color(0.8, 0.8, 0.95))
	_coop_level_d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coop_level_d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_coop_level_d.custom_minimum_size = Vector2(300, 0)
	v.add_child(_coop_level_d)
	var down := _button("▼", GOLD, 120)
	down.pressed.connect(func(): _coop_change_level(1))
	v.add_child(down)
	var help := _label("Уровень меняет Игрок 1: вверх / вниз", 13, Color(0.7, 0.7, 0.85))
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.size_flags_vertical = Control.SIZE_EXPAND_FILL
	help.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	v.add_child(help)
	return panel


func _coop_reset() -> void:
	_join_block = true
	_coop_level = clampi(Data.selected_level, 0, mini(Meta.levels_cleared, Data.LEVELS.size() - 1))
	var heroes := _unlocked_heroes()
	for i in _coop_slots.size():
		var sl: Dictionary = _coop_slots[i]
		sl["dev"] = null
		sl["input"] = null
		sl["ready"] = false
		var want: String = Data.selected_character if i == 0 else Data.selected_character2
		sl["hero"] = maxi(0, heroes.find(want))
		_coop_refresh(i)
	_coop_change_level(0)


func _coop_change_level(d: int) -> void:
	var max_l := mini(Meta.levels_cleared, Data.LEVELS.size() - 1)
	_coop_level = clampi(_coop_level + d, 0, max_l)
	var lv: Dictionary = Data.LEVELS[_coop_level]
	_coop_level_l.text = "%d. %s" % [_coop_level + 1, lv["name"]]
	_coop_level_d.text = "%s\n\nВремя: %d:%02d\nОткрыто уровней: %d / %d" % [lv["desc"], int(lv["time"]) / 60, int(lv["time"]) % 60, max_l + 1, Data.LEVELS.size()]
	if d != 0:
		Sound.play("hover", -6.0)


func _coop_refresh(i: int) -> void:
	var sl: Dictionary = _coop_slots[i]
	var heroes := _unlocked_heroes()
	var id: String = heroes[clampi(sl["hero"], 0, heroes.size() - 1)]
	var c: Dictionary = Data.CHARACTERS[id]
	var joined: bool = sl["dev"] != null
	sl["panel"].modulate = Color.WHITE if joined else Color(0.6, 0.6, 0.7)
	sl["dev_l"].text = DevInput.device_name(sl["dev"]) if joined else "Свободно"
	sl["name_l"].text = c["name"]
	sl["name_l"].add_theme_color_override("font_shadow_color", Color(c["color"], 0.8))
	sl["info_l"].text = "%s\nОружие: %s\n%s" % [c["title"], Data.WEAPONS[c["weapon"]]["name"], c["active"]]
	if not joined:
		sl["state_l"].text = "Нажмите A на геймпаде" if Settings.input_mode() != "kb" else "Нажмите ПРОБЕЛ, ENTER\nили A на геймпаде"
	elif sl["ready"]:
		sl["state_l"].text = "✓ ГОТОВ"
	else:
		sl["state_l"].text = "◀ ▶ герой   •   %s — готов" % DevInput.ability_hint(sl["dev"])
	for entry in _portraits:
		if entry[0].get_parent() == sl["portrait"]:
			entry[1] = Pixel.frames(c["sprite"])


func _coop_tick(delta: float) -> void:
	if _page_name != "coop":
		return
	var used: Array = []
	for sl in _coop_slots:
		if sl["dev"] != null:
			used.append(sl["dev"])
	var j = DevInput.detect_join()
	if j == null:
		_join_block = false
	elif not _join_block and not (j in used):
		for i in _coop_slots.size():
			if _coop_slots[i]["dev"] == null:
				_coop_slots[i]["dev"] = j
				var inp = DevInput.new(j)
				inp.poll()
				inp.poll()
				_coop_slots[i]["input"] = inp
				Sound.play("levelup", -6.0, 1.0 + i * 0.2)
				_coop_refresh(i)
				break
		_join_block = true
	var heroes := _unlocked_heroes()
	for i in _coop_slots.size():
		var sl: Dictionary = _coop_slots[i]
		var inp = sl["input"]
		if inp == null:
			continue
		inp.poll()
		if not sl["ready"]:
			if inp.just("left") or inp.just("right"):
				sl["hero"] = wrapi(sl["hero"] + (1 if inp.just("right") else -1), 0, heroes.size())
				Sound.play("hover", -6.0)
				_coop_refresh(i)
			if i == 0 and (inp.just("up") or inp.just("down")):
				_coop_change_level(-1 if inp.just("up") else 1)
			if inp.just("ok"):
				sl["ready"] = true
				Sound.play("click")
				_coop_refresh(i)
		if inp.just("back"):
			if sl["ready"]:
				sl["ready"] = false
			else:
				sl["dev"] = null
				sl["input"] = null
			_join_block = true
			_coop_refresh(i)
	var both: bool = _coop_slots[0]["dev"] != null and _coop_slots[1]["dev"] != null
	_coop_start.disabled = not both
	_coop_hint.text = "Ждём второго игрока: нажмите кнопку на своём устройстве" if not both else "Когда оба готовы — бой начнётся сам (или нажмите «В бой вдвоём»)"
	if both and _coop_slots[0]["ready"] and _coop_slots[1]["ready"]:
		_coop_launch()
	# Esc / B, когда никто не вошёл — назад в меню
	if not both and _coop_slots[0]["dev"] == null and _coop_slots[1]["dev"] == null and Input.is_action_just_pressed("ui_cancel"):
		_show("main")


func _coop_launch() -> void:
	if _page_name != "coop":
		return
	var heroes := _unlocked_heroes()
	Data.coop = true
	Data.selected_character = heroes[_coop_slots[0]["hero"]]
	Data.selected_character2 = heroes[_coop_slots[1]["hero"]]
	Data.coop_devices = [_coop_slots[0]["dev"], _coop_slots[1]["dev"]]
	Data.selected_level = _coop_level
	Data.world_seed = 0
	_page_name = ""
	Sound.play("levelup", 0.0)
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(0, 0, 0, 1), 0.35)
	tw.tween_callback(func(): Loader.go("res://main.tscn"))


# ---------- Сетевая игра (LAN) ----------

var _net_v: VBoxContainer
var _net_status: Label
var _net_ip: LineEdit
var _net_hosts_box: VBoxContainer
var _net_conn_box: VBoxContainer
var _net_lobby_box: VBoxContainer
var _net_ready := false
var _net_hero := 0
var _net_level := 0
var _net_input
var _net_sig := ""
var _net_leaving := false


func _build_net_page() -> void:
	_net_v = _page("net")
	var title := _label("СЕТЕВАЯ ИГРА", 48, Color.WHITE, Color(Color(0.4, 1.0, 0.6), 0.8))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_net_v.add_child(title)
	_net_status = _label("Два компьютера в одной локальной сети (Wi-Fi или кабель).", 16, Color(0.8, 0.8, 0.95))
	_net_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_net_v.add_child(_net_status)

	# Подключение
	_net_conn_box = VBoxContainer.new()
	_net_conn_box.add_theme_constant_override("separation", 12)
	_net_v.add_child(_net_conn_box)
	var host_btn := _button("СОЗДАТЬ ИГРУ — В МОЁ УБЕЖИЩЕ", Color(0.4, 1.0, 0.6), 520)
	host_btn.pressed.connect(func():
		Sound.play("click")
		var err: String = Net.host()
		_net_status.text = err if err != "" else "Игра создана. Ждём второго игрока...  Ваши адреса: " + _local_ips()
		if err == "":
			_net_push()
		_net_refresh())
	_net_conn_box.add_child(host_btn)
	var found := _label("Найденные игры в сети:", 18, CYAN)
	found.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_net_conn_box.add_child(found)
	_net_hosts_box = VBoxContainer.new()
	_net_hosts_box.add_theme_constant_override("separation", 8)
	_net_conn_box.add_child(_net_hosts_box)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	_net_ip = LineEdit.new()
	_net_ip.placeholder_text = "IP хоста, например 192.168.1.5"
	_net_ip.custom_minimum_size = Vector2(300, 52)
	_net_ip.add_theme_font_size_override("font_size", 20)
	row.add_child(_net_ip)
	_vk_field(_net_ip, "IP ХОСТА", "0123456789.", func(t: String): _net_ip.text = t)
	var join_btn := _button("ПОДКЛЮЧИТЬСЯ", CYAN, 260)
	join_btn.pressed.connect(func():
		Sound.play("click")
		_net_join(_net_ip.text.strip_edges()))
	row.add_child(join_btn)
	_net_conn_box.add_child(row)

	# Лобби
	_net_lobby_box = VBoxContainer.new()
	_net_lobby_box.add_theme_constant_override("separation", 12)
	_net_v.add_child(_net_lobby_box)

	var back := _button("НАЗАД", Color(0.6, 0.6, 0.75), 260)
	back.pressed.connect(func():
		Sound.play("click")
		Net.leave()
		Net.listen(false)
		_show("main"))
	_net_v.add_child(back)

	Net.lobby_changed.connect(_net_refresh)
	Net.hosts_changed.connect(_net_fill_hosts)
	Net.status.connect(func(t: String):
		if is_instance_valid(_net_status):
			_net_status.text = t
		_net_refresh())


func _local_ips() -> String:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return ", ".join(out) if not out.is_empty() else "не найдены"


func _net_join(ip: String) -> void:
	if ip == "":
		_net_status.text = "Введите IP хоста или выберите игру из списка"
		return
	var heroes := _unlocked_heroes()
	Net.lobby["hero2"] = heroes[clampi(_net_hero, 0, heroes.size() - 1)]
	var err: String = Net.join(ip)
	if err != "":
		_net_status.text = err
	_net_refresh()


func _net_fill_hosts() -> void:
	if _net_hosts_box == null:
		return
	for c in _net_hosts_box.get_children():
		c.queue_free()
	if Net.hosts.is_empty():
		var l := _label("Поиск...  (хост должен нажать «Создать игру»)", 14, Color(0.6, 0.6, 0.75))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_net_hosts_box.add_child(l)
		return
	for ip in Net.hosts:
		var h: Dictionary = Net.hosts[ip]
		var b := _button("%s  —  %s%s" % [h["name"], ip, "  (занято)" if h["busy"] else ""], CYAN, 520)
		b.disabled = h["busy"]
		b.pressed.connect(func():
			Sound.play("click")
			_net_join(ip))
		_net_hosts_box.add_child(b)


func _net_refresh() -> void:
	if _net_lobby_box == null:
		return
	var in_lobby: bool = Net.mode == "host" or (Net.mode == "client" and Net.lobby.get("client", false))
	_net_conn_box.visible = Net.mode == ""
	Net.listen(_page_name == "net" and Net.mode == "")
	if Net.mode == "":
		_net_fill_hosts()
	for c in _net_lobby_box.get_children():
		c.queue_free()
	if Net.mode == "client":
		_net_status.text = "Подключено — входим в убежище хоста..." if in_lobby else "Подключение..."
	return
	var lob: Dictionary = Net.lobby
	var me := 0 if Net.mode == "host" else 1
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	_net_lobby_box.add_child(row)
	for i in 2:
		row.add_child(_net_player_panel(i, i == me, lob))
		if i == 0:
			row.add_child(_net_level_panel(Net.mode == "host", int(lob["level"])))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	var rd := _button("НЕ ГОТОВ" if _net_ready else "ГОТОВ!", GOLD, 260)
	rd.pressed.connect(func():
		_net_ready = not _net_ready
		Sound.play("click")
		_net_push())
	buttons.add_child(rd)
	if Net.mode == "host":
		var st := _button("НАЧАТЬ", Color(0.4, 1.0, 0.6), 260)
		st.disabled = not Net.can_start()
		st.pressed.connect(func(): Net.start())
		buttons.add_child(st)
	_net_lobby_box.add_child(buttons)
	if Net.mode == "host" and not lob["client"]:
		_net_status.text = "Ждём второго игрока...  Ваши адреса: " + _local_ips()
	elif Net.mode == "host":
		_net_status.text = "Игрок 2 подключён. Когда оба готовы — нажмите «Начать»" if not Net.can_start() else "Все готовы!"
	else:
		_net_status.text = "Вы — Игрок 2. Ждём, когда хост начнёт игру"


func _net_player_panel(i: int, mine: bool, lob: Dictionary) -> Control:
	var col := CYAN if i == 0 else Color(1.0, 0.4, 0.75)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 360)
	panel.add_theme_stylebox_override("panel", _box(col.darkened(0.3) if not mine else col, PANEL_BG, 2, 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var connected: bool = i == 0 or lob["client"]
	var head := _label("ИГРОК %d%s" % [i + 1, "  (вы)" if mine else ""], 24, col, Color(col, 0.6))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	if not connected:
		var w := _label("Ожидание подключения...", 16, Color(0.7, 0.7, 0.85))
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(w)
		return panel
	var hid: String = lob["hero1"] if i == 0 else lob["hero2"]
	var c: Dictionary = Data.CHARACTERS.get(hid, Data.CHARACTERS["vega"])
	var portrait := _sprite_stack(c["sprite"], 140, true)
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(portrait)
	var nm := _label(c["name"], 26, Color.WHITE, Color(c["color"], 0.8))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nm)
	var inf := _label("%s\nОружие: %s" % [c["title"], Data.WEAPONS[c["weapon"]]["name"]], 14, Color(0.85, 0.85, 0.95))
	inf.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(inf)
	if mine:
		var hb := HBoxContainer.new()
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.add_theme_constant_override("separation", 10)
		var l := _button("◀", col, 80)
		l.pressed.connect(func(): _net_cycle(-1))
		var r := _button("▶", col, 80)
		r.pressed.connect(func(): _net_cycle(1))
		hb.add_child(l)
		hb.add_child(r)
		v.add_child(hb)
	var ready: bool = lob["ready1"] if i == 0 else lob["ready2"]
	var rl := _label("✓ ГОТОВ" if ready else "выбирает...", 18, GOLD if ready else Color(0.7, 0.7, 0.85))
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(rl)
	return panel


func _net_level_panel(editable: bool, lvl: int) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 360)
	panel.add_theme_stylebox_override("panel", _box(GOLD.darkened(0.3), PANEL_BG, 2, 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var head := _label("УРОВЕНЬ", 24, GOLD, Color(GOLD, 0.6))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	var lv: Dictionary = Data.LEVELS[clampi(lvl, 0, Data.LEVELS.size() - 1)]
	var nl := _label("%d. %s" % [lvl + 1, lv["name"]], 22, Color.WHITE, Color(GOLD, 0.5))
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.custom_minimum_size = Vector2(270, 0)
	v.add_child(nl)
	var dl := _label(lv["desc"], 14, Color(0.8, 0.8, 0.95))
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.custom_minimum_size = Vector2(270, 0)
	v.add_child(dl)
	if editable:
		var hb := HBoxContainer.new()
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.add_theme_constant_override("separation", 10)
		var a := _button("◀", GOLD, 80)
		a.pressed.connect(func(): _net_change_level(-1))
		var b := _button("▶", GOLD, 80)
		b.pressed.connect(func(): _net_change_level(1))
		hb.add_child(a)
		hb.add_child(b)
		v.add_child(hb)
		var hint := _label("Доступно уровней: %d" % (mini(Meta.levels_cleared, Data.LEVELS.size() - 1) + 1), 13, Color(0.7, 0.7, 0.85))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(hint)
	else:
		var hint := _label("Уровень выбирает хост", 13, Color(0.7, 0.7, 0.85))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(hint)
	return panel


func _net_cycle(d: int) -> void:
	var heroes := _unlocked_heroes()
	_net_hero = wrapi(_net_hero + d, 0, heroes.size())
	_net_ready = false
	Sound.play("hover", -6.0)
	_net_push()


func _net_change_level(d: int) -> void:
	_net_level = clampi(_net_level + d, 0, mini(Meta.levels_cleared, Data.LEVELS.size() - 1))
	Sound.play("hover", -6.0)
	_net_push()


func _net_push() -> void:
	var heroes := _unlocked_heroes()
	var id: String = heroes[clampi(_net_hero, 0, heroes.size() - 1)]
	Net.set_local(id, _net_ready, _net_level if Net.mode == "host" else -1)


func _net_tick(_delta: float) -> void:
	if _page_name != "net":
		return
	# Хост сразу уходит в своё убежище — второй игрок придёт туда
	if Net.mode == "host" and not _net_leaving:
		_net_leaving = true
		Net.listen(false)
		Loader.go("res://hub.tscn")
		return
	var sig := str(Net.mode) + str(Net.lobby)
	if sig != _net_sig:
		_net_sig = sig
		_net_refresh()
