extends Node

## The whole game: the rules and the state they act on. Everything else in this repository
## either feeds it (the netcode, the keyboard) or draws it.
##
## [b]One class for every place the game runs.[/b] A dedicated server's copy has
## [member authoritative] on and decides everything. A connected client's has it off: a mirror
## the netcode writes into, which only moves its own player ahead of the server (prediction)
## and never collects a coin. An offline client's has it on and nobody else in it. A separate
## "single player" copy of the rules would be a second game to keep in step with this one.
##
## Nothing here needs a frame, a window or a physics server, which is why
## `examples/headless_rules.tscn` can run all of it.

## Where the server's copy publishes itself, for [code]tpl_module.gd[/code] to find.
const SERVICE := &"tpl_game"

## The arena, in world units. The client scales it to fit whatever window it gets.
const ARENA := Vector2(1280.0, 720.0)

const PLAYER_RADIUS := 22.0

## Units per second at full stick.
const PLAYER_SPEED := 320.0

const COIN_RADIUS := 11.0
const COIN_COUNT := 8

## What one coin is worth. The README's first exercise.
const COIN_VALUE := 1

## A coin was collected and has reappeared somewhere else. Server side.
signal coin_moved(index: int, position: Vector2)

## Somebody's score changed. Server side; clients see it through the replicated score.
signal scored(player_id: int, score: int)


## One person in the arena. The rules never mention the netcode; it copies these fields.
class Player:
	var id: int = 0
	var name: String = ""
	var position: Vector2 = Vector2.ZERO
	## Where they are trying to go, length 0..1. Set from their input every tick.
	var intent: Vector2 = Vector2.ZERO
	var score: int = 0


## Whether this copy decides things. See the class note.
var authoritative: bool = true

## Whether to publish under [constant SERVICE]. Only the server's copy does, or two copies in
## one process would fight over the name.
var register_service: bool = false

## id -> [Player]. Insertion order is the order everybody is simulated in, on every machine.
var players: Dictionary = {}

var coins: Array[Vector2] = []

var collected: int = 0

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if register_service:
		DotRegistry.register(SERVICE, self)


func _exit_tree() -> void:
	DotRegistry.unregister_instance(SERVICE, self)


## Lays the coins out. A non-zero [param rng_seed] makes it repeatable, which the suites use.
func start(rng_seed: int = 0) -> void:
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	coins.clear()
	collected = 0
	for _i in range(COIN_COUNT):
		coins.append(_free_spot())


func add_player(id: int, display_name: String) -> Player:
	var who := Player.new()
	who.id = id
	who.name = display_name
	# Deterministic from the id, so a server and a client that both create this player put
	# them in the same place before the first snapshot says so.
	who.position = ARENA * 0.5 + Vector2(float(id % 7) - 3.0, float(id % 5) - 2.0) * 60.0
	players[id] = who
	return who


func remove_player(id: int) -> void:
	players.erase(id)


func player(id: int) -> Player:
	return players.get(id)


## Where somebody at [param from] ends up after one tick of [param intent].
##
## [b]Static and pure, and that is the whole of client prediction.[/b] The owning client runs
## it on the same input as the server, a few ticks ahead, and they agree. Anything that differs
## between machines -- the clock, [code]randf()[/code], another player -- must never reach it.
static func step(from: Vector2, intent: Vector2, delta: float) -> Vector2:
	var moved := from + intent.limit_length(1.0) * PLAYER_SPEED * delta
	var edge := Vector2(PLAYER_RADIUS, PLAYER_RADIUS)
	return moved.clamp(edge, ARENA - edge)


func move(who: Player, delta: float) -> void:
	who.position = step(who.position, who.intent, delta)


## Collects the first coin [param who] is touching; returns its index, or -1. Only the
## authority collects: a client that did would show a score the server may then take back.
func collect(who: Player) -> int:
	if not authoritative:
		return -1
	for i in range(coins.size()):
		if who.position.distance_to(coins[i]) > PLAYER_RADIUS + COIN_RADIUS:
			continue
		who.score += COIN_VALUE
		collected += 1
		coins[i] = _free_spot()
		coin_moved.emit(i, coins[i])
		scored.emit(who.id, who.score)
		return i
	return -1


## One tick for everybody, offline. On a server the netcode runs [method move] and
## [method collect] per player instead, inside its own tick.
func tick(delta: float) -> void:
	for id: int in players:
		var who: Player = players[id]
		move(who, delta)
		collect(who)


## A random spot not under anybody, so a coin never reappears already collected.
func _free_spot() -> Vector2:
	var margin := COIN_RADIUS * 3.0
	var spot := Vector2.ZERO
	for _attempt in range(16):
		spot = Vector2(_rng.randf_range(margin, ARENA.x - margin), _rng.randf_range(margin, ARENA.y - margin))
		if players.values().all(func(who: Player) -> bool: return who.position.distance_to(spot) >= PLAYER_RADIUS * 3.0):
			break
	return spot


## A colour per player, the same on every machine because it comes from the id.
static func colour_of(id: int) -> Color:
	return Color.from_hsv(fposmod(float(id) * 0.618034, 1.0), 0.6, 0.95)


## The state, for a console command or a bug report. A delivered game's host cannot name this
## class, so this is also how dot-server-deploy's suite asks the world what it has.
func describe() -> Dictionary:
	var scores := {}
	for id: int in players:
		scores[id] = (players[id] as Player).score
	return {"players": players.size(), "coins": coins.size(), "collected": collected, "scores": scores}


func describe_lines() -> PackedStringArray:
	var lines := PackedStringArray(["%d player(s), %d coin(s) collected" % [players.size(), collected]])
	for id: int in players:
		var who: Player = players[id]
		lines.append("  %-20s %4d  at %s" % [who.name, who.score, who.position.round()])
	return lines
