# Генератор персонажей для кат-сцен «Ночь охотника: Неон».
# Запуск: blender -b -P build_cine.py -- specs.json out_dir [--preview] [ключи...]
# Строит для каждого персонажа скелет (кости совпадают с процедурной анимацией
# в Godot), гладкое тело (скин-модификатор + подразделение), лепное лицо с
# глазами, веками, ртом и бровями, причёску прядями, перчатки с пальцами,
# сапоги, одежду, головной убор и оружие. Экспорт — .glb, превью — Cycles.
# Материалы называются по «слотам» (skin, main, trim, neon...), цвета
# подставляет игра по описанию героя.

import bpy, bmesh, json, math, sys, os, random
from mathutils import Vector, Matrix, Euler

argv = sys.argv[sys.argv.index("--") + 1:]
SPECS = json.load(open(argv[0]))
OUT = argv[1]
PREVIEW = "--preview" in argv
ONLY = [a for a in argv[2:] if not a.startswith("--")]
os.makedirs(OUT, exist_ok=True)
if PREVIEW:
    os.makedirs(os.path.join(OUT, "preview"), exist_ok=True)

S = {}          # текущее описание
ARM = None      # арматура
MATS = {}


def C(name, default=(0.5, 0.5, 0.5)):
    v = S.get(name)
    if isinstance(v, list) and len(v) >= 3:
        return (v[0], v[1], v[2])
    return default


def dark(c, k):
    return (c[0] * (1 - k), c[1] * (1 - k), c[2] * (1 - k))


# ---------- Материалы (цвет — только для превью; в игре подменяется по имени) ----------

def slot_color(name):
    table = {
        "skin": C("skin", (0.85, 0.7, 0.6)), "main": C("main"), "main2": dark(C("main"), 0.18),
        "trim": C("trim", (0.9, 0.7, 0.3)), "legs": C("legs"), "boots": C("boots"), "glove": dark(C("main"), 0.45),
        "neon": C("neon", (0.3, 0.9, 1)), "neon2": C("neon2", (1, 0.4, 0.8)), "gem": C("gem", (0.4, 0.9, 1)),
        "hair": C("hair", (0.2, 0.15, 0.1)), "hat": C("head_c", (0.3, 0.3, 0.4)), "back": C("back_c", (0.3, 0.2, 0.3)),
        "weapon": C("w_c", (0.5, 0.5, 0.6)), "metal": (0.62, 0.64, 0.72), "dark": (0.06, 0.05, 0.08),
        "eye_white": (0.95, 0.95, 0.97), "iris": dark(C("neon", (0.3, 0.6, 1)), 0.25), "pupil": (0.02, 0.02, 0.03),
        "mouth": (0.32, 0.08, 0.1), "teeth": (0.95, 0.93, 0.88), "beard": C("beard", C("hair", (0.3, 0.2, 0.15))),
        "visor": C("neon", (0.3, 0.9, 1)), "bone": (0.88, 0.85, 0.78), "leather": (0.35, 0.22, 0.14), "wood": (0.42, 0.27, 0.16),
        "glass": (0.6, 0.8, 0.9),
    }
    return table.get(name, (0.5, 0.5, 0.5))


def M(name):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    c = slot_color(name)
    b.inputs["Base Color"].default_value = (c[0], c[1], c[2], 1)
    b.inputs["Roughness"].default_value = 0.55
    if name in ("neon", "neon2", "gem", "visor"):
        b.inputs["Emission Color"].default_value = (c[0], c[1], c[2], 1)
        b.inputs["Emission Strength"].default_value = 4.0
    if name in ("metal", "trim", "weapon"):
        b.inputs["Metallic"].default_value = 0.7
        b.inputs["Roughness"].default_value = 0.35
    if name == "skin":
        b.inputs["Subsurface Weight"].default_value = 0.25
    MATS[name] = m
    return m


# ---------- Утилиты сетки ----------

def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def obj_from_bm(name, bm, mat=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = link(bpy.data.objects.new(name, me))
    if mat:
        o.data.materials.append(M(mat))
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def activate(o):
    for x in bpy.context.view_layer.objects:
        x.select_set(False)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)


def apply_mods(o):
    activate(o)
    for m in list(o.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=m.name)
        except Exception as e:
            print("modifier fail", o.name, m.name, e)


def subsurf(o, lv=1):
    m = o.modifiers.new("sub", "SUBSURF")
    m.levels = lv
    m.render_levels = lv
    apply_mods(o)


def bevel(o, w=0.006, seg=2):
    m = o.modifiers.new("bev", "BEVEL")
    m.width = w
    m.segments = seg
    m.limit_method = "ANGLE"
    apply_mods(o)
    for p in o.data.polygons:
        p.use_smooth = True
    o.data.shade_auto_smooth() if hasattr(o.data, "shade_auto_smooth") else None


def sphere(name, r, mat, seg=24, rings=16, loc=(0, 0, 0), scl=(1, 1, 1), rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=r)
    mt = Matrix.Translation(loc) @ Euler(rot).to_matrix().to_4x4() @ Matrix.Diagonal((scl[0], scl[1], scl[2], 1))
    bmesh.ops.transform(bm, matrix=mt, verts=bm.verts)
    return obj_from_bm(name, bm, mat)


def cyl(name, r1, r2, h, mat, seg=20, loc=(0, 0, 0), rot=(0, 0, 0), scl=(1, 1, 1), caps=True):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=seg, radius1=r1, radius2=r2, depth=h)
    mt = Matrix.Translation(loc) @ Euler(rot).to_matrix().to_4x4() @ Matrix.Diagonal((scl[0], scl[1], scl[2], 1))
    bmesh.ops.transform(bm, matrix=mt, verts=bm.verts)
    return obj_from_bm(name, bm, mat)


