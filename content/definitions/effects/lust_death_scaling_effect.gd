class_name LustDeathScalingEffect
extends AbilityEffect


@export_range(0.0, 1000.0, 1.0, "or_greater") var percent_per_death := 6.0


func apply(source, _target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source):
		source.set_lust_death_scaling(percent_per_death, ability.id)
