class_name KillRewardEffect
extends AbilityEffect


@export_range(0, 1000000, 1, "or_greater") var gold_per_kill := 10
@export_range(0.0, 100000.0, 0.1, "or_greater") var permanent_damage_per_kill := 1.0


func apply(_source, target, ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		target.kill_reward_ability_id = ability.id
		target.kill_reward_effect_id = effect_id
		target.kill_gold_reward = gold_per_kill
		target.kill_permanent_damage = permanent_damage_per_kill
