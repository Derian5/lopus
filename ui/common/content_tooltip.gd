class_name ContentTooltip
extends PanelContainer

## Floating tooltip for abilities, items, jobs and stats. Text is BBCode
## (see AbilityText): coloured keywords, inline icons and per-level numbers.

const WIDTH := 400.0

var _content_size := Vector2(WIDTH, 40.0)
var _text := ""


func setup(text: String) -> void:
	_text = text
	%Text.text = text
	_refresh_size()


func _ready() -> void:
	_refresh_size()


func _get_minimum_size() -> Vector2:
	return _content_size


## Measures the rendered text (inline icons and wrapping included) once it has a theme.
func _refresh_size() -> void:
	var label := %Text as RichTextLabel
	var margin := $Margin as MarginContainer
	var horizontal := float(margin.get_theme_constant(&"margin_left") + margin.get_theme_constant(&"margin_right"))
	var vertical := float(margin.get_theme_constant(&"margin_top") + margin.get_theme_constant(&"margin_bottom"))
	label.custom_minimum_size.x = WIDTH - horizontal
	label.size.x = WIDTH - horizontal
	var height := float(label.get_content_height()) if is_inside_tree() else _estimated_height(_text)
	_content_size = Vector2(WIDTH, height + vertical + 4.0)
	custom_minimum_size = _content_size
	update_minimum_size()
	if is_inside_tree():
		size = _content_size


func _estimated_height(text: String) -> float:
	var visual_lines := 0
	for line in text.split("\n"):
		visual_lines += maxi(1, ceili(String(line).length() / 46.0))
	return visual_lines * 24.0
