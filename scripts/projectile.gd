extends Node2D
## Снаряд героя: плазменная сфера, ледяной осколок или волна клинка.
## Синергия: искра, пролетевшая сквозь Рунный круг, загорается и поджигает врагов.

const Pixel := preload("res://scripts/pixel.gd")
const Fx := preload("res://scripts/fx.gd")
const Art := preload("res://scripts/projectile_art.gd")

var main: Node2D
var owner_pl: Node2D   # чей снаряд (кооператив)
var puppet := false
var net_pos := Vector2.ZERO
var velocity := Vector2.ZERO
var damage := 10.0
var pierce := 1
var radius := 7.0
var life := 1.6
var status := "shock"
var color := Color(0.3, 0.85, 1.0)
var homing := false
var explode := 0.0
var style := "orb"  # orb | shard | wave | arrow | spirit | ball | flask | shuriken
var art_key := ""
var can_ignite := true
var source := ""
var boomerang := false
var zap_radius := 0.0
var zap_damage := 0.0
var zap_chain := false
var pool := {}  # для колбы: параметры лужи
var _zap_t := 0.0
var _returning := false
var _life0 := 0.0

var status2 := ""      # стихия, подхваченная из чужого поля
var no_rebound := false
var _infuse_t := 0.0
var _zap_r0 := 0.0
var _split_cd := 0.0
var _hot := 0.0        # шар: вспышка после перезарядки

# Шаровая молния: ядро, кольца, дуги, свет на земле
var _ball_core: MeshInstance3D
var _ball_im := ImmediateMesh.new()
var _ball_fx: MeshInstance3D
var _arcs: Array = []   # [точки, время жизни]
var _arc_t := 0.0
var _ball_light: PointLight2D
var _ground: Node2D

var _hit_ids := {}
var _trail: Line2D
var _core: Sprite2D
var _glow: Sprite2D
var _t := 0.0
var _ignited := false

# 3D-изображение: сфера/осколок летит на высоте груди, за ней светящийся шлейф
var _v3: Node3D
var _core3: MeshInstance3D
var _glow3: MeshInstance3D
var _trail3: MeshInstance3D
var _trail_im := ImmediateMesh.new()
var _trail_pts: Array[Vector3] = []
var _height := 0.6
var _spirit_phase := 0.0
var _spirit_near_target := false


func _ready() -> void:
	if owner_pl == null:
		owner_pl = main.attacker if main.attacker != null else main.player
	_trail = Line2D.new()
	_trail.top_level = true
	_trail.width = 9.0 if style != "wave" else 26.0
	var wc := Curve.new()
	wc.add_point(Vector2(0, 0))
	wc.add_point(Vector2(1, 1))
	_trail.width_curve = wc
	_trail.material = Pixel.mat_add()
	_trail.z_index = 5
	add_child(_trail)

	_glow = Sprite2D.new()
	_glow.texture = Pixel.glow()
	_glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_glow.material = Pixel.mat_add()
	_glow.scale = Vector2(1.0, Pixel.STAND) * (0.45 if style == "orb" else 0.3)
	add_child(_glow)

	_life0 = life
	_core = Sprite2D.new()
	art_key = Art.select(style)
	if style == "spirit":
		_spirit_phase = float(get_instance_id() % 13) * 0.31
	if style not in ["ball", "wave"]:
		_core.texture = Art.texture(art_key)
	_core.material = Pixel.mat_unshaded()
	_core.scale = Vector2(Pixel.PX, Pixel.PX * Pixel.STAND) * 0.9
	add_child(_core)
	# 2D-слои остаются только как источник данных — на полу их не видно
	for n in [_trail, _glow, _core]:
		n.visibility_layer = 2
	if style not in ["ball", "flask"] and not puppet:
		velocity *= owner_pl.proj_speed
	if not puppet and owner_pl.evolved.has(source):
		color = owner_pl.evo_tint(source, color)
	_zap_r0 = zap_radius
	_build_3d()
	if style == "ball":
		_build_ball()
	_recolor()


