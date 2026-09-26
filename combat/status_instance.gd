class_name StatusInstance
extends RefCounted


var definition: StatusDefinition
var remaining_duration := 0.0
var stacks := 1
var source_id := ""
var source_ability_id: StringName
var periodic_timer := 0.0
var source
var infinite_duration := false


func setup(status_definition: StatusDefinition, source_combatant, ability_id: StringName) -> void:
	definition = status_definition
	infinite_duration = definition.default_duration <= 0.0
	remaining_duration = definition.default_duration if not infinite_duration else -1.0
	source = source_combatant
	source_id = source.snapshot.runtime_id if is_instance_valid(source) else ""
	source_ability_id = ability_id
	periodic_timer = definition.periodic_interval


func refresh(source_combatant, ability_id: StringName) -> void:
	infinite_duration = definition.default_duration <= 0.0
	remaining_duration = definition.default_duration if not infinite_duration else -1.0
	source = source_combatant
	source_id = source.snapshot.runtime_id if is_instance_valid(source) else ""
	source_ability_id = ability_id
	if definition.stack_policy == StatusDefinition.StackPolicy.ADD_STACKS:
		stacks = mini(stacks + 1, definition.max_stacks)


func update(delta: float, target) -> bool:
	if not infinite_duration:
		remaining_duration -= delta
	if definition.periodic_interval > 0.0:
		periodic_timer -= delta
		while periodic_timer <= 0.0 and (infinite_duration or remaining_duration > 0.0):
			periodic_timer += definition.periodic_interval
			var ability: AbilityDefinition = target.session.get_ability_definition(source_ability_id)
			if ability != null:
				for _stack_index in stacks:
					for effect in definition.periodic_effects:
						effect.apply(source, target, ability)
	return not infinite_duration and remaining_duration <= 0.0
