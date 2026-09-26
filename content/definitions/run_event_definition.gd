class_name RunEventDefinition
extends ContentDefinition


@export_range(0.0, 1000000.0, 0.1, "or_greater") var weight := 1.0
@export var one_time := true
@export var conditions: Array[RunEventCondition] = []
@export_range(0, 12, 1, "or_greater") var soldier_target_count := 0
@export var target_allowed_job_ids: Array[StringName] = []
@export_range(0, 100, 1, "or_greater") var target_min_veterancy_level := 0
@export var entry_node_id: StringName
@export var nodes: Array[RunEventNode] = []


func get_node_definition(node_id: StringName) -> RunEventNode:
	for node in nodes:
		if node != null and node.node_id == node_id:
			return node
	return null
