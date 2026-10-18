class_name DespairAttackSlowEffect
extends AbilityEffect


@export_range(1, 1000, 1, "or_greater") var max_stacks := 2
@export_range(0.0, 80.0, 0.1) var attack_speed_reduction_per_stack := 10.0
@export_range(0.0, 80.0, 0.1) var maximum_reduction_percent := 80.0


func apply(source, _target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source):
		source.set_despair_attack_slow(max_stacks, attack_speed_reduction_per_stack, maximum_reduction_percent, ability.id, effect_id)
