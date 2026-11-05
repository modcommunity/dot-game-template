extends Node

## Renders the client as a phone shows it (touch on, 844x390), for phone_shot.sh (never --headless).
## DotGameClient attaches DotGameScreenFit on its own; this only says a finger can reach the screen.


func _ready() -> void:
	DotPlatform.touch_override = 1
	var client: Node = load("res://scenes/tpl_client.tscn").instantiate()
	add_child(client)
	await get_tree().create_timer(4.0).timeout
	var win := get_tree().root
	print("window ", win.size, " canvas ", win.content_scale_size, " aspect ", win.content_scale_aspect)
	var err := win.get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
	print("saved ", err)
	get_tree().quit()
