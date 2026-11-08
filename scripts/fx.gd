extends RefCounted
## Фабрика эффектов: вспышки частиц, цифры урона, кольца, молнии, световые вспышки.

const Pixel := preload("res://scripts/pixel.gd")
const FxDraw := preload("res://scripts/fx_draw.gd")

const MAX_NUMBERS := 32


## Сетевая игра: хост записывает эффект для клиента; клиент рисует только присланные.
## Возвращает true, если локально эффект рисовать не нужно.
static func _net(main: Node, kind: String, args: Array) -> bool:
	var nm = main.get("net_mode")
	if nm == null or nm == "":
		return false
	if nm == "client":
		if Net.replaying:
			return false
		if Net.local:
			Net.cfx(kind, args)   # свой эффект: рисуем у себя и показываем хосту
			return false
		return true
	if not Net.replaying:
		Net.fx(kind, args)
	return false


## Эффектов на экране уже слишком много (или кадров мало) — новые декоративные пропускаем.
static func _crowded(main: Node, cap: int) -> bool:
	if not ("fx_node" in main) or main.fx_node == null:
		return false
	var k: float = Settings.fx_k()
	if "_fps_s" in main:
		k *= 1.0 if main._fps_s > 45.0 else (0.6 if main._fps_s > 30.0 else 0.35)
	return main.fx_node.get_child_count() > int(cap * k)


# ---------- Частицы на видеокарте ----------
## Процессорные частицы удобно настраивать, но считать их лучше на видеокарте:
## переносим настройки в GPUParticles и кэшируем материал процесса по ключу,
## чтобы одинаковые эффекты не создавали заново текстуры градиентов и кривых.
static var _pm2d := {}
static var _pm3d := {}


static func gpu2d(p: CPUParticles2D, key := "") -> GPUParticles2D:
	var g := GPUParticles2D.new()
	if key != "" and _pm2d.has(key):
		g.process_material = _pm2d[key]
	else:
		g.convert_from_particles(p)
		if key != "":
			_pm2d[key] = g.process_material
	g.amount = p.amount
	g.lifetime = p.lifetime
	g.one_shot = p.one_shot
	g.explosiveness = p.explosiveness
	g.preprocess = p.preprocess
	g.local_coords = p.local_coords
	g.material = p.material
	g.texture = p.texture
	g.z_index = p.z_index
	g.position = p.position
	g.visibility_rect = Rect2(-600, -600, 1200, 1200)
	p.free()
	return g


static func gpu3d(p: CPUParticles3D, key := "") -> GPUParticles3D:
	var g := GPUParticles3D.new()
	if key != "" and _pm3d.has(key):
		g.process_material = _pm3d[key][0]
		g.draw_pass_1 = _pm3d[key][1]
	else:
		g.convert_from_particles(p)
		if key != "":
			_pm3d[key] = [g.process_material, g.draw_pass_1]
	g.amount = p.amount
	g.lifetime = p.lifetime
	g.one_shot = p.one_shot
	g.explosiveness = p.explosiveness
	g.preprocess = p.preprocess
	g.local_coords = p.local_coords
	g.transform = p.transform
	g.visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 60, 80))
	p.free()
	return g


static func _ramp(colors: Array) -> Gradient:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		offs.append(float(i) / float(colors.size() - 1))
		cols.append(colors[i])
	g.offsets = offs
	g.colors = cols
	return g


static func _shrink_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, 1))
	c.add_point(Vector2(1, 0))
	return c


## Взрыв пиксельных частиц.
static func burst(main: Node, pos: Vector2, colors: Array, amount: int, speed: float,
		life: float, size: float, additive := true, gravity := Vector2.ZERO,
		dir := Vector2.UP, spread := 180.0) -> void:
	if _net(main, "burst", [pos, colors, amount, speed, life, size, additive, gravity, dir, spread]):
		return
	# Оптимизация: при толпе ограничиваем число всплесков за кадр и общее число эффектов
	if "burst_budget" in main:
		if main.burst_budget <= 0 or _crowded(main, 380):
			return
		main.burst_budget -= 1
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.damping_min = speed * 0.6
	p.damping_max = speed * 1.2
	p.gravity = gravity
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	p.scale_amount_curve = _shrink_curve()
	p.color_ramp = _ramp(colors)
	p.material = Pixel.mat_add() if additive else Pixel.mat_unshaded()
	p.z_index = 5
	# Частицы считает видеокарта: настройки переносятся в GPU-систему (материал кэшируется)
	var key := "b|%s|%.0f|%.2f|%.1f|%s|%s|%s|%.0f" % [str(colors), speed, life, size, additive, str(gravity), str(dir), spread]
	var g := gpu2d(p, key)
	main.fx_node.add_child(g)
	g.emitting = true
	main.get_tree().create_timer(life + 0.2, false).timeout.connect(g.queue_free)


