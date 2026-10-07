class_name PhysicsLayers
extends RefCounted
## Collision layer numbers, matching the names in Project Settings > Layer Names > 3D Physics.
## Use PhysicsLayers.bit(PhysicsLayers.PROPS) when setting masks in code.

## Floors, walls, static level geometry.
const WORLD: int = 1
const PLAYERS: int = 2
const ENEMIES: int = 3
## Loose physics props: gems, meat, crates, robot parts, lift parts.
const PROPS: int = 4
## A prop while a player holds it (so it ignores its own holder).
const HELD_PROPS: int = 5
const CARTS: int = 6
## Areas that detect things but don't block (elevator zone, printer slot, vendor slot).
const TRIGGERS: int = 7
## Things the "use" ray can hit (buttons, vendors, doors).
const INTERACTABLES: int = 8
## Enemy attacks, thrown-item hits.
const HITBOXES: int = 9


## Turns a layer number into the bit value Godot's collision_layer/mask use.
static func bit(layer: int) -> int:
	return 1 << (layer - 1)
