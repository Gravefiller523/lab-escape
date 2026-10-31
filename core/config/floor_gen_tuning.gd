class_name FloorGenTuning
extends Resource
## Every floor generation number in one place. NEW 2026-10-30 (floor generation, step 2).
## The live copy is res://config/floor_gen_tuning.tres, loaded by the Config autoload: read it with
## Config.floor_gen.<field>. Open the file in the Inspector and fold out a section to change it.
## Not used by gameplay yet: the new FloorGenerator reads it from step 3 of
## docs/design/floor-generation-plan.md. "(V3)" etc. point at that plan's table of numbers (section 17).
##
## Two patterns used below:
## - "Grows with the floor": value = base + per_floor x (floor - 1), never above the cap. See grown().
## - "By floor bracket": a list with one number per bracket of floors. floor_brackets says where each
##   bracket starts (1, 4, 8 = floors 1-3, 4-7, 8 and up). See bracket_index() and by_bracket().

@export_group("Generator")
## NEW 2026-10-31 (step 3): regular floors in a run use the new FloorGenerator (3 m tiles). Off = the old
## grey-box generator (12 m rooms). Boss floors always use the old arena floor for now.
@export var use_floor_generator: bool = true
## A floor attempt is thrown away (and the next attempt tried) when it has fewer rooms than this share of
## its target, or a main hallway shorter than min_main_hall_units.
@export var min_rooms_share: float = 0.5
@export var min_main_hall_units: int = 3

@export_group("Tile standards (V1, V2)")
## Size of one grid square in metres. Every tile's footprint is a whole number of these.
## Changing it means rebuilding every tile, so it is here to read, not to tune.
@export var grid_unit: float = 3.0
## Every door socket's opening (metres). A double door fits; a cart needs only 1.6 m.
@export var doorway_width: float = 2.4
@export var doorway_height: float = 2.8
## Ceiling height at every tile edge (metres). The cargo lift cage is 3.4 m tall.
@export var ceiling_height: float = 3.6
## Walls are this thick, centred on the footprint edge (metres).
@export var wall_thickness: float = 0.3
## The elevator tile's footprint (grid units). The lift cage plus its shaft gap is 6.6 m wide.
@export var elevator_size_units: Vector2i = Vector2i(3, 3)
## The welcome center's footprint (grid units).
@export var welcome_center_size_units: Vector2i = Vector2i(8, 6)
## Room footprints (grid units) for each size category. Either way round counts (2x3 = 3x2).
@export var small_room_sizes: Array[Vector2i] = [Vector2i(2, 2), Vector2i(2, 3), Vector2i(3, 3)]
@export var medium_room_sizes: Array[Vector2i] = [Vector2i(3, 4), Vector2i(4, 4), Vector2i(4, 5)]
@export var large_room_sizes: Array[Vector2i] = [Vector2i(5, 6), Vector2i(6, 6), Vector2i(6, 8)]

@export_group("Floor brackets")
## The first floor of each bracket, for the "by bracket" lists below: 1, 4, 8 = floors 1-3, 4-7, 8+.
@export var floor_brackets: PackedInt32Array = PackedInt32Array([1, 4, 8])

@export_group("Main hallways (V3)")
## Length of each main hallway in grid units on floor 1: rolled between these.
@export var main_hall_length_min: int = 10
@export var main_hall_length_max: int = 14
## Extra length per floor after the first (0.5 = +1 every 2 floors).
@export var main_hall_length_per_floor: float = 0.5
## Never longer than this (grid units).
@export var main_hall_length_cap: int = 24
## Chance per hallway piece that it turns (0 to 1).
@export var main_hall_turn_chance: float = 0.1
## Most turns in one main hallway.
@export var main_hall_max_turns: int = 2

## CHANGED 2026-10-30 (Zachary): main hallways are built from walled pieces, 3 units long (one side doorway
## per side) or 5 units long (two per side). Share of straight stretches that use the 5-long piece.
@export var main_hall_long_piece_share: float = 0.5

