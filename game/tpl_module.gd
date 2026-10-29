extends DotGameModule

const TplArenas := preload("tpl_arenas.gd")
const TplBridge := preload("net/tpl_bridge.gd")
const TplGame := preload("tpl_game.gd")
const TplPaths := preload("tpl_paths.gd")

## This game, as a module a dedicated server loads (`module:` in game.yml).
## What every server game repeats is [DotGameModule]'s; what is left is this game's.
## No `class_name`: a delivered pack's class names are never registered in the host.

## The players' say over the arena: dot-vote's director, whose commands include the map
## menu's server half. See [method _build_map_menu].
var director: DotVoteDirector = null
var vote_commands: DotVoteCommands = null

## Connected to the server, which outlives this module, so it is let go in [method _game_unload].
var _on_left: Callable = Callable()


## For a server that has this game in its own project rather than in a pack: the suites, and a
## server run straight from this repository. A deployed server reads game.yml instead.
static func game_descriptor() -> DotGameDescriptor:
	var descriptor := DotGameDescriptor.new()
	descriptor.game_id = "tpl"
	descriptor.display_name = "Coin Grab"
	descriptor.scene = TplPaths.rebase("res://scenes/tpl_server.tscn")
	return descriptor


func _module_name() -> String:
	return "tpl"


func _game_service() -> StringName:
	return TplGame.SERVICE


## The engine's physics rate, which the server has already set from `sv_tickrate`: the
## module's tick is driven by the physics frame, so any other number would be a netcode
## counting time at one rate inside a process ticking at another.
func _net_config() -> DotNetConfig:
	return TplBridge.net_config(Engine.physics_ticks_per_second)


func _make_bridge() -> Node:
	return TplBridge.new()


func _game_load() -> DotResult:
	var binder := (game as TplGame).config_binder
	if binder != null:
		binder.bind_cvars(add_cvar, DotConVar.FLAG_ARCHIVE, console.has_name)
		binder.bind_commands(add_command)
	add_command("tpl_status", _cmd_status, "Show the players, their scores and the coins")
	_build_map_menu()
	# "Still loading": a player behind their client's cover collects nothing (TplGame.collect).
	# The player id is the session's userid, which is the roster's seat.
	(game as TplGame).harm_gate = can_be_harmed
	return DotResult.success(null)


## M on a server: dot-vote's map menu, over a vote of the arenas.
## [b]Who may change the arena is `sv_map_menu_flag`[/b] (`generic` staff by default, `changemap`, `anyone`; `sv_map_menu_alone`
## for a lone player); anybody else nominates and rocks the vote (`!rtv`, `!vote 2`). The client half is [method DotMenu.use_maps].
func _build_map_menu() -> void:
	var world := game as TplGame
	var source := DotVoteListSource.new()
	source.label = "arenas"
	# LIST and not TplArenas.rows(): a server never follows the Workshop (tpl_workshop.gd), and
	# an arena id is the wire, so a ballot may only name arenas every client has.
	for arena: Dictionary in TplArenas.LIST:
		var choice := DotVoteChoice.of(arena["id"], arena["name"])
		choice.description = arena["about"]
		var _added := source.add(choice)
	source.current = world.arena["id"]
	source.apply_fn = world.change_arena

	var rules := DotVoteRules.new()
	rules.trigger = DotVoteRules.Trigger.RTV_ONLY
	rules.duration_sec = 0.0
	rules.apply = DotVoteRules.Apply.IMMEDIATE
	rules.rtv_apply = DotVoteRules.Apply.IMMEDIATE
	# The ballot's "Don't change" already stands for the arena being played.
	rules.include_current = false
	rules.include_extend = false
	rules.cooldown = 0
	rules.vote_duration_sec = 20.0

	director = DotVoteDirector.new()
	director.name = "ArenaVote"
	director.rules = rules
	director.source = source
	# The arena_changed signal below calls begin() for every change, the menu's and the vote's
	# alike, so the director must not call it a second time for its own.
	director.begin_on_apply = false
	director.player_count_fn = func() -> int: return server.playing_sessions().size()
	# What the vote says goes to everybody's chat box as the server's own line.
	director.announce_fn = func(line: String) -> void: server.broadcast_message(line)
	# A voter is `u<userid>` (dot-vote's commands' spelling); the lines name them properly.
	director.people_fn = func(voter: StringName) -> Dictionary:
		var session := server.session_by_userid(String(voter).trim_prefix("u").to_int())
		return {"name": session.display_name} if session != null else {}
	add_child(director)
	# How to vote, when a ballot opens: the chat box is this game's only ballot.
	director.vote_opened.connect(func(options: Array, _seconds: float) -> void:
		var numbered := PackedStringArray()
		for i in range(options.size()):
			numbered.append("%d. %s" % [i + 1, director.option_label(StringName(str(options[i])))])
		server.broadcast_message("Type !vote and a number: %s" % "   ".join(numbered)))

	vote_commands = DotVoteCommands.new()
	vote_commands.director = director
	# `!vote 2` rather than dot-vote's default `!votefor 2`: nothing else here is called vote.
	vote_commands.names = {"vote": "vote"}
	var _bound := vote_commands.bind(self)
	# The menu changes the arena now, through the same function a vote's winner goes through.
	vote_commands.map_menu.change_fn = world.change_arena
	vote_commands.map_menu.rows_fn = func(_rows: Array) -> Array: return TplArenas.rows(world.arena["id"])

	director.begin(world.arena["id"])
	var _reported := report_map(String(world.arena["id"]))
	world.arena_changed.connect(func(id: StringName) -> void:
		source.current = id
		director.begin(id)
		var _told := report_map(String(id)))
	# A player who leaves takes their rock-the-vote with them. dot-vote's commands name a voter
	# `u<userid>`.
	_on_left = func(session: DotClientSession, _reason: String) -> void:
		director.forget_voter(StringName("u%d" % session.userid))
	server.client_disconnected.connect(_on_left)


func _game_unload() -> void:
	if game != null:
		(game as TplGame).harm_gate = Callable()
	if _on_left.is_valid() and server.client_disconnected.is_connected(_on_left):
		server.client_disconnected.disconnect(_on_left)


## The vote's clock, on the server's tick.
func _game_tick(_tick: int, delta: float) -> void:
	if director != null:
		director.advance(delta)


## This game's column on the Tab board. dot-server already sends every player's name, ping
## and time connected; this adds the one thing only the game knows, per player.
func _game_board_fields(session: Object) -> Dictionary:
	var who: TplGame.Player = (game as TplGame).player(int(session.get("userid"))) if game != null else null
	return {"coins": who.score} if who != null else {}


func _cmd_status(ctx: DotCmdContext) -> void:
	ctx.reply_lines((game as TplGame).describe_lines())
	ctx.reply_lines((bridge as TplBridge).describe_lines())
