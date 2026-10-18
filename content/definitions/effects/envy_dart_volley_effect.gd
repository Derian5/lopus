class_name EnvyDartVolleyEffect
extends AbilityEffect


@export_range(0.0, 1000000.0, 0.1, "or_greater") var damage := 12.0
@export_range(0.0, 100.0, 1.0) var movement_slow_percent := 30.0
@export_range(1, 100, 1, "or_greater") var max_targets := 3


func can_apply(source, _target, _ability: AbilityDefinition) -> bool:
	return is_instance_valid(source) and source.session.has_enemy_target(source)


func apply(source, _target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source):
		source.session.launch_envy_darts(source, damage, movement_slow_percent, max_targets, ability.id, effect_id)
