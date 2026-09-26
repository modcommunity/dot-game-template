extends RefCounted

## Where this game's own files are, wherever this copy of it happens to live.
##
## [b]A delivered game does not live at res://.[/b] A published pack mounts at
## [code]res://dot_cloud/<owner>/<repo>/<version>/[/code], so an absolute "res://..." naming one
## of this game's files resolves against the HOST instead -- another game's file, or nothing.
## A script knows where it is, though: its [code]resource_path[/code] is the mounted path. So
## the root is this script's directory with [code]game/[/code] taken off, and every path hangs
## off that. Built into a project, [method rebase] returns exactly what it was given.
##
## [b]Rebase where the path is DEFINED[/b] ([code]static var X := TplPaths.rebase("res://...")[/code]),
## never at each use: the second is one new call site away from a file that does not load in a
## delivered game and loads perfectly here. [code]tools/check.sh[/code] refuses the bare form.

const _SELF := preload("tpl_paths.gd")


## This game's content root: `res://` in a build, the mount prefix in a pack.
static func root() -> String:
	# Through [Resource]: a preloaded script is typed as its own class, which does not expose
	# `resource_path` to the parser. The cast costs nothing.
	var here: Resource = _SELF
	return here.resource_path.get_base_dir().get_base_dir()


## Moves one `res://` path onto [method root]. Anything else comes back untouched.
static func rebase(path: String) -> String:
	return rebase_onto(path, root())


## [method rebase] against a root given rather than discovered, so the mounted case can be
## tested from a build -- where [method root] is `res://` and every property of [method rebase]
## that matters in a pack would otherwise be a tautology.
static func rebase_onto(path: String, here: String) -> String:
	if not path.begins_with("res://"):
		return path

	# Idempotent. The publisher rewrites every res:// string inside a .tscn or .tres onto the
	# mount before it signs the pack, and does NOT rewrite the ones inside a .gd. So a delivered
	# game holds both kinds, and a path that is already under the mount must be left alone --
	# rebasing it twice gives res://dot_cloud/x/1/dot_cloud/x/1/..., which does not load.
	if path.begins_with(here):
		return path

	return here.path_join(path.substr(6))
