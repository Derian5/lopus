extends SceneTree


const COMBAT_SCENE := preload("res://combat/combat.tscn")
const SESSION_SCENE := preload("res://combat/combat_session.tscn")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry := root.get_node("ContentRegistry")
	var route := registry.get_definition(RunState.ROUTE_DEFINITION_ID) as RouteDefinition
	var run := DemoRunFactory.create_starting_run(79001)
	_check(RunEventService.prepare_specific_event(run, route.opening_event_id, registry).ok, "The actual opening event is prepared.")
	var combat = COMBAT_SCENE.instantiate()
	combat.setup_run(run)
	root.add_child(combat)
	await process_frame
	await process_frame
	var session := combat.get_node("%CombatSession") as CombatSession
	_check(combat.get_node("%RunEventPopup").visible and not combat.battle_started, "The first event is visible before combat starts.")
	_check(not session.battle_active and session.combatants.is_empty() and session.elapsed_time == 0.0, "Creating the scenery does not start combat or spawn the army.")
	_check(session.backdrop != null and session.backdrop.stream.resource_path == CombatSession.BACKDROP_VIDEO_PATH and session.backdrop.is_playing(), "The new animated backdrop is playing behind the opening event.")
	_check(session.foreground != null and session.foreground.texture.resource_path == CombatSession.FOREGROUND_PATH and session.vignette != null, "Foreground and atmosphere exist before the first story choice.")
	var backdrop_id := session.backdrop.get_instance_id()
	var foreground_id := session.foreground.get_instance_id()
	var choices := 0
	while not run.pending_event.is_empty() and choices < 8:
		var event := registry.get_definition(run.pending_event.event_id) as RunEventDefinition
		var node := event.get_node_definition(run.pending_event.node_id)
		var choice := RunEventService.choose(run, node.choices[0].choice_id, registry)
		_check(choice.ok, "The opening story advances normally.")
		if not choice.ok:
			break
		run = choice.run_state
		combat.refresh_run_event(run)
		choices += 1
	_check(run.pending_event.is_empty() and combat.battle_started and session.battle_active and not session.combatants.is_empty(), "Completing the event still starts the first battle.")
	_check(session.backdrop.get_instance_id() == backdrop_id and session.foreground.get_instance_id() == foreground_id, "Battle startup reuses the scenery instead of replacing or duplicating it.")
	combat.free()
	var simulation: CombatSession = SESSION_SCENE.instantiate()
	simulation.vfx_enabled = false
	root.add_child(simulation)
	_check(simulation.backdrop == null and simulation.foreground == null and simulation.vignette == null, "Balance Lab sessions still skip presentation resources.")
	simulation.free()
	if failures == 0:
		print("Opening battlefield tests passed: animated scenery before the event, delayed combat startup and Balance Lab opt-out.")
		quit()
	else:
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
