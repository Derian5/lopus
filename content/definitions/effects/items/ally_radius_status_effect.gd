class_name AllyRadiusStatusEffect
extends AbilityEffect


## Active (self): applies status to every living ally within radius of the caster
## (radius 0 = the whole army). Optional conditions keep it from firing uselessly.

@export var status: StatusDefinition
@export_range(0.0, 10000.0, 1.0, "or_greater") var radius := 500.0
## Only cast when at least one ally in range is below full HP.
@export var require_wounded_ally := false
## Only cast when at least this many allies are below wounded_health_ratio (0 = off).
@export_range(0, 100, 1) var min_wounded_allies := 0
@export_range(0.0, 1.0, 0.01) var wounded_health_ratio := 0.5


func can_apply(source, _target, _ability: AbilityDefinition) -> bool:
	if not is_instance_valid(source):
		return false
	var hurt := 0
	var badly_hurt := 0
	for ally in _allies(source):
		var ratio: float = ally.current_hp / maxf(ally.get_effective_stat(&"max_hp"), 1.0)
		if ratio < 0.999:
			hurt += 1
		if ratio < wounded_health_ratio:
			badly_hurt += 1
	if require_wounded_ally and hurt == 0:
		return false
	return min_wounded_allies <= 0 or badly_hurt >= min_wounded_allies


func apply(source, _target, ability: AbilityDefinition) -> void:
	if not is_instance_valid(source) or status == null:
		return
	for ally in _allies(source):
		ally.apply_status(status, source, ability.id)


func _allies(source) -> Array:
	var result: Array = []
	for candidate in source.session.combatants:
		if candidate.snapshot.team != source.snapshot.team or not candidate.is_targetable():
			continue
		if radius > 0.0 and candidate.position.distance_to(source.position) > radius:
			continue
		result.append(candidate)
	return result
