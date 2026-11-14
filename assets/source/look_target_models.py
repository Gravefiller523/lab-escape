# Builds the look target's first models in Blender (roadmap WP21) and exports them as .glb files.
# Run from the project folder:
#   blender --background --factory-startup --python assets/source/look_target_models.py
# Every model is chunky low-poly with flat shading, UV-mapped onto the Zoology palette texture (one 256 x 256 image
# of colour squares, docs/ART_BIBLE.md section 4), so it needs no texture of its own.
# Blender +Y becomes Godot -Z (forward), so faces and heads point to +Y here.

import math
import os

import bpy
import bmesh

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PALETTE_PATH = os.path.join(ROOT, "assets", "textures", "zoology", "palette_zoology.png")
MODEL_DIR = os.path.join(ROOT, "assets", "models")

# The palette: 8 x 8 squares of 32 px. Name -> (column, row, colour).
SWATCH = 32
PALETTE = {
    "fur": (0, 0, (0.42, 0.40, 0.42)),
    "fur_dark": (1, 0, (0.28, 0.26, 0.28)),
    "skin_pink": (2, 0, (0.93, 0.62, 0.62)),
    "tooth": (3, 0, (0.96, 0.92, 0.78)),
    "eye": (4, 0, (0.05, 0.05, 0.06)),
    "eye_red": (5, 0, (0.85, 0.12, 0.10)),
    "wood": (0, 1, (0.62, 0.43, 0.25)),
    "wood_dark": (1, 1, (0.45, 0.30, 0.17)),
    "metal": (2, 1, (0.55, 0.57, 0.60)),
    "gem": (3, 1, (0.30, 0.85, 1.00)),
    "gem_light": (4, 1, (0.65, 0.95, 1.00)),
    "meat": (5, 1, (0.78, 0.28, 0.25)),
    "meat_fat": (6, 1, (0.96, 0.82, 0.74)),
    "bone": (7, 1, (0.95, 0.92, 0.84)),
    "glass": (0, 2, (0.80, 0.92, 0.95)),
    "dna_green": (1, 2, (0.40, 0.95, 0.45)),
    "cap_red": (2, 2, (0.85, 0.20, 0.18)),
    "label": (3, 2, (0.95, 0.95, 0.90)),
    "moss": (4, 2, (0.45, 0.60, 0.30)),
    "sand": (5, 2, (0.82, 0.74, 0.55)),
    "safety_yellow": (0, 3, (0.95, 0.74, 0.10)),
    "safety_yellow_worn": (1, 3, (0.78, 0.60, 0.12)),
    "steel": (2, 3, (0.42, 0.45, 0.50)),
    "steel_dark": (3, 3, (0.20, 0.22, 0.25)),
    "stripe_black": (4, 3, (0.08, 0.08, 0.09)),
    "rubber": (5, 3, (0.12, 0.12, 0.13)),
    "bolt": (6, 3, (0.70, 0.72, 0.75)),
    "plaster": (0, 4, (0.86, 0.80, 0.66)),
    "plaster_dirty": (1, 4, (0.70, 0.64, 0.50)),
    "hay": (2, 4, (0.90, 0.76, 0.36)),
    "hay_dark": (3, 4, (0.72, 0.56, 0.24)),
    "water": (4, 4, (0.35, 0.60, 0.75)),
    "skylight": (5, 4, (1.00, 0.95, 0.80)),
    "concrete": (6, 4, (0.62, 0.58, 0.50)),
    "feed_sack": (7, 4, (0.80, 0.72, 0.55)),
    "lab_white": (0, 5, (0.90, 0.93, 0.91)),
    "lab_panel": (1, 5, (0.80, 0.85, 0.82)),
    "lab_green": (2, 5, (0.28, 0.72, 0.40)),
    "lab_floor": (3, 5, (0.74, 0.78, 0.75)),
    "leaf": (4, 5, (0.30, 0.62, 0.25)),
    "leaf_dark": (5, 5, (0.18, 0.42, 0.18)),
    "soil": (6, 5, (0.35, 0.25, 0.17)),
    "terracotta": (7, 5, (0.78, 0.42, 0.28)),
    "light_strip": (0, 6, (0.95, 1.00, 0.95)),
    "mushroom_cap": (1, 6, (0.80, 0.30, 0.20)),
    "mushroom_stalk": (2, 6, (0.92, 0.88, 0.78)),
    "spore": (3, 6, (0.78, 0.72, 0.36)),
    "vine": (4, 6, (0.36, 0.52, 0.22)),
    "flytrap_mouth": (5, 6, (0.80, 0.25, 0.30)),
}


def make_palette():
    size = SWATCH * 8
    image = bpy.data.images.new("palette_zoology", size, size, alpha=False)
    pixels = [0.5] * (size * size * 4)
    for name, (column, row, colour) in PALETTE.items():
        for y in range(row * SWATCH, (row + 1) * SWATCH):
            image_y = size - 1 - y
            for x in range(column * SWATCH, (column + 1) * SWATCH):
                index = (image_y * size + x) * 4
                pixels[index:index + 4] = [colour[0], colour[1], colour[2], 1.0]
    image.pixels = pixels
    os.makedirs(os.path.dirname(PALETTE_PATH), exist_ok=True)
    image.filepath_raw = PALETTE_PATH
    image.file_format = "PNG"
    image.save()
    return image


def palette_material(image, name="palette_zoology", transparent=False):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image
    texture.interpolation = "Closest"
    material.node_tree.links.new(texture.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.8
    if transparent:
        bsdf.inputs["Alpha"].default_value = 0.45
        material.blend_method = "BLEND"
    return material


def swatch_uv(name):
    column, row, _ = PALETTE[name]
    u = (column + 0.5) / 8.0
    v = 1.0 - (row + 0.5) / 8.0
    return (u, v)


def paint(obj, swatch):
    """Every face of this part shows one palette square."""
    mesh = obj.data
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    uv = swatch_uv(swatch)
    for loop in mesh.uv_layers.active.data:
        loop.uv = uv


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in list(bpy.data.meshes):
        bpy.data.meshes.remove(block)


def part(kind, swatch, location=(0, 0, 0), scale=(1, 1, 1), rotation=(0, 0, 0), **kwargs):
    if kind == "cube":
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    elif kind == "ico":
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=kwargs.get("subdivisions", 1), radius=0.5, location=location)
    elif kind == "uv":
        bpy.ops.mesh.primitive_uv_sphere_add(segments=kwargs.get("segments", 8), ring_count=kwargs.get("rings", 5),
                                             radius=0.5, location=location)
    elif kind == "cylinder":
        bpy.ops.mesh.primitive_cylinder_add(vertices=kwargs.get("vertices", 8), radius=0.5, depth=1.0,
                                            location=location)
    elif kind == "cone":
        bpy.ops.mesh.primitive_cone_add(vertices=kwargs.get("vertices", 8), radius1=0.5, radius2=kwargs.get("tip", 0.0),
                                        depth=1.0, location=location)
    obj = bpy.context.active_object
    obj.scale = scale
    obj.rotation_euler = [math.radians(a) for a in rotation]
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    paint(obj, swatch)
    return obj


def join_and_export(parts, name, material, folder, origin_at_base):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    model = bpy.context.active_object
    model.name = name
    for polygon in model.data.polygons:
        polygon.use_smooth = False
    model.data.materials.clear()
    model.data.materials.append(material)
    if origin_at_base:
        lowest = min((model.matrix_world @ v.co).z for v in model.data.vertices)
        bpy.context.scene.cursor.location = (0, 0, lowest)
        bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
        model.location = (0, 0, 0)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    triangles = sum(len(p.vertices) - 2 for p in model.data.polygons)
    out_dir = os.path.join(MODEL_DIR, folder)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, name + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    model.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format="GLB", export_yup=True,
                              export_apply=True)
    print("EXPORTED %s (%d triangles)" % (path, triangles))
    bpy.data.objects.remove(model)


def rat(material):
    parts = [
        part("uv", "fur", (0, 0, 0.15), (0.32, 0.5, 0.26), segments=10, rings=6),          # body
        part("uv", "fur", (0, 0.27, 0.19), (0.22, 0.26, 0.2), segments=8, rings=5),        # head
        part("cone", "skin_pink", (0, 0.42, 0.18), (0.1, 0.1, 0.12), (-90, 0, 0)),         # snout
        part("uv", "skin_pink", (0, 0.48, 0.18), (0.05, 0.05, 0.05), segments=6, rings=4),  # nose
        part("cube", "tooth", (0.018, 0.355, 0.125), (0.03, 0.025, 0.07)),                   # teeth, under the head
        part("cube", "tooth", (-0.018, 0.355, 0.125), (0.03, 0.025, 0.07)),
        part("uv", "eye_red", (0.07, 0.36, 0.24), (0.045, 0.045, 0.045), segments=6, rings=4),
        part("uv", "eye_red", (-0.07, 0.36, 0.24), (0.045, 0.045, 0.045), segments=6, rings=4),
        part("cylinder", "skin_pink", (0.09, 0.24, 0.3), (0.12, 0.12, 0.02), (90, 0, 20), vertices=8),  # ears
        part("cylinder", "skin_pink", (-0.09, 0.24, 0.3), (0.12, 0.12, 0.02), (90, 0, -20), vertices=8),
    ]
    for x in (0.1, -0.1):
        for y in (0.13, -0.15):
            parts.append(part("cube", "fur_dark", (x, y, 0.03), (0.06, 0.08, 0.07)))         # stubby legs
    previous = (0, -0.22, 0.12)
    for index in range(6):                                                                  # tail, curling up
        sideways = math.radians(index * 14)
        lift = math.radians(index * 9)
        step = 0.075
        direction = (math.sin(sideways) * math.cos(lift), -math.cos(sideways) * math.cos(lift), math.sin(lift))
        nxt = tuple(p + d * step for p, d in zip(previous, direction))
        mid = tuple((a + b) / 2 for a, b in zip(previous, nxt))
        width = 0.034 - index * 0.004
        segment = part("cylinder", "skin_pink", mid, (width, width, step * 1.35), vertices=6)
        # Point the segment along its direction (a cylinder starts along Z).
        segment.rotation_mode = "QUATERNION"
        from mathutils import Vector
        segment.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(Vector(direction))
        bpy.ops.object.select_all(action="DESELECT")
        segment.select_set(True)
        bpy.context.view_layer.objects.active = segment
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
        parts.append(segment)
        previous = nxt
    join_and_export(parts, "enemy_rat", material, "zoology", True)


