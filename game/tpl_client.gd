extends Node

const TplArenas := preload("tpl_arenas.gd")
const TplBridge := preload("net/tpl_bridge.gd")
const TplGame := preload("tpl_game.gd")
const TplView := preload("tpl_view.gd")

const CHANNEL := "tpl.client"

## What a player runs: `scenes/tpl_client.tscn`. Offline, or joined to a server.
##
## [b]Whether there is a link decides which.[/b] The client shell connects a [DotClientLink],
## which registers itself, and then loads this scene out of the pack the server named. Run the
## project on its own and there is no link, so it plays offline: the same rules, alone.
##
## [b]Keys are read directly, not through the input map:[/b] project.godot does not travel in
## a pack, so an action defined there does not exist in the shell that mounts this game.
##
## [b]The platform layer is dot-game's [DotGameClient][/b]: the loading cover, the settings
## and the Escape menu, the console, the HUD's theme, Tab for the board, M for the map menu,
## and input held while the cover is up, a menu is open or a chat line is being typed. What is
## left here is what is this game's own. See [method _ready].
##
## [b]Escape is the menu and Tab, held, is the scoreboard[/b], both dot-menu's: the stock
## window and frame-rate settings and six themes, and a board of every player's coins, time
## on the server and ping. See [method _build_menu].
##
## [b]M is the map menu[/b], dot-menu's: the arenas (tpl_arenas.gd). Solo the choice is the
## change, made here at once; connected the server decides: the menu asks it with
## `/mapmenu`, the server answers with its list and whether this player holds the permission
## its owner named (`sv_map_menu_flag`, staff by default), and changes the arena for
## everybody or, for anybody else, starts a vote for it (tpl_module.gd).
##
## [b]Y is chat[/b], dot-ui's chat box: what players say, and what the server says (a vote, an
## admin's `say`, the reply to a command). See [method _build_chat].

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

## dot-game's platform layer: the loading cover (its [code]gate[/code]), the menu, the
## console, the keys. See [method _ready].
var platform: DotGameClient = null

var _hud: Label = null
var _hud_root: Control = null

## The Escape menu and the settings behind it. See [method _build_menu].
var settings: DotMenuSettings = null

## The chat box. See [method _build_chat].
var chat: DotChatWindow = null
var _touching: bool = false
var _touch_at: Vector2 = Vector2.ZERO


func _ready() -> void:
	# First, before anything is drawn: the loading cover (dot-core's load gate, through
	# dot-game). Add your own holds on `platform.gate`: `gate.hold(&"map", "Loading")` now and
	# `gate.release(&"map")` when it is built. It also covers the first frames' shader
	# compiles. Nothing is held at first except the local player, asked every frame and met
	# at once offline. No Camera3D in a 2D game, so none to wait for.
	platform = DotGameClient.new()
	platform.link = link
	platform.require_camera = false
	platform.spawned_fn = func() -> bool: return game != null and game.player(local_id) != null
	# A 2D game played with a finger or a held mouse button: the pointer stays free.
	platform.capture_pointer = false
	add_child(platform)
	link = platform.link as DotClientLink
	var offline := platform.offline
	game = TplGame.new()
	game.authoritative = offline
	add_child(game)
	view = TplView.new()
	view.game = game
	add_child(view)
	var layer := CanvasLayer.new()
	add_child(layer)
	# The HUD's root: a full-rect Control under the layer, so the menu can theme and scale
	# everything on it at once (see [method _build_menu]).
	_hud_root = Control.new()
	_hud_root.name = "Hud"
	_hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud_root)
	_hud = Label.new()
	_hud.position = Vector2(16.0, 12.0)
	_hud.add_theme_font_size_override("font_size", 20)
	_hud_root.add_child(_hud)
	_build_menu()
	_build_chat(offline)
	# The settings, the menu, the console (the key under Escape), the HUD in the player's
	# theme and HUD size, Tab and M: dot-game's, from what was just built.
	platform.hud = _hud_root
	platform.chat = chat
	platform.board_snapshot_fn = board_snapshot
	platform.maps_rows_fn = func() -> Array: return TplArenas.rows(game.arena["id"])
	platform.maps_change_fn = func(id: StringName) -> DotResult: return game.change_arena(id)
	platform.maps_title = "Change arena"
	platform.maps_noun = "arenas"
	DotLog.result(CHANNEL, "the menu and the console", platform.setup())
	_dress_board()
	if offline:
		game.start()
		local_id = 1
		game.add_player(local_id, "You")
		view.local_id = local_id
	else:
		_join()


## Settings and the Escape menu, from dot-menu; [DotGameClient] sets them up.
##
## Only the stock settings this game has something to apply to: the window, V-Sync, the
## frame-rate cap, the theme and the frame-rate counter. A 2D game with no audio has no
## use for a field of view, a render scale, effects or volumes, and a switch that changes
## nothing is worse than no switch. Add the groups back as the game grows them.
func _build_menu() -> void:
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
	platform.settings = settings
	# Pass a Theme for your game's accent (dot-ui's DotHudPiece colours `highlight` and
	# `plate_edge`); null is the menu's theme alone.
	platform.hud_accent = null


