extends DotNetMessage

## Everything the server tells a client that is not a snapshot: who you are, where the coins
## are, who arrived and who left. A kind and a body, so a new kind is one line here and one
## handler in TplBridge rather than a new message type.

const NAME := &"tpl.event"

## [b]Append only.[/b] The number IS the wire: a kind inserted in the middle renumbers every
## kind after it, and an older client reads a COIN as a SPAWN. A client older than a new kind
## drops it (see [method _validate]).
enum Kind { HELLO, COINS, COIN, SPAWN, DESPAWN }

const KIND_BITS := 4
const MAX_BODY := 2048

var kind: int = 0
var body: PackedByteArray = PackedByteArray()


## Both arguments default because the registry decodes with a bare `new()`. This file must not
## preload itself: a DotNetMessage script that does leaks every script at exit on Godot 4.7.2.
func _init(p_kind: int = 0, p_body: PackedByteArray = PackedByteArray()) -> void:
	kind = p_kind
	body = p_body


func _type_name() -> StringName:
	return NAME


func _write(writer: DotNetWriter) -> void:
	writer.write_uint(kind, KIND_BITS)
	writer.write_bytes(body)


func _read(reader: DotNetReader) -> void:
	kind = reader.read_uint(KIND_BITS)
	body = reader.read_bytes(MAX_BODY)


func _validate() -> DotResult:
	if kind < 0 or kind >= Kind.size():
		return DotResult.fail(DotError.CODE_INVALID, "Unknown event kind %d." % kind)
	return DotResult.success(true)
