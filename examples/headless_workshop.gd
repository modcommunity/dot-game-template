extends "suite.gd"

const TplArenas := preload("../game/tpl_arenas.gd")
const TplGame := preload("../game/tpl_game.gd")
const TplWorkshop := preload("../game/tpl_workshop.gd")

## What a subscribed map pack does to the solo arena list, against a fixture [DotContentIndex]:
## listed as Name [Pack] and playable, none online, an unaccepted map kind left out, the game's
## own ids win, a bad document refused with a reason.

const DIR := "user://ws_fixture/"


func _ready() -> void:
	checks = 19
	print("dot-game-template: Workshop maps")
	DotLog.set_level(DotLog.Level.ERROR)
	_write("bunker.json", '{"id": "bunker", "name": "Bunker", "size": [900, 500], "coins": 12, "floor": [0.2, 0.1, 0.1]}')
	_write("bad.json", '{"id": "bad", "name": "Bad", "size": [9000, 500], "coins": 12}')
	_write("run.json", '{"id": "run", "name": "Run", "size": [900, 500], "coins": 3}')
	_write("classic.json", '{"id": "classic", "name": "Imposter", "size": [900, 500], "coins": 3}')

	section("what the game accepts")
	var accepts: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://provides.json")) as Dictionary).get("accepts", {})
	check(accepts.get("kinds") == ["map"], "only maps")
	check(PackedStringArray(accepts.get("map_kinds", [])) == TplWorkshop.accepted(), "map kinds match TplWorkshop.accepted()")
	done()

	section("solo")
	var shop := TplWorkshop.new()
	shop.follow(_index(DotContentIndex.SESSION_SOLO))
	var names := _names()
	check(names.has("Bunker [Fixture Pack]"), "the accepted map is listed as Name [Pack] " + str(names))
	check(not names.has("Run [Fixture Pack]"), "a map kind the game does not accept is filtered out")
	check(not names.has("Bad [Fixture Pack]"), "a bad document is listed nowhere")
	check(names.size() == TplArenas.LIST.size() + 1, "and nothing else is added")
	done()

	section("online")
	var index := _index(DotContentIndex.SESSION_SOLO)
	var follower := TplWorkshop.new()
	follower.follow(index)
	check(TplArenas.workshop.size() == 1, "listed while the index is solo")
	index.set_session(DotContentIndex.SESSION_ONLINE)
	follower.refresh()
	check(TplArenas.workshop.is_empty(), "gone when the session turns online")
	check(TplArenas.find(&"bunker").is_empty(), "and not playable")
	done()

	section("ids and refusals")
	shop = TplWorkshop.new()
	shop.follow(_index(DotContentIndex.SESSION_SOLO))
	check(not _names().has("Imposter [Fixture Pack]"), "the game's own id wins")
	check(TplArenas.find(&"classic")["name"] == "Classic", "and keeps its own row")
	check(shop.refused.has("bad"), "the bad document is refused with a reason: " + str(shop.refused.get("bad", "")))
	done()

	section("play")
	var game := TplGame.new()
	game.authoritative = true
	add_child(game)
	game.start()
	var res := game.change_arena(&"bunker")
	check(res.ok, "change_arena (what M calls) accepts the pack map")
	check(game.arena["id"] == &"bunker" and game.size == Vector2(900.0, 500.0), "the game is on its size")
	check(game.coins.size() == 12, "with its twelve coins")
	check(game.coins.all(func(spot: Vector2) -> bool: return Rect2(Vector2.ZERO, game.size).has_point(spot)), "all inside its walls")
	check(TplArenas.rows(&"bunker").any(func(r: Dictionary) -> bool: return r["name"] == "Bunker [Fixture Pack]" and r["current"]),
		"M lists it as the current map")
	check(not game.change_arena(&"nothing").ok, "an unknown pack map is refused cleanly")
	game.queue_free()
	TplArenas.workshop.clear()
	done()

	finish()


func _write(file: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(DIR + file, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _index(session: StringName) -> DotContentIndex:
	var index := DotContentIndex.new()
	index.set_session(session)
	var _added := index.add_pack({
		"content_id": "fixture/arenas", "version": "1.0.0", "prefix": DIR,
		"session": session, "source": &"subscription",
		"provides": {"schema": 1, "title": "Fixture Pack", "kinds": ["map"], "entries": [
			{"kind": "map", "id": "bunker", "name": "Bunker", "scene": "bunker.json", "map_kind": "coin_arena"},
			{"kind": "map", "id": "bad", "name": "Bad", "scene": "bad.json", "map_kind": "coin_arena"},
			{"kind": "map", "id": "run", "name": "Run", "scene": "run.json", "map_kind": "surf"},
			{"kind": "map", "id": "classic", "name": "Imposter", "scene": "classic.json", "map_kind": "coin_arena"},
		]},
	})
	return index


func _names() -> PackedStringArray:
	var out := PackedStringArray()
	for row: Dictionary in TplArenas.rows(&"classic"):
		out.append(row["name"])
	return out
