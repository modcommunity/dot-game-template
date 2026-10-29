extends Node

## The whole game: the rules and the state they act on; everything else feeds or draws it.
## [b]One class everywhere[/b]: a server's copy decides ([member authoritative]); a connected client's is a mirror that
## only predicts its own player; an offline one is alone. Nothing needs a window, so `headless_rules.tscn` runs all of it.

const TplArenas := preload("tpl_arenas.gd")
const TplConfig := preload("tpl_config.gd")

## Where the server's copy publishes itself, for [code]tpl_module.gd[/code] to find.
const SERVICE := &"tpl_game"

## The largest arena, in world units: every arena in [code]tpl_arenas.gd[/code] fits inside
## it, positions are sent within it, and the client scales it to fit whatever window it gets.
const ARENA := Vector2(1280.0, 720.0)

const PLAYER_RADIUS := 22.0

## Units per second at full stick.
const PLAYER_SPEED := 320.0

const COIN_RADIUS := 11.0

## A coin was collected and has reappeared somewhere else. Server side.
signal coin_moved(index: int, position: Vector2)

## Somebody's score changed. Server side; clients see it through the replicated score.
signal scored(player_id: int, score: int)

## The arena changed (see [method change_arena]). Server side and offline.
signal arena_changed(id: StringName)


## One person in the arena. The rules never mention the netcode; it copies these fields.
class Player:
	var id: int = 0
	var name: String = ""
	var position: Vector2 = Vector2.ZERO
	## Where they are trying to go, length 0..1. Set from their input every tick.
	var intent: Vector2 = Vector2.ZERO
	var score: int = 0

	## Where they stood when their last tick began, and the tick before that: what a frame is
	## drawn between (see [method drawn_position]). Recorded by [method TplGame.move], so only
	## on a machine that simulates this player; NAN until a tick has run.
	var drawn_from: Vector2 = Vector2(NAN, NAN)
	var drawn_two_back: Vector2 = Vector2(NAN, NAN)

	## Where to DRAW them, [param alpha] of the way through their last tick. A player simulated here moves once a tick
	## but is drawn more often, so between the last tick's start and end; alpha outside 0..1 (a frame with no tick,
	## or two) extends along the last step. Somebody else's player is already smoothed by the netcode.
	func drawn_position(alpha: float) -> Vector2:
		if not drawn_from.is_finite():
			return position
		var step := position - drawn_from
		# More than a body's width in one tick is a teleport (a new arena, a correction),
		# never motion to draw through.
		if step.length() > PLAYER_RADIUS * 2.0:
			return position
		if alpha > 1.0:
			return position + step * minf(alpha - 1.0, 1.0)
		if alpha < 0.0:
			if not drawn_two_back.is_finite():
				return drawn_from
			return drawn_two_back.lerp(drawn_from, maxf(alpha + 1.0, 0.0))
		return drawn_from.lerp(position, alpha)


## Whether this copy decides things. See the class note.
## The tunables (coin_value, extra_coins); the server scene replaces it with the layered one.
var config := TplConfig.new()

## Binds [member config] to cvars; set by the server scene.
var config_binder: DotGameConfigBinder = null

var authoritative: bool = true

## Whether to publish under [constant SERVICE]. Only the server's copy does, or two copies in
## one process would fight over the name.
var register_service: bool = false

## id -> [Player]. Insertion order is the order everybody is simulated in, on every machine.
var players: Dictionary = {}

var coins: Array[Vector2] = []

## The arena being played: a row of [code]tpl_arenas.gd[/code]'s list.
var arena: Dictionary = TplArenas.find(TplArenas.DEFAULT)

## Its size, which is where [method step] stops a player. The arena's top-left corner is 0, 0.
var size: Vector2 = arena["size"]

var collected: int = 0

## `func(player_id: int) -> bool`: whether that player may be affected now. The module assigns
## dot-game's `can_be_harmed` on a server and leaves it unset everywhere else (offline nobody
## is behind a cover). See [method can_be_harmed].
var harm_gate: Callable = Callable()

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
	for _i in range(int(arena["coins"]) + config.extra_coins):
		coins.append(_free_spot())


