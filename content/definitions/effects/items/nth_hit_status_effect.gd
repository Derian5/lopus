class_name NthHitStatusEffect
extends AbilityEffect


## Passive: every hits_required-th successful basic attack applies the status.

@export_range(1, 100, 1) var hits_required := 3
@export var status: StatusDefinition


func apply(_source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target) and status != null:
		target.items.nth_hit_statuses.append({"hits_required": hits_required, "status": status, "count": 0, "ability_id": ability.id})
