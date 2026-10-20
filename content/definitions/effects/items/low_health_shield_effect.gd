class_name LowHealthShieldEffect
extends AbilityEffect


## Passive, once per battle: dropping to health_threshold grants a shield for duration
## seconds and bonus HP regeneration while that shield still holds.

@export_range(0.0, 1.0, 0.01) var health_threshold := 0.4
@export_range(0.0, 100000.0, 1.0, "or_greater") var shield_amount := 600.0
@export_range(0.0, 3600.0, 0.1, "or_greater") var duration := 6.0
@export_range(0.0, 10000.0, 0.1, "or_greater") var regen_bonus := 30.0


func apply(_source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		target.items.low_hp_shields.append({
			"threshold": health_threshold,
			"shield": shield_amount,
			"duration": duration,
			"regen": regen_bonus,
			"used": false,
			"active": false,
			"ability_id": ability.id,
			"effect_id": effect_id,
		})
