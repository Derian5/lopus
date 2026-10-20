class_name GoldStatScalingEffect
extends AbilityEffect


## Passive (applied when the army is built): the owner gains percent_per_step % damage
## and Max HP for every gold_step Gold the player holds, up to max_percent.
## Handled by CombatSnapshotBuilder, so apply() does nothing in combat.

@export_range(0.0, 1000.0, 0.1, "or_greater") var percent_per_step := 2.0
@export_range(1, 100000, 1, "or_greater") var gold_step := 50
@export_range(0.0, 10000.0, 1.0, "or_greater") var max_percent := 50.0


func bonus_percent(gold: int) -> float:
	return minf(max_percent, floorf(float(maxi(gold, 0)) / float(gold_step)) * percent_per_step)
