class_name StatusInstance
extends RefCounted


var definition: StatusDefinition
var remaining_duration := 0.0
var stacks := 1
var source_id := ""
var source_ability_id: StringName
var periodic_timer := 0.0
var source


func setup(status_definition: StatusDefinition, source_combatant, ability_id: StringName) -> void:
	definition = status_definition
	remaining_duration = definition.default_duration
	source = source_combatant
	source_id = source.snapshot.runtime_id if is_instance_valid(source) else ""
	source_ability_id = ability_id
	periodic_timer = definition.periodic_interval


func refresh(source_combatant, ability_id: StringName) -> void:
	remaining_duration = definition.default_duration
	source = source_combatant
	source_id = source.snapshot.runtime_id if is_instance_valid(source) else ""
	source_ability_id = ability_id
	if definition.stack_policy == StatusDefinition.StackPolicy.ADD_STACKS:
		stacks = mini(stacks + 1, definition.max_stacks)


func update(delta: float, target) -> bool:
	remaining_duration -= delta
	if definition.periodic_interval > 0.0:
		periodic_timer -= delta
		while periodic_timer <= 0.0 and remaining_duration > 0.0:
			periodic_timer += definition.periodic_interval
			var ability: AbilityDefinition = target.session.get_ability_definition(source_ability_id)
			if ability != null:
				for _stack_index in stacks:
					for effect in definition.periodic_effects:
						effect.apply(source, target, ability)
	return remaining_duration <= 0.0