def crate(material):
    parts = [part("cube", "wood", (0, 0, 0), (0.56, 0.56, 0.56))]
    for axis in range(3):                                                                    # frame on the edges
        for a in (-1, 1):
            for b in (-1, 1):
                location = [0, 0, 0]
                scale = [0.07, 0.07, 0.07]
                other = [i for i in range(3) if i != axis]
                location[other[0]] = a * 0.28
                location[other[1]] = b * 0.28
                scale[axis] = 0.6
                parts.append(part("cube", "wood_dark", tuple(location), tuple(scale)))
    for side in (-1, 1):                                                                     # a diagonal brace
        parts.append(part("cube", "wood_dark", (0, side * 0.285, 0), (0.06, 0.03, 0.72), (0, 45, 0)))
    join_and_export(parts, "prop_crate", material, "shared", False)


def gem(material, name, size):
    parts = [
        part("ico", "gem", (0, 0, 0), (size * 0.8, size * 0.8, size), subdivisions=1),
        part("ico", "gem_light", (size * 0.12, -size * 0.18, size * 0.15), (size * 0.25, size * 0.25, size * 0.3),
             subdivisions=1),
    ]
    join_and_export(parts, name, material, "shared", False)


def meat(material):
    parts = [
        part("uv", "meat", (0.03, 0, 0), (0.22, 0.17, 0.13), segments=8, rings=5),
        part("uv", "meat_fat", (0.06, 0.02, 0.05), (0.12, 0.08, 0.04), segments=6, rings=4),
        part("cylinder", "bone", (-0.12, 0, 0), (0.035, 0.035, 0.12), (0, 90, 0), vertices=6),
        part("uv", "bone", (-0.18, 0.02, 0), (0.05, 0.05, 0.05), segments=6, rings=4),
        part("uv", "bone", (-0.18, -0.02, 0), (0.05, 0.05, 0.05), segments=6, rings=4),
    ]
    join_and_export(parts, "prop_meat", material, "shared", False)


def vial(material, glass_material):
    # The liquid is its own mesh: the game tints it the colour of the mutation inside (glow_tint.gd).
    liquid = [part("cylinder", "dna_green", (0, 0, -0.02), (0.08, 0.08, 0.15), vertices=10)]
    join_and_export(liquid, "prop_dna_vial_liquid", material, "shared", False)
    cap = [
        part("cylinder", "cap_red", (0, 0, 0.1), (0.11, 0.11, 0.04), vertices=10),
        part("cube", "label", (0, -0.045, -0.02), (0.06, 0.012, 0.07)),
    ]
    join_and_export(cap, "prop_dna_vial", material, "shared", False)
    glass = [part("cylinder", "glass", (0, 0, -0.005), (0.1, 0.1, 0.2), vertices=10)]
    join_and_export(glass, "prop_dna_vial_glass", glass_material, "shared", False)


def lift(material):
    """The cargo lift's cage (docs/systems/cargo_lift.md): 5 x 5 m inside, 3.4 m high, the gate at +Y here (Godot
    -Z), the back wall with the part panel at -Y. The doors, slots and buttons stay the lift's own nodes."""
    inside_x, inside_y, height, wall = 5.0, 5.0, 3.4, 0.2
    hx, hy = inside_x / 2.0, inside_y / 2.0
    parts = [
        part("cube", "steel_dark", (0, 0, -0.15), (inside_x + wall * 2, inside_y + wall * 2, 0.3)),       # platform
        part("cube", "steel", (0, -hy - wall / 2.0, height / 2.0), (inside_x + wall * 2, wall, height)),  # back wall
        part("cube", "steel_dark", (0, 0, height + wall / 2.0), (inside_x + wall * 2, inside_y + wall * 2, wall)),
    ]
    # Floor treads and a yellow and black edge at the gate.
    for index in range(9):
        parts.append(part("cube", "steel", (0, -hy + 0.3 + index * 0.55, 0.005), (inside_x - 0.3, 0.06, 0.02)))
    for index in range(10):
        swatch = "safety_yellow" if index % 2 == 0 else "stripe_black"
        parts.append(part("cube", swatch, (-hx + 0.25 + index * 0.5, hy - 0.12, 0.01), (0.5, 0.24, 0.03)))
    # Corner posts and beams in safety yellow, worn where hands touch.
    for x in (-hx - wall / 2.0, hx + wall / 2.0):
        for y in (-hy - wall / 2.0, 0.0, hy + wall / 2.0):
            parts.append(part("cube", "safety_yellow", (x, y, height / 2.0), (wall * 1.2, wall * 1.2, height)))
        parts.append(part("cube", "safety_yellow_worn", (x, 0, 1.05), (wall * 0.8, inside_y, 0.1)))     # railing
        parts.append(part("cube", "steel", (x, 0, 0.15), (wall * 0.9, inside_y, 0.3)))                  # kick plate
        parts.append(part("cube", "safety_yellow", (x, 0, height - 0.1), (wall * 1.2, inside_y + wall, 0.2)))
    parts.append(part("cube", "safety_yellow", (0, hy + wall / 2.0, height - 0.1), (inside_x + wall * 2, wall * 1.2, 0.2)))
    # Back wall: ribs, bolts, and a dark frame round the part panel.
    for x in (-2.0, -1.0, 0.0, 1.0, 2.0):
        parts.append(part("cube", "steel_dark", (x, -hy + 0.02, height / 2.0), (0.08, 0.06, height - 0.2)))
    for x in (-2.4, 2.4):
        for z in (0.2, 1.7, 3.2):
            parts.append(part("cylinder", "bolt", (x, -hy + 0.04, z), (0.07, 0.07, 0.04), (90, 0, 0), vertices=6))
    parts.append(part("cube", "rubber", (-0.9, -hy + 0.03, 1.25), (3.3, 0.03, 2.2)))
    # A caged work light on the roof.
    parts.append(part("cube", "steel_dark", (0, 0, height - 0.08), (0.6, 0.3, 0.12)))
    join_and_export(parts, "lift_cage", material, "shared", True)

    # One gate door: 2.5 m wide, 3 m high, a yellow frame round a steel mesh.
    door_w, door_h = inside_x / 2.0, height - 0.4
    door = [part("cube", "safety_yellow", (0, 0, door_h / 2.0), (door_w, 0.06, 0.12))]
    door.append(part("cube", "safety_yellow", (0, 0, -door_h / 2.0), (door_w, 0.06, 0.12)))
    for x in (-door_w / 2.0, door_w / 2.0):
        door.append(part("cube", "safety_yellow", (x, 0, 0), (0.12, 0.08, door_h)))
    for index in range(1, 8):
        door.append(part("cube", "steel", (-door_w / 2.0 + index * door_w / 8.0, 0, 0), (0.03, 0.03, door_h)))
    for index in range(1, 6):
        door.append(part("cube", "steel", (0, 0, -door_h / 2.0 + index * door_h / 6.0), (door_w, 0.03, 0.03)))
    join_and_export(door, "lift_door", material, "shared", False)


def g(x, y, z):
    """A Godot position (x right, y up, z towards the viewer) in Blender's axes."""
    return (x, -z, y)


ZOOLOGY = {"lower": "wood", "upper": "plaster", "trim": "wood_dark", "ceiling": "plaster_dirty", "beam": "wood_dark",
           "light": None}
BOTANY = {"lower": "lab_panel", "upper": "lab_white", "trim": "lab_green", "ceiling": "lab_white", "beam": None,
          "light": "light_strip"}


def wall_with_gaps(parts, start, end, gaps, height, thickness, style=None):
    """A wall from start to end (Godot x, z on the floor), with doorway gaps [(centre along the wall, width)]: a
    wooden lower half and plaster above, with a header over each doorway."""
    sx, sz = start
    ex, ez = end
    along_x = abs(ex - sx) > abs(ez - sz)
    length = abs(ex - sx) if along_x else abs(ez - sz)
    cuts = [0.0]
    for centre, width in sorted(gaps):
        cuts += [centre - width / 2.0, centre + width / 2.0]
    cuts.append(length)
    for index in range(0, len(cuts), 2):
        a, b = cuts[index], cuts[index + 1]
        if b - a < 0.01:
            continue
        mid = (a + b) / 2.0
        cx = sx + (mid if along_x else 0.0)
        cz = sz + (0.0 if along_x else mid)
        seg = (b - a, thickness) if along_x else (thickness, b - a)
        s = style or ZOOLOGY
        parts.append(part("cube", s["lower"], g(cx, 0.6, cz), (seg[0], seg[1], 1.2)))
        parts.append(part("cube", s["upper"], g(cx, 0.6 + height / 2.0, cz), (seg[0], seg[1], height - 1.2)))
        parts.append(part("cube", s["trim"], g(cx, 1.22, cz), (seg[0] + 0.02, seg[1] + 0.04, 0.08)))
    for centre, width in gaps:
        cx = sx + (centre if along_x else 0.0)
        cz = sz + (0.0 if along_x else centre)
        seg = (width, thickness) if along_x else (thickness, width)
        parts.append(part("cube", (style or ZOOLOGY)["upper"], g(cx, 2.8 + (height - 2.8) / 2.0, cz), (seg[0], seg[1], height - 2.8)))


