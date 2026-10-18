class_name EnvyExecuteEffect
extends AbilityEffect


@export_range(0.0, 1.0, 0.01) var health_threshold := 0.16


func can_apply(source, _target, _ability: AbilityDefinition) -> bool:
	return is_instance_valid(source) and source.session.has_envy_execute_target(source, health_threshold)


func apply(source, _target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source):
		source.session.execute_envy_target(source, health_threshold, ability.id, effect_id)