## Changes the arena for everybody: a fresh round on it, every score back to 0. What M does,
## solo and on a server; the server's bridge tells every client. Only the authority calls it.
func change_arena(id: StringName) -> DotResult:
	if TplArenas.find(id).is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "There is no arena called '%s'." % id)
	use_arena(id)
	for who: Player in players.values():
		who.score = 0
	start()
	arena_changed.emit(id)
	return DotResult.success(id)


## Takes [param id]'s size and floor without laying any coins: a client hears where they are
## from the server. Anybody outside the new walls is moved inside them.
func use_arena(id: StringName) -> void:
	var found := TplArenas.find(id)
	if found.is_empty():
		return
	arena = found
	size = arena["size"]
	var edge := Vector2(PLAYER_RADIUS, PLAYER_RADIUS)
	for who: Player in players.values():
		who.position = who.position.clamp(edge, size - edge)


func add_player(id: int, display_name: String) -> Player:
	var who := Player.new()
	who.id = id
	who.name = display_name
	# Deterministic from the id, so a server and a client that both create this player put
	# them in the same place before the first snapshot says so.
	who.position = size * 0.5 + Vector2(float(id % 7) - 3.0, float(id % 5) - 2.0) * 60.0
	players[id] = who
	return who


func remove_player(id: int) -> void:
	players.erase(id)


func player(id: int) -> Player:
	return players.get(id)


## Where somebody at [param from] ends up after one tick of [param intent], within [param walls].
## [b]Static and pure, and that is the whole of client prediction[/b]: the owning client runs it on the server's input.
## Nothing that differs between machines (the clock, `randf()`, another player) may reach it.
static func step(from: Vector2, intent: Vector2, delta: float, walls: Vector2 = ARENA) -> Vector2:
	var moved := from + intent.limit_length(1.0) * PLAYER_SPEED * delta
	var edge := Vector2(PLAYER_RADIUS, PLAYER_RADIUS)
	return moved.clamp(edge, walls - edge)


## One tick of [param who]'s movement, remembering where it began for [method Player.drawn_position].
## On a client's own player this runs again for every tick dot-net replays after a correction,
## so what is remembered is the last replayed tick's, which is the one on screen.
func move(who: Player, delta: float) -> void:
	who.drawn_two_back = who.drawn_from
	who.drawn_from = who.position
	who.position = step(who.position, who.intent, delta, size)


## Collects the first coin [param who] is touching; returns its index, or -1. Only the
## authority collects: a client that did would show a score the server may then take back.
func collect(who: Player) -> int:
	if not authoritative:
		return -1
	# THE CHOKE POINT: the one place the game does anything to the world on a player's behalf.
	# Add the same line wherever YOUR hazards or rewards act; a player behind their loading cover
	# can neither be harmed nor take anything (README "Add your own hazards").
	if not can_be_harmed(who.id):
		return -1
	for i in range(coins.size()):
		if who.position.distance_to(coins[i]) > PLAYER_RADIUS + COIN_RADIUS:
			continue
		who.score += config.coin_value
		collected += 1
		coins[i] = _free_spot()
		coin_moved.emit(i, coins[i])
		scored.emit(who.id, who.score)
		return i
	return -1


## Whether [param player_id] is in play: false while their client is behind its loading cover
## (dot-game's "still loading", asked of the module through [member harm_gate]). True for anyone
## the gate does not know: offline, and a bot, which never loads.
func can_be_harmed(player_id: int) -> bool:
	return not harm_gate.is_valid() or bool(harm_gate.call(player_id))


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
		spot = Vector2(_rng.randf_range(margin, size.x - margin), _rng.randf_range(margin, size.y - margin))
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
	return {"arena": String(arena["id"]), "players": players.size(), "coins": coins.size(), "collected": collected, "scores": scores}


func describe_lines() -> PackedStringArray:
	var lines := PackedStringArray(["%s: %d player(s), %d coin(s) collected" % [arena["name"], players.size(), collected]])
	for id: int in players:
		var who: Player = players[id]
		lines.append("  %-20s %4d  at %s" % [who.name, who.score, who.position.round()])
	return lines
