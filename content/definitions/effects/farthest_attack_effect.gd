class_name FarthestAttackEffect
extends AbilityEffect


@export_range(0.0, 10000.0, 1.0, "or_greater") var attack_range_bonus := 50.0


func apply(_source, target, _ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		target.basic_attack_range_bonus += attack_range_bonus
		target.targets_farthest_enemy = true
