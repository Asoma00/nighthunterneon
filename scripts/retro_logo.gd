extends Control
## Логотип в стиле 80-х: хромированные буквы с горизонтом и бликом, неоновая
## надпись «от руки» со шлейфом и полосатый треугольник за ними.
## Используется в заставке и в главном меню.
##   setup(chrome, neon, size) — тексты и высота хрома в пикселях;
##   play()  — анимация появления (треугольник → хром → неон → блик);
##   t       — время с начала анимации (можно крутить вручную).

const CHROME_SHADER := """
shader_type canvas_item;
uniform float shine = -2.0;
uniform float reveal = 1.0;
void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	float a = texture(TEXTURE, UV).a;
	// Обводка: светлый кант вокруг букв и мягкое синее свечение
	float o = 0.0;
	float g = 0.0;
	for (int i = 0; i < 12; i++) {
		float ang = float(i) * 0.5236;
		vec2 d = vec2(cos(ang), sin(ang));
		o = max(o, texture(TEXTURE, UV + d * px * 3.5).a);
		g += texture(TEXTURE, UV + d * px * 11.0).a;
	}
	g /= 12.0;
	// Хромовый градиент: небо сверху, линия горизонта с горами, закат снизу
	float y = UV.y;
	float hz = 0.56 + 0.025 * sin(UV.x * 37.0) * sin(UV.x * 13.0 + 1.3);
	vec3 col;
	if (y < hz) {
		float k = y / hz;
		col = mix(vec3(0.05, 0.08, 0.45), vec3(0.45, 0.7, 1.0), smoothstep(0.1, 0.85, k));
		col = mix(col, vec3(0.95, 0.97, 1.0), smoothstep(0.82, 1.0, k));
	} else {
		float k = (y - hz) / (1.0 - hz);
		col = mix(vec3(0.12, 0.02, 0.22), vec3(0.85, 0.25, 0.7), smoothstep(0.0, 0.7, k));
		col = mix(col, vec3(1.0, 0.75, 0.95), smoothstep(0.75, 1.0, k));
	}
	// Фаска: светлый верхний край букв, тёмный нижний
	float up = a - texture(TEXTURE, UV - vec2(0.0, px.y * 3.0)).a;
	float dn = a - texture(TEXTURE, UV + vec2(0.0, px.y * 3.0)).a;
	col += vec3(0.6) * clamp(up, 0.0, 1.0);
	col *= 1.0 - 0.35 * clamp(dn, 0.0, 1.0);
	// Блик, бегущий по диагонали
	float s = UV.x + UV.y * 0.35 - shine;
	col += vec3(1.0) * smoothstep(0.06, 0.0, abs(s)) * 0.9;
	vec3 stroke = vec3(0.85, 0.85, 1.0);
	vec3 glow = vec3(0.35, 0.5, 1.0);
	vec4 res = vec4(glow, g * 0.55);
	res = mix(res, vec4(stroke, 1.0), clamp(o - a, 0.0, 1.0) * step(0.01, o));
	res = mix(res, vec4(col, 1.0), a);
	// Проявление сверху вниз
	res.a *= smoothstep(reveal + 0.02, reveal - 0.02, UV.y * 0.98);
	COLOR = res;
}
"""

const NEON_SHADER := """
shader_type canvas_item;
uniform float power = 1.0;
uniform vec3 tint = vec3(1.0, 0.18, 0.62);
uniform float slant = -0.28;
void vertex() {
	VERTEX.x += (VERTEX.y - 60.0) * slant;
}
void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	float a = texture(TEXTURE, UV).a;
	float g1 = 0.0;
	float g2 = 0.0;
	for (int i = 0; i < 12; i++) {
		float ang = float(i) * 0.5236;
		vec2 d = vec2(cos(ang), sin(ang));
		g1 += texture(TEXTURE, UV + d * px * 4.0).a;
		g2 += texture(TEXTURE, UV + d * px * 12.0).a;
	}
	g1 /= 12.0;
	g2 /= 12.0;
	vec3 core = mix(tint, vec3(1.0, 0.9, 0.97), 0.55);
	vec4 res = vec4(tint, (g2 * 0.45 + g1 * 0.6) * power);
	res = mix(res, vec4(core * (0.6 + 0.6 * power), 1.0), a * clamp(power * 1.4, 0.0, 1.0));
	COLOR = res;
}
"""

var chrome_text := "CPA4KA"
var neon_text := ""
var chrome_px := 110
var tri := true
var t := 99.0
var playing := false

var _chrome: TextureRect
var _neon: TextureRect
var _cvp: SubViewport
var _nvp: SubViewport
var _cmat: ShaderMaterial
var _nmat: ShaderMaterial
var _bold: FontVariation
var _ital: FontVariation


func setup(chrome: String, neon := "", size_px := 110, with_triangle := true) -> void:
	chrome_text = chrome
	neon_text = neon
	chrome_px = size_px
	tri = with_triangle
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bold = FontVariation.new()
	_bold.base_font = ThemeDB.fallback_font
	_bold.variation_embolden = 1.3
	_bold.spacing_glyph = int(size_px * 0.02)
	_ital = FontVariation.new()
	_ital.base_font = ThemeDB.fallback_font
	_ital.variation_embolden = 0.4
	# Хром: текст рендерится в свой вьюпорт, сверху — шейдер
	_cvp = _make_vp(chrome, _bold, size_px, Color.WHITE, false)
	_chrome = TextureRect.new()
	_chrome.texture = _cvp.get_texture()
	_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cmat = ShaderMaterial.new()
	_cmat.shader = Shader.new()
	_cmat.shader.code = CHROME_SHADER
	_chrome.material = _cmat
	add_child(_chrome)
	if neon != "":
		_nvp = _make_vp(neon, _ital, int(size_px * 0.72), Color.WHITE, true)
		_neon = TextureRect.new()
		_neon.texture = _nvp.get_texture()
		_neon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_nmat = ShaderMaterial.new()
		_nmat.shader = Shader.new()
		_nmat.shader.code = NEON_SHADER
		_neon.material = _nmat
		add_child(_neon)
	_layout()
	resized.connect(_layout)


