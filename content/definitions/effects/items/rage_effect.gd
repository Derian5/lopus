class_name RageEffect
extends AbilityEffect


## Passive: damage taken builds Rage (1 point per damage_per_point). At points_required
## Rage is spent and status is applied (no Rage builds while it is active).

@export_range(0.1, 100000.0, 0.1, "or_greater") var damage_per_point := 15.0
@export_range(1.0, 10000.0, 1.0, "or_greater") var points_required := 40.0
@export var status: StatusDefinition


func apply(_source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target) and status != null:
		var runtime: CombatantItemRuntime = target.items
		runtime.rage_damage_per_point = damage_per_point
		runtime.rage_points_required = points_required
		runtime.rage_status = status
		runtime.rage_ability_id = ability.id