def fence(parts, start, end, height=2.2):
    """Cage bars from start to end (Godot x, z): a wooden kick board, bars every 0.3 m and a top rail."""
    sx, sz = start
    ex, ez = end
    length = math.hypot(ex - sx, ez - sz)
    along_x = abs(ex - sx) > abs(ez - sz)
    mid = ((sx + ex) / 2.0, (sz + ez) / 2.0)
    size = (length, 0.08) if along_x else (0.08, length)
    parts.append(part("cube", "wood_dark", g(mid[0], 0.25, mid[1]), (size[0], size[1], 0.5)))
    parts.append(part("cube", "steel", g(mid[0], height, mid[1]), (size[0] + 0.06, size[1] + 0.04, 0.08)))
    count = max(int(length / 0.3), 1)
    for index in range(count + 1):
        t = index / count
        x = sx + (ex - sx) * t
        z = sz + (ez - sz) * t
        parts.append(part("cylinder", "steel", g(x, 0.5 + (height - 0.5) / 2.0, z), (0.035, 0.035, height - 0.5),
                          vertices=4))


def hay_bale(parts, x, z, turn=0.0, stack=1):
    for level in range(stack):
        parts.append(part("cube", "hay", g(x, 0.22 + level * 0.44, z), (0.9, 0.5, 0.44), (0, 0, turn + level * 12)))
        parts.append(part("cube", "hay_dark", g(x, 0.22 + level * 0.44, z), (0.92, 0.1, 0.46), (0, 0, turn + level * 12)))


def animal_holding(material):
    """Zoology's animal holding room (tile_zoology_animal_holding, 18 x 18 m, 3.6 m high): the shell, four pens of
    cage bars on the same lines as the grey box's pens, hay, troughs and feed sacks, and skylights."""
    size, height, wall = 18.0, 3.6, 0.3
    parts = [part("cube", "concrete", g(size / 2.0, -0.05, size / 2.0), (size, size, 0.1))]
    # Straw on the floor inside the pens, and a drain down the aisle.
    for x, z, w, d in ((2.5, 2.5, 4.6, 4.6), (14.0, 2.5, 7.6, 4.6), (2.5, 15.5, 4.6, 4.6), (15.5, 15.5, 4.6, 4.6)):
        parts.append(part("cube", "hay_dark", g(x, 0.012, z), (w, d, 0.02)))
    parts.append(part("cube", "steel_dark", g(9.0, 0.006, 9.0), (0.3, 8.0, 0.012)))
    wall_with_gaps(parts, (0.0, -wall / 2.0), (size, -wall / 2.0), [(7.5, 2.4)], height, wall)          # north
    wall_with_gaps(parts, (0.0, size + wall / 2.0), (size, size + wall / 2.0), [(10.5, 2.4)], height, wall)  # south
    wall_with_gaps(parts, (-wall / 2.0, 0.0), (-wall / 2.0, size), [(7.5, 2.4)], height, wall)          # west
    wall_with_gaps(parts, (size + wall / 2.0, 0.0), (size + wall / 2.0, size), [(10.5, 2.4)], height, wall)  # east
    # Ceiling: dark beams and four skylights (one is broken: a dark hole, for the damaged look).
    parts.append(part("cube", "plaster_dirty", g(size / 2.0, height + 0.05, size / 2.0), (size + wall * 2, size + wall * 2, 0.1)))
    for z in (3.0, 6.0, 9.0, 12.0, 15.0):
        parts.append(part("cube", "wood_dark", g(size / 2.0, height - 0.15, z), (size, 0.25, 0.3)))
    for x, z in ((4.5, 4.5), (13.5, 4.5), (4.5, 13.5), (13.5, 13.5)):
        parts.append(part("cube", "skylight", g(x, height - 0.01, z), (2.2, 2.2, 0.02)))
        parts.append(part("cube", "steel_dark", g(x, height - 0.05, z), (2.4, 0.1, 0.1)))
        parts.append(part("cube", "steel_dark", g(x, height - 0.05, z), (0.1, 2.4, 0.1)))
    # The pens: the same lines as the grey box (each side wall and front, with a 1.2 m gate gap in the front).
    fence(parts, (5.0, 0.15), (5.0, 4.0))
    fence(parts, (0.15, 5.0), (3.5, 5.0))
    fence(parts, (10.0, 0.15), (10.0, 4.0))
    fence(parts, (11.5, 5.0), (17.85, 5.0))
    fence(parts, (5.0, 13.0), (5.0, 17.85))
    fence(parts, (0.15, 13.0), (3.5, 13.0))
    fence(parts, (13.0, 13.0), (13.0, 17.85))
    fence(parts, (14.5, 13.0), (17.85, 13.0))
    # Hay, troughs and feed sacks.
    hay_bale(parts, 1.4, 1.2, 10, 2)
    hay_bale(parts, 16.4, 1.3, -5, 1)
    hay_bale(parts, 1.3, 16.6, 0, 2)
    hay_bale(parts, 16.5, 16.5, 20, 1)
    for x, z in ((3.0, 3.9), (15.0, 3.9), (3.0, 14.1), (15.5, 14.1)):
        parts.append(part("cube", "steel", g(x, 0.25, z), (1.4, 0.45, 0.5)))
        parts.append(part("cube", "water", g(x, 0.42, z), (1.25, 0.35, 0.06)))
    for index, (x, z) in enumerate(((8.2, 1.0), (8.8, 1.1), (8.5, 1.0))):
        parts.append(part("uv", "feed_sack", g(x, 0.3 + (0.45 if index == 2 else 0.0), z), (0.55, 0.4, 0.6), (0, 0, index * 25),
                          segments=6, rings=4))
    # A hose reel and a pail by the east door.
    parts.append(part("cylinder", "moss", g(17.6, 1.4, 8.0), (0.6, 0.6, 0.15), (90, 0, 90), vertices=10))
    parts.append(part("cylinder", "steel", g(16.8, 0.2, 8.6), (0.35, 0.35, 0.4), vertices=8))
    join_and_export(parts, "room_zoology_animal_holding", material, "zoology", False)


def room_shell(parts, width, depth, doors, floor_swatch="concrete", height=3.6, wall=0.3, style=None):
    """Floor, four walls with doorway gaps and a ceiling for a tile of width x depth metres (origin at its corner).
    doors: {"N": [x...], "S": [x...], "W": [z...], "E": [z...]}: each doorway's centre along that wall (2.4 m wide)."""
    parts.append(part("cube", floor_swatch, g(width / 2.0, -0.05, depth / 2.0), (width, depth, 0.1)))
    gaps = {side: [(c, 2.4) for c in doors.get(side, [])] for side in "NSWE"}
    s = style or ZOOLOGY
    wall_with_gaps(parts, (0.0, -wall / 2.0), (width, -wall / 2.0), gaps["N"], height, wall, s)
    wall_with_gaps(parts, (0.0, depth + wall / 2.0), (width, depth + wall / 2.0), gaps["S"], height, wall, s)
    wall_with_gaps(parts, (-wall / 2.0, 0.0), (-wall / 2.0, depth), gaps["W"], height, wall, s)
    wall_with_gaps(parts, (width + wall / 2.0, 0.0), (width + wall / 2.0, depth), gaps["E"], height, wall, s)
    parts.append(part("cube", s["ceiling"], g(width / 2.0, height + 0.05, depth / 2.0), (width + wall * 2, depth + wall * 2, 0.1)))
    for z in [3.0 * i for i in range(1, int(depth / 3.0))]:
        if s["beam"]:
            parts.append(part("cube", s["beam"], g(width / 2.0, height - 0.15, z), (width, 0.25, 0.3)))
        if s["light"]:
            parts.append(part("cube", s["light"], g(width / 2.0, height - 0.01, z), (width * 0.7, 0.25, 0.02)))


