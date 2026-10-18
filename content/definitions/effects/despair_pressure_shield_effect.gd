class_name DespairPressureShieldEffect
extends AbilityEffect


@export_range(0.0, 100000.0, 0.1, "or_greater") var shield_amount := 200.0
@export_range(0.01, 1.0, 0.01) var attack_speed_multiplier := 1.0 / 3.0
@export_range(0.1, 3600.0, 0.1, "or_greater") var duration := 5.0


func can_apply(source, _target, _ability: AbilityDefinition) -> bool:
	return is_instance_valid(source) and source.session.has_despair_pressure_target(source)


func apply(source, _target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source):
		source.session.apply_despair_pressure_shield(source, shield_amount, attack_speed_multiplier, duration, ability.id, effect_id)
