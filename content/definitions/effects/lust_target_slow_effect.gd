class_name LustTargetSlowEffect
extends AbilityEffect


@export_range(0.0, 99.0, 1.0) var slow_percent := 20.0


func apply(source, _target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source):
		source.set_lust_target_slow(slow_percent, ability.id)
