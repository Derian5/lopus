class_name SmokeBombEffect
extends AbilityEffect


@export_range(0.0, 10000.0, 1.0, "or_greater") var radius := 200.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var activation_enemy_radius := 100.0
@export_range(0.0, 3600.0, 0.1, "or_greater") var duration := 6.0
@export_range(0.0, 100.0, 0.1) var dodge_percent := 20.0


func apply(source, _target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source):
		source.session.create_smoke_zone(source, radius, duration, dodge_percent / 100.0, ability.id, effect_id)


func can_apply(source, _target, _ability: AbilityDefinition) -> bool:
	return is_instance_valid(source) and source.session.has_enemy_in_radius(source, activation_enemy_radius)