def vet_surgery(material):
    """Zoology's vet surgery (tile_zoology_vet_surgery, 12 x 12 m): a pale tiled floor, the operating table under a
    big lamp, an instrument trolley, a glass-fronted cabinet, a sink and an X-ray light box."""
    w = d = 12.0
    parts = []
    room_shell(parts, w, d, {"N": [4.5], "S": [7.5], "W": [7.5], "E": [4.5]}, "label")
    for i in range(1, 12):                                                         # floor tile grout
        parts.append(part("cube", "plaster_dirty", g(float(i), 0.004, d / 2.0), (0.03, d, 0.008)))
        parts.append(part("cube", "plaster_dirty", g(w / 2.0, 0.004, float(i)), (w, 0.03, 0.008)))
    # Operating table (2.2 x 1 m top, 1 m high) and its lamp.
    parts.append(part("cube", "metal", g(6.0, 0.95, 6.0), (2.2, 1.0, 0.1)))
    parts.append(part("cube", "steel_dark", g(6.0, 0.45, 6.0), (0.3, 0.3, 0.9)))
    parts.append(part("cube", "steel_dark", g(6.0, 0.05, 6.0), (1.4, 0.7, 0.1)))
    parts.append(part("cube", "water", g(6.0, 1.02, 6.0), (2.0, 0.8, 0.04)))
    parts.append(part("cylinder", "steel_dark", g(6.0, 3.1, 6.0), (0.05, 0.05, 1.0), vertices=6))
    parts.append(part("cylinder", "metal", g(6.0, 2.55, 6.0), (0.9, 0.9, 0.15), vertices=12))
    parts.append(part("cylinder", "skylight", g(6.0, 2.47, 6.0), (0.75, 0.75, 0.02), vertices=12))
    # Instrument trolley (1 x 0.6 m, two shelves).
    for y in (0.3, 0.85):
        parts.append(part("cube", "metal", g(9.0, y, 9.0), (1.0, 0.6, 0.04)))
    for x in (8.55, 9.45):
        for z in (8.75, 9.25):
            parts.append(part("cylinder", "steel", g(x, 0.45, z), (0.04, 0.04, 0.9), vertices=4))
    parts.append(part("cube", "bolt", g(8.8, 0.9, 9.0), (0.3, 0.2, 0.04)))
    # Cabinet against the north wall (3 x 2 x 0.8 m) with glass doors and bottles.
    parts.append(part("cube", "wood_dark", g(9.5, 1.0, 0.55), (3.0, 0.8, 2.0)))
    parts.append(part("cube", "glass", g(9.5, 1.3, 0.94), (2.8, 0.02, 1.2)))
    for i in range(6):
        parts.append(part("cylinder", ("dna_green", "cap_red", "water")[i % 3], g(8.4 + i * 0.42, 1.35, 0.8),
                          (0.1, 0.1, 0.25), vertices=6))
    # Sink on the west wall and an X-ray light box above it.
    parts.append(part("cube", "metal", g(0.45, 0.9, 3.0), (0.6, 1.2, 0.2)))
    parts.append(part("cube", "steel_dark", g(0.4, 0.45, 3.0), (0.5, 0.9, 0.9)))
    parts.append(part("cube", "skylight", g(0.04, 2.0, 3.0), (0.02, 1.0, 0.7)))
    join_and_export(parts, "room_zoology_vet_surgery", material, "zoology", False)


def sack(parts, x, y, z, turn):
    parts.append(part("uv", "feed_sack", g(x, y, z), (0.75, 0.5, 0.32), (0, 0, turn), segments=6, rings=4))
    parts.append(part("cube", "wood_dark", g(x, y + 0.15, z), (0.1, 0.4, 0.05), (0, 0, turn)))


def feed_storage(material):
    """Zoology's feed storage (tile_zoology_feed_storage, 9 x 9 m): sack piles in the four corners (on the grey box's
    1.8 m squares), a shelf of tins, a scoop and spilt feed."""
    w = d = 9.0
    parts = []
    room_shell(parts, w, d, {"N": [4.5], "S": [4.5], "W": [4.5], "E": [4.5]})
    for cx, cz in ((1.2, 1.2), (7.8, 1.2), (1.2, 7.8), (7.8, 7.8)):
        parts.append(part("cube", "wood", g(cx, 0.06, cz), (1.8, 1.8, 0.12)))         # a pallet
        # Three layers, so the pile fills the grey box's 1 m tall collision.
        for level, offsets in enumerate(([(-0.4, -0.4), (0.4, -0.4), (-0.4, 0.4), (0.4, 0.4)],
                                         [(-0.3, -0.3), (0.35, -0.25), (0.0, 0.35)], [(0.0, 0.0)])):
            for i, (ox, oz) in enumerate(offsets):
                sack(parts, cx + ox, 0.3 + level * 0.32, cz + oz, (i * 37 + level * 50) % 90)
    # Spilt feed, a scoop and a shelf of tins on the south wall.
    parts.append(part("cube", "hay_dark", g(5.6, 0.01, 6.2), (1.4, 0.9, 0.02), (0, 0, 20)))
    parts.append(part("cube", "steel", g(5.9, 0.06, 6.0), (0.35, 0.2, 0.12), (0, 0, 30)))
    parts.append(part("cube", "wood_dark", g(4.5, 1.4, 8.8), (2.4, 0.4, 0.06)))
    parts.append(part("cube", "wood_dark", g(4.5, 1.9, 8.8), (2.4, 0.4, 0.06)))
    for i in range(6):
        parts.append(part("cylinder", ("metal", "cap_red", "moss")[i % 3], g(3.6 + i * 0.36, 1.58, 8.8),
                          (0.22, 0.22, 0.3), vertices=8))
    join_and_export(parts, "room_zoology_feed_storage", material, "zoology", False)


def observation_room(material):
    """Zoology's observation room (9 x 12 m): two counters with big viewing windows across the middle, stools,
    clipboards and a coffee mug. The pieces match the grey box's collision boxes."""
    w, d = 9.0, 12.0
    parts = []
    room_shell(parts, w, d, {"N": [4.5], "S": [4.5], "W": [7.5], "E": [4.5]}, "wood")
    for cx in (1.575, 7.425):
        parts.append(part("cube", "wood_dark", g(cx, 0.5, 6.0), (2.85, 0.6, 1.0)))       # counter
        parts.append(part("cube", "wood", g(cx, 1.02, 6.0), (2.95, 0.7, 0.05)))         # its top
        parts.append(part("cube", "glass", g(cx, 1.7, 6.0), (2.85, 0.05, 1.4)))        # window
        parts.append(part("cube", "steel_dark", g(cx, 2.42, 6.0), (2.9, 0.1, 0.06)))
        for x in (cx - 0.9, cx + 0.9):
            parts.append(part("cylinder", "steel_dark", g(x, 0.35, 7.0), (0.06, 0.06, 0.7), vertices=6))
            parts.append(part("cylinder", "cap_red", g(x, 0.72, 7.0), (0.4, 0.4, 0.06), vertices=8))
        parts.append(part("cube", "label", g(cx - 0.6, 1.06, 6.1), (0.3, 0.4, 0.02), (0, 0, 15)))
    parts.append(part("cylinder", "label", g(1.0, 1.1, 5.95), (0.09, 0.09, 0.12), vertices=8))
    join_and_export(parts, "room_zoology_observation_room", material, "zoology", False)


def aquarium(material):
    """Zoology's aquarium (12 x 15 m): two long tanks and a round one in the middle on the grey box's footprints, with
    water, sand, weed and a few fish shapes; pipes along the north wall."""
    w, d = 12.0, 15.0
    parts = []
    room_shell(parts, w, d, {"N": [7.5], "S": [4.5], "W": [7.5], "E": [7.5]})
    for cx, cz in ((3.0, 3.5), (9.5, 11.5)):
        parts.append(part("cube", "steel_dark", g(cx, 0.3, cz), (4.0, 1.6, 0.6)))           # stand
        parts.append(part("cube", "water", g(cx, 1.3, cz), (3.9, 1.5, 1.4)))               # water
        parts.append(part("cube", "sand", g(cx, 0.68, cz), (3.85, 1.45, 0.15)))
        parts.append(part("cube", "steel_dark", g(cx, 2.02, cz), (4.0, 1.6, 0.06)))         # lid
        for i in range(5):
            parts.append(part("cone", "moss", g(cx - 1.5 + i * 0.7, 1.0, cz), (0.18, 0.18, 0.5)))
        for i in range(3):
            parts.append(part("uv", ("cap_red", "safety_yellow", "gem")[i], g(cx - 0.8 + i * 0.8, 1.35, cz + 0.2),
                              (0.25, 0.08, 0.14), segments=6, rings=4))
    parts.append(part("cylinder", "steel_dark", g(6.0, 0.15, 7.5), (2.0, 2.0, 0.3), vertices=12))
    parts.append(part("cylinder", "water", g(6.0, 0.9, 7.5), (1.9, 1.9, 1.2), vertices=12))
    parts.append(part("cylinder", "steel_dark", g(6.0, 1.52, 7.5), (2.0, 2.0, 0.04), vertices=12))
    for x in (0.5, 11.5):
        parts.append(part("cylinder", "steel", g(x, 3.0, d / 2.0), (0.15, 0.15, d - 0.6), (90, 0, 0), vertices=6))
    join_and_export(parts, "room_zoology_aquarium", material, "zoology", False)


def habitat_sim(material):
    """Zoology's habitat simulation (15 x 18 m): fake grass, two rocks and a tree on the grey box's footprints,  and
    low tufts of grass (low enough to walk over: the grey box has nothing there)."""
    w, d = 15.0, 18.0
    parts = []
    room_shell(parts, w, d, {"N": [4.5], "S": [10.5], "W": [4.5], "E": [13.5]}, "moss")
    for cx, cz, sx, sz, h in ((11.0, 4.0, 3.0, 2.5, 1.2), (4.0, 12.0, 3.0, 3.0, 1.0)):
        parts.append(part("ico", "plaster_dirty", g(cx, h / 2.0, cz), (sx * 1.05, sz * 1.05, h * 1.15), subdivisions=1))
    parts.append(part("cylinder", "wood_dark", g(8.0, 1.8, 9.0), (1.0, 1.0, 3.6), vertices=8))
    parts.append(part("ico", "moss", g(8.0, 3.2, 9.0), (3.2, 3.2, 1.2), subdivisions=1))
    for x, z in ((2.0, 3.0), (13.0, 15.0), (6.5, 15.5), (12.5, 9.0)):
        parts.append(part("cone", "moss", g(x, 0.1, z), (0.8, 0.8, 0.2), vertices=6))
    join_and_export(parts, "room_zoology_habitat_sim", material, "zoology", False)


