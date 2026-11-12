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
	float k = 0.0;
	float g = 0.0;
	for (int i = 0; i < 12; i++) {
		float ang = float(i) * 0.5236;
		vec2 d = vec2(cos(ang), sin(ang));
		o = max(o, texture(TEXTURE, UV + d * px * 3.5).a);
		k = max(k, texture(TEXTURE, UV + d * px * 8.0 + vec2(0.0, px.y * 3.0)).a);
		g += texture(TEXTURE, UV + d * px * 14.0).a;
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
	vec4 res = vec4(glow, g * 0.35);
	// Тёмная обводка с тенью — буквы не сливаются с треугольником
	res = mix(res, vec4(0.02, 0.0, 0.06, 0.95), k);
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
uniform float draw = 1.0;
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
	// Надпись «пишется» слева направо, на кончике — искра
	res.a *= smoothstep(draw + 0.03, draw - 0.03, UV.x);
	res.rgb += vec3(1.0, 0.9, 1.0) * smoothstep(0.04, 0.0, abs(UV.x - draw)) * step(0.02, g1) * step(draw, 0.99);
	COLOR = res;
}
"""


## Итоговая картинка с перспективой: левый край ближе, правый дальше и выше.
## Плюс глитч-срезы и растворение для переходов.
const WARP_SHADER := """
shader_type canvas_item;
uniform float far_k = 0.8;      // высота правого края относительно левого
uniform float lift = 0.07;      // насколько правый край выше
uniform float glitch = 0.0;
uniform float fade = 1.0;
uniform float t = 0.0;
void fragment() {
	float u = UV.x;
	float h = mix(1.0, far_k, u);
	float c = mix(0.5, 0.5 - lift, u);
	float us = u * far_k / ((1.0 - u) + u * far_k);
	float vs = (UV.y - c) / h + 0.5;
	// Глитч: горизонтальные полосы сдвигаются
	float band = floor(UV.y * 24.0);
	float rnd = fract(sin(band * 91.7 + floor(t * 20.0) * 13.1) * 4375.5);
	us += (rnd - 0.5) * 0.12 * glitch * step(0.55, rnd);
	vec4 col = texture(TEXTURE, vec2(us, vs));
	vec4 cr = texture(TEXTURE, vec2(us + 0.006 * glitch, vs));
	vec4 cb = texture(TEXTURE, vec2(us - 0.006 * glitch, vs));
	col.r = mix(col.r, cr.r, glitch);
	col.b = mix(col.b, cb.b, glitch);
	if (vs < 0.0 || vs > 1.0 || us < 0.0 || us > 1.0) col.a = 0.0;
	col.a *= fade;
	COLOR = col;
}
"""

var chrome_text := "CPA4KA"
var neon_text := ""
var chrome_px := 110
var tri := true
var t := 99.0
var playing := false
var leaving := -1.0
var perspective := true

var _vp: SubViewport
var _stage: Control
var _out: TextureRect
var _wmat: ShaderMaterial
var _chrome: TextureRect
var _neon: TextureRect
var _cvp: SubViewport
var _nvp: SubViewport
var _cmat: ShaderMaterial
var _nmat: ShaderMaterial
var _bold: FontVariation
var _ital: FontVariation
var _base_pos := Vector2.ZERO


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
	# Вся сцена логотипа рисуется в свой вьюпорт, а на экран — через шейдер перспективы
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.disable_3d = true
	add_child(_vp)
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp.add_child(_stage)
	_stage.draw.connect(_draw_triangle)
	_out = TextureRect.new()
	_out.texture = _vp.get_texture()
	_out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_out.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_out.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wmat = ShaderMaterial.new()
	_wmat.shader = Shader.new()
	_wmat.shader.code = WARP_SHADER
	_out.material = _wmat
	add_child(_out)
	_cvp = _make_vp(chrome, _bold, size_px, Color.WHITE, false)
	_chrome = TextureRect.new()
	_chrome.texture = _cvp.get_texture()
	_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cmat = ShaderMaterial.new()
	_cmat.shader = Shader.new()
	_cmat.shader.code = CHROME_SHADER
	_chrome.material = _cmat
	_stage.add_child(_chrome)
	if neon != "":
		_nvp = _make_vp(neon, _ital, int(size_px * 0.72), Color.WHITE, true)
		_neon = TextureRect.new()
		_neon.texture = _nvp.get_texture()
		_neon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_nmat = ShaderMaterial.new()
		_nmat.shader = Shader.new()
		_nmat.shader.code = NEON_SHADER
		_neon.material = _nmat
		_stage.add_child(_neon)
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
	_vp.size = Vector2i(maxi(int(size.x), 16), maxi(int(size.y), 16))
	_stage.size = size
	var cs := Vector2(_cvp.size)
	var k := minf(1.0, (size.x * 0.86) / cs.x) if size.x > 0.0 else 1.0
	_chrome.size = cs
	_chrome.scale = Vector2(k, k)
	_chrome.pivot_offset = cs / 2.0
	_base_pos = Vector2(size.x / 2.0 - cs.x / 2.0, size.y * (0.43 if _neon else 0.47) - cs.y / 2.0)
	_chrome.position = _base_pos
	if _neon:
		var ns := Vector2(_nvp.size)
		_neon.size = ns
		_neon.pivot_offset = ns / 2.0
		_neon.scale = Vector2(k, k)
		_neon.position = Vector2(size.x / 2.0 - ns.x / 2.0 + cs.x * 0.06 * k, _base_pos.y + cs.y * (0.5 + 0.35 * k) - ns.y * 0.12)
	_wmat.set_shader_parameter("far_k", 0.8 if perspective else 1.0)
	_wmat.set_shader_parameter("lift", 0.07 if perspective else 0.0)
	_stage.queue_redraw()


func play() -> void:
	t = 0.0
	playing = true
	leaving = -1.0


## Уход логотипа: глитч, рывок и растворение (для смены логотипов в заставке).
func leave() -> void:
	leaving = 0.0


func _process(delta: float) -> void:
	if playing:
		t += delta
	if leaving >= 0.0:
		leaving += delta
	_animate()


func _animate() -> void:
	if _chrome == null:
		return
	_wmat.set_shader_parameter("t", t)
	# Хром: влетает из глубины (крупнее и прозрачный), проявляется сверху вниз
	var kc := clampf((t - 0.3) / 0.7, 0.0, 1.0)
	var ez := 1.0 - pow(1.0 - kc, 3.0)
	_cmat.set_shader_parameter("reveal", ez * 1.05)
	var k0: float = _chrome.scale.x / maxf(_chrome.scale.x, 0.0001)
	var base_k := minf(1.0, (size.x * 0.86) / float(_cvp.size.x)) if size.x > 0.0 else 1.0
	var zoom := lerpf(1.6, 1.0, ez)
	# После появления — лёгкое парение
	var bob := sin(t * 1.6) * 3.0 if t > 1.2 else 0.0
	_chrome.scale = Vector2(base_k, base_k) * zoom
	_chrome.position = _base_pos + Vector2(0, bob)
	_chrome.modulate.a = ez
	# Блик каждые 3 секунды
	var sh := fmod(maxf(t - 1.0, 0.0), 3.0)
	_cmat.set_shader_parameter("shine", -0.4 + sh * 1.2 if t > 1.0 else -2.0)
	if _neon:
		var d := clampf((t - 1.0) / 0.6, 0.0, 1.0)
		_nmat.set_shader_parameter("draw", d * 1.05)
		var p := 1.0 if t > 1.0 else 0.0
		if t > 1.6 and t < 1.9:
			p = 1.0 if fmod(t * 17.0, 1.0) > 0.4 else 0.25
		elif t > 1.9 and randf() < 0.008:
			p = 0.45
		_nmat.set_shader_parameter("power", p)
		_neon.position.y = _chrome.position.y - _base_pos.y + _neon_base_y()
	# Вспышка-глитч при «защёлкивании» и при уходе
	var g := 0.0
	if t > 0.95 and t < 1.15:
		g = 0.6
	var fade := 1.0
	if leaving >= 0.0:
		g = clampf(leaving / 0.25, 0.0, 1.0)
		fade = clampf(1.0 - (leaving - 0.15) / 0.3, 0.0, 1.0)
		_chrome.scale *= 1.0 + leaving * 0.4
	_wmat.set_shader_parameter("glitch", g)
	_wmat.set_shader_parameter("fade", fade)
	var _u := k0
	_stage.queue_redraw()


func _neon_base_y() -> float:
	var cs := Vector2(_cvp.size)
	var k := minf(1.0, (size.x * 0.86) / cs.x) if size.x > 0.0 else 1.0
	var ns := Vector2(_nvp.size)
	return _base_pos.y + cs.y * (0.5 + 0.35 * k) - ns.y * 0.12


func _draw_triangle() -> void:
	if not tri or _chrome == null:
		return
	var cs := Vector2(_cvp.size) * minf(1.0, (size.x * 0.86) / float(_cvp.size.x))
	var c := Vector2(size.x / 2.0, _base_pos.y + Vector2(_cvp.size).y / 2.0)
	var w := cs.x * 1.08
	var top := c.y - cs.y * 0.06
	var h := minf(w * 0.48, size.y - top - 2.0)
	# Полосы выезжают по очереди слева и справа, затем по кромке пробегает свет
	var bands := [[0.0, 0.17], [0.24, 0.41], [0.48, 0.66], [0.73, 1.0]]
	for i in bands.size():
		var b: Array = bands[i]
		var kb := clampf((t - i * 0.09) / 0.45, 0.0, 1.0)
		if kb <= 0.0:
			continue
		var e := 1.0 - pow(1.0 - kb, 3.0)
		var dx := (1.0 - e) * w * (1.0 if i % 2 == 0 else -1.0)
		var y0: float = top + h * float(b[0])
		var y1: float = top + h * float(b[1])
		var hw0: float = w / 2.0 * (1.0 - float(b[0]))
		var hw1: float = w / 2.0 * (1.0 - float(b[1]))
		var c0 := Color(0.2, 0.22, 0.6).lerp(Color(0.16, 0.04, 0.3), float(b[0]))
		var c1 := Color(0.2, 0.22, 0.6).lerp(Color(0.16, 0.04, 0.3), float(b[1]))
		c0.a = e * 0.92
		c1.a = e * 0.92
		var cx := c.x + dx
		var pts := PackedVector2Array([Vector2(cx - hw0, y0), Vector2(cx + hw0, y0), Vector2(cx + hw1, y1), Vector2(cx - hw1, y1)])
		_stage.draw_polygon(pts, PackedColorArray([c0, c0, c1, c1]))
		var edge := Color(0.55, 0.85, 1.0, e)
		_stage.draw_line(pts[0], pts[1], edge, 2.5)
		_stage.draw_polyline(PackedVector2Array([pts[1], pts[2], pts[3], pts[0]]), Color(0.6, 0.6, 1.0, 0.5 * e), 1.5)
		# Пробегающий по верхней кромке свет
		var run := fmod(t * 0.5 + i * 0.13, 1.6)
		if run < 1.0 and t > 0.6:
			var px := lerpf(pts[0].x, pts[1].x, run)
			_stage.draw_circle(Vector2(px, y0), 3.0, Color(1, 1, 1, 0.9 * e))
