class_name DamageLooks
extends RefCounted
## NEW 2026-11-13 (floor generation step 6b): how a department's heavily damaged and destroyed tiles look, on top of
## the damage overlays (Config.floor_gen.damage_looks_by_department). "skylights" (Zoology): holes broken in the
## ceiling with a pale shaft of light falling through each, a ceiling panel hanging down, and dark corners
## (shadowy corners and dead light fittings). Looks only: no collision changes that matter, nothing networked;
## seeded by the floor, so every PC sees the same. Built by Level.build.

const NODE_NAME: String = "DamageLook"
## Ceiling holes per damage level (heavy, destroyed) and dark corners per damage level.
const HOLES: Array[int] = [0, 0, 1, 2]
const DARK_CORNERS: Array[int] = [0, 0, 2, 4]
const HOLE_SIZE: float = 1.6
const SKY_COLOR: Color = Color(0.75, 0.85, 1.0)


## Every PC: dress one tile (placement `index`) with its department's damage look. Nothing for lightly damaged
## tiles, hallways' open ends, or departments without a look.
static func dress(tile: Node3D, index: int, layout: FloorLayout, department: DepartmentData) -> void:
	var level: int = layout.damage[index] if index < layout.damage.size() else 0
	var blockout := tile as BlockoutTile
	if level < 2 or blockout == null or department == null:
		return
	var look: StringName = Config.floor_gen.damage_looks_by_department.get(department.id, &"")
	if look != &"skylights":
		return
	var unit: float = Config.floor_gen.grid_unit
	var height: float = Config.floor_gen.ceiling_height
	var size := Vector2(blockout.size_units) * unit
	var holder := Node3D.new()
	holder.name = NODE_NAME
	tile.add_child(holder)
	var rng: RandomNumberGenerator = SeededRng.make(layout.floor_seed, &"damage_look", index)
	var ceiling := _ceiling_of(tile)
	var holes: int = HOLES[mini(level, HOLES.size() - 1)] * maxi(1, roundi(size.x * size.y / 81.0))
	for hole: int in holes:
		var at := Vector2(rng.randf_range(HOLE_SIZE, size.x - HOLE_SIZE), rng.randf_range(HOLE_SIZE, size.y - HOLE_SIZE))
		_skylight(holder, ceiling, hole, at, height, rng)
	var corners: Array[Vector2] = [Vector2(0.5, 0.5), Vector2(size.x - 0.5, 0.5), Vector2(0.5, size.y - 0.5),
		Vector2(size.x - 0.5, size.y - 0.5)]
	var order: Array[int] = [0, 1, 2, 3]
	for swap: int in 4:
		var other: int = rng.randi_range(0, 3)
		var kept: int = order[swap]
		order[swap] = order[other]
		order[other] = kept
	for which: int in DARK_CORNERS[mini(level, DARK_CORNERS.size() - 1)]:
		_dark_corner(holder, which, corners[order[which % 4]], height)


## The tile's generated ceiling (a CSG combiner), or null.
static func _ceiling_of(tile: Node3D) -> CSGCombiner3D:
	for node: Node in RoomShape.all_children(tile):
		if node is CSGCombiner3D and node.is_in_group(TileStandards.CEILING_GROUP):
			return node as CSGCombiner3D
	return null


static func _skylight(holder: Node3D, ceiling: CSGCombiner3D, index: int, at: Vector2, height: float,
		rng: RandomNumberGenerator) -> void:
	if ceiling != null:
		var hole := CSGBox3D.new()
		hole.name = "Skylight%d" % index
		hole.operation = CSGShape3D.OPERATION_SUBTRACTION
		hole.size = Vector3(HOLE_SIZE, 1.0, HOLE_SIZE)
		hole.position = Vector3(at.x, height, at.y)
		ceiling.add_child(hole)
	# A pale shaft of light falling through it.
	var shaft := MeshInstance3D.new()
	shaft.name = "Shaft%d" % index
	var box := BoxMesh.new()
	box.size = Vector3(HOLE_SIZE * 0.8, height, HOLE_SIZE * 0.8)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.albedo_color = Color(SKY_COLOR, 0.08)
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	box.material = glow
	shaft.mesh = box
	shaft.position = Vector3(at.x, height / 2.0, at.y)
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(shaft)
	var light := SpotLight3D.new()
	light.name = "SkyLight%d" % index
	light.light_color = SKY_COLOR
	light.light_energy = 1.2
	light.spot_range = height + 1.0
	light.spot_angle = 30.0
	light.shadow_enabled = false
	light.position = Vector3(at.x, height - 0.05, at.y)
	light.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	holder.add_child(light)
	# A broken ceiling panel hanging down at the edge of the hole.
	var panel := MeshInstance3D.new()
	panel.name = "HangingPanel%d" % index
	var slab := BoxMesh.new()
	slab.size = Vector3(HOLE_SIZE * 0.9, 0.05, HOLE_SIZE * 0.5)
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.55, 0.53, 0.5)
	slab.material = grey
	panel.mesh = slab
	panel.position = Vector3(at.x, height - 0.45, at.y + HOLE_SIZE * 0.45)
	panel.rotation = Vector3(rng.randf_range(0.7, 1.1), 0.0, rng.randf_range(-0.2, 0.2))
	holder.add_child(panel)


## A shadowy corner: a dark see-through volume and a dead light fitting on the ceiling above it.
static func _dark_corner(holder: Node3D, index: int, at: Vector2, height: float) -> void:
	var shade := MeshInstance3D.new()
	shade.name = "DarkCorner%d" % index
	var box := BoxMesh.new()
	box.size = Vector3(1.6, height, 1.6)
	var dark := StandardMaterial3D.new()
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dark.albedo_color = Color(0.0, 0.0, 0.0, 0.45)
	dark.cull_mode = BaseMaterial3D.CULL_DISABLED
	box.material = dark
	shade.mesh = box
	shade.position = Vector3(at.x, height / 2.0, at.y)
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(shade)
	var fitting := MeshInstance3D.new()
	fitting.name = "DeadFitting%d" % index
	var lamp := BoxMesh.new()
	lamp.size = Vector3(0.6, 0.08, 0.2)
	var off := StandardMaterial3D.new()
	off.albedo_color = Color(0.15, 0.15, 0.15)
	lamp.material = off
	fitting.mesh = lamp
	fitting.position = Vector3(at.x, height - 0.1, at.y)
	holder.add_child(fitting)
