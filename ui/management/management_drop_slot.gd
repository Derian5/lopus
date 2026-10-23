class_name ManagementDropSlot
extends ContentIconButton

signal payload_dropped(source: Dictionary, target: Dictionary)

var target_payload: Dictionary = {}
var accepted_sources: Array[StringName] = []
var drag_payload: Dictionary = {}


func _get_drag_data(_position: Vector2) -> Variant:
	if drag_payload.is_empty() or disabled:
		return null
	set_drag_preview(make_icon_preview(icon, text))
	return drag_payload.duplicate(true)


## Drag ghost: the dragged icon (or its text when it has none), centred on the cursor.
static func make_icon_preview(texture: Texture2D, label := "") -> Control:
	var holder := Control.new()
	if texture != null:
		var image := TextureRect.new()
		image.texture = texture
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.size = Vector2(64.0, 64.0)
		image.position = Vector2(-32.0, -32.0)
		image.modulate = Color(1.0, 1.0, 1.0, 0.85)
		holder.add_child(image)
	else:
		var text_label := Label.new()
		text_label.text = label
		text_label.position = Vector2(-20.0, -19.0)
		text_label.modulate = Color(1.0, 1.0, 1.0, 0.9)
		holder.add_child(text_label)
	return holder


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	if disabled or not data is Dictionary:
		return false
	return accepted_sources.is_empty() or accepted_sources.has(StringName(data.get("source", "")))


func _drop_data(_position: Vector2, data: Variant) -> void:
	payload_dropped.emit(Dictionary(data).duplicate(true), target_payload.duplicate(true))
