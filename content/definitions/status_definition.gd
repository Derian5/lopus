class_name StatusDefinition
extends ContentDefinition


enum StackPolicy {
	REFRESH_DURATION,
	ADD_STACKS,
}

enum Polarity {
	NEUTRAL,
	POSITIVE,
	NEGATIVE,
}

@export_range(0.0, 3600.0, 0.1, "or_greater") var default_duration := 0.0
@export_range(1, 1000, 1, "or_greater") var max_stacks := 1
@export var stack_policy := StackPolicy.REFRESH_DURATION
@export_range(0.0, 3600.0, 0.1, "or_greater") var periodic_interval := 0.0
@export var periodic_effects: Array[AbilityEffect] = []
@export var stat_modifiers: Array[StatModifier] = []
@export var prevents_actions := false
@export var polarity := Polarity.NEUTRAL
