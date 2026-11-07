extends Node2D
## Рисуемые эффекты: расходящееся кольцо, молния, портал появления.

var kind := "ring"
var r0 := 4.0
var r1 := 40.0
var color := Color.WHITE
var duration := 0.3
var width := 3.0
var points := PackedVector2Array()
var _t := 0.0
var _bolt := PackedVector2Array()
var _branches: Array = []
var _chain_cache := PackedVector2Array()


func _ready() -> void:
	if kind == "lightning":
		_bolt = _jagged(Vector2(randf_range(-30, 30), -380), Vector2.ZERO, 12, 18.0)
		for i in 2:
			var from_idx := randi_range(3, _bolt.size() - 4)
			var start := _bolt[from_idx]
			var end := start + Vector2(randf_range(-90, 90), randf_range(40, 110))
			_branches.append(_jagged(start, end, 5, 14.0))


func _jagged(a: Vector2, b: Vector2, segments: int, jitter: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments + 1:
		var t := float(i) / segments
		var p := a.lerp(b, t)
		if i > 0 and i < segments:
			p += Vector2(randf_range(-jitter, jitter), randf_range(-jitter * 0.3, jitter * 0.3))
		pts.append(p)
	return pts


func _process(delta: float) -> void:
	_t += delta
	if kind == "chain" and randf() < 0.4:
		_chain_cache = PackedVector2Array()
	if _t >= duration:
		queue_free()
		return
	# Молния «мерцает» — перестраиваем её пару раз
	if kind == "lightning" and randf() < 0.25:
		_bolt = _jagged(_bolt[0], Vector2.ZERO, 14, 22.0)
	queue_redraw()


func _draw() -> void:
	var k := _t / duration
	match kind:
		"ring":
			var r := lerpf(r0, r1, 1.0 - pow(1.0 - k, 3.0))
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(color, 1.0 - k), maxf(1.0, width * (1.0 - k)))
		"lightning":
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 1.45))
			var a := 1.0 - k
			var glow_c := Color(color.r, color.g, color.b * 1.2, a * 0.35)
			var core := Color(1.1, 1.1, 1.3, a)
			draw_polyline(_bolt, glow_c, 12.0)
			draw_polyline(_bolt, core, 3.0)
			for br in _branches:
				draw_polyline(br, Color(glow_c, a * 0.35), 7.0)
				draw_polyline(br, Color(core, a * 0.8), 2.0)
			draw_circle(Vector2.ZERO, r1 * (0.5 + k * 0.5), Color(color, a * 0.12))
		"chain":
			if _chain_cache.is_empty():
				for i in range(points.size() - 1):
					var seg := _jagged(points[i], points[i + 1], 6, 10.0)
					_chain_cache.append_array(seg)
			var a := 1.0 - k
			draw_polyline(_chain_cache, Color(color, a * 0.3), 7.0)
			draw_polyline(_chain_cache, Color(1.1, 1.1, 1.3, a), 2.0)
		"beam":
			var a := 1.0 - k
			draw_line(points[0], points[1], Color(color, a * 0.45), 8.0)
			draw_line(points[0], points[1], Pixel_hdr(color, 1.1, a), 2.0)
			draw_circle(points[1], 8.0 * a, Color(color, a * 0.6))
		"slash":
			# Серп удара: несколько дуг, от яркой к прозрачной
			var a := 1.0 - k
			var sweep := r0 * (0.4 + 0.6 * minf(1.0, k * 3.0))
			for i in 4:
				var rr := r1 * (0.55 + i * 0.13)
				draw_arc(Vector2.ZERO, rr, -sweep / 2.0, sweep / 2.0, 24,
					Color(color.r, color.g, color.b, a * (0.15 + i * 0.12)), 10.0 - i * 2.0)
			draw_arc(Vector2.ZERO, r1 * 0.95, -sweep / 2.0, sweep / 2.0, 24, Color(1.1, 1.1, 1.1, a * 0.8), 2.0)
		"portal":
			var open := sin(k * PI)
			var rx := r1 * open
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
			draw_circle(Vector2.ZERO, rx, Color(color, 0.25 * open))
			draw_arc(Vector2.ZERO, rx, 0.0, TAU, 32, Color(color, open * 0.7), 2.0)
			draw_arc(Vector2.ZERO, rx * 0.6, _t * 8.0, _t * 8.0 + PI, 16, Color(color, open * 0.8), 2.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func Pixel_hdr(c: Color, k: float, a: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, a)
