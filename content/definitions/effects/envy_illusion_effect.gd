class_name EnvyIllusionEffect
extends AbilityEffect


@export_range(0.0, 1000.0, 1.0, "or_greater") var stat_percent := 20.0
@export_range(1, 100, 1, "or_greater") var max_active_summons := 100


func can_apply(source, _target, ability: AbilityDefinition) -> bool:
	return is_instance_valid(source) and source.session.can_create_envy_illusion(source, ability.id, effect_id, max_active_summons)


func apply(source, _target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source):
		source.session.create_envy_illusion(source, stat_percent, ability.id, effect_id, max_active_summons)
