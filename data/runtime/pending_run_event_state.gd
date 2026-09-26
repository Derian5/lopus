class_name PendingRunEventState
extends RefCounted


var event_id: StringName
var node_id: StringName
var target_ids: Array[String] = []


func is_empty() -> bool:
	return String(event_id).is_empty()


func clear() -> void:
	event_id = &""
	node_id = &""
	target_ids.clear()


func to_dictionary() -> Dictionary:
	return {
		"event_id": String(event_id),
		"node_id": String(node_id),
		"target_ids": target_ids.duplicate(),
	}


static func from_dictionary(data: Dictionary) -> PendingRunEventState:
	var state := PendingRunEventState.new()
	state.event_id = StringName(data.get("event_id", ""))
	state.node_id = StringName(data.get("node_id", ""))
	for target_id in data.get("target_ids", []):
		state.target_ids.append(String(target_id))
	return state
