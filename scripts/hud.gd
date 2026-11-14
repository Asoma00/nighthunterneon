extends CanvasLayer
## Неоновый интерфейс: опыт, здоровье, таймер, оружие с иконками,
## карточки улучшений и экран итогов.

const Data := preload("res://scripts/data.gd")
const UiFocus := preload("res://scripts/ui_focus.gd")
const DevInput := preload("res://scripts/devinput.gd")
const Pixel := preload("res://scripts/pixel.gd")

const CYAN := Color(0.3, 0.95, 1.0)
const MAGENTA := Color(1.0, 0.3, 0.75)
const GOLD := Color(1.0, 0.8, 0.3)
const PANEL_BG := Color(0.05, 0.03, 0.1, 0.88)

var main: Node2D

var _xp_bar: ProgressBar
var _hp_bar: ProgressBar
var _hp_label: Label
var _level_label: Label
var _time_label: Label
var _kills_label: Label
var _weapons_box: Container
var _weapons_sig := ""
var _levelup_root: Control
var _cards: HBoxContainer
var _lvl_title: Label
var _lvl_sub: Label
var _over_root: Control
var _over_title: Label
var _over_stats: Label
var _t := 0.0
var _boss_root: Control
var _boss_bar: ProgressBar
var _boss_name: Label
var _ability_icon: TextureRect
# Второй игрок (кооператив)
var _p2_hp: ProgressBar
var _p2_hp_label: Label
var _p2_xp: ProgressBar
var _p2_weapons: Container
var _p2_sig := ""
var _p2_ab_icon: TextureRect
var _p2_ab_shade: ColorRect
var _p2_ab_label: Label
var _ability_shade: ColorRect
var _ability_label: Label
var _chest_root: Control
var _chest_list: VBoxContainer
var _chest_icon: TextureRect
var _pause_root: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build_hud()
	_build_level_up()
	_build_game_over()
	_build_chest()
	_build_pause()


var _focus := {}
var _focus_root: Control
var _lvl_t := 0.0


## Точки интереса: стрелки у края экрана к далёким алтарям и строка задания.
var _poi_layer: Control
var _quest: Label
func _update_pois() -> void:
	if _poi_layer == null:
		_poi_layer = Control.new()
		_poi_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_poi_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_poi_layer.draw.connect(_draw_poi_arrows)
		add_child(_poi_layer)
		move_child(_poi_layer, 0)
		_quest = _label("", 20, Color(1.0, 0.9, 0.6), Color(0.75, 0.45, 1.0, 0.8))
		_quest.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_quest.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_quest.offset_left = -340 if portrait() else -400
		_quest.offset_right = 340 if portrait() else 400
		_quest.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_quest.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_poi_layer.add_child(_quest)
	var q := ""
	for p in _poi_list():
		if is_instance_valid(p) and p.has_method("quest_text"):
			q = p.quest_text()
			if q != "":
				break
	_quest.text = q
	_update_tracker()
	_quest.offset_top = (196.0 if (_boss_root and _boss_root.visible) else 124.0) + (60.0 if portrait() else 0.0)
	_poi_layer.queue_redraw()


func _poi_list() -> Array:
	var l: Array = []
	if main.get("omens") != null:
		l.append(main.omens)
	l.append_array(main.pois)
	if main.events != null:
		l.append(main.events)
	return l


## Задания этой вылазки: компактный список слева + собранные материалы.
var _tracker: Label
var _tracker_t := 0.0


func _update_tracker() -> void:
	_tracker_t -= get_process_delta_time()
	if _tracker_t > 0.0:
		return
	_tracker_t = 0.4
	if _tracker == null:
		_tracker = _label("", 14 if portrait() else 15, Color(0.92, 0.9, 1.0), Color(0.3, 0.15, 0.5, 0.7))
		_tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tracker.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		_tracker.custom_minimum_size = Vector2(300, 0)
		_tracker.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_poi_layer.add_child(_tracker)
	var lines: Array = []
	var st: Dictionary = main.Meta.story_cur()
	if not st.is_empty() and main.Meta.story_taken:
		lines.append("◆ Сюжет: %s — %s" % [st["title"], main.Meta.story_goal_text(st)])
	if main.challenge != "":
		lines.append("⚠ %s  •  угроза %d" % [main.Meta.CHALLENGES[main.challenge]["name"], main.threat])
	var bt: String = main.Lore.buff_text()
	if bt != "":
		lines.append(bt)
	var Q = main.QuestsScript
	for q in main.active_quests:
		var pr := mini(Q.progress(q, main.run), int(q["g"]))
		var ok := pr >= int(q["g"])
		var t: String = Q.title(q)
		if q.has("hero"):
			t = "★ " + t
		lines.append("%s %s  %d/%d" % ["✓" if ok else "•", t, pr, int(q["g"])])
	# Журнал подсказок рунной загадки — чтобы вывести порядок
	for pz in main.pois:
		if is_instance_valid(pz) and pz.has_method("found_clues") and pz.get("state") != "done":
			var fc: Array = pz.found_clues()
			if not fc.is_empty():
				lines.append("Подсказки рун (▲ пламя ◆ лист ● вода ✚ солнце ★ звезда):")
				for c in fc:
					lines.append("  " + str(c))
	var mats: Array = []
	for m in main.Meta.MATERIALS:
		var v := int(main.run.get("mat_" + m, 0))
		if v > 0:
			mats.append("%s %d" % [main.Meta.MATERIALS[m]["icon"], v])
	if not mats.is_empty():
		lines.append("  ".join(mats))
	_tracker.text = "\n".join(lines)
	_tracker.visible = not lines.is_empty()
	var sm: Array = Settings.safe_margins()
	_tracker.position = Vector2(14.0 + float(sm[0]), (240.0 if portrait() else 150.0) + float(sm[1]))


## Стрелка к месту появляется, только если место уже попадало в кадр, а потом герой ушёл от него.
var _arrow_seen := {}


func _arrow_ok(n: Node2D, pos: Vector2) -> bool:
	var id := n.get_instance_id()
	if main.on_screen(pos):
		_arrow_seen[id] = true
		return false
	return _arrow_seen.has(id)