def quarantine_pens(material):
    """Zoology's quarantine pens (9 x 12 m): two barred cells on the grey box's lines, warning stripes, and a
    biohazard bin."""
    w, d = 9.0, 12.0
    parts = []
    room_shell(parts, w, d, {"N": [4.5], "S": [4.5], "W": [7.5], "E": [4.5]})
    fence(parts, (3.0, 0.15), (3.0, 2.5))
    fence(parts, (0.15, 2.5), (2.0, 2.5))
    fence(parts, (6.0, 9.5), (6.0, 11.85))
    fence(parts, (7.0, 9.5), (8.85, 9.5))
    for i in range(8):
        swatch = "safety_yellow" if i % 2 == 0 else "stripe_black"
        parts.append(part("cube", swatch, g(0.2 + i * 0.35, 0.006, 2.75), (0.35, 0.2, 0.012)))
        parts.append(part("cube", swatch, g(6.3 + i * 0.35, 0.006, 9.25), (0.35, 0.2, 0.012)))
    hay_bale(parts, 1.2, 1.1, 5, 1)
    hay_bale(parts, 7.8, 10.9, -10, 1)
    parts.append(part("cylinder", "cap_red", g(8.4, 0.4, 0.6), (0.6, 0.6, 0.8), vertices=8))
    join_and_export(parts, "room_zoology_quarantine_pens", material, "zoology", False)


def bat(material):
    """The bat (enemy_bat): a furry body between two wide leather wings, big ears, red eyes. Centred on its middle
    (it flies), about 0.8 m from wing tip to wing tip."""
    parts = [
        part("uv", "fur_dark", (0, 0, 0), (0.2, 0.26, 0.18), segments=8, rings=5),
        part("uv", "fur_dark", (0, 0.15, 0.04), (0.14, 0.13, 0.13), segments=8, rings=5),
        part("cone", "skin_pink", (0.05, 0.14, 0.13), (0.08, 0.05, 0.14), vertices=4),
        part("cone", "skin_pink", (-0.05, 0.14, 0.13), (0.08, 0.05, 0.14), vertices=4),
        part("uv", "eye_red", (0.035, 0.21, 0.06), (0.03, 0.03, 0.03), segments=6, rings=4),
        part("uv", "eye_red", (-0.035, 0.21, 0.06), (0.03, 0.03, 0.03), segments=6, rings=4),
        part("cube", "tooth", (0.012, 0.21, 0.0), (0.012, 0.012, 0.03)),
        part("cube", "tooth", (-0.012, 0.21, 0.0), (0.012, 0.012, 0.03)),
    ]
    for side in (-1, 1):                                                             # wings: three panels each
        for i, (x, y, w, d) in enumerate(((0.16, 0.0, 0.16, 0.22), (0.3, -0.02, 0.14, 0.18), (0.4, -0.05, 0.1, 0.12))):
            parts.append(part("cube", "fur", (side * x, y, 0.0), (w, d, 0.015), (0, side * (8 + i * 6), 0)))
        parts.append(part("cube", "fur_dark", (side * 0.28, 0.07, 0.01), (0.26, 0.02, 0.02), (0, side * 10, 0)))
    join_and_export(parts, "enemy_bat", material, "zoology", False)


def fly(material):
    """The fly (enemy_fly): a fat dark body, two huge red eyes, glassy wings. Centred on its middle, about 0.2 m."""
    parts = [
        part("uv", "steel_dark", (0, -0.03, 0), (0.12, 0.16, 0.1), segments=8, rings=5),
        part("uv", "rubber", (0, 0.07, 0.01), (0.09, 0.08, 0.08), segments=8, rings=5),
        part("uv", "eye_red", (0.045, 0.1, 0.03), (0.07, 0.06, 0.08), segments=8, rings=5),
        part("uv", "eye_red", (-0.045, 0.1, 0.03), (0.07, 0.06, 0.08), segments=8, rings=5),
        part("cube", "glass", (0.08, -0.02, 0.06), (0.14, 0.08, 0.008), (0, 15, 20)),
        part("cube", "glass", (-0.08, -0.02, 0.06), (0.14, 0.08, 0.008), (0, -15, -20)),
    ]
    for side in (-1, 1):
        for y in (0.03, -0.03):
            parts.append(part("cube", "rubber", (side * 0.06, y, -0.06), (0.08, 0.01, 0.01), (0, side * 40, 0)))
    join_and_export(parts, "enemy_fly", material, "zoology", False)


def kangaroo(material):
    """The kangaroo (enemy_kangaroo): 1.7 m tall, big feet, a thick tail, boxing gloves and a torn lab tag."""
    parts = [
        part("uv", "sand", (0, 0, 0.75), (0.5, 0.45, 0.7), segments=8, rings=6),             # body
        part("uv", "sand", (0, 0.06, 1.25), (0.32, 0.3, 0.36), segments=8, rings=5),         # chest
        part("uv", "sand", (0, 0.12, 1.55), (0.24, 0.3, 0.24), segments=8, rings=5),         # head
        part("cone", "sand", (0, 0.3, 1.52), (0.14, 0.14, 0.18), (-90, 0, 0), vertices=6),   # muzzle
        part("uv", "eye", (0, 0.39, 1.52), (0.05, 0.05, 0.05), segments=6, rings=4),
        part("uv", "eye", (0.07, 0.22, 1.6), (0.04, 0.04, 0.04), segments=6, rings=4),
        part("uv", "eye", (-0.07, 0.22, 1.6), (0.04, 0.04, 0.04), segments=6, rings=4),
        part("cone", "sand", (0.08, 0.06, 1.78), (0.1, 0.06, 0.26), vertices=4),            # ears
        part("cone", "sand", (-0.08, 0.06, 1.78), (0.1, 0.06, 0.26), vertices=4),
        part("cylinder", "sand", (0, -0.4, 0.3), (0.16, 0.16, 0.8), (60, 0, 0), vertices=6),  # tail
        part("cube", "label", (0.13, 0.2, 1.15), (0.1, 0.02, 0.12), (0, 0, 10)),             # torn lab tag
    ]
    for side in (-1, 1):
        parts.append(part("uv", "sand", (side * 0.17, 0.0, 0.35), (0.22, 0.3, 0.42), segments=6, rings=4))  # thighs
        parts.append(part("cube", "sand_dark" if "sand_dark" in PALETTE else "wood", (side * 0.17, 0.2, 0.05), (0.14, 0.5, 0.1)))  # feet
        parts.append(part("cylinder", "sand", (side * 0.2, 0.22, 1.12), (0.08, 0.08, 0.3), (60, 0, 0), vertices=6))  # arms
        parts.append(part("uv", "cap_red", (side * 0.2, 0.36, 1.22), (0.16, 0.16, 0.16), segments=8, rings=5))   # gloves
    join_and_export(parts, "enemy_kangaroo", material, "zoology", True)


def giant_rat(material):
    """The Giant Rat boss (boss_giant_rat): the rat's shape at 2.6 m long and 1.3 m tall, scarred, with a lab collar
    and a broken chain."""
    s = 4.6
    parts = [
        part("uv", "fur", (0, 0, 0.15 * s), (0.32 * s, 0.5 * s, 0.26 * s), segments=12, rings=7),
        part("uv", "fur", (0, 0.27 * s, 0.19 * s), (0.22 * s, 0.26 * s, 0.2 * s), segments=10, rings=6),
        part("cone", "skin_pink", (0, 0.42 * s, 0.18 * s), (0.1 * s, 0.1 * s, 0.12 * s), (-90, 0, 0)),
        part("uv", "skin_pink", (0, 0.48 * s, 0.18 * s), (0.05 * s, 0.05 * s, 0.05 * s), segments=6, rings=4),
        part("cube", "tooth", (0.018 * s, 0.355 * s, 0.125 * s), (0.03 * s, 0.025 * s, 0.07 * s)),
        part("cube", "tooth", (-0.018 * s, 0.355 * s, 0.125 * s), (0.03 * s, 0.025 * s, 0.07 * s)),
        part("uv", "eye_red", (0.07 * s, 0.36 * s, 0.24 * s), (0.045 * s, 0.045 * s, 0.045 * s), segments=6, rings=4),
        part("uv", "eye_red", (-0.07 * s, 0.36 * s, 0.24 * s), (0.045 * s, 0.045 * s, 0.045 * s), segments=6, rings=4),
        part("cylinder", "skin_pink", (0.09 * s, 0.24 * s, 0.3 * s), (0.12 * s, 0.12 * s, 0.02 * s), (90, 0, 20), vertices=8),
        part("cylinder", "skin_pink", (-0.09 * s, 0.24 * s, 0.3 * s), (0.12 * s, 0.12 * s, 0.02 * s), (90, 0, -20), vertices=8),
        part("cylinder", "rubber", (0, 0.17 * s, 0.18 * s), (0.27 * s, 0.27 * s, 0.035 * s), (90, 0, 0), vertices=12),  # collar
        part("cube", "bolt", (0, 0.2 * s, 0.07 * s), (0.04 * s, 0.03 * s, 0.05 * s)),
        part("cube", "skin_pink", (0.1 * s, 0.05 * s, 0.27 * s), (0.02 * s, 0.18 * s, 0.01 * s), (0, 0, 30)),  # scars
        part("cube", "skin_pink", (0.05 * s, -0.1 * s, 0.27 * s), (0.02 * s, 0.14 * s, 0.01 * s), (0, 0, -25)),
    ]
    for i in range(4):                                                                   # the broken chain
        parts.append(part("cylinder", "steel", (0.05 * s, (0.17 - i * 0.05) * s, (0.06 - i * 0.01) * s),
                          (0.035 * s, 0.035 * s, 0.01 * s), (0, 90 if i % 2 else 0, 0), vertices=6))
    for x in (0.1, -0.1):
        for y in (0.13, -0.15):
            parts.append(part("cube", "fur_dark", (x * s, y * s, 0.03 * s), (0.06 * s, 0.08 * s, 0.07 * s)))
    previous = (0, -0.22 * s, 0.12 * s)
    from mathutils import Vector
    for index in range(6):
        sideways = math.radians(index * 14)
        lift = math.radians(index * 9)
        step = 0.075 * s
        direction = (math.sin(sideways) * math.cos(lift), -math.cos(sideways) * math.cos(lift), math.sin(lift))
        nxt = tuple(p + d * step for p, d in zip(previous, direction))
        mid = tuple((a + b) / 2 for a, b in zip(previous, nxt))
        width = (0.034 - index * 0.004) * s
        segment = part("cylinder", "skin_pink", mid, (width, width, step * 1.35), vertices=6)
        segment.rotation_mode = "QUATERNION"
        segment.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(Vector(direction))
        bpy.ops.object.select_all(action="DESELECT")
        segment.select_set(True)
        bpy.context.view_layer.objects.active = segment
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
        parts.append(segment)
        previous = nxt
    join_and_export(parts, "boss_giant_rat", material, "zoology", True)