func _billboard_mat(t: Texture2D, additive: bool, nearest: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = t
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if nearest else BaseMaterial3D.TEXTURE_FILTER_LINEAR
	return m


func _build_3d() -> void:
	_height = {"orb": 0.6, "shard": 0.45, "wave": 0.5, "arrow": 0.55, "spirit": 0.7, "ball": 0.6, "shuriken": 0.5, "flask": 0.6}.get(style, 0.6)
	_v3 = Node3D.new()
	main._bill_root.add_child(_v3)
	_glow3 = MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = Vector2(1.1, 1.1) if style == "ball" else (Vector2(0.55, 0.55) if style in ["orb", "spirit"] else Vector2(0.35, 0.35))
	_glow3.mesh = gq
	_glow3.material_override = _billboard_mat(Pixel.glow(), true, false)
	_v3.add_child(_glow3)
	if _core.texture != null:
		_core3 = Art.volume_instance(art_key, _core.texture)
		_v3.add_child(_core3)
	# При толпе снарядов хвосты не рисуем (полёт и урон не меняются)
	if main.projectiles_node.get_child_count() > 140:
		return
	_trail3 = MeshInstance3D.new()
	_trail3.mesh = _trail_im
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.vertex_color_use_as_albedo = true
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail3.material_override = tm
	_trail3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main._bill_root.add_child(_trail3)


func _update_3d() -> void:
	var h := _height
	var art_pos := position
	if style == "flask":
		h = _height + sin(clampf(1.0 - life / maxf(_life0, 0.01), 0.0, 1.0) * PI) * 1.4
	elif style == "spirit":
		var phase := _t * 7.0 + _spirit_phase
		h += sin(phase) * 0.13 + sin(phase * 0.57) * 0.05
		art_pos += velocity.normalized().orthogonal() * sin(phase * 0.76) * 4.0
		Art.update_volume(_core3, "spirit", Art.SPIRIT_FRAMES[Art.spirit_pose(_t, _spirit_phase, _spirit_near_target)])
		_glow3.scale = Vector3.ONE * (0.88 + 0.15 * sin(phase))
	elif style == "shuriken":
		Art.update_volume(_core3, "shuriken", Art.SHURIKEN_FRAMES[int(_t * 18.0) % 2])
	var p: Vector3 = main.to3d(art_pos, h)
	_v3.position = p
	if _core3:
		if style == "arrow" and velocity.length_squared() > 0.01:
			var dir := Vector3(velocity.x, 0.0, velocity.y).normalized()
			var side := Vector3.UP.cross(dir)
			var up := (Vector3.UP * 0.63 + side * 0.78).normalized()
			_core3.basis = Basis(dir, up, dir.cross(up))
		else:
			var camera := main._cam3d as Camera3D
			var facing := camera.global_basis.orthonormalized()
			var roll := _t * 17.0 if style == "shuriken" else 0.0
			var tilt := sin(_t * 8.0 + _spirit_phase) * 0.18 if style == "spirit" else 0.0
			var pulse := 1.0 + 0.06 * sin(_t * 19.0)
			if style == "spirit":
				pulse *= lerpf(0.45, 1.0, clampf(_t * 9.0, 0.0, 1.0))
			_core3.basis = facing.rotated(facing.z, roll).rotated(facing.y, tilt).scaled(Vector3.ONE * pulse)
	if _trail3 == null:
		return
	_trail_pts.append(p)
	while _trail_pts.size() > (12 if style == "wave" else 8):
		_trail_pts.remove_at(0)
	_trail_im.clear_surfaces()
	if _trail_pts.size() < 2:
		return
	# Шлейф — вертикальная лента, сужается к хвосту
	var hw := 0.22 if style == "wave" else 0.07
	_trail_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in _trail_pts.size():
		var k := float(i) / (_trail_pts.size() - 1)
		var c := Color(color.r * 1.2, color.g * 1.2, color.b * 1.2, k * 0.75)
		_trail_im.surface_set_color(c)
		_trail_im.surface_add_vertex(_trail_pts[i] + Vector3(0, hw * k, 0))
		_trail_im.surface_add_vertex(_trail_pts[i] - Vector3(0, hw * k, 0))
	_trail_im.surface_end()


func _spirit_dissolve(impact: bool) -> void:
	var last_pose := (_core3.material_override as StandardMaterial3D).albedo_texture
	var trace := Art.volume_instance("spirit", last_pose)
	var mat := trace.material_override as StandardMaterial3D
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color.lerp(Color.WHITE, 0.72)
	main._bill_root.add_child(trace)
	trace.global_transform = _core3.global_transform
	var tween := trace.create_tween()
	if impact:
		tween.tween_interval(0.06)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.17)
	tween.parallel().tween_property(mat, "emission_energy_multiplier", 0.0, 0.17)
	tween.parallel().tween_property(trace, "scale", trace.scale * 1.12, 0.17)
	tween.tween_callback(trace.queue_free)


