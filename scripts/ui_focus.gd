extends RefCounted
## Навигация по кнопкам с геймпада/клавиатуры: если ничего не в фокусе —
## фокусируем кнопку (ту же по счёту, что была раньше, или первую).


static var pad_mode := false   # включается от геймпада/стрелок, выключается мышью
static var _kb_nav_t := -10.0  # когда последний раз нажата клавиша ходьбы (WASD и др.)


static func on_input(event: InputEvent) -> void:
	_touch_scroll(event)
	if event is InputEventJoypadMotion and event.axis == JOY_AXIS_RIGHT_Y:
		_rs_val = event.axis_value
	if event is InputEventJoypadMotion and _stick_nav(event):
		return
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
	if root != null and root.is_visible_in_tree():
		_pad_scroll(root, state)
		_nav_repeat()
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
		# Выбор ушёл за край списка — список докручивается до него (геймпад, клавиатура)
		if state.get("last_f") != f:
			state["last_f"] = f
			_reveal(f)
		return
	# Фокус на любом другом элементе этого окна (неактивная кнопка выбранного героя,
	# поле ввода, слайдер) — не отбираем, иначе навигация «застревает»
	if f != null and f.is_visible_in_tree() and root.is_ancestor_of(f):
		return
	var i := clampi(int(state.get("idx", 0)), 0, list.size() - 1)
	(list[i] as Control).grab_focus()


# ---------- Прокрутка списков пальцем в любом месте (телефон) ----------
# Godot прокручивает список, только если палец лёг на пустое место: кнопки и карточки
# забирают касание себе. Здесь: палец сдвинулся больше чем на порог — это прокрутка
# ближайшего списка под пальцем, а нажатие кнопки отменяется. Короткое касание без
# сдвига — обычный выбор пункта.
static var _sc: ScrollContainer = null
static var _sc_drag := false
static var _sc_from := Vector2.ZERO
static var _sc_godot := false   # список и так прокручивает сам (палец на пустом месте)
static var _sc_base := Vector2.ZERO
const DRAG_PX := 14.0


static func _mobile() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var st = tree.root.get_node_or_null("Settings")
	return st != null and st.has_method("is_mobile") and st.is_mobile()


static func _scroll_at(vp: Viewport, pos: Vector2) -> ScrollContainer:
	var best: ScrollContainer = null
	var best_area := INF
	var best_layer := -INF
	for n in vp.find_children("*", "ScrollContainer", true, false):
		var sc := n as ScrollContainer
		if sc == null or not sc.is_visible_in_tree():
			continue
		var r := sc.get_global_rect()
		if not r.has_point(pos):
			continue
		var cl := sc.get_canvas_layer_node()
		var layer := float(cl.layer) if cl != null else 0.0
		var area := r.get_area()
		if layer > best_layer or (layer == best_layer and area < best_area):
			best = sc
			best_area = area
			best_layer = layer
	return best


## Пойдёт ли касание само до списка (по пути одни «пропускающие» элементы)?
static func _godot_scrolls(vp: Viewport, sc: ScrollContainer) -> bool:
	if not vp.has_method("gui_get_hovered_control"):
		return false
	var c: Control = vp.gui_get_hovered_control()
	if c == null:
		return true
	while c != null and c != sc:
		if c.mouse_filter == Control.MOUSE_FILTER_STOP:
			return false
		c = c.get_parent() as Control
	return true


