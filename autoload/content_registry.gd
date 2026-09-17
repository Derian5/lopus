extends Node


const CONTENT_DIRECTORIES: Array[String] = ["res://content/demo"]

var definitions: Dictionary = {}
var validation_errors: PackedStringArray = []


func _ready() -> void:
	reload_content()


func reload_content() -> bool:
	definitions.clear()
	validation_errors.clear()

	var paths: Array[String] = []
	for directory in CONTENT_DIRECTORIES:
		_collect_resource_paths(directory, paths)
	paths.sort()

	for path in paths:
		var resource := ResourceLoader.load(path)
		if resource is ContentDefinition:
			register_definition(resource)

	return validation_errors.is_empty()


func register_definition(definition: ContentDefinition, report_error := true) -> bool:
	if definition == null:
		return _record_error("Cannot register a null content definition.", report_error)

	if String(definition.id).is_empty():
		return _record_error("Content definition has an empty ID.", report_error)

	if definitions.has(definition.id):
		return _record_error("Duplicate content ID: %s" % definition.id, report_error)

	var forbidden_path := _find_forbidden_value(definition, "definition:%s" % definition.id)
	if not forbidden_path.is_empty():
		return _record_error("Content definition contains Node or NodePath at %s." % forbidden_path, report_error)

	definitions[definition.id] = definition
	return true


func get_definition(content_id: StringName, report_missing := true) -> ContentDefinition:
	var definition: ContentDefinition = definitions.get(content_id)
	if definition == null:
		_record_error("Missing content ID: %s" % content_id, report_missing)
	return definition


func has_definition(content_id: StringName) -> bool:
	return definitions.has(content_id)


func get_definition_count() -> int:
	return definitions.size()


func _collect_resource_paths(directory_path: String, paths: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		_record_error("Content directory does not exist: %s" % directory_path, true)
		return

	var file_names := directory.get_files()
	file_names.sort()
	for file_name in file_names:
		if file_name.get_extension() == "tres":
			paths.append(directory_path.path_join(file_name))

	var directory_names := directory.get_directories()
	directory_names.sort()
	for child_directory in directory_names:
		_collect_resource_paths(directory_path.path_join(child_directory), paths)


func _find_forbidden_value(value: Variant, path: String) -> String:
	if value is Node or value is NodePath:
		return path

	if value is Resource:
		for property in value.get_property_list():
			if not property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				continue
			var property_name: StringName = property.name
			var forbidden_path := _find_forbidden_value(value.get(property_name), "%s.%s" % [path, property_name])
			if not forbidden_path.is_empty():
				return forbidden_path
	elif value is Array:
		for index in value.size():
			var forbidden_path := _find_forbidden_value(value[index], "%s[%d]" % [path, index])
			if not forbidden_path.is_empty():
				return forbidden_path
	elif value is Dictionary:
		for key in value:
			var forbidden_path := _find_forbidden_value(value[key], "%s[%s]" % [path, key])
			if not forbidden_path.is_empty():
				return forbidden_path

	return ""


func _record_error(message: String, report_error: bool) -> bool:
	validation_errors.append(message)
	if report_error:
		push_error(message)
	return false
