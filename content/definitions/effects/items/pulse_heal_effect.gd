class_name PulseHealEffect
extends AbilityEffect


## Passive: every interval seconds heals the target_count nearest wounded allies
## (including this unit) for max_hp_percent of this unit's Max HP.

@export_range(0.1, 3600.0, 0.1, "or_greater") var interval := 1.0
@export_range(1, 100, 1) var target_count := 3
@export_range(0.0, 100.0, 0.1) var max_hp_percent := 4.0


func apply(_source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		target.items.pulse_heals.append({
			"interval": interval,
			"remaining": interval,
			"targets": target_count,
			"max_hp_percent": max_hp_percent,
			"ability_id": ability.id,
			"effect_id": effect_id,
		})
