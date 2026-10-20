class_name IsolationBonusEffect
extends AbilityEffect


## Passive: while no ally is within radius, damage is increased by damage_percent and
## damage taken changes by damage_taken_percent (negative = less damage).

@export_range(0.0, 10000.0, 1.0, "or_greater") var radius := 500.0
@export_range(0.0, 1000.0, 1.0, "or_greater") var damage_percent := 90.0
@export_range(-90.0, 0.0, 1.0) var damage_taken_percent := -45.0


func apply(_source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		var runtime: CombatantItemRuntime = target.items
		runtime.isolation_radius = radius
		runtime.isolation_damage_percent = damage_percent
		runtime.isolation_damage_taken_percent = damage_taken_percent
		runtime.isolation_ability_id = ability.id
