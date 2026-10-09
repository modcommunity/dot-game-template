extends DotGameModule

const TplBridge := preload("net/tpl_bridge.gd")
const TplGame := preload("tpl_game.gd")
const TplPaths := preload("tpl_paths.gd")

## This game, as a module a dedicated server loads (`module:` in game.yml).
##
## [b]What every server game repeats is [DotGameModule]'s, not this file's.[/b] It finds the
## world the server scene registered, builds the netcode from [method _net_config] and the
## bridge from [method _make_bridge], seats each player through the bridge's `add_player` when
## they finish joining, calls the bridge's `server_tick` every physics frame, and takes it all
## down in reverse on unload. What is left here is what is this game's.
##
## No `class_name`, here or anywhere in this repository: a delivered pack's class names are
## never registered in the host, so a script that used one would not compile there.


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
	add_command("tpl_status", _cmd_status, "Show the players, their scores and the coins")
	return DotResult.success(null)


## This game's column on the Tab board. dot-server already sends every player's name, ping
## and time connected; this adds the one thing only the game knows, per player.
func _game_board_fields(session: Object) -> Dictionary:
	var who: TplGame.Player = (game as TplGame).player(int(session.get("userid"))) if game != null else null
	return {"coins": who.score} if who != null else {}


func _cmd_status(ctx: DotCmdContext) -> void:
	ctx.reply_lines((game as TplGame).describe_lines())
	ctx.reply_lines((bridge as TplBridge).describe_lines())