def welcome_center(material):
    """Zoology's welcome centre (24 x 18 m, where Zoology floors start): the reception desk, waiting benches, the
    security room in the north middle (walls, a doorway, the monitor desk and screens, the map table), hay bales and
    a yellow entry stripe. Everything sits on the grey box's pieces."""
    w, d = 24.0, 18.0
    parts = []
    room_shell(parts, w, d, {"S": [10.5, 13.5, 16.5], "W": [7.5, 10.5], "E": [7.5, 10.5]}, "wood")
    # The security room: front wall with its doorway, and the two side walls.
    wall_with_gaps(parts, (8.85, 6.0), (18.15, 6.0), [(4.65, 2.4)], 3.6, 0.3)
    wall_with_gaps(parts, (9.0, 0.0), (9.0, 6.0), [], 3.6, 0.3)
    wall_with_gaps(parts, (18.0, 0.0), (18.0, 6.0), [], 3.6, 0.3)
    parts.append(part("cube", "steel_dark", g(13.5, 0.4, 0.75), (6.0, 0.7, 0.8)))            # monitor desk
    parts.append(part("cube", "wood", g(13.5, 0.81, 0.75), (6.1, 0.75, 0.04)))
    for x in (11.25, 12.75, 14.25, 15.75):
        parts.append(part("cube", "rubber", g(x, 1.8, 0.25), (1.1, 0.1, 0.65)))
        parts.append(part("cube", "water", g(x, 1.8, 0.31), (1.0, 0.02, 0.55)))
        parts.append(part("cube", "steel_dark", g(x, 1.2, 0.3), (0.08, 0.08, 0.6)))
    parts.append(part("cube", "wood_dark", g(13.5, 0.45, 3.2), (2.4, 1.4, 0.9)))            # map table
    parts.append(part("cube", "sand", g(13.5, 0.91, 3.2), (2.3, 1.3, 0.02)))
    # Reception desk (6 m, with returns at both ends).
    parts.append(part("cube", "wood", g(13.5, 0.55, 10.5), (6.0, 0.8, 1.1)))
    parts.append(part("cube", "wood_dark", g(13.5, 1.12, 10.5), (6.1, 0.9, 0.05)))
    for x in (10.9, 16.1):
        parts.append(part("cube", "wood", g(x, 0.55, 11.4), (0.8, 1.0, 1.1)))
    parts.append(part("cube", "label", g(13.5, 0.7, 10.08), (2.2, 0.02, 0.4)))               # "WELCOME" plate
    parts.append(part("cube", "steel_dark", g(12.2, 1.3, 10.6), (0.5, 0.35, 0.3)))           # a till
    # Waiting benches by the south doors.
    for x in (4.0, 20.0):
        parts.append(part("cube", "wood", g(x, 0.45, 17.2), (4.0, 0.6, 0.08)))
        parts.append(part("cube", "wood_dark", g(x, 0.22, 17.2), (3.8, 0.5, 0.44)))
    # Hay bales and a potted fern, the entry stripe.
    hay_bale(parts, 3.0, 2.0, 0, 2)
    hay_bale(parts, 19.5, 1.0, 10, 2)
    parts.append(part("cube", "safety_yellow", g(13.5, 0.01, 14.5), (0.3, 7.0, 0.02)))
    parts.append(part("cylinder", "wood_dark", g(22.5, 0.3, 15.5), (0.6, 0.6, 0.6), vertices=8))
    parts.append(part("cone", "moss", g(22.5, 1.0, 15.5), (0.9, 0.9, 0.9), vertices=6))
    join_and_export(parts, "room_zoology_welcome_center", material, "zoology", False)


def bench(parts, x, y_top, z, sx, sz, top="lab_white", body="lab_panel"):
    """A lab bench whose box matches a grey-box bench: cupboard body, a white top."""
    parts.append(part("cube", body, g(x, (y_top - 0.04) / 2.0, z), (sx, sz, y_top - 0.04)))
    parts.append(part("cube", top, g(x, y_top - 0.02, z), (sx + 0.05, sz + 0.05, 0.04)))


def plants_on(parts, x, y, z, count, spacing, along_x=True):
    for i in range(count):
        px = x + (i - (count - 1) / 2.0) * spacing if along_x else x
        pz = z if along_x else z + (i - (count - 1) / 2.0) * spacing
        parts.append(part("cylinder", "terracotta", g(px, y + 0.1, pz), (0.24, 0.24, 0.2), vertices=6))
        parts.append(part("ico", "leaf" if i % 2 else "leaf_dark", g(px, y + 0.32, pz), (0.36, 0.36, 0.3), subdivisions=1))


