class_name BasicAttackLifestealEffect
extends AbilityEffect


## Passive: heals the holder for a percentage of the HP damage its basic attacks deal.
@export_range(0.0, 1000.0, 0.1, "or_greater") var lifesteal_percent := 50.0


func apply(_source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		target.add_passive_basic_lifesteal(lifesteal_percent, ability.id, effect_id)
