class_name SacrificeSoldierEffect
extends AbilityEffect


@export_range(0.0, 10000.0, 1.0, "or_greater") var radius := 160.0
@export_range(0.0, 100.0, 0.1, "or_greater") var stat_gain_percent := 10.0


func apply(source, _target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source):
		source.session.sacrifice_random_soldier(source, radius, stat_gain_percent, ability.id, effect_id)


func can_apply(source, _target, _ability: AbilityDefinition) -> bool:
	return is_instance_valid(source) and source.session.has_sacrifice_target(source, radius)
