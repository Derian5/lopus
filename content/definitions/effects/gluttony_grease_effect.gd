class_name GluttonyGreaseEffect
extends AbilityEffect


@export_range(0.0, 100.0, 0.1) var miss_percent := 15.0
@export_range(0.1, 3600.0, 0.1, "or_greater") var duration := 4.0


func apply(source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		target.apply_gluttony_grease(miss_percent, duration, source, ability.id)
