extends SceneTree


const MANAGEMENT_SCENE := preload("res://ui/management/management.tscn")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var run := DemoRunFactory.create_starting_run(7070)
	var screen = MANAGEMENT_SCENE.instantiate()
	root.add_child(screen)
	screen.setup(run)
	await process_frame
	await process_frame

	_check(screen.get_node("%Roster").get_child_count() == 12, "Army roster exposes all 3 heroes and 9 soldiers.")
	_check(screen.get_node("%GoldLabel").text.contains("300"), "Gold is visible.")
	_check(screen.get_node("%EncounterLabel").text.contains("TRAINING SKIRMISH"), "Next Encounter is visible.")
	_check(screen.get_node("%MarketRows").get_child_count() == 4, "Market lists three Job capacity offers.")

	var warrior_option: int = screen.job_option_ids.find(&"job.warrior")
	for soldier_index in 3:
		screen._select_unit("soldier", soldier_index)
		screen.get_node("%JobOption").select(warrior_option)
		screen._on_change_job_pressed()
		_check(run.soldiers[soldier_index].current_job_id == &"job.warrior", "Available Warrior capacity accepts assignment %d." % soldier_index)
	screen._select_unit("soldier", 3)
	screen.get_node("%JobOption").select(warrior_option)
	screen._on_change_job_pressed()
	_check(run.soldiers[3].current_job_id == &"job.militia", "A fourth Warrior assignment is blocked at capacity.")
	_check(screen.get_node("%FeedbackLabel").text.contains("capacity is full"), "Blocked assignment explains the capacity problem.")

	run.soldiers[0].veterancy_level = 3
	run.soldiers[0].veterancy_xp = 75
	screen._select_unit("soldier", 0)
	var archer_option: int = screen.job_option_ids.find(&"job.archer")
	screen.get_node("%JobOption").select(archer_option)
	screen._on_job_preview_selected(archer_option)
	_check(screen.get_node("%JobWarning").text.contains("3") and screen.get_node("%JobWarning").text.contains("75"), "Job preview shows veterancy loss before confirmation.")
	screen._on_change_job_pressed()
	_check(run.soldiers[0].veterancy_level == 0 and run.soldiers[0].veterancy_xp == 0, "Confirmed Job change resets veterancy.")

	screen._select_unit("hero", 0)
	var old_first := run.heroes[0].ability_priority[0]
	screen._move_hero_ability(1, -1)
	_check(run.heroes[0].ability_priority[1] == old_first, "Hero ability priority moves up and down.")
	var heal_option: int = screen.ability_option_ids.find(&"ability.mending_light")
	screen.get_node("%AbilityOption").select(heal_option)
	screen.selected_ability_slot = 0
	screen._on_replace_ability_pressed()
	_check(run.heroes[0].ability_priority[0] == &"ability.mending_light", "Hero ability slot can be replaced without debug commands.")

	var old_gold := run.gold
	var old_capacity := int(run.job_capacities["job.archer"])
	screen._buy_capacity(&"job.archer")
	_check(run.gold == old_gold - 110 and int(run.job_capacities["job.archer"]) == old_capacity + 1, "Market purchase spends real Gold and increases capacity.")
	var tooltip := ContentButton.describe_content(&"ability.fire_bolt")
	_check(tooltip.contains("Cooldown: 6.0") and tooltip.contains("Damage: 4.0"), "Unified tooltip reads live ability values.")
	_check(ContentButton.describe_content(&"status.burn").contains("Max stacks: 3"), "Unified tooltip supports statuses.")

	var snapshots := CombatSnapshotBuilder.build_player_army(run, root.get_node("ContentRegistry"))
	_check(snapshots.size() == 12 and snapshots[3].job_id == &"job.archer", "Management changes immediately affect combat preview snapshots.")
	screen.size = Vector2(800, 600)
	await process_frame
	_check(screen.get_node("Page/Layout/ColumnsScroll").is_visible_in_tree(), "Management remains available in a narrow viewport.")

	screen.free()
	if failures == 0:
		print("Management UI tests passed.")
		quit()
	else:
		push_error("Management UI tests failed: %d" % failures)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
