class_name ExecuteOnHitEffect
extends AbilityEffect


## Passive: a basic attack that leaves a non-boss enemy below health_threshold kills it.
## Each execution adds gold_per_execute after a won battle, up to max_gold.

@export_range(0.0, 1.0, 0.01) var health_threshold := 0.2
@export_range(0, 10000, 1, "or_greater") var gold_per_execute := 15
@export_range(0, 100000, 1, "or_greater") var max_gold := 90


func apply(_source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		var runtime: CombatantItemRuntime = target.items
		runtime.execute_threshold = maxf(runtime.execute_threshold, health_threshold)
		runtime.execute_gold = gold_per_execute
		runtime.execute_gold_cap = max_gold
		runtime.execute_ability_id = ability.id
		runtime.execute_effect_id = effect_id
