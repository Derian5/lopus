class_name EncounterDefinition
extends ContentDefinition


@export var enemy_ids: Array[StringName] = []
@export_range(0, 1000000, 1, "or_greater") var gold_reward := 0
@export var arena_id: StringName = &"arena.default"
