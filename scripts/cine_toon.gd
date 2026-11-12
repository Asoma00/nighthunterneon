extends RefCounted
## Материалы кат-сцен в духе анимационных роликов: мягкий «мультяшный» свет
## с цветными тенями (тени не серые, а сиренево-синие), ровный блик и контровая
## подсветка по краю силуэта. Плюс небо, окна, порталы и лава.

# ---------- Аниме-рисовка (в духе Cyberpunk: Edgerunners) ----------
# Заливка не зависит от источников света движка: направление и цвет «ключа»,
# цвет тени, каймы и тёплого локального света (костёр) задаёт кат-сцена через
# глобальные параметры — так картинка одинакова на ПК, в браузере и на телефоне.

const CEL := """
shader_type spatial;
render_mode unshaded, cull_back;
global uniform vec3 cine_key_dir;
global uniform vec4 cine_key_col;
global uniform vec4 cine_shadow;
global uniform vec4 cine_rim;
global uniform vec4 cine_pt;
global uniform vec4 cine_pt_col;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float flat_k = 0.0;
uniform float skin = 0.0;
uniform float hair = 0.0;
uniform float gloss = 0.0;
uniform float tone = 1.0;
uniform float glow = 0.0;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 L = normalize(cine_key_dir);
	float ndl = dot(n, L) + skin * 0.55;
	float lit = max(smoothstep(-0.03, 0.03, ndl), flat_k);
	vec3 base = albedo.rgb;
	vec3 col = mix(base * cine_shadow.rgb, base * cine_key_col.rgb, lit);
	// Тонировочные точки в тени, как скринтон в манге
	vec2 p = FRAGCOORD.xy / 4.0;
	p = vec2(p.x - p.y, p.x + p.y) * 0.7071;
	float d = length(fract(p) - 0.5);
	float ht = (1.0 - smoothstep(0.2, 0.27, d)) * (1.0 - lit) * tone;
	col *= 1.0 - 0.25 * ht;
	// Тёплый локальный свет (костёр, лава) — отдельная жёсткая зона
	vec3 tp = cine_pt.xyz - wpos;
	float dist = length(tp);
	float pl = step(0.05, dot(n, tp / max(dist, 0.001))) * (1.0 - smoothstep(cine_pt.w * 0.85, cine_pt.w, dist));
	col = mix(col, max(col, base * cine_pt_col.rgb * 1.35), pl * cine_pt_col.a * (1.0 - flat_k));
	// Кайма: резкая цветная полоса по краю силуэта со стороны, обратной свету
	float fr = 1.0 - clamp(dot(n, v), 0.0, 1.0);
	float rim = step(0.76, fr) * step(dot(n, L), 0.2);
	col = mix(col, cine_rim.rgb * 1.4, rim * cine_rim.a * (1.0 - flat_k));
	// Жёсткий блик (волосы, металл)
	vec3 h = normalize(L + v);
	float sp = step(0.955 - hair * 0.07, dot(n, h)) * lit;
	col += sp * (gloss * 0.6 + hair * 0.35) * cine_key_col.rgb;
	ALBEDO = col + base * glow;
}
"""

const OUTLINE := """
shader_type spatial;
render_mode unshaded, cull_front;
uniform float width_px = 2.0;
uniform vec4 line_col : source_color = vec4(0.035, 0.015, 0.06, 1.0);
void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 nv = mat3(MODELVIEW_MATRIX) * NORMAL;
	vec2 nc = (PROJECTION_MATRIX * vec4(nv, 0.0)).xy;
	float l = length(nc);
	if (l > 0.0001) {
		clip.xy += nc / l * width_px * (VIEWPORT_SIZE.y / 720.0) * 2.0 / VIEWPORT_SIZE * clip.w;
	}
	POSITION = clip;
}
void fragment() {
	ALBEDO = line_col.rgb;
}
"""

const NEON_FLAT := """
shader_type spatial;
render_mode unshaded;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float k = 2.0;
void fragment() {
	ALBEDO = albedo.rgb * k;
}
"""