func _draw_poi_arrows() -> void:
	var vs := _poi_layer.size
	var c := vs / 2.0
	var me: Vector2 = main.view_center()
	for p in _poi_list():
		if not is_instance_valid(p) or (p.get("state") == "done"):
			continue
		if p.has_method("arrow_visible") and not p.arrow_visible():
			continue
		var pp: Vector2 = p.target_pos() if p.has_method("target_pos") else p.position
		if not pp.is_finite():
			continue
		var d: Vector2 = pp - me
		if not _arrow_ok(p, pp):
			continue
		var col: Color = p.color() if p.has_method("color") else Color(1.0, 0.3, 0.35)
		var dir := d.normalized()
		var edge := c + Vector2(dir.x * (vs.x * 0.44), dir.y * (vs.y * 0.40))
		var pts := PackedVector2Array([edge + dir * 16.0, edge + dir.rotated(2.5) * 12.0, edge + dir.rotated(-2.5) * 12.0])
		_poi_layer.draw_colored_polygon(pts, Color(col, 0.9))
		var name_txt: String = p.title() if p.has_method("title") else "Алтарь мобов"
		_poi_layer.draw_string(ThemeDB.fallback_font, edge - dir * 22.0 + Vector2(-60, 5), "%s  %dм" % [name_txt, int(d.length() / 100.0)], HORIZONTAL_ALIGNMENT_CENTER, 120, 13, Color(col, 0.9))
	# Сундуки: золотые стрелки к краю экрана
	for ch in get_tree().get_nodes_in_group("chests"):
		if not is_instance_valid(ch):
			continue
		var d: Vector2 = ch.position - me
		if not _arrow_ok(ch, ch.position):
			continue
		var col := GOLD
		var dir := d.normalized()
		var edge := c + Vector2(dir.x * (vs.x * 0.46), dir.y * (vs.y * 0.43))
		var pts := PackedVector2Array([edge + dir * 14.0, edge + dir.rotated(2.5) * 10.0, edge + dir.rotated(-2.5) * 10.0])
		_poi_layer.draw_colored_polygon(pts, Color(col, 0.95))
		_poi_layer.draw_string(ThemeDB.fallback_font, edge - dir * 20.0 + Vector2(-60, 5), "Сундук  %dм" % int(d.length() / 100.0), HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Color(col, 0.9))


# ---------- TAB: все текущие характеристики ----------

var _stats_root: Control
var _stats_box: Container
var _stats_t := 0.0


var force_stats := false
func _stats_held() -> bool:
	if force_stats or Input.is_key_pressed(KEY_TAB):
		return true
	for d in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(d, JOY_BUTTON_BACK):
			return true
	return false


func _pct(v: float) -> String:
	return ("+%d%%" % int(round(v * 100.0))) if v >= 0.0 else ("%d%%" % int(round(v * 100.0)))


func _num(v) -> String:
	if v is float:
		return ("%.2f" % v).rstrip("0").rstrip(".")
	return str(v)


## Колонка характеристик фиксированной ширины: длинные заголовки и значения
## переносятся по словам и никогда не выходят за рамку.
func _stat_col(title: String, rows: Array, accent: Color, width := 330.0) -> Control:
	var panel := PanelContainer.new()
	var b := _neon_box(accent, PANEL_BG, 2, 6, 8)
	b.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", b)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(width, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var inner := width - 28.0
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	panel.add_child(v)
	var tl := _label(title, 18, accent, Color(accent, 0.5))
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.custom_minimum_size = Vector2(inner, 0)
	v.add_child(tl)
	for r in rows:
		if r.size() == 1:
			var sub := _label(r[0], 14, accent.lightened(0.3))
			sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			sub.custom_minimum_size = Vector2(inner, 0)
			v.add_child(sub)
			continue
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var nl := _label(r[0], 13, Color(0.78, 0.78, 0.92))
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.custom_minimum_size = Vector2(inner * 0.45, 0)
		h.add_child(nl)
		var val := _label(r[1], 13, Color(1.0, 0.9, 0.55))
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		val.custom_minimum_size = Vector2(inner * 0.5, 0)
		h.add_child(val)
		v.add_child(h)
	return panel


func _update_stats_panel(delta: float) -> void:
	var held := _stats_held() and not is_modal_open()
	if _stats_root == null:
		if not held:
			return
		_stats_root = Control.new()
		_full_rect(_stats_root)
		_stats_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dim := ColorRect.new()
		dim.color = Color(0.02, 0.0, 0.06, 0.55)
		_full_rect(dim)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stats_root.add_child(dim)
		# Прокрутка, если колонки не помещаются (узкий / вертикальный экран);
		# колонки сами переносятся на новую строку
		var sc := ScrollContainer.new()
		_full_rect(sc)
		sc.offset_left = 12
		sc.offset_right = -12
		sc.offset_top = 200 if portrait() else 70
		sc.offset_bottom = -12
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.mouse_filter = Control.MOUSE_FILTER_PASS
		_stats_root.add_child(sc)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 10)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(v)
		var t := _label("ХАРАКТЕРИСТИКИ  •  %s" % ("≡ — закрыть" if Settings.input_mode() == "touch" else "удерживайте " + Settings.key("stats")), 22, Color.WHITE, Color(CYAN, 0.7))
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(t)
		var fl := HFlowContainer.new()
		fl.add_theme_constant_override("h_separation", 14)
		fl.add_theme_constant_override("v_separation", 14)
		fl.alignment = FlowContainer.ALIGNMENT_CENTER
		fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(fl)
		_stats_box = fl
		add_child(_stats_root)
	_stats_root.visible = held
	if not held:
		_stats_t = 0.0
		return
	_stats_t -= delta
	if _stats_t > 0.0:
		return
	_stats_t = 0.3
	for c in _stats_box.get_children():
		c.queue_free()
	var p: Node2D = _me()
	var base_speed0: float = Data.CHARACTERS[p.char_id]["speed"]
	var hero_rows := [
		["Уровень", "%d  (%d / %d опыта)" % [p.level, int(p.xp), int(p.xp_to_next)]],
		["Здоровье", "%d / %d" % [int(p.hp), int(p.max_hp)]],
		["Регенерация", "%s / с" % _num(snappedf(p.regen, 0.01))],
		["Броня", ("-%s урона" % _num(snappedf(p.armor + p._bastion, 0.1))) if p.armor + p._bastion > 0.0 else "0"],
		["Уклонение", "%d%%" % int(p.dodge * 100.0)],
		["Скорость", "%d  (%s)" % [int(p.base_speed), _pct(p.base_speed / base_speed0 - 1.0)]],
		["Радиус сбора", "%d" % int(p.magnet)],
		["Опыт", _pct(p.xp_mult - 1.0)],
		["Шанс сундука", _pct(p.chest_bonus)],
		["Лечение за убийство", _num(snappedf(p.kill_heal, 0.01))],
		["Сила лечения", _pct(p.heal_mult - 1.0)],
		["Способность: перезарядка", "%s с" % _num(snappedf(p.ability_cd * p.cooldown_mult, 0.1))],
		["Сила способности", _pct(p.power - 1.0)],
	]
	if not p.buffs.is_empty():
		hero_rows.append(["Баффы алтарей"])
		for k in p.buffs:
			hero_rows.append([{"rage": "Ярость", "haste": "Стремительность", "crit": "Око охотника", "magnet": "Притяжение"}.get(k, k), "%d с" % ceili(p.buffs[k])])
	_stats_box.add_child(_stat_col("ГЕРОЙ — " + Data.CHARACTERS[p.char_id]["name"], hero_rows, MAGENTA))
	var atk_rows := [
		["Урон (общий)", _pct(p.damage_mult - 1.0)],
		["Урон оружия (модули)", _pct(p.weapon_dmg - 1.0)],
		["Перезарядка (общая)", _pct(p.cooldown_mult - 1.0)],
		["Перезарядка оружия", _pct(p.weapon_cd - 1.0)],
		["Область (общая)", _pct(p.area_mult - 1.0)],
		["Область оружия", _pct(p.weapon_area - 1.0)],
		["Шанс крита", "%d%%" % int((p.crit_chance + p.weapon_crit) * 100.0)],
		["Длительность статусов", _pct(p.status_mult * p.weapon_status - 1.0)],
		["Доп. снаряды", "+%d" % p.extra_proj],
		["Урон реакций", _pct(p.react_mult - 1.0)],
		["Урон статусов (DoT)", _pct(p.dot_mult - 1.0)],
	]
	if not p.passives.is_empty():
		atk_rows.append(["Модули"])
		for id in p.passives:
			atk_rows.append([Data.PASSIVES[id]["name"], "ур. %d" % p.passives[id]])
	_stats_box.add_child(_stat_col("АТАКА И МОДУЛИ", atk_rows, GOLD))
	var w_rows: Array = []
	var names := {"damage": "урон", "cooldown": "перезарядка, с", "count": "количество", "pierce": "пробивание",
		"radius": "радиус", "range": "дальность", "length": "длина", "strikes": "удары", "beams": "лучи",
		"interval": "интервал, с", "duration": "длительность, с", "tick": "такт, с", "speed": "скорость снаряда"}
	# Порядок: основа слияния, сразу под ней — её второе оружие
	var order: Array = []
	for id in p.weapons:
		if p.is_secondary(id):
			continue
		order.append(id)
		var pt: String = p.partner(id)
		if pt != "":
			order.append(pt)
	for id in order:
		var s: Dictionary = p.stats(id)
		var head := "%s  ур. %d" % [Data.WEAPONS[id]["name"], p.weapons[id]]
		var fu: Array = p.fusion_of(id)
		if not fu.is_empty() and id == fu[0]:
			head = "★ %s (слияние, 1 слот) — основа: %s" % [Data.fused_name(fu[0], fu[1]), Data.WEAPONS[id]["name"]]
		elif not fu.is_empty():
			head = "   + залп в слиянии: %s" % Data.WEAPONS[id]["name"]
		w_rows.append([head])
		for k in names:
			if s.has(k) and (s[k] is float or s[k] is int):
				var val = s[k]
				if k == "damage":
					val = float(val) * p.damage_mult
				w_rows.append(["   " + names[k], _num(snappedf(float(val), 0.01))])
		var asp: Array = p.evolved.get(id, [])
		if not asp.is_empty():
			var an: Array = []
			for m in asp:
				an.append(Data.ASPECTS[m]["name"])
			w_rows.append(["   аспекты", ", ".join(an)])
	if not w_rows.is_empty():
		_stats_box.add_child(_stat_col("ОРУЖИЕ", w_rows, CYAN, 420.0))


