class_name ManagementDropSlot
extends ContentIconButton

signal payload_dropped(source: Dictionary, target: Dictionary)

var target_payload: Dictionary = {}
var accepted_sources: Array[StringName] = []
var drag_payload: Dictionary = {}


func _get_drag_data(_position: Vector2) -> Variant:
	if drag_payload.is_empty() or disabled:
		return null
	var preview := Label.new()
	preview.text = text
	preview.custom_minimum_size = Vector2(180.0, 38.0)
	preview.modulate = Color(1.0, 1.0, 1.0, 0.9)
	set_drag_preview(preview)
	return drag_payload.duplicate(true)


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	if disabled or not data is Dictionary:
		return false
	return accepted_sources.is_empty() or accepted_sources.has(StringName(data.get("source", "")))


func _drop_data(_position: Vector2, data: Variant) -> void:
	payload_dropped.emit(Dictionary(data).duplicate(true), target_payload.duplicate(true))
