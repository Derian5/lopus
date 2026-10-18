extends Control


signal new_game_requested
signal continue_requested
signal quit_requested

const DESIGN_SIZE := Vector2(1920.0, 1080.0)
const BACKGROUND_ATLAS := preload("res://graphics/ui/atlas_ui.png")
const BACKGROUND_REGIONS := [
	Rect2(20, 535, 147, 165), Rect2(174, 535, 147, 165), Rect2(327, 535, 146, 165),
	Rect2(481, 535, 139, 165), Rect2(628, 535, 148, 165), Rect2(782, 535, 148, 165),
	Rect2(936, 535, 147, 165),
]
const BADGE_REGIONS := [
	Rect2(18, 432, 77, 92), Rect2(99, 432, 77, 92), Rect2(180, 432, 77, 92),
	Rect2(261, 432, 77, 92), Rect2(342, 432, 77, 92), Rect2(425, 432, 77, 92),
	Rect2(508, 432, 77, 92),
]

var save_exists := false


func _ready() -> void:
	_build_atlas_backdrop()
	resized.connect(_apply_design_scale)
	_apply_design_scale()
	%DebugBadge.visible = get_node("/root/DevMode").enabled
	if %ContinueButton.disabled:
		%NewGameButton.grab_focus()
	else:
		%ContinueButton.grab_focus()


func setup(save_probe: Dictionary) -> void:
	save_exists = bool(save_probe.get("exists", false))
	%ContinueButton.disabled = not bool(save_probe.get("ok", false))
	# Only problems are worth a line of text; a loadable save speaks through the Continue button.
	%StatusLabel.text = String(save_probe.get("status_override", ""))
	if not bool(save_probe.get("ok", false)) and save_exists:
		%StatusLabel.text = "%s\nStart a New Game to replace this save." % save_probe.get("status_override", save_probe.get("message", "Save cannot be loaded."))
	if not %ContinueButton.disabled:
		%ContinueButton.grab_focus()


func _on_new_game_button_pressed() -> void:
	new_game_requested.emit()


func _on_continue_button_pressed() -> void:
	continue_requested.emit()


func _on_quit_button_pressed() -> void:
	quit_requested.emit()


func _build_atlas_backdrop() -> void:
	for index in BACKGROUND_REGIONS.size():
		var banner := TextureRect.new()
		banner.position = Vector2(105.0 + index * 250.0, 138.0)
		banner.size = Vector2(210.0, 790.0)
		banner.texture = _atlas_texture(BACKGROUND_REGIONS[index])
		banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		banner.modulate = Color(0.72, 0.78, 0.9, 0.07)
		banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		%BannerLayer.add_child(banner)
		var badge := TextureRect.new()
		badge.position = Vector2(425.0 + index * 150.0, 82.0)
		badge.size = Vector2(78.0, 94.0)
		badge.texture = _atlas_texture(BADGE_REGIONS[index])
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.modulate = Color(0.9, 0.92, 1.0, 0.82)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		%SigilLayer.add_child(badge)


func _apply_design_scale() -> void:
	if not is_node_ready():
		return
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	%DesignRoot.scale = Vector2.ONE * factor
	%DesignRoot.position = (size - DESIGN_SIZE * factor) * 0.5


func _atlas_texture(region: Rect2) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = BACKGROUND_ATLAS
	texture.region = region
	return texture
