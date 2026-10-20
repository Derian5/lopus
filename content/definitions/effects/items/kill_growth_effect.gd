class_name KillGrowthEffect
extends AbilityEffect


## Passive: each enemy this unit kills permanently adds max_hp_per_kill Max HP for the
## rest of the run (up to max_total across all battles) and heals heal_percent of Max HP.

@export_range(0.0, 10000.0, 1.0, "or_greater") var max_hp_per_kill := 15.0
@export_range(0.0, 100000.0, 1.0, "or_greater") var max_total := 500.0
@export_range(0.0, 100.0, 1.0) var heal_percent := 20.0


func apply(_source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		var runtime: CombatantItemRuntime = target.items
		runtime.kill_growth_max_hp = max_hp_per_kill
		runtime.kill_growth_cap = max_total
		runtime.kill_growth_existing = float(target.snapshot.permanent_gains.get(ability.id, 0.0))
		runtime.kill_growth_heal_percent = heal_percent
		runtime.kill_growth_ability_id = ability.id
