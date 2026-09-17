extends Control


signal resume_requested
signal main_menu_requested
signal quit_requested


func _ready() -> void:
	%ResumeButton.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		resume_requested.emit()


func _on_resume_button_pressed() -> void:
	resume_requested.emit()


func _on_main_menu_button_pressed() -> void:
	main_menu_requested.emit()


func _on_quit_button_pressed() -> void:
	quit_requested.emit()
