extends Node

const TplBridge := preload("net/tpl_bridge.gd")
const TplGame := preload("tpl_game.gd")
const TplView := preload("tpl_view.gd")

## What a player runs: `scenes/tpl_client.tscn`. Offline, or joined to a server.
##
## [b]Whether there is a link decides which.[/b] The client shell connects a [DotClientLink],
## which registers itself, and then loads this scene out of the pack the server named. Run the
## project on its own and there is no link, so it plays offline: the same rules, alone.
##
## [b]Keys are read directly, not through the input map:[/b] project.godot does not travel in
## a pack, so an action defined there does not exist in the shell that mounts this game.
##
## [b]Escape is the menu and Tab, held, is the scoreboard[/b], both dot-menu's: the stock
## window and frame-rate settings and six themes, and a board of every player's coins, time
## on the server and ping. See [method _build_menu].

## The shell's link, when the shell sets it; otherwise found in the registry.
var link: DotClientLink = null

## When valid, steers instead of the keyboard: `func() -> Vector2`. How the suites drive a
## real client, and how a bot would.
var steer: Callable = Callable()

var game: TplGame = null
var view: TplView = null
var bridge: TplBridge = null
var net: DotNetManager = null

## Which player is this client's. Offline it is always 1.
var local_id: int = 0

var _hud: Label = null

## The Escape menu and the settings behind it. See [method _build_menu].
var settings: DotMenuSettings = null
var _touching: bool = false
var _touch_at: Vector2 = Vector2.ZERO


func _ready() -> void:
	if link == null:
		link = DotRegistry.get_node_service(DotClientLink.SERVICE) as DotClientLink
	var offline := link == null or OS.get_cmdline_user_args().has("--offline")
	game = TplGame.new()
	game.authoritative = offline
	add_child(game)
	view = TplView.new()
	view.game = game
	add_child(view)
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16.0, 12.0)
	_hud.add_theme_font_size_override("font_size", 20)
	layer.add_child(_hud)
	_build_menu(offline)
	if offline:
		game.start()
		local_id = 1
		game.add_player(local_id, "You")
		view.local_id = local_id
	else:
		_join()


## Settings, the Escape menu and the Tab board, from dot-menu.
##
## Only the stock settings this game has something to apply to: the window, V-Sync, the
## frame-rate cap, the theme and the frame-rate counter. A 2D game with no audio has no
## use for a field of view, a render scale, effects or volumes, and a switch that changes
## nothing is worse than no switch. Add the groups back as the game grows them.
func _build_menu(offline: bool) -> void:
	settings = DotMenuSettings.new()
	settings.name = "Settings"
	settings.directory = "user://tpl_settings"
	settings.app_namespace = &"tpl"
	settings.schema = DotMenuStock.declare(DotSettingsSchema.new(),
		[DotMenuStock.GROUP_VIDEO, DotMenuStock.GROUP_INTERFACE] as Array[StringName], null,
		[&"field_of_view", &"render_scale", &"fx_quality"] as Array[StringName])
	settings.config = DotMenuConfig.new()
	settings.config.brand_name = "Coin Grab"
	settings.config.show_help = false
	settings.config.show_leave = false
	add_child(settings)
	if not settings.setup().ok or settings.menu == null:
		return

	var board := settings.menu.scoreboard
	board.title_text = "Coin Grab"
	board.columns = [
		{"key": &"name", "title": "Player", "width": 3.0},
		{"key": &"coins", "title": "Coins", "kind": DotMenuScoreboard.KIND_NUMBER},
		{"key": &"seconds", "title": "Time", "kind": DotMenuScoreboard.KIND_DURATION},
		{"key": &"ping", "title": "Ping", "kind": DotMenuScoreboard.KIND_PING},
	]
	board.sort_by = &"coins"
	if not offline and link != null:
		# The server's roster: names, pings, time connected, and the coins the module adds.
		board.feed_from(link)
	else:
		board.source = func() -> Dictionary:
			var rows: Array = []
			for who: TplGame.Player in game.players.values():
				rows.append({"id": who.id, "name": who.name, "coins": who.score, "you": who.id == local_id})
			return {"server": {"name": "Coin Grab", "game": "offline"}, "players": rows}


