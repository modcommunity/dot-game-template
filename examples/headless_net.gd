extends "suite.gd"

## A real dedicated server and a real client, in one process, over a real socket.
##
##     godot --headless --path . res://examples/headless_net.tscn
##
## A [DotServer] loads the module BY PATH, as a deployed one does; a [DotClientLink] (what the
## client shell connects with) carries this game's client scene. Each side has its own
## [MultiplayerAPI], so every RPC crosses the socket, and the client is steered through its
## `steer` hook as a keyboard would steer it. It cannot see a PACK -- here the files are at
## res:// -- which is dot-server-deploy's examples/template_client.tscn.

const PORT := 28911
const CLIENT_PEER := 7
const SERVER_DIR := "user://tpl_headless_net"
const MODULE := "res://game/tpl_module.gd"
const CLIENT_SCENE := "res://scenes/tpl_client.tscn"
const TplBridge := preload("res://game/net/tpl_bridge.gd")
const TplEvent := preload("res://game/net/tpl_event.gd")
const TplGame := preload("res://game/tpl_game.gd")
const TplRequest := preload("res://game/net/tpl_request.gd")

var _server: DotServer = null
var _link: DotClientLink = null
var _client: Node = null
var _client_side: Node = null


func _ready() -> void:
	checks = 47
	_run.call_deferred()


func _run() -> void:
	print("dot-game-template: a server and a client over a socket")
	DotPaths.remove_tree(SERVER_DIR)
	_test_kinds_fit()
	await _test_map_menu_solo()
	if await _boot() and await _test_join():
		await _test_moving()
		await _test_a_coin()
		await _test_still_loading()
		await _test_chat()
		await _test_map_menu()
		await _test_drawn_through_a_slip()
		await _test_leaving()
	await _test_a_lost_input()
	if _link != null:
		_link.disconnect_from_server("done")
	if _server != null:
		_server.shutdown("done")
	await get_tree().process_frame
	DotPaths.remove_tree(SERVER_DIR)
	finish()


## A kind goes out in a fixed field the writer masks without a word, so one past it aliases
## a smaller kind and nothing errors. A game made from this one grows [enum TplEvent.Kind]
## first; the check is here so the kind that outgrows four bits fails a suite.
func _test_kinds_fit() -> void:
	section("every kind fits its field")
	check(TplEvent.fits(), "every event kind fits the kind field (%d kinds in %d bits)" % [TplEvent.Kind.size(), TplEvent.KIND_BITS])
	check(TplRequest.asks_fit(), "every request kind fits it too (%d in %d bits)" % [TplRequest.Ask.size(), TplRequest.KIND_BITS])
	done()


## M with no server: the client scene run on its own (no link yet), and the choice is the change.
func _test_map_menu_solo() -> void:
	section("M: the map menu, solo")
	var solo: Node = (load(CLIENT_SCENE) as PackedScene).instantiate()
	add_child(solo)
	await get_tree().process_frame
	var menu: DotMenu = (solo.get("settings") as DotMenuSettings).menu
	var maps: DotMenuMaps = menu.maps
	check(maps != null and not maps.is_online() and InputMap.has_action(menu.maps_action),
		"M is bound, and with no server the menu is solo")
	menu.open_maps()
	check(menu.any_open(), "M opens the arena list")
	maps.call(&"_chosen", &"pocket")
	var game: Node = solo.get("game")
	check(game.get("arena")["id"] == &"pocket" and (game.get("coins") as Array).size() == 5,
		"choosing one changes the arena at once, with its own coins")
	menu.close_all()
	solo.queue_free()
	await get_tree().process_frame
	done()


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

	# The Tab board, held on the real client: the server's roster over the socket, with the
	# coins the module adds and this player picked out.
	var menu: DotMenu = (_client.get("settings") as DotMenuSettings).menu
	menu.scoreboard.open()
	var arrived := await _until(func() -> bool:
		return menu.scoreboard.rows().any(func(r: Dictionary) -> bool:
			return bool(r.get("you", false)) and int(r.get("coins", 0)) > 0 and int(r.get("seconds", -1)) >= 0))
	check(arrived, "Tab shows the server's board: this player, their coins and their time (%s)" % str(menu.scoreboard.rows()))
	menu.scoreboard.close()
	done()


