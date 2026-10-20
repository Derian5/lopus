class_name DamageRedirectEffect
extends AbilityEffect


## Passive: redirect_percent of enemy damage aimed at allies within radius is taken by
## this unit instead; it heals for heal_percent of the damage it absorbs this way.

@export_range(0.0, 10000.0, 1.0, "or_greater") var radius := 400.0
@export_range(0.0, 100.0, 1.0) var redirect_percent := 40.0
@export_range(0.0, 1000.0, 1.0, "or_greater") var heal_percent := 25.0


func apply(_source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		var runtime: CombatantItemRuntime = target.items
		runtime.redirect_radius = radius
		runtime.redirect_percent = redirect_percent
		runtime.redirect_heal_percent = heal_percent
		runtime.redirect_ability_id = ability.id
		runtime.redirect_effect_id = effect_id
