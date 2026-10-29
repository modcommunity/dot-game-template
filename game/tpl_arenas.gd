extends RefCounted

## The arenas: this game's maps as data; M lists them and choosing one changes it.
## [b]A map is a row of numbers, not a scene[/b]: size, coin count, floor colour; add a row and it is in the M menu.
## Every arena fits inside [constant TplGame.ARENA], the wire's range. [b]The ids are the wire[/b]: never rename one alone.

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

## Subscribed pack maps (tpl_workshop.gd), same shape as a [constant LIST] row. Solo only: a
## server never fills it, so online the arenas are LIST and nothing else. [method find] and
## [method rows] read both, which is all it takes for M and [code]change_arena[/code] to play one.
static var workshop: Dictionary = {}


## The arena called [param id], or an empty dictionary when there is none.
static func find(id: StringName) -> Dictionary:
	for arena: Dictionary in LIST:
		if arena["id"] == id:
			return arena
	return workshop.get(id, {})


## The M menu's rows (dot-menu's `DotMenuMaps` and dot-vote's `DotVoteMapMenu` take the same
## shape), with [param current] marked.
static func rows(current: StringName) -> Array:
	var out: Array = []
	var all: Array = LIST.duplicate()
	all.append_array(workshop.values())
	for arena: Dictionary in all:
		out.append({"id": String(arena["id"]), "name": arena["name"], "detail": arena["about"],
			"current": arena["id"] == current})
	return out