func _process(delta: float) -> void:
	_t += delta
	_update_stats_panel(delta)
	if main and "pois" in main:
		_update_pois()
	var modal: Control = null
	for r in [_levelup_root, _chest_root, _over_root, _pause_root, _endless_root]:
		if r != null and r.visible:
			modal = r
	if modal != _focus_root:
		_focus_root = modal
		_focus = {}
		# Окно — поверх всех плашек (зона, сюжет, подсказки), иначе они перекрывают кнопки
		if modal != null:
			move_child(modal, get_child_count() - 1)
	if modal != null:
		UiFocus.keep(modal, _focus)
	_lvl_t += delta
	# Кооператив: улучшение выбирает тот, чья очередь, своим устройством
	if modal == _levelup_root and main.coop and main._chooser != null and main._chooser.input != null and _lvl_t > 0.35:
		var inp = main._chooser.input
		inp.poll()
		var cards := _cards.get_children().filter(func(b): return not b.is_queued_for_deletion())
		if not cards.is_empty():
			var f := get_viewport().gui_get_focus_owner()
			var i: int = cards.find(f)
			if inp.just("left") or inp.just("right") or i < 0:
				i = clampi((0 if i < 0 else i) + (-1 if inp.just("left") else (1 if inp.just("right") else 0)), 0, cards.size() - 1)
				cards[i].grab_focus()
				UiFocus.pad_mode = true
			if inp.just("ok"):
				cards[i].pressed.emit()
	if main == null or main.player == null:
		return
	var p: Node2D = _me()
	_xp_bar.max_value = p.xp_to_next
	_xp_bar.value = lerpf(_xp_bar.value, float(p.xp), minf(1.0, delta * 12.0))
	_hp_bar.max_value = p.max_hp
	_hp_bar.value = lerpf(_hp_bar.value, p.hp, minf(1.0, delta * 10.0))
	_hp_label.text = ("ПАЛ — ВСТАНЬТЕ РЯДОМ" if p._dead else "%d / %d" % [int(ceil(p.hp)), int(p.max_hp)])
	if main.coop and _p2_hp:
		_update_p2(delta)
	_level_label.text = "УР %d" % p.level
	if main.endless:
		_time_label.text = "∞ %s  •  мин %d" % [_fmt_time(main.time_alive), main.endless_min]
	else:
		_time_label.text = "%s / %s" % [_fmt_time(main.time_alive), _fmt_time(main.level["time"])]
	_kills_label.text = str(main.kills)
	# Неоновое «дыхание» таймера
	var pulse := 0.5 + 0.5 * sin(_t * 2.0)
	_time_label.add_theme_color_override("font_shadow_color", Color(MAGENTA, 0.5 + 0.4 * pulse))
	_update_weapons(p)
	if main.boss != null and is_instance_valid(main.boss):
		_boss_bar.max_value = main.boss.max_hp
		_boss_bar.value = lerpf(_boss_bar.value, main.boss.hp, minf(1.0, delta * 8.0))
	# Способность
	var cd: float = p.ability_left
	var full: float = maxf(0.01, p.ability_cd * p.cooldown_mult)
	_ability_shade.anchor_top = 1.0 - clampf(cd / full, 0.0, 1.0)
	_ability_label.text = ("%.0f" % ceil(cd)) if cd > 0.0 else _ab_hint(0)
	_ability_icon.modulate = Color(1, 1, 1) if cd <= 0.0 else Color(0.5, 0.5, 0.6)


func _fmt_time(t: float) -> String:
	var s := int(t)
	return "%02d:%02d" % [s / 60, s % 60]


# ---------- Строительные блоки ----------

