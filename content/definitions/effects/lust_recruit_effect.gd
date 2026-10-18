class_name LustRecruitEffect
extends AbilityEffect


@export_range(0.0, 1000000.0, 1.0, "or_greater") var hp_threshold := 100.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var radius := 250.0


func can_apply(source, _target, _ability: AbilityDefinition) -> bool:
	return is_instance_valid(source) and source.session.has_lust_recruit_target(source, radius, hp_threshold)


func apply(source, _target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source):
		source.session.recruit_lust_target(source, radius, hp_threshold, ability.id, effect_id)
