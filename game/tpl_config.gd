extends DotConfig

## This game's server tunables. Every exported field becomes a `tpl_<field>` cvar, a game.yml
## key, a `TPL_*` environment variable and a `--tpl-*` flag, and shows in dot-workbench.
## A pack may not declare a `class_name`, so TplGame loads this by preload.


## `@export_group` -> cfg file: `cfg/game/dot-game-template/config_<file>/game.yml`. A group missing here is refused at boot.
const CFG_FILES := {"Rules": "rules"}


## The binder every entry point uses (server scene, suites): [param config] layered, one cfg file per [constant CFG_FILES] entry.
static func make_binder(config: DotConfig, json_path := "") -> DotGameConfigBinder:
	var b := DotGameConfigBinder.create(config, "dot-game-template", "tpl", json_path)
	b.grouped = true
	b.group_files = CFG_FILES
	return b


func env_prefix() -> String:
	return "TPL_"


func cli_prefix() -> String:
	return "--tpl-"


@export_group("Rules")
## What one coin is worth.
@export_range(1, 1000, 1) var coin_value: int = 1

## Coins on the field beyond the arena's own number.
@export_range(0, 200, 1) var extra_coins: int = 0
