class_name NearbyAllyStatBonusEffect
extends AbilityEffect


## Passive: grants a flat stat bonus for each other living ally of the same Job
## within the radius, up to max_allies (Militia's Strength in Numbers).
@export_enum("max_hp", "damage", "attack_speed", "movement_speed", "attack_range", "armor") var stat := "armor"
@export_range(0.0, 10000.0, 0.1, "or_greater") var value_per_ally := 3.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var radius := 160.0
@export_range(1, 100, 1, "or_greater") var max_allies := 5


func apply(_source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		target.set_nearby_ally_stat_bonus(StringName(stat), value_per_ally, radius, max_allies, ability.id)
