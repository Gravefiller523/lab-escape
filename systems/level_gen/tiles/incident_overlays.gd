class_name IncidentOverlays
extends RefCounted
## NEW 2026-11-11 (floor generation step 5a): what an incident leaves on the damaged tiles around it, by its
## IncidentData.overlay_flavour: "vines" (creepers down the walls, clumps on the floor), "spores" (drifting
## glowing motes, mould patches), "flood" (water over the floor; puddles when lightly damaged), "frost" (ice on the
## floor and walls), "scorch" (soot) and "wreckage" (bent scrap). Each damaged tile takes the flavour of the
## nearest incident (the main one or a smaller one), and gets more of it the worse its damage. Looks only: no
## collision, nothing networked; seeded by the floor, so every PC sees the same. Built by Level.build.

const NODE_NAME: String = "IncidentOverlay"
## Pieces per damage level (light, heavy, destroyed).
const PIECES: Array[int] = [0, 4, 9, 15]


## Every PC: dress one tile (placement `index`) for the nearest incident. Does nothing for undamaged tiles or
## incidents without a flavour.
static func dress(tile: Node3D, index: int, layout: FloorLayout, department: DepartmentData) -> void:
	var level: int = layout.damage[index] if index < layout.damage.size() else 0
	var blockout := tile as BlockoutTile
	if level <= 0 or blockout == null or department == null:
		return
	var flavour: StringName = flavour_for(index, layout, department)
	if flavour == &"":
		return
	var unit: float = Config.floor_gen.grid_unit
	var size := Vector2(blockout.size_units) * unit
	var holder := Node3D.new()
	holder.name = NODE_NAME
	tile.add_child(holder)
	var rng: RandomNumberGenerator = SeededRng.make(layout.floor_seed, &"incident_overlay", index)
	var count: int = PIECES[mini(level, PIECES.size() - 1)] * maxi(1, roundi(size.x * size.y / 81.0))
	match flavour:
		&"vines":
			_vines(holder, size, count, rng)
		&"spores":
			_spores(holder, size, count, rng)
		&"flood":
			_flood(holder, size, level, count, rng)
		&"frost":
			_patches(holder, size, count, rng, Color(0.85, 0.95, 1.0, 0.8), true)
		&"scorch":
			_patches(holder, size, count, rng, Color(0.06, 0.05, 0.05, 0.85), true)
		&"wreckage":
			_wreckage(holder, size, count, rng)


## The flavour of the incident nearest this tile (by straight distance between tile middles), or "".
static func flavour_for(index: int, layout: FloorLayout, department: DepartmentData) -> StringName:
	var origins: Array[int] = []
	var ids: Array[StringName] = []
	if layout.origin >= 0:
		origins.append(layout.origin)
		ids.append(layout.incident_id)
	for minor: int in layout.minor_origins.size():
		origins.append(layout.minor_origins[minor])
		ids.append(StringName(layout.minor_incident_ids[minor]) if minor < layout.minor_incident_ids.size() else layout.incident_id)
	var here: Vector2 = _middle(layout, index)
	var best: int = -1
	for which: int in origins.size():
		if best < 0 or here.distance_to(_middle(layout, origins[which])) < here.distance_to(_middle(layout, origins[best])):
			best = which
	if best < 0:
		return &""
	for incident: IncidentData in department.incidents:
		if incident != null and incident.id == ids[best]:
			return incident.overlay_flavour
	return &""


static func _middle(layout: FloorLayout, index: int) -> Vector2:
	var placement: RoomPlacement = layout.placements[index]
	return Vector2(placement.cell.x, placement.cell.z)


static func _material(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = Color(color, 1.0)
		material.emission_energy_multiplier = glow
	return material


static func _piece(holder: Node3D, piece_name: String, at: Vector3, size: Vector3, material: Material,
		turn: float = 0.0) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = piece_name
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	mesh.mesh = box
	mesh.position = at
	mesh.rotation.y = turn
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mesh)
	return mesh


## A spot just inside one of the walls: [position on the floor plan, which way the wall runs (radians)].
static func _wall_spot(size: Vector2, rng: RandomNumberGenerator) -> Array:
	var inner: float = 0.17
	match rng.randi_range(0, 3):
		0:
			return [Vector2(rng.randf_range(0.6, size.x - 0.6), inner), 0.0]
		1:
			return [Vector2(rng.randf_range(0.6, size.x - 0.6), size.y - inner), 0.0]
		2:
			return [Vector2(inner, rng.randf_range(0.6, size.y - 0.6)), PI / 2.0]
	return [Vector2(size.x - inner, rng.randf_range(0.6, size.y - 0.6)), PI / 2.0]


