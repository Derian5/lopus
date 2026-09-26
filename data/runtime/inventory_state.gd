class_name InventoryState
extends RefCounted


var items: Array[Dictionary] = []
var next_instance_serial := 1


func create_item(definition_id: StringName, bound_target_id := "") -> StringName:
	if String(definition_id).is_empty():
		return &""
	var instance_id := StringName("item-%08d" % next_instance_serial)
	while has_instance(instance_id):
		next_instance_serial += 1
		instance_id = StringName("item-%08d" % next_instance_serial)
	next_instance_serial += 1
	items.append({
		"instance_id": String(instance_id),
		"definition_id": String(definition_id),
		"bound_target_id": bound_target_id,
	})
	return instance_id


func add_item(instance_id: StringName, definition_id: StringName, bound_target_id := "") -> bool:
	if String(instance_id).is_empty() or String(definition_id).is_empty() or has_instance(instance_id):
		return false
	items.append({
		"instance_id": String(instance_id),
		"definition_id": String(definition_id),
		"bound_target_id": bound_target_id,
	})
	return true


func has_instance(instance_id: StringName) -> bool:
	return not get_item(instance_id).is_empty()


func get_item(instance_id: StringName) -> Dictionary:
	for item in items:
		if StringName(item.get("instance_id", "")) == instance_id:
			return item
	return {}


func get_definition_id(instance_id: StringName) -> StringName:
	return StringName(get_item(instance_id).get("definition_id", ""))


func remove_item(instance_id: StringName) -> bool:
	for index in items.size():
		if StringName(items[index].get("instance_id", "")) == instance_id:
			items.remove_at(index)
			return true
	return false


func to_dictionary() -> Dictionary:
	return {
		"items": StateSerialization.dictionaries_to_data(items),
		"next_instance_serial": next_instance_serial,
	}


static func from_dictionary(data: Dictionary) -> InventoryState:
	var state := InventoryState.new()
	for item in StateSerialization.data_to_dictionaries(data.get("items", [])):
		state.add_item(
			StringName(item.get("instance_id", "")),
			StringName(item.get("definition_id", "")),
			String(item.get("bound_target_id", ""))
		)
	state.next_instance_serial = maxi(1, int(data.get("next_instance_serial", 1)))
	return state
