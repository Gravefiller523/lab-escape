class_name InputActions
extends RefCounted
## Names of every input action, plus default keys.
## Always use these constants (InputActions.USE), never type the string.
## The settings_input system loads the player's rebinds on top of these defaults.
## Adding an action: add a constant and a default here (foundation change, see CLAUDE.md).

const MOVE_FORWARD: StringName = &"move_forward"
const MOVE_BACK: StringName = &"move_back"
const MOVE_LEFT: StringName = &"move_left"
const MOVE_RIGHT: StringName = &"move_right"
const JUMP: StringName = &"jump"
const CROUCH: StringName = &"crouch"
const SPRINT: StringName = &"sprint"
## Grab / interact. While holding something that grants an upgrade: eat or install it.
const USE: StringName = &"use"
## Let go of a held object.
const DROP: StringName = &"drop"
## Attack with the held item, or throw the held object.
const PRIMARY: StringName = &"primary"
## Item's second action (e.g. use-on-object).
const SECONDARY: StringName = &"secondary"
const SLOT_NEXT: StringName = &"slot_next"
const SLOT_PREV: StringName = &"slot_prev"
const PUSH_TO_TALK: StringName = &"push_to_talk"
const PAUSE: StringName = &"pause"
const DEBUG_CONSOLE: StringName = &"debug_console"

## Direct slot keys 1 to 9. Slots beyond 9 are reached with SLOT_NEXT / SLOT_PREV.
const MAX_SLOT_KEYS: int = 9

const DEFAULT_KEYS: Dictionary = {
	MOVE_FORWARD: KEY_W,
	MOVE_BACK: KEY_S,
	MOVE_LEFT: KEY_A,
	MOVE_RIGHT: KEY_D,
	JUMP: KEY_SPACE,
	CROUCH: KEY_CTRL,
	SPRINT: KEY_SHIFT,
	USE: KEY_E,
	DROP: KEY_Q,
	PUSH_TO_TALK: KEY_V,
	PAUSE: KEY_ESCAPE,
	DEBUG_CONSOLE: KEY_QUOTELEFT,
}

const DEFAULT_MOUSE_BUTTONS: Dictionary = {
	PRIMARY: MOUSE_BUTTON_LEFT,
	SECONDARY: MOUSE_BUTTON_RIGHT,
	SLOT_NEXT: MOUSE_BUTTON_WHEEL_DOWN,
	SLOT_PREV: MOUSE_BUTTON_WHEEL_UP,
}


## Action name for a direct slot key, 1-based: slot_action(1) == &"slot_1".
static func slot_action(slot_number: int) -> StringName:
	return StringName("slot_%d" % slot_number)


## Adds any missing action with its default binding. Safe to call more than once.
static func ensure_registered() -> void:
	for action: StringName in DEFAULT_KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var key_event: InputEventKey = InputEventKey.new()
			key_event.physical_keycode = DEFAULT_KEYS[action] as Key
			InputMap.action_add_event(action, key_event)
	for action: StringName in DEFAULT_MOUSE_BUTTONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var mouse_event: InputEventMouseButton = InputEventMouseButton.new()
			mouse_event.button_index = DEFAULT_MOUSE_BUTTONS[action] as MouseButton
			InputMap.action_add_event(action, mouse_event)
	for slot_number: int in range(1, MAX_SLOT_KEYS + 1):
		var action: StringName = slot_action(slot_number)
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var slot_event: InputEventKey = InputEventKey.new()
			slot_event.physical_keycode = (KEY_0 + slot_number) as Key
			InputMap.action_add_event(action, slot_event)