func _build_ball() -> void:
	_ball_core = Art.energy_sphere()
	_v3.add_child(_ball_core)
	# Кольца и дуги рисуются одной лентой каждый кадр
	_ball_fx = MeshInstance3D.new()
	_ball_fx.mesh = _ball_im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ball_fx.material_override = m
	_ball_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main._bill_root.add_child(_ball_fx)
	# Живой свет: освещает пол и соседние спрайты
	_ball_light = PointLight2D.new()
	_ball_light.texture = Pixel.glow()
	_ball_light.color = Color(0.55, 0.8, 1.0)
	_ball_light.energy = 1.0
	_ball_light.texture_scale = maxf(2.5, zap_radius / 40.0)
	add_child(_ball_light)
	main.mirror_light(_ball_light, self, 0.6)
	# Пятно на полу: мерцающий круг зоны поражения
	_ground = preload("res://scripts/drawer.gd").new()
	_ground.draw_fn = _draw_ball_ground
	_ground.material = Pixel.mat_add()
	_ground.z_index = -10
	add_child(_ground)


func _draw_ball_ground(c: Node2D) -> void:
	var a := clampf(life * 2.0, 0.0, 1.0) * clampf(_t * 4.0, 0.0, 1.0)
	var r := zap_radius
	var col := color.lerp(Color(1.0, 0.6, 0.2), clampf(zap_radius / maxf(_zap_r0, 1.0) - 1.0, 0.0, 1.0))
	c.draw_circle(Vector2.ZERO, r * 0.35, Color(col, 0.10 * a))
	# Пунктир по краю зоны, вращается
	var n := 24
	for i in n:
		if i % 2 == 1:
			continue
		var a0 := _t * 1.5 + TAU * i / n
		c.draw_arc(Vector2.ZERO, r, a0, a0 + TAU / n, 4, Color(col, 0.35 * a), 2.0)
	# Внутренний рунный круг в обратную сторону
	for i in 6:
		var ang := -_t * 2.5 + TAU * i / 6.0
		var p := Vector2(cos(ang), sin(ang)) * r * 0.55
		c.draw_circle(p, 3.0, Color(col.lightened(0.4), 0.5 * a))
	c.draw_arc(Vector2.ZERO, r * 0.55, 0.0, TAU, 32, Color(col, 0.18 * a), 1.5)


## Лента, повёрнутая к камере, через набор точек (кольца и дуги шара).
func _ribbon(pts: PackedVector3Array, w: float, col: Color, cam: Vector3) -> void:
	if pts.size() < 2:
		return
	_ball_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in pts.size():
		var p := pts[i]
		var dir := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := dir.cross((cam - p).normalized()).normalized() * w
		_ball_im.surface_set_color(col)
		_ball_im.surface_add_vertex(p - side)
		_ball_im.surface_add_vertex(p + side)
	_ball_im.surface_end()


