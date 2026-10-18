extends GutTest
## The real DebugConsole autoload spawning real props through the Props autoload (solo, in the
## physics_props test scene).

const SCENE: PackedScene = preload("res://systems/physics_props/test/pass_the_box.tscn")
const WAIT: float = 5.0


func test_spawn_command_makes_props() -> void:
	var level: Node = SCENE.instantiate()
	add_child_autofree(level)
	await wait_until(func() -> bool: return PlayerCharacter.find(Net.local_player_id()) != null, WAIT)
	await wait_physics_frames(2)
	var before: int = Props.get_props(&"prop_crate").size()
	var output: String = DebugConsole.run("spawn prop_crate 3")
	assert_eq(output, "Spawned 3 x prop_crate.")
	await wait_physics_frames(2)
	assert_eq(Props.get_props(&"prop_crate").size(), before + 3)
