extends Control


signal new_run_requested
signal main_menu_requested


func setup(run_status: StringName, act: int, encounter_index: int) -> void:
	if run_status == RunState.STATUS_DEFEAT:
		%Eyebrow.text = "THE ARMY HAS FALLEN"
		%Title.text = "RUN DEFEAT"
		%Body.text = "The campaign ended in Act %d after %d completed battles in this act.\nThe next run begins with a fresh army, market, and route." % [act, encounter_index]
	else:
		%Eyebrow.text = "STEAM DEMO COMPLETE"
		%Title.text = "THE WAR CONTINUES"
		%Body.text = "You survived Act I and completed all three battles of Act II.\nThank you for playing Can Be Only One Hero."
	%NewRunButton.grab_focus()


func set_status(message: String) -> void:
	%StatusLabel.text = message


func _on_new_run_pressed() -> void:
	new_run_requested.emit()


func _on_main_menu_pressed() -> void:
	main_menu_requested.emit()
