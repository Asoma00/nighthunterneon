extends Node3D
## Солнечный луч в 3D: зарядка у руки героя, затем толстый луч из трёх слоёв
## с двойной спиралью, бегущими солнечными кольцами, вспышками на концах
## и тлеющей полосой на земле.

const Pixel := preload("res://scripts/pixel.gd")

var main: Node2D
var anchor: Node2D
var dir := Vector2.RIGHT
var length_px := 500.0
var width_px := 40.0
var color := Color(1.0, 0.8, 0.35)

const CHARGE := 0.14
const FIRE := 0.42

var _t := 0.0
var _im := ImmediateMesh.new()
var _mesh: MeshInstance3D
var _flare_a: MeshInstance3D
var _flare_b: MeshInstance3D
var _scorch: Node2D
var _scorch_from := Vector2.ZERO
var _scorch_to := Vector2.ZERO
var _scorch_t := 0.0
var _motes: Array = []


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = m
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_flare_a = _flare()
	_flare_b = _flare()
	for i in 10:
		_motes.append([Vector3(randf_range(-1, 1), randf_range(-0.6, 1), randf_range(-1, 1)).normalized(), randf_range(0.0, 0.5)])


func _flare() -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var mi := MeshInstance3D.new()
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = Pixel.glow()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _process(delta: float) -> void:
	_t += delta
	if _t >= CHARGE + FIRE and _scorch_t <= 0.0:
		queue_free()
		return
	_scorch_t = maxf(0.0, _scorch_t - delta)
	_rebuild()


func _strip(pts: PackedVector3Array, w: float, col: Color, cam: Vector3) -> void:
	if pts.size() < 2:
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in pts.size():
		var p := pts[i]
		var d := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := d.cross((cam - p).normalized()).normalized() * w
		_im.surface_set_color(col)
		_im.surface_add_vertex(p - side)
		_im.surface_add_vertex(p + side)
	_im.surface_end()


func _set_flare(f: MeshInstance3D, p: Vector3, size: float, col: Color) -> void:
	f.position = p
	f.scale = Vector3.ONE * maxf(size, 0.001)
	(f.material_override as StandardMaterial3D).albedo_color = col


