extends "suite.gd"

const TplCommand := preload("../game/net/tpl_command.gd")
const TplGame := preload("../game/tpl_game.gd")

## The rules, with no window, no server and no network.
##
##     godot --headless --path . res://examples/headless_rules.tscn


func _ready() -> void:
	checks = 17
	print("dot-game-template: the rules")

	section("a game starts")
	var game := _game()
	check(game.coins.size() == TplGame.COIN_COUNT, "with %d coins" % TplGame.COIN_COUNT)
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

	section("coins")
	var moved: Array = []
	game.coin_moved.connect(func(index: int, _spot: Vector2) -> void: moved.append(index))
	who = game.add_player(1, "Ada")
	var target := game.coins[2]
	who.position = target
	check(game.collect(who) == 2, "standing on a coin collects it")
	check(who.score == TplGame.COIN_VALUE, "and scores COIN_VALUE (%d)" % who.score)
	check(moved == [2] and game.coins[2] != target, "and the coin reappears elsewhere")
	check(game.coins[2].distance_to(who.position) >= TplGame.PLAYER_RADIUS * 3.0,
		"not under the player who just took it")
	var mirror := _game()
	mirror.authoritative = false
	var copy: TplGame.Player = mirror.add_player(1, "Ada")
	copy.position = mirror.coins[0]
	check(mirror.collect(copy) == -1 and copy.score == 0, "a client's copy of the game never collects")
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
