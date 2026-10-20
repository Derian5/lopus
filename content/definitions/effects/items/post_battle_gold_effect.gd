class_name PostBattleGoldEffect
extends AbilityEffect


## Passive: +gold after every won battle.

@export_range(0, 100000, 1, "or_greater") var gold := 50


func apply(_source, target, _ability: AbilityDefinition) -> void:
	if is_instance_valid(target):
		target.items.post_battle_gold += gold
