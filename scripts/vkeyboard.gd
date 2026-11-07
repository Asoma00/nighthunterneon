extends CanvasLayer
## Экранная клавиатура для геймпада и Steam Deck (ник, IP-адрес для сетевой игры).
## Крестовина/стик — выбор клавиши, A — нажать, B — закрыть, «ГОТОВО» — сохранить.

signal done(text: String)

const CYAN := Color(0.3, 0.95, 1.0)
const MAGENTA := Color(1.0, 0.3, 0.75)
const GOLD := Color(1.0, 0.8, 0.3)
const RU := ["ЙЦУКЕНГШЩЗХЪ", "ФЫВАПРОЛДЖЭ", "ЯЧСМИТЬБЮЁ"]
const EN := ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"]
const NUM := "1234567890"

var text := ""
var max_len := 16
var allow := ""          # если не пусто — только эти символы (например, для IP)
var _title := ""
var _layout := "ru"
var _lower := false
var _shown: Label
var _keys: GridContainer
var _rows_box: VBoxContainer
var _first: Button


## Открыть клавиатуру над текущей сценой.
static func open(parent: Node, title: String, start_text: String, max_length := 16, allowed := "") -> Node:
	var k = load("res://scripts/vkeyboard.gd").new()
	k.text = start_text
	k.max_len = max_length
	k.allow = allowed
	k._title = title
	if allowed != "":
		k._layout = "num"
	parent.get_tree().root.add_child(k)
	return k


func _ready() -> void:
	layer = 125
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.01, 0.05, 0.9)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.03, 0.1, 0.97)
	sb.border_color = CYAN
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.shadow_color = Color(CYAN, 0.4)
	sb.shadow_size = 14
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var t := Label.new()
	t.text = _title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", CYAN)
	v.add_child(t)
	_shown = Label.new()
	_shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shown.add_theme_font_size_override("font_size", 28)
	_shown.custom_minimum_size = Vector2(560, 44)
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color(0.1, 0.06, 0.18)
	ssb.border_color = MAGENTA
	ssb.set_border_width_all(2)
	ssb.set_corner_radius_all(6)
	_shown.add_theme_stylebox_override("normal", ssb)
	v.add_child(_shown)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 6)
	v.add_child(_rows_box)
	var hint := Label.new()
	hint.text = "A — нажать  •  B — закрыть  •  X — стереть  •  Y — пробел"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.85))
	v.add_child(hint)
	_build_keys()
	_refresh()


func _key(label: String, w := 44, col := CYAN) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(w, 46)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 20)
	for st in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.08, 0.05, 0.14) if st == "normal" else Color(col, 0.35 if st != "pressed" else 0.6)
		s.border_color = col if st != "normal" else Color(col, 0.4)
		s.set_border_width_all(2)
		s.set_corner_radius_all(5)
		b.add_theme_stylebox_override(st, s)
	return b


func _build_keys() -> void:
	for c in _rows_box.get_children():
		c.queue_free()
	_first = null
	var rows: Array = []
	match _layout:
		"num":
			rows = [NUM, "." if allow.contains(".") else ""]
		"en":
			rows = [NUM] + EN
		_:
			rows = [NUM] + RU
	for r in rows:
		if r == "":
			continue
		var h := HBoxContainer.new()
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_theme_constant_override("separation", 5)
		_rows_box.add_child(h)
		for ch in r:
			var c: String = ch.to_lower() if _lower else ch
			var b := _key(c)
			b.pressed.connect(func(): _type(c))
			h.add_child(b)
			if _first == null:
				_first = b
	var ctl := HBoxContainer.new()
	ctl.alignment = BoxContainer.ALIGNMENT_CENTER
	ctl.add_theme_constant_override("separation", 6)
	_rows_box.add_child(ctl)
	if allow == "":
		var lang := _key("RU/EN", 90, GOLD)
		lang.pressed.connect(func():
			_layout = "en" if _layout == "ru" else "ru"
			_build_keys())
		ctl.add_child(lang)
		var caps := _key("аА", 70, GOLD)
		caps.pressed.connect(func():
			_lower = not _lower
			_build_keys())
		ctl.add_child(caps)
		var sp := _key("ПРОБЕЛ", 160, GOLD)
		sp.pressed.connect(func(): _type(" "))
		ctl.add_child(sp)
	var bs := _key("⌫ СТЕРЕТЬ", 130, MAGENTA)
	bs.pressed.connect(_backspace)
	ctl.add_child(bs)
	var ok := _key("ГОТОВО", 120, Color(0.4, 1.0, 0.6))
	ok.pressed.connect(_finish)
	ctl.add_child(ok)
	if _first:
		_first.call_deferred("grab_focus")


func _type(c: String) -> void:
	if text.length() >= max_len:
		return
	if allow != "" and not allow.contains(c):
		return
	text += c
	Sound.play("click", -10.0)
	_refresh()


func _backspace() -> void:
	if text.length() > 0:
		text = text.substr(0, text.length() - 1)
		_refresh()


func _refresh() -> void:
	_shown.text = text + "▌"


func _finish() -> void:
	Sound.play("click")
	done.emit(text)
	queue_free()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_B:
				get_viewport().set_input_as_handled()
				queue_free()
			JOY_BUTTON_X:
				get_viewport().set_input_as_handled()
				_backspace()
			JOY_BUTTON_Y:
				get_viewport().set_input_as_handled()
				if allow == "":
					_type(" ")
			JOY_BUTTON_START:
				get_viewport().set_input_as_handled()
				_finish()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()
