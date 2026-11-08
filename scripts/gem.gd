extends Node2D
## Кристалл опыта (или нано-сердце). Парит, светится, притягивается к герою.

const Pixel := preload("res://scripts/pixel.gd")
const Fx := preload("res://scripts/fx.gd")

var main: Node2D
var player: Node2D
var kind := "xp"
var value := 1

var _attracted := false
var puppet := false
var net_pos := Vector2.ZERO
var _speed := 0.0
var _t := 0.0
var _body: Sprite2D
var _emit: Sprite2D
var _glow: Sprite2D
var _color := Color.WHITE
## Ступень кристалла: 0 — синий, 1 — зелёный, 2 — жёлтый, 3 — красный.
## Несколько одинаковых рядом сливаются в кристалл следующей ступени.
var tier := -1

const TIER_KEYS := ["gem1", "gem3", "gem5", "gem9", "gemx"]
const TIER_COLORS := [Color(0.3, 0.65, 1.0), Color(0.3, 1.0, 0.55), Color(1.0, 0.75, 0.25), Color(1.0, 0.25, 0.3), Color(1.0, 0.45, 0.3)]
var _value_label: Label3D


static func tier_for(v: int) -> int:
	if v >= 15:
		return 3
	if v >= 6:
		return 2
	if v >= 3:
		return 1
	return 0


func _key() -> String:
	if kind == "heal":
		return "heal"
	tier = maxi(tier, tier_for(value))
	return TIER_KEYS[tier]


func _col(key: String) -> Color:
	if key == "heal":
		return Color(1.0, 0.25, 0.4)
	return TIER_COLORS[TIER_KEYS.find(key)]


## Кристалл перенесли и добавили опыта: обновить вид и снова подбросить.
func refresh_look() -> void:
	if _body == null:
		return
	var key := _key()
	var fr := Pixel.frames(key)
	_body.texture = fr["base"][0]
	_emit.texture = fr["emit"][0]
	_color = _col(key)
	_glow.modulate = Color(_color, 0.35)
	_glow.scale = Vector2.ONE * (0.4 + 0.1 * maxi(tier, 0) + (0.25 if tier >= 4 else 0.0))
	_size_k = 1.35 if tier >= 4 else 1.0
	_body.position.y = -20
	var tw := create_tween()
	tw.tween_property(_body, "position:y", -8.0, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


var _size_k := 1.0


## Мега-кристалл впитал кристалл: искры летят к нему, он вздрагивает.
func absorb_fx(from: Vector2) -> void:
	Fx.burst(main, from + Vector2(0, -10), [Pixel.hdr(_color, 2.0), Color(_color, 0.0)], 3, 70.0, 0.25, 2.0)
	_pulse = 0.25
	if _value_label:
		_value_label.text = "+%d" % value


var _pulse := 0.0


func _ready() -> void:
	_t = randf() * TAU
	var key := _key()
	_color = _col(key)
	var fr := Pixel.frames(key)

	var sh := Sprite2D.new()
	sh.texture = Pixel.shadow()
	sh.scale = Vector2(1.6, 1.6)
	sh.z_index = -5
	add_child(sh)
	_glow = Sprite2D.new()
	_glow.texture = Pixel.glow()
	_glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_glow.material = Pixel.mat_add()
	_glow.modulate = Color(_color, 0.35)
	_glow.scale = Vector2.ONE * 0.4
	add_child(_glow)
	_body = Sprite2D.new()
	_body.texture = fr["base"][0]
	_body.scale = Vector2(Pixel.PX, Pixel.PX * Pixel.STAND) * 0.8
	add_child(_body)
	_emit = Sprite2D.new()
	_emit.texture = fr["emit"][0]
	_emit.scale = _body.scale
	_emit.material = Pixel.mat_unshaded()
	_emit.modulate = Pixel.hdr(Color.WHITE, 2.0)
	add_child(_emit)
	main.mirror(_body, self, false)
	main.mirror(_emit, self, true)
	# Появление с подскоком
	_body.position.y = -20
	var tw := create_tween()
	tw.tween_property(_body, "position:y", -8.0, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


var _vis := true
var _ph := randi() % 4


func _process(delta: float) -> void:
	_t += delta
	if puppet:
		position = position.lerp(net_pos, 1.0 - exp(-20.0 * delta))
		_body.position.y = -10.0 + sin(_t * 3.0) * 3.0
		_emit.position = _body.position
		_glow.position = _body.position
		return
	if not _attracted:
		# Оптимизация: лежащий за кадром кристалл проверяем раз в 4 кадра и не анимируем
		if (main._frame + _ph) % 4 == 0:
			_vis = main._on_view(position)
		elif not _vis:
			return
		for p in main.players:
			if not p._dead and p.position.distance_to(position) < p.magnet:
				_attracted = true
				player = p
				break
	elif player._dead:
		player = main.nearest_player(position)
	var to_player: Vector2 = player.position - position
	var dist := to_player.length()
	if _attracted:
		_speed = minf(_speed + 1500.0 * delta, 950.0)
		position += to_player.normalized() * _speed * delta
	if dist < player.radius + 8.0:
		if kind == "heal":
			player.heal(25.0)
		else:
			player.add_xp(value)  # опыт у каждого героя свой
		Fx.burst(main, position + Vector2(0, -10), [Pixel.hdr(_color, 2.0), Color(_color, 0.0)], 4, 80.0, 0.3, 2.5)
		queue_free()
		return
	if not _attracted:
		var y := -10.0 + sin(_t * 3.0) * 3.0
		_body.position.y = y
	_emit.position = _body.position
	_glow.position = _body.position
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	_glow.modulate.a = 0.25 + 0.2 * pulse
	_pulse = maxf(0.0, _pulse - delta)
	var pk := _size_k * (1.0 + _pulse * 0.8)
	_body.scale = Vector2(Pixel.PX * 0.8 * (0.85 + 0.15 * cos(_t * 2.5)), Pixel.PX * Pixel.STAND * 0.8) * pk
	_emit.scale = _body.scale