func _full_rect(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


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
		l.add_theme_constant_override("shadow_outline_size", 14)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _neon_box(border: Color, bg := PANEL_BG, width := 2, radius := 4, glow := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(border, 0.45)
	s.shadow_size = glow
	s.set_content_margin_all(6)
	return s


func _bar(fill_color: Color, border: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.add_theme_stylebox_override("background", _neon_box(border, Color(0.03, 0.02, 0.07, 0.9), 2, 3, 6))
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(2)
	fill.border_color = fill_color.lightened(0.4)
	fill.border_width_top = 2
	fill.set_expand_margin_all(-2)
	b.add_theme_stylebox_override("fill", fill)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _icon_rect(tex: Texture2D, size: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = Vector2(size, size)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# ---------- Основной HUD ----------

func _build_hud() -> void:
	var root := Control.new()
	_full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_safe_root = root

	_xp_bar = _bar(CYAN.darkened(0.15), CYAN)
	_xp_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_xp_bar.offset_left = 8
	_xp_bar.offset_right = -8
	_xp_bar.offset_top = 8
	_xp_bar.offset_bottom = 26
	root.add_child(_xp_bar)

	var lvl_panel := PanelContainer.new()
	lvl_panel.add_theme_stylebox_override("panel", _neon_box(GOLD))
	lvl_panel.position = Vector2(12, 34)
	lvl_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_label = _label("УР 1", 20, GOLD, Color(GOLD, 0.6))
	lvl_panel.add_child(_level_label)
	root.add_child(lvl_panel)

	_time_label = _label("00:00", 40, Color(1.0, 0.9, 1.0), Color(MAGENTA, 0.8))
	_time_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.offset_left = -120
	_time_label.offset_right = 120
	_time_label.offset_top = 30
	root.add_child(_time_label)

	var kills_box := HBoxContainer.new()
	kills_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	kills_box.offset_left = -170
	kills_box.offset_right = -14
	kills_box.offset_top = 36
	kills_box.alignment = BoxContainer.ALIGNMENT_END
	kills_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kills_box.add_child(_icon_rect(Pixel.icon("skull"), 30))
	_kills_label = _label("0", 24, Color(1, 0.85, 0.95), Color(MAGENTA, 0.6))
	kills_box.add_child(_kills_label)
	root.add_child(kills_box)

	if main.coop:
		# В кооперативе ряды двух игроков переносятся, чтобы не налезать друг на друга
		var flow := HFlowContainer.new()
		flow.size = Vector2(560, 0)
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 4)
		_weapons_box = flow
	else:
		_weapons_box = HBoxContainer.new()
		_weapons_box.add_theme_constant_override("separation", 6)
	_weapons_box.position = Vector2(12, 82)
	_weapons_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_weapons_box)

	_hp_bar = _bar(Color(0.9, 0.12, 0.3), MAGENTA)
	_hp_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hp_bar.offset_left = -180
	_hp_bar.offset_right = 180
	_hp_bar.offset_top = -40
	_hp_bar.offset_bottom = -18
	_hp_bar.value = 100
	root.add_child(_hp_bar)
	# Индикатор способности
	var ab := PanelContainer.new()
	ab.add_theme_stylebox_override("panel", _neon_box(GOLD, PANEL_BG, 2, 6, 8))
	ab.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	ab.offset_left = 16
	ab.offset_top = -110
	ab.offset_right = 104
	ab.offset_bottom = -16
	ab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ab)
	var abv := VBoxContainer.new()
	abv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ab.add_child(abv)
	var icon_holder := Control.new()
	icon_holder.custom_minimum_size = Vector2(56, 56)
	icon_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	abv.add_child(icon_holder)
	_ability_icon = _icon_rect(Pixel.icon("ab_" + _me().char_id), 56)
	_full_rect(_ability_icon)
	icon_holder.add_child(_ability_icon)
	_ability_shade = ColorRect.new()
	_ability_shade.color = Color(0, 0, 0, 0.55)
	_full_rect(_ability_shade)
	_ability_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_holder.add_child(_ability_shade)
	_ability_label = _label(_ab_hint(0), 11, GOLD)
	_ability_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	abv.add_child(_ability_label)

	# Полоса босса
	_boss_root = VBoxContainer.new()
	_boss_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_boss_root.offset_left = -320
	_boss_root.offset_right = 320
	_boss_root.offset_top = 84
	_boss_root.offset_bottom = 130
	_boss_root.visible = false
	_boss_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_boss_root)
	_boss_name = _label("", 20, Color.WHITE, Color(MAGENTA, 0.7))
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_root.add_child(_boss_name)
	_boss_bar = _bar(Color(0.8, 0.15, 0.5), MAGENTA)
	_boss_bar.custom_minimum_size = Vector2(640, 16)
	_boss_root.add_child(_boss_bar)

	_hp_label = _label("100 / 100", 15, Color.WHITE)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_full_rect(_hp_label)
	_hp_bar.add_child(_hp_label)
	if main.coop:
		_build_p2(root)
	relayout()


var _last_choices: Array = []
var _last_lvl_title := ""
var _last_lvl_sub := ""


## Раскладка под положение экрана (телефон можно повернуть прямо в бою).
var _safe_root: Control


func relayout() -> void:
	var p := portrait()
	if _safe_root:
		Settings.apply_safe(_safe_root)
	if not main.coop:
		_weapons_box.position = Vector2(12, 132 if p else 82)
	var bw := 600.0 if p else 640.0
	_boss_root.offset_left = -bw / 2.0
	_boss_root.offset_right = bw / 2.0
	_boss_root.offset_top = 196 if p else 84
	_boss_bar.custom_minimum_size = Vector2(bw, 16)
	if _quest:
		_quest.offset_left = -340 if p else -400
		_quest.offset_right = 340 if p else 400
	_stats_t = 0.0
	if _levelup_root and _levelup_root.visible and not _last_choices.is_empty():
		show_level_up(_last_choices, _last_lvl_title, _last_lvl_sub)


func _build_p2(root: Control) -> void:
	var c1: Color = _me().player_color()
	var c2: Color = _other().player_color()
	# Полосы здоровья: свой герой слева, напарник справа
	_hp_bar.offset_left = -400
	_hp_bar.offset_right = -30
	_hp_bar.add_child(_tag("P%d" % (_me().pid + 1), c1, Vector2(-38, -2)))
	_p2_hp = _bar(Color(0.9, 0.12, 0.3), MAGENTA)
	_p2_hp.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_p2_hp.offset_left = 30
	_p2_hp.offset_right = 400
	_p2_hp.offset_top = -40
	_p2_hp.offset_bottom = -18
	root.add_child(_p2_hp)
	_p2_hp_label = _label("100 / 100", 15, Color.WHITE)
	_p2_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_p2_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_full_rect(_p2_hp_label)
	_p2_hp.add_child(_p2_hp_label)
	_p2_hp.add_child(_tag("P%d" % (_other().pid + 1), c2, Vector2(376, -2)))
	# Опыт напарника — тонкая полоска под его здоровьем
	_p2_xp = _bar(CYAN.darkened(0.15), CYAN)
	_p2_xp.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_p2_xp.offset_left = 30
	_p2_xp.offset_right = 400
	_p2_xp.offset_top = -14
	_p2_xp.offset_bottom = -8
	root.add_child(_p2_xp)
	# Оружие второго игрока — справа сверху
	var flow := HFlowContainer.new()
	flow.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	flow.offset_left = -572
	flow.offset_right = -12
	flow.offset_top = 82
	flow.alignment = FlowContainer.ALIGNMENT_END
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 4)
	_p2_weapons = flow
	_p2_weapons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_p2_weapons)
	# Способность второго игрока — справа снизу
	var ab := PanelContainer.new()
	ab.add_theme_stylebox_override("panel", _neon_box(c2, PANEL_BG, 2, 6, 8))
	ab.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ab.offset_left = -104
	ab.offset_top = -110
	ab.offset_right = -16
	ab.offset_bottom = -16
	ab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ab)
	var abv := VBoxContainer.new()
	abv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ab.add_child(abv)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(56, 56)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	abv.add_child(holder)
	_p2_ab_icon = _icon_rect(Pixel.icon("ab_" + _other().char_id), 56)
	_full_rect(_p2_ab_icon)
	holder.add_child(_p2_ab_icon)
	_p2_ab_shade = ColorRect.new()
	_p2_ab_shade.color = Color(0, 0, 0, 0.55)
	_full_rect(_p2_ab_shade)
	_p2_ab_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_p2_ab_shade)
	_p2_ab_label = _label(_ab_hint(1), 11, c2)
	_p2_ab_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	abv.add_child(_p2_ab_label)


