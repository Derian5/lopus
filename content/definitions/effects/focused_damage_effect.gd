class_name FocusedDamageEffect
extends AbilityEffect


@export_range(0.0, 100000.0, 0.1, "or_greater") var damage_per_stack := 5.0
@export_range(0.0, 3600.0, 0.1, "or_greater") var stack_duration := 7.0


func apply(_source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		target.set_focused_damage(damage_per_stack, stack_duration, ability.id, effect_id)
