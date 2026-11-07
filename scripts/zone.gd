extends Node2D
## Зона на земле: лужа кислоты, ледяной туман, смерч. Тикает уроном и статусом,
## может двигаться и затягивать врагов. Смерч дополнительно рисуется в 3D.

const Pixel := preload("res://scripts/pixel.gd")
const Fx := preload("res://scripts/fx.gd")

var main: Node2D
var owner_pl: Node2D
var puppet := false
var net_pos := Vector2.ZERO
var radius := 60.0
var damage := 5.0
var tick := 0.5
var duration := 3.0
var status := "burn"
var color := Color(0.6, 1.0, 0.3)
var velocity := Vector2.ZERO
var pull := 0.0
var tornado := false
var source := ""
var flask := false     # ядовитая лужа колбы — рисуется ярче
var cloud := false     # облако пара / яда
var _light: PointLight2D
var _blob := PackedFloat32Array()

var _t := 0.0
var _tick_t := 0.0
var _spiral_t := 0.0
var _r0 := 0.0
var _boost_cd := 0.0


func _ready() -> void:
	_setup_look()
	if puppet:
		material = Pixel.mat_add()
		z_index = 1
		_r0 = radius
		return
	if owner_pl == null:
		owner_pl = main.attacker if main.attacker != null else main.player
	material = Pixel.mat_add()
	z_index = 1
	_r0 = radius


## Подпитка полем другого оружия: молот расплёскивает, импульс продлевает.
func energize(kind: String) -> void:
	if _boost_cd > 0.0:
		return
	_boost_cd = 0.5
	match kind:
		"quake":
			radius = minf(radius * 1.25, _r0 * 2.0)
			Fx.ring(main, position, radius * 0.6, radius, Color(color, 0.6), 0.3, 3.0)
		"pulse":
			_t = maxf(0.0, _t - 1.5)
			radius = minf(radius * 1.1, _r0 * 2.0)


func _process(delta: float) -> void:
	# Клиент: свой снаряд/зона — локальная симуляция, эффекты показываются и у хоста
	var loc: bool = not puppet and main.net_mode == "client"
	if loc:
		Net.local = true
	_process_body(delta)
	if loc:
		Net.local = false


func _process_body(delta: float) -> void:
	_t += delta
	if puppet:
		position = position.lerp(net_pos, 1.0 - exp(-15.0 * delta))
		queue_redraw()
		return
	if _t >= duration or main.game_over:
		queue_free()
		return
	position += velocity * delta
	_boost_cd = maxf(0.0, _boost_cd - delta)
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t = tick
		for e in main.get_enemies():
			if not e.can_be_hit():
				continue
			var d: float = e.position.distance_to(position)
			if d < radius + e.radius:
				main.attacker = owner_pl
				owner_pl.set_source(source)
				# Электролит: кислота проводит ток врага под током
				if source == "flask" and owner_pl.catalyzed("flask", e):
					main.beam3d(PackedVector3Array([main.to3d(position, 0.05), main.to3d(e.position, 0.4)]), Color(0.5, 0.85, 1.0), 0.02, 0.12, 0.08)
					e.hit(damage * 0.8, position, 0.0)
					if randf() < 0.1:
						owner_pl.combo("flask", e.position)
				e.hit(damage, position, 0.0 if pull > 0.0 else 30.0, status)
	if pull > 0.0:
		for e in main.get_enemies():
			if e.dead or e.is_boss:
				continue
			var to: Vector2 = position - e.position
			var d := to.length()
			if d < radius * 1.8 and d > 5.0:
				e.position += to / d * pull * delta
	if tornado:
		_spiral_t -= delta
		if _spiral_t <= 0.0:
			_spiral_t = 0.07
			_spiral3d()
	if randf() < 0.2:
		var p := position + Vector2.RIGHT.rotated(randf() * TAU) * randf() * radius
		Fx.burst(main, p, [Color(color, 0.8), Color(color, 0.0)], 1, 30.0, 0.6, 3.0, true, Vector2(0, -40))
	queue_redraw()


