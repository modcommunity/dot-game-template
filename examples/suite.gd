extends Node

## What every suite here shares. A script error aborts its section silently and the run goes
## on, so a suite counts sections that finished AND the checks made, and fails if either is
## short. Set [member checks] to the number your suite makes.

var checks: int = 0

var _passed := 0
var _failed := 0
var _entered := 0
var _completed := 0


func section(title: String) -> void:
	_entered += 1
	print("\n" + title)


func done() -> void:
	_completed += 1


func check(condition: bool, what: String) -> bool:
	if condition:
		_passed += 1
	else:
		_failed += 1
	print("  %s  %s" % ["ok  " if condition else "FAIL", what])
	return condition


func finish() -> void:
	print("")
	check(_completed == _entered, "every section ran to its last line (%d of %d)" % [_completed, _entered])
	check(_passed + _failed == checks, "every check ran (%d of %d)" % [_passed + _failed, checks])
	print("%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