## Свой герой (слева на экране) и напарник (справа).
func _me() -> Node2D:
	if main.net_mode == "client" and main.players.size() > 1:
		return main.players[1]
	return main.player


func _other() -> Node2D:
	if main.players.size() < 2:
		return main.player
	return main.players[0] if _me() == main.players[1] else main.players[1]


## Оружие с аспектом подсвечено цветом аспекта.
func _weapon_color(p: Node2D, id: String) -> Color:
	if not p.fusion_of(id).is_empty():
		return GOLD
	var list: Array = p.evolved.get(id, [])
	if not list.is_empty() and Data.ASPECTS.has(list[-1]):
		return Data.ASPECTS[list[-1]]["color"]
	return CYAN


## Цвет модуля: героя — розовый, оружия — золотой.
func _mod_color(id: String) -> Color:
	return MAGENTA if Data.PASSIVES.get(id, {}).get("kind", "hero") == "hero" else GOLD


func _ab_hint(i: int) -> String:
	if main.net_mode != "":
		return Settings.key("ability") if i == 0 else "ИГРОК %d" % (_other().pid + 1)
	if not main.coop:
		return Settings.key("ability")
	return DevInput.ability_hint(Data.coop_devices[i])


func _tag(text: String, col: Color, pos: Vector2) -> Label:
	var l := _label(text, 18, col, Color(col, 0.6))
	l.position = pos
	return l


func _update_p2(delta: float) -> void:
	var p: Node2D = _other()
	_p2_hp.max_value = p.max_hp
	_p2_hp.value = lerpf(_p2_hp.value, p.hp, minf(1.0, delta * 10.0))
	var st := "ПАЛ — НУЖНА ПОМОЩЬ" if p._dead else ("выбирает улучшение" if p.choosing else "%d / %d" % [int(ceil(p.hp)), int(p.max_hp)])
	_p2_hp_label.text = "УР %d  •  %s" % [p.level, st]
	_p2_xp.max_value = p.xp_to_next
	_p2_xp.value = p.xp
	var sig := str(p.weapons) + str(p.passives) + str(p.evolved) + str(p.fusions)
	if sig != _p2_sig:
		_p2_sig = sig
		_fill_slots(_p2_weapons, p)
	var cd: float = p.ability_left
	var full: float = maxf(0.01, p.ability_cd * p.cooldown_mult)
	_p2_ab_shade.anchor_top = 1.0 - clampf(cd / full, 0.0, 1.0)
	_p2_ab_label.text = ("%.0f" % ceil(cd)) if cd > 0.0 else _ab_hint(1)
	_p2_ab_icon.modulate = Color(1, 1, 1) if cd <= 0.0 else Color(0.5, 0.5, 0.6)


func _update_weapons(p: Node2D) -> void:
	var sig := str(p.weapons) + str(p.passives) + str(p.evolved) + str(p.fusions)
	if sig == _weapons_sig:
		return
	_weapons_sig = sig
	_fill_slots(_weapons_box, p)


## Слоты оружия и модулей. Эволюция — два оружия в ОДНОМ слоте со своей иконкой.
func _fill_slots(box: Control, p: Node2D) -> void:
	for c in box.get_children():
		c.queue_free()
	for id in p.weapons:
		var fu: Array = p.fusion_of(id)
		if not fu.is_empty() and id == fu[1]:
			continue
		if not fu.is_empty():
			box.add_child(_slot(id, 0, GOLD, Pixel.fusion_icon(fu[0], fu[1]), "СЛИЯНИЕ"))
			continue
		box.add_child(_slot(id, p.weapons[id], _weapon_color(p, id)))
	for id in p.passives:
		box.add_child(_slot(id, p.passives[id], _mod_color(id)))


func _slot(id: String, lvl: int, border: Color, icon_tex: Texture2D = null, tag := "") -> Control:
	var panel := PanelContainer.new()
	var box := _neon_box(border, PANEL_BG, 2, 4, 4)
	box.set_content_margin_all(3)
	panel.add_theme_stylebox_override("panel", box)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_icon_rect(icon_tex if icon_tex != null else Pixel.icon(id), 36))
	var l := _label(tag if tag != "" else "УР %d" % lvl, 10, border)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	panel.add_child(v)
	return panel


# ---------- Оверлеи ----------

func _make_overlay(dim_color: Color) -> Control:
	var root := Control.new()
	_full_rect(root)
	root.visible = false
	add_child(root)
	var dim := ColorRect.new()
	dim.color = dim_color
	_full_rect(dim)
	root.add_child(dim)
	return root


func _build_level_up() -> void:
	_levelup_root = _make_overlay(Color(0.03, 0.0, 0.08, 0.7))
	var center := CenterContainer.new()
	_full_rect(center)
	_levelup_root.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	center.add_child(v)
	var title := _label("ПОВЫШЕНИЕ УРОВНЯ", 38, Color(1.0, 0.95, 0.75), Color(GOLD, 0.8))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_lvl_title = title
	var sub := _label("выберите модуль  •  " + Settings.key("pick"), 16, Color(0.75, 0.7, 0.9))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lvl_sub = sub
	v.add_child(sub)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 22)
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(_cards)


## Экран выше, чем шире (телефон в вертикальном положении)
func portrait() -> bool:
	var vs := get_viewport().get_visible_rect().size
	return vs.y > vs.x


