class_name HeroDefinition
extends ContentDefinition


@export var base_stats: StatBlock
@export var placeholder_color := Color(0.93, 0.72, 0.25)
@export var portrait: Texture2D
@export var available_in_new_game := false
@export_range(0, 1000, 1, "or_greater") var selection_order := 0
