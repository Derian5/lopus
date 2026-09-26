class_name CleanseEffect
extends AbilityEffect


func apply(source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		target.remove_random_negative_status(source, ability.id, effect_id)


func can_apply(_source, target, _ability: AbilityDefinition) -> bool:
	return is_instance_valid(target) and target.has_negative_status()
