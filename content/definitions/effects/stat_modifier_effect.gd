class_name StatModifierEffect
extends AbilityEffect


@export var modifier: StatModifier
@export_range(0.0, 3600.0, 0.1, "or_greater") var duration := 5.0


func apply(source, target, ability: AbilityDefinition) -> void:
	if modifier != null and is_instance_valid(target):
		target.add_temporary_modifier(modifier, duration, source, ability.id, effect_id)