func _update_ball(delta: float) -> void:
	_hot = maxf(0.0, _hot - delta)
	_split_cd = maxf(0.0, _split_cd - delta)
	var c: Vector3 = _v3.position
	var cam: Vector3 = main._cam3d.global_position
	var grow := zap_radius / maxf(_zap_r0, 1.0)
	var R := 0.26 * grow
	var flick := 0.85 + 0.15 * sin(_t * 47.0) * sin(_t * 23.0)
	var heat := clampf(grow - 1.0, 0.0, 1.0)
	var col := color.lerp(Color(1.0, 0.65, 0.3), heat)
	var hot := 1.0 + _hot * 2.0
	_ball_core.scale = Vector3.ONE * (0.22 + 0.06 * flick) * grow * (1.0 + _hot)
	(_ball_core.material_override as StandardMaterial3D).albedo_color = col.lerp(Color.WHITE, 0.74) * 1.6
	(_glow3.material_override as StandardMaterial3D).albedo_color = Color(col, 0.55 * flick)
	_glow3.scale = Vector3.ONE * grow * (1.0 + 0.1 * sin(_t * 9.0) + _hot * 0.5)
	_ball_light.energy = (0.55 + 0.3 * flick) * hot
	_ball_light.color = col
	_ball_im.clear_surfaces()
	# Три наклонных кольца-орбиты
	for k in 3:
		var tilt := 0.6 + k * 0.9
		var spin := _t * (2.6 + k * 1.3) * (1.0 if k % 2 == 0 else -1.0)
		var axis_a := Vector3(cos(tilt), 0.0, sin(tilt))
		var axis_b := Vector3(0.0, 1.0, 0.0).rotated(axis_a, 0.5 + k * 0.7)
		var pts := PackedVector3Array()
		var rr := R * (1.25 + 0.12 * k)
		for i in 21:
			var ang := spin + TAU * i / 20.0
			pts.append(c + (axis_a * cos(ang) + axis_b * sin(ang)) * rr)
		_ribbon(pts, 0.012, Color(col.lightened(0.3), 0.45 * hot), cam)
		# Искра, бегущая по кольцу
		var sp := c + (axis_a * cos(spin * 2.0) + axis_b * sin(spin * 2.0)) * rr
		_ribbon(PackedVector3Array([sp - axis_a * 0.04, sp + axis_a * 0.04]), 0.03, Color(1.0, 1.0, 1.0, 0.9), cam)
	# Дуги-разряды из ядра наружу
	_arc_t -= delta
	if _arc_t <= 0.0:
		_arc_t = 0.05
		var dir := Vector3(randf_range(-1, 1), randf_range(-0.6, 1), randf_range(-1, 1)).normalized()
		var pts := PackedVector3Array()
		var segs := 5
		for i in segs + 1:
			var k := float(i) / segs
			var off := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.05 * (1.0 if i > 0 and i < segs else 0.0)
			pts.append(dir * R * (0.3 + 1.6 * k) + off)
		_arcs.append([pts, 0.12])
	var i := _arcs.size() - 1
	while i >= 0:
		_arcs[i][1] -= delta
		if _arcs[i][1] <= 0.0:
			_arcs.remove_at(i)
		else:
			var local: PackedVector3Array = _arcs[i][0]
			var world := PackedVector3Array()
			for p in local:
				world.append(c + p)
			var a: float = _arcs[i][1] / 0.12
			_ribbon(world, 0.022, Color(col, 0.35 * a), cam)
			_ribbon(world, 0.008, Color(1.0, 1.0, 1.0, 0.9 * a), cam)
		i -= 1


## Подпитка от другого оружия (молния, луч, импульс): шар раскаляется.
func overcharge(power := 1.0) -> void:
	if style != "ball":
		return
	life = minf(life + 0.8 * power, _life0 + 3.0)
	zap_radius = minf(zap_radius * (1.0 + 0.12 * power), _zap_r0 * 1.7)
	_hot = 0.35
	_zap_t = 0.0
	if _ball_light:
		_ball_light.texture_scale = maxf(2.5, zap_radius / 40.0)


