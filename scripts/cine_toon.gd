extends RefCounted
## Материалы кат-сцен в духе анимационных роликов: мягкий «мультяшный» свет
## с цветными тенями (тени не серые, а сиренево-синие), ровный блик и контровая
## подсветка по краю силуэта. Плюс небо, окна, порталы и лава.

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
	ALBEDO = wall.rgb;
	ROUGHNESS = 0.85;
	if (abs(wn.y) < 0.5) {
		vec2 uv = abs(wn.x) > 0.5 ? wp.zy : wp.xy;
		vec2 g = uv * vec2(1.4, 1.1);
		vec2 c = floor(g);
		vec2 f = fract(g);
		float win = step(0.22, f.x) * step(f.x, 0.78) * step(0.28, f.y) * step(f.y, 0.82);
		float on = step(1.0 - density, h(c));
		vec3 lc = mix(lit.rgb, vec3(0.4, 0.9, 1.0), step(0.85, h(c + 7.0)));
		EMISSION = lc * win * on * 1.3;
		ALBEDO = mix(wall.rgb, wall.rgb * 0.5, win);
	}
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
	COLOR = c;
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


static func shader(code_name: String) -> Shader:
	if _cache.has("sh_" + code_name):
		return _cache["sh_" + code_name]
	var sh := Shader.new()
	match code_name:
		"toon": sh.code = TOON
		"glass": sh.code = GLASS
		"glow": sh.code = GLOW
		"windows": sh.code = WINDOWS
		"sky": sh.code = SKY
		"portal": sh.code = PORTAL
		"lava": sh.code = LAVA
	_cache["sh_" + code_name] = sh
	return sh


## Стилизованный PBR-материал, как в анимационных роликах: мягкая шероховатость,
## контровая кайма света, металл с отражениями. glow > 0 — светится (неон).
static func mat(c: Color, glow := 0.0, gloss := 0.25, rim := 0.16) -> Material:
	var key := "m_%s_%.2f_%.2f_%.2f" % [c.to_html(), glow, gloss, rim]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = clampf(0.85 - gloss * 0.9, 0.18, 0.9)
	m.metallic = 0.75 if gloss >= 0.6 else 0.0
	m.metallic_specular = 0.45
	m.rim_enabled = rim > 0.0
	m.rim = clampf(rim * 1.6, 0.0, 1.0)
	m.rim_tint = 0.6
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow * 1.3
	_cache[key] = m
	return m


static func neon(c: Color, k := 2.5) -> Material:
	return mat(c, k, 0.0, 0.0)


## Материалы слотов модели из Blender: кожа с подповерхностным рассеянием,
## ткань, кожа-материал, металл, неон, глаза.
static func slot(name: String, S: Dictionary) -> Material:
	var key := "slot_%s_%s" % [name, str(S.get("_key", ""))]
	if _cache.has(key):
		return _cache[key]
	var col := func(k: String, d: Color) -> Color:
		return S[k] if S.has(k) and S[k] is Color else d
	var m := StandardMaterial3D.new()
	m.roughness = 0.75
	m.rim_enabled = true
	m.rim = 0.25
	m.rim_tint = 0.65
	var main_c: Color = col.call("main", Color(0.4, 0.4, 0.5))
	match name:
		"skin":
			m.albedo_color = col.call("skin", Color(0.85, 0.68, 0.58))
			m.roughness = 0.52
			m.subsurf_scatter_enabled = true
			m.subsurf_scatter_strength = 0.45
			m.subsurf_scatter_skin_mode = true
			m.rim = 0.35
			m.rim_tint = 0.5
		"main":
			m.albedo_color = main_c
			m.roughness = 0.78
		"main2":
			m.albedo_color = main_c.darkened(0.18)
			m.roughness = 0.8
		"glove":
			m.albedo_color = main_c.darkened(0.5)
			m.roughness = 0.5
		"legs":
			m.albedo_color = col.call("legs", Color(0.25, 0.25, 0.3))
			m.roughness = 0.8
		"boots":
			m.albedo_color = col.call("boots", Color(0.2, 0.15, 0.12))
			m.roughness = 0.45
		"trim":
			m.albedo_color = col.call("trim", Color(0.9, 0.7, 0.3))
			m.metallic = 0.85
			m.roughness = 0.3
		"metal":
			m.albedo_color = Color(0.62, 0.64, 0.72)
			m.metallic = 0.9
			m.roughness = 0.28
		"weapon":
			m.albedo_color = col.call("w_c", Color(0.5, 0.5, 0.6))
			m.metallic = 0.6
			m.roughness = 0.35
		"neon", "neon2", "gem", "visor":
			var nc: Color = col.call({"neon": "neon", "neon2": "neon2", "gem": "gem", "visor": "neon"}[name], Color(0.3, 0.9, 1.0))
			m.albedo_color = nc
			m.emission_enabled = true
			m.emission = nc
			m.emission_energy_multiplier = 3.2 if name != "visor" else 2.2
			m.rim_enabled = false
			if name == "visor":
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.albedo_color.a = 0.75
		"hair", "beard":
			m.albedo_color = col.call("beard" if name == "beard" and S.has("beard") else "hair", Color(0.25, 0.17, 0.12))
			m.roughness = 0.42
			m.metallic_specular = 0.7
			m.rim = 0.45
		"hat":
			m.albedo_color = col.call("head_c", Color(0.3, 0.3, 0.4))
			m.roughness = 0.7
		"back":
			m.albedo_color = col.call("back_c", Color(0.3, 0.2, 0.3))
			m.roughness = 0.82
		"eye_white":
			m.albedo_color = Color(0.96, 0.95, 0.97)
			m.roughness = 0.12
			m.clearcoat_enabled = true
			m.rim_enabled = false
		"iris":
			var ic: Color = col.call("neon", Color(0.3, 0.6, 1.0))
			m.albedo_color = ic.darkened(0.2)
			m.emission_enabled = true
			m.emission = ic
			m.emission_energy_multiplier = 0.35
			m.roughness = 0.1
			m.clearcoat_enabled = true
			m.rim_enabled = false
		"pupil":
			m.albedo_color = Color(0.02, 0.02, 0.03)
			m.roughness = 0.05
			m.rim_enabled = false
		"mouth":
			m.albedo_color = Color(0.3, 0.07, 0.09)
			m.roughness = 0.6
			m.rim_enabled = false
		"teeth", "bone":
			m.albedo_color = Color(0.92, 0.89, 0.82)
			m.roughness = 0.4
		"dark":
			m.albedo_color = Color(0.05, 0.045, 0.06)
			m.roughness = 0.5
		"leather":
			m.albedo_color = Color(0.35, 0.22, 0.14)
			m.roughness = 0.55
		"wood":
			m.albedo_color = Color(0.42, 0.27, 0.16)
			m.roughness = 0.7
		"glass":
			m.albedo_color = Color(0.7, 0.85, 0.95, 0.3)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.05
		_:
			m.albedo_color = main_c
	_cache[key] = m
	return m


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
