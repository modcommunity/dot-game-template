extends DotGameWorkbenchSuite

## dot-game-template: the workbench over the config binder, one edit per profile set, the export and its cfg round trip.
## Run: godot --headless --path . res://examples/headless_workbench.tscn

const TplConfig := preload("../game/tpl_config.gd")


func _make_config() -> DotConfig:
	return TplConfig.new()


func _make_binder(config: DotConfig) -> DotGameConfigBinder:
	return TplConfig.make_binder(config)
