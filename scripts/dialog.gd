extends CanvasLayer
## Диалоги в стиле визуальной новеллы: большие портреты по краям, табличка с именем,
## окно текста с «печатной машинкой», выборы ответа. Клик / Пробел / E — дальше,
## Esc — пропустить сцену.
##
## Строка сцены: [кто, текст] или {"who", "text", "side": "l"|"r", "choices": [...]}.
## Выбор: {"t": текст кнопки, "lines": [ответные строки], "do": Callable}.
## «кто» — id из Scenes.CAST, id героя, "player" (выбранный герой) или "" (рассказчик).

signal finished

const Pixel := preload("res://scripts/pixel.gd")
const Scenes := preload("res://scripts/scenes.gd")
const Meta := preload("res://scripts/meta.gd")

var lines: Array = []
var opts := {}
var _i := -1
var _root: Control
var _box: PanelContainer
var _box_style: StyleBoxFlat
var _plate: PanelContainer
var _plate_style: StyleBoxFlat
var _name: Label
var _text: Label
var _arrow: Label
var _choices: VBoxContainer
var _slots := {}          # "l"/"r" -> {"holder", "base", "emit", "who", "frames"}
var _typing := false
var _shown := 0.0
var _cps := 52.0
var _anim := 0.0
var _closing := false
var _was_paused := false
var _waiting_choice := false
var _input_lock := 0.15


static func open(parent: Node, scene, options := {}) -> CanvasLayer:
	var d: CanvasLayer = preload("res://scripts/dialog.gd").new()
	d.opts = options
	d.lines = Scenes.get_scene(scene) if scene is String else (scene as Array).duplicate()
	parent.add_child(d)
	return d


func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	if opts.get("pause", false):
		_was_paused = get_tree().paused
		get_tree().paused = true
	_build()
	if lines.is_empty():
		_finish.call_deferred()
		return
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.25)
	_next()


func _vs() -> Vector2:
	return get_viewport().get_visible_rect().size