@export_group("Branches (V4)")
## CHANGED 2026-10-30 (Zachary): branches only grow from a hallway's side doorways (the walled pieces
## decide the spacing), so there is no "branch every few units" number any more. Each side doorway rolls
## what grows there (weights, compared with each other); "nothing" leaves it capped.
@export var branch_room_weight: float = 0.4
@export var branch_cluster_weight: float = 0.2
@export var branch_hall_weight: float = 0.3
@export var branch_nothing_weight: float = 0.1
## Rooms in a cluster (rooms joined by inner doors, one entrance) (Q28).
@export var cluster_rooms_min: int = 2
@export var cluster_rooms_max: int = 4
## How many times secondary hallways may branch again, by floor bracket.
@export var max_branch_depth_by_bracket: PackedInt32Array = PackedInt32Array([2, 3, 3])
## NEW 2026-10-31 (step 3): length of a secondary hallway (grid units): rolled between these.
@export var secondary_hall_length_min: int = 3
@export var secondary_hall_length_max: int = 10
## NEW 2026-10-31: chance a secondary hallway splits in two at a T junction (each piece it adds).
@export var secondary_split_chance: float = 0.15
## NEW 2026-10-31: chance per piece that a secondary hallway turns a corner.
@export var secondary_turn_chance: float = 0.15

@export_group("Floor size (V5)")
## Rooms on floor 1 (hallways come on top).
@export var target_rooms_base: int = 10
## Extra rooms per floor after the first.
@export var target_rooms_per_floor: float = 1.0
## Never more rooms than this.
@export var target_rooms_cap: int = 28

@export_group("Loops (V6)")
## Extra connections that make a second route, by floor bracket.
@export var loops_by_bracket: PackedInt32Array = PackedInt32Array([1, 2, 3])
## Largest gap (grid units) a loop's short hallway may bridge.
@export var loop_max_gap_units: int = 4

@export_group("Incident and damage (V7)")
## How far the damage spreads, 0 to 1: base on floor 1, plus per floor, never above the cap.
@export var damage_intensity_base: float = 0.35
@export var damage_intensity_per_floor: float = 0.06
@export var damage_intensity_cap: float = 1.0
## Damage fades to nothing over this walking distance from the incident's room (metres).
@export var damage_falloff_metres: float = 45.0
## Random wobble added to each tile's damage score (plus or minus).
@export var damage_noise: float = 0.1
## Damage score at which a tile becomes lightly damaged, heavily damaged, destroyed.
@export var damage_light_threshold: float = 0.2
@export var damage_heavy_threshold: float = 0.5
@export var damage_destroyed_threshold: float = 0.8
## Chance a destroyed hallway collapses (only where a loop gives a way round it).
@export var collapse_chance: float = 0.5
## The welcome center and security room are never worse than this (Q30).
@export var start_area_max_damage: StringName = &"light"
## The incident starts at least this share of the farthest walking distance from the elevator (Q13).
@export var incident_min_distance_share: float = 0.5

@export_group("Damage lighting")
## NEW 2026-10-30 (Zachary): what damage does to a tile's ceiling lights (group "tile_light") and red emergency
## lights (group "tile_emergency_light"). Ranges are seconds, rolled between x and y each time. Flickering is
## looks only (not sent over the network) and seeded by each light's node path, so every PC looks alike.
## While a light flickers it switches this often (each light's own speed changes it too).
## CHANGED 2026-10-31 (Zachary: "way more random"): wider ranges and the randomness settings below.
@export var flicker_toggle_seconds: Vector2 = Vector2(0.02, 0.2)
## Each light gets its own speed: all its waits are multiplied by a number rolled between these, so lights
## in the same room never keep the same rhythm.
@export var flicker_light_speed: Vector2 = Vector2(0.5, 2.0)
## While flickering, the chance each switch turns the light on (otherwise off). Not a strict on-off-on rhythm.
@export var flicker_on_chance: float = 0.55
## Brightness of each flash, as a share of the light's brightness for its damage level (rolled every flash).
@export var flicker_brightness: Vector2 = Vector2(0.2, 1.0)
## Chance a flicker is just one quick blink instead of a stuttering burst.
@export var flicker_single_blink_chance: float = 0.35
## Lightly damaged: share of lights that flicker now and then; the rest stay on.
@export var light_flicker_share: float = 0.3
## Lightly damaged: on this long between flickers, then flickers for this long.
@export var light_on_seconds: Vector2 = Vector2(1.0, 12.0)
@export var light_flicker_seconds: Vector2 = Vector2(0.05, 0.6)
## Heavily damaged: share of lights that are dead; the rest flicker more and stay dark longer.
@export var heavy_dead_share: float = 0.3
## Heavily damaged: brightness of the lights that still work (1 = normal).
@export var heavy_energy: float = 0.6
## Heavily damaged: dark this long between flickers, then flickers for this long.
@export var heavy_dark_seconds: Vector2 = Vector2(0.5, 6.0)
@export var heavy_flicker_seconds: Vector2 = Vector2(0.1, 2.0)
## Destroyed: share of lights that are dead; the rest only flicker faintly once in a while.
@export var destroyed_dead_share: float = 0.7
@export var destroyed_energy: float = 0.35
@export var destroyed_dark_seconds: Vector2 = Vector2(4.0, 25.0)
@export var destroyed_flicker_seconds: Vector2 = Vector2(0.03, 0.4)
## Destroyed: the red emergency light stays on this long, then flickers for this long.
## (Heavily damaged rooms keep their emergency light steady.)
@export var emergency_on_seconds: Vector2 = Vector2(2.0, 12.0)
@export var emergency_flicker_seconds: Vector2 = Vector2(0.05, 0.6)

