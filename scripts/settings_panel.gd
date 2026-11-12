extends VBoxContainer
## Панель настроек: экран, графика, кадры, эффекты, тени, текстуры, память, звук.
## Одна и та же панель — в главном меню и в паузе во время боя / в убежище.

const Data := preload("res://scripts/data.gd")
const CYAN := Color(0.3, 0.95, 1.0)
const MAGENTA := Color(1.0, 0.3, 0.75)
const PANEL_BG := Color(0.05, 0.03, 0.1, 0.92)

var on_back: Callable
var compact := false   # в паузе — без заголовка-крупняка


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_mem_t -= delta
	if _mem_t <= 0.0:
		_mem_t = 0.5
		_update_memory()


var _mem_bar: ProgressBar
var _mem_label: Label
var _mem_t := 0.0


## Память игры: занятая ОЗУ от всей памяти компьютера, пик и видеопамять.
func _update_memory() -> void:
	if _mem_label == null:
		return
	var used := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var peak := Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1048576.0
	var vram := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var tex := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
	var info := OS.get_memory_info()
	var total: float = float(info.get("physical", 0)) / 1048576.0
	var avail: float = float(info.get("available", 0)) / 1048576.0
	if total <= 0.0:
		total = maxf(peak, 1.0)
	if used <= 0.0:
		# В выпущенной сборке Godot не считает свою ОЗУ — показываем видеопамять игры
		# и общую загрузку памяти компьютера
		var sys_used := maxf(0.0, total - avail)
		var pct_sys := clampf(sys_used / total * 100.0, 0.0, 100.0)
		_mem_bar.max_value = 100.0
		_mem_bar.value = maxf(pct_sys, 0.5)
		_mem_label.text = "Игра: видео %d МБ (текстуры %d) • ОЗУ ПК: %.1f из %.1f ГБ (%d%%)" % [int(vram), int(tex), sys_used / 1024.0, total / 1024.0, int(pct_sys)]
		return
	var pct := clampf((used + vram) / total * 100.0, 0.0, 100.0)
	_mem_bar.max_value = 100.0
	_mem_bar.value = maxf(pct, 0.5)
	_mem_label.text = "ОЗУ %d МБ (пик %d) • видео %d МБ • %.1f%% от %.1f ГБ" % [int(used), int(peak), int(vram), pct, total / 1024.0]


## Вкладки: Видео (экран, кадры), Графика (качество картинки), Звук.
static var tab := "video"
const TABS := [["video", "ВИДЕО"], ["graphics", "ГРАФИКА"], ["sound", "ЗВУК"]]
const TAB_OF := {
	"Режим экрана": "video", "Формат": "video", "Разрешение 3D": "video", "Чёткость 3D": "video",
	"Пиксельный 3D": "video", "Кадры в секунду": "video", "Вертикальная синхр.": "video",
	"Держать кадры": "video", "Кнопки": "video", "Взгляд героя": "video", "Память": "video", "Графика": "video",
	"Профиль": "graphics", "Свечение": "graphics", "Погода": "graphics", "Декор пола": "graphics",
	"Дальность": "graphics", "Врагов на экране": "graphics", "Объёмные эффекты": "graphics",
	"Эффекты": "graphics", "Тени": "graphics", "Текстуры": "graphics",
	"Музыка": "sound", "Звуки": "sound",
}


## Оставить в сетке только пары «название — значение» текущей вкладки.
func _filter_tab(grid: GridContainer) -> void:
	var kids := grid.get_children()
	var i := 0
	while i + 1 < kids.size():
		var l: Node = kids[i]
		var ctl: Node = kids[i + 1]
		var name := str(l.get("text")) if l is Label else ""
		if TAB_OF.get(name, "video") != tab:
			for n in [l, ctl]:
				grid.remove_child(n)
				n.queue_free()
			if name == "Память":
				_mem_label = null
				_mem_bar = null
			elif name == "Режим экрана":
				_mode_opt = null
			elif name == "Формат":
				_aspect_opt = null
			elif name == "Разрешение 3D":
				_res_opt = null
		i += 2