func _build() -> void:
	var vs := _vs()
	var narrow := vs.x < 900.0 or vs.y > vs.x
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_root_input)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.0, 0.06, float(opts.get("dim", 0.58)))
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	# Нижнее затемнение, чтобы портреты и текст читались на любом фоне
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.0, 0.06, 0.0))
	g.set_color(1, Color(0.02, 0.0, 0.06, 0.92))
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	grad.texture = gt
	grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	grad.offset_top = -vs.y * 0.62
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(grad)
	# Портреты
	var ph := minf(minf(vs.y * (0.5 if narrow else 0.66), 460.0), vs.x * 0.55)
	for side in ["l", "r"]:
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.size = Vector2(ph * 0.8, ph)
		holder.pivot_offset = Vector2(ph * 0.4, ph)
		var bx := vs.x * (0.02 if side == "l" else 0.98) - (0.0 if side == "l" else ph * 0.8)
		holder.position = Vector2(bx, vs.y - ph - (150.0 if narrow else 120.0))
		_root.add_child(holder)
		var base := TextureRect.new()
		base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		base.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		base.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		base.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(base)
		var emit := TextureRect.new()
		emit.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		emit.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		emit.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		emit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		emit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		emit.material = add
		holder.add_child(emit)
		if side == "r":
			base.flip_h = true
			emit.flip_h = true
		holder.visible = false
		_slots[side] = {"holder": holder, "base": base, "emit": emit, "who": "", "frames": {}, "x": bx}
	# Окно текста
	_box = PanelContainer.new()
	_box_style = StyleBoxFlat.new()
	_box_style.bg_color = Color(0.04, 0.02, 0.09, 0.94)
	_box_style.border_color = Color(0.3, 1.0, 1.0)
	_box_style.set_border_width_all(2)
	_box_style.set_corner_radius_all(10)
	_box_style.shadow_color = Color(0.3, 1.0, 1.0, 0.35)
	_box_style.shadow_size = 10
	_box_style.content_margin_left = 26
	_box_style.content_margin_right = 26
	_box_style.content_margin_top = 18
	_box_style.content_margin_bottom = 16
	_box.add_theme_stylebox_override("panel", _box_style)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bw := minf(1120.0, vs.x - 28.0)
	var bh := 150.0 if not narrow else 176.0
	_box.position = Vector2((vs.x - bw) / 2.0, vs.y - bh - 14.0)
	_box.size = Vector2(bw, bh)
	_root.add_child(_box)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("font_size", 22 if not narrow else 19)
	_text.add_theme_color_override("font_color", Color(0.96, 0.95, 1.0))
	_text.add_theme_constant_override("line_spacing", 4)
	_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_text.custom_minimum_size = Vector2(bw - 60.0, bh - 40.0)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_text)
	_arrow = Label.new()
	_arrow.text = "▼"
	_arrow.add_theme_font_size_override("font_size", 18)
	_arrow.add_theme_color_override("font_color", Color(0.3, 1.0, 1.0))
	_arrow.position = Vector2(_box.position.x + bw - 40.0, _box.position.y + bh - 34.0)
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_arrow)
	# Табличка с именем
	_plate = PanelContainer.new()
	_plate_style = StyleBoxFlat.new()
	_plate_style.bg_color = Color(0.3, 1.0, 1.0)
	_plate_style.set_corner_radius_all(6)
	_plate_style.content_margin_left = 16
	_plate_style.content_margin_right = 16
	_plate_style.content_margin_top = 4
	_plate_style.content_margin_bottom = 4
	_plate.add_theme_stylebox_override("panel", _plate_style)
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.position = Vector2(_box.position.x + 22.0, _box.position.y - 22.0)
	_root.add_child(_plate)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 20)
	_name.add_theme_color_override("font_color", Color(0.03, 0.02, 0.08))
	_plate.add_child(_name)
	# Выборы
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 8)
	_choices.visible = false
	_root.add_child(_choices)
	# Пропустить
	var skip := Button.new()
	skip.text = "Пропустить ⏭" if Input.get_connected_joypads().is_empty() else "Пропустить ⏭  (держать B)"
	skip.focus_mode = Control.FOCUS_NONE
	skip.add_theme_font_size_override("font_size", 16)
	skip.position = Vector2(vs.x - 190.0, 14.0)
	skip.custom_minimum_size = Vector2(170, 40)
	if not Input.get_connected_joypads().is_empty():
		skip.position.x = vs.x - 290.0
	var sst := StyleBoxFlat.new()
	sst.bg_color = Color(0.06, 0.03, 0.12, 0.92)
	sst.border_color = Color(0.6, 0.55, 0.85)
	sst.set_border_width_all(1)
	sst.set_corner_radius_all(8)
	skip.add_theme_stylebox_override("normal", sst)
	skip.pressed.connect(_skip)
	skip.visible = not opts.get("no_skip", false)
	_root.add_child(skip)


func _on_root_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_advance()
	elif ev is InputEventScreenTouch and ev.pressed:
		_advance()


func _input(ev: InputEvent) -> void:
	if _closing:
		return
	# Геймпад: B / Start — пропуск только удержанием (случайное нажатие не съедает обучение)
	if ev is InputEventJoypadButton and (ev.button_index == JOY_BUTTON_B or ev.button_index == JOY_BUTTON_START):
		get_viewport().set_input_as_handled()
		return
	if ev.is_action_pressed("pause") or ev.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_skip()
		return
	var adv: bool = ev.is_action_pressed("interact") or ev.is_action_pressed("ui_accept") or ev.is_action_pressed("ability")
	if ev is InputEventJoypadButton and ev.pressed and ev.button_index in [JOY_BUTTON_A, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_LEFT_SHOULDER]:
		adv = true
	if not adv:
		return
	if _waiting_choice:
		# Ждём выбора: подтверждение достаётся выбранной кнопке ответа (раньше съедалось здесь,
		# и с геймпада/клавиатуры ответ было не выбрать)
		var f := get_viewport().gui_get_focus_owner()
		if f == null or not _choices.is_ancestor_of(f):
			get_viewport().set_input_as_handled()
			if _choices.get_child_count() > 0:
				(_choices.get_child(0) as Button).grab_focus()
		return
	get_viewport().set_input_as_handled()
	_advance()


