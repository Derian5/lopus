class_name InventoryState
extends RefCounted


var items: Array[Dictionary] = []


func to_dictionary() -> Dictionary:
	return {"items": StateSerialization.dictionaries_to_data(items)}


static func from_dictionary(data: Dictionary) -> InventoryState:
	var state := InventoryState.new()
	state.items = StateSerialization.data_to_dictionaries(data.get("items", []))
	return state
