class_name PlayerRecord
extends RefCounted
## Everything the host remembers about one player during a run, so a player who drops and
## rejoins gets it all back. The host's copy is the truth; clients get read-only copies.
## Change fields on the host with Net.update_record(), never directly.

var player_id: int = 0
var display_name: String = ""
var slot_index: int = -1
var connected: bool = true
var is_alive: bool = true
## Joined mid-run: spectates like a dead player and spawns with everyone at the next floor.
var waiting_for_next_floor: bool = false
## Written by upgrades. Repeated ids are stacks.
var upgrade_ids: Array[StringName] = []
## Slot -> cosmetic id, written by cosmetics.
var cosmetic_loadout: Dictionary = {}


## A copy that can be sent over the network (only plain types inside).
func to_dict() -> Dictionary:
	return {
		"player_id": player_id,
		"display_name": display_name,
		"slot_index": slot_index,
		"connected": connected,
		"is_alive": is_alive,
		"waiting_for_next_floor": waiting_for_next_floor,
		"upgrade_ids": upgrade_ids.duplicate(),
		"cosmetic_loadout": cosmetic_loadout.duplicate(true),
	}


static func from_dict(data: Dictionary) -> PlayerRecord:
	var record := PlayerRecord.new()
	record.apply_dict(data)
	return record


## Copies every field found in data onto this record (missing fields are left alone).
## Used by Net to update a record in place, so other systems' references stay valid.
func apply_dict(data: Dictionary) -> void:
	player_id = data.get("player_id", player_id)
	display_name = str(data.get("display_name", display_name))
	slot_index = data.get("slot_index", slot_index)
	connected = data.get("connected", connected)
	is_alive = data.get("is_alive", is_alive)
	waiting_for_next_floor = data.get("waiting_for_next_floor", waiting_for_next_floor)
	if data.has("upgrade_ids"):
		var upgrades: Array = data["upgrade_ids"]
		upgrade_ids.clear()
		for upgrade_id: Variant in upgrades:
			upgrade_ids.append(StringName(str(upgrade_id)))
	if data.has("cosmetic_loadout"):
		var loadout: Dictionary = data["cosmetic_loadout"]
		cosmetic_loadout = loadout.duplicate(true)
