extends CanvasLayer
## Сенсорное управление для телефона (Android).
## Плавающий джойстик: появляется там, где коснулись экрана (кроме кнопок и окон интерфейса).
## Способность — двойное касание в любом месте экрана (кроме кнопок интерфейса),
## в том числе там, где джойстик. Сверху справа — пауза и статистика; в убежище — «Войти».
## Подключён как автозагрузка «Touch»; на ПК не виден (проверка: запуск с --touch).

const CYAN := Color(0.3, 0.95, 1.0)
const MAGENTA := Color(1.0, 0.3, 0.75)
const GOLD := Color(1.0, 0.8, 0.3)

var _canvas: Control
var _joy_index := -1
var _joy_origin := Vector2.ZERO
var _joy_vec := Vector2.ZERO
var _held := {}        # индекс касания -> id кнопки
var _ctx := ""         # "battle" / "hub" / ""
var _blocked := false  # открыто окно — управление спрятано
# Двойное касание: короткое касание, затем второе рядом и быстро — способность
var _press_t := {}      # индекс -> [время нажатия, место]
var _last_tap_t := -10.0
var _last_tap_pos := Vector2.ZERO
var _ab_flash := 0.0
var _ab_pos := Vector2.ZERO
const TAP_MAX := 0.25
const DOUBLE_GAP := 0.32


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_controls)
	add_child(_canvas)
	visible = Settings.is_mobile()
	if visible:
		# Касания экрана — это и «мышь» для меню, но мышь не превращается в касания
		Input.emulate_mouse_from_touch = true
		Input.emulate_touch_from_mouse = "--touch" in OS.get_cmdline_user_args()


func _k() -> float:
	return [0.8, 1.0, 1.25][clampi(Settings.touch_size, 0, 2)]


func _vs() -> Vector2:
	return _canvas.get_viewport_rect().size


## Кнопки текущего экрана: id -> [центр, радиус, подпись, цвет]
func _buttons() -> Dictionary:
	var sm := Settings.safe_margins()
	var vs := _vs() - Vector2(sm[2], 0.0)
	var k := _k()
	var out := {}
	if _ctx == "battle":
		out["pause"] = [Vector2(vs.x - 48.0 * k, 118.0 + 10.0 * k + sm[1]), 34.0 * k, "II", CYAN]
		out["stats"] = [Vector2(vs.x - 48.0 * k, 200.0 + 18.0 * k + sm[1]), 30.0 * k, "≡", GOLD]
	elif _ctx == "hub":
		var scene := _scene()
		if scene != null and str(scene.get("_near")) != "":
			out["interact"] = [Vector2(vs.x - 140.0 * k, vs.y - 150.0 * k), 72.0 * k, "ВОЙТИ", GOLD]
		out["pause"] = [Vector2(vs.x - 48.0 * k, 160.0 + sm[1]), 34.0 * k, "II", CYAN]
	return out


## Сцена боя или убежища (может быть вложена в тестовую сцену)
func _scene() -> Node:
	var s := get_tree().current_scene
	if s == null:
		return null
	if s.get("hud") != null or s.get("_panel_id") != null:
		return s
	for c in s.get_children():
		if c.get("hud") != null or c.get("_panel_id") != null:
			return c
	return s


func _process(_delta: float) -> void:
	if not visible:
		return
	var scene := _scene()
	var ctx := ""
	var blocked := false
	if scene != null:
		if scene.get("hud") != null and scene.get("player") != null:
			ctx = "battle"
			var hud = scene.get("hud")
			blocked = hud.is_modal_open() or bool(scene.get("game_over"))
		elif scene.get("_panel_id") != null:
			ctx = "hub"
			blocked = str(scene.get("_panel_id")) != ""
	if ctx != _ctx or blocked != _blocked:
		_ctx = ctx
		_blocked = blocked
		_release_all()
	_ab_flash = maxf(0.0, _ab_flash - _delta)
	_canvas.queue_redraw()


func _release_all() -> void:
	_joy_index = -1
	_set_joy(Vector2.ZERO)
	for idx in _held.keys():
		_fire(_held[idx], false)
	_held.clear()


func _set_joy(v: Vector2) -> void:
	_joy_vec = v
	for pair in [["move_left", -v.x], ["move_right", v.x], ["move_up", -v.y], ["move_down", v.y]]:
		var s: float = clampf(pair[1], 0.0, 1.0)
		if s > 0.05:
			Input.action_press(pair[0], s)
		else:
			Input.action_release(pair[0])


func _release_ability() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_fire("ability", false)


func _fire(id: String, pressed: bool) -> void:
	if id == "stats":
		var scene := _scene()
		if pressed and scene != null and scene.get("hud") != null:
			scene.hud.force_stats = not scene.hud.force_stats
		return
	var ev := InputEventAction.new()
	ev.action = id
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


