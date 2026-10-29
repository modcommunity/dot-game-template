extends Node

## A headless dedicated Coin Grab for tools/render_cover.gd to join, left running:
## `godot --headless --path . res://tools/cover_server.tscn -- --port 27399`. The root is named
## CoverServer, like render_cover's, so the RPC path to "Server" is the same on both sides.

var server: DotServer = null


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var i := args.find(name)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback


func _run() -> void:
	var dir := ProjectSettings.globalize_path("user://cover_server")
	DotPaths.remove_tree(dir)
	DirAccess.make_dir_recursive_absolute(dir)

	var config := DotServerConfig.new()
	config.autoexec_config = ""
	config.hostname = "cover test"
	config.hibernate_when_empty = false
	config.rcon_password = ""
	config.query_enabled = false
	config.port = int(_arg("--port", "27399"))
	config.admins_path = "%s/admins.json" % dir
	config.bans_path = "%s/bans.json" % dir
	config.audit_log_path = "%s/audit.jsonl" % dir
	config.stdin_console_enabled = false

	server = DotServer.new()
	server.name = "Server"
	server.config = config
	add_child(server)
	for _i in 60:
		await get_tree().process_frame
		if server.state == DotServer.State.RUNNING:
			break

	var module_path := "res://game/tpl_module.gd"
	var descriptor: DotGameDescriptor = (load(module_path) as GDScript).call("game_descriptor")
	server.games.add_game(descriptor)
	var changed: DotResult = await server.games.change_game(descriptor.game_id, "boot")
	var loaded: DotResult = await server.modules.load_module(module_path)
	print("cover_server: game=%s module=%s port=%d" % [changed.ok, loaded.ok, config.port])
