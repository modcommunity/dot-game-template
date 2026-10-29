extends RefCounted

## Where this game's own files are, wherever this copy of it happens to live.
## A pack mounts at res://dot_cloud/<owner>/<repo>/<version>/, so an absolute "res://..." names the HOST's file; a script's
## `resource_path` is the mounted path, hence [method rebase]. Rebase where a path is DEFINED, never at each use.

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
	# Idempotent: the publisher already moved every res:// inside a .tscn or .tres onto the
	# mount (not inside a .gd), and a path moved twice does not load.
	if path.begins_with(here):
		return path
	return here.path_join(path.substr(6))