## dot-game's "still loading", over the real socket: a player the server holds as behind their
## cover collects nothing, even standing on a coin, and collects again once the client's
## `game.cover` report (the kind DotGameClient sends when its gate opens) lifts it.
func _test_still_loading() -> void:
	section("a player behind their loading cover collects nothing")
	var module := _server.modules.get_module("tpl") as DotGameModule
	var world := _server_game()
	var who: Variant = _server_player()
	check(module.can_be_harmed(who.id), "settled in, the player is in play")

	# The server's own doing, as on a map change: only the server starts a loading state.
	module.mark_reloading()
	check(module.is_loading(who.id), "the server holds the player as loading")
	var score_before: int = who.score
	var coin_before: Vector2 = world.coins[0]
	who.position = coin_before
	await _settle(15)
	check(who.score == score_before and world.coins[0] == coin_before,
		"standing on a coin collects nothing (%d, was %d)" % [who.score, score_before])

	# The client says its cover lifted, as DotGameClient does when the gate opens.
	var sent := DotGameClient.report_cover(_link, false)
	var lifted := await _until(func() -> bool: return not module.is_loading(who.id))
	check(sent and lifted, "the client's report lifts it")
	check(await _until(func() -> bool: return who.score > score_before),
		"and the same coin is then collected (%d)" % who.score)
	done()


## The chat box on the real client: a line typed goes through the server and comes back, the
## server's own lines are drawn, `!sm` never reaches the server, and typing does not steer.
func _test_chat() -> void:
	section("chat")
	var chat: DotChatWindow = _client.get("chat")
	var heard: Array = []
	_server.chat.message_sent.connect(func(_session: Object, text: String, _team: bool) -> void: heard.append(text))
	chat.call(&"_on_submitted", "hello from Ada")
	check(await _until(func() -> bool: return _shown(chat, "hello from Ada")),
		"a line typed in the box goes through the server and is drawn with its speaker")
	_server.broadcast_message("the server speaks")
	check(await _until(func() -> bool: return _shown(chat, "the server speaks")),
		"a line the server says (a vote, a `say`) is drawn")
	# An admin's line goes only to staff, and this player is not, so it is handed to the
	# client's handler as the link would hand it.
	_client.call(&"_on_chat_line", {"kind": "admin", "name": "(ADMIN) Bob", "text": "be nice"})
	check(_shown(chat, "be nice"), "and so is an admin's")

	var rows_before := chat.history().size()
	chat.call(&"_on_submitted", "!sm")
	await _settle(10)
	check(not heard.has("!sm") and not heard.has("sm"), "`!sm` is run on the client and never reaches the server")
	check(chat.history().size() > rows_before, "and it answers in the box (%s)" % str(chat.history().back()))
	# A muted player's lines are dropped. In memory only: the suite's list is not the player's.
	var mutes: DotChatSelfMute = DotChatSelfMute.shared()
	var kept_path := mutes.path
	mutes.path = ""
	mutes.set_muted({"name": "Mallory"}, true)
	_client.call(&"_on_chat_line", {"kind": "all", "userid": 99, "name": "Mallory", "text": "spam spam"})
	check(not _shown(chat, "spam spam"), "a line from somebody this player muted is not drawn")
	mutes.set_muted({"name": "Mallory"}, false)
	mutes.path = kept_path
	var console: DotConsoleController = (_client.get("platform") as DotGameClient).console as DotConsoleController
	check(console != null and console.all_names().has("sm"), "the console has `sm` too")

	# Typing is not steering: a player pressing right while the box is open moves nowhere.
	# The steer hook stands in for the keys, which a headless run cannot hold.
	_client.set("steer", func() -> Vector2: return Vector2.RIGHT)
	chat.open()
	var open_intent: Vector2 = _client.call(&"_intent")
	chat.close()
	var closed_intent: Vector2 = _client.call(&"_intent")
	check(open_intent == Vector2.ZERO and closed_intent == Vector2.RIGHT,
		"pressing right while the box is open does not move the player (open %s, closed %s)" % [open_intent, closed_intent])
	_client.set("steer", func() -> Vector2: return Vector2.ZERO)
	done()