def botany_rooms(material):
    """Botany's ten rooms (docs/ART_BIBLE.md: clinical white with green accents). Every big piece sits on the grey
    box's collision box of the same name."""
    rooms = {}

    p = []
    room_shell(p, 6.0, 9.0, {"N": [1.5], "S": [4.5], "W": [4.5], "E": [4.5]}, "lab_floor", style=BOTANY)
    p.append(part("cube", "metal", g(4.5, 0.75, 0.75), (2.0, 1.2, 1.5)))
    p.append(part("cylinder", "steel_dark", g(4.5, 0.85, 1.36), (1.0, 1.0, 0.06), (90, 0, 0), vertices=10))
    p.append(part("cube", "lab_green", g(5.2, 1.3, 1.37), (0.3, 0.02, 0.15)))
    for x in (0.35, 2.65):
        for z in (8.05, 8.75):
            p.append(part("cube", "steel_dark", g(x, 0.9, z), (0.06, 0.06, 1.8)))
    for y in (0.3, 0.9, 1.5):
        p.append(part("cube", "metal", g(1.5, y, 8.4), (2.4, 0.8, 0.04)))
        for i in range(4):
            p.append(part("cylinder", "glass", g(0.6 + i * 0.6, y + 0.15, 8.4), (0.15, 0.15, 0.26), vertices=6))
    rooms["autoclave_room"] = p

    p = []
    room_shell(p, 12.0, 12.0, {"N": [4.5], "S": [7.5], "W": [7.5], "E": [4.5]}, "lab_floor", style=BOTANY)
    for x in (4.5, 9.0):
        bench(p, x, 0.9, 3.0, 3.0, 1.0)
        for i in range(4):
            p.append(part("cylinder", "glass", g(x - 1.1 + i * 0.7, 1.0, 3.0), (0.2, 0.2, 0.06), vertices=10))
    bench(p, 6.0, 0.9, 8.0, 4.0, 1.2)
    p.append(part("cube", "lab_white", g(6.0, 1.15, 8.0), (1.0, 0.6, 0.5)))
    p.append(part("cube", "glass", g(6.0, 1.45, 8.0), (0.9, 0.5, 0.1)))
    rooms["cell_culture_lab"] = p

    p = []
    room_shell(p, 3.0, 6.0, {"N": [1.5], "S": [1.5]}, "steel_dark", style=BOTANY)
    p.append(part("cube", "lab_panel", g(0.4, 0.25, 3.0), (0.5, 1.6, 0.5)))
    for z in (2.0, 4.0):
        p.append(part("cube", "metal", g(1.5, 3.3, z), (2.4, 0.15, 0.15)))
        for i in range(5):
            p.append(part("cone", "steel_dark", g(0.7 + i * 0.4, 3.2, z), (0.06, 0.06, 0.08), (180, 0, 0), vertices=4))
    for i in range(7):
        swatch = "safety_yellow" if i % 2 == 0 else "stripe_black"
        p.append(part("cube", swatch, g(0.3 + i * 0.4, 0.006, 0.3), (0.4, 0.25, 0.012)))
        p.append(part("cube", swatch, g(0.3 + i * 0.4, 0.006, 5.7), (0.4, 0.25, 0.012)))
    rooms["decon_airlock"] = p

    p = []
    room_shell(p, 18.0, 24.0, {"N": [7.5], "S": [10.5], "W": [7.5], "E": [16.5]}, "lab_floor", style=BOTANY)
    for z in (5.0, 10.0, 15.0, 20.0):
        p.append(part("cube", "lab_panel", g(9.0, 0.35, z), (12.0, 1.2, 0.7)))
        p.append(part("cube", "soil", g(9.0, 0.76, z), (11.8, 1.1, 0.08)))
        for i in range(12):
            p.append(part("ico", "leaf" if (i + int(z)) % 2 else "leaf_dark", g(3.5 + i * 1.0, 1.0, z), (0.6, 0.6, 0.45), subdivisions=1))
    p.append(part("cylinder", "lab_green", g(1.2, 0.9, 12.0), (1.6, 1.6, 1.8), vertices=10))
    p.append(part("cylinder", "steel", g(1.2, 1.85, 12.0), (1.6, 1.6, 0.1), vertices=10))
    for x in (4.5, 9.0, 13.5):                                                                 # glass roof panes
        p.append(part("cube", "glass", g(x, 3.58, 12.0), (3.6, 22.0, 0.02)))
    rooms["greenhouse"] = p

    p = []
    room_shell(p, 12.0, 12.0, {"N": [4.5], "S": [7.5], "W": [7.5], "E": [4.5]}, "lab_floor", style=BOTANY)
    for z in (4.0, 8.5):
        p.append(part("cube", "metal", g(6.0, 1.2, z), (8.0, 0.08, 2.4)))                    # rack back
        for y in (0.4, 1.2, 2.0):
            p.append(part("cube", "metal", g(6.0, y, z), (8.0, 1.0, 0.05)))
            p.append(part("cube", "light_strip", g(6.0, y + 0.7, z), (7.6, 0.3, 0.03)))
            for i in range(10):
                p.append(part("ico", "leaf", g(2.4 + i * 0.8, y + 0.15, z), (0.4, 0.4, 0.28), subdivisions=1))
        for x in (2.0, 10.0):
            p.append(part("cube", "steel_dark", g(x, 1.2, z), (0.08, 1.0, 2.4)))
    rooms["growth_chamber"] = p

    p = []
    room_shell(p, 9.0, 12.0, {"N": [4.5], "S": [4.5], "W": [7.5], "E": [4.5]}, "lab_floor", style=BOTANY)
    bench(p, 1.0, 0.9, 3.0, 1.4, 3.0)
    for z in (2.2, 3.0, 3.8):
        p.append(part("cube", "steel_dark", g(0.9, 1.0, z), (0.25, 0.25, 0.2)))
        p.append(part("cylinder", "steel_dark", g(0.9, 1.25, z), (0.1, 0.1, 0.35), vertices=6))
    bench(p, 1.65, 0.9, 11.0, 2.7, 1.2)
    bench(p, 4.5, 0.9, 7.5, 2.0, 1.2, "lab_green")
    rooms["microscopy_lab"] = p

    p = []
    room_shell(p, 9.0, 12.0, {"N": [4.5], "S": [4.5], "W": [7.5], "E": [4.5]}, "steel_dark", style=BOTANY)
    for x, z in ((2.0, 3.0), (7.0, 9.5)):
        p.append(part("cube", "lab_green", g(x, 0.6, z), (2.0, 2.0, 1.2)))
        p.append(part("cylinder", "steel", g(x, 0.6, z), (1.0, 1.0, 2.1), (0, 90, 0), vertices=10))
    p.append(part("cylinder", "lab_white", g(2.0, 1.0, 10.0), (2.0, 2.0, 2.0), vertices=10))
    p.append(part("cube", "water", g(2.0, 1.4, 11.0), (0.3, 0.02, 0.6)))
    p.append(part("cylinder", "steel", g(8.6, 3.3, 6.0), (0.3, 0.3, 10.0), (90, 0, 0), vertices=8))
    rooms["pump_room"] = p

    p = []
    room_shell(p, 9.0, 9.0, {"N": [4.5], "S": [4.5], "W": [4.5], "E": [4.5]}, "lab_floor", style=BOTANY)
    for x, z in ((1.15, 0.55), (7.85, 0.55), (1.15, 8.45), (7.85, 8.45)):
        p.append(part("cube", "lab_white", g(x, 1.0, z), (2.0, 0.8, 2.0)))
        p.append(part("cube", "glass", g(x, 1.1, z + (0.41 if z < 4.5 else -0.41)), (1.8, 0.02, 1.6)))
        p.append(part("cube", "light_strip", g(x, 1.9, z), (1.6, 0.6, 0.04)))
    bench(p, 4.5, 0.9, 4.5, 1.2, 1.2)
    for i in range(3):
        p.append(part("cube", "terracotta", g(4.2 + i * 0.3, 0.95, 4.5), (0.15, 0.2, 0.1)))
    rooms["seed_vault"] = p

    p = []
    room_shell(p, 12.0, 15.0, {"N": [7.5], "S": [4.5], "W": [7.5], "E": [7.5]}, "lab_floor", style=BOTANY)
    for z in (4.0, 11.0):
        bench(p, 6.0, 0.9, z, 8.0, 1.2, "wood", "lab_panel")
        plants_on(p, 6.0, 0.9, z, 8, 0.9)
        p.append(part("cube", "soil", g(3.0, 0.93, z), (0.8, 0.5, 0.06)))
    p.append(part("cube", "terracotta", g(10.5, 0.5, 13.5), (1.6, 1.6, 1.0)))
    p.append(part("cube", "soil", g(10.5, 1.0, 13.5), (1.5, 1.5, 0.05)))
    rooms["soil_prep"] = p

    p = []
    room_shell(p, 24.0, 18.0, {"S": [10.5, 13.5, 16.5], "W": [7.5, 10.5], "E": [7.5, 10.5]}, "lab_floor", style=BOTANY)
    wall_with_gaps(p, (8.85, 6.0), (18.15, 6.0), [(4.65, 2.4)], 3.6, 0.3, BOTANY)
    wall_with_gaps(p, (9.0, 0.0), (9.0, 6.0), [], 3.6, 0.3, BOTANY)
    wall_with_gaps(p, (18.0, 0.0), (18.0, 6.0), [], 3.6, 0.3, BOTANY)
    p.append(part("cube", "steel_dark", g(13.5, 0.4, 0.75), (6.0, 0.7, 0.8)))
    for x in (11.25, 12.75, 14.25, 15.75):
        p.append(part("cube", "rubber", g(x, 1.8, 0.25), (1.1, 0.1, 0.65)))
        p.append(part("cube", "water", g(x, 1.8, 0.31), (1.0, 0.02, 0.55)))
    p.append(part("cube", "lab_panel", g(13.5, 0.45, 3.2), (2.4, 1.4, 0.9)))
    p.append(part("cube", "lab_white", g(13.5, 0.55, 10.5), (6.0, 0.8, 1.1)))
    p.append(part("cube", "lab_green", g(13.5, 1.12, 10.5), (6.1, 0.9, 0.05)))
    for x in (10.9, 16.1):
        p.append(part("cube", "lab_white", g(x, 0.55, 11.4), (0.8, 1.0, 1.1)))
    for x in (4.0, 20.0):
        p.append(part("cube", "lab_green", g(x, 0.25, 17.2), (4.0, 0.8, 0.5)))
    for x, z, sx, sz in ((3.0, 2.0, 2.0, 1.2), (19.5, 1.0, 1.6, 1.0)):
        p.append(part("cube", "terracotta", g(x, 0.4, z), (sx, sz, 0.8)))
        plants_on(p, x, 0.8, z, 3, sx / 3.0)
    p.append(part("cube", "lab_green", g(13.5, 0.01, 14.5), (0.3, 7.0, 0.02)))
    rooms["welcome_center"] = p

    for name, pieces in rooms.items():
        join_and_export(pieces, "room_botany_" + name, material, "botany", False)


def mushroom_zombie(material):
    """The mushroom zombie (enemy_mushroom_zombie): a lab worker in a white coat, 1.6 m tall, arms out in front, a red
    mushroom cap bursting out of the head and small mushrooms on the shoulders."""
    parts = [
        part("cube", "lab_white", (0, 0, 1.05), (0.42, 0.26, 0.6)),                          # coat
        part("cube", "lab_white", (0, -0.01, 0.68), (0.44, 0.28, 0.3)),                      # coat tails
        part("cube", "lab_green", (0.12, 0.135, 1.15), (0.08, 0.01, 0.1)),                   # badge
        part("uv", "mushroom_stalk", (0, 0.02, 1.42), (0.24, 0.24, 0.26), segments=8, rings=5),  # head
        part("uv", "mushroom_cap", (0.04, 0, 1.6), (0.52, 0.5, 0.2), (0, 12, 0), segments=10, rings=5),
        part("uv", "mushroom_stalk", (0.15, 0.06, 1.68), (0.08, 0.08, 0.04), segments=6, rings=3),
        part("uv", "mushroom_stalk", (-0.1, -0.1, 1.68), (0.06, 0.06, 0.03), segments=6, rings=3),
        part("uv", "spore", (0.05, 0.12, 1.44), (0.04, 0.03, 0.04), segments=6, rings=4),    # glazed eyes
        part("uv", "spore", (-0.05, 0.12, 1.44), (0.04, 0.03, 0.04), segments=6, rings=4),
        part("cube", "rubber", (0, 0.13, 1.36), (0.08, 0.01, 0.025)),                        # mouth
    ]
    for side in (-1, 1):
        parts.append(part("cylinder", "rubber", (side * 0.1, 0, 0.27), (0.14, 0.14, 0.54), vertices=6))   # legs
        parts.append(part("cube", "rubber", (side * 0.1, 0.04, 0.03), (0.13, 0.22, 0.06)))                # shoes
        parts.append(part("cylinder", "lab_white", (side * 0.25, 0.2, 1.22), (0.11, 0.11, 0.45), (80, 0, 0), vertices=6))
        parts.append(part("uv", "mushroom_stalk", (side * 0.25, 0.44, 1.18), (0.1, 0.1, 0.1), segments=6, rings=4))
        parts.append(part("cylinder", "mushroom_stalk", (side * 0.16, -0.02, 1.4), (0.04, 0.04, 0.1), vertices=6))
        parts.append(part("uv", "mushroom_cap", (side * 0.16, -0.02, 1.46), (0.12, 0.12, 0.05), segments=6, rings=3))
    join_and_export(parts, "enemy_mushroom_zombie", material, "botany", True)