func _input(event: InputEvent) -> void:
	if not visible or _ctx == "" or _blocked:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			var bs := _buttons()
			for id in bs:
				if t.position.distance_to(bs[id][0]) <= float(bs[id][1]) * 1.15:
					_held[t.index] = id
					_fire(id, true)
					return
			# Джойстик — в _unhandled_input: если касание попало в интерфейс, он его заберёт
		else:
			if _press_t.has(t.index):
				var pr: Array = _press_t[t.index]
				var now := Time.get_ticks_msec() / 1000.0
				if now - float(pr[0]) < TAP_MAX and t.position.distance_to(pr[1]) < 40.0:
					_last_tap_t = now
					_last_tap_pos = t.position
				_press_t.erase(t.index)
			if _held.has(t.index):
				_fire(_held[t.index], false)
				_held.erase(t.index)
			if t.index == _joy_index:
				_joy_index = -1
				_set_joy(Vector2.ZERO)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _joy_index:
			var r := 90.0 * _k()
			var off := d.position - _joy_origin
			# База джойстика подтягивается за пальцем, если увести его далеко
			if off.length() > r:
				_joy_origin = d.position - off.normalized() * r
				off = d.position - _joy_origin
			_set_joy(off / r)


## Касание мимо интерфейса — здесь появляется джойстик (в любом месте экрана)
func _unhandled_input(event: InputEvent) -> void:
	if not visible or _ctx == "" or _blocked:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and not _held.has(t.index):
			var now := Time.get_ticks_msec() / 1000.0
			_press_t[t.index] = [now, t.position]
			# Второе касание сразу после короткого первого — способность
			if _ctx == "battle" and now - _last_tap_t < DOUBLE_GAP and t.position.distance_to(_last_tap_pos) < 110.0:
				_last_tap_t = -10.0
				_fire("ability", true)
				_release_ability.call_deferred()
				_ab_flash = 0.35
				_ab_pos = t.position
		if t.pressed and _joy_index == -1 and not _held.has(t.index):
			_joy_index = t.index
			_joy_origin = t.position
			_set_joy(Vector2.ZERO)


func _notification(what: int) -> void:
	# Кнопка «Назад» на Android: закрыть окно / пауза
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		var ev := InputEventAction.new()
		ev.action = "pause" if (_ctx == "battle" and not _blocked) else "ui_cancel"
		ev.pressed = true
		Input.parse_input_event(ev)
		var up := ev.duplicate()
		up.pressed = false
		Input.parse_input_event(up)


func _draw_controls() -> void:
	if _ctx == "" or _blocked:
		return
	var font := ThemeDB.fallback_font
	var k := _k()
	var r := 90.0 * k
	# Джойстик виден только пока палец на экране — там, где коснулись
	if _joy_index != -1:
		var origin := _joy_origin
		var a := 0.55
		_canvas.draw_circle(origin, r, Color(0.05, 0.02, 0.1, a * 0.6))
		_canvas.draw_arc(origin, r, 0.0, TAU, 48, Color(CYAN, a + 0.15), 3.0, true)
		var knob := origin + _joy_vec.limit_length(1.0) * r
		_canvas.draw_circle(knob, 38.0 * k, Color(CYAN, a + 0.1))
		_canvas.draw_arc(knob, 38.0 * k, 0.0, TAU, 32, Color(1, 1, 1, a + 0.2), 2.0, true)
	# Вспышка двойного касания — способность сработала
	if _ab_flash > 0.0:
		var k2 := _ab_flash / 0.35
		_canvas.draw_arc(_ab_pos, 40.0 + (1.0 - k2) * 60.0, 0.0, TAU, 40, Color(MAGENTA, k2), 4.0, true)
		_canvas.draw_string(font, _ab_pos + Vector2(-10, -50), "★", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 1, 1, k2))
	# Кнопки
	var bs := _buttons()
	for id in bs:
		var b: Array = bs[id]
		var held: bool = id in _held.values() or (id == "stats" and _scene().hud.force_stats)
		var col: Color = b[3]
		var ab_ready := true
		if id == "ability":
			var p = _scene().get("player")
			if p != null and is_instance_valid(p):
				ab_ready = float(p.ability_left) <= 0.0
		var fill := Color(col, 0.55 if held else (0.3 if ab_ready else 0.12))
		_canvas.draw_circle(b[0], b[1], Color(0.05, 0.02, 0.1, 0.5))
		_canvas.draw_circle(b[0], b[1], fill)
		_canvas.draw_arc(b[0], b[1], 0.0, TAU, 48, Color(col, 0.95 if ab_ready else 0.4), 3.0, true)
		var fs := int(float(b[1]) * (0.75 if str(b[2]).length() <= 2 else 0.32))
		var w := font.get_string_size(b[2], HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		_canvas.draw_string(font, b[0] + Vector2(-w / 2.0, fs * 0.35), b[2], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95 if ab_ready else 0.5))
