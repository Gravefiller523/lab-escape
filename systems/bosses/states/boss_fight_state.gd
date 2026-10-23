extends EnemyState
## The state every boss uses: waits until the fight starts (the arena starts it, or the boss sees a
## player), then walks at its target between attacks, picking attacks from its current phase and
## running minion waves. Host only.


func physics_update(enemy: Enemy, delta: float) -> StringName:
	var boss := enemy as Boss
	if boss == null:
		return &""
	var target: PlayerCharacter = boss.update_target()
	if not boss.is_fighting():
		boss.stop()
		# In an arena the arena starts the fight (when a player walks in); elsewhere seeing a player does.
		if target != null and BossArena.current() == null:
			boss.start_fight()
		return &""
	boss.update_waves(delta)
	var attack: BossAttack = boss.get_current_attack()
	if attack != null:
		attack.update(boss, delta)
		if attack.is_finished():
			boss.end_attack()
		return &""
	if target == null:
		boss.stop()
		return &""
	var next: BossAttack = boss.choose_attack()
	if next != null:
		boss.begin_attack(next)
		return &""
	boss.move_towards(target.global_position, 1.0, delta)
	return &""
