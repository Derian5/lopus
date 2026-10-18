class_name MeleeRetaliationEffect
extends AbilityEffect


@export_range(0.0, 10000.0, 1.0, "or_greater") var radius := 400.0
@export_range(0.0, 100.0, 0.1, "or_greater") var damage_multiplier := 1.0


func apply(_source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		target.set_melee_retaliation(radius, damage_multiplier, ability.id, effect_id)