func _card(index: int, ch: Dictionary) -> Button:
	var is_weapon: bool = ch["type"] == "weapon"
	var is_evo: bool = ch["type"] == "evo"
	var is_fusion: bool = ch["type"] == "fusion"
	var accent := CYAN if is_weapon else (MAGENTA if ch["type"] == "passive" else Color(0.4, 1.0, 0.5))
	if is_evo:
		accent = Data.ASPECTS[ch["module"]]["color"]
	elif is_fusion:
		accent = GOLD
	elif ch["type"] == "passive":
		accent = _mod_color(ch["id"])
	var btn := Button.new()
	var cw := 222.0 if portrait() else 270.0
	btn.custom_minimum_size = Vector2(cw, 430 if portrait() else 400)
	btn.clip_contents = true
	btn.mouse_entered.connect(func(): Sound.play("hover", -10.0))
	btn.add_theme_stylebox_override("normal", _neon_box(accent.darkened(0.35), PANEL_BG, 2, 8, 6))
	btn.add_theme_stylebox_override("hover", _neon_box(accent, Color(0.1, 0.05, 0.18, 0.95), 3, 8, 18))
	btn.add_theme_stylebox_override("pressed", _neon_box(Color.WHITE, Color(0.15, 0.08, 0.25, 0.95), 3, 8, 22))
	btn.add_theme_stylebox_override("focus", _neon_box(accent, Color(0.1, 0.05, 0.18, 0.95), 3, 8, 18))
	btn.pressed.connect(func():
		Sound.play("click")
		main.apply_choice(ch))

	var v := VBoxContainer.new()
	_full_rect(v)
	v.offset_left = 10
	v.offset_right = -10
	v.offset_top = 14
	v.offset_bottom = -14
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(v)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_label("%d" % (index + 1), 16, Color(0.6, 0.6, 0.75)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	var tag_text := "НОВОЕ" if ch["new"] else ("УР %d" % ch["level"] if ch["level"] > 0 else "")
	if is_evo:
		tag_text = "+ " + Data.PASSIVES[ch["module"]]["name"]
	elif is_fusion:
		tag_text = "СЛИЯНИЕ"
	head.add_child(_label(tag_text, 15, GOLD if ch["new"] else accent, Color(GOLD, 0.5) if ch["new"] else Color(0, 0, 0, 0)))
	v.add_child(head)

	var icon_bg := PanelContainer.new()
	icon_bg.add_theme_stylebox_override("panel", _neon_box(accent, Color(0.02, 0.01, 0.05, 0.9), 2, 40, 10))
	icon_bg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_fusion:
		var pair := HBoxContainer.new()
		pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pair.add_child(_icon_rect(Pixel.icon(ch["id"]), 30))
		pair.add_child(_label("+", 18, GOLD))
		pair.add_child(_icon_rect(Pixel.icon(ch["partner"]), 30))
		pair.add_child(_label("=", 18, GOLD))
		pair.add_child(_icon_rect(Pixel.fusion_icon(ch["id"], ch["partner"]), 72))
		icon_bg.add_child(pair)
	else:
		icon_bg.add_child(_icon_rect(Pixel.icon(ch["id"]), 64 if portrait() else 84))
	v.add_child(icon_bg)

	var title := _label(ch["title"], 21, Color.WHITE, Color(accent, 0.6))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(title)
	var dtext: String = ch["desc"]
	var desc := _label(dtext, 15 if dtext.length() < 50 else 13, Color(0.8, 0.8, 0.92))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(cw - 40.0, 0)
	v.add_child(desc)
	var hint_text: String = ch.get("hint", "")
	if hint_text != "":
		var hint := _label(hint_text, 12 if hint_text.length() < 90 else 11, accent.lightened(0.3))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(cw - 40.0, 0)
		v.add_child(hint)
	var kind_text := "ЛЕЧЕНИЕ"
	if is_evo:
		kind_text = "АСПЕКТ ОРУЖИЯ"
	elif is_fusion:
		kind_text = "ЭВОЛЮЦИЯ ОРУЖИЯ"
	elif is_weapon:
		kind_text = "ОРУЖИЕ"
	elif ch["type"] == "passive":
		kind_text = "МОДУЛЬ ГЕРОЯ" if Data.PASSIVES[ch["id"]]["kind"] == "hero" else "МОДУЛЬ ОРУЖИЯ"
	var kind_label := _label(kind_text, 12, accent.darkened(0.1))
	kind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kind_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	kind_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	v.add_child(kind_label)
	return btn


func show_level_up(choices: Array, title := "ПОВЫШЕНИЕ УРОВНЯ", sub := "") -> void:
	if sub == "":
		sub = "выберите модуль  •  " + Settings.key("pick")
	_lvl_t = 0.0
	_last_choices = choices
	_last_lvl_title = title
	_last_lvl_sub = sub
	_lvl_title.text = title
	_lvl_sub.text = sub
	for c in _cards.get_children():
		c.queue_free()
	_cards.add_theme_constant_override("separation", 8 if portrait() else 22)
	for i in choices.size():
		var card := _card(i, choices[i])
		_cards.add_child(card)
		# Карточки вылетают по очереди
		card.modulate = Color(1, 1, 1, 0)
		card.pivot_offset = Vector2(130, 180)
		card.scale = Vector2(0.7, 0.7)
		var tw := card.create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_interval(0.06 * i)
		tw.tween_property(card, "modulate:a", 1.0, 0.15)
		tw.parallel().tween_property(card, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_levelup_root.visible = true


func hide_level_up() -> void:
	_levelup_root.visible = false


var _over_scroll: ScrollContainer


## Размер прокрутки итогов под текущий экран
func _fit_over() -> void:
	var vs := get_viewport().get_visible_rect().size
	var w := minf(780.0, vs.x - 120.0)
	_over_stats.custom_minimum_size = Vector2(w, 0)
	await get_tree().process_frame
	var h := _over_stats.get_combined_minimum_size().y
	_over_scroll.custom_minimum_size = Vector2(w, minf(h, vs.y - 330.0))
	_over_scroll.scroll_vertical = 0


func _build_game_over() -> void:
	_over_root = _make_overlay(Color(0.03, 0.0, 0.08, 0.78))
	var center := CenterContainer.new()
	_full_rect(center)
	_over_root.add_child(center)
	var panel := PanelContainer.new()
	var box := _neon_box(MAGENTA, PANEL_BG, 3, 10, 24)
	box.set_content_margin_all(34)
	panel.add_theme_stylebox_override("panel", box)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	panel.add_child(v)
	_over_title = _label("", 46, Color.WHITE, Color(MAGENTA, 0.8))
	_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_over_title)
	_over_stats = _label("", 20, Color(0.85, 0.85, 1.0))
	_over_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Итоги прокручиваются, если не помещаются: кнопки всегда на экране
	_over_scroll = ScrollContainer.new()
	_over_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_over_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_over_scroll.add_child(_over_stats)
	v.add_child(_over_scroll)
	var btn := Button.new()
	btn.text = "ИГРАТЬ СНОВА"
	btn.custom_minimum_size = Vector2(300, 56)
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_stylebox_override("normal", _neon_box(CYAN.darkened(0.3), PANEL_BG, 2, 6, 6))
	btn.add_theme_stylebox_override("hover", _neon_box(CYAN, Color(0.08, 0.05, 0.16, 0.95), 3, 6, 16))
	btn.add_theme_stylebox_override("pressed", _neon_box(Color.WHITE, Color(0.12, 0.08, 0.2, 0.95), 3, 6, 20))
	btn.add_theme_stylebox_override("focus", _neon_box(CYAN, Color(0.08, 0.05, 0.16, 0.95), 3, 6, 16))
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(func():
		Sound.play("click")
		main.restart())
	v.add_child(btn)
	btn.visible = main.net_mode == ""
	var hub_btn := _menu_button("В ЛОББИ" if (main.coop or main.net_mode != "") else "В УБЕЖИЩЕ", GOLD)
	hub_btn.pressed.connect(func():
		Sound.play("click")
		main.to_hub())
	v.add_child(hub_btn)


## Сюжетная карточка в начале уровня: заголовок и бриф, гаснет сама.
func show_story(title: String, text: String) -> void:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _neon_box(Color(0.75, 0.6, 1.0, 0.7), Color(0.04, 0.02, 0.09, 0.82), 2, 8, 10))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	box.add_child(v)
	var t := _label(title.to_upper(), 16, Color(0.85, 0.75, 1.0))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var b := _label(text, 15, Color(0.95, 0.92, 1.0))
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(b)
	var vs := get_viewport().get_visible_rect().size
	var w := minf(620.0, vs.x - 40.0)
	b.custom_minimum_size = Vector2(w - 24.0, 0)
	add_child(box)
	box.z_index = -1   # под окнами (повышение уровня, сундук, пауза), не поверх кнопок
	box.position = Vector2((vs.x - w) / 2.0, vs.y * (0.62 if portrait() else 0.66))
	box.modulate.a = 0.0
	var tw := box.create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 0.6)
	tw.tween_interval(6.5)
	tw.tween_property(box, "modulate:a", 0.0, 1.0)
	tw.tween_callback(box.queue_free)


