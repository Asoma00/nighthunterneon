extends RefCounted
## Навигация по кнопкам с геймпада/клавиатуры: если ничего не в фокусе —
## фокусируем кнопку (ту же по счёту, что была раньше, или первую).


static var pad_mode := false   # включается от геймпада/стрелок, выключается мышью


static func on_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		pad_mode = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.6:
		pad_mode = true
	elif event is InputEventKey and event.pressed and event.physical_keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_TAB]:
		pad_mode = true
	elif event is InputEventMouseMotion and event.relative.length() > 6.0 and Input.get_connected_joypads().is_empty():
		pad_mode = false


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
	var i := clampi(int(state.get("idx", 0)), 0, list.size() - 1)
	(list[i] as Control).grab_focus()
