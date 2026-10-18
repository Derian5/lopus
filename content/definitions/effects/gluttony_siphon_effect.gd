class_name GluttonySiphonEffect
extends AbilityEffect


@export_range(0.0, 100000.0, 0.1, "or_greater") var damage := 100.0


func apply(source, target, ability: AbilityDefinition) -> void:
	if not is_instance_valid(source) or not is_instance_valid(target):
		return
	var dealt: float = target.take_damage(damage, source, ability.id, effect_id, true, false)
	if dealt > 0.0:
		source.receive_healing(dealt, source, ability.id, effect_id)
