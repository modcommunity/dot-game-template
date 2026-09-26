extends "suite.gd"

const TplPaths := preload("../game/tpl_paths.gd")

## The rules a game must keep to be delivered as a pack, checked against this repository.
##
##     godot --headless --path . res://examples/headless_pack.tscn
##
## A published game is mounted at res://dot_cloud/<owner>/<repo>/<version>/, where a
## `class_name` is never registered and a bare "res://<your folder>/..." names the host's file,
## not yours. Both break without an error, so both are refused here -- by scanners that must
## first find a planted violation, because a blind scanner reports a clean tree.

## Folders that never travel in a pack (dot-ci's package.sh drops them).
const NOT_SHIPPED := ["addons", "examples", "tools", "screenshots"]

const MOUNT := "res://dot_cloud/you/dot-game-template/1.0.0"


func _ready() -> void:
	checks = 12
	print("dot-game-template: what a delivered pack may contain")
	_test_the_scanners_see()
	_test_this_repository()
	_test_rebase()
	_test_the_descriptor()
	finish()


func _test_the_scanners_see() -> void:
	section("the scanners find a planted violation")
	check(class_names_in("class_name TplThing\nextends Node\n").size() == 1, "a class_name")
	var planted := "\n".join([
		'var bad := "res://game/thing.tscn"',
		'static var good := TplPaths.rebase("res://game/thing.tscn")',
		'# "res://game/in_a_comment.tscn" is prose',
		'var host := "res://addons/dot_core/thing.gd"',
	])
	var found := bare_paths_in(planted, PackedStringArray(["game"]))
	check(found.size() == 1 and found[0].contains("bad"),
		"exactly the bare path to one of the game's own folders (%d)" % found.size())
	done()


func _test_this_repository() -> void:
	section("this repository")
	var owned := _owned_folders()
	check(owned.has("game") and owned.has("scenes"), "the shipped folders are %s" % [owned])
	var names := PackedStringArray()
	var bare := PackedStringArray()
	for path in _scripts("res://"):
		var source := FileAccess.get_file_as_string(path)
		for hit in class_names_in(source):
			names.append("%s: %s" % [path, hit])
		if not path.trim_prefix("res://").get_slice("/", 0) in NOT_SHIPPED:
			for hit in bare_paths_in(source, owned):
				bare.append("%s: %s" % [path, hit])
	check(names.is_empty(), "no script declares a class_name %s" % [names])
	check(bare.is_empty(), "no shipped script names its own files by a bare res:// path %s" % [bare])
	done()


func _test_rebase() -> void:
	section("TplPaths.rebase")
	check(TplPaths.root() == "res://", "in this project the root is res://")
	var moved := TplPaths.rebase_onto("res://scenes/tpl_client.tscn", MOUNT)
	check(moved == MOUNT + "/scenes/tpl_client.tscn", "in a pack a path moves under the mount")
	check(TplPaths.rebase_onto(moved, MOUNT) == moved, "and a path already there is left alone")
	check(TplPaths.rebase_onto("user://save.json", MOUNT) == "user://save.json", "user:// is never moved")
	done()


func _test_the_descriptor() -> void:
	section("game.yml")
	var fields := {}
	for line in FileAccess.get_file_as_string("res://game.yml").split("\n"):
		if not line.begins_with("#") and line.contains(": "):
			fields[line.get_slice(": ", 0)] = line.get_slice(": ", 1).strip_edges()
	var missing := PackedStringArray()
	for key in ["scene", "client_scene", "module"]:
		var path := str(fields.get(key, ""))
		if path == "" or path.contains("://") or not FileAccess.file_exists("res://" + path):
			missing.append(key)
	check(missing.is_empty(), "scene, client_scene and module are relative and exist %s" % [missing])
	check(fields.has("content_id") and fields.has("version") and str(fields.get("kind")) == "pack",
		"and content_id, version and kind are there for the installer to stamp")
	done()


## Every `class_name` line in [param source].
static func class_names_in(source: String) -> PackedStringArray:
	var out := PackedStringArray()
	for line in source.split("\n"):
		if line.strip_edges().begins_with("class_name "):
			out.append(line.strip_edges())
	return out


## Every "res://<folder>..." in [param source] whose folder is one of [param owned], outside
## comments and outside a `...Paths.rebase("res://...")` call.
static func bare_paths_in(source: String, owned: PackedStringArray) -> PackedStringArray:
	var wrapped := RegEx.create_from_string('[A-Za-z0-9_]*Paths\\.rebase\\("res://[^"]*"\\)')
	var literal := RegEx.create_from_string('"res://([^/"]+)')
	var out := PackedStringArray()
	for line in source.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		for hit in literal.search_all(wrapped.sub(line, "", true)):
			if hit.get_string(1) in owned:
				out.append(line.strip_edges())
	return out


## The top-level folders a pack of this repository carries.
func _owned_folders() -> PackedStringArray:
	var out := PackedStringArray()
	for name in DirAccess.get_directories_at("res://"):
		if not name.begins_with(".") and not name in NOT_SHIPPED:
			out.append(name)
	return out


## Every .gd in the repository, skipping the linked addons and anything hidden.
func _scripts(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for name in DirAccess.get_directories_at(dir):
		if not name.begins_with(".") and not (dir == "res://" and name == "addons"):
			out.append_array(_scripts(dir.path_join(name)))
	for name in DirAccess.get_files_at(dir):
		if name.ends_with(".gd"):
			out.append(dir.path_join(name))
	return out