## M on a server: a player without the owner's flag is offered a vote and the vote changes the
## arena; with the flag (here, the flag emptied so everybody holds it) the choice is the change.
func _test_map_menu() -> void:
	section("M: the map menu on a server")
	var module: Node = _server.modules.get_module("tpl")
	var maps: DotMenuMaps = ((_client.get("settings") as DotMenuSettings).menu).maps
	check(maps != null and maps.is_online(), "M is wired, and connected it asks the server")
	maps.open()
	check(await _until(func() -> bool: return maps.last_offer.has("maps")), "the server answers with its arenas")
	var offer := maps.last_offer
	check(not bool(offer.get("allowed", true)) and str(offer.get("flag", "")) == "generic" and bool(offer.get("vote", false))
		and (offer["maps"] as Array).size() == 3,
		"a player who is not staff gets the list as a vote, by sv_map_menu_flag's default (%s)" % str(maps.describe()["offer"]))

	# Rocking the vote waits two minutes into an arena by default; this suite has not got them.
	(module.get("director") as DotVoteDirector).rules.rtv_delay_sec = 0.0
	maps.call(&"_chosen", &"pocket")
	check(await _until(func() -> bool: return "Nominated" in maps.last_said), "choosing one nominates it and rocks the vote (%s)" % maps.last_said)
	check(await _until(func() -> bool: return (module.get("director") as DotVoteDirector).is_voting()), "and a ballot opens")
	# The ballot is in chat: "Type !vote and a number: 1. Pocket ...". Nominated, Pocket is first.
	_link.send_chat("!vote 1")
	var game: Node = _client.get("game")
	check(await _until(func() -> bool: return _server_game().get("arena")["id"] == &"pocket" and game.get("arena")["id"] == &"pocket"),
		"the vote's winner is played: the server and the client are on Pocket")
	check(await _until(func() -> bool: return (game.get("coins") as Array).size() == 5 and _client_player().position.x < 760.0),
		"with Pocket's coins, and the player inside its walls")

	_server.console.find_cvar("sv_map_menu_flag").force_set("")
	maps.last_offer = {}
	maps.open()
	check(await _until(func() -> bool: return bool(maps.last_offer.get("allowed", false))), "with sv_map_menu_flag emptied, anybody may change it")
	maps.call(&"_chosen", &"gold_rush")
	check(await _until(func() -> bool: return game.get("arena")["id"] == &"gold_rush" and (game.get("coins") as Array).size() == 24),
		"and the choice is the change, for everybody (%s)" % maps.last_said)
	_server.console.find_cvar("sv_map_menu_flag").force_set("generic")
	maps.menu.close_all()
	done()


## Your own player is drawn between its ticks at the clock's render alpha, and a physics frame
## the clock's drift leaves with no tick, or with two, is drawn through.
##
## The connected client hands its view its clock. The motion itself is measured on a clock of
## its own, which nothing steers: over a socket the clock's drift makes slips of its own at
## moments nobody chooses, and two in a row are more than render_alpha takes back by design.
## Frames are drawn a third of the way through their tick, with one no-tick and one two-tick
## frame forced, beside a control drawn at that third alone (the engine's fraction, how it would
## be drawn without the clock). A frame that moves under half the steady step is a stall; over
## one and a half, a double.
func _test_drawn_through_a_slip() -> void:
	section("your own player is drawn through a frame with no tick, or two")
	var net: DotNetManager = _client.get("net")
	var view: Node = _client.get("view")
	await get_tree().process_frame
	check(view.get("render_clock") == net.clock and is_equal_approx(float(view.call(&"frame_alpha")), net.clock.render_alpha()),
		"the connected client's view draws at its netcode clock's render alpha")

	var clock := DotNetClock.new(60)
	var dt := clock.tick_duration()
	var game := TplGame.new()
	add_child(game)
	var me: TplGame.Player = game.add_player(1, "Ada")
	me.position = Vector2(100.0, 300.0)
	me.intent = Vector2.RIGHT
	var drawn: Array[Vector2] = []
	var control: Array[Vector2] = []
	var frame := func(delta: float) -> void:
		for _i in range(clock.advance(delta)):
			game.move(me, dt)
		drawn.append(me.drawn_position(clock.render_alpha(0.33, dt)))
		control.append(me.drawn_position(0.33))
	for _i in range(6):
		frame.call(dt)
	frame.call(0.0)
	for _i in range(6):
		frame.call(dt)
	clock.set(&"_accumulator", float(clock.get(&"_accumulator")) + dt)
	frame.call(dt)
	for _i in range(6):
		frame.call(dt)
	game.queue_free()

	var judge := func(points: Array[Vector2]) -> Array:
		var steps: Array[float] = []
		for i in range(1, points.size()):
			steps.append(points[i].distance_to(points[i - 1]))
		var sorted := steps.duplicate()
		sorted.sort()
		var steady: float = sorted[sorted.size() / 2]
		var stalled := 0
		var doubled := 0
		for s in steps:
			if s < steady * 0.5:
				stalled += 1
			elif s > steady * 1.5:
				doubled += 1
		return [stalled, doubled, steady]

	var on_clock: Array = judge.call(drawn)
	var alone: Array = judge.call(control)
	check(int(alone[0]) >= 1 and int(alone[1]) >= 1,
		"the control (a fraction alone) stalls on the frame with no tick and doubles on the one with two (%d, %d)" % [alone[0], alone[1]])
	check(int(on_clock[0]) == 0 and int(on_clock[1]) == 0,
		"drawn at the clock's render alpha, no frame stalls or doubles (%d, %d; steady %.2f units a frame)" % [on_clock[0], on_clock[1], on_clock[2]])
	done()