func _rebuild() -> void:
	_im.clear_surfaces()
	if not is_instance_valid(anchor) or main._cam3d == null:
		_flare_a.visible = false
		_flare_b.visible = false
		return
	var cam: Vector3 = main._cam3d.global_position
	var a2: Vector2 = anchor.position + dir * 22.0
	var b2: Vector2 = anchor.position + dir * length_px
	var a: Vector3 = main.to3d(a2, 0.85)
	var b: Vector3 = main.to3d(b2, 0.55)
	var axis := (b - a).normalized()
	var up := Vector3.UP
	var side := axis.cross(up).normalized()
	var up2 := side.cross(axis).normalized()
	var W := width_px * 0.01 * 0.5
	var hot := color.lerp(Color.WHITE, 0.55)

	if _t < CHARGE:
		# Зарядка: искры сходятся к руке, тонкая направляющая линия
		var k := _t / CHARGE
		for m in _motes:
			var d: Vector3 = m[0]
			var r := (1.0 - fmod(k + m[1], 1.0)) * 0.5
			var p := a + d * r
			_strip(PackedVector3Array([p, p - d * 0.08]), 0.012, Color(hot, 0.8), cam)
		var flick := 0.25 + 0.25 * sin(_t * 90.0)
		_strip(PackedVector3Array([a, b]), 0.006 + 0.01 * k, Color(color, flick * k), cam)
		_set_flare(_flare_a, a, 0.25 + 0.6 * k, Color(hot, 0.5 + 0.4 * k))
		_flare_b.visible = false
		return

	var ft := (_t - CHARGE) / FIRE
	if ft >= 1.0:
		_flare_a.visible = false
		_flare_b.visible = false
		_draw_scorch_only()
		return
	if _scorch == null:
		_start_scorch(a2, b2)
	_scorch_from = a2
	_scorch_to = b2
	_flare_b.visible = true
	# Огибающая: резкий выстрел, лёгкий пульс, плавное угасание
	var env := minf(1.0, ft / 0.08) * (1.0 - ft * ft) * (1.0 + 0.12 * sin(_t * 60.0))
	var hw := W * env
	var line := PackedVector3Array([a, b])
	_strip(line, hw * 2.8, Color(color.r, color.g * 0.8, color.b * 0.6, 0.12 * env), cam)
	_strip(line, hw * 1.2, Color(color, 0.45 * env), cam)
	_strip(line, hw * 0.45, Color(1.0, 1.0, 0.95, 0.95 * env), cam)
	# Двойная спираль вокруг луча
	var length := a.distance_to(b)
	var turns := length * 1.6
	for strand in 2:
		var pts := PackedVector3Array()
		var n := 48
		for i in n + 1:
			var u := float(i) / n
			var ang := u * turns * TAU - _t * 22.0 + strand * PI
			var rr := hw * 1.25 * (0.6 + 0.4 * sin(u * PI))
			pts.append(a.lerp(b, u) + (side * cos(ang) + up2 * sin(ang)) * rr)
		_strip(pts, 0.011, Color(hot, 0.7 * env), cam)
	# Солнечные кольца бегут от героя к цели
	for i in 5:
		var u := fmod(ft * 2.2 + i / 5.0, 1.0)
		var c := a.lerp(b, u)
		var rr := hw * (1.5 + 0.8 * u)
		var pts := PackedVector3Array()
		for j in 17:
			var ang := TAU * j / 16.0
			pts.append(c + (side * cos(ang) + up2 * sin(ang)) * rr)
		var fade := sin(u * PI)
		_strip(pts, 0.009, Color(color, 0.6 * fade * env), cam)
	# Лучи-«блики» на конце
	var e := b
	for k in 4:
		var ang := _t * 3.0 + k * PI / 4.0
		var d := (side * cos(ang) + up2 * sin(ang)) * hw * 4.0
		_strip(PackedVector3Array([e - d, e + d]), 0.008, Color(hot, 0.45 * env), cam)
	_set_flare(_flare_a, a, hw * 7.0, Color(hot, 0.85 * env))
	_set_flare(_flare_b, b, hw * 9.0 * (0.9 + 0.2 * sin(_t * 40.0)), Color(color, 0.9 * env))


func _start_scorch(from: Vector2, to: Vector2) -> void:
	_scorch_from = from
	_scorch_to = to
	_scorch_t = 0.9
	_scorch = preload("res://scripts/drawer.gd").new()
	_scorch.material = Pixel.mat_add()
	_scorch.z_index = -11
	_scorch.draw_fn = _draw_scorch
	main.fx_node.add_child(_scorch)
	var tw := _scorch.create_tween()
	tw.tween_interval(1.2)
	tw.tween_callback(_scorch.queue_free)


func _draw_scorch_only() -> void:
	pass


func _draw_scorch(c: Node2D) -> void:
	var k := clampf(_scorch_t / 0.9, 0.0, 1.0)
	if k <= 0.0:
		return
	var w := width_px
	c.draw_line(_scorch_from, _scorch_to, Color(color.r, color.g * 0.6, 0.1, 0.18 * k), w * 1.1)
	c.draw_line(_scorch_from, _scorch_to, Color(color, 0.35 * k), w * 0.35)
	# Тлеющие угольки вдоль полосы
	var n := int(_scorch_from.distance_to(_scorch_to) / 30.0)
	var perp := (_scorch_to - _scorch_from).normalized().orthogonal()
	for i in n:
		var u := (i + 0.5) / n
		var p := _scorch_from.lerp(_scorch_to, u) + perp * sin(i * 12.9898) * w * 0.4
		c.draw_circle(p, 2.5 + 1.5 * sin(i * 3.1 + k * 9.0), Color(1.0, 0.55, 0.15, 0.6 * k))
