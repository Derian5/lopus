class_name AbilityEffect
extends Resource


@export var effect_id: StringName


func apply(_source, _target, _ability: AbilityDefinition) -> void:
	pass


func can_apply(_source, _target, _ability: AbilityDefinition) -> bool:
	return true