def flytrap(material):
    """The flytrap (enemy_flytrap): a giant snapping plant in a clay pot, 0.9 m tall, jaws open towards the front
    with pale teeth on the rims."""
    parts = [
        part("cylinder", "terracotta", (0, 0, 0.17), (0.56, 0.56, 0.34), vertices=8),
        part("cylinder", "terracotta", (0, 0, 0.33), (0.6, 0.6, 0.06), vertices=8),
        part("cylinder", "soil", (0, 0, 0.355), (0.5, 0.5, 0.02), vertices=8),
        part("cylinder", "vine", (0, 0.02, 0.48), (0.09, 0.09, 0.28), (10, 0, 0), vertices=6),        # stem
        part("uv", "leaf", (0, 0.1, 0.74), (0.46, 0.4, 0.14), (-28, 0, 0), segments=10, rings=5),   # top jaw
        part("uv", "flytrap_mouth", (0, 0.11, 0.72), (0.4, 0.34, 0.08), (-28, 0, 0), segments=10, rings=5),
        part("uv", "leaf", (0, 0.08, 0.6), (0.44, 0.38, 0.12), (14, 0, 0), segments=10, rings=5),    # bottom jaw
        part("uv", "flytrap_mouth", (0, 0.09, 0.62), (0.38, 0.32, 0.06), (14, 0, 0), segments=10, rings=5),
    ]
    for i in range(7):                                                                  # teeth on both rims
        angle = math.radians(-70 + i * (140 / 6))
        x, y = math.sin(angle) * 0.2, 0.1 + math.cos(angle) * 0.18
        parts.append(part("cone", "tooth", (x, y, 0.8 + (0.18 - abs(x)) * 0.25), (0.03, 0.03, 0.08), (180, 0, 0), vertices=4))
        parts.append(part("cone", "tooth", (x, y - 0.02, 0.64), (0.03, 0.03, 0.07), vertices=4))
    for i in range(4):                                                                  # leaves over the pot rim
        a = math.radians(45 + i * 90)
        parts.append(part("cube", "leaf_dark", (math.sin(a) * 0.3, math.cos(a) * 0.3, 0.4), (0.12, 0.26, 0.02),
                          (25, 0, -math.degrees(a))))
    join_and_export(parts, "enemy_flytrap", material, "botany", True)


def spore_shooter(material):
    """The spore shooter (enemy_spore_shooter): a waddling puffball 0.8 m tall on root feet, with a spout on top that
    lobs spore clouds forward, two small eyes and pale spots."""
    parts = [
        part("uv", "spore", (0, 0, 0.4), (0.5, 0.48, 0.56), segments=10, rings=6),
        part("cylinder", "leaf_dark", (0, 0.13, 0.66), (0.16, 0.16, 0.26), (-55, 0, 0), vertices=8),     # spout
        part("cylinder", "soil", (0, 0.24, 0.74), (0.12, 0.12, 0.04), (-55, 0, 0), vertices=8),
        part("uv", "eye_red", (0.08, 0.22, 0.46), (0.06, 0.04, 0.06), segments=6, rings=4),
        part("uv", "eye_red", (-0.08, 0.22, 0.46), (0.06, 0.04, 0.06), segments=6, rings=4),
    ]
    for x, y, z in ((0.2, 0.05, 0.5), (-0.18, -0.1, 0.55), (0.1, -0.2, 0.35), (-0.22, 0.08, 0.3), (0.0, -0.08, 0.66)):
        parts.append(part("uv", "mushroom_stalk", (x, y, z), (0.07, 0.07, 0.04), segments=6, rings=3))
    for i in range(4):                                                                  # root feet
        a = math.radians(45 + i * 90)
        parts.append(part("cone", "vine", (math.sin(a) * 0.16, math.cos(a) * 0.16, 0.08), (0.1, 0.1, 0.18),
                          (155, 0, -math.degrees(a)), vertices=5))
    join_and_export(parts, "enemy_spore_shooter", material, "botany", True)


def vine_creeper(material):
    """The vine creeper (enemy_vine_creeper): a 1.4 m tangle of vines with a flower-mouth head and two long tendrils
    reaching forward (it pulls players in)."""
    parts = [
        part("ico", "leaf_dark", (0, 0, 0.25), (0.8, 0.75, 0.5), subdivisions=1),
        part("ico", "vine", (0, 0, 0.7), (0.6, 0.55, 0.55), subdivisions=1),
        part("ico", "leaf_dark", (0, 0.03, 1.12), (0.5, 0.48, 0.45), subdivisions=1),
        part("cylinder", "flytrap_mouth", (0, 0.24, 1.14), (0.32, 0.32, 0.04), (90, 0, 0), vertices=6),   # petals
        part("cylinder", "rubber", (0, 0.26, 1.14), (0.14, 0.14, 0.03), (90, 0, 0), vertices=6),          # mouth
        part("uv", "spore", (0.12, 0.2, 1.3), (0.06, 0.04, 0.06), segments=6, rings=4),
        part("uv", "spore", (-0.12, 0.2, 1.3), (0.06, 0.04, 0.06), segments=6, rings=4),
    ]
    for side in (-1, 1):                                                                # tendrils, three pieces each
        for i in range(3):
            parts.append(part("cylinder", "vine", (side * (0.3 + i * 0.03), 0.2 + i * 0.22, 0.95 - i * 0.08),
                              (0.08 - i * 0.015, 0.08 - i * 0.015, 0.26), (75 + i * 8, 0, side * -8), vertices=5))
        parts.append(part("cube", "leaf", (side * 0.4, 0.0, 0.85), (0.24, 0.12, 0.02), (0, side * 30, 0)))
    for i in range(6):                                                                  # roots
        a = math.radians(i * 60)
        parts.append(part("cone", "vine", (math.sin(a) * 0.32, math.cos(a) * 0.32, 0.06), (0.12, 0.12, 0.34),
                          (-100, 0, -math.degrees(a)), vertices=5))
    join_and_export(parts, "enemy_vine_creeper", material, "botany", True)


def mushroom_man(material):
    """The Mushroom Man boss (boss_mushroom_man): a 2.8 m mushroom with a thick stalk, a huge spotted red cap, gills
    underneath, an angry face, stubby arms, root feet and a torn lab coat collar."""
    parts = [
        part("cylinder", "mushroom_stalk", (0, 0, 1.0), (1.3, 1.3, 2.0), vertices=12),
        part("cylinder", "mushroom_stalk", (0, 0, 0.15), (1.5, 1.5, 0.3), vertices=12),
        part("cylinder", "mushroom_stalk", (0, 0, 1.75), (1.55, 1.55, 0.08), vertices=12),     # skirt ring
        part("uv", "mushroom_cap", (0, 0, 2.3), (3.0, 3.0, 1.1), segments=14, rings=7),
        part("cylinder", "spore", (0, 0, 2.18), (2.7, 2.7, 0.12), vertices=14),                 # gills
        part("uv", "spore", (0.24, 0.66, 1.3), (0.22, 0.1, 0.15), segments=6, rings=4),        # eyes
        part("uv", "spore", (-0.24, 0.66, 1.3), (0.22, 0.1, 0.15), segments=6, rings=4),
        part("cube", "rubber", (0.24, 0.68, 1.43), (0.3, 0.05, 0.06), (0, -15, 0)),            # angry brows
        part("cube", "rubber", (-0.24, 0.68, 1.43), (0.3, 0.05, 0.06), (0, 15, 0)),
        part("cube", "rubber", (0, 0.66, 0.98), (0.46, 0.05, 0.12)),                              # mouth
        part("cylinder", "lab_white", (0, 0.0, 1.62), (1.42, 1.42, 0.14), vertices=12),                          # coat collar
        part("cube", "label", (0.3, 0.71, 1.62), (0.2, 0.02, 0.1)),
    ]
    for x, y in ((0.6, 0.6), (-0.8, 0.2), (0.2, -0.7), (-0.4, -0.5), (0.9, -0.3), (-0.2, 0.9), (0.0, 0.0)):
        parts.append(part("uv", "mushroom_stalk", (x, y, 2.3 + 0.55 * math.sqrt(max(0.0, 1 - (x * x + y * y) / 2.25))),
                          (0.42, 0.42, 0.16), segments=8, rings=3))
    for side in (-1, 1):                                                                # stubby arms
        parts.append(part("cylinder", "mushroom_stalk", (side * 0.8, 0.15, 1.15), (0.3, 0.3, 0.7), (30, side * 35, 0), vertices=8))
        parts.append(part("uv", "mushroom_stalk", (side * 0.98, 0.35, 0.88), (0.3, 0.3, 0.3), segments=8, rings=4))
        parts.append(part("cylinder", "mushroom_stalk", (side * 0.6, -0.3, 0.75), (0.05, 0.05, 0.16), vertices=6))
        parts.append(part("uv", "mushroom_cap", (side * 0.6, -0.33, 0.84), (0.2, 0.2, 0.08), segments=6, rings=3))
    for i in range(6):                                                                  # root feet
        a = math.radians(i * 60 + 30)
        parts.append(part("cone", "soil", (math.sin(a) * 0.78, math.cos(a) * 0.78, 0.1), (0.3, 0.3, 0.55),
                          (-100, 0, -math.degrees(a)), vertices=5))
    join_and_export(parts, "boss_mushroom_man", material, "botany", True)


clear_scene()
palette = make_palette()
solid = palette_material(palette)
see_through = palette_material(palette, "palette_zoology_glass", True)
rat(solid)
crate(solid)
gem(solid, "prop_gem", 0.16)
gem(solid, "prop_gem_large", 0.28)
meat(solid)
vial(solid, see_through)
lift(solid)
animal_holding(solid)
vet_surgery(solid)
feed_storage(solid)
observation_room(solid)
aquarium(solid)
habitat_sim(solid)
quarantine_pens(solid)
welcome_center(solid)
botany_rooms(solid)
mushroom_zombie(solid)
flytrap(solid)
spore_shooter(solid)
vine_creeper(solid)
mushroom_man(solid)
bat(solid)
fly(solid)
kangaroo(solid)
giant_rat(solid)
print("LOOK_TARGET_DONE")
