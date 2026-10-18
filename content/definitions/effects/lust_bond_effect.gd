class_name LustBondEffect
extends AbilityEffect


@export_range(0.0, 100.0, 1.0) var lifesteal_percent := 20.0
@export_range(0.01, 100.0, 0.1, "or_greater") var attack_speed_multiplier := 1.4


func apply(source, _target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source):
		source.prepare_lust_bond(lifesteal_percent, attack_speed_multiplier, ability.id, effect_id)