## The Tab board's columns. Connected, the rows are the server's roster plus the coins the
## module adds; offline, [method board_snapshot].
func _dress_board() -> void:
	var board: DotMenuScoreboard = platform.board as DotMenuScoreboard
	if board == null:
		return
	board.title_text = "Coin Grab"
	board.columns = [
		{"key": &"name", "title": "Player", "width": 3.0},
		{"key": &"coins", "title": "Coins", "kind": DotMenuScoreboard.KIND_NUMBER},
		{"key": &"seconds", "title": "Time", "kind": DotMenuScoreboard.KIND_DURATION},
		{"key": &"ping", "title": "Ping", "kind": DotMenuScoreboard.KIND_PING},
	]
	board.sort_by = &"coins"


## The board offline, from this client's own world.
func board_snapshot() -> Dictionary:
	var rows: Array = []
	for who: TplGame.Player in game.players.values():
		rows.append({"id": who.id, "name": who.name, "coins": who.score, "you": who.id == local_id})
	return {"server": {"name": "Coin Grab", "game": "offline"}, "players": rows}


## The chat box: Y opens it, Enter sends, Escape closes.
##
## [b]This game routes no chat of its own, and does not need to.[/b] What a player types goes
## to dot-server's chat manager through the shell's link ([method DotClientLink.send_chat]),
## which checks it (rate, length, a gag), sends it to everybody, and runs a line starting
## with `!` or `/` as a command instead: `!rtv`, `!vote 2`, the map menu's `/mapmenu`. Every
## line comes back on [signal DotClientLink.chat_received], the sender's own included, so
## what you see is what the server accepted. A game whose chat needs channels of its own
## (teams, a radius) routes it through dot-game's `DotGameServices` instead.
##
## [b]`!sm` and `/sm` never leave this machine.[/b] They are the player's own block list
## (dot-chat's `DotChatSelfMute`), which the box runs before anything is sent, so the muted
## player is never told; the console's `sm` is the same list. Lines from a muted player are
## dropped in [method _on_chat_line].
func _build_chat(offline: bool) -> void:
	chat = DotChatWindow.new()
	chat.name = "Chat"
	# No teams here, so no team-chat key (dot-ui's default is U).
	chat.team_action = &""
	chat.channels = [{"id": &"all", "label": "Say", "colour": Color(0.88, 0.90, 0.94)}]
	# Under the HUD's root, so the menu's theme and HUD size reach it too.
	_hud_root.add_child(chat)
	chat.submitted.connect(_on_chat_submitted)
	# The block list, made now rather than at the first `!sm`: it is what asks the server who
	# is here, so it knows whose lines to drop before the first one arrives.
	var _mutes := DotChatSelfMute.shared()
	if not offline and link != null:
		link.chat_received.connect(_on_chat_line)


## The player pressed Enter on a line. Offline there is nobody to send it to, so it is shown.
func _on_chat_submitted(text: String, _channel: StringName) -> void:
	if net == null:
		chat.add_said("You", text, TplGame.colour_of(local_id))
		return
	link.send_chat(text)


## One line from the server: `{kind, name, text}`, and `userid` on what a player said.
func _on_chat_line(payload: Dictionary) -> void:
	# The server's own lines (`system`: votes, joins, `say`; `admin`), drawn as every game in
	# the family draws them.
	if DotGameChatClient.draw_server_line(chat, payload):
		return
	var kind := str(payload.get("kind", ""))
	# `state` is not a line: it says whether something else carries this conversation.
	if kind != "all" and kind != "team":
		return
	var speaker := str(payload.get("name", ""))
	var userid := int(payload.get("userid", 0))
	# Matched by the userid as well as the name, so a renamed player stays muted.
	if DotChatSelfMute.shared().is_muted(speaker, str(userid)):
		return
	# The speaker in their disc's colour: a player id here is their userid.
	chat.add_said(speaker, str(payload.get("text", "")), TplGame.colour_of(userid))


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
	# Your own player is drawn between its ticks at the clock's render alpha (see
	# TplView.frame_alpha). Offline there is no clock, and the engine's fraction is exact.
	view.render_clock = net.clock if net != null else null
	var lines := PackedStringArray()
	for who: TplGame.Player in game.players.values():
		lines.append("%s%s  %d" % ["> " if who.id == local_id else "  ", who.name, who.score])
	if net == null:
		lines.append("\nWASD, arrows or touch to move. Tab: scores. M: arenas. Y: chat. Esc: menu")
	_hud.text = "\n".join(lines) if not lines.is_empty() else "Joining..."


## Where the player wants to go, length 0..1: keys, or a finger (or a held mouse button).
func _intent() -> Vector2:
	# Typing is not steering (keys are polled, and a focused chat line does not stop that:
	# typing "sad" walked the player down and left), nor is a menu, nor is the cover up.
	if platform.is_input_blocked():
		return Vector2.ZERO
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