## Разрубить шар (катана, сюрикены): два шара поменьше.
func split() -> void:
	if style != "ball" or _split_cd > 0.0 or life < 0.6:
		return
	var balls := 0
	for p in main.projectiles_node.get_children():
		if p.get("style") == "ball":
			balls += 1
	if balls >= 6:
		return
	_split_cd = 1.5
	var p := duplicate_ball()
	p.velocity = velocity.rotated(0.8)
	velocity = velocity.rotated(-0.8)
	main.projectiles_node.add_child(p)
	main.combo_pop(position + Vector2(0, -60), "РАСЩЕПЛЕНИЕ", Color(0.6, 0.85, 1.0))


func duplicate_ball() -> Node2D:
	var p = get_script().new()
	p.main = main
	p.style = "ball"
	p.position = position
	p.velocity = velocity
	p.pierce = 9999
	p.life = life * 0.8
	p.zap_radius = _zap_r0 * 0.85
	p.zap_damage = zap_damage * 0.8
	p.zap_chain = zap_chain
	p.color = color
	p.source = source
	p.owner_pl = owner_pl
	p._split_cd = 1.5
	return p


## Снаряд пролетает сквозь поле другого оружия и перенимает его стихию.
func _check_infuse() -> void:
	if status2 != "" or style in ["ball", "flask", "wave"]:
		return
	var got := ""
	for z in main.zones_node.get_children():
		if z.status != status and z.status != "" and position.distance_to(z.position) < z.radius:
			got = z.status
			break
	if got == "":
		for b in main.projectiles_node.get_children():
			if b != self and b.get("style") == "ball" and status != "shock" and position.distance_to(b.position) < b.zap_radius * 0.6:
				got = "shock"
				break
	if got == "":
		return
	status2 = got
	var c: Color = preload("res://scripts/data.gd").STATUSES[got]["color"]
	color = color.lerp(c, 0.55)
	_recolor()
	Fx.burst(main, position, [Pixel.hdr(c, 1.8), Color(c, 0.0)], 5, 100.0, 0.3, 3.0)


## Катализаторы снарядов: усиление от чужого статуса на цели.
func _catalyst(e: Node2D) -> void:
	var pl = owner_pl
	if not pl.catalyzed(source, e):
		return
	match source:
		"scatter":
			# Короткое замыкание: осколок во враге под током бьёт соседа
			pl.combo("scatter", e.position)
			var nb: Array = main.nearest_enemies_to(e.position, 2, 120.0, e)
			for n in nb:
				if n != e and is_instance_valid(n) and n.can_be_hit():
					Fx.sparks(main, n.position + Vector2(0, -15), Color(0.5, 0.9, 1.0), 6)
					n.hit(damage * 0.6, e.position, 60.0, "shock")
					break
		"mines":
			# Гремучая смесь: мина среди отравленных взрывается шире
			explode *= 1.5
			pl.combo("mines", e.position)
		"bolt":
			if explode <= 0.0:
				pl.combo("bolt", e.position)
				Fx.explosion(main, position, Color(1.0, 0.55, 0.2), Color(0.6, 0.4, 1.0), 60.0 * pl.area_mult)
				main.damage_area(position, 60.0 * pl.area_mult, damage * 0.6, e, "shock")
		"railbow":
			pl.combo("railbow", e.position)
			main.spawn_shards(e.position + Vector2(0, -15), 4, damage * 0.4)
		"spirits":
			var n := 0
			for p in main.projectiles_node.get_children():
				if p.get("style") == "spirit":
					n += 1
			if n < 40:
				pl.combo("spirits", e.position)
				var sp = pl._make_proj("spirit", e.position + Vector2(0, -15), velocity.rotated(PI * 0.7), damage, "chill", "spirits")
				sp.homing = true
				sp.life = 1.6
				sp.color = Color(1.0, 0.6, 0.9)
				sp._hit_ids[e.get_instance_id()] = true
				main.projectiles_node.add_child(sp)
		"shuriken":
			if not no_rebound:
				var others: Array = main.nearest_enemies_to(e.position, 1, 320.0, e)
				if not others.is_empty():
					pl.combo("shuriken", e.position)
					var dir: Vector2 = (others[0].position - e.position).normalized()
					var sh = pl._make_proj("shuriken", e.position, dir * velocity.length(), damage * 0.8, "bleed", "shuriken")
					sh.pierce = 2
					sh.life = 0.5
					sh.no_rebound = true
					sh.color = Color(0.6, 0.9, 1.0)
					sh._hit_ids[e.get_instance_id()] = true
					main.projectiles_node.add_child(sh)


