extends CanvasLayer
## Неоновый переход между экранами: застывший кадр прошлого экрана
## растворяется кольцом от центра с лёгким наездом, открывая то, что под ним.
## Используется между заставкой и меню, а также до и после экрана загрузки.

const SHADER := """
shader_type canvas_item;
uniform float p = 0.0;
uniform float aspect = 1.0;
uniform vec4 edge : source_color = vec4(1.0, 0.25, 0.85, 1.0);
void fragment() {
	vec2 d = (UV - 0.5) * vec2(aspect, 1.0);
	float r = length(d) / (0.5 * length(vec2(aspect, 1.0)));
	// рваная кромка: волна идёт от центра наружу
	float n = sin(atan(d.y, d.x) * 9.0 + p * 6.0) * 0.025 + sin(UV.y * 80.0) * 0.006;
	float front = p * 1.35 - 0.12;
	float k = smoothstep(front - 0.02, front + 0.1, r + n);
	vec4 c = texture(TEXTURE, UV);
	float glow = smoothstep(0.12, 0.0, abs(r + n - front - 0.03)) * (1.0 - p);
	COLOR = vec4(mix(c.rgb, edge.rgb * 2.0, glow * 0.8), max(c.a * k, glow * 0.9));
}
"""

static var _shader: Shader


## Снимок того, что сейчас на экране (null, если снять нельзя).
static func capture(vp: Viewport) -> Texture2D:
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


## Растворить кадр tex поверх всего. Возвращает узел перехода (у него сигнал done).
static func play(tex: Texture2D, layer_index := 130, dur := 1.1, edge := Color(1.0, 0.25, 0.85)) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tex == null or tree == null:
		return null
	var t = load("res://scripts/transition.gd").new()
	t.layer = layer_index
	tree.root.add_child(t)
	t._run(tex, dur, edge)
	return t


signal done

var _rect: TextureRect


func _run(tex: Texture2D, dur: float, edge: Color) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = TextureRect.new()
	_rect.texture = tex
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs := get_viewport().get_visible_rect().size
	_rect.pivot_offset = vs / 2.0
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("aspect", vs.x / maxf(1.0, vs.y))
	m.set_shader_parameter("edge", edge)
	_rect.material = m
	add_child(_rect)
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(v: float): m.set_shader_parameter("p", v), 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_rect, "scale", Vector2.ONE * 1.12, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		done.emit()
		queue_free())