static func _vines(holder: Node3D, size: Vector2, count: int, rng: RandomNumberGenerator) -> void:
	var leaf := _material(Color(0.2, 0.45, 0.18))
	for index: int in count:
		var spot: Array = _wall_spot(size, rng)
		var at: Vector2 = spot[0]
		var length: float = rng.randf_range(1.0, 3.2)
		_piece(holder, "Creeper%d" % index, Vector3(at.x, 3.6 - length / 2.0, at.y), Vector3(rng.randf_range(0.15, 0.4),
			length, 0.06), leaf, spot[1])
		var clump := Vector2(rng.randf_range(0.5, size.x - 0.5), rng.randf_range(0.5, size.y - 0.5))
		_piece(holder, "Clump%d" % index, Vector3(clump.x, 0.04, clump.y), Vector3(rng.randf_range(0.4, 1.0), 0.08,
			rng.randf_range(0.4, 1.0)), leaf, rng.randf() * TAU)


static func _spores(holder: Node3D, size: Vector2, count: int, rng: RandomNumberGenerator) -> void:
	var glow := _material(Color(0.5, 1.0, 0.4), 2.5)
	var mould := _material(Color(0.4, 0.55, 0.25, 0.7))
	for index: int in count:
		_piece(holder, "Mote%d" % index, Vector3(rng.randf_range(0.5, size.x - 0.5), rng.randf_range(0.4, 2.8),
			rng.randf_range(0.5, size.y - 0.5)), Vector3.ONE * 0.06, glow)
		_piece(holder, "Mould%d" % index, Vector3(rng.randf_range(0.5, size.x - 0.5), 0.012, rng.randf_range(0.5, size.y - 0.5)),
			Vector3(rng.randf_range(0.5, 1.4), 0.02, rng.randf_range(0.5, 1.4)), mould, rng.randf() * TAU)


static func _flood(holder: Node3D, size: Vector2, level: int, count: int, rng: RandomNumberGenerator) -> void:
	var water := _material(Color(0.25, 0.4, 0.45, 0.6))
	water.roughness = 0.05
	if level >= 2:
		_piece(holder, "Water", Vector3(size.x / 2.0, 0.05, size.y / 2.0), Vector3(size.x - 0.3, 0.02, size.y - 0.3), water)
		return
	for index: int in count:
		_piece(holder, "Puddle%d" % index, Vector3(rng.randf_range(0.6, size.x - 0.6), 0.012, rng.randf_range(0.6, size.y - 0.6)),
			Vector3(rng.randf_range(0.6, 1.8), 0.02, rng.randf_range(0.6, 1.8)), water, rng.randf() * TAU)


static func _patches(holder: Node3D, size: Vector2, count: int, rng: RandomNumberGenerator, color: Color,
		on_walls: bool) -> void:
	var material := _material(color)
	for index: int in count:
		_piece(holder, "Patch%d" % index, Vector3(rng.randf_range(0.5, size.x - 0.5), 0.012, rng.randf_range(0.5, size.y - 0.5)),
			Vector3(rng.randf_range(0.5, 1.6), 0.02, rng.randf_range(0.5, 1.6)), material, rng.randf() * TAU)
		if on_walls:
			var spot: Array = _wall_spot(size, rng)
			var at: Vector2 = spot[0]
			_piece(holder, "WallPatch%d" % index, Vector3(at.x, rng.randf_range(0.5, 2.8), at.y),
				Vector3(rng.randf_range(0.5, 1.4), rng.randf_range(0.4, 1.2), 0.04), material, spot[1])


static func _wreckage(holder: Node3D, size: Vector2, count: int, rng: RandomNumberGenerator) -> void:
	var metal := _material(Color(0.38, 0.38, 0.4))
	for index: int in count:
		var piece := _piece(holder, "Scrap%d" % index, Vector3(rng.randf_range(0.5, size.x - 0.5), 0.06,
			rng.randf_range(0.5, size.y - 0.5)), Vector3(rng.randf_range(0.2, 0.7), 0.06, rng.randf_range(0.1, 0.4)),
			metal, rng.randf() * TAU)
		piece.rotation.x = rng.randf_range(-0.3, 0.3)
