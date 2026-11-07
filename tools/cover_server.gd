extends DotCoverServer

## A headless dedicated Coin Grab for tools/render_cover.gd to join, left running:
## `godot --headless --path . res://tools/cover_server.tscn -- --port 27399`. The boot is
## DotCoverServer's; this is the game's half.


func _boot(_dir: String) -> void:
	await boot_descriptor_module("res://game/tpl_module.gd")
