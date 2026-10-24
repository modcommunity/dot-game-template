extends "suite.gd"

const TplArenas := preload("../game/tpl_arenas.gd")
const TplCommand := preload("../game/net/tpl_command.gd")
const TplGame := preload("../game/tpl_game.gd")

## The rules, with no window, no server and no network.
##
##     godot --headless --path . res://examples/headless_rules.tscn


func _ready() -> void:
	checks = 28
	print("dot-game-template: the rules")

	section("a game starts")
	var game := _game()
	check(game.arena["id"] == TplArenas.DEFAULT and game.coins.size() == int(game.arena["coins"]),
		"on the default arena, with its %d coins" % game.coins.size())
	check(game.coins.all(func(spot: Vector2) -> bool: return Rect2(Vector2.ZERO, TplGame.ARENA).has_point(spot)),
		"all of them inside the arena")
	check(_game().coins == game.coins, "and the same seed lays them out the same way")
	var who: TplGame.Player = game.add_player(3, "Ada")
	check(game.player(3) == who and who.score == 0, "a player joins with no score")
	game.remove_player(3)
	check(game.player(3) == null, "and leaves")
	done()

	section("moving")
	var from := TplGame.ARENA * 0.5
	check(is_equal_approx(TplGame.step(from, Vector2.RIGHT, 1.0).x - from.x, TplGame.PLAYER_SPEED),
		"a second of full right is PLAYER_SPEED units")
	var diagonal := TplGame.step(from, Vector2(1.0, 1.0), 0.1).distance_to(from)
	check(is_equal_approx(diagonal, TplGame.PLAYER_SPEED * 0.1),
		"a diagonal is no faster than a straight line (%.2f)" % diagonal)
	check(TplGame.step(Vector2.ZERO, Vector2(-1.0, -1.0), 5.0) == Vector2.ONE * TplGame.PLAYER_RADIUS,
		"nobody leaves the arena")
	# What prediction rests on: the same input from the same place gives the same place.
	check(TplGame.step(from, Vector2(0.3, -0.7), 1.0 / 60.0) == TplGame.step(from, Vector2(0.3, -0.7), 1.0 / 60.0),
		"a step is a pure function of where you were, what you pressed and for how long")
	done()

	section("drawn between ticks")
	var runner := _game()
	var dot: TplGame.Player = runner.add_player(5, "Bo")
	check(dot.drawn_position(0.5) == dot.position, "before a tick has run, a player is drawn where they are")
	dot.intent = Vector2.RIGHT
	runner.move(dot, 0.1)
	var start := dot.drawn_from
	runner.move(dot, 0.1)
	check(dot.drawn_position(0.5).is_equal_approx(dot.drawn_from.lerp(dot.position, 0.5))
		and dot.drawn_position(1.5).is_equal_approx(dot.position + (dot.position - dot.drawn_from) * 0.5)
		and dot.drawn_position(-0.5).is_equal_approx(start.lerp(dot.drawn_from, 0.5)),
		"a frame is drawn between the last two ticks, on past the last below 2, between the two before above -1")
	dot.position += Vector2(0.0, 300.0)
	check(dot.drawn_position(0.5) == dot.position, "and a jump of more than a body's width is drawn where it landed")
	done()

	section("coins")
	var moved: Array = []
	game.coin_moved.connect(func(index: int, _spot: Vector2) -> void: moved.append(index))
	who = game.add_player(1, "Ada")
	var target := game.coins[2]
	who.position = target
	check(game.collect(who) == 2, "standing on a coin collects it")
	check(who.score == game.config.coin_value, "and scores config.coin_value (%d)" % who.score)
	var binder := DotGameConfigBinder.create(game.config, "tpl", "tpl")
	check(binder.schema().size() == 2 and binder.schema()[0]["key"] == "coin_value", "the config's fields reach dot-game's binder (cvars, yml, workbench)")
	check(moved == [2] and game.coins[2] != target, "and the coin reappears elsewhere")
	check(game.coins[2].distance_to(who.position) >= TplGame.PLAYER_RADIUS * 3.0,
		"not under the player who just took it")
	var mirror := _game()
	mirror.authoritative = false
	var copy: TplGame.Player = mirror.add_player(1, "Ada")
	copy.position = mirror.coins[0]
	check(mirror.collect(copy) == -1 and copy.score == 0, "a client's copy of the game never collects")
	done()

	section("arenas")
	check(TplArenas.LIST.all(func(a: Dictionary) -> bool:
		return a["size"].x <= TplGame.ARENA.x and a["size"].y <= TplGame.ARENA.y and int(a["coins"]) <= 255),
		"every arena fits inside ARENA, the wire's range, and its coin count in a byte")
	var changes: Array = []
	game.arena_changed.connect(func(id: StringName) -> void: changes.append(id))
	who.position = Vector2(1200.0, 700.0)
	check(game.change_arena(&"pocket").ok and changes == [&"pocket"], "changing the arena says so")
	var pocket := Rect2(Vector2.ZERO, game.size)
	check(game.size == TplArenas.find(&"pocket")["size"] and game.coins.size() == int(game.arena["coins"])
		and game.coins.all(func(spot: Vector2) -> bool: return pocket.has_point(spot)),
		"and lays the new arena's own coins inside its walls (%d)" % game.coins.size())
	check(pocket.grow(-TplGame.PLAYER_RADIUS + 0.01).has_point(who.position) and who.score == 0,
		"a player outside the new walls is moved inside, and every score starts again")
	check(TplGame.step(who.position, Vector2.RIGHT, 5.0, game.size).x == game.size.x - TplGame.PLAYER_RADIUS,
		"and the new walls stop a player")
	check(not game.change_arena(&"nowhere").ok and game.arena["id"] == &"pocket", "an arena that does not exist is refused")
	var rows := TplArenas.rows(&"pocket")
	check(rows.size() == TplArenas.LIST.size() and rows.filter(func(r: Dictionary) -> bool: return r["current"]).size() == 1,
		"the M menu lists every arena, the one being played marked")
	done()

	section("what a client may send")
	var command := TplCommand.new()
	command.move = Vector2(1.0, 1.0)
	command.sanitise(60)
	check(is_equal_approx(command.move.length(), 1.0), "a (1, 1) input is cut to length 1 by the server")
	command.move = Vector2(0.37, -0.81)
	var writer := DotNetWriter.new()
	command.write(writer)
	var read := TplCommand.new()
	read.read(DotNetReader.new(writer.to_bytes()))
	check(read.move.distance_to(command.move) < 0.01, "and one survives the wire to within a hundredth")
	done()

	finish()


## In the tree, so it is freed with the suite. It registers nothing: only a server's copy does.
func _game() -> TplGame:
	var game := TplGame.new()
	add_child(game)
	game.start(1234)
	return game
