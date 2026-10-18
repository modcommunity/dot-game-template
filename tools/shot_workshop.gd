extends Node

## Renders a solo pack map with the M menu open, for ~/tools/screenshot.sh (never --headless: that draws nothing):
##
##     screenshot.sh dot-game-template out.png --wait 6 --scene res://tools/shot_workshop.tscn
##
## A fixture pack stands in for the Workshop's: one document registered in the shared index as
## solo before the client starts, so the client follows it exactly as a subscription would.

const DIR := "user://ws_shot/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(DIR + "bunker.json", FileAccess.WRITE)
	f.store_string('{"id": "bunker", "name": "Bunker", "size": [900, 500], "coins": 12, "floor": [0.30, 0.12, 0.12]}')
	f.close()
	var index := DotContentIndex.shared()
	index.set_session(DotContentIndex.SESSION_SOLO)
	var _added := index.add_pack({
		"content_id": "fixture/shot", "version": "1.0.0", "prefix": DIR,
		"session": DotContentIndex.SESSION_SOLO, "source": &"subscription",
		"provides": {"schema": 1, "title": "Fixture Pack", "kinds": ["map"], "entries": [
			{"kind": "map", "id": "bunker", "name": "Bunker", "scene": "bunker.json", "map_kind": "coin_arena"}]},
	})
	var client: Node = load("res://scenes/tpl_client.tscn").instantiate()
	add_child(client)
	await get_tree().create_timer(2.0).timeout
	print("pack map chosen: ", ((client.get("game") as Object).call("change_arena", &"bunker") as DotResult).ok)
	# And the M menu as a player sees it, listing the pack map next to the game's own.
	((client.get("settings") as Object).get("menu") as Object).call("open_maps")