const TOON := """
shader_type spatial;
uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 shade : source_color = vec4(0.36, 0.3, 0.58, 1.0);
uniform vec4 rim_col : source_color = vec4(0.75, 0.85, 1.0, 1.0);
uniform float rim = 0.35;
uniform float glow = 0.0;
uniform float gloss = 0.25;
void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.75;
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.4);
	EMISSION = albedo.rgb * glow + rim_col.rgb * smoothstep(0.55, 1.0, f) * rim;
}
void light() {
	float w = clamp(dot(NORMAL, LIGHT) * 0.5 + 0.5, 0.0, 1.0);
	float b = smoothstep(0.44, 0.6, w);
	vec3 tint = mix(shade.rgb, vec3(1.0), b * 0.8 + w * 0.2);
	DIFFUSE_LIGHT += tint * LIGHT_COLOR * ATTENUATION * mix(0.55, 1.0, b);
	vec3 h = normalize(LIGHT + VIEW);
	float s = pow(clamp(dot(NORMAL, h), 0.0, 1.0), 36.0);
	SPECULAR_LIGHT += smoothstep(0.45, 0.7, s) * gloss * LIGHT_COLOR * ATTENUATION;
}
"""

const GLASS := """
shader_type spatial;
render_mode blend_mix, cull_back;
uniform vec4 albedo : source_color = vec4(0.6, 0.8, 1.0, 0.35);
uniform float glow = 0.4;
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = albedo.rgb;
	EMISSION = albedo.rgb * glow + vec3(1.0) * f * 0.6;
	ALPHA = clamp(albedo.a + f * 0.5, 0.0, 1.0);
	ROUGHNESS = 0.1;
}
"""

