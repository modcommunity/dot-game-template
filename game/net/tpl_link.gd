extends Node

const TplBridge := preload("tpl_bridge.gd")

## The four remote calls this game makes, on one node that exists on both ends.
## [b]Godot routes an RPC by NODE PATH and refuses it unless both ends declare the same @rpc methods[/b],
## so one script runs on both, named [constant NODE_NAME], under `Server`. Add a TplEvent kind, not an @rpc.

const NODE_NAME := &"Tpl"
const CHANNEL_STATE := 1

var bridge: TplBridge = null


func _live() -> bool:
	return is_inside_tree() and multiplayer.has_multiplayer_peer()


func send_snapshot(peer_id: int, payload: PackedByteArray) -> void:
	if _live():
		_rpc_snapshot.rpc_id(peer_id, payload)


func send_event(peer_id: int, payload: PackedByteArray) -> void:
	if _live():
		_rpc_event.rpc_id(peer_id, payload)


func send_input(payload: PackedByteArray) -> void:
	if _live():
		_rpc_input.rpc_id(1, payload)


func send_request(payload: PackedByteArray) -> void:
	if _live():
		_rpc_request.rpc_id(1, payload)


@rpc("authority", "unreliable", "call_remote", CHANNEL_STATE)
func _rpc_snapshot(payload: PackedByteArray) -> void:
	bridge.receive_snapshot(payload)


@rpc("authority", "reliable", "call_remote", CHANNEL_STATE)
func _rpc_event(payload: PackedByteArray) -> void:
	bridge.receive_event(payload)


## The sender comes from the transport, never from the payload: a peer id inside a body is a
## claim, and this is a fact.
@rpc("any_peer", "unreliable", "call_remote", CHANNEL_STATE)
func _rpc_input(payload: PackedByteArray) -> void:
	bridge.receive_input(multiplayer.get_remote_sender_id(), payload)


@rpc("any_peer", "reliable", "call_remote", CHANNEL_STATE)
func _rpc_request(payload: PackedByteArray) -> void:
	bridge.receive_request(multiplayer.get_remote_sender_id(), payload)