func show_game_over(victory: bool, time_alive: float, kills: int, level: int, reactions := 0) -> void:
	_over_title.text = ("УРОВЕНЬ %d ПРОЙДЕН" % (main.level_index + 1)) if victory else "СИГНАЛ ПОТЕРЯН"
	var c := GOLD if victory else MAGENTA
	_over_title.add_theme_color_override("font_shadow_color", Color(c, 0.8))
	var after := ""
	if victory and main.level_index < main.Story.LEVEL_STORY.size():
		after = "«" + str(main.Story.LEVEL_STORY[main.level_index]["after"]) + "»\n\n"
	_over_stats.text = after + "%s  •  %s\n\nВремя:  %s\nУничтожено:  %d\nУровень:  %d\nРеакций:  %d" % [
		_me().char_data["name"], _me().char_data["title"], _fmt_time(time_alive), kills, _me().level, reactions]
	if not main.reward.is_empty():
		_over_stats.text += "\n\nНаграда:  +%d ◆ осколков" % main.reward["total"]
		if main.reward.get("first", 0) > 0:
			_over_stats.text += "\nПервое прохождение:  +%d ◆" % main.reward["first"]
		if main.endless_min > 0:
			_over_stats.text += "\nБесконечный режим: %d мин  (+%d ◆)" % [main.endless_min, main.reward.get("endless", 0)]
		if int(main.reward.get("bonus", 0)) > 0:
			_over_stats.text += "\nУгроза %d и испытание: +%d ◆" % [main.threat, int(main.reward["bonus"])]
		var mats: Dictionary = main.reward.get("materials", {})
		if not mats.is_empty():
			var parts: Array = []
			for m in mats:
				parts.append("+%d %s %s" % [int(mats[m]), main.Meta.MATERIALS[m]["icon"], main.Meta.MATERIALS[m]["name"]])
			_over_stats.text += "\nМатериалы для базы:  " + "   ".join(parts) + ("" if victory else "  (при поражении — 60%)")
		for q in main.reward.get("quests", []):
			_over_stats.text += "\n✓ Задание «%s»:  %s" % [q[0], q[1]]
		if str(main.reward.get("built", "")) != "":
			_over_stats.text += "\n⚒ Стройка завершена: %s" % main.Meta.BUILDINGS[main.reward["built"]]["name"]
		if int(main.reward.get("greed", 0)) > 0:
			_over_stats.text += "\nНавык «Жадность»: +%d ◆" % int(main.reward["greed"])
		var prog: Array = main.Lore.summary_lines(main.reward.get("prog", {}))
		if not prog.is_empty():
			_over_stats.text += "\n\n— ПУТЬ ОХОТНИКА —\n" + "\n".join(prog)
	_fit_over()
	_over_root.visible = true
	_over_root.modulate.a = 0.0
	var tw := _over_root.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_over_root, "modulate:a", 1.0, 0.5)


