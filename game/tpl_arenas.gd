extends RefCounted

## The arenas: this game's maps, as data. M lists them, and choosing one changes it.
##
## [b]A map here is a row of numbers, not a scene.[/b] Coin Grab's arena is a rectangle with
## coins in it, so an arena is how big the rectangle is, how many coins lie in it and what
## colour its floor is. Add a row and it is in the M menu, solo and on a server, with nothing
## else to change. A game whose maps are levels with walls in them keeps a scene per map
## instead, and dot-map's catalogue is the way to list those.
##
## Every arena fits inside [constant TplGame.ARENA], which is also the range positions are
## sent in: a bigger one would need the wire's ranges widened with it.
##
## [b]The ids are the wire.[/b] The server names the arena it changed to by id, so rename one
## only together with everybody's client, which in a pack is always the case: a server and its
## players mount the same version.

## `id`: what the server and the menu call it. `name`: what a player reads. `size`: in world
## units, at most TplGame.ARENA. `coins`: how many lie in it at once (at most 255). `floor`:
## its colour. `about`: the line under its name in the menu.
const LIST: Array[Dictionary] = [
	{"id": &"classic", "name": "Classic", "size": Vector2(1280.0, 720.0), "coins": 8,
		"floor": Color(0.11, 0.13, 0.18), "about": "The whole screen, eight coins"},
	{"id": &"pocket", "name": "Pocket", "size": Vector2(760.0, 480.0), "coins": 5,
		"floor": Color(0.16, 0.12, 0.17), "about": "Small and crowded, five coins"},
	{"id": &"gold_rush", "name": "Gold Rush", "size": Vector2(1280.0, 720.0), "coins": 24,
		"floor": Color(0.10, 0.15, 0.13), "about": "The whole screen, twenty-four coins"},
]

## What a game starts on.
const DEFAULT := &"classic"


## The arena called [param id], or an empty dictionary when there is none.
static func find(id: StringName) -> Dictionary:
	for arena: Dictionary in LIST:
		if arena["id"] == id:
			return arena
	return {}


## The M menu's rows (dot-menu's `DotMenuMaps` and dot-vote's `DotVoteMapMenu` take the same
## shape), with [param current] marked.
static func rows(current: StringName) -> Array:
	var out: Array = []
	for arena: Dictionary in LIST:
		out.append({"id": String(arena["id"]), "name": arena["name"], "detail": arena["about"],
			"current": arena["id"] == current})
	return out