func _make_vp(text: String, font: Font, fs: int, col: Color, swoosh: bool) -> SubViewport:
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var pad := int(fs * 0.35)
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	vp.size = Vector2i(int(sz.x) + pad * 2 + (int(fs * 0.6) if swoosh else 0), int(fs * 1.25) + pad * 2 + (int(fs * 0.3) if swoosh else 0))
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.position = Vector2(pad + (int(fs * 0.3) if swoosh else 0), pad - fs * 0.1)
	vp.add_child(l)
	if swoosh:
		# Росчерк под надписью, как неоновая трубка
		var ln := Line2D.new()
		ln.width = maxf(4.0, fs * 0.07)
		ln.default_color = col
		ln.joint_mode = Line2D.LINE_JOINT_ROUND
		ln.begin_cap_mode = Line2D.LINE_CAP_ROUND
		ln.end_cap_mode = Line2D.LINE_CAP_ROUND
		var w := float(vp.size.x)
		var h := float(vp.size.y)
		for i in 24:
			var k := float(i) / 23.0
			ln.add_point(Vector2(pad * 0.5 + k * (w - pad), h * 0.86 - sin(k * PI * 0.9 + 0.2) * h * 0.12 - k * h * 0.08))
		vp.add_child(ln)
	add_child(vp)
	return vp


func _layout() -> void:
	if _chrome == null:
		return
	var cs := Vector2(_cvp.size)
	var k := minf(1.0, (size.x - 20.0) / cs.x) if size.x > 0.0 else 1.0
	_chrome.size = cs
	_chrome.scale = Vector2(k, k)
	_chrome.pivot_offset = cs / 2.0
	_chrome.position = Vector2(size.x / 2.0 - cs.x / 2.0, size.y * (0.4 if _neon else 0.44) - cs.y / 2.0)
	if _neon:
		var ns := Vector2(_nvp.size)
		_neon.size = ns
		_neon.pivot_offset = ns / 2.0
		_neon.scale = Vector2(k, k)
		_neon.position = Vector2(size.x / 2.0 - ns.x / 2.0 + cs.x * 0.06 * k, _chrome.position.y + cs.y * (0.5 + 0.35 * k) - ns.y * 0.15)
	queue_redraw()


func play() -> void:
	t = 0.0
	playing = true


func _process(delta: float) -> void:
	if playing:
		t += delta
	_animate()


func _animate() -> void:
	if _chrome == null:
		return
	# 0.0–0.5 треугольник, 0.35–1.0 хром сверху вниз, 1.0–1.6 неон, 1.5+ блик и мерцание
	var kc := clampf((t - 0.35) / 0.6, 0.0, 1.0)
	_cmat.set_shader_parameter("reveal", ease(kc, 0.5) * 1.05)
	var base_k := _chrome.scale.x
	_chrome.modulate.a = 1.0
	var sh := fmod(maxf(t - 1.4, 0.0), 4.0)
	_cmat.set_shader_parameter("shine", -0.4 + sh * 0.9 if t > 1.4 else -2.0)
	if _neon:
		var p := 0.0
		if t > 1.0:
			p = 1.0
			# Неон «зажигается» с запинками, потом изредка подмигивает
			if t < 1.6:
				p = 1.0 if fmod(t * 13.0, 1.0) > 0.45 else 0.15
			elif randf() < 0.01:
				p = 0.4
		_nmat.set_shader_parameter("power", p)
	var _unused := base_k
	queue_redraw()


func _draw() -> void:
	if not tri or _chrome == null:
		return
	var kt := ease(clampf(t / 0.55, 0.0, 1.0), 0.4)
	if kt <= 0.0:
		return
	var cs := Vector2(_cvp.size) * _chrome.scale.x
	var c := Vector2(size.x / 2.0, _chrome.position.y + Vector2(_cvp.size).y / 2.0 + cs.y * 0.05)
	var w := cs.x * 1.05 * kt
	var top := c.y - cs.y * 0.12
	var h := minf(w * 0.5, size.y - top - 2.0)   # треугольник не вылезает за свой блок
	# Полосатый перевёрнутый треугольник: 4 полосы с зазорами
	var bands := [[0.0, 0.18], [0.24, 0.42], [0.48, 0.68], [0.74, 1.0]]
	for b in bands:
		var y0: float = top + h * float(b[0])
		var y1: float = top + h * float(b[1])
		var hw0: float = w / 2.0 * (1.0 - float(b[0]))
		var hw1: float = w / 2.0 * (1.0 - float(b[1]))
		var c0 := Color(0.55, 0.62, 1.0).lerp(Color(0.32, 0.08, 0.55), float(b[0]))
		var c1 := Color(0.55, 0.62, 1.0).lerp(Color(0.32, 0.08, 0.55), float(b[1]))
		var pts := PackedVector2Array([Vector2(c.x - hw0, y0), Vector2(c.x + hw0, y0), Vector2(c.x + hw1, y1), Vector2(c.x - hw1, y1)])
		draw_polygon(pts, PackedColorArray([c0, c0, c1, c1]))
		draw_line(pts[0], pts[1], Color(0.9, 0.9, 1.0, 0.9), 2.0)
		draw_polyline(PackedVector2Array([pts[1], pts[2], pts[3], pts[0]]), Color(0.75, 0.75, 1.0, 0.45), 1.5)
