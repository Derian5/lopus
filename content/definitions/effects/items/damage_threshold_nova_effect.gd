class_name DamageThresholdNovaEffect
extends AbilityEffect


## Passive: every damage_threshold damage taken (shields included) releases a nova that
## deals damage to enemies within radius, applies status to them and heals this unit
## for heal_percent of Max HP.

@export_range(1.0, 100000.0, 1.0, "or_greater") var damage_threshold := 300.0
@export_range(0.0, 100000.0, 1.0, "or_greater") var damage := 250.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var radius := 200.0
@export var status: StatusDefinition
@export_range(0.0, 100.0, 1.0) var heal_percent := 15.0


func apply(_source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		target.items.damage_novas.append({
			"threshold": damage_threshold,
			"damage": damage,
			"radius": radius,
			"status": status,
			"heal_percent": heal_percent,
			"accumulated": 0.0,
			"ability_id": ability.id,
			"effect_id": effect_id,
		})
