extends CanvasLayer
## Экран загрузки между сценами (меню → убежище → бой и обратно).
## Длится ровно столько, сколько нужно: загрузка сцены в фоне, генерация всех
## пиксельных текстур, которые понадобятся, сборка мира и «прогрев» видеокарты
## (первые кадры, пока грузятся текстуры и шейдеры). Время не фиксировано:
## при повторном заходе текстуры уже в кэше, и загрузка проходит быстрее.

const Data := preload("res://scripts/data.gd")
const Pixel := preload("res://scripts/pixel.gd")
const CYAN := Color(0.3, 0.95, 1.0)
const MAGENTA := Color(1.0, 0.3, 0.75)
const GOLD := Color(1.0, 0.8, 0.3)

const TIPS := [
	"Два оружия 10 уровня можно слить в эволюцию — один раз за забег.",
	"Столбы света в бою указывают на сундуки. Остальное придётся искать самим.",
	"{stats} — все текущие характеристики героя и оружия.",
	"Алтари мобов дают задания: выполните их ради усилений.",
	"Боссы неуязвимы при смене фазы — используйте паузу, чтобы отойти.",
	"Чем дольше длится забег, тем сильнее враги и их свойства.",
	"Осколки тратятся в убежище на здания, героев и ветки навыков.",
	"В библиотеке убежища собраны описания всего, что вы открыли.",
	"У каждого слота сохранения свой прогресс и свой ник.",
]

var busy := false
var _root: Control
var _bar: ProgressBar
var _stage: Label
var _tip: Label
var _title: Label
var _pct: Label
var _spin := 0.0
var _shown := 0.0
var _t_go := 0


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.025, 0.012, 0.055)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	var deco := Control.new()
	deco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.draw.connect(_draw_deco.bind(deco))
	deco.name = "Deco"
	_root.add_child(deco)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	v.custom_minimum_size = Vector2(640, 0)
	v.position = Vector2(-320, -80)
	v.add_theme_constant_override("separation", 14)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(v)
	_title = _label("ЗАГРУЗКА", 40, Color.WHITE, Color(MAGENTA, 0.8))
	v.add_child(_title)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(640, 18)
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.step = 0.0
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = Color(0.08, 0.04, 0.14)
	bgs.border_color = Color(CYAN, 0.6)
	bgs.set_border_width_all(2)
	bgs.set_corner_radius_all(6)
	var fg := StyleBoxFlat.new()
	fg.bg_color = CYAN
	fg.set_corner_radius_all(6)
	fg.shadow_color = Color(CYAN, 0.5)
	fg.shadow_size = 8
	_bar.add_theme_stylebox_override("background", bgs)
	_bar.add_theme_stylebox_override("fill", fg)
	v.add_child(_bar)
	var row := HBoxContainer.new()
	_stage = _label("", 17, Color(0.8, 0.85, 1.0))
	_stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_stage)
	_pct = _label("0%", 17, CYAN)
	_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_pct)
	v.add_child(row)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 30)
	v.add_child(sp)
	_tip = _label("", 16, Color(GOLD, 0.9))
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_tip)


