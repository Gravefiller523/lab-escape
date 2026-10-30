class_name TileStandards
extends RefCounted
## NEW 2026-10-30 (floor generation, step 2): the names every 3 m tile uses, in one place, so tiles, tests
## and the generator agree. The sizes (grid unit, doorway, ceiling, wall) are numbers in
## Config.floor_gen (config/floor_gen_tuning.tres). The rules are written out in docs/systems/level_gen.md,
## "Tile standards".

## RoomData.tile_role values.
const ROLE_ROOM: StringName = &"room"
const ROLE_MAIN_HALL: StringName = &"main_hall"
const ROLE_SECONDARY_HALL: StringName = &"secondary_hall"
const ROLE_TEMPLATE: StringName = &"template"
const ROLES: Array[StringName] = [ROLE_ROOM, ROLE_MAIN_HALL, ROLE_SECONDARY_HALL, ROLE_TEMPLATE]

## Room size categories (RoomData.size_category; the footprints are in Config.floor_gen).
const SIZE_CATEGORIES: Array[StringName] = [&"small", &"medium", &"large"]

## Damage levels, mildest first. "pristine" is the tile itself; the others are overlay nodes.
const DAMAGE_LEVELS: Array[StringName] = [&"pristine", &"light", &"heavy", &"destroyed"]
## The node holding a tile's damage overlays, and the overlay node for each damaged level.
const DAMAGE_NODE: String = "Damage"
const OVERLAY_NODES: Dictionary[StringName, String] = {&"light": "Light", &"heavy": "Heavy", &"destroyed": "Destroyed"}

## Group of a tile's normal lights (damage makes them flicker, go red or go out).
const LIGHT_GROUP: StringName = &"tile_light"
## Group of a tile's ceiling (the tile gallery hides ceilings to look in from above).
const CEILING_GROUP: StringName = &"tile_ceiling"

## Named material slots: a node with the metadata "material_slot" set to one of these gets the
## department's material for it (DepartmentData.palette) when the floor is built.
const MATERIAL_SLOT_META: StringName = &"material_slot"
const MATERIAL_SLOTS: Array[StringName] = [&"wall", &"floor", &"trim", &"accent"]

## Marker kinds tiles may use (RoomMarker.kind). New kinds need no code, but add them here and to the
## spec so the tile test knows them. The first group is from the floor generation plan (section 3.4).
const MARKER_KINDS: Array[StringName] = [
	&"lift_part", &"camera", &"enemy_spawn", &"patrol", &"prop_spawn", &"cover", &"hazard", &"keycard", &"sign",
	# Other systems' markers that keep working.
	&"lift", &"printer", &"cart", &"vendor", &"upgrade_machine", &"charger", &"item_spawn", &"player_spawn",
	&"supply_counter", &"task", &"boss_spawn", &"minion_spawn", &"locked_door",
	# NEW 2026-10-30: where the security room's map table and camera monitors go (step 4e).
	&"security_map", &"security_monitor",
]

## Lift part sizes (PropData.part_size and the "max_size" param of lift_part markers), smallest first.
const PART_SIZES: Array[StringName] = [&"small", &"medium", &"large", &"huge"]


## The overlay node of one damage level inside a tile, or null ("pristine" has none).
static func overlay_of(tile: Node, level: StringName) -> Node3D:
	if not OVERLAY_NODES.has(level):
		return null
	return tile.get_node_or_null("%s/%s" % [DAMAGE_NODE, OVERLAY_NODES[level]]) as Node3D


## Shows one damage level's overlay inside a tile and hides the others ("pristine" hides them all).
static func show_damage(tile: Node, level: StringName) -> void:
	for overlay_level: StringName in OVERLAY_NODES:
		var overlay: Node3D = overlay_of(tile, overlay_level)
		if overlay != null:
			overlay.visible = overlay_level == level


## Puts a palette's materials ("wall", "floor", "trim", "accent" -> Material) on every node under root
## that names a material slot. Slots the palette doesn't have keep their material.
static func apply_palette(root: Node, palette: Dictionary) -> void:
	for node: Node in RoomShape.all_children(root):
		if not node.has_meta(MATERIAL_SLOT_META):
			continue
		var material := palette.get(String(node.get_meta(MATERIAL_SLOT_META)), null) as Material
		if material == null:
			continue
		if node is CSGPrimitive3D:
			(node as CSGPrimitive3D).set("material", material)
		elif node is GeometryInstance3D:
			(node as GeometryInstance3D).material_override = material
