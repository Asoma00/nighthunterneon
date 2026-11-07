extends Node2D
## Сундук: выпадает из элиты и боссов. Подойдите — откроется окно с наградой.

const Pixel := preload("res://scripts/pixel.gd")
const Fx := preload("res://scripts/fx.gd")

var main: Node2D
var player: Node2D
var _t := 0.0
var _body: Sprite2D
var _emit: Sprite2D
var _beam: Sprite2D
var _opened := false
var puppet := false


func _ready() -> void:
	add_to_group("chests")
	var fr := Pixel.frames("chest")
	var sh := Sprite2D.new()
	sh.texture = Pixel.shadow()
	sh.scale = Vector2(4.0, 3.0)
	sh.z_index = -5
	add_child(sh)
	_beam = Sprite2D.new()
	_beam.texture = Pixel.glow()
	_beam.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_beam.material = Pixel.mat_add()
	_beam.modulate = Color(1.0, 0.75, 0.3, 0.35)
	_beam.scale = Vector2(0.5, 3.0)
	_beam.position = Vector2(0, -120)
	add_child(_beam)
	_body = Sprite2D.new()
	_body.texture = fr["base"][0]
	_body.scale = Vector2(Pixel.PX, Pixel.PX * Pixel.STAND)
	_body.offset = Vector2(0, -7)
	add_child(_body)
	_emit = Sprite2D.new()
	_emit.texture = fr["emit"][0]
	_emit.scale = _body.scale
	_emit.offset = _body.offset
	_emit.material = Pixel.mat_unshaded()
	_emit.modulate = Pixel.hdr(Color.WHITE, 2.0)
	add_child(_emit)
	var light := PointLight2D.new()
	light.texture = Pixel.glow()
	light.color = Color(1.0, 0.75, 0.3)
	light.energy = 1.2
	light.texture_scale = 2.0
	light.position = Vector2(0, -20)
	add_child(light)
	main.mirror(_body, self, false)
	main.mirror(_emit, self, true)
	main.mirror_light(light, self, 0.8)
	# Падение с неба
	_body.position.y = -200
	_emit.position.y = -200
	var tw := create_tween()
	tw.tween_property(_body, "position:y", 0.0, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_emit, "position:y", 0.0, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_t += delta
	_beam.modulate.a = 0.25 + 0.15 * sin(_t * 3.0)
	if puppet:
		return
	if _opened or _t < 0.6:
		return
	if randf() < 0.1:
		Fx.burst(main, position + Vector2(randf_range(-20, 20), -30), [Pixel.hdr(Color(1.0, 0.85, 0.4), 2.0), Color(1, 0.6, 0.2, 0)], 1, 30.0, 0.8, 3.0, true, Vector2(0, -60))
	var opener: Node2D = null
	for p in main.players:
		if not p._dead and position.distance_to(p.position) < 50.0:
			opener = p
	if opener != null:
		_opened = true
		remove_from_group("chests")
		var fr := Pixel.frames("chest")
		_body.texture = fr["base"][1]
		_emit.texture = fr["emit"][1]
		Fx.burst(main, position + Vector2(0, -20), [Pixel.hdr(Color(1.0, 0.9, 0.5), 2.5), Pixel.hdr(Color(1.0, 0.4, 0.8), 1.5), Color(0.4, 0.2, 1.0, 0)], 40, 300.0, 1.0, 4.0, true, Vector2(0, 100), Vector2.UP, 60.0)
		Fx.ring(main, position, 10.0, 140.0, Pixel.hdr(Color(1.0, 0.8, 0.3), 2.0), 0.5, 5.0)
		main.open_chest(opener)
		var tw := create_tween()
		tw.tween_interval(1.0)
		tw.tween_property(self, "modulate:a", 0.0, 0.5)
		tw.tween_callback(queue_free)
