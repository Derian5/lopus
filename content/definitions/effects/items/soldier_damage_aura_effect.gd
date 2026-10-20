class_name SoldierDamageAuraEffect
extends AbilityEffect


## Passive aura: allied Soldiers within radius deal soldier_percent more damage, or
## veteran_percent if their Veterancy is at least veteran_min_level. Does not stack.

@export_range(0.0, 10000.0, 1.0, "or_greater") var radius := 600.0
@export_range(0.0, 1000.0, 1.0, "or_greater") var soldier_percent := 25.0
@export_range(0.0, 1000.0, 1.0, "or_greater") var veteran_percent := 40.0
@export_range(0, 100, 1) var veteran_min_level := 1


func apply(_source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		if target.session != null:
			target.session.any_soldier_damage_aura = true
		var runtime: CombatantItemRuntime = target.items
		runtime.soldier_aura_radius = radius
		runtime.soldier_aura_percent = soldier_percent
		runtime.veteran_aura_percent = veteran_percent
		runtime.veteran_min_level = veteran_min_level
		runtime.soldier_aura_ability_id = ability.id
