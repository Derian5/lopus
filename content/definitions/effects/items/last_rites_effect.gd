class_name LastRitesEffect
extends AbilityEffect


## Active, once per battle: when fewer than army_alive_ratio of the starting army
## (Heroes and Soldiers) is alive, every ally gets status (for example invulnerability)
## and heals heal_percent of its Max HP.

@export_range(0.0, 1.0, 0.01) var army_alive_ratio := 0.5
@export var status: StatusDefinition
@export_range(0.0, 100.0, 1.0) var heal_percent := 40.0


func can_apply(source, _target, ability: AbilityDefinition) -> bool:
	if not is_instance_valid(source) or source.items.used_once.has(ability.id):
		return false
	var initial: int = source.session.initial_player_army_count
	if initial <= 0:
		return false
	return float(source.session.player_army_alive_count()) < float(initial) * army_alive_ratio


func apply(source, _target, ability: AbilityDefinition) -> void:
	if not is_instance_valid(source):
		return
	source.items.used_once[ability.id] = true
	for ally in source.session.combatants:
		if ally.snapshot.team != source.snapshot.team or not ally.is_targetable():
			continue
		if status != null:
			ally.apply_status(status, source, ability.id)
		ally.receive_healing(ally.get_effective_stat(&"max_hp") * heal_percent / 100.0, source, ability.id, effect_id)