static func sparks(main: Node, pos: Vector2, color: Color, amount := 6) -> void:
	if main.flash_budget <= 0:
		return
	main.flash_budget -= 1
	burst(main, pos, [Pixel.hdr(color.lerp(Color.WHITE, 0.4), 1.1), Color(color, 0.6), Color(color, 0.0)],
		maxi(2, amount / 2), 220.0, 0.3, 2.5)


static func death(main: Node, pos: Vector2, color: Color, big := false) -> void:
	if big:
		burst(main, pos, [Pixel.hdr(color, 1.3), Color(color, 0.8), Color(color.darkened(0.5), 0.0)],
			28, 450.0, 0.6, 5.0)
		burst(main, pos, [Color(0.15, 0.12, 0.2, 0.9), Color(0.1, 0.08, 0.15, 0.0)],
			15, 225.0, 0.8, 5.0, false, Vector2(0, 60))
		ring(main, pos, 4.0, 85.0, Color(color, 0.7), 0.3, 4.0)
		glow_flash(main, pos, color, 140.0, 0.25)
		return
	# Обычный моб: короткая скромная вспышка
	burst(main, pos, [Color(color, 0.9), Color(color.darkened(0.4), 0.0)], 4, 110.0, 0.3, 3.0)


static func number(main: Node, pos: Vector2, value: float, color := Color.WHITE, size := 15) -> void:
	if _net(main, "number", [pos, value, color, size]):
		return
	if main.fx_numbers >= int(MAX_NUMBERS * Settings.fx_k()):
		return
	main.fx_numbers += 1
	var l := Label.new()
	l.text = str(int(round(value)))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.1))
	l.add_theme_constant_override("outline_size", 5)
	l.material = Pixel.mat_unshaded()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(60, 24)
	l.position = pos + Vector2(-30 + randf_range(-8, 8), -34)
	l.z_index = 30
	l.pivot_offset = Vector2(30, 12)
	l.scale = Vector2(1.5, 1.5 * Pixel.STAND)
	main.fx_node.add_child(l)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector2(1.0, Pixel.STAND), 0.15)
	tw.tween_property(l, "position:y", l.position.y - 28, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.35)
	tw.chain().tween_callback(func():
		main.fx_numbers -= 1
		l.queue_free())


static func text_pop(main: Node, pos: Vector2, text: String, color: Color, size := 28) -> void:
	if _net(main, "text_pop", [pos, text, color, size]):
		return
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.1))
	l.add_theme_constant_override("outline_size", 8)
	l.material = Pixel.mat_unshaded()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(400, 40)
	l.pivot_offset = Vector2(200, 20)
	l.position = pos + Vector2(-200, -90)
	l.z_index = 40
	l.scale = Vector2(0.3, 0.3 * Pixel.STAND)
	main.fx_node.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2(1.15, 1.15 * Pixel.STAND), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2(1.0, Pixel.STAND), 0.1)
	tw.tween_property(l, "position:y", l.position.y - 30, 0.7)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.2)
	tw.tween_callback(l.queue_free)


static func ring(main: Node, pos: Vector2, r0: float, r1: float, color: Color, duration: float, width := 3.0) -> void:
	if _net(main, "ring", [pos, r0, r1, color, duration, width]):
		return
	if _crowded(main, 260):
		return
	var n := FxDraw.new()
	n.kind = "ring"
	n.position = pos
	n.r0 = r0
	n.r1 = r1
	n.color = color
	n.duration = duration
	n.width = width
	n.material = Pixel.mat_add()
	n.z_index = 4
	main.fx_node.add_child(n)


static func lightning(main: Node, pos: Vector2, radius: float) -> void:
	# Настоящий удар с неба в 3D
	var ground: Vector3 = main.to3d(pos, 0.0)
	var sky := ground + Vector3(randf_range(-0.8, 0.8), 7.0, randf_range(-0.8, 0.8))
	main.beam3d(PackedVector3Array([sky, ground]), Color(0.55, 0.75, 1.0), 0.05, 0.3, 0.3)
	ring(main, pos, 6.0, radius * 1.2, Color(0.5, 0.8, 1.0, 0.6), 0.3, 3.0)
	sparks(main, pos, Color(0.6, 0.85, 1.0), 8)
	light_flash(main, pos, Color(0.6, 0.75, 1.0), 1.0, 3.0, 0.25)


