# Рендер аниме-роликов «Ночь охотника: Неон» в духе Cyberpunk: Edgerunners.
# blender -b -P anime_video.py -- specs.json scenes.json out_dir СЦЕНА [--test N] [--res 1280x720]
# Плоская заливка «на двух тонах» (Shader to RGB + постеризация цветного света),
# жирный контур Freestyle, кислотная палитра, свечение неона, расслоение цвета,
# кадры-вспышки, линии скорости, глитч на склейках. 12 кадров/с — «на двойках».

import bpy, bmesh, json, math, sys, os, random
from mathutils import Vector, Matrix, Euler, Quaternion

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_cine as BC

argv = sys.argv[sys.argv.index("--") + 1:]
SPECS = json.load(open(argv[0]))
DATA = json.load(open(argv[1]))
OUT = argv[2]
SCENE_ID = argv[3]
TEST = 0
RES = (1280, 720)
if "--test" in argv:
    TEST = int(argv[argv.index("--test") + 1])
if "--res" in argv:
    w, h = argv[argv.index("--res") + 1].split("x")
    RES = (int(w), int(h))
FPS = 12
os.makedirs(OUT, exist_ok=True)

YELLOW = (0.99, 0.93, 0.04)
CYAN = (0.0, 0.94, 1.0)
MAGENTA = (1.0, 0.0, 0.42)
LINE = (0.04, 0.015, 0.07)


def G(v):
    """Координаты сценария (Godot: Y вверх, вперёд +Z) → Blender (Z вверх, вперёд −Y)."""
    return Vector((v[0], -v[2], v[1]))


# ================= Материалы =================

PAL = {"shadow": (0.42, 0.3, 0.72)}


def node_mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    return m, nt


def cel(name, base, gloss=False, shadow=None, flat=False):
    """Аниме-заливка: свет постеризуется до 2–3 ступеней, тень — цветная."""
    m, nt = node_mat(name)
    N, L = nt.nodes, nt.links
    out = N.new("ShaderNodeOutputMaterial")
    em = N.new("ShaderNodeEmission")
    L.new(em.outputs[0], out.inputs[0])
    b = (base[0], base[1], base[2], 1)
    if flat:
        em.inputs["Color"].default_value = b
        return m
    dif = N.new("ShaderNodeBsdfDiffuse")
    dif.inputs["Color"].default_value = (1, 1, 1, 1)
    s2r = N.new("ShaderNodeShaderToRGB")
    L.new(dif.outputs[0], s2r.inputs[0])
    mul = N.new("ShaderNodeVectorMath")
    mul.operation = "MULTIPLY_ADD"
    mul.inputs[1].default_value = (2.0, 2.0, 2.0)
    mul.inputs[2].default_value = (0.25, 0.25, 0.25)
    L.new(s2r.outputs[0], mul.inputs[0])
    fl = N.new("ShaderNodeVectorMath")
    fl.operation = "FLOOR"
    L.new(mul.outputs[0], fl.inputs[0])
    dv = N.new("ShaderNodeVectorMath")
    dv.operation = "SCALE"
    dv.inputs["Scale"].default_value = 0.5
    L.new(fl.outputs[0], dv.inputs[0])
    sh = shadow or PAL["shadow"]
    mx = N.new("ShaderNodeVectorMath")
    mx.operation = "MAXIMUM"
    mx.inputs[1].default_value = (sh[0], sh[1], sh[2])
    L.new(dv.outputs[0], mx.inputs[0])
    mn = N.new("ShaderNodeVectorMath")
    mn.operation = "MINIMUM"
    mn.inputs[1].default_value = (1.35, 1.35, 1.35)
    L.new(mx.outputs[0], mn.inputs[0])
    col = N.new("ShaderNodeVectorMath")
    col.operation = "MULTIPLY"
    col.inputs[1].default_value = (base[0], base[1], base[2])
    L.new(mn.outputs[0], col.inputs[0])
    last = col.outputs[0]
    if gloss:
        # Жёсткий блик: отдельная ступень по яркости света
        bw = N.new("ShaderNodeRGBToBW")
        L.new(s2r.outputs[0], bw.inputs[0])
        rp = N.new("ShaderNodeValToRGB")
        rp.color_ramp.interpolation = "CONSTANT"
        rp.color_ramp.elements[0].color = (0, 0, 0, 1)
        rp.color_ramp.elements[1].position = 0.92
        rp.color_ramp.elements[1].color = (0.35, 0.35, 0.35, 1)
        L.new(bw.outputs[0], rp.inputs[0])
        add = N.new("ShaderNodeVectorMath")
        add.operation = "ADD"
        L.new(last, add.inputs[0])
        L.new(rp.outputs[0], add.inputs[1])
        last = add.outputs[0]
    L.new(last, em.inputs["Color"])
    return m


def neon(name, c, k=4.0):
    m, nt = node_mat(name)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (c[0], c[1], c[2], 1)
    em.inputs["Strength"].default_value = k
    nt.links.new(em.outputs[0], out.inputs[0])
    m["neon"] = True
    return m


def windows_mat(name, wall, lit, seed):
    """Неоновые окна небоскрёбов — сетка «кирпичей» на всех вертикальных гранях."""
    m, nt = node_mat(name)
    N, L = nt.nodes, nt.links
    out = N.new("ShaderNodeOutputMaterial")
    em = N.new("ShaderNodeEmission")
    L.new(em.outputs[0], out.inputs[0])
    tc = N.new("ShaderNodeTexCoord")
    sep = N.new("ShaderNodeSeparateXYZ")
    L.new(tc.outputs["Object"], sep.inputs[0])
    add = N.new("ShaderNodeMath")
    add.operation = "ADD"
    L.new(sep.outputs[0], add.inputs[0])
    L.new(sep.outputs[1], add.inputs[1])
    comb = N.new("ShaderNodeCombineXYZ")
    L.new(add.outputs[0], comb.inputs[0])
    L.new(sep.outputs[2], comb.inputs[1])
    comb.inputs[2].default_value = seed
    br = N.new("ShaderNodeTexBrick")
    br.inputs["Scale"].default_value = 1.4
    br.inputs["Mortar Size"].default_value = 0.12
    br.inputs["Brick Width"].default_value = 0.6
    br.inputs["Row Height"].default_value = 0.5
    br.inputs["Color1"].default_value = (lit[0], lit[1], lit[2], 1)
    br.inputs["Color2"].default_value = (wall[0] * 0.8, wall[1] * 0.8, wall[2] * 0.8, 1)
    br.inputs["Mortar"].default_value = (wall[0], wall[1], wall[2], 1)
    br.offset = 0.0
    br.squash = 1.0
    L.new(comb.outputs[0], br.inputs["Vector"])
    st = N.new("ShaderNodeMapRange")
    L.new(br.outputs["Fac"], st.inputs[0])
    st.inputs["To Min"].default_value = 2.2
    st.inputs["To Max"].default_value = 1.0
    L.new(br.outputs["Color"], em.inputs["Color"])
    L.new(st.outputs[0], em.inputs["Strength"])
    return m