static func _touch_scroll(event: InputEvent) -> void:
	if not (event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventScreenDrag):
		return
	if not _mobile():
		return
	var tree := Engine.get_main_loop() as SceneTree
	var vp := tree.root
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_sc = _scroll_at(vp, event.position)
			_sc_from = event.position
			_sc_drag = false
			_sc_godot = false
		else:
			_sc = null
			_sc_drag = false
		return
	if event is InputEventScreenDrag:
		if _sc_drag:
			vp.set_input_as_handled()
		return
	var mm := event as InputEventMouseMotion
	if mm.position.x < -5000.0:
		return   # наш служебный сдвиг «за экран»
	if _sc == null or not is_instance_valid(_sc) or not (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
		return
	if not _sc_drag:
		if mm.position.distance_to(_sc_from) < DRAG_PX:
			return
		_sc_godot = _godot_scrolls(vp, _sc)
		if _sc_godot:
			_sc = null
			return
		_sc_drag = true
		# Отменить нажатие кнопки под пальцем: «увести» указатель за экран
		var off := InputEventMouseMotion.new()
		off.position = Vector2(-10000, -10000)
		off.global_position = off.position
		off.button_mask = MOUSE_BUTTON_MASK_LEFT
		vp.push_input(off)
		_sc_base = Vector2(_sc.scroll_horizontal, _sc.scroll_vertical) + (mm.position - _sc_from)
	# Список едет за пальцем ровно на столько, на сколько палец сдвинулся
	var dpos := mm.position - _sc_from
	_sc.scroll_vertical = int(round(_sc_base.y - dpos.y))
	if _sc.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		_sc.scroll_horizontal = int(round(_sc_base.x - dpos.x))
	vp.set_input_as_handled()



## Левый стик в меню: один наклон — ровно один шаг. Godot шлёт «нажато» на каждое
## движение стика за мёртвой зоной, и выбор перескакивал через карточку (1 → 3).
## Здесь — нажатие на пороге 0.6 и отпускание ниже 0.35, остальное гасится.
static var _stick := {}
static var _rs_val := 0.0


static func _stick_nav(ev: InputEventJoypadMotion) -> bool:
	if ev.axis != JOY_AXIS_LEFT_X and ev.axis != JOY_AXIS_LEFT_Y:
		return false
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var vp := tree.root
	var f := vp.gui_get_focus_owner()
	if f == null or not f.is_visible_in_tree():
		return false
	vp.set_input_as_handled()
	var key := "%d:%d" % [ev.device, ev.axis]
	var held: int = int(_stick.get(key, 0))
	var v := ev.axis_value
	var want := held
	if held == 0 and absf(v) > 0.6:
		want = 1 if v > 0.0 else -1
	elif held != 0 and absf(v) < 0.35:
		want = 0
	elif held != 0 and signf(v) != float(held) and absf(v) > 0.6:
		want = 1 if v > 0.0 else -1
	if want == held:
		return true
	_stick[key] = want
	if want != 0:
		pad_mode = true
		var act := ("ui_right" if want > 0 else "ui_left") if ev.axis == JOY_AXIS_LEFT_X else ("ui_down" if want > 0 else "ui_up")
		for pressed in [true, false]:
			var a := InputEventAction.new()
			a.action = act
			a.pressed = pressed
			a.strength = 1.0 if pressed else 0.0
			Input.parse_input_event(a)
	return true



## Прокрутить все списки-предки так, чтобы элемент был виден целиком (с запасом).
static func _reveal(c: Control) -> void:
	var n := c.get_parent()
	while n != null:
		if n is ScrollContainer:
			var sc := n as ScrollContainer
			var r := c.get_global_rect()
			var sr := sc.get_global_rect()
			var pad := 24.0
			if r.position.y < sr.position.y + pad:
				sc.scroll_vertical -= int(sr.position.y + pad - r.position.y)
			elif r.end.y > sr.end.y - pad:
				sc.scroll_vertical += int(r.end.y - (sr.end.y - pad))
			if sc.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
				if r.position.x < sr.position.x:
					sc.scroll_horizontal -= int(sr.position.x - r.position.x)
				elif r.end.x > sr.end.x:
					sc.scroll_horizontal += int(r.end.x - sr.end.x)
		n = n.get_parent()


## Правый стик геймпада — плавная прокрутка списка (того, где выбор, или самого большого
## в окне): так читаются и длинные тексты без кнопок.
static func _pad_scroll(root: Control, state: Dictionary) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var dt := clampf(now - float(state.get("ps_t", now)), 0.0, 0.1)
	state["ps_t"] = now
	var v := _rs_val
	for j in Input.get_connected_joypads():
		var a := Input.get_joy_axis(j, JOY_AXIS_RIGHT_Y)
		if absf(a) > absf(v):
			v = a
	if absf(v) < 0.2 or dt <= 0.0:
		return
	var sc: ScrollContainer = null
	var f := root.get_viewport().gui_get_focus_owner()
	if f != null and root.is_ancestor_of(f):
		var n := f.get_parent()
		while n != null and n != root.get_parent():
			if n is ScrollContainer and (n as ScrollContainer).get_v_scroll_bar().max_value > (n as ScrollContainer).size.y + 4.0:
				sc = n
				break
			n = n.get_parent()
	if sc == null:
		var best := 0.0
		for n in root.find_children("*", "ScrollContainer", true, false):
			var c := n as ScrollContainer
			if not c.is_visible_in_tree():
				continue
			var area := c.size.x * c.size.y
			if area > best and c.get_v_scroll_bar().max_value > c.size.y + 4.0:
				best = area
				sc = c
	if sc == null:
		return
	var sgn := signf(v)
	sc.scroll_vertical += int(sgn * pow((absf(v) - 0.2) / 0.8, 1.5) * 1400.0 * dt + sgn)



## Удержание стика или крестовины в меню: после короткой паузы выбор бежит сам —
## сначала шагами по 0.11 с, потом быстрее (длинные списки листаются удержанием).
static var _rep := {}
static var _rep_frame := -1


static func _nav_repeat() -> void:
	var fr := Engine.get_process_frames()
	if fr == _rep_frame:
		return
	_rep_frame = fr
	var held := {}
	for key in _stick:
		var v: int = int(_stick[key])
		if v == 0:
			continue
		var axis := int(str(key).split(":")[1])
		if axis == JOY_AXIS_LEFT_X:
			held["ui_right" if v > 0 else "ui_left"] = true
		else:
			held["ui_down" if v > 0 else "ui_up"] = true
	for j in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(j, JOY_BUTTON_DPAD_DOWN):
			held["ui_down"] = true
		if Input.is_joy_button_pressed(j, JOY_BUTTON_DPAD_UP):
			held["ui_up"] = true
		if Input.is_joy_button_pressed(j, JOY_BUTTON_DPAD_LEFT):
			held["ui_left"] = true
		if Input.is_joy_button_pressed(j, JOY_BUTTON_DPAD_RIGHT):
			held["ui_right"] = true
	var now := Time.get_ticks_msec() / 1000.0
	for act in _rep.keys():
		if not held.has(act):
			_rep.erase(act)
	for act in held:
		if not _rep.has(act):
			_rep[act] = {"t0": now, "next": now + 0.38}
			continue
		var r: Dictionary = _rep[act]
		if now >= float(r["next"]):
			var step := 0.11 if now - float(r["t0"]) < 1.2 else 0.055
			r["next"] = now + step
			for pressed in [true, false]:
				var a := InputEventAction.new()
				a.action = act
				a.pressed = pressed
				a.strength = 1.0 if pressed else 0.0
				Input.parse_input_event(a)
