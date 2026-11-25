extends Node2D
## Снаряд босса: светящаяся сфера, может наводиться на героя.

const Pixel := preload("res://scripts/pixel.gd")
const Fx := preload("res://scripts/fx.gd")
const Art := preload("res://scripts/projectile_art.gd")

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
var _volume: MeshInstance3D


func _ready() -> void:
	_volume = Art.energy_sphere()
	var mat := _volume.material_override as StandardMaterial3D
	mat.albedo_color = Pixel.hdr(color.lerp(Color.WHITE, 0.30), 1.5)
	main._bill_root.add_child(_volume)
	var glow := Sprite3D.new()
	glow.texture = Pixel.glow()
	glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	glow.pixel_size = 4.4 / glow.texture.get_width()
	glow.modulate = Color(color, 0.45)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_volume.add_child(glow)
	_update_look()


func _process(delta: float) -> void:
	_t += delta
	if puppet:
		net_pos += velocity * delta
		position = position.lerp(net_pos, 1.0 - exp(-20.0 * delta))
		_update_look()
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
	_update_look()


func _update_look() -> void:
	_volume.position = main.to3d(position, 0.6)
	_volume.scale = Vector3.ONE * radius * 0.02 * (1.0 + 0.2 * sin(_t * 20.0))


func _exit_tree() -> void:
	if is_instance_valid(_volume):
		_volume.queue_free()
