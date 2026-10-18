class_name ButtonMotion
extends Node


@export_range(1.0, 1.2, 0.005) var hover_scale := 1.035
@export_range(0.8, 1.0, 0.005) var pressed_scale := 0.965
@export_range(0.01, 1.0, 0.01) var duration := 0.09
@export var hover_color := Color(1.12, 1.12, 1.12, 1.0)
@export var pressed_color := Color(0.86, 0.86, 0.9, 1.0)
@export var animate_focus := false
@export var target_path: NodePath

var button: BaseButton
var target: Control
var hovered := false
var pressed := false
var tween: Tween
var rest_scale := Vector2.ONE
var rest_color := Color.WHITE


func _ready() -> void:
	button = get_parent() as BaseButton
	if button == null:
		push_error("ButtonMotion must be a child of BaseButton.")
		return
	target = button if target_path.is_empty() else get_node(target_path) as Control
	if target == null:
		push_error("ButtonMotion target must be a Control.")
		return
	rest_scale = target.scale
	rest_color = target.modulate
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.mouse_entered.connect(_on_mouse_entered)
	button.mouse_exited.connect(_on_mouse_exited)
	button.button_down.connect(_on_button_down)
	button.button_up.connect(_on_button_up)
	button.focus_entered.connect(_on_focus_entered)
	button.focus_exited.connect(_on_focus_exited)
	target.resized.connect(_update_pivot)
	button.visibility_changed.connect(_on_visibility_changed)
	_update_pivot()


func _process(_delta: float) -> void:
	if button == null or not button.is_inside_tree():
		return
	var pointer_inside := _pointer_inside()
	var changed := hovered != pointer_inside
	hovered = pointer_inside
	if pressed and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		pressed = false
		changed = true
		if not hovered and button.has_focus():
			button.release_focus()
	if changed:
		_animate_current_state()


func _on_mouse_entered() -> void:
	hovered = true
	_animate_current_state()


func _on_mouse_exited() -> void:
	hovered = false
	_animate_current_state()


func _on_button_down() -> void:
	pressed = true
	_animate_current_state()


func _on_button_up() -> void:
	var was_pressed := pressed
	pressed = false
	_sync_hover_state()
	if was_pressed and not hovered and button.has_focus():
		button.release_focus()
	_animate_current_state()


func _input(event: InputEvent) -> void:
	if (
		pressed
		and event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and not event.pressed
	):
		pressed = false
		_sync_hover_state()
		if not hovered and button.has_focus():
			button.release_focus()
		_animate_current_state()


func _on_focus_entered() -> void:
	_animate_current_state()


func _on_focus_exited() -> void:
	_animate_current_state()


func _on_visibility_changed() -> void:
	if button.visible:
		return
	hovered = false
	pressed = false
	target.scale = rest_scale
	target.modulate = rest_color


func set_rest_state(new_scale: Vector2, new_color := Color.WHITE) -> void:
	rest_scale = new_scale
	rest_color = new_color
	if not hovered and not pressed and (not animate_focus or not button.has_focus()):
		target.scale = rest_scale
		target.modulate = rest_color


func _animate_current_state() -> void:
	if button == null:
		return
	var active_hover := hovered or (animate_focus and button.has_focus())
	var target_scale := rest_scale
	var target_color := rest_color
	if not button.disabled:
		if pressed and hovered:
			target_scale = rest_scale * pressed_scale
			target_color = rest_color * pressed_color
		elif active_hover:
			target_scale = rest_scale * hover_scale
			target_color = rest_color * hover_color
	if tween != null and tween.is_valid():
		tween.kill()
	tween = target.create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(target, "scale", target_scale, duration)
	tween.tween_property(target, "modulate", target_color, duration)


func _update_pivot() -> void:
	if target != null:
		target.pivot_offset = target.size * 0.5


func _sync_hover_state() -> void:
	if button != null and button.is_inside_tree():
		hovered = _pointer_inside()


func _pointer_inside() -> bool:
	if not Rect2(Vector2.ZERO, button.size).has_point(button.get_local_mouse_position()):
		return false
	var hovered_control := button.get_viewport().gui_get_hovered_control()
	return hovered_control == button or (hovered_control != null and button.is_ancestor_of(hovered_control))
