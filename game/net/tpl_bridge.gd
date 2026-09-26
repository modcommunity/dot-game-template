extends Node

const TplCommand := preload("tpl_command.gd")
const TplEvent := preload("tpl_event.gd")
const TplGame := preload("../tpl_game.gd")
const TplLink := preload("tpl_link.gd")
const TplPlayerNet := preload("tpl_player_net.gd")
const TplRequest := preload("tpl_request.gd")

## The only file that names both the game and dot-net. Everything that crosses the wire starts
## or ends here, on both ends.
##
## Four things travel through [TplLink]: SNAPSHOTS (dot-net's: positions and scores), INPUTS
## (the client's intent, every tick), EVENTS (hello, coins, spawn, despawn) and REQUESTS (ready).
## dot-game's module calls [method add_player], [method remove_peer] and [method server_tick].

## The acknowledgement dot-net puts in front of every input. Fixed width, so it goes first.
const ACK_BYTES := 4

## Client side: the server said which player this client is.
signal hello_received(player_id: int)

var game: TplGame = null
var net: DotNetManager = null
var link: TplLink = null

## Client side: the round trip in ms. dot-net owns no socket, so it cannot measure one.
var rtt_source: Callable = Callable()

## Client side: which player is ours. 0 until the hello.
var local_id: int = 0

var _tick: int = 0
var _player_of_peer: Dictionary = {}

## Server side: peers whose scene exists. An event sent to any other lands on nothing.
var _ready_peers: Dictionary = {}

## player id -> TplPlayerNet, on both ends.
var _nets: Dictionary = {}


## The netcode's numbers. One function for both ends, so they cannot disagree.
static func net_config(tick_rate: int) -> DotNetConfig:
	var config := DotNetConfig.new()
	config.tick_rate = tick_rate
	# About twenty snapshots a second, and the rate has to divide the tick rate exactly.
	config.snapshot_rate = 20
	while tick_rate % config.snapshot_rate != 0:
		config.snapshot_rate -= 1
	config.enable_prediction = true
	# Rewinding is for resolving a shot against what the shooter saw. Nobody shoots here.
	config.enable_lag_compensation = false
	return config


func attach(p_game: TplGame, p_net: DotNetManager) -> DotResult:
	game = p_game
	net = p_net
	net.send_fn = _send

	# The direction is enforced on receipt, against the transport's idea of the sender.
	var event := net.messages.register(TplEvent.NAME, TplEvent,
		DotNetMessage.Delivery.RELIABLE, DotNetMessage.Direction.TO_CLIENT)
	var request := net.messages.register(TplRequest.REQUEST, TplRequest,
		DotNetMessage.Delivery.RELIABLE, DotNetMessage.Direction.TO_SERVER)
	if not event.ok or not request.ok:
		return event if not event.ok else request
	net.messages.on(TplEvent.NAME, _on_event)
	net.messages.on(TplRequest.REQUEST, _on_request)
	if net.is_server:
		game.coin_moved.connect(_on_coin_moved)
	return DotResult.success(self)


## Puts the link under the node named `Server` on this end. See [TplLink].
func open_link(parent: Node) -> void:
	link = TplLink.new()
	link.name = TplLink.NODE_NAME
	link.bridge = self
	parent.add_child(link)


## Every byte dot-net sends leaves here. Snapshots are its only unreliable traffic.
func _send(peer_id: int, payload: PackedByteArray, delivery: int) -> void:
	if link == null:
		return
	if delivery == DotNetMessage.Delivery.UNRELIABLE:
		link.send_snapshot(peer_id, payload)
	elif net.is_server:
		link.send_event(peer_id, payload)
	else:
		link.send_request(payload)


# --- Server ------------------------------------------------------------------

## Somebody finished joining. [param player_id] is their session's userid, which survives a
## reconnect where a peer id does not.
func add_player(peer_id: int, player_id: int, display_name: String) -> DotResult:
	_player_of_peer[peer_id] = player_id
	var who: TplGame.Player = game.add_player(player_id, display_name)
	var registered := net.registry.register(_spawn(who, peer_id), 0, _tick, net.config)
	if not registered.ok:
		return registered
	for peer: int in _ready_peers:
		_tell(peer, TplEvent.Kind.SPAWN, _spawn_body(player_id))

	# Their READY can arrive before this: the two race on a fast connection.
	if _ready_peers.has(peer_id):
		_admit(peer_id)
	return DotResult.success(who)


