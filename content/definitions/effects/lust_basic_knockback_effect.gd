class_name LustBasicKnockbackEffect
extends AbilityEffect


@export_range(1, 100, 1, "or_greater") var hits_required := 6
@export_range(0.0, 10000.0, 1.0, "or_greater") var knockback_distance := 80.0
@export_range(0.0, 3600.0, 0.1, "or_greater") var stun_duration := 0.6


func apply(source, _target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source):
		source.set_lust_basic_knockback(hits_required, knockback_distance, stun_duration, ability.id, effect_id)
