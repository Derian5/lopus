class_name GluttonyRegenerationEffect
extends AbilityEffect


@export_range(1, 1000, 1, "or_greater") var max_stacks := 10
@export_range(0.0, 100.0, 0.01, "or_greater") var max_hp_percent_per_stack := 0.1


func apply(source, _target, ability: AbilityDefinition) -> void:
	if is_instance_valid(source):
		source.set_gluttony_regeneration(max_stacks, max_hp_percent_per_stack, ability.id, effect_id)
