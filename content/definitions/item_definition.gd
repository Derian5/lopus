class_name ItemDefinition
extends ContentDefinition


@export var allowed_target_type: StringName = &"hero"
@export var allowed_job_ids: Array[StringName] = []
@export_range(0, 1000000, 1, "or_greater") var price := 0
@export var stat_modifiers: StatBlock
