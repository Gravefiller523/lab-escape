extends MeshInstance3D
## On a glowing gem's (or robot part's) mesh: takes the glow colour of the upgrade the prop holds
## (NetProp.extra.upgrade_id -> UpgradeData.glow_color), so you can tell what's inside by its colour.


func _ready() -> void:
	var prop := get_parent() as NetProp
	if prop == null:
		return
	var upgrade_id := StringName(str(prop.extra.get("upgrade_id", "")))
	var upgrade := ContentRegistry.get_content(upgrade_id) as UpgradeData
	if upgrade == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = upgrade.glow_color
	material.emission_enabled = true
	material.emission = upgrade.glow_color
	material.emission_energy_multiplier = 1.5
	material_override = material
