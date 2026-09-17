class_name DamageEffect
extends AbilityEffect


@export_range(0.0, 100000.0, 0.1, "or_greater") var amount := 10.0


func apply(source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		target.take_damage(amount, source, ability.id, effect_id)
