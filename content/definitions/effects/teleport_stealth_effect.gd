class_name TeleportStealthEffect
extends AbilityEffect


@export_range(0.0, 3600.0, 0.1, "or_greater") var duration := 3.0


func apply(source, _target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source):
		source.session.teleport_to_farthest_enemy(source)
		source.apply_stealth(duration, ability.id, effect_id)


func can_apply(source, _target, _ability: AbilityDefinition) -> bool:
	return is_instance_valid(source) and source.session.has_enemy_target(source)
