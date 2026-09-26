extends DotNetInput

## One tick of a player's intent: the ONLY thing a client sends about itself.
##
## Clients send inputs, never state. A client that could send its position could send any
## position; one that sends "I am pushing up-left" can only ever move as fast as the rules let
## it, because the server runs the rules.

## Where they are trying to go, length 0..1.
var move: Vector2 = Vector2.ZERO


## Eight bits per axis. The client predicts with the DECODED value (see TplBridge.client_tick),
## so the server and the client simulate the same number and never disagree about it.
func _write(writer: DotNetWriter) -> void:
	writer.write_float_range(move.x, -1.0, 1.0, 8)
	writer.write_float_range(move.y, -1.0, 1.0, 8)


func _read(reader: DotNetReader) -> void:
	move = Vector2(reader.read_float_range(-1.0, 1.0, 8), reader.read_float_range(-1.0, 1.0, 8))


## Runs on the server after decoding. Each axis is bounded by the quantisation; their
## LENGTH is not -- (1, 1) is two legal values and 41% more speed than anybody else.
func _sanitise() -> void:
	move = move.limit_length(1.0)


func _equals(other: DotNetInput) -> bool:
	return other != null and other.get_script() == get_script() \
		and (other.get("move") as Vector2).is_equal_approx(move)
