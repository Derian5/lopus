class_name GluttonyDamageAuraEffect
extends AbilityEffect


@export_range(0.0, 10000.0, 1.0, "or_greater") var radius := 200.0
@export_range(0.0, 100000.0, 0.1, "or_greater") var damage := 10.0
@export_range(0.1, 3600.0, 0.1, "or_greater") var interval := 1.0


func apply(source, _target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source):
		source.set_gluttony_damage_aura(radius, damage, interval, ability.id, effect_id)
