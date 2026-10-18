class_name OnHitStatusEffect
extends AbilityEffect


## Passive: every successful basic attack applies the status to the target.
## Stacking follows the status definition, so units sharing one status id share
## its stack cap on a target (for example several Warriors shredding armor).
@export var status: StatusDefinition


func apply(_source, target, ability: AbilityDefinition) -> void:
	if status != null and is_instance_valid(target):
		target.add_on_hit_status(status, ability.id)