func _spiral3d() -> void:
	# Смерч: спираль из дрожащих разрядов от земли до неба
	var pts := PackedVector3Array()
	var base: Vector3 = main.to3d(position, 0.0)
	var a0 := _t * 9.0
	for i in 14:
		var h := i * 0.2
		var r := (0.25 + h * 0.35) * radius / 90.0
		var a := a0 + i * 0.9
		pts.append(base + Vector3(cos(a) * r, h, sin(a) * r))
	main.beam3d(pts, color, 0.04, 0.16, 0.05)


func _setup_look() -> void:
	# Неровный край лужи
	var rng := RandomNumberGenerator.new()
	rng.seed = get_instance_id()
	for i in 20:
		_blob.append(rng.randf_range(0.82, 1.08))
	if flask or cloud:
		_light = PointLight2D.new()
		_light.texture = Pixel.glow()
		_light.color = color
		_light.energy = 0.9 if flask else 0.5
		_light.texture_scale = maxf(1.5, radius / 40.0)
		add_child(_light)


func _draw() -> void:
	var k := _t / duration
	var fade := minf(1.0, (1.0 - k) * 4.0) * minf(1.0, _t * 6.0)
	if flask:
		_draw_pool(fade)
		return
	if cloud:
		_draw_cloud(fade)
		return
	var pulse := 0.85 + 0.15 * sin(_t * 8.0)
	draw_circle(Vector2.ZERO, radius * pulse, Color(color, 0.16 * fade))
	draw_arc(Vector2.ZERO, radius * pulse, 0.0, TAU, 36, Color(color, 0.55 * fade), 3.0)
	for i in 5:
		var a := _t * (1.5 + i * 0.3) + i * 1.3
		var p := Vector2(cos(a), sin(a)) * radius * (0.3 + 0.12 * i)
		draw_circle(p, 4.0 + 2.0 * sin(_t * 6.0 + i), Color(color.lightened(0.3), 0.5 * fade))


## Ядовитая лужа: неровное пятно, яркий край, пузыри.
func _draw_pool(fade: float) -> void:
	var pts := PackedVector2Array()
	var n := _blob.size()
	for i in n:
		var a := TAU * i / n
		var r := radius * _blob[i] * (0.97 + 0.03 * sin(_t * 3.0 + i))
		pts.append(Vector2(cos(a), sin(a)) * r)
	var deep := Color(color.r * 0.5, color.g * 0.8, color.b * 0.3)
	draw_colored_polygon(pts, Color(deep, 0.5 * fade))
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(p * 0.62)
	draw_colored_polygon(inner, Color(color, 0.32 * fade))
	pts.append(pts[0])
	draw_polyline(pts, Color(color.lightened(0.35), 0.95 * fade), 4.0)
	draw_polyline(pts, Color(color, 0.35 * fade), 10.0)
	# Пузыри: растут и лопаются
	for i in 9:
		var ph := fmod(_t * (0.7 + 0.11 * i) + i * 0.37, 1.0)
		var a := i * 2.39996
		var p := Vector2(cos(a), sin(a)) * radius * (0.15 + 0.07 * i)
		var br := 2.0 + ph * 6.0
		draw_arc(p, br, 0.0, TAU, 12, Color(color.lightened(0.5), (1.0 - ph) * 0.9 * fade), 2.0)
	if _light:
		_light.energy = (0.8 + 0.2 * sin(_t * 5.0)) * fade


## Облако пара или яда: клубы, медленно расползаются.
func _draw_cloud(fade: float) -> void:
	for i in 10:
		var a := i * 2.39996 + _t * (0.3 + 0.05 * i)
		var d := radius * (0.2 + 0.07 * i) * (0.8 + 0.2 * minf(1.0, _t * 2.0))
		var p := Vector2(cos(a), sin(a)) * d
		draw_circle(p, radius * 0.35, Color(color, 0.12 * fade))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(color, 0.3 * fade), 2.0)
	if _light:
		_light.energy = 0.5 * fade
