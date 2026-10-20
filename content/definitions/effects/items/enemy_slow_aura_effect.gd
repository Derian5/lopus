class_name EnemySlowAuraEffect
extends AbilityEffect


## Passive aura: enemies within radius attack and move slow_percent slower.
## The strongest such aura applies; it does not stack.

@export_range(0.0, 10000.0, 1.0, "or_greater") var radius := 450.0
@export_range(0.0, 95.0, 1.0) var slow_percent := 45.0


func apply(_source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		if target.session != null:
			target.session.any_item_slow_aura = true
		var runtime: CombatantItemRuntime = target.items
		runtime.slow_aura_radius = radius
		runtime.slow_aura_percent = slow_percent
		runtime.slow_aura_ability_id = ability.id