func _build() -> void:
	var v := self
	var title := _label("НАСТРОЙКИ", 44, Color.WHITE, Color(MAGENTA, 0.8))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var tabs := HFlowContainer.new()
	tabs.alignment = FlowContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("h_separation", 12)
	tabs.add_theme_constant_override("v_separation", 8)
	for t in TABS:
		var on: bool = t[0] == tab
		var tb := _button(t[1], CYAN if on else Color(0.55, 0.55, 0.7), 190)
		if on:
			tb.add_theme_stylebox_override("normal", _box(CYAN, Color(0.1, 0.25, 0.32, 0.95), 3, 14))
		var key: String = t[0]
		tb.pressed.connect(func():
			Sound.play("click")
			Settings.save_settings()
			tab = key
			_rebuild.call_deferred())
		tabs.add_child(tb)
	v.add_child(tabs)

	var panel := PanelContainer.new()
	var pb := _box(CYAN.darkened(0.3), PANEL_BG, 2, 10)
	pb.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", pb)
	v.add_child(panel)
	var grid := GridContainer.new()
	grid.columns = 2 if (Settings.is_portrait() or get_viewport().get_visible_rect().size.x < 1180.0) else 4   # «название — значение», на вертикальном экране — одна пара в ряд
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 12)
	panel.add_child(grid)

	# --- Телефон: только чёткость картинки (окна и форматы не нужны) ---
	# Профиль графики — во всех версиях: разом выставляет все пункты ниже
	grid.add_child(_row_label("Профиль"))
	var pr_opt := _option(Settings.PRESET_NAMES + ["Свой"])
	pr_opt.selected = Settings.preset if Settings.preset >= 0 else Settings.PRESET_NAMES.size()
	pr_opt.item_selected.connect(func(i: int):
		if i < Settings.PRESET_NAMES.size():
			Settings.apply_preset(i)
			_rebuild.call_deferred())
	grid.add_child(pr_opt)
	if Settings.is_mobile():
		grid.add_child(_row_label("Чёткость 3D"))
		var mh_opt := _option(["360p — минимум", "450p — очень быстро", "540p — быстрее", "720p — баланс", "900p", "1080p — чётче"])
		mh_opt.selected = maxi(0, Settings.MOBILE_HEIGHTS.find(Settings.mobile_h))
		mh_opt.item_selected.connect(func(i: int):
			Settings.preset = -1
			Settings.mobile_h = Settings.MOBILE_HEIGHTS[i]
			Settings.apply_display()
			Settings.save_settings())
		grid.add_child(mh_opt)
		grid.add_child(_row_label("Кнопки"))
		var ts_opt := _option(["Маленькие", "Обычные", "Крупные"])
		ts_opt.selected = clampi(Settings.touch_size, 0, 2)
		ts_opt.item_selected.connect(func(i: int):
			Settings.touch_size = i
			Settings.save_settings())
		grid.add_child(ts_opt)
	else:
		_build_desktop_rows(grid)
	# Тонкие настройки нагрузки — во всех версиях (ПК, Steam Deck, телефоны, браузер)
	_mob_opt(grid, "Свечение", ["Выключено (быстрее)", "Включено"], 1 if Settings.glow else 0, func(i): Settings.glow = i == 1)
	_mob_opt(grid, "Погода", ["Выключена (быстрее)", "Включена"], 1 if Settings.weather else 0, func(i): Settings.weather = i == 1)
	_mob_opt(grid, "Декор пола", ["Упрощённый", "Полный"], Settings.decor, func(i): Settings.decor = i)
	_mob_opt(grid, "Дальность", ["Ближняя (быстрее)", "Средняя", "Полная"], Settings.view_dist, func(i): Settings.view_dist = i)
	_mob_opt(grid, "Врагов на экране", ["Меньше, но крепче", "Обычно"], Settings.crowd, func(i): Settings.crowd = i)
	_mob_opt(grid, "Держать кадры", ["Нет", "Да — упрощать при просадке"], 1 if Settings.adaptive else 0, func(i): Settings.adaptive = i == 1)
	_build_common_rows(grid)


func _build_desktop_rows(grid: GridContainer) -> void:
	# --- Экран ---
	grid.add_child(_row_label("Режим экрана"))
	_mode_opt = _option(["Полный экран", "В окне", "В окне без рамки"])
	_mode_opt.selected = ["fullscreen", "windowed", "borderless"].find(Settings.mode)
	grid.add_child(_mode_opt)

	grid.add_child(_row_label("Формат"))
	_aspect_opt = _option(["Как у монитора", "16:9", "16:10", "21:9", "4:3", "5:4"])
	_aspect_opt.selected = maxi(0, Settings.FORMATS.find(Settings.aspect))
	_aspect_opt.item_selected.connect(func(_i: int): _fill_resolutions(Vector2i.ZERO))
	grid.add_child(_aspect_opt)

	grid.add_child(_row_label("Разрешение 3D"))
	_res_opt = _option([])
	grid.add_child(_res_opt)
	_fill_resolutions(Settings.resolution)

	# --- Графический API --- (в браузере всегда WebGL — пункт не нужен)
	if Settings.is_web():
		return
	grid.add_child(_row_label("Графика"))
	var api_box := VBoxContainer.new()
	var api_opt := _option(["Vulkan", "DirectX 12", "OpenGL (для старых видеокарт)"])
	api_opt.selected = maxi(0, Settings.APIS.find(Settings.api))
	var api_note := _label("Сейчас: %s" % RenderingServer.get_current_rendering_driver_name(), 13, Color(0.7, 0.7, 0.85))
	api_opt.item_selected.connect(func(i: int):
		Sound.play("click")
		api_note.text = Settings.set_api(Settings.APIS[i]))
	api_box.add_child(api_opt)
	api_box.add_child(api_note)
	grid.add_child(api_box)


