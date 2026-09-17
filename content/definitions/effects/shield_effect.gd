class_name ShieldEffect
extends AbilityEffect


@export_range(0.0, 100000.0, 0.1, "or_greater") var amount := 10.0
@export_range(0.0, 3600.0, 0.1, "or_greater") var duration := 5.0


func apply(source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		target.add_shield(amount, duration, source, ability.id, effect_id)