def portal_mat(name, c1, c2):
    m, nt = node_mat(name)
    N, L = nt.nodes, nt.links
    out = N.new("ShaderNodeOutputMaterial")
    em = N.new("ShaderNodeEmission")
    L.new(em.outputs[0], out.inputs[0])
    tc = N.new("ShaderNodeTexCoord")
    mp = N.new("ShaderNodeMapping")
    mp.name = "spin"
    L.new(tc.outputs["Generated"], mp.inputs[0])
    mp.inputs["Location"].default_value = (-0.5, -0.5, 0)
    wv = N.new("ShaderNodeTexWave")
    wv.wave_type = "RINGS"
    wv.rings_direction = "SPHERICAL"
    wv.inputs["Scale"].default_value = 3.0
    wv.inputs["Distortion"].default_value = 6.0
    L.new(mp.outputs[0], wv.inputs[0])
    rp = N.new("ShaderNodeValToRGB")
    rp.color_ramp.interpolation = "CONSTANT"
    rp.color_ramp.elements[0].color = (c1[0], c1[1], c1[2], 1)
    rp.color_ramp.elements[1].position = 0.5
    rp.color_ramp.elements[1].color = (c2[0], c2[1], c2[2], 1)
    e = rp.color_ramp.elements.new(0.85)
    e.color = (1, 1, 1, 1)
    L.new(wv.outputs[0], rp.inputs[0])
    L.new(rp.outputs[0], em.inputs["Color"])
    em.inputs["Strength"].default_value = 3.0
    return m


def lava_mat(name):
    m, nt = node_mat(name)
    N, L = nt.nodes, nt.links
    out = N.new("ShaderNodeOutputMaterial")
    em = N.new("ShaderNodeEmission")
    L.new(em.outputs[0], out.inputs[0])
    tc = N.new("ShaderNodeTexCoord")
    mp = N.new("ShaderNodeMapping")
    mp.name = "flow"
    L.new(tc.outputs["Object"], mp.inputs[0])
    vo = N.new("ShaderNodeTexVoronoi")
    vo.inputs["Scale"].default_value = 1.2
    L.new(mp.outputs[0], vo.inputs[0])
    rp = N.new("ShaderNodeValToRGB")
    rp.color_ramp.interpolation = "CONSTANT"
    rp.color_ramp.elements[0].color = (1.0, 0.9, 0.3, 1)
    rp.color_ramp.elements[1].position = 0.25
    rp.color_ramp.elements[1].color = (1.0, 0.35, 0.05, 1)
    L.new(vo.outputs["Distance"], rp.inputs[0])
    L.new(rp.outputs[0], em.inputs["Color"])
    em.inputs["Strength"].default_value = 3.0
    return m


def put(o, m):
    o.data.materials.clear()
    o.data.materials.append(m)
    return o


MCACHE = {}


def C(c, gloss=False):
    key = ("c", tuple(round(x, 3) for x in c), gloss)
    if key not in MCACHE:
        MCACHE[key] = cel("cel", c, gloss)
    return MCACHE[key]


def NE(c, k=4.0):
    key = ("n", tuple(round(x, 3) for x in c), k)
    if key not in MCACHE:
        MCACHE[key] = neon("neon", c, k)
    return MCACHE[key]


# ================= Декорации =================

RNG = random.Random(7)
ANIM = []      # функции f(frame, t) для «живых» деталей


