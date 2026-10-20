class_name AttackSpeedAuraEffect
extends AbilityEffect


@export_range(0.0, 10000.0, 1.0, "or_greater") var radius := 80.0
@export_range(0.0, 1.0, 0.01) var multiplier := 0.6


func apply(_source, target, _ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		if target.session != null:
			target.session.any_attack_speed_aura = true
		target.enemy_attack_speed_aura_radius = maxf(target.enemy_attack_speed_aura_radius, radius)
		target.enemy_attack_speed_aura_multiplier = minf(target.enemy_attack_speed_aura_multiplier, multiplier)
