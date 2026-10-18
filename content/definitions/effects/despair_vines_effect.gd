class_name DespairVinesEffect
extends AbilityEffect


@export_range(1, 1000, 1, "or_greater") var target_count := 2
@export_range(0.0, 1000000.0, 0.1, "or_greater") var damage := 50.0
@export_range(0.1, 3600.0, 0.1, "or_greater") var duration := 5.0
@export_range(0.1, 3600.0, 0.1, "or_greater") var interval := 1.0


func can_apply(source, _target, _ability: AbilityDefinition) -> bool:
	return is_instance_valid(source) and source.session.has_enemy_target(source)


func apply(source, _target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source):
		source.session.apply_despair_vines(source, target_count, damage, duration, interval, ability.id, effect_id)