func _menu_button(text: String, accent: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(300, 52)
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_stylebox_override("normal", _neon_box(accent.darkened(0.3), PANEL_BG, 2, 6, 6))
	btn.add_theme_stylebox_override("hover", _neon_box(accent, Color(0.08, 0.05, 0.16, 0.95), 3, 6, 16))
	btn.add_theme_stylebox_override("pressed", _neon_box(Color.WHITE, Color(0.12, 0.08, 0.2, 0.95), 3, 6, 20))
	btn.add_theme_stylebox_override("focus", _neon_box(accent, Color(0.08, 0.05, 0.16, 0.95), 3, 6, 16))
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.mouse_entered.connect(func(): Sound.play("hover", -10.0))
	return btn


# ---------- Босс ----------

## Название района, в который вошёл герой — под таймером (ниже полосы босса, если она есть).
var _area_label: Label
var _area_tw: Tween
func show_area(text: String, color: Color) -> void:
	if _area_label == null:
		_area_label = _label("", 22, Color(1, 1, 1), Color(color, 0.8))
		_area_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_area_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_area_label.offset_left = -300
		_area_label.offset_right = 300
		_area_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_time_label.get_parent().add_child(_area_label)
	_area_label.text = "— %s —" % text
	_area_label.add_theme_color_override("font_color", color.lightened(0.35))
	_area_label.add_theme_color_override("font_shadow_color", Color(color, 0.8))
	_area_label.offset_top = 140.0 if _boss_root.visible else 84.0
	_area_label.offset_bottom = _area_label.offset_top + 30.0
	if _area_tw:
		_area_tw.kill()
	_area_label.modulate.a = 0.0
	_area_tw = create_tween()
	_area_tw.tween_property(_area_label, "modulate:a", 1.0, 0.4)
	_area_tw.tween_interval(2.2)
	_area_tw.tween_property(_area_label, "modulate:a", 0.0, 0.8)


var _boss_base_name := ""
func boss_phase(n: int, pname: String) -> void:
	_boss_name.text = "%s   •   ФАЗА %d: %s" % [_boss_base_name, n, pname]


func show_boss(boss_name: String, color: Color) -> void:
	_boss_base_name = boss_name
	_boss_name.text = boss_name + "   •   ФАЗА 1"
	_boss_name.add_theme_color_override("font_shadow_color", Color(color, 0.8))
	_boss_bar.value = _boss_bar.max_value
	_boss_root.visible = true


func hide_boss() -> void:
	_boss_root.visible = false


# ---------- Сундук ----------

func _build_chest() -> void:
	_chest_root = _make_overlay(Color(0.03, 0.0, 0.08, 0.75))
	var center := CenterContainer.new()
	_full_rect(center)
	_chest_root.add_child(center)
	var panel := PanelContainer.new()
	var box := _neon_box(GOLD, PANEL_BG, 3, 10, 26)
	box.set_content_margin_all(30)
	panel.add_theme_stylebox_override("panel", box)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var title := _label("СУНДУК ВСКРЫТ", 36, Color(1.0, 0.95, 0.75), Color(GOLD, 0.8))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_chest_icon = _icon_rect(Pixel.icon("chest"), 96)
	_chest_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(_chest_icon)
	_chest_list = VBoxContainer.new()
	_chest_list.add_theme_constant_override("separation", 10)
	v.add_child(_chest_list)
	var btn := _menu_button("ЗАБРАТЬ", GOLD)
	btn.pressed.connect(func():
		Sound.play("click")
		main.close_chest())
	v.add_child(btn)


func show_chest(rewards: Array) -> void:
	for c in _chest_list.get_children():
		c.queue_free()
	for i in rewards.size():
		var r: Dictionary = rewards[i]
		var row := PanelContainer.new()
		var is_evo: bool = r["type"] == "evo"
		row.add_theme_stylebox_override("panel", _neon_box(GOLD if is_evo else CYAN, PANEL_BG, 2, 6, 12 if is_evo else 4))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		row.add_child(h)
		h.add_child(_icon_rect(Pixel.icon(r["id"]), 56))
		var tv := VBoxContainer.new()
		tv.add_child(_label(("АСПЕКТ!  " if is_evo else "") + r["title"], 22, GOLD if is_evo else Color.WHITE, Color(GOLD, 0.6) if is_evo else Color(0, 0, 0, 0)))
		var d := _label(r["desc"], 15, Color(0.8, 0.8, 0.95))
		d.custom_minimum_size = Vector2(360, 0)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(d)
		h.add_child(tv)
		_chest_list.add_child(row)
		row.modulate.a = 0.0
		var tw := row.create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_interval(0.5 + 0.25 * i)
		tw.tween_property(row, "modulate:a", 1.0, 0.25)
		tw.tween_callback(func(): Sound.play("gem", -4.0, 1.0 + i * 0.25))
	_chest_root.visible = true
	# Сундук трясётся перед открытием
	_chest_icon.pivot_offset = Vector2(48, 48)
	var shake := _chest_icon.create_tween()
	shake.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	for i in 6:
		shake.tween_property(_chest_icon, "rotation", 0.15 * (1 if i % 2 == 0 else -1), 0.05)
	shake.tween_property(_chest_icon, "rotation", 0.0, 0.05)
	shake.tween_property(_chest_icon, "scale", Vector2(1.3, 1.3), 0.1)
	shake.tween_property(_chest_icon, "scale", Vector2.ONE, 0.15)


func hide_chest() -> void:
	_chest_root.visible = false


# ---------- Пауза ----------

func _build_pause() -> void:
	_pause_root = _make_overlay(Color(0.03, 0.0, 0.08, 0.7))
	var center := CenterContainer.new()
	_full_rect(center)
	_pause_root.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	center.add_child(v)
	var title := _label("ПАУЗА", 48, Color.WHITE, Color(CYAN, 0.8))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var cont := _menu_button("ПРОДОЛЖИТЬ", CYAN)
	cont.pressed.connect(func():
		Sound.play("click")
		toggle_pause())
	v.add_child(cont)
	var sett := _menu_button("НАСТРОЙКИ", GOLD)
	sett.pressed.connect(func():
		Sound.play("click")
		_open_pause_settings(true))
	v.add_child(sett)
	_pause_menu = v
	var hub_text := "СДАТЬСЯ И В УБЕЖИЩЕ"
	if main.net_mode == "client":
		hub_text = "ПОКИНУТЬ ИГРУ"
	elif main.coop:
		hub_text = "СДАТЬСЯ И В ЛОББИ"
	var hub := _menu_button(hub_text, MAGENTA)
	hub.pressed.connect(func():
		Sound.play("click")
		main.on_player_died_quit())
	v.add_child(hub)


var _pause_menu: Control
var _pause_settings: Control


## Настройки прямо в паузе боя — та же панель, что и в главном меню
func _open_pause_settings(on: bool) -> void:
	if on and _pause_settings == null:
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sc.offset_top = 20
		sc.offset_bottom = -20
		sc.process_mode = Node.PROCESS_MODE_ALWAYS
		_pause_root.add_child(sc)
		var wrap := CenterContainer.new()
		wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.add_child(wrap)
		var sp = preload("res://scripts/settings_panel.gd").new()
		sp.on_back = func(): _open_pause_settings(false)
		wrap.add_child(sp)
		_pause_settings = sc
	if _pause_settings != null:
		_pause_settings.visible = on
	_pause_menu.get_parent().visible = not on


func toggle_pause() -> void:
	_pause_root.visible = not _pause_root.visible
	if not _pause_root.visible and _pause_settings != null and _pause_settings.visible:
		Settings.save_settings()
		_open_pause_settings(false)
	# Клиент сетевой игры не может остановить мир хоста
	if main.net_mode != "client":
		get_tree().paused = _pause_root.visible


# ---------- Ожидание (сетевая игра) ----------

var _wait_root: Control
var _wait_label: Label


func show_wait(text: String) -> void:
	if _wait_root == null:
		_wait_root = Control.new()
		_full_rect(_wait_root)
		_wait_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_wait_root)
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _neon_box(GOLD, PANEL_BG, 2, 8, 10))
		panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		panel.offset_left = -260
		panel.offset_right = 260
		panel.offset_top = 140
		panel.offset_bottom = 196
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_wait_root.add_child(panel)
		_wait_label = _label("", 22, Color(1.0, 0.95, 0.8), Color(GOLD, 0.6))
		_wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_wait_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		panel.add_child(_wait_label)
	_wait_label.text = text
	_wait_root.visible = true


func hide_wait() -> void:
	if _wait_root != null:
		_wait_root.visible = false


func is_modal_open() -> bool:
	return _levelup_root.visible or _chest_root.visible or _over_root.visible or _pause_root.visible \
		or (_endless_root != null and _endless_root.visible)


# ---------- Уровень пройден: завершить или бесконечный режим ----------

var _endless_root: Control


func show_endless_choice() -> void:
	if _endless_root == null:
		_endless_root = _make_overlay(Color(0.03, 0.0, 0.08, 0.72))
		var center := CenterContainer.new()
		_full_rect(center)
		_endless_root.add_child(center)
		var panel := PanelContainer.new()
		var box := _neon_box(GOLD, PANEL_BG, 3, 10, 24)
		box.set_content_margin_all(30)
		panel.add_theme_stylebox_override("panel", box)
		center.add_child(panel)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 16)
		panel.add_child(v)
		var title := _label("УРОВЕНЬ ПРОЙДЕН!", 40, Color(1.0, 0.95, 0.75), Color(GOLD, 0.8))
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(title)
		var d := _label("Можно забрать награду сейчас — или остаться в бесконечном режиме.\nКаждую минуту врагов становится больше и они сильнее,\nзато каждая минута даёт +25 ◆. Победа уже засчитана.", 17, Color(0.85, 0.85, 1.0))
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(d)
		var fin := _menu_button("ЗАВЕРШИТЬ И ЗАБРАТЬ НАГРАДУ", GOLD)
		fin.custom_minimum_size = Vector2(440, 56)
		fin.pressed.connect(func():
			Sound.play("click")
			main.finish_level())
		v.add_child(fin)
		var cont := _menu_button("ПРОДОЛЖИТЬ: БЕСКОНЕЧНЫЙ РЕЖИМ ∞", Color(1.0, 0.35, 0.5))
		cont.custom_minimum_size = Vector2(440, 56)
		cont.pressed.connect(func():
			Sound.play("click")
			main.continue_endless())
		v.add_child(cont)
	_endless_root.visible = true


func hide_endless_choice() -> void:
	if _endless_root != null:
		_endless_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	# B / Esc — назад: закрыть паузу, забрать сундук
	if event.is_action_pressed("ui_cancel"):
		if _pause_root.visible:
			get_viewport().set_input_as_handled()
			if _pause_settings != null and _pause_settings.visible:
				Settings.save_settings()
				_open_pause_settings(false)
			else:
				toggle_pause()
			return
		if _chest_root.visible:
			get_viewport().set_input_as_handled()
			main.close_chest()
			return
	if not _levelup_root.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var idx := -1
		match event.physical_keycode:
			KEY_1: idx = 0
			KEY_2: idx = 1
			KEY_3: idx = 2
		var cards := _cards.get_children().filter(func(b): return not b.is_queued_for_deletion())
		if idx >= 0 and idx < cards.size():
			cards[idx].pressed.emit()
			get_viewport().set_input_as_handled()
