class_name GluttonyDeathExplosionEffect
extends AbilityEffect


@export_range(0.0, 10000.0, 1.0, "or_greater") var radius := 250.0
@export_range(0.0, 100000.0, 0.1, "or_greater") var damage := 200.0


func apply(source, _target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source):
		source.set_gluttony_death_explosion(radius, damage, ability.id, effect_id)
