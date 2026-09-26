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
	add_child(game)
	game.start()
