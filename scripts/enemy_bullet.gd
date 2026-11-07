extends Node2D
## Снаряд босса: светящаяся сфера, может наводиться на героя.

const Pixel := preload("res://scripts/pixel.gd")
const Fx := preload("res://scripts/fx.gd")

var main: Node2D
var player: Node2D
var velocity := Vector2.ZERO
var damage := 10.0
var color := Color(0.7, 0.4, 1.0)
var homing := false
var radius := 9.0
var life := 6.0
var _t := 0.0
var puppet := false
var net_pos := Vector2.ZERO


func _ready() -> void:
	material = Pixel.mat_add()
	z_index = 6


func _process(delta: float) -> void:
	_t += delta
	if puppet:
		net_pos += velocity * delta
		position = position.lerp(net_pos, 1.0 - exp(-20.0 * delta))
		queue_redraw()
		return
	life -= delta
	if homing and _t < 2.5:
		var want: Vector2 = (player.position + Vector2(0, -30) - position).normalized() * velocity.length()
		velocity = velocity.lerp(want, delta * 1.6)
	position += velocity * delta
	if life <= 0.0 or main.game_over:
		queue_free()
		return
	for p in main.players:
		if p._dead:
			continue
		var target: Vector2 = p.position + Vector2(0, -30)
		if position.distance_squared_to(target) < pow(radius + 14.0, 2):
			p.take_damage(damage)
			Fx.sparks(main, position, color, 8)
			queue_free()
			return
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2(0, 0), 0.0, Vector2(1.0, Pixel.STAND))
	var pulse := 1.0 + 0.2 * sin(_t * 20.0)
	draw_circle(Vector2.ZERO, radius * 2.2 * pulse, Color(color, 0.18))
	draw_circle(Vector2.ZERO, radius * pulse, Pixel.hdr(color, 1.6))
	draw_circle(Vector2.ZERO, radius * 0.5, Pixel.hdr(Color.WHITE, 1.8))
