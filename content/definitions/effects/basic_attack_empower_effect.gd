class_name BasicAttackEmpowerEffect
extends AbilityEffect


@export_range(0.0, 100.0, 0.1, "or_greater") var lifesteal_percent := 50.0
@export_range(0.01, 10.0, 0.01, "or_greater") var size_multiplier := 1.5
@export_range(0.0, 3600.0, 0.1, "or_greater") var duration := 6.0


func apply(_source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		target.add_basic_attack_empowerment(lifesteal_percent, size_multiplier, duration, ability.id, effect_id)
