class_name EmergencyStealthEffect
extends AbilityEffect


## Active (self): usable below health_threshold. The unit turns invisible for duration
## seconds (enemies drop it as a target) and restores heal_percent of Max HP.

@export_range(0.0, 1.0, 0.01) var health_threshold := 0.4
@export_range(0.0, 3600.0, 0.1, "or_greater") var duration := 3.0
@export_range(0.0, 100.0, 1.0) var heal_percent := 25.0


func can_apply(source, _target, _ability: AbilityDefinition) -> bool:
	return is_instance_valid(source) and source.current_hp / maxf(source.get_effective_stat(&"max_hp"), 1.0) <= health_threshold


func apply(source, _target, ability: AbilityDefinition) -> void:
	if not is_instance_valid(source):
		return
	source.apply_stealth(duration, ability.id, effect_id)
	for candidate in source.session.combatants:
		if candidate.target == source and candidate.snapshot.team != source.snapshot.team:
			candidate.clear_combat_action()
	source.receive_healing(source.get_effective_stat(&"max_hp") * heal_percent / 100.0, source, ability.id, effect_id)
