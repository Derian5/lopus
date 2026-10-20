class_name OnHitStackTriggerEffect
extends AbilityEffect


## Passive: each successful basic attack adds a stack of stack_status to the target.
## At stacks_required the stacks are consumed and trigger_status is applied. The
## same target cannot be triggered again for per_target_cooldown seconds.

@export var stack_status: StatusDefinition
@export_range(1, 100, 1) var stacks_required := 3
@export var trigger_status: StatusDefinition
@export_range(0.0, 3600.0, 0.1, "or_greater") var per_target_cooldown := 8.0


func apply(_source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target) and stack_status != null and trigger_status != null:
		target.items.stack_triggers.append({
			"stack_status": stack_status,
			"stacks_required": stacks_required,
			"trigger_status": trigger_status,
			"per_target_cooldown": per_target_cooldown,
			"cooldowns": {},
			"ability_id": ability.id,
		})