@export_group("Doors (V8)")
## Door type weights by damage level, in this order: open, broken open, jammed, debris.
@export var door_weights_pristine: PackedFloat32Array = PackedFloat32Array([95.0, 5.0, 0.0, 0.0])
@export var door_weights_light: PackedFloat32Array = PackedFloat32Array([75.0, 10.0, 10.0, 5.0])
@export var door_weights_heavy: PackedFloat32Array = PackedFloat32Array([40.0, 20.0, 25.0, 15.0])
@export var door_weights_destroyed: PackedFloat32Array = PackedFloat32Array([15.0, 35.0, 25.0, 25.0])

@export_group("Keycards (V9)")
## Keycard doors per floor, by floor bracket: rolled between min and max.
@export var keycard_doors_min_by_bracket: PackedInt32Array = PackedInt32Array([0, 1, 2])
@export var keycard_doors_max_by_bracket: PackedInt32Array = PackedInt32Array([1, 2, 3])
## Most lift parts behind keycard doors, by floor bracket (1 on low floors: Zachary).
@export var parts_behind_keycards_max_by_bracket: PackedInt32Array = PackedInt32Array([1, 2, 3])
## Most keycard colours on one floor (Q9).
@export var keycard_colours_max: int = 3

@export_group("Lift parts (V10)")
## Broken lift parts per floor, by floor bracket: rolled between min and max (Zachary's brackets).
@export var parts_min_by_bracket: PackedInt32Array = PackedInt32Array([1, 2, 3])
@export var parts_max_by_bracket: PackedInt32Array = PackedInt32Array([2, 3, 5])
## Bigger parts get more likely higher up: weight x (1 + this x (floor - 1) x size step).
@export var part_size_bias_per_floor: float = 0.15
## Parts are at least this share of the farthest room's walking distance from the elevator (Zachary).
@export var part_min_distance_share: float = 0.4
## From this floor, at least one part is near the incident (Q14).
@export var part_near_incident_from_floor: int = 4
## "Near the incident" = in a heavy or destroyed room, or within this walking distance of it (metres).
@export var part_near_incident_metres: float = 15.0

@export_group("Security cameras (V11)")
@export var cameras_per_main_hall: int = 2
@export var cameras_per_part_room: int = 1
@export var cameras_random: int = 2
## Monitors in the security room (Q12).
@export var security_monitors: int = 4
## Chance a camera is broken (shows static) in heavily damaged and destroyed areas.
@export var camera_broken_chance_heavy: float = 0.4
@export var camera_broken_chance_destroyed: float = 1.0

@export_group("Hazards (V12)")
## Hazards on floor 1: rolled between these.
@export var hazards_min: int = 1
@export var hazards_max: int = 2
## Extra hazards per floor after the first (0.5 = +1 every 2 floors), never above the cap.
@export var hazards_per_floor: float = 0.5
@export var hazards_cap: int = 10
## Hazards only in rooms at least this damaged.
@export var hazard_min_damage: StringName = &"heavy"
## NEW 2026-10-31 (step 4b, placeholder hazard zones in systems/hazards): damage per second to anyone
## standing in one, by hazard kind (kinds not listed use "sparks"), and its damage type.
@export var hazard_damage_per_second: Dictionary[StringName, float] = {&"sparks": 8.0, &"fire": 12.0}
@export var hazard_damage_types: Dictionary[StringName, StringName] = {&"sparks": &"electric", &"fire": &"fire"}
## How often a hazard hurts (seconds) and how big its zone is (radius, metres).
@export var hazard_tick_seconds: float = 0.5
@export var hazard_radius: float = 1.4