func _in_any_aura() -> bool:
	for p in main.players:
		if not p._dead and p.in_aura(position):
			return true
	return false


func _exit_tree() -> void:
	if is_instance_valid(_ball_fx):
		_ball_fx.queue_free()
	if is_instance_valid(_v3):
		_v3.queue_free()
	if is_instance_valid(_trail3):
		_trail3.queue_free()


func _recolor() -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(color, 0.0), Color(color, 0.7)])
	_trail.gradient = g
	_glow.modulate = Color(color, 0.3)
	_core.modulate = Pixel.hdr(color.lerp(Color.WHITE, 0.4), 1.3)
	if _glow3:
		(_glow3.material_override as StandardMaterial3D).albedo_color = Color(color, 0.45)
	if _core3:
		(_core3.material_override as StandardMaterial3D).albedo_color = color.lerp(Color.WHITE, 0.68)


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
		net_pos += velocity * delta
		position = position.lerp(net_pos, 1.0 - exp(-20.0 * delta))
		_update_3d()
		if style == "ball":
			_update_ball(delta)
		return
	var prev := position
	if homing:
		var targets: Array = main.nearest_enemies_to(position, 1, 400.0, null)
		if style == "spirit":
			_spirit_near_target = not targets.is_empty() and position.distance_squared_to(targets[0].position) < 165.0 * 165.0
		if not targets.is_empty():
			var want: Vector2 = (targets[0].position + Vector2(0, -15) - position).normalized() * velocity.length()
			velocity = velocity.lerp(want, minf(1.0, delta * 5.0))
	position += velocity * delta
	life -= delta
	_update_3d()
	if style == "ball":
		_update_ball(delta)
	_infuse_t -= delta
	if _infuse_t <= 0.0:
		_infuse_t = 0.1
		_check_infuse()
	_trail.add_point(global_position)
	while _trail.get_point_count() > (12 if style == "wave" else 9):
		_trail.remove_point(0)
	if style == "orb":
		_core.rotation += delta * 12.0
		_core.scale = Vector2(Pixel.PX, Pixel.PX * Pixel.STAND) * (0.85 + 0.15 * sin(_t * 30.0))
	else:
		_core.rotation = velocity.angle()

	if boomerang and not _returning and life < _life0 * 0.5:
		_returning = true
		_hit_ids.clear()
	if _returning:
		var back: Vector2 = owner_pl.position - position
		velocity = back.normalized() * velocity.length()
		if back.length() < 30.0:
			queue_free()
			return
	if zap_radius > 0.0:
		_zap_t -= delta
		if _zap_t <= 0.0:
			_zap_t = 0.35
			_zap()
	if style == "flask":
		if life <= 0.0:
			_splash()
			queue_free()
		return

	# Синергия: пролёт через Рунный круг поджигает искру
	if can_ignite and not _ignited and _in_any_aura():
		_ignited = true
		status = "burn"
		color = Color(1.0, 0.5, 0.15)
		damage *= 1.25
		_recolor()
		Fx.burst(main, position, [Pixel.hdr(Color(1.0, 0.6, 0.2), 2.0), Color(1.0, 0.2, 0.1, 0.0)], 6, 120.0, 0.35, 3.0)

	if life <= 0.0:
		if style == "spirit":
			_spirit_dissolve(false)
		Fx.burst(main, position, [Pixel.hdr(color, 1.6), Color(color, 0.0)], 4, 60.0, 0.25, 2.5)
		queue_free()
		return
	var seg_mid := (prev + position) * 0.5
	var seg_r := prev.distance_to(position) * 0.5 + radius + 40.0
	for e in main.enemies_near(seg_mid, seg_r):
		if not e.can_be_hit() or _hit_ids.has(e.get_instance_id()):
			continue
		var r: float = radius + e.radius + (20.0 if style == "wave" else 0.0)
		var target: Vector2 = e.position + Vector2(0, -15)
		var closest := Geometry2D.get_closest_point_to_segment(target, prev, position)
		if closest.distance_squared_to(target) < r * r:
			_hit_ids[e.get_instance_id()] = true
			main.attacker = owner_pl
			owner_pl.set_source(source)
			_catalyst(e)
			e.hit(damage, position - velocity.normalized() * 20.0, 160.0, status)
			if status2 != "" and not e.dead:
				e.apply_status(status2)
			Fx.sparks(main, position, color, 5)
			if explode > 0.0:
				Fx.explosion(main, position, color, Color(0.6, 0.4, 1.0), explode)
				main.damage_area(position, explode, damage * 0.5, e, status)
			pierce -= 1
			if pierce <= 0:
				if style == "spirit":
					_spirit_dissolve(true)
				queue_free()
				return



