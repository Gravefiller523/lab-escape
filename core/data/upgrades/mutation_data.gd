class_name MutationData
extends UpgradeData
## A mutation, gained by eating a glowing gem. Example id: "mutation_fly".
## Files live in res://content/mutations/.


func get_type_key() -> StringName:
	return &"mutation"
