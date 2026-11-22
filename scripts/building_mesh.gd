extends RefCounted
## Скошенные кромки дают кладке и металлическим панелям собственные блики.

static var _boxes: Dictionary[Vector3, Mesh] = {}


static func box(size: Vector3) -> Mesh:
	if _boxes.has(size):
		return _boxes[size]
	var narrow := minf(size.x, minf(size.y, size.z))
	var wide := maxf(size.x, maxf(size.y, size.z))
	if narrow < 0.12 or wide < 0.55:
		var plain := BoxMesh.new()
		plain.size = size
		_boxes[size] = plain
	else:
		_boxes[size] = _beveled_box(size * 0.5, minf(0.075, narrow * 0.22))
	return _boxes[size]


static func _ring(x: float, y: float, z: float, corner: float) -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(-x + corner, y, -z), Vector3(x - corner, y, -z),
		Vector3(x, y, -z + corner), Vector3(x, y, z - corner),
		Vector3(x - corner, y, z), Vector3(-x + corner, y, z),
		Vector3(-x, y, z - corner), Vector3(-x, y, -z + corner),
	])


static func _beveled_box(half: Vector3, edge: float) -> ArrayMesh:
	var inset := edge * 0.5
	var rings := [
		_ring(half.x - inset, -half.y, half.z - inset, inset),
		_ring(half.x, -half.y + edge, half.z, edge),
		_ring(half.x, half.y - edge, half.z, edge),
		_ring(half.x - inset, half.y, half.z - inset, inset),
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in 3:
		var lower: PackedVector3Array = rings[j]
		var upper: PackedVector3Array = rings[j + 1]
		for i in 8:
			var next := (i + 1) % 8
			_triangle(st, lower[i], lower[next], upper[i])
			_triangle(st, upper[i], lower[next], upper[next])
	for i in range(1, 7):
		_triangle(st, rings[0][0], rings[0][i], rings[0][i + 1])
		_triangle(st, rings[3][0], rings[3][i], rings[3][i + 1])
	return st.commit()


static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	var vertices: PackedVector3Array
	if normal.dot(a + b + c) > 0.0:
		vertices = PackedVector3Array([a, c, b])
	else:
		normal = -normal
		vertices = PackedVector3Array([a, b, c])
	for p in vertices:
		st.set_normal(normal)
		st.set_uv(Vector2(p.x, p.z) if absf(normal.y) > 0.5 else Vector2(p.x + p.z, -p.y))
		st.add_vertex(p)