func _advance() -> void:
	if _closing or _waiting_choice or _input_lock > 0.0:
		return
	if _typing:
		_typing = false
		_text.visible_ratio = 1.0
		return
	_next()


func _skip() -> void:
	if _closing:
		return
	# Пропуск не пропускает выбор: сцена доходит до первого вопроса
	while _i + 1 < lines.size():
		_i += 1
		var ln = lines[_i]
		if ln is Dictionary and ln.has("choices"):
			_i -= 1
			_typing = false
			_next()
			return
	_finish()


func _next() -> void:
	_i += 1
	if _i >= lines.size():
		_finish()
		return
	var ln = lines[_i]
	var who := ""
	var txt := ""
	var side := ""
	if ln is Array:
		who = str(ln[0])
		txt = str(ln[1])
	else:
		who = str(ln.get("who", ""))
		txt = str(ln.get("text", ""))
		side = str(ln.get("side", ""))
	txt = Scenes.fill(txt)
	var cast: Dictionary = opts.get("cast", {}).get(who, Scenes.cast(who))
	if side == "":
		side = str(cast.get("side", "r"))
	var col: Color = cast.get("color", Color(0.8, 0.8, 0.95))
	# Табличка и рамка — цветом говорящего
	_plate.visible = who != ""
	_name.text = str(cast.get("name", ""))
	_plate_style.bg_color = col
	_box_style.border_color = col if who != "" else Color(0.55, 0.5, 0.75)
	_box_style.shadow_color = Color(col, 0.35)
	_text.add_theme_color_override("font_color", Color(0.96, 0.95, 1.0) if who != "" else Color(0.82, 0.8, 0.95))
	_text.text = txt if who != "" else txt
	_text.visible_ratio = 0.0
	_shown = 0.0
	_typing = true
	_input_lock = 0.12
	if who != "" and (str(cast.get("sprite", "")) != "" or opts.get("frames", {}).has(who)):
		_show_portrait(side, who, cast)
	_focus(side if who != "" else "")
	if ln is Dictionary and ln.has("choices"):
		_waiting_choice = true
		_show_choices(ln["choices"])
	if ln is Dictionary and ln.has("do"):
		(ln["do"] as Callable).call()
	Sound.play("click", -14.0, 1.6)


func _show_portrait(side: String, who: String, cast: Dictionary) -> void:
	var s: Dictionary = _slots[side]
	if s["who"] == who:
		return
	var fr: Dictionary = opts.get("frames", {}).get(who, {})
	if fr.is_empty():
		fr = Pixel.frames(str(cast["sprite"]))
	s["frames"] = fr
	s["who"] = who
	var holder: Control = s["holder"]
	var first := not holder.visible
	holder.visible = true
	(s["base"] as TextureRect).texture = fr["base"][0]
	(s["emit"] as TextureRect).texture = fr["emit"][0]
	# Выход на сцену: выезжает сбоку
	var x0: float = s["x"]
	holder.position.x = x0 + (-80.0 if side == "l" else 80.0)
	holder.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(holder, "position:x", x0, 0.28 if first else 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "modulate:a", 1.0, 0.22)


func _focus(side: String) -> void:
	for k in _slots:
		var holder: Control = _slots[k]["holder"]
		var on: bool = k == side
		var tw := create_tween().set_parallel()
		tw.tween_property(holder, "scale", Vector2.ONE * (1.0 if on else 0.92), 0.18)
		tw.tween_property(holder, "self_modulate", Color(1, 1, 1) if on else Color(0.45, 0.42, 0.55), 0.18)
		(_slots[k]["emit"] as TextureRect).modulate = Color(1, 1, 1, 1.0 if on else 0.35)


