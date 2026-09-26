extends DotNetBehaviour

const TplCommand := preload("tpl_command.gd")
const TplGame := preload("../tpl_game.gd")

## One player, as the netcode sees them. The same script everywhere: on the server it moves
## the player and collects coins; on the client that OWNS the player it moves them ahead of the
## server (prediction), and dot-net rewinds and replays that when a snapshot disagrees; on every
## other client it only receives, and interpolates between snapshots.

var game: TplGame = null
var player: TplGame.Player = null

# Replicated. dot-net sends only what changed since what each client confirmed.
var net_x: float = 0.0
var net_y: float = 0.0
var net_score: int = 0


## What replicates, and how precisely: sixteen bits over 1280 units is two hundredths of a
## unit, far below a pixel. A new field goes at the END, like everything on the wire.
func _register_net_vars() -> void:
	replicate(&"net_x", DotNetVar.Type.FLOAT_RANGE).range_of(0.0, TplGame.ARENA.x).bits(16).interpolated()
	replicate(&"net_y", DotNetVar.Type.FLOAT_RANGE).range_of(0.0, TplGame.ARENA.y).bits(16).interpolated()
	replicate(&"net_score", DotNetVar.Type.UINT).bits(16)


## One tick of the owner's intent. On the server it has already been sanitised.
func _net_apply_input(input: DotNetInput, _tick: int) -> void:
	var command := input as TplCommand
	if command != null and player != null:
		player.intent = command.move


## One tick, on whichever machine may simulate this player.
func _net_simulate(_tick: int, delta: float) -> void:
	if player == null:
		return

	game.move(player, delta)
	# Only the server collects: a client reaching a coin first on its own screen is not proof.
	if identity.is_authoritative:
		game.collect(player)

	net_x = player.position.x
	net_y = player.position.y
	net_score = player.score
	_place()


## A snapshot arrived. For the local player this is the rewind half of prediction: the
## server's answer is adopted and dot-net replays the unacknowledged inputs on top of it.
func _net_state_applied(_tick: int) -> void:
	if player == null:
		return

	player.position = Vector2(net_x, net_y)
	player.score = net_score
	# Not the node, on a predicted player: dot-net reads the node to measure how wrong the
	# prediction was, and the server's answer written there first would hide the answer.
	if not identity.is_predicted():
		_place()


## Every frame, for everybody else: the smoothed position between snapshots. Without it a
## remote player moves in snapshot-sized steps while the smooth value sits unread.
func _net_interpolated(_tick: int) -> void:
	if player != null:
		player.position = Vector2(net_x, net_y)
		_place()


## The node follows the player, because dot-net reads the node to judge distance and error.
func _place() -> void:
	var node := identity.entity as Node2D if identity != null else null
	if node != null:
		node.position = player.position
