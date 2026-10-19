class_name DamageService
extends Node
## Autoload "Damage". Gives every player body its damage components as soon as it spawns (so the player
## scene doesn't need editing): "Stats" (StatsComponent), "Health" (HealthComponent, Config.game.
## player_max_health), "Statuses" (StatusEffectComponent) and a "Hurtbox" capsule. Also: hit() for
## attacks, and the console commands hurt, heal, god, status and revive. Spec: docs/systems/damage.md.
##
## STUB (death_respawn): a player whose health reaches 0 is revived by the host after
## STUB_REVIVE_SECONDS with a toast, until death_respawn handles dying and reprinting.

const HURTBOX_RADIUS: float = 0.4
const HURTBOX_HEIGHT: float = 1.8
const STUB_REVIVE_SECONDS: float = 3.0


func _ready() -> void:
	EventBus.player_spawned.connect(_on_player_spawned)
	DebugConsole.register_command(&"hurt", _cmd_hurt, "hurt [amount] [type]: hurt yourself (default 25 blunt)")
	DebugConsole.register_command(&"heal", _cmd_heal, "heal [amount]: heal yourself (default: full)")
	DebugConsole.register_command(&"god", _cmd_god, "god: you can't be hurt (again to turn off)")
	DebugConsole.register_command(&"status", _cmd_status, "status <id>: give yourself a status effect, e.g. status_burning")
	DebugConsole.register_command(&"revive", _cmd_revive, "revive: bring yourself back with full health")


## Host: hit something with an attack. Goes through its Hurtbox if it has one (weak spots), otherwise
## straight to its HealthComponent. False if it can't be hurt.
func hit(target: Node, info: DamageInfo) -> bool:
	if not multiplayer.is_server() or target == null or info == null:
		return false
	var hurtbox := target as Hurtbox
	if hurtbox != null:
		hurtbox.receive_hit(info)
		return hurtbox.get_health() != null
	var health: HealthComponent = HealthComponent.of(target)
	if health == null:
		return false
	health.apply_damage(info)
	return true


## Gives a node the damage components (used for player bodies; enemies and props can use it too).
## Leaves existing ones alone.
static func give_components(target: Node3D, max_health: float, hurtbox_radius: float = HURTBOX_RADIUS,
		hurtbox_height: float = HURTBOX_HEIGHT) -> void:
	if target.get_node_or_null(NodePath(StatsComponent.NODE_NAME)) == null:
		target.add_child(StatsComponent.new())
	if target.get_node_or_null(NodePath(HealthComponent.NODE_NAME)) == null:
		var health := HealthComponent.new()
		health.max_health = max_health
		target.add_child(health)
	if target.get_node_or_null(NodePath(StatusEffectComponent.NODE_NAME)) == null:
		target.add_child(StatusEffectComponent.new())
	if target.get_node_or_null(NodePath(Hurtbox.NODE_NAME)) == null and hurtbox_radius > 0.0:
		var hurtbox := Hurtbox.new()
		hurtbox.name = Hurtbox.NODE_NAME
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = hurtbox_radius
		capsule.height = hurtbox_height
		shape.shape = capsule
		shape.position.y = hurtbox_height / 2.0
		hurtbox.add_child(shape)
		target.add_child(hurtbox)


func _on_player_spawned(_player_id: int, player_node: Node3D) -> void:
	var body := player_node as PlayerCharacter
	if body == null or body.is_queued_for_deletion():
		return
	give_components(body, Config.game.player_max_health)
	var health: HealthComponent = HealthComponent.of(body)
	if not health.died.is_connected(_on_player_died):
		health.died.connect(_on_player_died.bind(body))


## STUB (death_respawn): come back after a few seconds.
func _on_player_died(_info: DamageInfo, body: PlayerCharacter) -> void:
	if body.is_local():
		EventBus.toast_requested.emit("You died! (death_respawn isn't built yet: back in %d s)" % int(STUB_REVIVE_SECONDS))
	if not multiplayer.is_server():
		return
	get_tree().create_timer(STUB_REVIVE_SECONDS).timeout.connect(func() -> void:
		if is_instance_valid(body) and body.is_inside_tree():
			var health: HealthComponent = HealthComponent.of(body)
			if health != null and health.is_dead():
				health.revive(1.0))


func _player_health(player_id: int) -> HealthComponent:
	var body: PlayerCharacter = PlayerCharacter.find(player_id)
	return HealthComponent.of(body) if body != null else null


func _cmd_hurt(args: PackedStringArray, player_id: int) -> String:
	var health: HealthComponent = _player_health(player_id)
	if health == null:
		return "You have no body right now."
	var amount: float = args[0].to_float() if args.size() > 0 and args[0].is_valid_float() else 25.0
	var damage_type := StringName(args[1]) if args.size() > 1 else &"blunt"
	var info := DamageInfo.make(amount, damage_type)
	info.source_player_id = player_id
	health.apply_damage(info)
	return "Health: %d / %d" % [roundi(health.get_current()), roundi(health.get_max())]


func _cmd_heal(args: PackedStringArray, player_id: int) -> String:
	var health: HealthComponent = _player_health(player_id)
	if health == null:
		return "You have no body right now."
	health.heal(args[0].to_float() if args.size() > 0 and args[0].is_valid_float() else health.get_max())
	return "Health: %d / %d" % [roundi(health.get_current()), roundi(health.get_max())]


func _cmd_god(_args: PackedStringArray, player_id: int) -> String:
	var health: HealthComponent = _player_health(player_id)
	if health == null:
		return "You have no body right now."
	health.invulnerable = not health.invulnerable
	return "God mode %s." % ("on" if health.invulnerable else "off")


func _cmd_status(args: PackedStringArray, player_id: int) -> String:
	var body: PlayerCharacter = PlayerCharacter.find(player_id)
	var statuses: StatusEffectComponent = StatusEffectComponent.of(body) if body != null else null
	if statuses == null:
		return "You have no body right now."
	if args.is_empty():
		return "Usage: status <id>. Try: list status"
	var status_id := StringName(args[0])
	if not ContentRegistry.get_content(status_id) is StatusEffectData:
		return "No status effect called '%s'. Try: list status" % status_id
	statuses.apply(status_id, player_id)
	return "Gave you %s." % status_id


func _cmd_revive(_args: PackedStringArray, player_id: int) -> String:
	var health: HealthComponent = _player_health(player_id)
	if health == null:
		return "You have no body right now."
	health.revive(1.0)
	return "Revived."
