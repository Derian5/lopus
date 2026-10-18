extends Node


const BUTTON_MOTION_SCRIPT := preload("res://ui/common/button_motion.gd")


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	for node in get_tree().root.find_children("*", "BaseButton", true, false):
		_queue_button(node)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_queue_button(node)


func _queue_button(button: BaseButton) -> void:
	call_deferred("_attach_motion", button)


func _attach_motion(candidate) -> void:
	if not is_instance_valid(candidate) or not candidate is BaseButton:
		return
	var button := candidate as BaseButton
	if not button.is_inside_tree() or button.has_meta("disable_auto_motion"):
		return
	for child in button.get_children():
		if child.get_script() == BUTTON_MOTION_SCRIPT:
			return
	var motion := BUTTON_MOTION_SCRIPT.new()
	motion.name = "AutoButtonMotion"
	motion.hover_scale = 1.025
	motion.pressed_scale = 0.975
	button.add_child(motion)
