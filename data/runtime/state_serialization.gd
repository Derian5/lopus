class_name StateSerialization
extends RefCounted


static func names_to_strings(values: Array[StringName]) -> Array:
	var result: Array = []
	for value in values:
		result.append(String(value))
	return result


static func strings_to_names(values: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for value in values:
		result.append(StringName(value))
	return result


static func dictionaries_to_data(values: Array[Dictionary]) -> Array:
	var result: Array = []
	for value in values:
		result.append(value.duplicate(true))
	return result


static func data_to_dictionaries(values: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in values:
		if value is Dictionary:
			result.append(value.duplicate(true))
	return result
