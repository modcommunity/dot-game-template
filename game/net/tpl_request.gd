extends "tpl_event.gd"

## Everything a client asks the server for: the same shape as [TplEvent], the other way.
## Today that is one thing, READY -- "my scene is built, you may send me things now". Anything
## sent before it would land on a node that does not exist yet. It carries wants, never state.
##
## A separate type because a message's direction is fixed per type, and that is what stops a
## client sending another client an event.

const REQUEST := &"tpl.request"

## Append only, for the reason TplEvent.Kind is.
enum Ask { READY }


func _type_name() -> StringName:
	return REQUEST


func _validate() -> DotResult:
	if kind < 0 or kind >= Ask.size():
		return DotResult.fail(DotError.CODE_INVALID, "Unknown ask %d." % kind)
	return DotResult.success(true)
