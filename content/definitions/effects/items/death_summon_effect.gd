class_name DeathSummonEffect
extends AbilityEffect


## Passive: when an enemy dies within radius there is a chance_percent chance to raise
## summoned_unit at its corpse for lifetime seconds (max_active_summons at once).

@export var summoned_unit: EnemyDefinition
@export_range(0.0, 10000.0, 1.0, "or_greater") var radius := 400.0
@export_range(0.0, 100.0, 1.0) var chance_percent := 50.0
@export_range(0.1, 3600.0, 0.1, "or_greater") var lifetime := 20.0
@export_range(1, 100, 1) var max_active_summons := 6


func apply(_source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target) and summoned_unit != null:
		target.items.death_summons.append({
			"unit": summoned_unit,
			"radius": radius,
			"chance": chance_percent,
			"lifetime": lifetime,
			"max_active": max_active_summons,
			"ability_id": ability.id,
			"effect_id": effect_id,
		})