const GLOW := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 col : source_color = vec4(1.0);
uniform float k = 1.0;
void fragment() {
	float f = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = col.rgb * k;
	ALPHA = col.a * pow(f, 1.5);
}
"""

const WINDOWS := """
shader_type spatial;
render_mode unshaded;
global uniform vec4 cine_shadow;
uniform vec4 wall : source_color = vec4(0.2, 0.2, 0.3, 1.0);
uniform vec4 lit : source_color = vec4(1.0, 0.7, 0.3, 1.0);
uniform vec4 shade : source_color = vec4(0.32, 0.28, 0.55, 1.0);
uniform float seed = 1.0;
uniform float density = 0.45;
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233)) + seed) * 43758.5453); }
void fragment() {
	// Плоские силуэты домов: освещённая грань чуть светлее, остальные — в тени
	float side = wn.x > 0.5 ? 1.0 : (wn.z > 0.5 ? 0.8 : 0.55);
	vec3 c = wall.rgb * mix(cine_shadow.rgb, vec3(1.0), side * 0.6);
	if (abs(wn.y) < 0.5) {
		vec2 uv = abs(wn.x) > 0.5 ? wp.zy : wp.xy;
		vec2 g = uv * vec2(1.4, 1.1);
		vec2 cc = floor(g);
		vec2 f = fract(g);
		float win = step(0.22, f.x) * step(f.x, 0.78) * step(0.28, f.y) * step(f.y, 0.82);
		float on = step(1.0 - density, h(cc));
		vec3 lc = mix(lit.rgb, vec3(0.3, 0.95, 1.0), step(0.8, h(cc + 7.0)));
		c = mix(c, lc * 1.6, win * on);
	}
	ALBEDO = c;
}
"""

const SKY := """
shader_type sky;
uniform vec3 top = vec3(0.04, 0.03, 0.12);
uniform vec3 hor = vec3(0.35, 0.16, 0.42);
uniform vec3 glowc = vec3(1.0, 0.3, 0.6);
uniform vec3 moon_dir = vec3(-0.4, 0.45, -1.0);
uniform float moon = 1.0;
uniform float rift = 0.0;
uniform float stars = 1.0;
void sky() {
	float y = EYEDIR.y;
	vec3 c = mix(hor, top, smoothstep(-0.05, 0.55, y));
	c += glowc * pow(1.0 - abs(y), 7.0) * 0.55;
	vec3 d = EYEDIR * 240.0;
	vec3 id = floor(d);
	float s = fract(sin(dot(id, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	c += vec3(step(0.9972, s) * smoothstep(0.02, 0.35, y)) * 1.6 * stars;
	float m = dot(EYEDIR, normalize(moon_dir));
	c += moon * (vec3(1.0, 0.94, 0.86) * smoothstep(0.9982, 0.9988, m) * 3.0 + vec3(0.55, 0.5, 1.0) * pow(max(m, 0.0), 160.0) * 0.7);
	if (rift > 0.0) {
		float a = atan(EYEDIR.x, EYEDIR.z);
		float l = abs(y - 0.42 - 0.07 * sin(a * 6.0 + 1.0) - 0.03 * sin(a * 19.0));
		c += vec3(1.0, 0.32, 0.8) * smoothstep(0.004, 0.0, l) * rift * 1.6;
		c += vec3(0.55, 0.25, 1.0) * smoothstep(0.05, 0.0, l) * rift * 0.35;
	}
	// Ступенчатый градиент — небо «нарисовано» плоскими полосами
	COLOR = mix(c, floor(c * 9.0 + 0.5) / 9.0, 0.7);
}
"""

const PORTAL := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 c1 : source_color = vec4(0.6, 0.2, 1.0, 1.0);
uniform vec4 c2 : source_color = vec4(1.0, 0.3, 0.7, 1.0);
uniform float speed = 1.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float sw = sin(a * 5.0 + r * 13.0 - TIME * 3.0 * speed) * 0.5 + 0.5;
	float core = smoothstep(1.0, 0.1, r);
	vec3 col = mix(c1.rgb, c2.rgb, sw) * core * (0.5 + 0.6 * sw) + vec3(1.0) * smoothstep(0.3, 0.0, r) * 0.8;
	ALBEDO = col * 1.6;
	ALPHA = core * step(r, 1.0);
}
"""

const LAVA := """
shader_type spatial;
render_mode unshaded;
uniform vec4 c1 : source_color = vec4(1.0, 0.35, 0.05, 1.0);
uniform vec4 c2 : source_color = vec4(1.0, 0.85, 0.3, 1.0);
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wp.xz * 0.6;
	float n = sin(p.x * 2.1 + TIME * 0.6) * sin(p.y * 1.7 - TIME * 0.4) + sin((p.x + p.y) * 3.3 + TIME) * 0.5;
	float k = smoothstep(-0.4, 1.0, n);
	ALBEDO = mix(c1.rgb * 0.7, c2.rgb, k) * 2.2;
}
"""

static var _cache := {}


## Глобальные параметры аниме-заливки (регистрируются один раз).
static func ensure_globals() -> void:
	if _cache.has("globals"):
		return
	_cache["globals"] = true
	var have := RenderingServer.global_shader_parameter_get_list()
	var defs := {
		"cine_key_dir": [RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(0.4, 0.8, 0.5)],
		"cine_key_col": [RenderingServer.GLOBAL_VAR_TYPE_COLOR, Color(1, 0.95, 0.9)],
		"cine_shadow": [RenderingServer.GLOBAL_VAR_TYPE_COLOR, Color(0.42, 0.33, 0.72)],
		"cine_rim": [RenderingServer.GLOBAL_VAR_TYPE_COLOR, Color(0.2, 0.95, 1.0, 1.0)],
		"cine_pt": [RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(0, 0, 0, 0)],
		"cine_pt_col": [RenderingServer.GLOBAL_VAR_TYPE_COLOR, Color(1, 0.6, 0.3, 0.0)],
	}
	for n in defs:
		if not (StringName(n) in have):
			RenderingServer.global_shader_parameter_add(n, defs[n][0], defs[n][1])


static func shader(code_name: String) -> Shader:
	if _cache.has("sh_" + code_name):
		return _cache["sh_" + code_name]
	ensure_globals()
	var sh := Shader.new()
	match code_name:
		"cel": sh.code = CEL
		"outline": sh.code = OUTLINE
		"neonflat": sh.code = NEON_FLAT
		"toon": sh.code = TOON
		"glass": sh.code = GLASS
		"glow": sh.code = GLOW
		"windows": sh.code = WINDOWS
		"sky": sh.code = SKY
		"portal": sh.code = PORTAL
		"lava": sh.code = LAVA
	_cache["sh_" + code_name] = sh
	return sh


## Аниме-материал: плоская заливка + жёсткая тень + контур.
static func cel(c: Color, opts := {}) -> Material:
	var key := "cel_%s_%s" % [c.to_html(), str(opts)]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = shader("cel")
	m.set_shader_parameter("albedo", c)
	for k in ["flat_k", "skin", "hair", "gloss", "tone", "glow"]:
		if opts.has(k):
			m.set_shader_parameter(k, float(opts[k]))
	var w := float(opts.get("line", 1.8))
	if w > 0.0:
		var o := ShaderMaterial.new()
		o.shader = shader("outline")
		o.set_shader_parameter("width_px", w)
		m.next_pass = o
	_cache[key] = m
	return m


static func mat(c: Color, glow := 0.0, gloss := 0.25, rim := 0.16) -> Material:
	if glow > 0.0:
		return neon(c, glow)
	return cel(c, {"gloss": 1.0 if gloss >= 0.6 else 0.0, "line": 2.2})


static func neon(c: Color, k := 2.5) -> Material:
	var key := "neon_%s_%.2f" % [c.to_html(), k]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = shader("neonflat")
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("k", 1.0 + k * 0.5)
	_cache[key] = m
	return m


## Материалы слотов модели из Blender в аниме-заливке.
static func slot(name: String, S: Dictionary, line := 2.0) -> Material:
	var col := func(k: String, d: Color) -> Color:
		return S[k] if S.has(k) and S[k] is Color else d
	var main_c: Color = col.call("main", Color(0.4, 0.4, 0.5))
	match name:
		"skin":
			return cel(col.call("skin", Color(0.95, 0.78, 0.68)), {"skin": 1.0, "tone": 0.0, "line": line})
		"main":
			return cel(main_c, {"line": line})
		"main2":
			return cel(main_c.darkened(0.18), {"line": line})
		"glove":
			return cel(main_c.darkened(0.5), {"gloss": 0.5, "line": line})
		"legs":
			return cel(col.call("legs", Color(0.25, 0.25, 0.3)), {"line": line})
		"boots":
			return cel(col.call("boots", Color(0.2, 0.15, 0.12)), {"gloss": 0.5, "line": line})
		"trim":
			return cel(col.call("trim", Color(0.9, 0.7, 0.3)), {"gloss": 1.0, "line": line})
		"metal":
			return cel(Color(0.62, 0.64, 0.72), {"gloss": 1.0, "line": line})
		"weapon":
			return cel(col.call("w_c", Color(0.5, 0.5, 0.6)), {"gloss": 1.0, "line": line})
		"neon", "visor":
			return neon(col.call("neon", Color(0.3, 0.9, 1.0)), 3.0)
		"neon2":
			return neon(col.call("neon2", Color(1.0, 0.3, 0.7)), 3.0)
		"gem":
			return neon(col.call("gem", Color(0.4, 0.9, 1.0)), 3.0)
		"hair", "beard":
			var hc: Color = col.call("beard" if name == "beard" and S.has("beard") else "hair", Color(0.25, 0.17, 0.12))
			return cel(hc, {"hair": 1.0, "tone": 0.6, "line": line})
		"hat":
			return cel(col.call("head_c", Color(0.3, 0.3, 0.4)), {"line": line})
		"back":
			return cel(col.call("back_c", Color(0.3, 0.2, 0.3)), {"line": line})
		"eye_white":
			return cel(Color(0.97, 0.96, 1.0), {"flat_k": 1.0, "line": 0.0})
		"iris":
			return cel(col.call("neon", Color(0.3, 0.6, 1.0)).lerp(Color.WHITE, 0.1), {"flat_k": 1.0, "line": 0.0, "glow": 0.25})
		"pupil":
			return cel(Color(0.03, 0.02, 0.05), {"flat_k": 1.0, "line": 0.0})
		"glint":
			return neon(Color(1, 1, 1), 1.2)
		"mouth":
			return cel(Color(0.25, 0.05, 0.08), {"flat_k": 1.0, "line": 0.0})
		"teeth", "bone":
			return cel(Color(0.93, 0.9, 0.84), {"line": line})
		"dark":
			return cel(Color(0.04, 0.03, 0.06), {"flat_k": 1.0, "line": 0.0})
		"leather":
			return cel(Color(0.38, 0.24, 0.15), {"line": line})
		"wood":
			return cel(Color(0.45, 0.29, 0.17), {"line": line})
		"glass":
			return glass(Color(0.7, 0.9, 1.0, 0.35), 0.5)
	return cel(main_c, {"line": line})


static func glass(c: Color, glow := 0.4) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("glass")
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("glow", glow)
	return m


static func halo(c: Color, k := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("glow")
	m.set_shader_parameter("col", c)
	m.set_shader_parameter("k", k)
	return m


static func windows(wall: Color, lit: Color, seed: float, density := 0.45) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("windows")
	m.set_shader_parameter("wall", wall)
	m.set_shader_parameter("lit", lit)
	m.set_shader_parameter("shade", wall.darkened(0.4).lerp(Color(0.3, 0.25, 0.6), 0.5))
	m.set_shader_parameter("seed", seed)
	m.set_shader_parameter("density", density)
	return m


static func portal(c1: Color, c2: Color, speed := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("portal")
	m.set_shader_parameter("c1", c1)
	m.set_shader_parameter("c2", c2)
	m.set_shader_parameter("speed", speed)
	return m


static func lava() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("lava")
	return m


# ---------- Меши ----------

static func mi(mesh: Mesh, m: Material, parent: Node3D, pos := Vector3.ZERO, scl := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = m
	n.position = pos
	n.scale = scl
	n.rotation = rot
	parent.add_child(n)
	return n


static func sphere(r: float, seg := 20) -> SphereMesh:
	var key := "sp_%.3f_%d" % [r, seg]
	if _cache.has(key):
		return _cache[key]
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = maxi(6, seg / 2)
	_cache[key] = s
	return s


static func capsule(r: float, h: float) -> CapsuleMesh:
	var key := "cap_%.3f_%.3f" % [r, h]
	if _cache.has(key):
		return _cache[key]
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0 + 0.001)
	c.radial_segments = 16
	c.rings = 6
	_cache[key] = c
	return c


static func box(x: float, y: float, z: float) -> BoxMesh:
	var key := "bx_%.3f_%.3f_%.3f" % [x, y, z]
	if _cache.has(key):
		return _cache[key]
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	_cache[key] = b
	return b


static func cyl(r_top: float, r_bot: float, h: float, seg := 16) -> CylinderMesh:
	var key := "cy_%.3f_%.3f_%.3f_%d" % [r_top, r_bot, h, seg]
	if _cache.has(key):
		return _cache[key]
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	_cache[key] = c
	return c


static func torus(ri: float, ro: float) -> TorusMesh:
	var key := "to_%.3f_%.3f" % [ri, ro]
	if _cache.has(key):
		return _cache[key]
	var t := TorusMesh.new()
	t.inner_radius = ri
	t.outer_radius = ro
	t.rings = 48
	t.ring_segments = 12
	_cache[key] = t
	return t


static func prism(x: float, y: float, z: float) -> PrismMesh:
	var p := PrismMesh.new()
	p.size = Vector3(x, y, z)
	return p