func _show_choices(list: Array) -> void:
	for c in _choices.get_children():
		c.queue_free()
	var vs := _vs()
	var w := minf(560.0, vs.x - 40.0)
	for ch in list:
		var b := Button.new()
		b.text = Scenes.fill(str(ch.get("t", "…")))
		b.custom_minimum_size = Vector2(w, 46)
		b.add_theme_font_size_override("font_size", 18)
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.06, 0.03, 0.12, 0.95)
		st.border_color = Color(1.0, 0.8, 0.3)
		st.set_border_width_all(2)
		st.set_corner_radius_all(8)
		b.add_theme_stylebox_override("normal", st)
		var sth := st.duplicate() as StyleBoxFlat
		sth.bg_color = Color(0.2, 0.12, 0.3, 0.98)
		b.add_theme_stylebox_override("hover", sth)
		b.add_theme_stylebox_override("focus", sth)
		b.pressed.connect(_pick.bind(ch))
		_choices.add_child(b)
	_choices.visible = true
	_choices.position = Vector2((vs.x - w) / 2.0, _box.position.y - 70.0 - list.size() * 54.0)
	if _choices.get_child_count() > 0:
		(_choices.get_child(0) as Button).grab_focus.call_deferred()


func _pick(ch: Dictionary) -> void:
	_choices.visible = false
	_waiting_choice = false
	Sound.play("click", -6.0)
	var reply: Array = ch.get("lines", [])
	for k in reply.size():
		lines.insert(_i + 1 + k, reply[k])
	if ch.has("do"):
		(ch["do"] as Callable).call()
	if ch.get("end", false):
		lines.resize(_i + 1 + reply.size())
	_typing = false
	_next()


var _skip_hold := 0.0


func _process(delta: float) -> void:
	_input_lock = maxf(0.0, _input_lock - delta)
	# Удержание B / Start на геймпаде — пропустить сцену
	var held := false
	for j in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(j, JOY_BUTTON_B) or Input.is_joy_button_pressed(j, JOY_BUTTON_START):
			held = true
	_skip_hold = (_skip_hold + delta) if held else 0.0
	if _skip_hold > 0.7 and not _closing and not opts.get("no_skip", false):
		_skip_hold = 0.0
		_skip()
	if _choices.visible:
		# Выбор ответа: фокус всегда на одной из кнопок (крестовина и стик)
		var fo := get_viewport().gui_get_focus_owner()
		if (fo == null or not _choices.is_ancestor_of(fo)) and _choices.get_child_count() > 0 and preload("res://scripts/ui_focus.gd").pad_mode:
			(_choices.get_child(0) as Button).grab_focus()
	if _typing:
		_shown += delta * _cps
		var total := maxi(1, _text.get_total_character_count())
		_text.visible_ratio = clampf(_shown / float(total), 0.0, 1.0)
		if _shown >= total:
			_typing = false
	_arrow.visible = not _typing and not _waiting_choice and fmod(_anim, 0.8) < 0.5
	_anim += delta
	# Дыхание портретов: кадры покоя
	for k in _slots:
		var s: Dictionary = _slots[k]
		if (s["holder"] as Control).visible and not (s["frames"] as Dictionary).is_empty():
			var fr: Dictionary = s["frames"]
			var n := mini(6, fr["base"].size() / Pixel.subframes(fr))
			var f := Pixel.loop_frame(fr, 0, n, _anim * 5.0)
			(s["base"] as TextureRect).texture = fr["base"][f]
			(s["emit"] as TextureRect).texture = fr["emit"][f]


func _exit_tree() -> void:
	# Сцену убрали раньше конца диалога (смена сцены) — пауза не должна остаться
	if opts.get("pause", false) and not _closing and is_inside_tree():
		get_tree().paused = _was_paused


func _finish() -> void:
	if _closing:
		return
	_closing = true
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func():
		if opts.get("pause", false):
			get_tree().paused = _was_paused
		finished.emit()
		queue_free())
