extends DotGameCheckSuite

## TplConfig through DotGameConfigBinder: fields, cvars, strict refusal, the diff, layers in a fresh process and the shipped cfg files.
## Run: godot --headless --path . res://examples/headless_config.tscn

const TplConfig := preload("../game/tpl_config.gd")
const CHECKS := 13
const ROOT := "user://tpl_cfgtest"
const GAME := "dot-game-template"


func _ready() -> void:
	DotLog.set_level(DotLog.Level.FATAL)
	_run.call_deferred()


func _run() -> void:
	if OS.get_cmdline_user_args().has("--probe"):
		_probe()
		return
	print("dot-game-template: config binder")
	var config := TplConfig.new()
	var binder := TplConfig.make_binder(config)
	binder.strict = true
	_check(binder.load_layers().ok, "defaults load")
	_check(binder.diff().is_empty(), "no diff at the code defaults")
	var keys := PackedStringArray()
	for e: Dictionary in binder.schema():
		keys.append(e["key"])
	for k in ["coin_value", "extra_coins"]:
		_check(keys.has(k), "%s is exposed" % k)

	var console := DotConsole.new()
	add_child(console)
	binder.bind_cvars(console.cvar, DotConVar.FLAG_ARCHIVE, console.has_name)
	console.set_cvar("tpl_coin_value", "7")
	_check(config.coin_value == 7 and binder.source_of("coin_value") == "cvar", "a cvar writes the field")
	_check(binder.diff_yaml().contains("coin_value: 7"), "the diff names the edit")

	var bad := FileAccess.open("user://tpl_config_bad.json", FileAccess.WRITE)
	bad.store_string('{"no_such_field": 1}')
	bad.close()
	var strict := TplConfig.make_binder(TplConfig.new(), "user://tpl_config_bad.json")
	strict.strict = true
	_check(not strict.load_layers().ok, "strict: an unknown key is refused")
	DirAccess.remove_absolute("user://tpl_config_bad.json")

	_layers()
	_templates(binder)
	console.free()
	_report(CHECKS)


## Child process: loads the layers strictly over the test root and prints what the live config holds.
func _probe() -> void:
	var config := TplConfig.new()
	var binder := TplConfig.make_binder(config)
	binder.strict = true
	binder.roots = PackedStringArray([ProjectSettings.globalize_path(ROOT)])
	var loaded := binder.load_layers()
	print("PROBE ok=%s coin=%s coin_src=%s extra=%s extra_src=%s" % [loaded.ok, config.coin_value,
		binder.source_of("coin_value"), config.extra_coins, binder.source_of("extra_coins")])
	get_tree().quit(0)


func _write(rel: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ROOT.path_join(rel).get_base_dir())
	var f := FileAccess.open(ROOT.path_join(rel), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _child() -> String:
	var out: Array = []
	var _code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://examples/headless_config.tscn", "--", "--probe", "--tpl-extra-coins=9"], out, true)
	return "".join(PackedStringArray(out))


## A value in a cfg file, the environment and argv each reaches the live config, later layers win, a wrong key is refused.
func _layers() -> void:
	var file := "game/%s/config_rules/game.yml" % GAME
	_write(file, "coin_value: 3\nextra_coins: 2\n")
	var alone := _child()
	_check(alone.contains("PROBE ok=true") and alone.contains("coin=3") and alone.contains("coin_src=yml"), "a cfg file reaches the live config in a fresh process", alone.right(300))
	OS.set_environment("TPL_COIN_VALUE", "5")
	var text := _child()
	OS.unset_environment("TPL_COIN_VALUE")
	_check(text.contains("extra=9") and text.contains("extra_src=argv"), "argv beats the cfg file")
	_check(text.contains("coin=5") and text.contains("coin_src=env"), "the environment beats the cfg file")
	_write(file, "no_such_key: 1\n")
	_check(_child().contains("PROBE ok=false"), "strict: an unknown key in the file is refused")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ROOT.path_join(file)))


## The shipped cfg files hold every key, in step with TplConfig.
func _templates(binder: DotGameConfigBinder) -> void:
	var files := binder.template_files()
	_check(files.size() == 1, "one shipped cfg file", str(files.size()))
	var stale := PackedStringArray()
	for path: String in files:
		if not FileAccess.file_exists("res://" + path) or FileAccess.get_file_as_string("res://" + path) != files[path]:
			stale.append(path)
	_check(stale.is_empty(), "the shipped files match the config (run addons/dot_game/qa/dot_game_cfg_templates.gd)", ",".join(stale))
