class_name GluttonyLifestealAuraEffect
extends AbilityEffect


@export_range(0.0, 10000.0, 1.0, "or_greater") var radius := 250.0
@export_range(0.0, 100.0, 0.1) var lifesteal_percent := 8.0


func apply(source, _target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source):
		source.set_gluttony_lifesteal_aura(radius, lifesteal_percent, ability.id, effect_id)
