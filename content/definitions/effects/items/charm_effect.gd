class_name CharmEffect
extends AbilityEffect


## Active: the target fights for the caster's side for duration seconds, attacking its
## former allies. Bosses cannot be charmed.

@export_range(0.1, 3600.0, 0.1, "or_greater") var duration := 5.0


func can_apply(source, target, _ability: AbilityDefinition) -> bool:
	return is_instance_valid(source) and is_instance_valid(target) and not target.snapshot.is_boss and target.snapshot.team != source.snapshot.team


func apply(source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target) and not target.snapshot.is_boss:
		target.items.start_charm(source.snapshot.team, duration, ability.id)