func remove_peer(peer_id: int) -> void:
	var player_id := int(_player_of_peer.get(peer_id, 0))
	# Off the list first: everything below tells everybody ELSE, and this peer has gone.
	_ready_peers.erase(peer_id)
	_player_of_peer.erase(peer_id)
	if player_id != 0:
		var body := DotNetWriter.new()
		body.write_varint(_despawn(player_id))
		game.remove_player(player_id)
		for peer: int in _ready_peers:
			_tell(peer, TplEvent.Kind.DESPAWN, body.to_bytes())
	if net.peers().has(peer_id):
		net.remove_peer(peer_id)


## One authoritative tick. dot-net applies each peer's input, simulates every player (see
## TplPlayerNet._net_simulate) and sends a snapshot when one is due.
func server_tick(tick: int) -> void:
	_tick = tick
	net.server_tick(tick)


## The peer can receive now: who it is, where the coins are, and who is here.
func _admit(peer_id: int) -> void:
	if not net.peers().has(peer_id):
		net.add_peer(peer_id)
	var hello := DotNetWriter.new()
	hello.write_varint(int(_player_of_peer[peer_id]))
	hello.write_uint(_tick, 32)
	hello.write_uint(net.config.tick_rate, 8)
	hello.write_uint(net.config.snapshot_rate, 8)
	_tell(peer_id, TplEvent.Kind.HELLO, hello.to_bytes())
	var coins := DotNetWriter.new()
	coins.write_uint(game.coins.size(), 8)
	for spot in game.coins:
		_write_spot(coins, spot)
	_tell(peer_id, TplEvent.Kind.COINS, coins.to_bytes())
	for player_id: int in _nets:
		_tell(peer_id, TplEvent.Kind.SPAWN, _spawn_body(player_id))


func _on_coin_moved(index: int, spot: Vector2) -> void:
	var body := DotNetWriter.new()
	body.write_uint(index, 8)
	_write_spot(body, spot)
	for peer: int in _ready_peers:
		_tell(peer, TplEvent.Kind.COIN, body.to_bytes())


func _tell(peer_id: int, kind: int, body: PackedByteArray) -> void:
	net.send(TplEvent.new(kind, body), peer_id)


func _spawn_body(player_id: int) -> PackedByteArray:
	var behaviour: TplPlayerNet = _nets[player_id]
	var body := DotNetWriter.new()
	body.write_varint(behaviour.identity.net_id)
	body.write_varint(behaviour.identity.owner_peer_id)
	body.write_varint(player_id)
	body.write_string(behaviour.player.name, 64)
	return body.to_bytes()


func receive_input(peer_id: int, payload: PackedByteArray) -> void:
	if payload.size() <= ACK_BYTES or not net.peers().has(peer_id):
		return
	net.receive_ack_payload(peer_id, payload.slice(0, ACK_BYTES))
	var command := TplCommand.new()
	command.read(DotNetReader.new(payload.slice(ACK_BYTES)))
	# Buffered for its tick. dot-net sanitises it on the way out, on the one path every input
	# takes, rather than here where a second caller could forget.
	net.input_buffer_for(peer_id).push(command)


func receive_request(peer_id: int, payload: PackedByteArray) -> void:
	net.receive(payload, peer_id)


func _on_request(message: DotNetMessage) -> void:
	var request := message as TplRequest
	if request != null and request.kind == TplRequest.Ask.READY:
		_ready_peers[request.sender_peer_id] = true
		if _player_of_peer.has(request.sender_peer_id):
			_admit(request.sender_peer_id)


# --- Client ------------------------------------------------------------------

## Tells the server this client's scene exists. Once, after the join has finished.
func ask_ready() -> void:
	net.send(TplRequest.new(TplRequest.Ask.READY), 1)


## One client tick: send the intent, then predict with exactly what the server will read.
func client_tick(tick: int, intent: Vector2) -> void:
	var command := TplCommand.new()
	command.tick = tick
	command.delta = net.clock.tick_duration()
	command.move = intent
	var bytes := DotNetWriter.new()
	command.write(bytes)

	# Decoded again before predicting: the server simulates the quantised value, so the client
	# must too, or every tick is a small disagreement the server has to correct.
	var sent := TplCommand.new()
	sent.read(DotNetReader.new(bytes.to_bytes()))
	sent.sanitise(net.config.tick_rate)
	net.local_inputs().push(sent)
	var payload := net.encode_ack()
	payload.append_array(bytes.to_bytes())
	link.send_input(payload)
	var me: TplGame.Player = game.player(local_id)
	if me != null:
		me.intent = sent.move
	net.client_tick(tick)


