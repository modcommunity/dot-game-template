extends DotConfig

## This game's server tunables. Every exported field becomes a `tpl_<field>` cvar, a key of
## `cfg/server/game/<game>/config/game.yml`, a `TPL_*` environment variable and a `--tpl-*`
## flag, and shows in dot-workbench, with no further code (dot-game's docs/config-binder.md).
## A delivered pack may not declare a `class_name`, so TplGame loads this by preload.


func env_prefix() -> String:
	return "TPL_"


func cli_prefix() -> String:
	return "--tpl-"


@export_group("Rules")
## What one coin is worth.
@export_range(1, 1000, 1) var coin_value: int = 1

## Coins on the field beyond the arena's own number.
@export_range(0, 200, 1) var extra_coins: int = 0
