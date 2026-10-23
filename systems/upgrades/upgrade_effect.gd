class_name UpgradeEffect
extends RefCounted
## Runtime building block for one kind of UpgradeEffectData. Found by file name:
## MovementEffectData (movement_effect_data.gd) -> systems/upgrades/effects/movement_effect.gd.
## apply / remove run on every PC (the owner needs movement, everyone needs looks and voice); pieces
## that change host-owned state (slots) only act on the host. Spec: docs/systems/upgrades.md.

const EFFECTS_FOLDER: String = "res://systems/upgrades/effects/"

static var _cache: Dictionary[String, UpgradeEffect] = {}


static func for_data(data: UpgradeEffectData) -> UpgradeEffect:
	if data == null or data.get_script() == null:
		return null
	var data_file: String = (data.get_script() as Script).resource_path.get_file()
	var runtime_path: String = EFFECTS_FOLDER + data_file.trim_suffix("_data.gd") + ".gd"
	if not _cache.has(runtime_path):
		if not ResourceLoader.exists(runtime_path):
			push_error("UpgradeEffect: no runtime file %s for %s." % [runtime_path, data_file])
			return null
		_cache[runtime_path] = (load(runtime_path) as GDScript).new() as UpgradeEffect
	return _cache[runtime_path]


func apply(_player: PlayerCharacter, _data: UpgradeEffectData, _source_id: StringName) -> void:
	pass


func remove(_player: PlayerCharacter, _data: UpgradeEffectData, _source_id: StringName) -> void:
	pass
