extends Node

const TplGame := preload("tpl_game.gd")

## What a dedicated server loads as this game's scene. Never a client.
##
## Small on purpose: the world has to be in the tree, registered under
## [constant TplGame.SERVICE], before the module looks for it -- dot-server loads the scene and
## then the module, in that order, for exactly this reason. Everything else is the module's.


func _ready() -> void:
	var game := TplGame.new()
	game.name = "World"
	game.authoritative = true
	game.register_service = true
	# Layered config; strict on a dedicated server, so a typo in cfg/ stops the boot.
	var binder := DotGameConfigBinder.create(game.config, "tpl", "tpl", "user://cfg/tpl.json")
	var loaded := binder.load_layers()
	if not loaded.ok:
		DotGameConfigBinder.fail_boot(get_tree(), loaded)
		return
	game.config_binder = binder
	add_child(game)
	game.start()
