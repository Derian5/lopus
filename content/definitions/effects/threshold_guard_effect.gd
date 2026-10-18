class_name ThresholdGuardEffect
extends AbilityEffect


@export_range(0.0, 1.0, 0.01) var health_threshold := 0.3
@export_range(0.0, 10.0, 0.01, "or_greater") var shield_max_hp_multiplier := 0.3
@export_range(0.01, 100.0, 0.01, "or_greater") var armor_multiplier := 1.0
@export_range(0.0, 3600.0, 0.1, "or_greater") var duration := 10.0
@export_range(0.0, 3600.0, 0.1, "or_greater") var cooldown_seconds := 30.0


func apply(_source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		target.set_threshold_guard(health_threshold, shield_max_hp_multiplier, armor_multiplier, duration, cooldown_seconds, ability.id, effect_id)
