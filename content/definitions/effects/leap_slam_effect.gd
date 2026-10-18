class_name LeapSlamEffect
extends AbilityEffect


@export_range(0.0, 100000.0, 0.1, "or_greater") var damage := 200.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var impact_radius := 200.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var knockback_distance := 150.0
@export_range(0.0, 3600.0, 0.1, "or_greater") var stun_duration := 2.0


func apply(source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source) and is_instance_valid(target):
		source.session.perform_leap_slam(source, target, damage, impact_radius, knockback_distance, stun_duration, ability.id, effect_id)
