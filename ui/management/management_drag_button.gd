class_name ManagementDragButton
extends ContentButton

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
