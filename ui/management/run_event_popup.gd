class_name RunEventPopup
extends Control


signal choice_selected(choice_id: StringName)

var run_state: RunState


func show_pending(new_run_state: RunState) -> void:
	run_state = new_run_state
	if run_state == null or run_state.pending_event.is_empty():
		visible = false
		return
	var event := _registry().get_definition(run_state.pending_event.event_id, false) as RunEventDefinition
	var node := event.get_node_definition(run_state.pending_event.node_id) if event != null else null
	if event == null or node == null:
		visible = false
		return
	%EventTitle.text = node.title if not node.title.is_empty() else event.display_name
	%EventBody.text = _format_text(node.body)
	%Feedback.text = ""
	_clear_choices()
	var first_enabled: Button
	for choice in node.choices:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 48)
		button.text = _format_text(choice.text)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var status := RunEventService.choice_status(run_state, choice, _registry())
		button.disabled = not status.ok
		button.tooltip_text = status.error if not status.ok else ""
		button.pressed.connect(_on_choice_pressed.bind(choice.choice_id))
		%Choices.add_child(button)
		if first_enabled == null and not button.disabled:
			first_enabled = button
	visible = true
	if first_enabled != null:
		first_enabled.grab_focus()


func set_feedback(message: String) -> void:
	%Feedback.text = message


func _on_choice_pressed(choice_id: StringName) -> void:
	choice_selected.emit(choice_id)


func _format_text(text: String) -> String:
	var result := text
	for index in run_state.pending_event.target_ids.size():
		var target_id := run_state.pending_event.target_ids[index]
		var target_name := target_id
		for soldier in run_state.soldiers:
			if soldier.unique_id == target_id:
				target_name = soldier.generated_name
				break
		result = result.replace("{soldier_%d}" % index, target_name)
	return result


func _clear_choices() -> void:
	for child in %Choices.get_children():
		child.visible = false
		child.queue_free()


func _registry() -> Node:
	return get_node("/root/ContentRegistry")
