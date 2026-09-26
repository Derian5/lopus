class_name RuntimeStatModifier
extends RefCounted


var instance_id := ""
var source_id: StringName
var stat := "max_hp"
var operation := StatModifier.Operation.ADD
var value := 0.0
var battles_remaining := -1


func to_stat_modifier() -> StatModifier:
	var modifier := StatModifier.new()
	modifier.stat = stat
	modifier.operation = operation
	modifier.value = value
	return modifier


func to_dictionary() -> Dictionary:
	return {
		"instance_id": instance_id,
		"source_id": String(source_id),
		"stat": stat,
		"operation": operation,
		"value": value,
		"battles_remaining": battles_remaining,
	}


static func from_dictionary(data: Dictionary) -> RuntimeStatModifier:
	var modifier := RuntimeStatModifier.new()
	modifier.instance_id = String(data.get("instance_id", ""))
	modifier.source_id = StringName(data.get("source_id", ""))
	modifier.stat = String(data.get("stat", "max_hp"))
	modifier.operation = int(data.get("operation", StatModifier.Operation.ADD))
	modifier.value = float(data.get("value", 0.0))
	modifier.battles_remaining = int(data.get("battles_remaining", -1))
	return modifier