## Builds this end's netcode and tells the server we are here.
func _join() -> void:
	net = DotNetManager.new()
	net.name = "Net"
	net.is_server = false
	# Its own registry name, so a server and a client in one process do not replace each other.
	net.service_scope = &"client"
	net.local_peer_id = multiplayer.get_unique_id()
	# The game drives the ticks (see _physics_process), and reads no config file: a stale
	# user://dot_net.json would otherwise choose this game's tick rate for it.
	net.auto_tick = false
	net.config_file = ""
	# A placeholder rate. The server's arrives in the hello and replaces it.
	net.config = TplBridge.net_config(60)
	add_child(net)
	if not net.setup().ok:
		return
	bridge = TplBridge.new()
	add_child(bridge)
	bridge.attach(game, net)
	# Under the link, which is named `Server` like the server's node: the name is the routing.
	bridge.open_link(link)
	net.messages.seal()
	net.start()
	bridge.rtt_source = func() -> float: return float(maxi(0, link.ping_ms()))
	bridge.hello_received.connect(func(player_id: int) -> void:
		local_id = player_id
		view.local_id = player_id
	)

	# Not one byte before the join has finished: the server builds nothing for us until then.
	if link.is_playing():
		bridge.ask_ready()
	else:
		link.spawned.connect(bridge.ask_ready, CONNECT_ONE_SHOT)


func _physics_process(delta: float) -> void:
	var intent := _intent()
	if net == null:
		var me: TplGame.Player = game.player(local_id)
		if me != null:
			me.intent = intent
		game.tick(delta)
		return

	# The clock decides how many ticks this frame is worth, and which tick an input is for:
	# a little AHEAD of the server, so it arrives before the server simulates that tick.
	#
	# Each pass is its own tick: `advance` has already moved the clock by all of them, so
	# `input_tick()` is the last one, and the passes before it count back from there.
	var ticks := net.clock.advance(delta)
	for i in range(ticks):
		if net.clock.is_synced() and local_id != 0:
			bridge.client_tick(net.clock.input_tick() - (ticks - 1 - i), intent)


func _process(_delta: float) -> void:
	if net != null:
		# Every frame: this is what turns twenty snapshots a second into smooth motion.
		net.interpolate_frame()
	var lines := PackedStringArray()
	for who: TplGame.Player in game.players.values():
		lines.append("%s%s  %d" % ["> " if who.id == local_id else "  ", who.name, who.score])
	if net == null:
		lines.append("\nWASD, arrows or touch to move. Tab: scores. Esc: menu")
	_hud.text = "\n".join(lines) if not lines.is_empty() else "Joining..."


## Where the player wants to go, length 0..1: keys, or a finger (or a held mouse button).
func _intent() -> Vector2:
	if steer.is_valid():
		return steer.call()
	var keys := Vector2(_held(KEY_D, KEY_RIGHT) - _held(KEY_A, KEY_LEFT), _held(KEY_S, KEY_DOWN) - _held(KEY_W, KEY_UP))
	if keys != Vector2.ZERO:
		return keys.normalized()
	var me: TplGame.Player = game.player(local_id)
	if _touching and me != null:
		var toward := view.to_arena(_touch_at) - me.position
		if toward.length() > TplGame.PLAYER_RADIUS * 0.5:
			return toward.normalized()
	return Vector2.ZERO


func _held(key: Key, other: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(key) or Input.is_physical_key_pressed(other) else 0.0


func _unhandled_input(event: InputEvent) -> void:
	# Tab, held: the scoreboard, up while the key is down.
	var key := event as InputEventKey
	if key != null and key.physical_keycode == KEY_TAB and not key.echo and settings != null and settings.menu != null:
		if key.pressed:
			settings.menu.scoreboard.open()
		else:
			settings.menu.scoreboard.close()
		return
	if event is InputEventScreenTouch:
		_touching = (event as InputEventScreenTouch).pressed
		_touch_at = (event as InputEventScreenTouch).position
	elif event is InputEventScreenDrag:
		_touch_at = (event as InputEventScreenDrag).position
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_touching = (event as InputEventMouseButton).pressed
		_touch_at = (event as InputEventMouseButton).position
	elif event is InputEventMouseMotion and _touching:
		_touch_at = (event as InputEventMouseMotion).position
