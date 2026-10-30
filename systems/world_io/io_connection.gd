class_name IOConnection
extends Resource
## NEW 2026-10-30 (HL2 feel step 4.2): one wire of the world wiring kit: "when `event` happens on this
## device, do `action` on the `target` device, after `delay` seconds". Add them to a WorldDevice's
## `outputs` list in the Inspector. Spec: docs/systems/world_io.md.

## The event on this device, e.g. &"pressed" (a button), &"entered" (a trigger), &"opened" (a door).
@export var event: StringName = &"pressed"
## The device to act on, relative to this device (pick it in the Inspector).
@export var target: NodePath
## What to do to it, e.g. &"open", &"unlock", &"toggle", &"add", &"enable".
@export var action: StringName = &"open"
## Seconds to wait first.
@export var delay: float = 0.0
## Only the first time the event happens.
@export var once: bool = false
