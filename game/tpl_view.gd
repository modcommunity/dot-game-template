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


func _process(_delta: float) -> void:
	_fit()
	queue_redraw()


## Scales the arena to the window, letterboxed.
func _fit() -> void:
	var window := get_viewport_rect().size
	var fit := minf(window.x / TplGame.ARENA.x, window.y / TplGame.ARENA.y)
	scale = Vector2(fit, fit)
	position = (window - TplGame.ARENA * fit) * 0.5


## Where a point on the screen is in the arena. For touch.
func to_arena(screen: Vector2) -> Vector2:
	return (screen - position) / scale.x


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, TplGame.ARENA), Color(0.11, 0.13, 0.18))
	draw_rect(Rect2(Vector2.ZERO, TplGame.ARENA), Color(0.35, 0.4, 0.5), false, 4.0)

	if game == null:
		return

	for spot in game.coins:
		draw_circle(spot, TplGame.COIN_RADIUS, Color(0.96, 0.77, 0.26))

	var font := ThemeDB.fallback_font

	for id: int in game.players:
		var who: TplGame.Player = game.players[id]
		draw_circle(who.position, TplGame.PLAYER_RADIUS, TplGame.colour_of(id))
		if id == local_id:
			draw_arc(who.position, TplGame.PLAYER_RADIUS + 3.0, 0.0, TAU, 32, Color.WHITE, 3.0)
		draw_string(font, who.position + Vector2(-60.0, -TplGame.PLAYER_RADIUS - 8.0),
			who.name, HORIZONTAL_ALIGNMENT_CENTER, 120.0, 16)
