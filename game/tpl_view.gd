extends Node2D

const TplGame := preload("tpl_game.gd")

## Draws a [TplGame]: the arena, the coins, the players. Reads the game and changes nothing,
## so it draws an offline game and a connected one the same way.
##
## Drawn in code rather than from art so the template ships no assets. Replace [method _draw]
## with sprites when you have some -- and load them through TplPaths.rebase().

var game: TplGame = null

## Which player to ring in white. 0 until the client knows who it is.
var local_id: int = 0

## A connected client's dot-net clock, which says how far through its tick a frame is; null
## offline. Set by the client every frame. See [method frame_alpha].
var render_clock: Object = null


func _process(_delta: float) -> void:
	_fit()
	queue_redraw()


## Scales the largest arena to the window, letterboxed, and centres the one being played in
## it: a smaller arena looks smaller, rather than the same size with bigger players.
func _fit() -> void:
	var window := get_viewport_rect().size
	var fit := minf(window.x / TplGame.ARENA.x, window.y / TplGame.ARENA.y)
	var walls := game.size if game != null else TplGame.ARENA
	scale = Vector2(fit, fit)
	position = (window - walls * fit) * 0.5


## Where a point on the screen is in the arena. For touch.
func to_arena(screen: Vector2) -> Vector2:
	return (screen - position) / scale.x


func _draw() -> void:
	# Everything outside the walls, so a small arena sits in the dark rather than in grey.
	draw_rect(Rect2(-position / scale.x, get_viewport_rect().size / scale.x), Color(0.05, 0.06, 0.08))

	if game == null:
		return

	draw_rect(Rect2(Vector2.ZERO, game.size), game.arena["floor"])
	draw_rect(Rect2(Vector2.ZERO, game.size), Color(0.35, 0.4, 0.5), false, 4.0)

	for spot in game.coins:
		draw_circle(spot, TplGame.COIN_RADIUS, Color(0.96, 0.77, 0.26))

	var font := ThemeDB.fallback_font
	var alpha := frame_alpha()

	for id: int in game.players:
		var who: TplGame.Player = game.players[id]
		# Between this player's last two ticks, when they are simulated here: your own player
		# connected, everybody offline. See TplGame.Player.drawn_position.
		var at := who.drawn_position(alpha)
		draw_circle(at, TplGame.PLAYER_RADIUS, TplGame.colour_of(id))
		if id == local_id:
			draw_arc(at, TplGame.PLAYER_RADIUS + 3.0, 0.0, TAU, 32, Color.WHITE, 3.0)
		draw_string(font, at + Vector2(-60.0, -TplGame.PLAYER_RADIUS - 8.0),
			who.name, HORIZONTAL_ALIGNMENT_CENTER, 120.0, 16)


## How far through its tick a frame drawn now is.
##
## [b]Connected, the clock's `render_alpha()`, not the engine's physics fraction.[/b] The
## clock stretches and shrinks its ticks while it settles on the server, so now and then a
## physics frame runs no tick, or two. Drawn at the engine's fraction, the frame after one
## with none goes back over the step it just drew (the player stands still) and the frame
## after one with two skips a step (it moves double). `render_alpha` keeps the drawing where
## it was and takes the slip back over the next few ticks. Asked by name, so a client shell
## with an older dot-net draws at the engine's fraction. Offline every physics frame is one
## tick, and the engine's fraction is exact.
func frame_alpha() -> float:
	if render_clock != null and is_instance_valid(render_clock) and render_clock.has_method(&"render_alpha"):
		return float(render_clock.call(&"render_alpha"))
	return clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
