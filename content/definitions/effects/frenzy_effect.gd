class_name FrenzyEffect
extends AbilityEffect


@export_range(0.01, 100.0, 0.01, "or_greater") var attack_speed_multiplier := 2.0
@export_range(0.0, 3600.0, 0.1, "or_greater") var duration := 7.0


func apply(_source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		target.apply_frenzy(attack_speed_multiplier, duration, ability.id, effect_id)


func can_apply(source, _target, _ability: AbilityDefinition) -> bool:
	return is_instance_valid(source) and source.can_activate_frenzy()
