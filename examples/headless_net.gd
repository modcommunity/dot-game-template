extends "suite.gd"

## A real dedicated server and a real client, in one process, over a real socket.
##
##     godot --headless --path . res://examples/headless_net.tscn
##
## The server is a [DotServer] that loads this game's module BY PATH, as a deployed server
## does. The client is a [DotClientLink] -- what the client shell connects with -- and this
## game's own client scene on top of it. Each side has its own [MultiplayerAPI], so every RPC
## crosses the socket. Nothing here reaches into the game to move anybody: the client is
## steered through its `steer` hook, exactly as a keyboard would steer it.
##
## What this cannot see is a PACK: here the game's files are at res://. That is
## dot-server-deploy's examples/template_client.tscn, which publishes this repository and runs
## it mounted.

const PORT := 28911
const SERVER_DIR := "user://tpl_headless_net"
const MODULE := "res://game/tpl_module.gd"
const CLIENT_SCENE := "res://scenes/tpl_client.tscn"

var _server: DotServer = null
var _link: DotClientLink = null
var _client: Node = null
var _client_side: Node = null


func _ready() -> void:
	checks = 14
	_run.call_deferred()


func _run() -> void:
	print("dot-game-template: a server and a client over a socket")
	DotPaths.remove_tree(SERVER_DIR)

	if await _boot() and await _test_join():
		await _test_moving()
		await _test_a_coin()
		await _test_leaving()

	if _link != null:
		_link.disconnect_from_server("done")
	if _server != null:
		_server.shutdown("done")
	await get_tree().process_frame
	DotPaths.remove_tree(SERVER_DIR)
	finish()


func _boot() -> bool:
	section("a dedicated server boots with this game")

	var server_side := Node.new()
	server_side.name = "ServerSide"
	add_child(server_side)
	_client_side = Node.new()
	_client_side.name = "ClientSide"
	add_child(_client_side)
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), server_side.get_path())
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), _client_side.get_path())

	var config := DotServerConfig.new()
	config.hostname = "template test"
	config.log_level = "warn"
	config.port = PORT
	config.bind_address = "127.0.0.1"
	config.rcon_password = ""
	config.admins_path = SERVER_DIR + "/admins.json"
	config.bans_path = SERVER_DIR + "/bans.json"
	config.audit_log_path = SERVER_DIR + "/audit.jsonl"
	config.hibernate_when_empty = false
	config.startup_config = ""
	config.autoexec_config = ""
	# Off, or this run never exits: the console reads stdin on a thread nothing can wake.
	config.stdin_console_enabled = false

	_server = DotServer.new()
	_server.name = "Server"
	_server.config = config
	_server.config_file = ""
	_server.auto_boot = false
	server_side.add_child(_server)

	var booted: DotResult = await _server.boot()
	if not check(booted.ok, "the server listens on %d" % PORT):
		done()
		return false

	# The descriptor comes from the module's script, loaded here rather than preloaded: the
	# order scripts load in is the order a deployed server has.
	var descriptor: DotGameDescriptor = (load(MODULE) as GDScript).call("game_descriptor")
	_server.games.add_game(descriptor)
	var changed: DotResult = await _server.games.change_game(descriptor.game_id, "boot")
	check(changed.ok, "the server scene loads and the world registers itself")

	var loaded: DotResult = await _server.modules.load_module(MODULE)
	check(loaded.ok, "the module loads by path")
	done()
	return changed.ok and loaded.ok


func _test_join() -> bool:
	section("a client joins")

	# Named "Server" to match the server's node: RPCs are routed by path, and the name is the
	# route. Any other name and the handshake itself goes nowhere.
	_link = DotClientLink.new()
	_link.name = "Server"
	_link.player_name = "Ada"
	_client_side.add_child(_link)

	var spawned := [false]
	_link.spawned.connect(func() -> void: spawned[0] = true)
	await _link.connect_to_server("127.0.0.1:%d" % PORT)
	check(await _until(func() -> bool: return spawned[0]), "it finishes signing on")

	_client = (load(CLIENT_SCENE) as PackedScene).instantiate()
	_client.set("link", _link)
	_client_side.add_child(_client)

	var told := await _until(func() -> bool: return int(_client.get("local_id")) != 0)
	check(told, "the client scene is told which player it is")
	check(_server_game().players.size() == 1, "the server seated one player")
	done()
	return told


func _test_moving() -> void:
	section("moving is replicated")

	var before: Vector2 = _server_player().position
	_client.set("steer", func() -> Vector2: return Vector2.RIGHT)
	var moved := await _until(func() -> bool: return _server_player().position.x > before.x + 100.0)
	_client.set("steer", func() -> Vector2: return Vector2.ZERO)
	check(moved, "the client's input moved the player on the server")

	# Stopped, both ends settle on the same spot: the prediction agreed with the server.
	await _settle(30)
	var gap: float = _client_player().position.distance_to(_server_player().position)
	check(gap < 1.0, "and the client's own copy agrees with the server (%.3f apart)" % gap)
	done()


func _test_a_coin() -> void:
	section("a coin is collected, and the score reaches the client")

	var game: Node = _client.get("game")
	# Steered at the nearest coin the CLIENT can see, every frame, as a player would.
	_client.set("steer", func() -> Vector2:
		var me: Vector2 = _client_player().position
		var best: Vector2 = game.get("coins")[0]
		for spot: Vector2 in game.get("coins"):
			if spot.distance_to(me) < best.distance_to(me):
				best = spot
		return (best - me).normalized()
	)

	var scored := await _until(func() -> bool: return _server_player().score > 0)
	check(scored, "the server scored a coin for the player")
	check(await _until(func() -> bool: return _client_player().score > 0),
		"and the client's copy shows the score (%d)" % _client_player().score)
	_client.set("steer", func() -> Vector2: return Vector2.ZERO)
	await _settle(10)
	var drift := 0.0
	for i in range(_server_game().coins.size()):
		drift = maxf(drift, (game.get("coins")[i] as Vector2).distance_to(_server_game().coins[i]))
	# Within the wire's precision: sixteen bits over the arena is about two hundredths.
	check(drift < 0.05, "and the client moved the coin where the server did (%.3f)" % drift)

	var status := _server.console.execute("tpl_status")
	check(status.ok, "the game's console command answers")
	done()


func _test_leaving() -> void:
	section("leaving")
	_link.disconnect_from_server("bye")
	var gone := await _until(func() -> bool: return _server_game().players.is_empty())
	check(gone, "the server takes the player out of the game")
	_link = null
	done()


# --- Helpers -----------------------------------------------------------------

func _server_game() -> Node:
	return (_server.modules.get_module("tpl") as DotGameModule).game as Node


func _server_player() -> Variant:
	return (_server_game().get("players") as Dictionary).values()[0]


func _client_player() -> Variant:
	var game: Node = _client.get("game")
	return (game.get("players") as Dictionary).get(int(_client.get("local_id")))


func _until(condition: Callable, seconds: float = 10.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(condition.call()):
			return true
		await get_tree().physics_frame
	return bool(condition.call())


func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().physics_frame
