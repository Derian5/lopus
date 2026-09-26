class_name LastStandEffect
extends AbilityEffect


@export_range(0.0, 3600.0, 0.1, "or_greater") var duration := 3.0


func apply(_source, target, _ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		target.last_stand_aura_duration = maxf(target.last_stand_aura_duration, duration)
