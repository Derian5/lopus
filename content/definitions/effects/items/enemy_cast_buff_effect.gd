class_name EnemyCastBuffEffect
extends AbilityEffect


## Passive: whenever an enemy within radius uses an active ability, this unit gains a
## stack of status (stacking and duration come from the status definition).

@export_range(0.0, 10000.0, 1.0, "or_greater") var radius := 800.0
@export var status: StatusDefinition


func apply(_source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target) and status != null:
		target.items.cast_frenzies.append({"radius": radius, "status": status, "ability_id": ability.id})
