class_name ItemDefinition
extends ContentDefinition


@export var allowed_target_type: StringName = &"hero"
@export var allowed_job_ids: Array[StringName] = []
@export var passive_effects: Array[StatModifier] = []
@export_enum("common", "uncommon", "rare", "legendary") var rarity := "common"
@export_range(0, 1000000, 1, "or_greater") var price := 0
@export_range(0, 1000000, 1, "or_greater") var sell_price := 0
