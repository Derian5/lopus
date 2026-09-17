class_name JobDefinition
extends ContentDefinition


@export var stat_modifiers: StatBlock
@export var attack_type: StringName = &"melee"
@export var attack_definition_id: StringName = &"attack.basic"
@export var ai_behavior: StringName = &"frontline"
@export var available_ability_ids: Array[StringName] = []
@export var restriction_tags: Array[StringName] = []
@export_range(0, 1000000, 1, "or_greater") var capacity_price := 100
@export var placeholder_color := Color(0.3, 0.55, 0.9)
