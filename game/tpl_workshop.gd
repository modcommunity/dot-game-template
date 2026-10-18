extends RefCounted

const TplArenas := preload("tpl_arenas.gd")
const TplGame := preload("tpl_game.gd")

const CHANNEL := "tpl.workshop"

## Subscribed map packs in SOLO play: the reference wiring a developer copies.
##
## [b]A pack's `map` entry names a JSON document in `scene`[/b], because this game's maps are
## rows of numbers (tpl_arenas.gd), not scenes. The document is one arena:
## [codeblock]
## {"id": "bunker", "name": "Bunker", "about": "Optional line for the menu.",
##  "size": [900, 500], "coins": 12, "floor": [0.2, 0.1, 0.1]}
## [/codeblock]
## `id` must equal the entry's id; `floor` is optional. The pack's entry says
## `"map_kind": "coin_arena"`, the one kind [method accepted] lists and provides.json repeats.
## A game whose maps are scenes loads `map.scene_path` instead and needs no document.
##
## [b]Online lists none[/b]: only the solo client calls [method follow], and it fills
## [member TplArenas.workshop], which a server never does. Arena ids are the wire online, and a
## player's pack is not on the server, so the vote and the server's M list stay the game's own.

## The map kinds this game takes: provides.json's `accepts.map_kinds`, which a test compares.
static func accepted() -> PackedStringArray:
	return PackedStringArray(["coin_arena"])

## Entry id -> why it was refused.
var refused: Dictionary = {}

var catalogue: DotMapCatalogue = null


## Follows [param index] (the process's shared one by default); the catalogue keeps itself
## current as packs mount and the session changes.
func follow(index: DotContentIndex = null) -> void:
	catalogue = DotMapCatalogue.new()
	catalogue.follow_content(index if index != null else DotContentIndex.shared(), accepted())
	refresh()


## Re-reads the index and replaces the registered arenas with what is visible now.
func refresh() -> void:
	TplArenas.workshop.clear()
	if catalogue == null:
		return
	catalogue.refresh_content()
	for map in catalogue.maps:
		# Own ids win; a pack_title is what tells a pack's map from one added by hand.
		if map.pack_title == "" or not TplArenas.find(map.id).is_empty():
			continue
		var arena := _read(map)
		if not arena.is_empty():
			TplArenas.workshop[map.id] = arena


func _read(map: DotMapDef) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(map.scene_path)) if map.scene_path != "" else null
	var why := ""
	var arena := {}
	if not (parsed is Dictionary):
		why = "The map document is empty or not JSON: %s" % map.scene_path
	else:
		var doc := parsed as Dictionary
		var size: Variant = doc.get("size", null)
		var floor_color: Variant = doc.get("floor", [0.12, 0.14, 0.18])
		if str(doc.get("id", "")) != String(map.id):
			why = "The entry's id is %s but its document's id is %s." % [map.id, doc.get("id", "")]
		elif not (size is Array) or (size as Array).size() != 2 \
				or float((size as Array)[0]) < 200.0 or float((size as Array)[1]) < 200.0 \
				or float((size as Array)[0]) > TplGame.ARENA.x or float((size as Array)[1]) > TplGame.ARENA.y:
			why = "size must be [width, height], 200 up to %dx%d." % [TplGame.ARENA.x, TplGame.ARENA.y]
		elif int(doc.get("coins", 0)) < 1 or int(doc.get("coins", 0)) > 255:
			why = "coins must be 1 to 255."
		elif not (floor_color is Array) or (floor_color as Array).size() != 3:
			why = "floor must be [r, g, b], each 0 to 1."
		else:
			var c := floor_color as Array
			arena = {"id": map.id, "name": map.label(), "size": Vector2(float((size as Array)[0]), float((size as Array)[1])),
				"coins": int(doc["coins"]), "floor": Color(float(c[0]), float(c[1]), float(c[2])),
				"about": str(doc.get("about", "A subscribed map."))}
	if why != "":
		refused[String(map.id)] = why
		DotLog.warn(CHANNEL, "a subscribed map was refused", {"id": String(map.id), "why": why})
	return arena
