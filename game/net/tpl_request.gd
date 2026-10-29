extends "tpl_event.gd"

## Everything a client asks the server for: the shape of [TplEvent], the other way.
## Today that is READY, "my scene is built, you may send me things now"; wants, never state.
## A separate type because direction is fixed per type, which stops a client sending an event.

const REQUEST := &"tpl.request"

## Append only, for the reason TplEvent.Kind is.
enum Ask { READY }



## Whether every [enum Ask] fits in the [constant KIND_BITS] this shares with [TplEvent].
static func asks_fit() -> bool:
	return int(Ask.values().max()) < (1 << KIND_BITS)


func _type_name() -> StringName:
	return REQUEST


func _validate() -> DotResult:
	if kind < 0 or kind >= Ask.size():
		return DotResult.fail(DotError.CODE_INVALID, "Unknown ask %d." % kind)
	return DotResult.success(true)
