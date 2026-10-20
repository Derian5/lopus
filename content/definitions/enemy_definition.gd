class_name EnemyDefinition
extends ContentDefinition


@export var base_stats: StatBlock
@export var attack_type: StringName = &"melee"
@export var ability_ids: Array[StringName] = []
## closest: attacks the nearest enemy. back_line: runs past the front line to the
## nearest ranged enemy (archers, priests, ranged Heroes), falling back to the closest.
@export_enum("closest", "back_line") var targeting_mode := "closest"
@export var placeholder_color := Color(0.82, 0.24, 0.2)