def box(name, sx, sy, sz, mat, loc=(0, 0, 0), rot=(0, 0, 0), bev=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    mt = Matrix.Translation(loc) @ Euler(rot).to_matrix().to_4x4() @ Matrix.Diagonal((sx, sy, sz, 1))
    bmesh.ops.transform(bm, matrix=mt, verts=bm.verts)
    o = obj_from_bm(name, bm, mat)
    if bev > 0:
        bevel(o, bev, 3)
    return o


def torus(name, R, r, mat, loc=(0, 0, 0), rot=(0, 0, 0), scl=(1, 1, 1), seg=32, arc=2 * math.pi):
    bm = bmesh.new()
    rings = []
    for i in range(seg + (0 if arc >= 2 * math.pi - 1e-4 else 1)):
        a = arc * i / seg
        ring = []
        for j in range(10):
            b = 2 * math.pi * j / 10
            p = Vector(((R + r * math.cos(b)) * math.cos(a), (R + r * math.cos(b)) * math.sin(a), r * math.sin(b)))
            ring.append(bm.verts.new(p))
        rings.append(ring)
    closed = arc >= 2 * math.pi - 1e-4
    n = len(rings)
    for i in range(n if closed else n - 1):
        r1 = rings[i]
        r2 = rings[(i + 1) % n]
        for j in range(10):
            bm.faces.new((r1[j], r1[(j + 1) % 10], r2[(j + 1) % 10], r2[j]))
    mt = Matrix.Translation(loc) @ Euler(rot).to_matrix().to_4x4() @ Matrix.Diagonal((scl[0], scl[1], scl[2], 1))
    bmesh.ops.transform(bm, matrix=mt, verts=bm.verts)
    return obj_from_bm(name, bm, mat)


def tube(name, pts, radii, mat, res=6):
    """Изогнутая сужающаяся трубка (прядь волос, перо, клинок косы)."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = 1.0
    cu.bevel_resolution = 2
    cu.use_fill_caps = True
    cu.resolution_u = res
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(pts) - 1)
    for i, p in enumerate(pts):
        bp = sp.bezier_points[i]
        bp.co = p
        bp.radius = radii[i]
        bp.handle_left_type = "AUTO"
        bp.handle_right_type = "AUTO"
    tmp = link(bpy.data.objects.new(name + "_c", cu))
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
    bpy.data.objects.remove(tmp)
    o = link(bpy.data.objects.new(name, me))
    o.data.materials.append(M(mat))
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def join(objs, name):
    objs = [o for o in objs if o is not None]
    if not objs:
        return None
    activate(objs[0])
    for o in objs[1:]:
        o.select_set(True)
    with bpy.context.temp_override(active_object=objs[0], selected_editable_objects=objs, selected_objects=objs):
        bpy.ops.object.join()
    objs[0].name = name
    return objs[0]


def to_bone(o, bone):
    """Жёстко прикрепить объект к кости (в glTF станет BoneAttachment)."""
    if o is None:
        return
    # Опорная точка — в центре детали (иначе масштаб глаз/рта для моргания и речи «уезжает»)
    activate(o)
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    mw = o.matrix_world.copy()
    o.parent = ARM
    o.parent_type = "BONE"
    o.parent_bone = bone
    bpy.context.view_layer.update()
    o.matrix_world = mw


def gauss(d, s):
    return math.exp(-(d * d) / (2 * s * s))


# ---------- Скелет ----------

def joints():
    tw = S["tw"]
    arm = S["arm"]
    J = {
        "hips": ((0, 0, 0.88), (0, 0, 0.98)),
        "spine": ((0, 0, 0.98), (0, 0, 1.24)),
        "chest": ((0, 0, 1.24), (0, 0, 1.48)),
        "neck": ((0, 0, 1.48), (0, 0, 1.58)),
        "head": ((0, 0, 1.58), (0, 0, 1.86)),
    }
    for i, s in ((0, -1), (1, 1)):
        x = s * (tw + arm * 0.55)
        J["upperarm%d" % i] = ((x, 0, 1.43), (x, 0, 1.14))
        J["forearm%d" % i] = ((x, 0, 1.14), (x, 0, 0.87))
        J["hand%d" % i] = ((x, 0, 0.87), (x, 0, 0.76))
        lx = s * tw * 0.5
        J["thigh%d" % i] = ((lx, 0, 0.86), (lx, 0, 0.46))
        J["shin%d" % i] = ((lx, 0, 0.46), (lx, 0, 0.07))
    return J


PARENT = {"spine": "hips", "chest": "spine", "neck": "chest", "head": "neck",
          "upperarm0": "chest", "forearm0": "upperarm0", "hand0": "forearm0",
          "upperarm1": "chest", "forearm1": "upperarm1", "hand1": "forearm1",
          "thigh0": "hips", "shin0": "thigh0", "thigh1": "hips", "shin1": "thigh1"}


def build_armature():
    global ARM
    ad = bpy.data.armatures.new("rig")
    ARM = link(bpy.data.objects.new("rig", ad))
    activate(ARM)
    bpy.ops.object.mode_set(mode="EDIT")
    J = joints()
    for name in ["hips", "spine", "chest", "neck", "head", "upperarm0", "forearm0", "hand0", "upperarm1", "forearm1", "hand1",
                 "thigh0", "shin0", "thigh1", "shin1"]:
        b = ad.edit_bones.new(name)
        b.head = J[name][0]
        b.tail = J[name][1]
        if name in PARENT:
            b.parent = ad.edit_bones[PARENT[name]]
            b.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")


# ---------- Тело ----------

def build_body():
    tw, td, arm, leg = S["tw"], S["td"], S["arm"], S["leg"]
    mob = S.get("mob", False)
    me = bpy.data.meshes.new("body")
    V = []
    E = []
    R = []

    def v(p, rx, ry=None):
        V.append(p)
        R.append((rx, ry if ry is not None else rx))
        return len(V) - 1

    belly = 1.25 if S.get("belly") else 1.0
    p0 = v((0, 0, 0.92), tw * 0.95, td * 1.1)
    p1 = v((0, 0, 1.06), tw * 0.76 * belly, td * 0.88 * belly)
    p2 = v((0, 0, 1.27), tw * 1.06, td * 1.12)
    p3 = v((0, 0, 1.41), tw * 0.96, td * 0.92)
    p4 = v((0, 0, 1.50), 0.058, 0.06)
    p5 = v((0, 0, 1.60), 0.052, 0.055)
    E += [(p0, p1), (p1, p2), (p2, p3), (p3, p4), (p4, p5)]
    for s in (-1, 1):
        x = s * (tw + arm * 0.55)
        a0 = v((s * tw * 0.8, 0, 1.42), arm * 1.55, arm * 1.45)
        a1 = v((x, 0, 1.38), arm * 1.3)
        a2 = v((x, 0, 1.13), arm * 0.98)
        a3 = v((x, 0, 0.9), arm * 0.78)
        E += [(p3, a0), (a0, a1), (a1, a2), (a2, a3)]
        lx = s * tw * 0.5
        l0 = v((lx, 0, 0.84), leg * 1.4, leg * 1.35)
        l1 = v((lx, 0, 0.47), leg * 0.95)
        l2 = v((lx, 0, 0.12), leg * 0.72)
        E += [(p0, l0), (l0, l1), (l1, l2)]
    me.from_pydata(V, E, [])
    o = link(bpy.data.objects.new("body", me))
    sk = o.modifiers.new("skin", "SKIN")
    sk.use_smooth_shade = True
    sk.branch_smoothing = 0.6
    for i, r in enumerate(R):
        sv = me.skin_vertices[0].data[i]
        sv.radius = r
        sv.use_root = (i == 0)
    sub = o.modifiers.new("sub", "SUBSURF")
    sub.levels = 2
    sub.render_levels = 2
    apply_mods(o)
    # Материалы по зонам тела
    names = ["skin" if mob else "main", "main2", "glove", "legs", "boots", "trim", "skin"]
    for n in names[:6] + ["skin"]:
        if n not in [m.name for m in o.data.materials]:
            o.data.materials.append(M(n))
    idx = {m.name: i for i, m in enumerate(o.data.materials)}
    for p in o.data.polygons:
        c = p.center
        ax = abs(c.x)
        is_arm = ax > tw * 0.98 and c.z > 0.82
        if is_arm:
            if c.z > 1.16:
                n = "skin" if mob else "main"
            elif c.z > 0.96:
                n = "skin" if mob else "main2"
            else:
                n = "skin" if mob else "glove"
        elif c.z < 0.45:
            n = "boots"
        elif c.z < 0.93:
            n = "legs"
        elif c.z < 1.0:
            n = "trim"
        elif c.z > 1.49:
            n = "skin"
        else:
            n = "skin" if mob else "main"
        p.material_index = idx[n]
        p.use_smooth = True
    # Привязка к скелету с автоматическими весами
    activate(o)
    ARM.select_set(True)
    bpy.context.view_layer.objects.active = ARM
    try:
        bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    except Exception as e:
        print("auto weights failed", e)
        bpy.ops.object.parent_set(type="ARMATURE_ENVELOPE")
    return o


# ---------- Голова ----------

HC = Vector((0, 0, 1.735))   # центр головы


def head_mesh(hr, mob=False):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=40, v_segments=28, radius=1.0)
    feats = [
        # (направление, сигма, величина)
        ((0, -0.76, -0.66), 0.25, 0.07),     # подбородок
        ((0.6, -0.72, -0.08), 0.24, 0.05), ((-0.6, -0.72, -0.08), 0.24, 0.05),   # скулы
        ((0.36, -0.9, 0.1), 0.15, -0.075), ((-0.36, -0.9, 0.1), 0.15, -0.075),   # глазницы
        ((0.34, -0.86, 0.32), 0.17, 0.045), ((-0.34, -0.86, 0.32), 0.17, 0.045), # надбровья
        ((0, -0.99, 0.06), 0.08, 0.07),      # переносица
        ((0, -1.0, -0.12), 0.1, 0.17),       # нос
        ((0, -0.97, -0.22), 0.075, 0.1),     # кончик носа
        ((0.1, -0.96, -0.21), 0.06, 0.05), ((-0.1, -0.96, -0.21), 0.06, 0.05),   # крылья носа
        ((0, -0.95, -0.36), 0.08, 0.035),    # верхняя губа
        ((0, -0.92, -0.47), 0.07, 0.04),     # нижняя губа
        ((0.23, -0.9, -0.41), 0.07, -0.035), ((-0.23, -0.9, -0.41), 0.07, -0.035),   # уголки рта
        ((0.96, 0, 0.18), 0.3, -0.05), ((-0.96, 0, 0.18), 0.3, -0.05),   # виски
    ]
    if mob:
        feats += [((0, -0.85, -0.55), 0.35, 0.15), ((0, -0.9, 0.35), 0.3, 0.08)]
    fv = [(Vector(d).normalized(), s, a) for d, s, a in feats]
    for vtx in bm.verts:
        p = vtx.co.copy()
        n = p.normalized()
        k = 1.0
        for d, s, a in fv:
            k += a * gauss((n - d).length, s)
        p = n * k
        # Пропорции: вытянуть, сузить челюсть и затылок книзу
        p.x *= 0.86
        p.z *= 1.12
        if p.z < -0.1:
            t = min(1.0, (-p.z - 0.1) / 0.95)
            p.x *= 1.0 - 0.3 * t
            if p.y > 0:
                p.y *= 1.0 - 0.38 * t
        if p.y > 0.2:
            p.y *= 1.04
        vtx.co = p * hr + HC
    o = obj_from_bm("head", bm, "skin")
    subsurf(o, 1)
    return o


def on_head(d, hr, depth=1.0):
    n = Vector(d).normalized()
    return HC + Vector((n.x * hr * 0.86 * depth, n.y * hr * depth, n.z * hr * 1.12 * depth))


def build_eyes(hr, glow=False, iris_mat="iris"):
    parts = []
    for i, s in ((0, -1), (1, 1)):
        c = on_head((s * 0.36, -0.9, 0.1), hr, 0.8)
        er = hr * 0.205
        if glow:
            # Злые светящиеся щёлки под тяжёлой надбровной дугой
            e = sphere("eye%d" % i, er * 0.9, "neon", 16, 10, on_head((s * 0.36, -0.9, 0.1), hr, 0.96), (1.3, 0.5, 0.55), (0, s * 0.25, -s * 0.3))
            to_bone(e, "head")
            to_bone(box("browr%d" % i, er * 2.2, er * 0.6, er * 0.5, "skin", on_head((s * 0.36, -0.88, 0.32), hr, 1.0), (0.3, 0, s * 0.35), bev=0.01), "head")
            continue
        w = sphere("ew", er, "eye_white", 24, 16, c)
        ir = sphere("ir", er * 0.6, iris_mat, 20, 12, c + Vector((0, -er * 0.84, 0.0)), (1, 0.32, 1))
        pu = sphere("pu", er * 0.3, "pupil", 14, 8, c + Vector((0, -er * 1.0, 0.0)), (1, 0.3, 1))
        e = join([w, ir, pu], "eye%d" % i)
        to_bone(e, "head")
        # Верхнее веко — даёт взгляду характер
        lid = sphere("lid%d" % i, er * 1.12, "skin", 20, 12, c + Vector((0, -er * 0.05, er * 0.18)), (1.05, 1.0, 0.62), (0.25, 0, 0))
        bm = bmesh.new()
        bm.from_mesh(lid.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < c.z + er * 0.32], context="VERTS")
        bm.to_mesh(lid.data)
        bm.free()
        to_bone(lid, "head")
        # Ресницы — тёмная дуга по краю века
        lash = torus("lash%d" % i, er * 0.98, er * 0.09, "dark", c + Vector((0, -er * 0.08, er * 0.32)), (0.45, 0, 0), (1.05, 1.0, 1.0), 20, math.pi)
        lash.rotation_euler = (math.radians(90) + 0.45, 0, 0)
        to_bone(lash, "head")


def build_face(hr, kind):
    if kind in ("human", "hood_face", "ninja"):
        build_eyes(hr)
        # Брови
        hc = C("hair", (0.2, 0.15, 0.1))
        for i, s in ((0, -1), (1, 1)):
            a = on_head((s * 0.18, -0.92, 0.33), hr, 1.03)
            b = on_head((s * 0.36, -0.9, 0.38), hr, 1.04)
            c2 = on_head((s * 0.55, -0.78, 0.3), hr, 1.03)
            br = tube("brow%d" % i, [a, b, c2], [hr * 0.05, hr * 0.06, hr * 0.03], "hair")
            to_bone(br, "head")
        if kind != "ninja":
            m = sphere("mouth", hr * 0.2, "mouth", 16, 8, on_head((0, -0.93, -0.42), hr, 0.99), (1.25, 0.3, 0.22))
            to_bone(m, "head")
        for i, s in ((0, -1), (1, 1)):
            ear = sphere("ear%d" % i, hr * 0.24, "skin", 14, 10, on_head((s * 1.0, 0.05, -0.02), hr, 0.95), (0.35, 0.7, 1.0), (0, 0, s * 0.3))
            to_bone(ear, "head")
    elif kind == "mob":
        if S.get("eye1"):
            c = on_head((0.32, -0.9, 0.1), hr, 0.85)
            to_bone(sphere("implant", hr * 0.3, "metal", 18, 12, c), "head")
            to_bone(sphere("eye1", hr * 0.2, "neon", 16, 10, c + Vector((0, -hr * 0.22, 0))), "head")
            to_bone(sphere("eye0", hr * 0.13, "neon", 14, 8, on_head((-0.34, -0.9, 0.12), hr, 0.85), (1.2, 0.6, 0.8)), "head")
        else:
            build_eyes(hr, glow=True)
        jaw = sphere("mouth", hr * 0.42, "dark", 18, 10, on_head((0, -0.88, -0.48), hr, 1.0), (1.0, 0.35, 0.3))
        to_bone(jaw, "head")
        for k in range(5):
            x = (k - 2) * hr * 0.15
            t = cyl("tooth%d" % k, hr * 0.045, 0.0, hr * 0.14, "teeth", 6, on_head((0, -0.92, -0.38), hr, 0.98) + Vector((x, -hr * 0.04, -hr * 0.04)), (math.pi, 0, 0))
            to_bone(t, "head")
        if S.get("jaw"):
            to_bone(box("jawplate", hr * 1.3, hr * 0.7, hr * 0.5, "metal", on_head((0, -0.8, -0.7), hr, 1.0), bev=0.01), "head")
        if S.get("ears"):
            for i, s in ((0, -1), (1, 1)):
                to_bone(cyl("ear%d" % i, hr * 0.22, 0.0, hr * 1.1, "skin", 10, on_head((s, 0, 0.1), hr, 1.0) + Vector((s * hr * 0.4, 0, hr * 0.1)), (0, s * -1.2, 0), (0.45, 1, 1)), "head")
    elif kind == "visor":
        v = torus("visor", hr * 0.92, hr * 0.085, "visor", HC + Vector((0, -hr * 0.05, hr * 0.12)), (0, 0, 0), (1.0, 1.15, 1.6), 28, math.pi)
        v.rotation_euler = (0, 0, math.pi)
        to_bone(v, "head")


# ---------- Причёски и головные уборы ----------

def hair_cap(hr, front=0.38, back=-0.45, mat="hair", puff=1.08):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=36, v_segments=24, radius=1.0)
    kill = []
    for vtx in bm.verts:
        n = vtx.co.normalized()
        # линия роста волос: спереди высоко, сзади низко
        lim = front + (back - front) * (n.y * 0.5 + 0.5)
        if n.z < lim:
            kill.append(vtx)
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    for vtx in bm.verts:
        n = vtx.co.normalized()
        p = n * puff
        p.x *= 0.88
        p.z *= 1.14
        vtx.co = p * hr + HC
    o = obj_from_bm("haircap", bm, mat)
    sol = o.modifiers.new("sol", "SOLIDIFY")
    sol.thickness = hr * 0.06
    apply_mods(o)
    subsurf(o, 1)
    return o


def clump(name, root_dir, tip_off, hr, thick=0.16, mat="hair", bend=(0, 0, 0)):
    a = on_head(root_dir, hr, 1.06)
    tip = a + Vector(tip_off) * hr
    mid = a.lerp(tip, 0.5) + Vector(bend) * hr
    return tube(name, [a, mid, tip], [hr * thick, hr * thick * 0.7, hr * 0.01], mat)


def build_hair(hr, style):
    parts = []
    if style == "short":
        parts.append(hair_cap(hr, 0.42, -0.35))
        for i in range(9):
            a = -1.1 + i * 0.27
            parts.append(clump("h%d" % i, (math.sin(a) * 0.7, -0.55, 0.6), (math.sin(a) * 0.25, -0.35, -0.35), hr, 0.17, bend=(0, -0.15, 0.1)))
    elif style == "spiky":
        parts.append(hair_cap(hr, 0.35, -0.4))
        rnd = random.Random(7)
        for i in range(14):
            d = Vector((rnd.uniform(-0.8, 0.8), rnd.uniform(-0.6, 0.8), rnd.uniform(0.5, 1.0))).normalized()
            parts.append(clump("h%d" % i, d, d * 0.9 + Vector((0, 0.3, 0.25)), hr, 0.2))
    elif style == "long":
        parts.append(hair_cap(hr, 0.32, -0.6))
        for i in range(12):
            a = -1.4 + i * (2.8 / 11)
            d = (math.sin(a), math.cos(a) * 0.9 + 0.1, 0.35)
            parts.append(clump("h%d" % i, d, (math.sin(a) * 0.5, 0.25 + math.cos(a) * 0.3, -2.4), hr, 0.22, bend=(math.sin(a) * 0.3, 0.2, 0)))
        for i in range(5):
            a = -0.7 + i * 0.35
            parts.append(clump("b%d" % i, (math.sin(a) * 0.6, -0.6, 0.62), (math.sin(a) * 0.4, -0.35, -0.6), hr, 0.15, bend=(0, -0.2, 0)))
    elif style == "ponytail":
        parts.append(hair_cap(hr, 0.4, -0.25))
        top = on_head((0, 0.6, 0.75), hr, 1.05)
        parts.append(tube("tail", [top, top + Vector((0, hr * 0.7, -hr * 0.2)), top + Vector((0, hr * 0.8, -hr * 1.6)), top + Vector((0, hr * 0.5, -hr * 2.6))],
                          [hr * 0.22, hr * 0.26, hr * 0.18, hr * 0.02], "hair"))
        for i in range(7):
            a = -0.9 + i * 0.3
            parts.append(clump("b%d" % i, (math.sin(a) * 0.7, -0.6, 0.55), (math.sin(a) * 0.25, -0.3, -0.45), hr, 0.15, bend=(0, -0.2, 0)))
    o = join(parts, "hair")
    to_bone(o, "head")
    return o


def build_headwear(hr):
    h = S.get("head", "plain")
    face = S.get("face", "human")
    if h in ("plain", "voron"):
        build_hair(hr, "short")
        if h == "voron":
            to_bone(box("patch", hr * 0.42, hr * 0.06, hr * 0.32, "dark", on_head((-0.36, -0.95, 0.1), hr, 1.02), bev=0.01), "head")
            to_bone(tube("strap", [on_head((-0.75, -0.5, 0.45), hr, 1.03), on_head((0, -0.6, 0.85), hr, 1.05), on_head((0.8, 0.0, 0.5), hr, 1.05)], [hr * 0.03] * 3, "dark"), "head")
        if S.get("beard"):
            b = sphere("beard", hr * 0.5, "beard", 24, 14, on_head((0, -0.7, -0.7), hr, 0.78), (1.0, 0.7, 0.7))
            to_bone(b, "head")
    elif h in ("hood", "hood_white", "skull"):
        if face != "skull":
            build_hair(hr, "long" if h == "hood_white" else "short")
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=36, v_segments=24, radius=1.0)
        kill = [v for v in bm.verts if v.co.y < -0.45 and v.co.z < 0.62]
        bmesh.ops.delete(bm, geom=kill, context="VERTS")
        for vtx in bm.verts:
            p = vtx.co.copy()
            p.x *= 1.0
            p.z *= 1.2
            if p.y > 0.3 and p.z > 0.2:
                p.y += (p.z - 0.2) * 0.5   # капюшон стекает назад остриём
            vtx.co = p * hr * 1.32 + HC + Vector((0, hr * 0.12, hr * 0.12))
        hood = obj_from_bm("hood", bm, "hat")
        sol = hood.modifiers.new("sol", "SOLIDIFY")
        sol.thickness = hr * 0.08
        apply_mods(hood)
        subsurf(hood, 1)
        to_bone(hood, "head")
        if h == "skull":
            sk = head_mesh(hr * 0.98)
            sk.name = "skullmask"
            sk.data.materials[0] = M("bone")
            to_bone(sk, "head")
            for i, s in ((0, -1), (1, 1)):
                to_bone(sphere("sock%d" % i, hr * 0.2, "dark", 16, 10, on_head((s * 0.36, -0.9, 0.1), hr, 0.92)), "head")
                to_bone(sphere("eye%d" % i, hr * 0.08, "neon", 12, 8, on_head((s * 0.36, -0.9, 0.1), hr, 1.0)), "head")
        if h == "hood":
            # Неоновая визор-маска поперёк глаз
            v = torus("visor", hr * 0.95, hr * 0.06, "visor", HC + Vector((0, 0, hr * 0.13)), (0, 0, math.pi), (0.95, 1.2, 1.4), 28, math.pi)
            to_bone(v, "head")
    elif h == "samurai":
        build_hair(hr, "ponytail")
        to_bone(torus("band", hr * 1.0, hr * 0.07, "neon", HC + Vector((0, 0, hr * 0.45)), (0, 0, 0), (0.9, 1.0, 1.0)), "head")
        for i, s in ((0, -1), (1, 1)):
            to_bone(tube("ribbon%d" % i, [on_head((s * 0.2, 0.95, 0.45), hr, 1.05), on_head((s * 0.3, 1.4, 0.0), hr, 1.0), on_head((s * 0.4, 1.7, -0.7), hr, 1.0)], [hr * 0.06, hr * 0.05, hr * 0.02], "neon"), "head")
    elif h == "dwarf":
        build_hair(hr, "short")
        helm = sphere("helm", hr * 1.12, "hat", 32, 20, HC + Vector((0, 0, hr * 0.32)), (0.95, 1.0, 0.78))
        bm = bmesh.new()
        bm.from_mesh(helm.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < HC.z + hr * 0.18], context="VERTS")
        bm.to_mesh(helm.data)
        bm.free()
        sol = helm.modifiers.new("sol", "SOLIDIFY")
        sol.thickness = hr * 0.08
        apply_mods(helm)
        to_bone(helm, "head")
        to_bone(torus("helmrim", hr * 1.06, hr * 0.08, "trim", HC + Vector((0, 0, hr * 0.22)), (0, 0, 0), (0.9, 1.0, 1.0)), "head")
        for i, s in ((0, -1), (1, 1)):
            base = on_head((s * 0.95, 0, 0.45), hr, 1.05)
            to_bone(tube("horn%d" % i, [base, base + Vector((s * hr * 0.6, 0, hr * 0.3)), base + Vector((s * hr * 0.8, -hr * 0.1, hr * 1.0))], [hr * 0.16, hr * 0.12, hr * 0.01], "bone"), "head")
        # Окладистая борода прядями
        parts = []
        for i in range(9):
            a = -1.0 + i * 0.25
            root = (math.sin(a) * 0.8, -0.75, -0.25 - abs(math.sin(a)) * 0.1)
            parts.append(clump("bd%d" % i, root, (math.sin(a) * 0.15, -0.4, -1.4 + abs(a) * 0.4), hr, 0.24, "beard", (0, -0.25, 0)))
        to_bone(join(parts, "beard"), "head")
        to_bone(tube("mous", [on_head((-0.45, -0.88, -0.3), hr, 1.0), on_head((0, -1.0, -0.28), hr, 1.04), on_head((0.45, -0.88, -0.3), hr, 1.0)], [hr * 0.04, hr * 0.1, hr * 0.04], "beard"), "head")
    elif h == "witch":
        build_hair(hr, "long")
        to_bone(cyl("brim", hr * 2.0, hr * 2.0, hr * 0.06, "hat", 40, HC + Vector((0, 0, hr * 0.62)), (0.08, 0, 0)), "head")
        pts = [HC + Vector((0, 0, hr * 0.6)), HC + Vector((0, hr * 0.1, hr * 1.6)), HC + Vector((-hr * 0.2, hr * 0.5, hr * 2.4)), HC + Vector((-hr * 0.7, hr * 0.9, hr * 2.6))]
        to_bone(tube("cone", pts, [hr * 1.0, hr * 0.62, hr * 0.28, hr * 0.03], "hat", 10), "head")
        to_bone(torus("hatband", hr * 0.98, hr * 0.07, "neon", HC + Vector((0, 0, hr * 0.72)), (0.08, 0, 0)), "head")
    elif h == "great_helm":
        helm = cyl("helm", hr * 1.12, hr * 1.18, hr * 2.4, "hat", 32, HC + Vector((0, 0, hr * 0.1)))
        bevel(helm, hr * 0.06, 3)
        to_bone(helm, "head")
        to_bone(sphere("dome", hr * 1.13, "hat", 32, 16, HC + Vector((0, 0, hr * 1.25)), (1, 1, 0.45)), "head")
        to_bone(box("slit", hr * 1.5, hr * 0.2, hr * 0.14, "visor", HC + Vector((0, -hr * 1.06, hr * 0.12))), "head")
        to_bone(box("ridge", hr * 0.16, hr * 0.22, hr * 1.9, "trim", HC + Vector((0, -hr * 1.12, hr * 0.25)), bev=0.005), "head")
        to_bone(torus("halo", hr * 1.0, hr * 0.06, "neon", HC + Vector((0, hr * 0.2, hr * 1.9)), (0.3, 0, 0)), "head")
    elif h == "feathers":
        build_hair(hr, "long")
        to_bone(torus("band", hr * 1.0, hr * 0.1, "hat", HC + Vector((0, 0, hr * 0.42)), (0, 0, 0), (0.9, 1.0, 1.0)), "head")
        fcol = ["neon", "neon2", "trim", "neon", "neon2"]
        for i in range(5):
            a = -0.8 + i * 0.4
            base = on_head((math.sin(a) * 0.5, 0.75, 0.5), hr, 1.05)
            to_bone(tube("feather%d" % i, [base, base + Vector((math.sin(a) * hr * 0.4, hr * 0.3, hr * 1.0)), base + Vector((math.sin(a) * hr * 0.9, hr * 0.7, hr * 1.9))],
                         [hr * 0.08, hr * 0.14, hr * 0.01], fcol[i]), "head")
    elif h == "goggles":
        build_hair(hr, "spiky")
        to_bone(torus("gstrap", hr * 1.0, hr * 0.07, "leather", HC + Vector((0, 0, hr * 0.5)), (0.15, 0, 0), (0.9, 1.0, 1.0)), "head")
        for i, s in ((0, -1), (1, 1)):
            c = on_head((s * 0.35, -0.8, 0.55), hr, 1.12)
            to_bone(cyl("gring%d" % i, hr * 0.3, hr * 0.3, hr * 0.22, "metal", 24, c, (math.pi / 2 - 0.5, 0, 0)), "head")
            to_bone(sphere("glens%d" % i, hr * 0.25, "visor", 20, 10, c + Vector((0, -hr * 0.1, hr * 0.06)), (1, 0.45, 1), (-0.5, 0, 0)), "head")
    elif h == "ninja":
        cap = hair_cap(hr, -0.05, -0.7, "hat", 1.06)
        cap.name = "cowl"
        to_bone(cap, "head")
        mask = sphere("mask", hr, "hat", 32, 18, HC + Vector((0, -hr * 0.05, -hr * 0.25)), (0.9, 1.05, 0.75))
        bm = bmesh.new()
        bm.from_mesh(mask.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z > HC.z - hr * 0.02], context="VERTS")
        bm.to_mesh(mask.data)
        bm.free()
        to_bone(mask, "head")
        to_bone(torus("band", hr * 1.0, hr * 0.07, "trim", HC + Vector((0, 0, hr * 0.42)), (0, 0, 0), (0.9, 1.0, 1.0)), "head")
        to_bone(tube("tails", [on_head((0, 1.0, 0.4), hr, 1.05), on_head((0.2, 1.6, 0.0), hr, 1.0), on_head((0.4, 2.0, -0.6), hr, 1.0)], [hr * 0.08, hr * 0.06, hr * 0.02], "trim"), "head")
    elif h == "mob":
        if S.get("horns"):
            for i, s in ((0, -1), (1, 1)):
                base = on_head((s * 0.6, 0.0, 0.75), hr, 1.0)
                to_bone(tube("horn%d" % i, [base, base + Vector((s * hr * 0.4, hr * 0.2, hr * 0.6)), base + Vector((s * hr * 0.3, hr * 0.7, hr * 1.2))], [hr * 0.18, hr * 0.11, hr * 0.01], "bone"), "head")
        if S.get("helm"):
            to_bone(sphere("helm", hr * 1.18, "metal", 32, 18, HC + Vector((0, 0, hr * 0.1)), (0.95, 1.05, 1.1)), "head")
            to_bone(box("slit", hr * 1.3, hr * 0.2, hr * 0.14, "neon", HC + Vector((0, -hr * 1.08, hr * 0.12))), "head")
            to_bone(tube("crest", [HC + Vector((0, -hr * 0.6, hr * 1.1)), HC + Vector((0, 0, hr * 1.5)), HC + Vector((0, hr * 1.0, hr * 1.0))], [hr * 0.05, hr * 0.12, hr * 0.02], "neon2"), "head")
        if S.get("hood"):
            hd = sphere("hood", hr * 1.3, "main", 32, 18, HC + Vector((0, hr * 0.15, hr * 0.15)), (1, 1.05, 1.15))
            bm = bmesh.new()
            bm.from_mesh(hd.data)
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.y < HC.y - hr * 0.5 and v.co.z < HC.z + hr * 0.7], context="VERTS")
            bm.to_mesh(hd.data)
            bm.free()
            to_bone(hd, "head")
        if S.get("goggles"):
            for i, s in ((0, -1), (1, 1)):
                c = on_head((s * 0.36, -0.88, 0.2), hr, 1.05)
                to_bone(cyl("gring%d" % i, hr * 0.28, hr * 0.28, hr * 0.2, "metal", 20, c, (math.pi / 2, 0, 0)), "head")
                to_bone(sphere("glens%d" % i, hr * 0.24, "visor", 16, 10, c + Vector((0, -hr * 0.1, 0)), (1, 0.4, 1)), "head")


# ---------- Кисти и сапоги ----------

def build_hand(i, s):
    J = joints()
    w = Vector(J["hand%d" % i][0])
    parts = []
    mat = "skin" if S.get("mob") else "glove"
    parts.append(box("palm", 0.075, 0.085, 0.09, mat, w + Vector((0, 0, -0.06)), bev=0.018))
    for f in range(4):
        y = -0.03 + f * 0.02
        base = w + Vector((s * 0.0, y * 1.2 - 0.005, -0.105))
        # Полусогнутые пальцы
        p = [base, base + Vector((-s * 0.012, 0, -0.04)), base + Vector((-s * 0.03, 0, -0.07))]
        parts.append(tube("f%d" % f, p, [0.012, 0.011, 0.009], mat, 4))
    tb = w + Vector((-s * 0.03, -0.04, -0.05))
    parts.append(tube("thumb", [tb, tb + Vector((-s * 0.02, -0.02, -0.03)), tb + Vector((-s * 0.02, -0.025, -0.055))], [0.014, 0.012, 0.01], mat, 4))
    if not S.get("mob"):
        parts.append(cyl("cuff", S["arm"] * 1.15, S["arm"] * 1.05, 0.05, "trim", 20, w + Vector((0, 0, 0.03))))
    if S.get("claws"):
        for f in range(3):
            parts.append(cyl("claw%d" % f, 0.008, 0.0, 0.04, "bone", 6, w + Vector((-s * 0.03, -0.025 + f * 0.025, -0.19)), (0, s * 0.4, 0)))
    o = join(parts, "hand%d" % i)
    to_bone(o, "hand%d" % i)


def build_boot(i, s):
    leg = S["leg"]
    lx = s * S["tw"] * 0.5
    parts = []
    parts.append(cyl("shaft", leg * 0.95, leg * 1.08, 0.36, "boots", 24, (lx, 0, 0.27)))
    parts.append(torus("cuffring", leg * 1.12, leg * 0.16, "trim", (lx, 0, 0.45)))
    foot = box("foot", leg * 2.0, 0.24, 0.09, "boots", (lx, -0.05, 0.05), bev=0.03)
    subsurf(foot, 1)
    parts.append(foot)
    parts.append(box("toe", leg * 1.9, 0.08, 0.07, "boots", (lx, -0.15, 0.045), bev=0.02))
    parts.append(box("sole", leg * 2.1, 0.27, 0.022, "neon", (lx, -0.055, 0.01), bev=0.006))
    parts.append(box("strap", leg * 2.2, 0.03, 0.05, "trim", (lx, -0.02, 0.12), bev=0.005))
    o = join(parts, "boot%d" % i)
    to_bone(o, "shin%d" % i)


# ---------- Одежда, спина ----------

def build_clothes():
    tw, td = S["tw"], S["td"]
    mob = S.get("mob", False)
    # Пояс с пряжкой
    to_bone(torus("belt", tw * 0.88, 0.022, "trim", (0, 0, 0.97), (0, 0, 0), (1.0, td / tw * 1.12, 1.0)), "hips")
    to_bone(box("buckle", 0.07, 0.025, 0.055, "metal", (0, -td * 1.0, 0.97), bev=0.006), "hips")
    if mob:
        if S.get("plates"):
            for k in range(3):
                to_bone(box("plate%d" % k, tw * 1.8, 0.04, 0.08, "metal", (0, -td * 1.05, 1.15 + k * 0.1), bev=0.01), "chest" if k else "spine")
        if S.get("tail"):
            pts = [Vector((0, td, 0.92)), Vector((0, td + 0.25, 0.75)), Vector((0, td + 0.5, 0.55)), Vector((0, td + 0.65, 0.6))]
            to_bone(tube("tail", pts, [0.05, 0.04, 0.025, 0.01], "skin"), "hips")
        if S.get("robe"):
            to_bone(cyl("robe", tw * 1.0, tw * 1.7, 0.85, "main2", 32, (0, 0, 0.55)), "hips")
        return
    # Неоновая полоса и воротник
    to_bone(box("stripe", 0.018, 0.012, 0.3, "neon", (tw * 0.42, -td * 1.08, 1.24), bev=0.003), "chest")
    to_bone(torus("collar", 0.075, 0.025, "trim", (0, 0, 1.5), (0.2, 0, 0)), "chest")
    # Наплечники
    for i, s in ((0, -1), (1, 1)):
        x = s * (tw + S["arm"] * 0.4)
        pad = sphere("pad%d" % i, S["arm"] * 2.0, "trim", 24, 14, (x, 0, 1.44), (1.1, 1.0, 0.7), (0, s * 0.35, 0))
        bm = bmesh.new()
        bm.from_mesh(pad.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < 1.40], context="VERTS")
        bm.to_mesh(pad.data)
        bm.free()
        sol = pad.modifiers.new("sol", "SOLIDIFY")
        sol.thickness = 0.012
        apply_mods(pad)
        to_bone(pad, "upperarm%d" % i)
    back = S.get("back", "none")
    if back in ("robe", "coat"):
        # Полы одежды: юбка-конус, у плаща — разрезанная спереди
        ln = 0.82 if back == "robe" else 0.5
        sk = cyl("skirt", tw * 1.0, tw * (1.55 if back == "robe" else 1.25), ln, "back" if back == "robe" else "main", 32, (0, 0, 0.98 - ln * 0.5), caps=False)
        if back == "coat":
            bm = bmesh.new()
            bm.from_mesh(sk.data)
            bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_center_median().y < -tw * 0.5 and abs(f.calc_center_median().x) < tw * 0.45], context="FACES")
            bm.to_mesh(sk.data)
            bm.free()
        sol = sk.modifiers.new("sol", "SOLIDIFY")
        sol.thickness = 0.015
        apply_mods(sk)
        subsurf(sk, 1)
        to_bone(sk, "hips")
        if back == "robe":
            to_bone(torus("hem", tw * 1.55, 0.012, "neon2", (0, 0, 0.98 - ln + 0.01), (0, 0, 0)), "hips")
    if back in ("cloak", "cape", "cape_short", "robe"):
        ln = {"cloak": 1.15, "cape": 1.2, "cape_short": 0.6, "robe": 1.0}[back]
        bm = bmesh.new()
        nx, nz = 10, 14
        vs = []
        for zi in range(nz + 1):
            row = []
            t = zi / nz
            for xi in range(nx + 1):
                u = xi / nx - 0.5
                w = tw * (2.1 + t * 1.3)
                x = u * w
                y = td + 0.04 + t * t * 0.18 + math.cos(u * math.pi) * 0.05 + math.sin(u * 9 + t * 4) * 0.012 * t
                z = 1.47 - t * ln
                row.append(bm.verts.new((x, y, z)))
            vs.append(row)
        for zi in range(nz):
            for xi in range(nx):
                bm.faces.new((vs[zi][xi], vs[zi][xi + 1], vs[zi + 1][xi + 1], vs[zi + 1][xi]))
        cape = obj_from_bm("cape", bm, "back")
        sol = cape.modifiers.new("sol", "SOLIDIFY")
        sol.thickness = 0.014
        apply_mods(cape)
        subsurf(cape, 1)
        to_bone(cape, "chest")
        if back in ("cloak", "cape_short"):
            hem = []
            for xi in range(nx + 1):
                hem.append(Vector(vs[nz][xi].co) if False else None)
            to_bone(box("hemglow", tw * (2.1 + 1.3) * 0.95, 0.01, 0.018, "neon2" if back == "cloak" else "neon", (0, td + 0.04 + 0.18, 1.47 - ln + 0.01)), "chest")
    if back == "scarf":
        to_bone(torus("scarf", 0.085, 0.04, "back", (0, 0, 1.5), (0.15, 0, 0), (1.15, 1.2, 1.0)), "chest")
        for k, (sx, ln) in enumerate(((0.06, 0.55), (-0.03, 0.4))):
            to_bone(tube("scarft%d" % k, [Vector((sx, td + 0.05, 1.48)), Vector((sx + 0.05, td + 0.25, 1.3)), Vector((sx + 0.1, td + 0.45, 1.48 - ln))], [0.035, 0.035, 0.02], "back"), "chest")
    if back == "quiver":
        q = cyl("quiver", 0.06, 0.05, 0.55, "back", 20, (0.05, td + 0.08, 1.25), (0, 0.35, 0))
        to_bone(q, "chest")
        for k in range(4):
            to_bone(cyl("arrow%d" % k, 0.007, 0.007, 0.25, "wood", 6, (0.13 + k * 0.02, td + 0.08, 1.6), (0, 0.35, 0)), "chest")
            to_bone(sphere("fl%d" % k, 0.022, "neon", 8, 6, (0.17 + k * 0.02, td + 0.08, 1.72)), "chest")


# ---------- Оружие ----------

def build_weapon():
    w = S.get("weapon", "none")
    J = joints()
    h = Vector(J["hand1"][0]) + Vector((0, -0.02, -0.07))   # хват в правой (по +X) руке
    parts = []
    if w in ("staff", "orbstaff", "scythe"):
        parts.append(cyl("shaft", 0.017, 0.022, 1.75, "weapon", 16, h + Vector((0, 0, 0.25))))
        for k in (0.6, 0.95):
            parts.append(torus("wrap%d" % k, 0.022, 0.008, "trim", h + Vector((0, 0, k))))
        top = h + Vector((0, 0, 1.13))
        if w == "staff":
            for s in (-1, 1):
                parts.append(tube("prong%d" % s, [top, top + Vector((s * 0.06, 0, 0.08)), top + Vector((s * 0.03, 0, 0.2))], [0.018, 0.014, 0.004], "weapon"))
            g = sphere("gem", 0.05, "gem", 6, 4, top + Vector((0, 0, 0.11)), (1, 1, 1.7))
            parts.append(g)
        elif w == "orbstaff":
            parts.append(sphere("orb", 0.075, "gem", 24, 16, top + Vector((0, 0, 0.1))))
            parts.append(torus("orbring", 0.105, 0.01, "trim", top + Vector((0, 0, 0.1)), (0.6, 0, 0.3)))
            parts.append(torus("orbring2", 0.12, 0.007, "neon", top + Vector((0, 0, 0.1)), (-0.5, 0.4, 0)))
        else:
            pts = [top + Vector((0, 0, 0.0)), top + Vector((0, -0.25, 0.08)), top + Vector((0, -0.5, -0.05)), top + Vector((0, -0.62, -0.25))]
            parts.append(tube("blade", pts, [0.05, 0.045, 0.03, 0.002], "metal"))
            parts.append(tube("edge", [p + Vector((0, 0, -0.035)) for p in pts], [0.012, 0.012, 0.01, 0.002], "neon"))
    elif w in ("katana", "blade"):
        ln = 0.9 if w == "katana" else 0.6
        g = h
        parts.append(cyl("grip", 0.017, 0.017, 0.24, "dark", 12, g + Vector((0, 0, 0.0))))
        parts.append(cyl("guard", 0.055, 0.055, 0.015, "trim", 20, g + Vector((0, 0, -0.13))))
        bl = box("blade", 0.008, 0.045, ln, "metal", g + Vector((0, 0.0, -0.14 - ln * 0.5)), bev=0.002)
        parts.append(bl)
        parts.append(box("edge", 0.01, 0.006, ln * 0.92, "neon", g + Vector((0, -0.024, -0.14 - ln * 0.5))))
    elif w == "hammer":
        parts.append(cyl("shaft", 0.022, 0.025, 0.9, "wood", 12, h + Vector((0, 0, 0.25))))
        parts.append(box("head", 0.36, 0.2, 0.2, "weapon", h + Vector((0, 0, 0.72)), bev=0.025))
        parts.append(box("band", 0.37, 0.21, 0.035, "neon", h + Vector((0, 0, 0.72))))
        for s in (-1, 1):
            parts.append(box("face%d" % s, 0.04, 0.22, 0.22, "trim", h + Vector((s * 0.19, 0, 0.72)), bev=0.01))
    elif w == "mace":
        parts.append(cyl("shaft", 0.02, 0.02, 0.6, "metal", 12, h + Vector((0, 0, 0.2))))
        parts.append(sphere("ball", 0.09, "trim", 24, 16, h + Vector((0, 0, 0.55))))
        for k in range(8):
            a = 2 * math.pi * k / 8
            d = Vector((math.cos(a), math.sin(a), 0.2 * (-1) ** k))
            parts.append(cyl("sp%d" % k, 0.02, 0.0, 0.07, "trim", 6, h + Vector((0, 0, 0.55)) + d * 0.1, (0, math.pi / 2, a)))
        J0 = Vector(J["hand0"][0])
        sh = cyl("shield", 0.26, 0.26, 0.04, "weapon", 6, J0 + Vector((-0.06, -0.06, -0.05)), (0, math.pi / 2, 0), (1.25, 1, 1))
        bevel(sh, 0.01, 2)
        to_bone(sh, "hand0")
        to_bone(box("srune", 0.05, 0.03, 0.4, "neon", J0 + Vector((-0.09, -0.06, -0.05))), "hand0")
    elif w == "wand":
        parts.append(cyl("rod", 0.012, 0.018, 0.38, "weapon", 10, h + Vector((0, -0.05, 0.1)), (0.5, 0, 0)))
        parts.append(sphere("tip", 0.035, "gem", 12, 8, h + Vector((0, -0.14, 0.27))))
    elif w == "bow":
        J0 = Vector(J["hand0"][0]) + Vector((0, -0.05, -0.07))
        pts = [J0 + Vector((0, 0.12, 0.62)), J0 + Vector((0, -0.08, 0.3)), J0, J0 + Vector((0, -0.08, -0.3)), J0 + Vector((0, 0.12, -0.62))]
        to_bone(tube("bow", pts, [0.008, 0.02, 0.026, 0.02, 0.008], "weapon"), "hand0")
        to_bone(cyl("string", 0.003, 0.003, 1.24, "neon", 6, J0 + Vector((0, 0.12, 0))), "hand0")
    elif w == "flask":
        parts.append(sphere("glass", 0.065, "glass", 20, 12, h + Vector((0, -0.04, -0.02))))
        parts.append(sphere("liquid", 0.052, "gem", 16, 10, h + Vector((0, -0.04, -0.03))))
        parts.append(cyl("neck", 0.02, 0.02, 0.07, "glass", 12, h + Vector((0, -0.04, 0.07))))
        parts.append(cyl("cork", 0.022, 0.02, 0.03, "wood", 10, h + Vector((0, -0.04, 0.11))))
    if S.get("orb"):
        parts.append(sphere("orb", 0.08, "neon", 16, 10, h + Vector((0, -0.12, -0.02))))
    o = join(parts, "weapon")
    if o:
        to_bone(o, "hand1")


# ---------- Сборка персонажа ----------

def build(key):
    global S, MATS, ARM
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS = {}
    S = dict(SPECS[key])
    S.setdefault("hunch", 0.0)
    build_armature()
    build_body()
    hr = 0.132 if not S.get("mob") else 0.14
    face = S.get("face", "human")
    head = S.get("head", "plain")
    if head == "hood":
        face = "human"        # под капюшоном видно лицо, поверх — неоновый визор
    if head == "ninja":
        face = "ninja"
    if head == "great_helm":
        face = "none"
    if face != "skull":
        hm = head_mesh(hr, S.get("mob", False))
        to_bone(hm, "head")
    build_face(hr, face if face != "visor" else "visor")
    build_headwear(hr)
    for i, s in ((0, -1), (1, 1)):
        build_hand(i, s)
        build_boot(i, s)
    build_clothes()
    build_weapon()
    path = os.path.join(OUT, key + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_skins=True,
                              export_animations=False, export_yup=True, export_materials="EXPORT")
    print("EXPORTED", key, os.path.getsize(path))
    if PREVIEW:
        render_preview(key)


def render_preview(key):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 24
    sc.cycles.use_denoising = True
    sc.render.resolution_x = 360
    sc.render.resolution_y = 520
    sc.render.film_transparent = False
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.05, 0.09, 1)
    sc.world = w
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    link(cam)
    cam.location = (1.3, -3.4, 1.35)
    cam.rotation_euler = (math.radians(86), 0, math.radians(21))
    cam.data.lens = 50
    sc.camera = cam
    for loc, e, c in (((2.5, -2.5, 3.0), 500, (1.0, 0.9, 0.8)), ((-3, -1.5, 1.5), 180, (0.5, 0.6, 1.0)), ((0, 3, 2.5), 400, (1.0, 0.5, 0.8))):
        L = bpy.data.objects.new("L", bpy.data.lights.new("L", "AREA"))
        L.data.energy = e
        L.data.color = c
        L.data.size = 2
        L.location = loc
        link(L)
        d = Vector((0, 0, 1.1)) - Vector(loc)
        L.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(OUT, "preview", key + ".png")
    bpy.ops.render.render(write_still=True)
    # Крупный план лица в три четверти
    cam.location = (0.32, -0.62, 1.76)
    d = Vector((0, 0, 1.735)) - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 60
    sc.render.resolution_x = 360
    sc.render.resolution_y = 360
    sc.render.filepath = os.path.join(OUT, "preview", key + "_face.png")
    bpy.ops.render.render(write_still=True)


keys = ONLY if ONLY else [k for k, v in SPECS.items() if v.get("kind") == "biped"]
fails = []
for k in keys:
    try:
        build(k)
    except Exception as e:
        import traceback
        traceback.print_exc()
        fails.append(k)
print("FAILED:", fails)