## Whether any row of the chat box's history has [param text] in it.
func _shown(chat: DotChatWindow, text: String) -> bool:
	for row: Variant in chat.history():
		for part: Variant in row:
			if text in str((part as Dictionary).get("text", "")):
				return true
	return false


func _test_leaving() -> void:
	section("leaving")
	_link.disconnect_from_server("bye")
	var gone := await _until(func() -> bool: return _server_game().players.is_empty())
	check(gone, "the server takes the player out of the game")
	_link = null
	done()


## Inputs go unreliable, so every packet carries the last few commands
## (TplBridge.INPUT_COPIES). A socket on localhost never loses one, so this section puts a
## second bridge pair side by side with no socket at all, carries the client's packets to the
## server by hand, and drops one. That tick's command must still reach the server, from the
## copies in the next packet. Then the copies of ticks the server has already simulated must be
## skipped rather than pushed, which would count every one of them as a late input.
func _test_a_lost_input() -> void:
	section("a lost input packet is made up by the next one")
	var server_bridge := _bridge_pair_half(true)
	var client_bridge := _bridge_pair_half(false)
	var sent: Array = (client_bridge.link as RecordingLink).sent
	server_bridge.add_player(CLIENT_PEER, 1, "Ada")
	server_bridge.net.add_peer(CLIENT_PEER)
	var buffer: DotNetInput.Buffer = server_bridge.net.input_buffer_for(CLIENT_PEER)
	var lost_tick := 10
	var held: DotNetInput = null

	# The client runs two ticks ahead of the server, as its clock does.
	for tick in range(1, 40):
		server_bridge.server_tick(tick)
		var input := tick + 2
		client_bridge.client_tick(input, Vector2.UP if input == lost_tick else Vector2.RIGHT)
		var payload: PackedByteArray = sent.pop_back()
		if input != lost_tick:
			server_bridge.receive_input(CLIENT_PEER, payload)
		if input == lost_tick + 1:
			held = buffer.peek(lost_tick)
		if input == lost_tick + 5:
			check(buffer.late_count == 0 and buffer.duplicate_count > 0,
				"copies of ticks already buffered are duplicates, not late (%d duplicates)" % buffer.duplicate_count)

	# Within the wire's precision: eight bits an axis, and zero is not on that grid.
	var recovered := held != null and (held.get("move") as Vector2).distance_to(Vector2.UP) < 0.01
	check(recovered and buffer.late_count == 0,
		"the lost tick's command arrives in the next packet, and the copies add no late input (%d late)" % buffer.late_count)
	for bridge: TplBridge in [server_bridge, client_bridge]:
		bridge.link.free()
		bridge.get_parent().queue_free()
	done()


## A link that keeps what it would send instead of sending it.
class RecordingLink extends "res://game/net/tpl_link.gd":
	var sent: Array = []

	func send_input(payload: PackedByteArray) -> void:
		sent.append(payload)


## One end of a socketless pair: a game, a manager scoped apart from the dedicated server's,
## and a bridge whose link records instead of sending.
func _bridge_pair_half(is_server: bool) -> TplBridge:
	var side := Node.new()
	side.name = "LostInputServer" if is_server else "LostInputClient"
	add_child(side)
	var game := TplGame.new()
	game.authoritative = is_server
	side.add_child(game)
	var net := DotNetManager.new()
	net.is_server = is_server
	net.local_peer_id = 1 if is_server else CLIENT_PEER
	net.auto_tick = false
	net.config_file = ""
	net.service_scope = side.name
	net.config = TplBridge.net_config(60)
	side.add_child(net)
	var _setup := net.setup()
	var bridge := TplBridge.new()
	side.add_child(bridge)
	var _attached := bridge.attach(game, net)
	net.messages.seal()
	# Out of the tree on purpose: a link outside the tree sends nothing, so the snapshots and
	# events this pair would send go nowhere, and only the inputs are recorded.
	bridge.link = RecordingLink.new()
	var _started := net.start()
	return bridge


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
