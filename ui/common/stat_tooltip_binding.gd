class_name StatTooltipBinding
extends RefCounted


const TOOLTIP_SCENE := preload("res://ui/common/content_tooltip.tscn")
const SCREEN_MARGIN := 8.0
const OWNER_GAP := 10.0

static var active_tooltip: ContentTooltip
static var active_owner: Control

var owner: Control
var text := ""
var _hover_generation := 0


func bind(control: Control) -> void:
	owner = control
	owner.mouse_filter = Control.MOUSE_FILTER_STOP
	owner.mouse_default_cursor_shape = Control.CURSOR_HELP
	owner.mouse_entered.connect(_on_mouse_entered)
	owner.mouse_exited.connect(_on_mouse_exited)
	owner.tree_exiting.connect(_on_owner_exiting)
	owner.set_meta("stat_tooltip_binding", self)


func set_text(value: String) -> void:
	text = value
	if active_owner == owner and is_instance_valid(active_tooltip):
		active_tooltip.setup(text)


func _on_mouse_entered() -> void:
	if text.is_empty():
		return
	_hover_generation += 1
	var generation := _hover_generation
	var delay := float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5))
	await owner.get_tree().create_timer(maxf(delay, 0.0)).timeout
	if generation == _hover_generation and is_instance_valid(owner) and Rect2(Vector2.ZERO, owner.size).has_point(owner.get_local_mouse_position()):
		_show()


func _on_mouse_exited() -> void:
	_hover_generation += 1
	_hide()


func _on_owner_exiting() -> void:
	_hover_generation += 1
	_hide()


func _show() -> void:
	ContentButton._hide_active_tooltip()
	_hide_active()
	active_tooltip = TOOLTIP_SCENE.instantiate()
	active_tooltip.setup(text)
	_apply_compact_style(active_tooltip)
	active_owner = owner
	owner.get_tree().root.add_child(active_tooltip)
	active_tooltip.size = active_tooltip.custom_minimum_size
	active_tooltip.z_as_relative = false
	active_tooltip.z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	var viewport_size := owner.get_viewport_rect().size
	var owner_rect := owner.get_global_rect()
	var tooltip_position := Vector2(
		clampf(owner_rect.get_center().x - active_tooltip.size.x * 0.5, SCREEN_MARGIN, viewport_size.x - active_tooltip.size.x - SCREEN_MARGIN),
		owner_rect.position.y - active_tooltip.size.y - OWNER_GAP
	)
	if tooltip_position.y < SCREEN_MARGIN:
		tooltip_position.y = owner_rect.end.y + OWNER_GAP
	tooltip_position.y = clampf(tooltip_position.y, SCREEN_MARGIN, viewport_size.y - active_tooltip.size.y - SCREEN_MARGIN)
	active_tooltip.position = tooltip_position


func _apply_compact_style(tooltip: ContentTooltip) -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.06, 0.042, 0.03, 0.98)
	panel.border_width_left = 1
	panel.border_width_top = 1
	panel.border_width_right = 1
	panel.border_width_bottom = 1
	panel.border_color = Color(0.62, 0.48, 0.24, 0.95)
	panel.corner_radius_top_left = 4
	panel.corner_radius_top_right = 4
	panel.corner_radius_bottom_left = 4
	panel.corner_radius_bottom_right = 4
	panel.corner_detail = 1
	panel.shadow_color = Color(0, 0, 0, 0.55)
	panel.shadow_size = 5
	tooltip.add_theme_stylebox_override("panel", panel)
	var margin := tooltip.get_node("Margin") as MarginContainer
	for side in [&"margin_left", &"margin_right"]:
		margin.add_theme_constant_override(side, 16)
	for side in [&"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	var label := tooltip.get_node("%Text") as RichTextLabel
	label.add_theme_font_size_override("normal_font_size", 16)
	label.add_theme_constant_override("line_separation", 2)


func _hide() -> void:
	if active_owner == owner:
		_hide_active()


static func _hide_active() -> void:
	if is_instance_valid(active_tooltip):
		active_tooltip.queue_free()
	active_tooltip = null
	active_owner = null
