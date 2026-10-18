class_name DespairSanctuaryEffect
extends AbilityEffect


@export_range(0.0, 1.0, 0.01) var health_threshold := 0.3
@export_range(0.0, 100.0, 0.1) var max_hp_heal_percent := 6.0
@export_range(0.1, 3600.0, 0.1, "or_greater") var duration := 4.0
@export_range(0.1, 3600.0, 0.1, "or_greater") var interval := 1.0


func can_apply(source, _target, _ability: AbilityDefinition) -> bool:
	return is_instance_valid(source) and source.session.has_despair_sanctuary_target(source, health_threshold)


func apply(source, _target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source):
		source.session.apply_despair_sanctuary(source, health_threshold, max_hp_heal_percent, duration, interval, ability.id, effect_id)
