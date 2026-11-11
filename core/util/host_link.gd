class_name HostLink
## Helpers for clients talking to the host (NEW 2026-11-11, roadmap WP1).


## Client: calls `send` now if the connection to the host is open, or as soon as it opens. A PC that joins mid-floor
## builds the floor before net_core's join handshake opens the connection, so machines and devices that ask the host
## for their state in _ready would otherwise ask too early and never hear back. `send` should be a method of `node`,
## so the wait is dropped if the node is freed first.
static func when_connected(node: Node, send: Callable) -> void:
	var api: MultiplayerAPI = node.multiplayer
	if api.get_peers().has(1):
		send.call()
	elif not api.connected_to_server.is_connected(send):
		api.connected_to_server.connect(send, CONNECT_ONE_SHOT)
