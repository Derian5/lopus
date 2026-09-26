class_name RunEventChoice
extends Resource


@export var choice_id: StringName
@export_multiline var text := ""
@export var conditions: Array[RunEventCondition] = []
@export var effects: Array[RunEventEffect] = []
@export var next_node_id: StringName
