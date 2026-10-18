class_name AttackReflectEffect
extends AbilityEffect


@export_range(0.0, 100.0, 0.1, "or_greater") var reflect_percent := 0.0


func apply(_source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		target.set_attack_reflection(reflect_percent, ability.id, effect_id)
