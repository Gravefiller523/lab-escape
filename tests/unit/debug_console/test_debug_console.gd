extends GutTest
## Tests for debug_console (docs/systems/debug_console.md). Each test makes its own console (not the
## autoload). The client -> host test uses two "PCs": SubViewports with their own multiplayer and Net,
## connected over real ENet, each with a console called "DebugConsole".

const PORT: int = 18060
const WAIT: float = 5.0

var _pcs: Array[Node] = []


func _config(cheats_in_release: bool = false) -> GameConfig:
	var config := GameConfig.new()
	config.cheats_in_release = cheats_in_release
	return config


## A console on its own (solo, so this PC is the host).
func _console(is_editor: bool = true, config: GameConfig = null) -> DebugConsoleService:
	var console := DebugConsoleService.new()
	console.use_test_setup(Net, config if config != null else _config(), is_editor)
	add_child_autofree(console)
	return console


func _make_pc(config: GameConfig) -> Node:
	var pc := SubViewport.new()
	pc.name = "Pc%d" % _pcs.size()
	add_child(pc)
	get_tree().set_multiplayer(SceneMultiplayer.new(), pc.get_path())
	var net := NetService.new()
	net.name = "Net"
	net.use_config(config)
	pc.add_child(net)
	var console := DebugConsoleService.new()
	console.name = "DebugConsole"
	console.use_test_setup(net, config, true)
	pc.add_child(console)
	_pcs.append(pc)
	return pc


func _net(pc: Node) -> NetService:
	return pc.get_node("Net") as NetService


func _pc_console(pc: Node) -> DebugConsoleService:
	return pc.get_node("DebugConsole") as DebugConsoleService


func after_each() -> void:
	var paths: Array[NodePath] = []
	var peers: Array[MultiplayerPeer] = []
	for pc: Node in _pcs:
		paths.append(pc.get_path())
		peers.append(pc.multiplayer.multiplayer_peer)
		pc.free()
	for index: int in paths.size():
		if peers[index] != null:
			peers[index].close()
		get_tree().set_multiplayer(null, paths[index])
	_pcs.clear()


func test_register_and_run_command() -> void:
	var console := _console()
	console.register_command(&"echo", func(args: PackedStringArray, _player_id: int) -> String:
		return " ".join(args), "echo <text>: prints the text", false)
	assert_eq(console.run("echo hello there"), "hello there")
	assert_eq(console.run("  ECHO  loud "), "loud", "names ignore case and extra spaces")
	assert_string_contains(console.run("help"), "echo <text>")
	assert_eq(console.run(""), "", "an empty line does nothing")


func test_unknown_command_message() -> void:
	var console := _console()
	assert_eq(console.run("fly_to_the_moon now"), DebugConsoleService.MSG_UNKNOWN % "fly_to_the_moon")


func test_spawn_routes_by_prefix() -> void:
	var console := _console()
	var calls: Array[Dictionary] = []
	console.register_spawner(&"prop", func(id: StringName, at: Transform3D, count: int, player_id: int) -> String:
		calls.append({"id": id, "at": at, "count": count, "player_id": player_id})
		return "fake spawned %d" % count)
	assert_eq(console.run("spawn prop_crate 3"), "fake spawned 3")
	assert_eq(calls.size(), 1)
	assert_eq(calls[0]["id"], &"prop_crate")
	assert_eq(calls[0]["count"], 3)
	assert_eq(calls[0]["player_id"], Net.local_player_id())
	console.run("spawn prop_crate 5000")
	assert_eq(calls[1]["count"], 100, "count is capped at 100")
	assert_string_contains(console.run("spawn prop_does_not_exist"), "No content called")
	assert_eq(calls.size(), 2, "unknown ids never reach a spawner")


func test_spawn_without_spawner_says_so() -> void:
	var console := _console()
	assert_string_contains(console.run("spawn prop_crate"), "no spawner registered")


func test_spread_lays_things_out_apart() -> void:
	var at := Transform3D(Basis.IDENTITY, Vector3(1, 2, 3))
	var first: Vector3 = DebugConsoleService.spread(at, 0).origin
	var second: Vector3 = DebugConsoleService.spread(at, 1).origin
	assert_almost_eq(first.distance_to(second), DebugConsoleService.SPAWN_SPREAD, 0.001)


func test_cheats_blocked_in_release_by_default() -> void:
	var release := _console(false)
	assert_false(release.cheats_allowed())
	release.register_command(&"god", func(_args: PackedStringArray, _player_id: int) -> String: return "god on",
		"god: can't die")
	assert_eq(release.run("god"), DebugConsoleService.MSG_NO_CHEATS)
	assert_ne(release.run("help"), DebugConsoleService.MSG_NO_CHEATS, "non-cheat commands still work")
	var allowed := _console(false, _config(true))
	assert_true(allowed.cheats_allowed(), "the config can allow cheats in release")
	assert_true(_console(true).cheats_allowed(), "editor builds always allow cheats")


func test_validate_matches_content_test() -> void:
	var console := _console()
	var problems: PackedStringArray = ContentValidator.validate_all(
		ContentRegistry.get_everything(), ContentRegistry.get_type_keys())
	problems.append_array(ContentRegistry.load_errors)
	var output: String = console.run("validate")
	if problems.is_empty():
		assert_string_contains(output, "are OK")
	else:
		for problem: String in problems:
			assert_string_contains(output, problem)


func test_list_shows_ids() -> void:
	var console := _console()
	assert_string_contains(console.run("list prop"), "prop_crate")
	assert_string_contains(console.run("list"), "prop")


func test_client_host_only_command_goes_to_host() -> void:
	var config := _config()
	var host := _make_pc(config)
	var server := ENetMultiplayerPeer.new()
	assert_eq(server.create_server(PORT, 32), OK)
	host.multiplayer.multiplayer_peer = server
	var client := _make_pc(config)
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", PORT)
	client.multiplayer.multiplayer_peer = peer
	await wait_until(func() -> bool: return _net(host).get_player_ids().size() == 2, WAIT)
	assert_eq(_net(host).get_player_ids().size(), 2, "the client joined")

	for pc: Node in _pcs:
		var net: NetService = _net(pc)
		_pc_console(pc).register_command(&"whoami", func(_args: PackedStringArray, player_id: int) -> String:
			return "host=%s player=%d" % [net.is_host(), player_id], "whoami: test cheat")
	var client_id: int = _net(client).local_player_id()
	assert_eq(_pc_console(client).run("whoami"), DebugConsoleService.MSG_SENT_TO_HOST)
	await wait_until(func() -> bool: return not _pc_console(client).last_remote_output.is_empty(), WAIT)
	assert_eq(_pc_console(client).last_remote_output, "host=true player=%d" % client_id,
		"the host ran it as the client's player and sent the output back")
	assert_eq(_pc_console(client).run("help").is_empty(), false, "non-cheat commands run on the client")