static func portal(main: Node, pos: Vector2, color: Color, size := 1.0) -> void:
	if _net(main, "portal", [pos, color, size]):
		return
	if _crowded(main, 300):
		return
	var n := FxDraw.new()
	n.kind = "portal"
	n.position = pos
	n.r1 = 26.0 * size
	n.color = color
	n.duration = 0.45
	n.material = Pixel.mat_add()
	n.z_index = -4
	main.fx_node.add_child(n)


## Аддитивное мягкое свечение (дешёвый «свет» без источника).
static func glow_flash(main: Node, pos: Vector2, color: Color, radius: float, duration: float) -> void:
	if _net(main, "glow_flash", [pos, color, radius, duration]):
		return
	if main.flash_budget <= 0:
		return
	main.flash_budget -= 1
	var s := Sprite2D.new()
	s.texture = Pixel.glow()
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	s.material = Pixel.mat_add()
	s.position = pos
	s.modulate = Color(color, 0.3)
	s.scale = Vector2.ONE * radius * 0.7 / 64.0
	s.z_index = 3
	main.fx_node.add_child(s)
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", 0.0, duration)
	tw.tween_callback(s.queue_free)


## Настоящий источник света на мгновение (освещает всё вокруг, даёт тени).
static func light_flash(main: Node, pos: Vector2, color: Color, energy: float, tex_scale: float, duration: float) -> void:
	if _net(main, "light_flash", [pos, color, energy, tex_scale, duration]):
		return
	if main.fx_lights >= (6 if not _crowded(main, 200) else 2):
		return
	main.fx_lights += 1
	var l := PointLight2D.new()
	l.texture = Pixel.glow()
	l.color = color
	l.energy = minf(energy, 1.5)
	l.texture_scale = tex_scale
	l.position = pos
	main.fx_node.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "energy", 0.0, duration)
	tw.tween_callback(func():
		main.fx_lights -= 1
		l.queue_free())


## Взрыв реакции: два цвета частиц, кольцо, свет, тряска.
static func explosion(main: Node, pos: Vector2, c1: Color, c2: Color, radius: float) -> void:
	# В толпе взрывов может быть десятки за кадр — рисуем только несколько
	if main.explosion_budget <= 0:
		return
	main.explosion_budget -= 1
	burst(main, pos, [Pixel.hdr(c1, 1.2), Color(c2, 0.7), Color(c2, 0.0)],
		int(6 + radius * 0.06), radius * 2.5, 0.45, 4.0)
	ring(main, pos, 6.0, radius, Color(c1, 0.6), 0.3, 4.0)
	glow_flash(main, pos, c1, radius * 0.7, 0.2)
	main.shake(1.5)
	Sound.play("boom", -10.0, 1.3, 0.1, 0.08)


## Цепная молния по точкам — в 3D на высоте груди.
static func chain(main: Node, pts: PackedVector2Array, color: Color) -> void:
	var p3 := PackedVector3Array()
	for p in pts:
		p3.append(main.to3d(p + Vector2(0, 15), 0.5))
	main.beam3d(p3, color, 0.035, 0.3, 0.12)
	Sound.play("zap", -8.0, 1.2, 0.1, 0.05)


## Удар клинком — объёмный серп в 3D на высоте пояса.
static func slash(main: Node, pos: Vector2, angle: float, arc: float, radius: float, color: Color, anchor: Node2D = null) -> void:
	main.slash3d(pos, angle, arc, radius, color, anchor)


## Лазерный луч в 3D: из точки a на высоте ha в точку b на высоте hb.
static func beam(main: Node, a: Vector2, b: Vector2, color: Color, ha := 0.9, hb := 0.4) -> void:
	main.beam3d(PackedVector3Array([main.to3d(a, ha), main.to3d(b + Vector2(0, 15), hb)]), color, 0.025, 0.14)


## Фантомный след героя (для рывка).
static func afterimage(main: Node, pos: Vector2, tex: Texture2D, offset: Vector2, flip: bool, color: Color, k := 1.0) -> void:
	var s := Sprite2D.new()
	s.texture = tex
	s.position = pos
	s.offset = offset
	s.flip_h = flip
	s.scale = Vector2(Pixel.PX, Pixel.PX * Pixel.STAND) * k
	s.material = Pixel.mat_add()
	s.modulate = Pixel.hdr(color, 1.5)
	s.z_index = 2
	main.fx_node.add_child(s)
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", 0.0, 0.35)
	tw.tween_callback(s.queue_free)