func receive_snapshot(payload: PackedByteArray) -> void:
	if rtt_source.is_valid():
		net.stats.note_rtt(float(rtt_source.call()))
	net.receive_snapshot(payload)


func receive_event(payload: PackedByteArray) -> void:
	net.receive(payload, 1)


func _on_event(message: DotNetMessage) -> void:
	var event := message as TplEvent
	var reader := DotNetReader.new(event.body)
	match event.kind:
		TplEvent.Kind.HELLO:
			local_id = reader.read_varint()
			var tick := reader.read_uint(32)
			_adopt_rates(reader.read_uint(8), reader.read_uint(8))
			net.clock.sync_from_server(tick, float(rtt_source.call()) if rtt_source.is_valid() else 0.0)
			hello_received.emit(local_id)
		TplEvent.Kind.COINS:
			game.coins.clear()
			for _i in range(reader.read_uint(8)):
				game.coins.append(_read_spot(reader))
		TplEvent.Kind.COIN:
			var index := reader.read_uint(8)
			var spot := _read_spot(reader)
			if index < game.coins.size():
				game.coins[index] = spot
		TplEvent.Kind.SPAWN:
			var net_id := reader.read_varint()
			var owner_peer := reader.read_varint()
			var player_id := reader.read_varint()
			var display_name := reader.read_string(64)
			if reader.ok() and not _nets.has(player_id):
				var who: TplGame.Player = game.add_player(player_id, display_name)
				net.registry.register(_spawn(who, owner_peer), net_id, net.clock.tick, net.config)
		TplEvent.Kind.DESPAWN:
			var gone := reader.read_varint()
			for player_id: int in _nets.keys():
				if (_nets[player_id] as TplPlayerNet).identity.net_id == gone:
					_despawn(player_id)
					game.remove_player(player_id)


## The server's rates, which are its operator's (`sv_tickrate`). The engine's physics rate
## too: interpolation draws at a fraction through a physics frame, which is only a fraction
## through a tick while the two are the same.
func _adopt_rates(tick_rate: int, snapshot_rate: int) -> void:
	if tick_rate > 0 and snapshot_rate > 0:
		net.config.tick_rate = tick_rate
		net.config.snapshot_rate = snapshot_rate
		net.clock.tick_rate = tick_rate
		Engine.physics_ticks_per_second = tick_rate


# --- Both --------------------------------------------------------------------

## A node, a behaviour and an identity: what makes a player replicate.
func _spawn(who: TplGame.Player, owner_peer: int) -> DotNetIdentity:
	var root := Node2D.new()
	root.name = "Player%d" % who.id
	root.position = who.position
	add_child(root)
	var behaviour := TplPlayerNet.new()
	behaviour.game = game
	behaviour.player = who
	root.add_child(behaviour)

	# After the behaviour: an identity collects its behaviours when it enters the tree.
	var identity := DotNetIdentity.new()
	identity.owner_peer_id = owner_peer
	# SHARED: the server decides and corrects, the owner predicts. SERVER would put the local
	# player a whole round trip behind their own keyboard.
	identity.authority = DotNetIdentity.Authority.SHARED
	# Everybody sees everybody; the arena is one screen. A bigger world wants interest
	# management here -- which is also the only anti-cheat that stops a wallhack.
	identity.always_relevant = true
	root.add_child(identity)
	_nets[who.id] = behaviour
	return identity


## Takes a player's entity out of the netcode and the tree. Returns its net id.
func _despawn(player_id: int) -> int:
	var behaviour: TplPlayerNet = _nets.get(player_id)
	_nets.erase(player_id)
	if behaviour == null:
		return 0
	var net_id := behaviour.identity.net_id
	net.registry.unregister(net_id)
	behaviour.get_parent().queue_free()
	return net_id


static func _write_spot(writer: DotNetWriter, spot: Vector2) -> void:
	writer.write_float_range(spot.x, 0.0, TplGame.ARENA.x, 16)
	writer.write_float_range(spot.y, 0.0, TplGame.ARENA.y, 16)


static func _read_spot(reader: DotNetReader) -> Vector2:
	var x := reader.read_float_range(0.0, TplGame.ARENA.x, 16)
	return Vector2(x, reader.read_float_range(0.0, TplGame.ARENA.y, 16))


func describe_lines() -> PackedStringArray:
	return PackedStringArray([
		"netcode    %s at %d Hz, snapshots at %d Hz" % [
			"server" if net.is_server else "client", net.config.tick_rate, net.config.snapshot_rate],
		"players    %d, %d peer(s) ready" % [_nets.size(), _ready_peers.size()],
	])
