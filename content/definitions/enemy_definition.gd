class_name EnemyDefinition
extends ContentDefinition


@export var base_stats: StatBlock
@export var attack_type: StringName = &"melee"
@export var ability_ids: Array[StringName] = []
@export var placeholder_color := Color(0.82, 0.24, 0.2)
