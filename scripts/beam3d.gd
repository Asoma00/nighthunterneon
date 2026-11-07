extends MeshInstance3D
## Светящаяся линия в 3D (луч дрона, цепной разряд, удар молнии).
## Лента всегда повёрнута к камере; может «дрожать» зигзагом, гаснет за duration.

var camera: Camera3D
var points := PackedVector3Array()
var color := Color(0.4, 1.0, 0.5)
var width := 0.06
var duration := 0.15
var jitter := 0.0
var _t := 0.0
var _im := ImmediateMesh.new()
var _shape := PackedVector3Array()


func _ready() -> void:
	mesh = _im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_make_shape()
	_rebuild()


func _make_shape() -> void:
	_shape = PackedVector3Array()
	if jitter <= 0.0:
		_shape = points
		return
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var segs := maxi(2, int(a.distance_to(b) / 0.35))
		for s in segs:
			var p := a.lerp(b, float(s) / segs)
			if s > 0:
				p += Vector3(randf_range(-jitter, jitter), randf_range(-jitter, jitter) * 0.5, randf_range(-jitter, jitter))
			_shape.append(p)
	_shape.append(points[points.size() - 1])


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
		return
	if jitter > 0.0 and randf() < 0.35:
		_make_shape()
	_rebuild()


func _strip(w: float, col: Color) -> void:
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var cam_pos := camera.global_position if camera else Vector3(0, 10, 10)
	for i in _shape.size():
		var p := _shape[i]
		var dir := (_shape[mini(i + 1, _shape.size() - 1)] - _shape[maxi(i - 1, 0)]).normalized()
		var side := dir.cross((cam_pos - p).normalized()).normalized() * w
		_im.surface_set_color(col)
		_im.surface_add_vertex(p - side)
		_im.surface_add_vertex(p + side)
	_im.surface_end()


func _rebuild() -> void:
	_im.clear_surfaces()
	if _shape.size() < 2:
		return
	var a := 1.0 - _t / duration
	_strip(width * 3.0, Color(color.r, color.g, color.b, 0.35 * a))
	_strip(width, Color(1.0, 1.0, 1.0, a).lerp(Color(color, a), 0.3))
