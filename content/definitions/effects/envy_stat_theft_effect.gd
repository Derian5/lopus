class_name EnvyStatTheftEffect
extends AbilityEffect


@export_range(0.0, 100.0, 1.0) var steal_percent := 10.0
@export_range(0.0, 3600.0, 0.1, "or_greater") var duration := 12.0


func can_apply(source, _target, _ability: AbilityDefinition) -> bool:
	return is_instance_valid(source) and source.session.has_envy_stat_theft_targets(source)


func apply(source, _target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source):
		source.session.apply_envy_stat_theft(source, steal_percent, duration, ability.id, effect_id)