func _label(text: String, size: int, color: Color, glow := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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


func _process(delta: float) -> void:
	if _root.visible:
		_spin += delta
		_root.get_node("Deco").queue_redraw()


func _draw_deco(c: Control) -> void:
	var vs := c.size
	# Неоновая сетка-горизонт и бегущие точки
	var hy := vs.y * 0.72
	for i in 14:
		var y := hy + pow(float(i) / 13.0, 2.0) * (vs.y - hy)
		c.draw_line(Vector2(0, y), Vector2(vs.x, y), Color(MAGENTA, 0.08 + 0.12 * float(i) / 13.0), 2.0)
	for i in range(-12, 13):
		var x0 := vs.x * 0.5 + float(i) * 30.0
		var x1 := vs.x * 0.5 + float(i) * 180.0
		c.draw_line(Vector2(x0, hy), Vector2(x1, vs.y), Color(CYAN, 0.1), 1.5)
	var cc := Vector2(vs.x * 0.5, vs.y * 0.5 - 150.0)
	for k in 3:
		var a0 := _spin * (2.0 + k * 0.7) + k * 2.1
		c.draw_arc(cc, 26.0 + k * 9.0, a0, a0 + 2.2, 24, [CYAN, MAGENTA, GOLD][k], 3.0, true)


func _setp(p: float, stage: String) -> void:
	_bar.value = clampf(p, 0.0, 1.0)
	_pct.text = "%d%%" % int(_bar.value * 100.0)
	if stage != "":
		_stage.text = stage


## Сменить сцену через экран загрузки.
func go(path: String) -> void:
	if busy:
		return
	busy = true
	_t_go = Time.get_ticks_msec()
	var tree := get_tree()
	_title.text = {"res://hub.tscn": "НЕОНОВОЕ УБЕЖИЩЕ", "res://main.tscn": "В БОЙ", "res://menu.tscn": "ГЛАВНОЕ МЕНЮ"}.get(path, "ЗАГРУЗКА")
	var stats_k: String = Settings.key("stats")
	_tip.text = "Совет: " + str(TIPS[randi() % TIPS.size()]).replace("{stats}", ("Кнопка " + stats_k) if Settings.input_mode() == "touch" else stats_k)
	_setp(0.0, "Загрузка сцены…")
	_root.visible = true
	_root.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.18)
	await tw.finished
	await tree.process_frame
	# 1. Сцена — в фоновом потоке
	ResourceLoader.load_threaded_request(path)
	var prog := []
	while true:
		var st := ResourceLoader.load_threaded_get_status(path, prog)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			break
		_setp(float(prog[0]) * 0.1 if prog.size() > 0 else 0.0, "")
		await tree.process_frame
	var ps: PackedScene = ResourceLoader.load_threaded_get(path)
	# 2. Текстуры — порциями, чтобы полоса и анимация не замирали
	var jobs := _jobs_for(path)
	var total := maxi(1, jobs.size())
	var done := 0
	_setp(0.1, "Текстуры…")
	while not jobs.is_empty():
		var t0 := Time.get_ticks_usec()
		while not jobs.is_empty() and Time.get_ticks_usec() - t0 < 12000:
			var j: Callable = jobs.pop_back()
			j.call()
			done += 1
		_setp(0.1 + 0.6 * float(done) / float(total), "Текстуры… %d / %d" % [done, total])
		await tree.process_frame
	# 3. Сборка мира
	_setp(0.72, "Сборка мира…")
	await tree.process_frame
	await tree.process_frame
	var old := tree.current_scene
	tree.paused = false
	if ps != null:
		tree.change_scene_to_packed(ps)
	else:
		tree.change_scene_to_file(path)
	var guard := 0
	while (tree.current_scene == old or tree.current_scene == null) and guard < 600:
		guard += 1
		await tree.process_frame
	# 4. Прогрев видеокарты: ждём, пока кадры не станут ровными
	_setp(0.8, "Подготовка видеокарты…")
	var calm := 0
	var frames := 0
	var t_start := Time.get_ticks_msec()
	var limit := 0.05 if Settings.is_mobile() else 0.034
	var min_dt := 10.0
	while calm < 4 and Time.get_ticks_msec() - t_start < 6000:
		await tree.process_frame
		frames += 1
		var dt := get_process_delta_time()
		if frames > 1:
			min_dt = minf(min_dt, dt)
		# «Ровный» кадр: быстрый, или не дольше обычного для этого устройства (без рывков)
		var ok_dt := dt < limit or (frames > 3 and dt < min_dt * 1.6)
		var scene := tree.current_scene
		var scene_ready := true
		if scene != null and scene.has_method("loading_ready"):
			scene_ready = scene.loading_ready()
		if ok_dt and frames > 2 and scene_ready:
			calm += 1
		else:
			calm = 0
		_setp(minf(0.98, 0.8 + 0.18 * float(frames) / float(frames + 6)), "")
	_setp(1.0, "Готово")
	if OS.is_debug_build():
		print("[Загрузка] %s: %d мс (кадров прогрева %d)" % [path, Time.get_ticks_msec() - _t_go, frames])
	await tree.process_frame
	var tw2 := create_tween()
	tw2.tween_property(_root, "modulate:a", 0.0, 0.25)
	await tw2.finished
	_root.visible = false
	busy = false


## Какие текстуры понадобятся в следующей сцене (уже готовые в кэше пропускаются).
func _jobs_for(path: String) -> Array:
	var jobs: Array = []
	var keys: Array = []
	if path == "res://main.tscn":
		for k in Pixel.SPECS:
			# Героев рисуем только тех, кто идёт в бой (каждый — 35 кадров 48×60)
			if k in Pixel.HERO_KEYS and k != str(Data.CHARACTERS.get(Data.selected_character, {}).get("sprite", "")):
				continue
			keys.append(k)
		for id in Data.WEAPONS:
			jobs.append(Pixel.icon.bind(id))
		for id in Data.PASSIVES:
			jobs.append(Pixel.icon.bind(id))
		jobs.append(Pixel.ground)
		jobs.append(Pixel.glow)
		jobs.append(Pixel.shadow)
		jobs.append(Pixel.rune_ring)
	elif path == "res://hub.tscn":
		for id in Data.CHARACTERS:
			keys.append(str(Data.CHARACTERS[id]["sprite"]))
			jobs.append(Pixel.portrait.bind(str(Data.CHARACTERS[id]["sprite"])))
		for k in Pixel.SPECS:
			if str(k).begins_with("env_") or str(k).begins_with("lamp") or str(k) in ["chest", "drone", "spirit"]:
				keys.append(k)
		for id in Data.WEAPONS:
			jobs.append(Pixel.icon.bind(id))
		for id in Data.PASSIVES:
			jobs.append(Pixel.icon.bind(id))
		jobs.append(Pixel.shadow)
		jobs.append(Pixel.glow)
	for k in keys:
		if not Pixel._cache.has(k):
			jobs.append(Pixel.frames.bind(str(k)))
	# Уже готовое не считаем — повторная загрузка заметно короче
	var out: Array = []
	for j in jobs:
		out.append(j)
	out.reverse()
	return out
