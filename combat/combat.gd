extends Control


signal management_requested
signal menu_requested


func _on_management_button_pressed() -> void:
	management_requested.emit()


func _on_menu_button_pressed() -> void:
	menu_requested.emit()
