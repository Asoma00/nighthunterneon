extends CanvasLayer
## Неоновый переход между экранами: застывший кадр прошлого экрана
## растворяется кольцом от центра с лёгким наездом, открывая то, что под ним.
## Используется между заставкой и меню, а также до и после экрана загрузки.

## Каждый переход — своя форма: волна из случайной точки, срез под углом,
## ромб, пузыри, дымка, жалюзи, «часы», пиксельные блоки, спираль.
## Форма не повторяется дважды подряд; центр, угол, цвет кромки и узор — случайные.
const SHADER := """
shader_type canvas_item;
uniform float p = 0.0;
uniform float aspect = 1.0;
uniform int mode = 0;
uniform vec2 center = vec2(0.5);
uniform float rot = 0.0;
uniform float seed = 0.0;
uniform float cells = 8.0;
uniform vec4 edge : source_color = vec4(1.0, 0.25, 0.85, 1.0);

float h21(vec2 q) { return fract(sin(dot(q, vec2(127.1, 311.7)) + seed * 17.0) * 43758.5453); }
float vnoise(vec2 q) {
	vec2 i = floor(q); vec2 f = fract(q); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 q) { float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++) { v += a * vnoise(q); q *= 2.03; a *= 0.5; } return v; }

// Момент (0…1), когда этот пиксель исчезает
float field(vec2 uv) {
	vec2 A = vec2(aspect, 1.0);
	vec2 d = (uv - center) * A;
	vec2 dir = vec2(cos(rot), sin(rot));
	if (mode == 0) {           // волна из случайной точки, рваная кромка
		float far = length(max(center, 1.0 - center) * A);
		return clamp(length(d) / far + sin(atan(d.y, d.x) * 9.0 + seed * 6.0) * 0.025, 0.0, 1.0);
	} else if (mode == 1) {    // срез под углом с зубчатой кромкой
		vec2 q = (uv - 0.5) * A;
		float span = abs(dir.x) * aspect + abs(dir.y);
		float along = dot(q, dir) / span + 0.5;
		float across = dot(q, vec2(-dir.y, dir.x));
		return clamp(along * 0.92 + abs(fract(across * 9.0) - 0.5) * 0.08, 0.0, 1.0);
	} else if (mode == 2) {    // ромб
		float far = (max(center.x, 1.0 - center.x) * aspect + max(center.y, 1.0 - center.y));
		return clamp((abs(d.x) + abs(d.y)) / far, 0.0, 1.0);
	} else if (mode == 3) {    // пузыри: в каждой ячейке своя дыра растёт со своей задержкой
		vec2 g = uv * A * cells;
		vec2 c = floor(g);
		float r = h21(c);
		float dist = length(fract(g) - 0.5) / 0.7071;
		return clamp(r * 0.55 + dist * 0.45, 0.0, 1.0);
	} else if (mode == 4) {    // дымка: рваный шум
		return clamp((fbm(uv * A * 4.0 + seed * 3.0) - 0.2) / 0.6, 0.0, 1.0);
	} else if (mode == 5) {    // жалюзи под углом, раскрываются по очереди
		vec2 q = (uv - 0.5) * A;
		float coord = dot(q, vec2(-dir.y, dir.x)) * cells * 0.6;
		float idx = floor(coord);
		float s = fract(coord);
		float order = fract(idx * 0.37 + seed);
		return clamp(order * 0.5 + abs(s - 0.5) * 1.0, 0.0, 1.0);
	} else if (mode == 6) {    // часы: стрелка обходит круг
		float a = atan(d.y, d.x) - rot;
		return fract(a / 6.2831853 + 1.0) * 0.94 + length(d) * 0.04;
	} else if (mode == 7) {    // пиксельные блоки рассыпаются от центра
		vec2 g = floor(uv * A * cells * 1.6);
		vec2 gc = (g + 0.5) / (cells * 1.6) - center * A;
		float far = length(max(center, 1.0 - center) * A);
		return clamp(h21(g) * 0.55 + length(gc) / far * 0.45, 0.0, 1.0);
	}
	// спираль
	float r = length(d) / length(max(center, 1.0 - center) * A);
	float a2 = atan(d.y, d.x) / 6.2831853 + 0.5;
	return clamp(fract(a2 + r * 1.3 + rot) * 0.55 + r * 0.45, 0.0, 1.0);
}

void fragment() {
	float f = field(UV);
	float prog = p * 1.2 - 0.1;
	float k = smoothstep(prog - 0.015, prog + 0.035, f);
	vec4 c = texture(TEXTURE, UV);
	float glow = smoothstep(0.06, 0.0, abs(f - prog - 0.01)) * (1.0 - p * 0.8);
	COLOR = vec4(mix(c.rgb, edge.rgb * 2.0, glow * 0.8 * k + glow * 0.4), max(c.a * k, glow * 0.85));
}
"""
const MODES := 9
const EDGES := [Color(1.0, 0.25, 0.85), Color(0.3, 0.95, 1.0), Color(1.0, 0.8, 0.3), Color(0.5, 1.0, 0.55), Color(0.7, 0.45, 1.0), Color(1.0, 0.45, 0.25)]
static var _last_mode := -1

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
var mode_used := -1

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
	# Случайная форма — не та же, что в прошлый раз
	var mode := randi() % MODES
	if mode == _last_mode:
		mode = (mode + 1 + randi() % (MODES - 1)) % MODES
	_last_mode = mode
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("center", Vector2(randf_range(0.25, 0.75), randf_range(0.25, 0.75)) if randf() < 0.7 else Vector2(0.5, 0.5))
	m.set_shader_parameter("rot", randf() * TAU)
	m.set_shader_parameter("seed", randf() * 100.0)
	m.set_shader_parameter("cells", randf_range(5.0, 11.0))
	m.set_shader_parameter("edge", edge if randf() < 0.4 else EDGES[randi() % EDGES.size()])
	mode_used = mode
	_rect.material = m
	add_child(_rect)
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(v: float): m.set_shader_parameter("p", v), 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Движение кадра тоже разное: наезд, отъезд или лёгкий поворот с наездом
	match randi() % 3:
		0:
			tw.tween_property(_rect, "scale", Vector2.ONE * 1.12, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		1:
			tw.tween_property(_rect, "scale", Vector2.ONE * 0.9, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_:
			tw.tween_property(_rect, "scale", Vector2.ONE * 1.08, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			tw.tween_property(_rect, "rotation", deg_to_rad(randf_range(-4.0, 4.0)), dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		done.emit()
		queue_free())
