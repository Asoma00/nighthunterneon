extends MeshInstance3D
## Объёмный удар клинком: светящаяся лента-серп на высоте пояса.
## Прорастает по дуге, слегка расширяется и гаснет. Следует за героем.

var main: Node
var center := Vector2.ZERO  # точка в 2D-мире
var anchor: Node2D           # если задан — удар следует за ним
var angle := 0.0
var arc := PI
var radius := 1.0            # метры
var color := Color(1.0, 0.3, 0.6)
var duration := 0.24
var _t := 0.0
var _im := ImmediateMesh.new()


func _ready() -> void:
	mesh = _im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rebuild()


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
		return
	_rebuild()


func _rebuild() -> void:
	var c2 := center
	if anchor and is_instance_valid(anchor):
		c2 = anchor.position
	position = main.to3d(c2, 0.0)
	var k := _t / duration
	var fade := 1.0 - k
	var grow := minf(1.0, k * 3.5)
	var sweep := arc * (0.35 + 0.65 * grow)
	var r := radius * (0.85 + 0.25 * k)
	var a0 := angle - sweep / 2.0
	var seg := 24
	_im.clear_surfaces()
	# Широкая полупрозрачная лента + яркая кромка
	for layer in 2:
		var y0 := 0.25 if layer == 0 else 0.62
		var y1 := 0.95 if layer == 0 else 0.7
		var lean := 0.25 if layer == 0 else 0.3
		var base_a := 0.45 if layer == 0 else 0.9
		var col := color if layer == 0 else color.lerp(Color.WHITE, 0.45)
		_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in seg + 1:
			var f := float(i) / seg
			var a := a0 + sweep * f
			var dir := Vector3(cos(a), 0.0, sin(a))
			# Хвост дуги прозрачный, передний край яркий
			var alpha := base_a * fade * pow(f, 1.5)
			var cc := Color(col.r * 1.25, col.g * 1.1, col.b * 1.25, alpha)
			_im.surface_set_color(cc)
			_im.surface_add_vertex(dir * r + Vector3(0, y0, 0))
			_im.surface_set_color(Color(cc, alpha * 0.6))
			_im.surface_add_vertex(dir * (r + lean) + Vector3(0, y1, 0))
		_im.surface_end()
