class_name AbilityLevelDefinition
extends Resource


@export_range(0.0, 3600.0, 0.1, "or_greater") var cooldown_seconds := 0.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var area_radius := 0.0
@export var effects: Array[AbilityEffect] = []
