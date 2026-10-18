class_name DespairSleepEffect
extends AbilityEffect


@export_range(0.1, 3600.0, 0.1, "or_greater") var duration := 2.5


func apply(source, target, ability: AbilityDefinition) -> void:
	if not is_instance_valid(target):
		return
	var sleep := StatusDefinition.new()
	sleep.id = effect_id
	sleep.display_name = "Deep Slumber"
	sleep.description = "Cannot act. Wakes after taking HP damage."
	sleep.default_duration = duration
	sleep.max_stacks = 1
	sleep.stack_policy = StatusDefinition.StackPolicy.REFRESH_DURATION
	sleep.prevents_actions = true
	sleep.breaks_on_hp_damage = true
	sleep.polarity = StatusDefinition.Polarity.NEGATIVE
	target.apply_status(sleep, source, ability.id)
