class_name ApplyStatusEffect
extends AbilityEffect


@export var status: StatusDefinition


func apply(source, target, ability: AbilityDefinition) -> void:
	if status != null and is_instance_valid(target):
		target.apply_status(status, source, ability.id)
