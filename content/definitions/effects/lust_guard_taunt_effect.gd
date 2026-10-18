class_name LustGuardTauntEffect
extends AbilityEffect


@export_range(0.0, 10000.0, 1.0, "or_greater") var activation_radius := 150.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var ally_radius := 250.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var armor_bonus := 20.0
@export_range(0.0, 3600.0, 0.1, "or_greater") var duration := 5.0


func can_apply(source, _target, _ability: AbilityDefinition) -> bool:
	return is_instance_valid(source) and source.session.can_apply_lust_guard(source, activation_radius, ally_radius)


func apply(source, _target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source):
		source.session.apply_lust_guard(source, activation_radius, ally_radius, armor_bonus, duration, ability.id, effect_id)
