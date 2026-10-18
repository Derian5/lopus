extends SceneTree


var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_name_pool()
	_test_starting_names()
	_test_job_prefix_and_persistence()
	if failures == 0:
		print("Soldier name generator tests passed (%d names)." % SoldierNameGenerator.NAMES.size())
		quit()
	else:
		push_error("Soldier name generator tests failed: %d" % failures)
		quit(1)


func _test_name_pool() -> void:
	var unique_names: Dictionary = {}
	for name in SoldierNameGenerator.NAMES:
		unique_names[name] = true
		_check(not name.is_empty() and name == name.strip_edges(), "Generated-name entries are non-empty and trimmed.")
	_check(SoldierNameGenerator.NAMES.size() == 300, "The shared pool contains 300 names.")
	_check(unique_names.size() == SoldierNameGenerator.NAMES.size(), "The shared name pool contains no duplicates.")


func _test_starting_names() -> void:
	var first := DemoRunFactory.create_starting_run(91234)
	var second := DemoRunFactory.create_starting_run(91234)
	var personal_names: Dictionary = {}
	for index in first.soldiers.size():
		var soldier := first.soldiers[index]
		personal_names[soldier.personal_name] = true
		_check(soldier.personal_name in SoldierNameGenerator.NAMES, "A starting Soldier receives a name from the shared pool.")
		_check(soldier.generated_name == "Militia %s" % soldier.personal_name, "A starting Soldier is displayed as Job plus Name.")
		_check(soldier.personal_name == second.soldiers[index].personal_name, "The same run seed and unit ID generate the same name.")
	_check(personal_names.size() == first.soldiers.size(), "Starting Soldier names are unique within the roster.")


func _test_job_prefix_and_persistence() -> void:
	var run := DemoRunFactory.create_starting_run(81234)
	var soldier := run.soldiers[0]
	var personal_name := soldier.personal_name
	_check(soldier.display_name("Priest") == "Priest %s" % personal_name, "Display formatting always uses the current Job name.")
	SoldierNameGenerator.update_job_name(soldier, "Militia", "Priest")
	_check(soldier.personal_name == personal_name and soldier.generated_name == "Priest %s" % personal_name, "Changing Job changes only the displayed Job prefix.")
	var restored := SoldierState.from_dictionary(soldier.to_dictionary())
	_check(restored.personal_name == personal_name and restored.generated_name == soldier.generated_name, "Save data preserves personal and displayed Soldier names.")

	var legacy := SoldierState.from_dictionary({"generated_name": "Militia 1", "current_job_id": "job.militia"})
	SoldierNameGenerator.update_job_name(legacy, "Militia", "Warrior")
	_check(legacy.personal_name == "1" and legacy.generated_name == "Warrior 1", "A legacy Soldier name remains usable after a Job change.")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
