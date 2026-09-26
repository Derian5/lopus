class_name ContentTooltip
extends Control

const WIDTH := 320.0

var _content_size := Vector2(WIDTH, 40.0)


func setup(text: String) -> void:
	$Panel/Margin/Text.text = text
	_content_size = Vector2(WIDTH, _estimated_height(text))
	custom_minimum_size = _content_size
	$Panel.size = _content_size
	update_minimum_size()


func _ready() -> void:
	call_deferred("_fit_visible_panel")


func _get_minimum_size() -> Vector2:
	return _content_size


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and has_node("Panel"):
		$Panel.size = _content_size


func _fit_visible_panel() -> void:
	var measured: Vector2 = $Panel.get_combined_minimum_size()
	if measured.x <= 0.0 or measured.y <= 0.0:
		return
	_content_size = measured
	custom_minimum_size = _content_size
	$Panel.size = _content_size
	update_minimum_size()


func _estimated_height(text: String) -> float:
	var visual_lines := 0
	for line in text.split("\n"):
		visual_lines += maxi(1, ceili(String(line).length() / 34.0))
	return 24.0 + visual_lines * 22.0
