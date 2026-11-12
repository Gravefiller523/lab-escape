class_name PlayerProfile
extends RefCounted
## One player's profile on their own PC (NEW 2026-11-12, roadmap WP12): unlocked cosmetics, the outfit they wear,
## lifetime stats and the first-time hints already shown. Runs are never saved. Spec: docs/systems/save_load.md.

var unlocked_cosmetic_ids: Array[StringName] = []
## slot -> cosmetic id
var loadout: Dictionary = {}
## stat name -> count, e.g. "runs_escaped" or "boss_defeated:boss_giant_rat".
var stats: Dictionary = {}
## Hints (HintData ids) this player has already seen.
var seen_hint_ids: Array[StringName] = []


func to_dict() -> Dictionary:
	var cosmetics: Array[String] = []
	for id: StringName in unlocked_cosmetic_ids:
		cosmetics.append(String(id))
	var hints: Array[String] = []
	for id: StringName in seen_hint_ids:
		hints.append(String(id))
	return {"save_version": SaveService.SAVE_VERSION, "unlocked_cosmetic_ids": cosmetics, "loadout": loadout.duplicate(),
		"stats": stats.duplicate(), "seen_hint_ids": hints}


## Builds a profile from an up-to-date dictionary (SaveService migrates old ones first). Missing fields get defaults;
## ids of content that no longer exists are kept, so removing content never deletes progress.
static func from_dict(data: Dictionary) -> PlayerProfile:
	var profile := PlayerProfile.new()
	for id: Variant in data.get("unlocked_cosmetic_ids", []) as Array:
		profile.unlocked_cosmetic_ids.append(StringName(str(id)))
	profile.loadout = (data.get("loadout", {}) as Dictionary).duplicate()
	var saved_stats: Dictionary = data.get("stats", {})
	for key: Variant in saved_stats:
		profile.stats[str(key)] = int(saved_stats[key])
	for id: Variant in data.get("seen_hint_ids", []) as Array:
		profile.seen_hint_ids.append(StringName(str(id)))
	return profile