func _build_common_rows(grid: GridContainer) -> void:
	var v := self
	_mob_opt(grid, "Пиксельный 3D", ["Выкл — гладко", "Мелкие пиксели", "Средние пиксели", "Крупные пиксели"], Settings.pixel_art, func(i):
		Settings.pixel_art = i
		Settings._apply_3d_scale())
	_mob_opt(grid, "Объёмные эффекты", ["Плоские — быстрее", "3D-искры, взрывы, обломки"], 1 if Settings.fx3d else 0, func(i): Settings.fx3d = i == 1)
	if not Settings.is_mobile():
		_mob_opt(grid, "Взгляд героя", ["Автоприцел", "Мышь / правый стик"], 1 if Settings.manual_aim else 0, func(i): Settings.manual_aim = i == 1)
	# --- Кадры и синхронизация ---
	grid.add_child(_row_label("Кадры в секунду"))
	var fps_names: Array = []
	for f in Settings.FPS_OPTIONS:
		fps_names.append("По частоте экрана (%d Гц)" % Settings.refresh_rate() if f == "monitor" else ("Без ограничения" if f == "0" else "%s кадров" % f))
	var fps_opt := _option(fps_names)
	fps_opt.selected = maxi(0, Settings.FPS_OPTIONS.find(Settings.fps))
	fps_opt.item_selected.connect(func(i: int):
		Settings.fps = Settings.FPS_OPTIONS[i]
		Settings.apply_graphics()
		Settings.save_settings())
	grid.add_child(fps_opt)

	grid.add_child(_row_label("Вертикальная синхр."))
	var vs_keys := ["on", "adaptive", "off"]
	var vs_opt := _option(["Включена", "Адаптивная", "Выключена"])
	vs_opt.selected = maxi(0, vs_keys.find(Settings.vsync))
	vs_opt.item_selected.connect(func(i: int):
		Settings.vsync = vs_keys[i]
		Settings.apply_graphics()
		Settings.save_settings())
	grid.add_child(vs_opt)

	# --- Эффекты, тени, текстуры ---
	grid.add_child(_row_label("Эффекты"))
	var fx_names := ["Минимум", "Мало", "Средне", "Много"]
	var fx_shift := 1
	var fx_opt := _option(fx_names)
	fx_opt.selected = clampi(Settings.effects + fx_shift, 0, fx_names.size() - 1)
	fx_opt.item_selected.connect(func(i: int):
		Settings.effects = i - fx_shift
		Settings.preset = -1
		Settings.save_settings())
	grid.add_child(fx_opt)

	grid.add_child(_row_label("Тени"))
	var sh_opt := _option(["Выключены", "Низкие", "Средние", "Высокие"])
	sh_opt.selected = clampi(Settings.shadows, 0, 3)
	sh_opt.item_selected.connect(func(i: int):
		Settings.shadows = i
		Settings.apply_graphics()
		Settings.save_settings())
	grid.add_child(sh_opt)

	grid.add_child(_row_label("Текстуры"))
	var tq_keys := ["auto", "low", "medium", "high"]
	var tq_opt := _option(["По разрешению экрана", "Обычные", "Чёткие ×1.5", "Очень чёткие ×2"])
	tq_opt.selected = maxi(0, tq_keys.find(Settings.tex_quality))
	tq_opt.item_selected.connect(func(i: int):
		Settings.tex_quality = tq_keys[i]
		Settings.save_settings())
	grid.add_child(tq_opt)

	# --- Память: сколько занимает игра ---
	grid.add_child(_row_label("Память"))
	var mem_box := VBoxContainer.new()
	mem_box.add_theme_constant_override("separation", 2)
	_mem_bar = ProgressBar.new()
	_mem_bar.custom_minimum_size = Vector2(280, 14)
	_mem_bar.show_percentage = false
	_mem_bar.add_theme_stylebox_override("background", _box(CYAN.darkened(0.6), PANEL_BG, 1, 0))
	var fill := StyleBoxFlat.new()
	fill.bg_color = CYAN
	_mem_bar.add_theme_stylebox_override("fill", fill)
	mem_box.add_child(_mem_bar)
	_mem_label = _label("", 13, Color(0.8, 0.85, 1.0))
	mem_box.add_child(_mem_label)
	grid.add_child(mem_box)
	_update_memory()

	# --- Звук ---
	for entry in [["Музыка", "music"], ["Звуки", "sfx"]]:
		grid.add_child(_row_label(entry[0]))
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.custom_minimum_size = Vector2(290, 30)
		slider.value = Data.music_volume if entry[1] == "music" else Data.sfx_volume
		var key: String = entry[1]
		slider.value_changed.connect(func(val: float):
			if key == "music":
				Data.music_volume = val
			else:
				Data.sfx_volume = val
				Sound.play("gem", 0.0, 1.0, 0.0, 0.08)
			Sound.apply_volumes())
		grid.add_child(slider)

	_filter_tab(grid)
	if tab == "sound":
		grid.columns = 2
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	var back := _button("НАЗАД", Color(0.6, 0.6, 0.75), 220)
	back.pressed.connect(func():
		Sound.play("click")
		Settings.save_settings()
		if on_back.is_valid():
			on_back.call())
	buttons.add_child(back)
	if tab == "video":
		var apply := _button("ПРИМЕНИТЬ", CYAN, 260)
		apply.pressed.connect(_apply_display)
		buttons.add_child(apply)
	v.add_child(buttons)


