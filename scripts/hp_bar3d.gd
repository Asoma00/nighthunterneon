extends MeshInstance3D
## Объёмная полоса здоровья над элитным врагом, алтарём или боссом.
## Висит в 3D над головой и всегда смотрит в камеру, а не лежит на полу.

const SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, blend_mix, shadows_disabled;
uniform float fill = 1.0;
uniform float ghost = 1.0;
uniform float flash = 0.0;
uniform vec4 col : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform float aspect = 7.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 uv = UV;
	float bx = 0.06 / aspect * 2.0;
	float by = 0.18;
	vec3 c = vec3(0.04, 0.02, 0.08);
	float a = 0.92;
	if (uv.x > bx && uv.x < 1.0 - bx && uv.y > by && uv.y < 1.0 - by) {
		float t = (uv.x - bx) / (1.0 - 2.0 * bx);
		float v = (uv.y - by) / (1.0 - 2.0 * by);
		// объём: блик сверху, тень снизу
		float shade = 1.25 - v * 0.7 + smoothstep(0.25, 0.0, v) * 0.6;
		if (t < fill) {
			c = col.rgb * shade * 1.6 + vec3(flash);
		} else if (t < ghost) {
			c = vec3(1.0, 0.95, 0.85) * (0.9 * shade);
		} else {
			c = vec3(0.16, 0.05, 0.12) * shade;
		}
		// тонкие деления по 10%
		if (fract(t * 10.0) < 0.012 * aspect / 7.0 * 10.0 && t > 0.01) c *= 0.55;
	}
	ALBEDO = c;
	ALPHA = a;
}
"""

static var _shader: Shader

var target: Node2D
var height := 1.2
var _main: Node
var _mat: ShaderMaterial
var _ghost := 1.0
var _shown := 1.0
var _flash := 0.0


static func attach(main: Node, enemy: Node2D, h: float, width: float, color: Color) -> Node3D:
	var root = main.get("_mirror_root")
	if root == null or not is_instance_valid(root):
		return null
	var b = load("res://scripts/hp_bar3d.gd").new()
	b._main = main
	b.target = enemy
	b.height = h
	var q := QuadMesh.new()
	q.size = Vector2(width, width / 7.0)
	b.mesh = q
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	b._mat = ShaderMaterial.new()
	b._mat.shader = _shader
	b._mat.set_shader_parameter("col", color)
	b._mat.render_priority = 18
	b.material_override = b._mat
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(b)
	b._follow(0.0)
	return b


func _process(delta: float) -> void:
	_follow(delta)


func _follow(delta: float) -> void:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		queue_free()
		return
	var mx: float = maxf(1.0, float(target.get("max_hp")))
	var f: float = clampf(float(target.get("hp")) / mx, 0.0, 1.0)
	if f < _shown - 0.001:
		_flash = 0.6
	_shown = f
	# «призрачная» часть отстаёт, показывая только что снятый урон
	_ghost = maxf(f, _ghost - delta * 0.6) if delta > 0.0 else f
	_flash = maxf(0.0, _flash - delta * 4.0)
	_mat.set_shader_parameter("fill", f)
	_mat.set_shader_parameter("ghost", _ghost)
	_mat.set_shader_parameter("flash", _flash)
	visible = target.visible and target.modulate.a > 0.3
	position = _main._bl(target.position, height)