def sp(r, c, loc, scl=(1, 1, 1), seg=16, rot=(0, 0, 0)):
    return put(BC.sphere("s", r, None, seg, max(6, seg // 2), loc, scl, rot), c)


def cy(r1, r2, h, c, loc, rot=(0, 0, 0), seg=16, caps=True):
    return put(BC.cyl("c", r1, r2, h, None, seg, loc, rot, caps=caps), c)


def bx(x, y, z, c, loc, rot=(0, 0, 0), bev=0.0):
    return put(BC.box("b", x, y, z, None, loc, rot, bev), c)


def to(R, r, c, loc, rot=(0, 0, 0), scl=(1, 1, 1), seg=48):
    return put(BC.torus("t", R, r, None, loc, rot, scl, seg), c)


def world(top, hor, glow, rift=0.0, moon_dir=(-0.4, 0.8, 0.45)):
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    nt = w.node_tree
    N, L = nt.nodes, nt.links
    N.clear()
    out = N.new("ShaderNodeOutputWorld")
    lp = N.new("ShaderNodeLightPath")
    amb = N.new("ShaderNodeBackground")
    amb.inputs["Color"].default_value = (0.05, 0.05, 0.08, 1)
    amb.inputs["Strength"].default_value = 1.0
    tc = N.new("ShaderNodeTexCoord")
    sep = N.new("ShaderNodeSeparateXYZ")
    L.new(tc.outputs["Window"], sep.inputs[0])
    # Ступенчатый градиент неба по высоте кадра
    rp = N.new("ShaderNodeValToRGB")
    rp.color_ramp.interpolation = "CONSTANT"
    els = rp.color_ramp.elements
    els[0].position = 0.0
    els[0].color = (hor[0], hor[1], hor[2], 1)
    els[1].position = 0.9
    els[1].color = (top[0], top[1], top[2], 1)
    for i, (p, k) in enumerate(((0.12, 0.15), (0.24, 0.32), (0.38, 0.5), (0.52, 0.68), (0.7, 0.85))):
        e = els.new(p)
        c = [hor[j] + (top[j] - hor[j]) * k for j in range(3)]
        if i == 0:
            c = [hor[j] + (glow[j] - hor[j]) * 0.35 for j in range(3)]
        e.color = (c[0], c[1], c[2], 1)
    L.new(sep.outputs[1], rp.inputs[0])
    # Звёзды
    vo = N.new("ShaderNodeTexVoronoi")
    vo.inputs["Scale"].default_value = 240.0
    L.new(tc.outputs["Generated"], vo.inputs[0])
    st = N.new("ShaderNodeMath")
    st.operation = "LESS_THAN"
    st.inputs[1].default_value = 0.035
    L.new(vo.outputs["Distance"], st.inputs[0])
    stm = N.new("ShaderNodeMath")
    stm.operation = "MULTIPLY"
    L.new(st.outputs[0], stm.inputs[0])
    L.new(sep.outputs[1], stm.inputs[1])
    addc = N.new("ShaderNodeMixRGB")
    addc.blend_type = "ADD"
    L.new(stm.outputs[0], addc.inputs[0])
    L.new(rp.outputs[0], addc.inputs[1])
    addc.inputs[2].default_value = (1, 1, 1, 1)
    sky = N.new("ShaderNodeBackground")
    L.new(addc.outputs[0], sky.inputs["Color"])
    mix = N.new("ShaderNodeMixShader")
    L.new(lp.outputs["Is Camera Ray"], mix.inputs[0])
    L.new(amb.outputs[0], mix.inputs[1])
    L.new(sky.outputs[0], mix.inputs[2])
    L.new(mix.outputs[0], out.inputs[0])
    bpy.context.scene.world = w


def moon(d, size=6.0, c=(1.0, 0.96, 0.85)):
    p = Vector(d).normalized() * 160
    sp(size, NE(c, 6.0), tuple(p), seg=24)


def ground(c, size=300):
    bpy.ops.mesh.primitive_plane_add(size=size)
    g = bpy.context.active_object
    put(g, C(c))
    g["noline"] = True
    for i in range(50):
        p = (RNG.uniform(-25, 25), RNG.uniform(-12, 25), 0)
        if Vector(p).length < 3:
            continue
        sp(RNG.uniform(0.08, 0.22), C([min(1, x * 1.3) for x in c]), p, (1, 1, 0.5), 6)


def city(at, n, width, depth, dark=False):
    for i in range(n):
        w = RNG.uniform(2.0, 4.5)
        h = RNG.uniform(6.0, 26.0)
        p = Vector(at) + Vector((RNG.uniform(-width / 2, width / 2), RNG.uniform(-depth / 2, depth / 2), h / 2))
        wall = (0.12, 0.08, 0.22) if not dark else (0.08, 0.05, 0.14)
        lit = [YELLOW, MAGENTA, CYAN][i % 3]
        b = put(BC.box("bld", w, w, h, None, tuple(p)), windows_mat("win", wall, lit, i * 3.7))
        if i % 3 == 0:
            sc = [MAGENTA, CYAN, YELLOW][(i // 3) % 3]
            bx(0.15, 0.9, h * 0.3, NE(sc, 5.0), tuple(p + Vector((w / 2 + 0.1, 0, h * 0.15))))
        if i % 4 == 1:
            cy(0.03, 0.06, 3.0, C((0.3, 0.3, 0.4)), tuple(p + Vector((0, 0, h / 2 + 1.5))), seg=6)
            sp(0.15, NE(MAGENTA, 6), tuple(p + Vector((0, 0, h / 2 + 3.0))), seg=8)


def castle(p, s):
    stone = (0.45, 0.4, 0.58)
    h = RNG.uniform(8, 14) * s
    cy(1.4 * s, 1.6 * s, h, C(stone), (p[0], p[1], h / 2), seg=14)
    for i in range(8):
        a = 2 * math.pi * i / 8
        bx(0.5 * s, 0.5 * s, 0.6 * s, C(stone), (p[0] + math.cos(a) * 1.45 * s, p[1] + math.sin(a) * 1.45 * s, h + 0.3 * s))
    cy(1.8 * s, 0.0, 3.5 * s, C((0.42, 0.18, 0.55)), (p[0], p[1], h + 2.3 * s), seg=14)
    bx(0.5 * s, 0.1, 0.9 * s, NE(YELLOW, 4), (p[0], p[1] - 1.55 * s, h * 0.7))
    to(1.65 * s, 0.07 * s, NE(CYAN, 4), (p[0], p[1], h * 0.45))


def island(p, s):
    cy(s, 0.2, s * 2.2, C((0.38, 0.26, 0.36)), (p[0], p[1], p[2] - s * 1.1), seg=9)
    cy(s * 1.05, s, 0.4, C((0.25, 0.55, 0.42)), (p[0], p[1], p[2] + 0.1), seg=9)
    tree((p[0] + s * 0.3, p[1], p[2] + 0.2), s * 0.5)


def tree(p, s):
    cy(0.15 * s, 0.25 * s, 2.2 * s, C((0.38, 0.22, 0.22)), (p[0], p[1], p[2] + 1.1 * s), seg=8)
    leaf = RNG.choice([(0.1, 0.55, 0.5), (0.15, 0.45, 0.55), (0.35, 0.2, 0.55)])
    sp(1.2 * s, C(leaf), (p[0], p[1], p[2] + 2.6 * s), seg=12)
    sp(0.9 * s, C([min(1, x * 1.2) for x in leaf]), (p[0] + 0.6 * s, p[1] - 0.2 * s, p[2] + 3.2 * s), seg=12)
    sp(0.8 * s, C([x * 0.85 for x in leaf]), (p[0] - 0.6 * s, p[1] + 0.2 * s, p[2] + 3.0 * s), seg=12)


def house(p, s):
    bx(3.0 * s, 2.6 * s, 2.2 * s, C((0.62, 0.45, 0.4)), (p[0], p[1], 1.1 * s))
    pr = BC.box("roof", 3.4 * s, 2.9 * s, 0.1, None, (p[0], p[1], 2.2 * s))
    bm = bmesh.new()
    bm.from_mesh(pr.data)
    for v in bm.verts:
        if v.co.z > 2.2 * s:
            v.co.y = p[1]
            v.co.z = 3.5 * s
    bm.to_mesh(pr.data)
    bm.free()
    put(pr, C((0.62, 0.15, 0.3)))
    bx(0.7 * s, 0.08, 1.2 * s, C((0.3, 0.18, 0.14)), (p[0], p[1] - 1.31 * s, 0.6 * s))
    bx(0.6 * s, 0.06, 0.5 * s, NE(YELLOW, 3.5), (p[0] + 0.9 * s, p[1] - 1.31 * s, 1.4 * s))
    bx(3.0 * s, 0.06, 0.06, NE(CYAN, 4), (p[0], p[1] - 1.32 * s, 2.2 * s))


def wall(y, w):
    cnt = int(w / 1.6)
    for i in range(cnt):
        x = -w / 2 + i * 1.6
        bx(1.5, 0.9, 3.4, C((0.42, 0.42, 0.55)), (x, y, 1.7))
        bx(1.5, 0.1, 0.08, NE(CYAN, 4), (x, y - 0.46, 2.4))
        if i % 4 == 0:
            cy(0.4, 0.5, 4.6, C((0.35, 0.35, 0.46)), (x, y - 0.1, 2.3), seg=8)
            sp(0.25, NE(YELLOW, 5), (x, y - 0.1, 4.8), seg=8)


def lantern(p):
    cy(0.04, 0.05, 2.2, C((0.2, 0.18, 0.24)), (p[0], p[1], 1.1), seg=6)
    sp(0.16, NE(YELLOW, 5), (p[0], p[1], 2.25), seg=10)


def fire(p):
    for i in range(5):
        a = 2 * math.pi * i / 5
        cy(0.08, 0.08, 1.1, C((0.42, 0.24, 0.16)), (p[0] + math.cos(a) * 0.25, p[1] + math.sin(a) * 0.25, 0.12), (math.pi / 2 - 0.3, 0, a + math.pi / 2), seg=6)
    for i in range(8):
        a = 2 * math.pi * i / 8
        sp(0.18, C((0.5, 0.45, 0.55)), (p[0] + math.cos(a) * 0.7, p[1] + math.sin(a) * 0.7, 0.08), seg=6)
    f1 = cy(0.35, 0.0, 1.1, NE((1.0, 0.45, 0.08), 5), (p[0], p[1], 0.65), seg=8)
    f2 = cy(0.22, 0.0, 0.8, NE((1.0, 0.92, 0.3), 6), (p[0] + 0.05, p[1], 0.55), seg=8)
    for f in (f1, f2):
        f["noline"] = True
    L = bpy.data.lights.new("fire", "POINT")
    L.color = (1.0, 0.5, 0.2)
    L.energy = 450
    L.shadow_soft_size = 0.2
    lo = bpy.data.objects.new("fire", L)
    lo.location = (p[0], p[1], 1.0)
    bpy.context.scene.collection.objects.link(lo)

    def flick(f, t, f1=f1, f2=f2, lo=lo):
        k = 1.0 + math.sin(t * 17.0) * 0.08 + math.sin(t * 7.3) * 0.1 + RNG.uniform(-0.05, 0.05)
        for o in (f1, f2):
            o.scale = (1 / math.sqrt(k), 1 / math.sqrt(k), k)
            o.keyframe_insert("scale", frame=f)
        lo.data.energy = 450 * k
        lo.data.keyframe_insert("energy", frame=f)
    ANIM.append(flick)


def gate(p, r, c1, c2):
    to(r, r * 0.08, C((0.3, 0.26, 0.4), True), (p[0], p[1], p[2] + r + 0.3), (math.pi / 2, 0, 0))
    ring = to(r * 0.88, r * 0.025, NE(c2, 5), (p[0], p[1] - 0.2, p[2] + r + 0.3), (math.pi / 2, 0, 0))
    runes = []
    for i in range(12):
        a = 2 * math.pi * i / 12
        runes.append(bx(r * 0.12, 0.2, r * 0.22, NE(c1, 5), (p[0] + math.cos(a) * r, p[1] - 0.25, p[2] + r + 0.3 + math.sin(a) * r), (0, -a, 0)))
    bpy.ops.mesh.primitive_circle_add(vertices=48, radius=r * 0.86, fill_type="NGON", location=(p[0], p[1] - 0.05, p[2] + r + 0.3), rotation=(math.pi / 2, 0, 0))
    disk = bpy.context.active_object
    pm = portal_mat("portal", c1, c2)
    put(disk, pm)
    disk["noline"] = True
    for sx in (-1, 1):
        bx(r * 0.3, r * 0.4, r * 0.6, C((0.28, 0.24, 0.38)), (p[0] + sx * r * 0.85, p[1], p[2] + r * 0.3))

    def spin(f, t, pm=pm):
        mp = pm.node_tree.nodes["spin"]
        mp.inputs["Rotation"].default_value = (0, 0, -t * 2.5)
        mp.inputs["Rotation"].keyframe_insert("default_value", frame=f)
    ANIM.append(spin)


def rock(p, s):
    sp(s, C((0.32, 0.24, 0.38)), p, (1, 0.9, 0.7), 7, (0, 0, RNG.random() * 6))
    if RNG.random() < 0.4:
        sp(s * 0.3, NE(MAGENTA, 5), (p[0], p[1], p[2] + s * 0.6), (0.6, 0.6, 1.6), 4)


def platform(c, ne):
    cy(14.0, 13.0, 1.5, C(c), (0, 2, -0.75), seg=48)
    to(13.8, 0.12, NE(ne, 5), (0, 2, 0.0))
    to(5.1, 0.08, NE(ne, 4), (0, 2, 0.01))
    for i in range(10):
        a = 2 * math.pi * i / 10 + 0.3
        if math.sin(a) > 0.6:
            continue
        h = RNG.uniform(1.0, 5.0)
        pp = (math.cos(a) * 12.0, 2 - math.sin(a) * 12.0, h / 2)
        cy(0.55, 0.65, h, C([min(1, x * 1.15) for x in c]), pp, seg=10)


def sky_rings(c, y=5.0):
    rings = []
    for i in range(3):
        rg = to(9.0 + i * 3.5, 0.08, NE(c, 4), (0, y, 9 + i * 3), (0.35 * (i - 1), 0.2 * i, 0), seg=64)
        rg["noline"] = True
        rings.append(rg)

    def rot(f, t, rings=rings):
        for i, rg in enumerate(rings):
            rg.rotation_euler[2] = t * 0.08 * (1 + i) * (-1 if i % 2 else 1)
            rg.keyframe_insert("rotation_euler", frame=f)
    ANIM.append(rot)


def build_set(name):
    global PAL
    RNG.seed(hash(name) % 1000)
    PAL = {"shadow": (0.42, 0.3, 0.72), "key": (1.0, 0.95, 0.9), "rim": CYAN}
    if name == "fusion":
        PAL = {"shadow": (0.5, 0.28, 0.75), "key": (1.0, 0.92, 0.85), "rim": YELLOW}
        world((0.05, 0.02, 0.16), (1.0, 0.1, 0.55), (1.0, 0.6, 0.2))
        moon((-0.5, 1.0, 0.55))
        ground((0.18, 0.12, 0.28))
        city((0, 30, 0), 30, 60.0, 34.0)
        for i in range(6):
            castle((-30 + i * 12 + RNG.uniform(-3, 3), 22 + RNG.uniform(0, 18)), RNG.uniform(0.8, 1.5))
        for i in range(7):
            island((RNG.uniform(-35, 35), RNG.uniform(25, 60), RNG.uniform(14, 26)), RNG.uniform(1.5, 3.5))
    elif name == "gate":
        PAL = {"shadow": (0.45, 0.22, 0.6), "key": (1.0, 0.85, 0.95), "rim": MAGENTA}
        world((0.06, 0.01, 0.12), (0.85, 0.05, 0.4), (1.0, 0.3, 0.6))
        moon((0.6, 1.0, 0.4), 5, (1.0, 0.75, 0.9))
        ground((0.22, 0.12, 0.24))
        gate((0, 16, 0), 7.0, (0.6, 0.15, 1.0), MAGENTA)
        for i in range(14):
            a = RNG.uniform(-1.2, 1.2)
            rock((math.sin(a) * RNG.uniform(8, 22), 16 - math.cos(a) * RNG.uniform(4, 14), 0), RNG.uniform(0.6, 2.0))
        city((0, 45, 0), 16, 70.0, 10.0, True)
    elif name == "camp":
        PAL = {"shadow": (0.3, 0.28, 0.62), "key": (0.85, 0.9, 1.0), "rim": CYAN}
        world((0.02, 0.02, 0.1), (0.2, 0.12, 0.45), (0.3, 0.6, 1.0))
        moon((-0.4, 1.0, 0.6), 5, (0.75, 0.85, 1.0))
        ground((0.16, 0.2, 0.22))
        fire((0, 0, 0))
        wall(11, 26.0)
        for i in range(5):
            house((-12 + i * 6 + RNG.uniform(-1, 1), 6.5 + RNG.uniform(0, 2)), RNG.uniform(0.9, 1.3))
        for i in range(10):
            sx = -1 if i % 2 == 0 else 1
            tree((sx * RNG.uniform(9, 18), RNG.uniform(-3, 10), 0), RNG.uniform(0.8, 1.3))
        for i in range(6):
            lantern((-7 + i * 2.8, 3.5))
        gate((10, 24, 0), 3.0, (0.6, 0.15, 1.0), MAGENTA)
        city((0, 50, 0), 12, 80.0, 6.0, True)
    elif name == "tower":
        PAL = {"shadow": (0.2, 0.42, 0.62), "key": (0.92, 1.0, 1.0), "rim": MAGENTA}
        world((0.02, 0.04, 0.12), (0.0, 0.55, 0.65), (0.3, 1.0, 0.9))
        moon((0.2, 1.0, 0.6), 6, (0.85, 1.0, 1.0))
        platform((0.2, 0.22, 0.32), CYAN)
        sky_rings(CYAN)
        city((0, 60, -30), 22, 120.0, 20.0, True)
    elif name == "foundry":
        PAL = {"shadow": (0.55, 0.2, 0.3), "key": (1.0, 0.8, 0.55), "rim": YELLOW}
        world((0.08, 0.01, 0.03), (0.75, 0.15, 0.04), (1.0, 0.5, 0.1))
        moon((0, 1.0, 0.5), 5, (1.0, 0.6, 0.3))
        ground((0.22, 0.13, 0.12))
        lm = lava_mat("lava")
        for i in range(4):
            bpy.ops.mesh.primitive_plane_add(size=1, location=(-10 + i * 7, 6 + RNG.uniform(0, 8), 0.03))
            lv = bpy.context.active_object
            lv.scale = (RNG.uniform(4, 8), RNG.uniform(3, 6), 1)
            put(lv, lm)
            lv["noline"] = True
            L = bpy.data.lights.new("lava", "POINT")
            L.color = (1.0, 0.45, 0.1)
            L.energy = 900
            lo = bpy.data.objects.new("lava", L)
            lo.location = (lv.location.x, lv.location.y, 1.5)
            bpy.context.scene.collection.objects.link(lo)
        for i in range(6):
            h = RNG.uniform(10, 20)
            x, y = -18 + i * 7, 20 + RNG.uniform(0, 8)
            cy(1.0, 1.4, h, C((0.32, 0.18, 0.2)), (x, y, h / 2), seg=12)
            to(1.1, 0.12, NE((1.0, 0.45, 0.1), 5), (x, y, h))

        def flow(f, t, lm=lm):
            mp = lm.node_tree.nodes["flow"]
            mp.inputs["Location"].default_value = (t * 0.15, t * 0.1, 0)
            mp.inputs["Location"].keyframe_insert("default_value", frame=f)
        ANIM.append(flow)
    elif name == "citadel":
        PAL = {"shadow": (0.32, 0.38, 0.72), "key": (0.97, 0.98, 1.0), "rim": MAGENTA}
        world((0.02, 0.02, 0.08), (0.2, 0.45, 0.75), (0.7, 0.95, 1.0))
        moon((0, 1.0, 0.6), 7, (0.9, 0.97, 1.0))
        platform((0.5, 0.52, 0.66), CYAN)
        gate((0, 13, 0), 9.0, (0.4, 0.9, 1.0), MAGENTA)
        for i in range(10):
            a = 2 * math.pi * i / 10
            s = RNG.uniform(2.0, 5.0)
            cy(s * 0.35, 0.0, s * 2.4, NE((0.55, 0.9, 1.0), 2.5), (math.cos(a) * 18, 8 - math.sin(a) * 14, s * 1.2 - 2), seg=6)
        city((0, 70, -30), 22, 140.0, 24.0, True)
    # Свет: ключевой «солнечный» и цветная контровая подсветка
    key = bpy.data.lights.new("key", "SUN")
    key.energy = 3.0
    key.color = PAL["key"]
    key.angle = math.radians(2)
    ko = bpy.data.objects.new("key", key)
    bpy.context.scene.collection.objects.link(ko)
    rim = bpy.data.lights.new("rim", "SUN")
    rim.energy = 4.0
    rim.color = PAL["rim"]
    rim.use_shadow = False
    ro = bpy.data.objects.new("rim", rim)
    bpy.context.scene.collection.objects.link(ro)
    return ko, ro


# ================= Персонажи =================

def anime_character(name, key):
    rig = BC.build_character(key, SPECS, name)
    S = json.loads(rig["spec"])
    BC.S = S
    for o in bpy.data.collections[name].objects:
        if o.type != "MESH":
            continue
        for i, m in enumerate(o.data.materials):
            if m is None:
                continue
            slot = m.get("slot", "main")
            c = BC.slot_color(slot)
            if slot in ("neon", "neon2", "gem", "visor"):
                nm = NE(c, 4.0)
            elif slot == "glint":
                nm = NE((1, 1, 1), 2.0)
            elif slot in ("eye_white", "pupil", "mouth", "dark"):
                nm = cel("flat", c, flat=True)
            elif slot == "iris":
                nm = NE(c, 1.3)
            elif slot in ("trim", "metal", "weapon", "boots", "glove", "hair"):
                nm = cel(slot, c, gloss=True)
            elif slot == "skin":
                nm = cel("skin", c, shadow=(0.78, 0.55, 0.68))
            else:
                nm = cel(slot, c)
            o.data.materials[i] = nm
        if o.name.endswith(":eye0") or o.name.endswith(":eye1") or o.name.endswith(":mouth") or ":lash" in o.name or ":lid" in o.name or ":brow" in o.name:
            o["noline"] = o.name.endswith(":mouth")
    return rig, S


BONES = ["hips", "spine", "chest", "neck", "head", "upperarm0", "forearm0", "hand0", "upperarm1", "forearm1", "hand1",
         "thigh0", "shin0", "thigh1", "shin1"]


class Actor:
    def __init__(self, name, key, pos, yaw):
        self.name = name
        self.key = key
        self.rig, self.S = anime_character(name, key)
        self.scale = float(SPECS.get(key, {}).get("scale", 1.0))
        if key == "hero":
            self.scale = 1.0
        self.rig.scale = (self.scale,) * 3
        self.pos = G(pos)
        self.yaw = math.radians(yaw)
        self.mode = "idle"
        self.look = None
        self.talk = 0.0
        self.move = None
        self.cur = {}
        self.seed = RNG.random() * 10
        self.blink = RNG.uniform(1.0, 3.0)
        self.floating = SPECS.get(key, {}).get("kind", "").startswith("boss_")
        self.dissolve = None
        self.walking = False
        g = {}
        for b in BONES:
            bb = self.rig.data.bones.get(b)
            if bb:
                g[b] = bb.matrix_local.to_quaternion()
        self.g = g
        self.eyes = [o for o in bpy.data.collections[name].objects if o.name.split(":")[-1] in ("eye0", "eye1")]
        self.mouth = next((o for o in bpy.data.collections[name].objects if o.name.endswith(":mouth")), None)
        for pb in self.rig.pose.bones:
            pb.rotation_mode = "QUATERNION"

    def face(self, target):
        d = target - self.pos
        self.yaw = math.atan2(d.x, -d.y)

    def head_pos(self):
        return self.pos + Vector((0, 0, 1.74 * self.scale))

    def targets(self, t):
        tg = {"sh0x": 0.1, "sh0z": -0.12, "sh1x": 0.1, "sh1z": 0.12, "el0": -0.2, "el1": -0.25,
              "hp0": 0.0, "hp1": 0.0, "kn0": 0.05, "kn1": 0.05, "spx": 0.0, "spy": 0.0, "hx": 0.0, "hy": 0.0, "dy": 0.0}
        br = math.sin(t * 2.0 + self.seed)
        tg["spx"] = br * 0.015
        tg["dy"] = br * 0.008
        m = self.mode
        if m == "talk":
            tg.update(sh1x=-0.55 + math.sin(t * 2.3) * 0.25, sh1z=0.35, el1=-1.1 + math.sin(t * 3.1) * 0.25, hy=math.sin(t * 1.3) * 0.12, hx=math.sin(t * 2.7) * 0.05)
        elif m == "point":
            tg.update(sh1x=-1.5, sh1z=0.1, el1=-0.05, spy=-0.2)
        elif m == "stance":
            tg.update(sh1x=-0.9, sh1z=0.3, el1=-1.3, sh0x=-0.6, sh0z=-0.35, el0=-1.1, hp0=-0.45, kn0=0.6, hp1=0.25, kn1=0.35, dy=-0.08 + br * 0.01, spx=0.12)
        elif m == "cast":
            tg.update(sh0x=-2.3, sh1x=-2.3, sh0z=-0.45, sh1z=0.45, el0=-0.3, el1=-0.3, hx=-0.25, spx=-0.1)
        elif m == "cheer":
            bo = abs(math.sin(t * 6.0))
            tg.update(sh0x=-2.5, sh1x=-2.5, sh0z=-0.75, sh1z=0.75, el0=-0.3, el1=-0.3, dy=bo * 0.12, hx=-0.3)
        elif m == "kneel":
            tg.update(hp0=-1.55, kn0=1.55, hp1=0.15, kn1=1.75, dy=-0.42, spx=0.3, hx=0.35, sh0x=-0.3, sh1x=-0.6, el1=-0.8)
        elif m == "hurt":
            tg.update(spx=0.5, hx=0.4, sh0x=0.4, sh1x=-0.8, el1=-1.6, dy=-0.1)
        elif m == "roar":
            tg.update(spx=-0.25, hx=-0.45, sh0x=-0.6, sh1x=-0.6, sh0z=-1.1, sh1z=1.1, el0=-0.9, el1=-0.9)
        elif m == "look":
            tg.update(hy=0.5, spy=0.15)
        if self.walking:
            ph = t * 9.0
            tg.update(hp0=math.sin(ph) * 0.55, hp1=-math.sin(ph) * 0.55, kn0=max(0, -math.sin(ph)) * 0.9 + 0.1, kn1=max(0, math.sin(ph)) * 0.9 + 0.1,
                      dy=abs(math.cos(ph)) * 0.05 - 0.02, spx=0.08)
            if m != "stance":
                tg["sh0x"] = -math.sin(ph) * 0.45
                if m != "point":
                    tg["sh1x"] = math.sin(ph) * 0.45
        if self.look is not None:
            d = self.look - self.head_pos()
            local = Matrix.Rotation(-self.yaw, 4, "Z") @ d
            # вперёд модели — −Y
            tg["hy"] = max(-0.9, min(0.9, math.atan2(local.x, -local.y)))
            tg["hx"] = max(-0.5, min(0.5, -math.atan2(local.z, Vector((local.x, local.y)).length))) + tg["hx"] * 0.3
        return tg

    def rot(self, bone, ex, ey, ez):
        if bone not in self.g:
            return None
        g = self.g[bone]
        # Углы сценария заданы в осях Godot: X → X, Y(вверх) → Z, Z(вперёд) → −Y
        d = Quaternion((0, 0, 1), ey) @ Quaternion((1, 0, 0), ex) @ Quaternion((0, 1, 0), -ez)
        return g.inverted() @ d @ g

    def apply(self, f, t, dt):
        # перемещение
        if self.move:
            a, b, t0, dur = self.move
            k = min(1.0, (t - t0) / dur)
            self.pos = a.lerp(b, k)
            self.walking = k < 1.0
            if k >= 1.0:
                self.move = None
        else:
            self.walking = False
        tg = self.targets(t)
        kk = 1.0 - math.exp(-9.0 * dt)
        for k2, v in tg.items():
            self.cur[k2] = self.cur.get(k2, v) + (v - self.cur.get(k2, v)) * kk
        Cc = self.cur
        hunch = float(self.S.get("hunch", 0.0))
        poses = {
            "spine": ((hunch + Cc["spx"]) * 0.5, Cc["spy"] * 0.5, 0), "chest": ((hunch + Cc["spx"]) * 0.5, Cc["spy"] * 0.5, 0),
            "neck": (Cc["hx"] * 0.35, Cc["hy"] * 0.35, 0), "head": (Cc["hx"] * 0.65, Cc["hy"] * 0.65, 0),
        }
        for i in (0, 1):
            poses["upperarm%d" % i] = (Cc["sh%dx" % i], 0, Cc["sh%dz" % i])
            poses["forearm%d" % i] = (Cc["el%d" % i], 0, 0)
            poses["thigh%d" % i] = (Cc["hp%d" % i], 0, 0)
            poses["shin%d" % i] = (Cc["kn%d" % i], 0, 0)
        for bn, e in poses.items():
            q = self.rot(bn, *e)
            if q is None:
                continue
            pb = self.rig.pose.bones[bn]
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=f)
        hb = self.rig.pose.bones.get("hips")
        if hb:
            hb.location = (0, Cc["dy"], 0)
            hb.keyframe_insert("location", frame=f)
        z = self.pos.z
        if self.floating:
            z += (0.3 + math.sin(t * 1.6 + self.seed) * 0.08) * self.scale
        sc = self.scale
        if self.dissolve is not None:
            k = min(1.0, (t - self.dissolve) / 2.5)
            sc = self.scale * (1.0 - k * 0.97)
            z += k * 1.5
        self.rig.location = (self.pos.x, self.pos.y, z)
        self.rig.rotation_euler = (0, 0, self.yaw)
        self.rig.scale = (sc, sc, sc)
        self.rig.keyframe_insert("location", frame=f)
        self.rig.keyframe_insert("rotation_euler", frame=f)
        self.rig.keyframe_insert("scale", frame=f)
        # моргание и рот
        self.blink -= dt
        closed = self.blink < 0.0
        if self.blink < -dt * 1.5:
            self.blink = RNG.uniform(2.0, 4.5)
        for e in self.eyes:
            e.scale = (1, 1, 0.12 if closed else 1.0)
            e.keyframe_insert("scale", frame=f)
        if self.mouth:
            open_ = 0.0
            if self.talk > t:
                open_ = abs(math.sin(t * 13.0 + math.sin(t * 5.0) * 2.0))
            self.mouth.scale = (1, 1, 1.0 + open_ * 1.6)
            self.mouth.keyframe_insert("scale", frame=f)


# ================= Камера, эффекты, композитинг =================

def setup_render():
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE_NEXT"
    sc.render.resolution_x, sc.render.resolution_y = RES
    sc.render.resolution_percentage = 100
    sc.render.fps = FPS
    sc.render.image_settings.file_format = "PNG"
    sc.render.film_transparent = False
    try:
        sc.eevee.taa_render_samples = 4
        sc.eevee.use_shadows = True
    except Exception:
        pass
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    # Контур
    sc.render.use_freestyle = True
    sc.render.line_thickness_mode = "ABSOLUTE"
    sc.render.line_thickness = 2.2 * RES[1] / 720.0
    vl = sc.view_layers[0]
    vl.use_freestyle = True
    fs = vl.freestyle_settings
    fs.crease_angle = math.radians(128)
    ls = fs.linesets[0] if fs.linesets else fs.linesets.new("ls")
    ls.select_by_visibility = True
    ls.select_by_edge_types = True
    ls.select_silhouette = True
    ls.select_border = True
    ls.select_crease = True
    ls.select_contour = True
    ls.select_external_contour = True
    ls.select_material_boundary = True
    ls.select_by_collection = False
    ls.select_by_face_marks = False
    if ls.linestyle is None:
        ls.linestyle = bpy.data.linestyles.new("ink")
    lst = ls.linestyle
    lst.color = LINE
    lst.thickness = 2.2 * RES[1] / 720.0
    lst.thickness_position = "CENTER"
    # Объекты без контура (неон, порталы, лава) — в отдельной коллекции-исключении
    nol = bpy.data.collections.new("noline")
    sc.collection.children.link(nol)
    for o in list(sc.objects):
        if o.type == "MESH" and (o.get("noline") or any(m and m.get("neon") for m in o.data.materials)):
            nol.objects.link(o)
    ls.select_by_collection = True
    ls.collection = nol
    ls.collection_negation = "EXCLUSIVE"
    comp(sc)


COMP = {}


def comp(sc):
    sc.use_nodes = True
    nt = sc.node_tree
    N, L = nt.nodes, nt.links
    N.clear()
    rl = N.new("CompositorNodeRLayers")
    gl = N.new("CompositorNodeGlare")
    gl.glare_type = "FOG_GLOW"
    gl.quality = "MEDIUM"
    gl.threshold = 1.0
    gl.size = 7
    L.new(rl.outputs["Image"], gl.inputs["Image"])
    ld = N.new("CompositorNodeLensdist")
    ld.use_fit = True
    ld.inputs["Dispersion"].default_value = 0.012
    L.new(gl.outputs["Image"], ld.inputs["Image"])
    tr = N.new("CompositorNodeTranslate")
    L.new(ld.outputs["Image"], tr.inputs["Image"])
    # Кадр-вспышка: чёрно-жёлтый силуэт
    bw = N.new("CompositorNodeRGBToBW")
    L.new(tr.outputs["Image"], bw.inputs[0])
    rp = N.new("CompositorNodeValToRGB")
    rp.color_ramp.interpolation = "CONSTANT"
    rp.color_ramp.elements[0].color = (0.03, 0.0, 0.06, 1)
    rp.color_ramp.elements[1].position = 0.42
    rp.color_ramp.elements[1].color = (YELLOW[0], YELLOW[1], YELLOW[2], 1)
    L.new(bw.outputs[0], rp.inputs[0])
    imp = N.new("CompositorNodeMixRGB")
    imp.inputs[0].default_value = 0.0
    L.new(tr.outputs["Image"], imp.inputs[1])
    L.new(rp.outputs[0], imp.inputs[2])
    # Сочность и контраст
    cb = N.new("CompositorNodeColorCorrection")
    cb.master_saturation = 1.2
    cb.master_contrast = 1.08
    L.new(imp.outputs[0], cb.inputs["Image"])
    # Виньетка
    el = N.new("CompositorNodeEllipseMask")
    el.width = 1.2
    el.height = 1.25
    bl = N.new("CompositorNodeBlur")
    bl.filter_type = "FAST_GAUSS"
    bl.use_relative = True
    bl.factor_x = 25
    bl.factor_y = 25
    L.new(el.outputs[0], bl.inputs["Image"])
    vg = N.new("CompositorNodeMixRGB")
    vg.blend_type = "MULTIPLY"
    vg.inputs[0].default_value = 0.6
    L.new(cb.outputs[0], vg.inputs[1])
    L.new(bl.outputs[0], vg.inputs[2])
    out = N.new("CompositorNodeComposite")
    L.new(vg.outputs[0], out.inputs["Image"])
    COMP.update(ld=ld, tr=tr, imp=imp)


SPEED = None


def speed_lines(cam):
    """Линии скорости: тонкие белые клинья вокруг кадра, привязанные к камере."""
    global SPEED
    bm = bmesh.new()
    rnd = random.Random(3)
    for i in range(70):
        a = 2 * math.pi * i / 70 + rnd.uniform(-0.03, 0.03)
        r0 = rnd.uniform(0.33, 0.45)
        r1 = 1.2
        w = rnd.uniform(0.004, 0.012)
        d = Vector((math.cos(a), math.sin(a), 0))
        n = Vector((-d.y, d.x, 0))
        v = [bm.verts.new(d * r0), bm.verts.new(d * r1 + n * w), bm.verts.new(d * r1 - n * w)]
        bm.faces.new(v)
    me = bpy.data.meshes.new("speed")
    bm.to_mesh(me)
    o = bpy.data.objects.new("speed", me)
    bpy.context.scene.collection.objects.link(o)
    put(o, NE((1, 1, 1), 1.0))
    o["noline"] = True
    o.parent = cam
    o.location = (0, 0, -0.62)
    SPEED = o


def kf_comp(f, impact, glitch, rnd):
    COMP["imp"].inputs[0].default_value = 1.0 if impact else 0.0
    COMP["imp"].inputs[0].keyframe_insert("default_value", frame=f)
    COMP["ld"].inputs["Dispersion"].default_value = 0.012 + glitch * 0.12
    COMP["ld"].inputs["Dispersion"].keyframe_insert("default_value", frame=f)
    COMP["tr"].inputs["X"].default_value = (rnd.uniform(-1, 1) * 40 * glitch)
    COMP["tr"].inputs["X"].keyframe_insert("default_value", frame=f)


def set_constant_interp():
    for a in bpy.data.actions:
        for fc in a.fcurves:
            for k in fc.keyframe_points:
                k.interpolation = "CONSTANT"
    for nt in [bpy.context.scene.node_tree] + [m.node_tree for m in bpy.data.materials if m.node_tree] + [l for l in []]:
        ad = nt.animation_data if nt else None
        if ad and ad.action:
            for fc in ad.action.fcurves:
                for k in fc.keyframe_points:
                    k.interpolation = "CONSTANT"


# ================= Сборка ролика =================

BOSS_INTROS = {
    "boss_lich": ("gate", "lich", MAGENTA),
    "boss_colossus": ("foundry", "colossus", YELLOW),
    "boss_queen": ("gate", "queen", MAGENTA),
    "boss_omega": ("tower", "omega", CYAN),
}


def boss_steps(kind):
    st, key, c = BOSS_INTROS[kind]
    return [
        {"set": st, "actors": [["boss", key, [0, 0, -6], 0]]},
        {"cam": [[0, 0.6, 8], [0, 2.4, -6], [0, 0.4, 5], [0, 3.0, -6]], "fov": [55, 50], "t": 1.25, "fx": "shake"},
        {"cam": [[0, 0.4, 3.2], [0, 3.2, -6], [0, 0.3, 2.6], [0, 3.4, -6]], "fov": [42, 36], "t": 1.0, "pose": {"boss": "roar"}, "fx": "flash_shake", "speed": True},
        {"cam": [[2.5, 1.5, 4.5], [0, 2.6, -6], [3.2, 1.8, 5.5], [0, 2.6, -6]], "fov": [40, 40], "t": 1.75, "pose": {"boss": "cast"}},
    ]


def build_video(scene_id):
    if scene_id.startswith("boss_"):
        steps = boss_steps(scene_id)
    else:
        steps = DATA["scenes"][scene_id]
    # Разбиваем на «декорационные» блоки; каждый блок — своя сцена Blender
    blocks = []
    for s in steps:
        if "set" in s:
            blocks.append({"set": s, "shots": []})
        else:
            blocks[-1]["shots"].append(s)
    frame0 = 1
    outputs = []
    for bi, blk in enumerate(blocks):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        MCACHE.clear()
        ANIM.clear()
        sset = blk["set"]
        key_o, rim_o = build_set(sset["set"])
        actors = {}
        for a in sset.get("actors", []):
            k = a[1]
            if k == "HERO":
                k = "hero"
            real = {"colossus": "knight", "queen": "caster"}.get(k, k)
            act = Actor(a[0], real, a[2], a[3] if len(a) > 3 else 0)
            if k == "colossus":
                act.scale = 2.3
            if k == "queen":
                act.scale = 1.8
                act.floating = True
            actors[a[0]] = act
        cam_d = bpy.data.cameras.new("cam")
        cam = bpy.data.objects.new("cam", cam_d)
        bpy.context.scene.collection.objects.link(cam)
        bpy.context.scene.camera = cam
        cam_d.clip_start = 0.05
        cam_d.clip_end = 500
        cam_d.sensor_fit = "VERTICAL"
        speed_lines(cam)
        setup_render()
        rnd = random.Random(bi)
        total = sum(float(s.get("t", 3.0)) for s in blk["shots"])
        nframes = int(round(total * FPS))
        if TEST:
            nframes = min(nframes, TEST)
        sc = bpy.context.scene
        sc.frame_start = 1
        sc.frame_end = nframes
        # проход по кадрам
        shot_i = -1
        shot_t0 = 0.0
        acc = 0.0
        bounds = []
        for s in blk["shots"]:
            bounds.append((acc, acc + float(s.get("t", 3.0)), s))
            acc += float(s.get("t", 3.0))
        dt = 1.0 / FPS
        shake = 0.0
        impact_frames = 0
        glitch = 1.0
        for f in range(1, nframes + 1):
            t = (f - 1) * dt
            while shot_i + 1 < len(bounds) and t >= bounds[shot_i + 1][0] - 1e-6:
                shot_i += 1
                t0, t1, s = bounds[shot_i]
                for an, mode in s.get("pose", {}).items():
                    if an in actors:
                        actors[an].mode = mode
                for an, tg in s.get("look", {}).items():
                    if an in actors:
                        if tg is None:
                            actors[an].look = None
                        elif isinstance(tg, str) and tg in actors:
                            actors[an].look = actors[tg].head_pos()
                        else:
                            actors[an].look = G(tg)
                for an, tg in s.get("face", {}).items():
                    if an in actors:
                        actors[an].face(actors[tg].pos if isinstance(tg, str) and tg in actors else G(tg))
                for an, mv in s.get("move", {}).items():
                    if an in actors:
                        a = actors[an]
                        b = G(mv[0])
                        a.face(b)
                        a.move = (a.pos.copy(), b, t, float(mv[1]))
                for an in s.get("dissolve", []):
                    if an in actors:
                        actors[an].dissolve = t
                if "line" in s and s["line"][0] in actors:
                    actors[s["line"][0]].talk = t + max(1.0, len(s["line"][2]) * 0.05)
                fx = s.get("fx", "")
                if fx in ("flash", "flash_shake"):
                    impact_frames = 2
                if fx in ("shake", "flash_shake"):
                    shake = 0.3
                    glitch = max(glitch, 0.4)
                SPEED.hide_render = not (s.get("speed") or fx == "flash_shake")
                SPEED.keyframe_insert("hide_render", frame=f)
            t0, t1, s = bounds[shot_i]
            k = (t - t0) / max(0.01, t1 - t0)
            k = k * k * (3 - 2 * k)
            c = s["cam"]
            p0, l0 = G(c[0]), G(c[1])
            p1 = G(c[2]) if len(c) > 2 else p0
            l1 = G(c[3]) if len(c) > 3 else l0
            p = p0.lerp(p1, k)
            l = l0.lerp(l1, k)
            if shake > 0:
                p += Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))) * shake * 0.25
                shake = max(0.0, shake - dt * 0.5)
            cam.location = p
            cam.rotation_euler = (l - p).to_track_quat("-Z", "Y").to_euler()
            fv = s.get("fov", [45, 45])
            cam_d.angle = math.radians(fv[0] + (fv[-1] - fv[0]) * k)
            cam.keyframe_insert("location", frame=f)
            cam.keyframe_insert("rotation_euler", frame=f)
            cam_d.keyframe_insert("lens", frame=f)
            # свет относительно камеры: ключ спереди-сбоку-сверху, контровой сзади
            fwd = (l - p)
            fwd.z = 0
            fwd = fwd.normalized() if fwd.length > 0.01 else Vector((0, 1, 0))
            right = fwd.cross(Vector((0, 0, 1))).normalized()
            kd = (-fwd - right * 1.1 + Vector((0, 0, 1.2))).normalized()
            key_o.rotation_euler = (-kd).to_track_quat("-Z", "Y").to_euler()
            key_o.keyframe_insert("rotation_euler", frame=f)
            rd = (fwd * 1.0 + right * 0.6 + Vector((0, 0, 0.5))).normalized()
            rim_o.rotation_euler = (-rd).to_track_quat("-Z", "Y").to_euler()
            rim_o.keyframe_insert("rotation_euler", frame=f)
            for a in actors.values():
                a.apply(f, t, dt)
            for fn in ANIM:
                fn(f, t)
            kf_comp(f, impact_frames > 0, glitch, rnd)
            impact_frames = max(0, impact_frames - 1)
            glitch = max(0.0, glitch - dt * 2.5)
        set_constant_interp()
        path = os.path.join(OUT, "%s_%02d_" % (scene_id, bi))
        sc.render.filepath = path
        print("RENDER", scene_id, bi, nframes, flush=True)
        bpy.ops.render.render(animation=True)
        outputs.append((path, nframes))
    with open(os.path.join(OUT, scene_id + ".txt"), "w") as fo:
        for pth, n in outputs:
            fo.write("%s %d\n" % (pth, n))


build_video(SCENE_ID)