## Шаровая молния: бьёт током ближайших врагов вокруг себя.
func _zap() -> void:
	var pl = owner_pl
	main.attacker = pl
	var targets: Array = main.nearest_enemies_to(position, 3 + pl.chain_bonus, zap_radius, null)
	var from: Vector3 = main.to3d(position, _height)
	var col := color.lerp(Color(1.0, 0.65, 0.3), clampf(zap_radius / maxf(_zap_r0, 1.0) - 1.0, 0.0, 1.0))
	for t in targets:
		main.beam3d(PackedVector3Array([from, main.to3d(t.position, 0.45)]), col, 0.03, 0.14, 0.1)
		pl.set_source(source)
		if pl.catalyzed("ball", t) and zap_radius < _zap_r0 * 1.6:
			zap_radius = minf(zap_radius * 1.08, _zap_r0 * 1.6)
			life += 0.3
			if randf() < 0.3:
				pl.combo("ball", position)
		t.hit(zap_damage, position, 40.0, "shock")
		if zap_chain:
			for n in main.nearest_enemies_to(t.position, 1 + pl.chain_bonus, 160.0, t):
				main.beam3d(PackedVector3Array([main.to3d(t.position, 0.45), main.to3d(n.position, 0.45)]), Color(0.55, 0.8, 1.0), 0.02, 0.12, 0.08)
				n.hit(zap_damage * 0.6, t.position, 30.0, "shock")
	if not targets.is_empty():
		Sound.play("zap", -16.0, 1.6, 0.2, 0.08)


## Колба разбивается и оставляет лужу.
func _splash() -> void:
	var z = preload("res://scripts/zone.gd").new()
	z.main = main
	z.position = position
	z.radius = pool.get("radius", 60.0)
	z.damage = pool.get("damage", 5.0)
	z.duration = pool.get("duration", 3.0)
	z.status = "poison"
	z.flask = true
	z.owner_pl = owner_pl
	z.color = owner_pl.evo_tint(source, Color(0.6, 1.0, 0.3))
	z.source = source
	main.zones_node.add_child(z)
	Fx.burst(main, position, [Color(0.7, 1.0, 0.4, 0.9), Color(0.3, 0.8, 0.2, 0.0)], 12, 160.0, 0.5, 3.5, false, Vector2(0, 120))
	Sound.play("hit", -6.0, 0.7, 0.1, 0.05)