var _mode_opt: OptionButton
var _aspect_opt: OptionButton
var _res_opt: OptionButton
var _res_values: Array[Vector2i] = []


func _row_label(text: String) -> Label:
	var l := _label(text, 17, CYAN)
	l.custom_minimum_size = Vector2(170, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _option(items: Array) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(290, 40)
	o.add_theme_font_size_override("font_size", 16)
	o.add_theme_stylebox_override("normal", _box(CYAN.darkened(0.4), PANEL_BG, 2, 4))
	o.add_theme_stylebox_override("hover", _box(CYAN, Color(0.08, 0.05, 0.16, 0.95), 2, 10))
	o.add_theme_stylebox_override("pressed", _box(CYAN, Color(0.1, 0.06, 0.2, 0.95), 2, 10))
	o.add_theme_stylebox_override("focus", _box(CYAN, Color(0.08, 0.05, 0.16, 0.95), 2, 10))
	o.get_popup().add_theme_font_size_override("font_size", 18)
	for it in items:
		o.add_item(it)
	o.item_selected.connect(func(_i: int): Sound.play("click"))
	return o


func _aspect_key() -> String:
	return Settings.FORMATS[maxi(0, _aspect_opt.selected)]


## Заполняет список разрешений выбранного формата (от максимального к минимальному).
func _fill_resolutions(prefer: Vector2i) -> void:
	_res_opt.clear()
	_res_values = Settings.resolutions_for(_aspect_key())
	var sel := 0
	var screen := Settings.native_size()
	for i in _res_values.size():
		var r := _res_values[i]
		var text := "%d × %d" % [r.x, r.y]
		if r == screen:
			text += "  (родное)"
		_res_opt.add_item(text)
		if r == prefer:
			sel = i
	_res_opt.selected = sel


## Строка мобильной настройки «название — варианты»; изменения сохраняются сразу
## и действуют со следующего боя (свечение и дальность — сразу в новой сцене).
func _mob_opt(grid: GridContainer, title: String, items: Array, sel: int, setter: Callable) -> void:
	grid.add_child(_row_label(title))
	var o := _option(items)
	o.selected = clampi(sel, 0, items.size() - 1)
	o.item_selected.connect(func(i: int):
		setter.call(i)
		Settings.preset = -1
		Settings.save_settings())
	grid.add_child(o)


## Перестроить панель (после смены профиля — показать новые значения)
func _rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_build()


func _apply_display() -> void:
	Sound.play("click")
	if _mode_opt == null or not is_instance_valid(_mode_opt) or _res_opt == null:
		Settings.apply_display()
		Settings.save_settings()
		return
	Settings.mode = ["fullscreen", "windowed", "borderless"][maxi(0, _mode_opt.selected)]
	Settings.aspect = _aspect_key()
	var chosen: Vector2i = _res_values[maxi(0, _res_opt.selected)]
	Settings.resolution = Vector2i.ZERO if chosen == Settings.native_size() else chosen
	Settings.apply_display()
	Settings.save_settings()


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


