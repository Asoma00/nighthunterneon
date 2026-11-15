extends RefCounted
## Навигация по кнопкам с геймпада/клавиатуры: если ничего не в фокусе —
## фокусируем кнопку (ту же по счёту, что была раньше, или первую).


static var pad_mode := false   # включается от геймпада/стрелок, выключается мышью
static var _kb_nav_t := -10.0  # когда последний раз нажата клавиша ходьбы (WASD и др.)


static func on_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		pad_mode = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.6:
		pad_mode = true
	elif event is InputEventKey and event.pressed and event.physical_keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_TAB]:
		pad_mode = true
	elif event is InputEventMouseMotion and event.relative.length() > 6.0 and Input.get_connected_joypads().is_empty():
		pad_mode = false
	if event is InputEventKey and event.pressed:
		for a in ["move_up", "move_down", "move_left", "move_right"]:
			if event.is_action(a) and not event.is_action("ui_" + a.substr(5)):
				_kb_nav_t = Time.get_ticks_msec() / 1000.0
				_wasd_nav(event, a.substr(5))
				return
		if event.is_action("ui_accept") or event.is_action("interact"):
			_kb_nav_t = Time.get_ticks_msec() / 1000.0


## Клавиши ходьбы (WASD или переназначенные) двигают выбор в меню, как стрелки.
static func _wasd_nav(event: InputEvent, dir: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var vp := tree.root
	var f := vp.gui_get_focus_owner()
	if f == null or not f.is_visible_in_tree() or f is LineEdit or f is TextEdit:
		return
	vp.set_input_as_handled()
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = "ui_" + dir
		ev.pressed = pressed
		ev.strength = 1.0 if pressed else 0.0
		Input.parse_input_event(ev)


static func buttons(root: Node) -> Array:
	var out: Array = []
	_collect(root, out)
	return out


static func _collect(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n.is_queued_for_deletion():
		return
	if n is BaseButton and not (n as BaseButton).disabled and (n as Control).focus_mode != Control.FOCUS_NONE:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)


## Вызывать каждый кадр, пока открыто окно root. state хранит номер кнопки.
static func keep(root: Control, state: Dictionary) -> void:
	# Клавиатура: нажали клавишу ходьбы или ENTER, пока окно открыто — включаем выбор кнопок
	if not pad_mode and Time.get_ticks_msec() / 1000.0 - _kb_nav_t < 0.12:
		pad_mode = true
	if not pad_mode or root == null or not root.is_visible_in_tree():
		return
	# Поверх открыта экранная клавиатура — фокус принадлежит ей, не отбираем
	if not root.get_tree().get_nodes_in_group("vkeyboard").is_empty():
		return
	var f := root.get_viewport().gui_get_focus_owner()
	var list := buttons(root)
	if list.is_empty():
		return
	if f != null and list.has(f):
		state["idx"] = list.find(f)
		return
	# Фокус на любом другом элементе этого окна (неактивная кнопка выбранного героя,
	# поле ввода, слайдер) — не отбираем, иначе навигация «застревает»
	if f != null and f.is_visible_in_tree() and root.is_ancestor_of(f):
		return
	var i := clampi(int(state.get("idx", 0)), 0, list.size() - 1)
	(list[i] as Control).grab_focus()