@export_group("Security room (V13)")
## Camera feed picture size (pixels) and how often it redraws (times a second).
@export var feed_resolution: Vector2i = Vector2i(256, 144)
@export var feed_updates_per_second: float = 8.0
## Feeds only draw while someone is this close to the security room (metres) (Q12).
@export var feed_active_radius: float = 12.0
## How often the map table moves its dots (times a second).
@export var map_updates_per_second: float = 5.0

@export_group("Validation (V14)")
## Tries before giving up and building the safe fallback floor (Q24).
@export var max_attempts: int = 25

@export_group("Jammed doors and debris (V15)")
## Seconds of holding E with a crowbar to pry a jammed door.
@export var pry_seconds: float = 3.0
## Props in a debris pile blocking a doorway: rolled between these (Q8).
@export var debris_pieces_min: int = 4
@export var debris_pieces_max: int = 8
## Heaviest debris piece (kg), so one player can always move it.
@export var debris_piece_max_mass: float = 15.0
## Share of jammed doors that need power instead of a crowbar (F7).
@export var power_door_share: float = 0.5
## Departments with a different share, e.g. {&"department_robotics": 0.65}.
@export var power_door_share_by_department: Dictionary[StringName, float] = {&"department_robotics": 0.65}
## From this floor a breaker box may be missing its power cell (F6).
@export var power_cell_from_floor: int = 4
## Every floor with a pry door on a needed route gets its own crowbar, even if a player has one (F5).
@export var crowbar_on_every_pry_floor: bool = true

@export_group("Markers (step 3 stand-in for step 10)")
## NEW 2026-10-31: share of "prop_spawn" markers that get a prop (the rest stay empty), so big floors don't
## fill up with crates. Step 10 of the plan replaces this with department prop pools.
@export var prop_spawn_share: float = 0.35
## NEW 2026-10-31 (step 4b): share of prop spots used in heavily damaged and destroyed rooms (loose debris).
@export var prop_spawn_share_damaged: float = 0.8
## NEW 2026-10-31 (step 4b): chance a used prop spot gets loose debris instead of a normal prop, by damage.
@export var debris_prop_chance_light: float = 0.2
@export var debris_prop_chance_heavy: float = 0.6
@export var debris_prop_chance_destroyed: float = 0.9
## NEW 2026-10-31 (step 4b): the loose debris props (PropData ids), picked evenly.
@export var debris_prop_ids: Array[StringName] = [&"prop_debris_chunk", &"prop_debris_panel"]

@export_group("Rooms (V16)")
## Share of non-required room slots that get a shared room (office, storage...). A department's
## shared_room_weight (when not -1) replaces it.
@export var shared_room_share: float = 0.35

# TODO (F3, game_flow, later step): run_floor_count 18 and boss_every_floors 6 belong in GameConfig and
# replace departments_per_run / floors_per_department when game_flow rolls a department every floor.


## A "grows with the floor" number: base + per_floor x (floor - 1), never above cap.
static func grown(base: float, per_floor: float, cap: float, floor_number: int) -> float:
	return minf(base + per_floor * float(maxi(floor_number - 1, 0)), cap)


## Which floor bracket a floor is in (0 for the first). See floor_brackets.
func bracket_index(floor_number: int) -> int:
	var index: int = 0
	for i: int in floor_brackets.size():
		if floor_number >= floor_brackets[i]:
			index = i
	return index


## The number for this floor from a "by bracket" list (the last one if the list is short).
func by_bracket(values: PackedInt32Array, floor_number: int) -> int:
	if values.is_empty():
		return 0
	return values[mini(bracket_index(floor_number), values.size() - 1)]


## The size category ("small", "medium", "large") of a room footprint in grid units, or "" if it is in
## none of the lists. Either way round counts.
func size_category_for(size_units: Vector2i) -> StringName:
	var turned := Vector2i(size_units.y, size_units.x)
	var categories: Dictionary[StringName, Array] = {
		&"small": small_room_sizes, &"medium": medium_room_sizes, &"large": large_room_sizes}
	for category: StringName in categories:
		var sizes: Array = categories[category]
		if sizes.has(size_units) or sizes.has(turned):
			return category
	return &""
