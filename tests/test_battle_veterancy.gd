extends SceneTree


## Soldiers rank up mid-battle once their pre-battle Veterancy XP plus battle
## contribution reaches the next threshold.
const SESSION_SCENE := preload("res://combat/combat_session.tscn")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry := root.get_node("ContentRegistry")
	var progression := registry.get_definition(&"progression.demo") as ProgressionDefinition
	var run := DemoRunFactory.create_starting_run(4242)
	var soldier := run.soldiers[0]
	soldier.veterancy_xp = progression.veterancy_xp_thresholds[1] - 1
	soldier.veterancy_level = progression.veterancy_level_for_xp(soldier.veterancy_xp)
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.vfx_enabled = false
	root.add_child(session)
	session.size = FormationService.REFERENCE_ARENA
	var enemy := CombatUnitSnapshot.new()
	enemy.runtime_id = "dummy"
	enemy.display_name = "Dummy"
	enemy.team = CombatUnitSnapshot.Team.ENEMY
	enemy.stats.max_hp = 100000.0
	session.setup(CombatSnapshotBuilder.build_player_army(run, registry), [enemy], 1)
	var unit := session.get_combatant_by_runtime_id(soldier.unique_id)
	var gained: Array[CombatEvent] = []
	session.combat_event_emitted.connect(func(event: CombatEvent) -> void:
		if event.event_type == CombatEvent.VETERANCY_GAINED:
			gained.append(event))
	var level_before := unit.snapshot.veterancy_level
	var damage_before := unit.get_effective_stat(&"damage")
	var hp_before := unit.get_effective_stat(&"max_hp")
	session.record_event(CombatEvent.DAMAGE_APPLIED, soldier.unique_id, "dummy", &"attack.basic", &"", 1.0)
	_check(gained.is_empty() and unit.snapshot.veterancy_level == level_before, "A contribution below the next threshold does not rank up.")
	session.record_event(CombatEvent.DAMAGE_APPLIED, soldier.unique_id, "dummy", &"attack.basic", &"", 40.0)
	_check(gained.size() == 1 and unit.snapshot.veterancy_level == level_before + 1, "Reaching the threshold ranks the Soldier up during the battle.")
	var expected := (1.0 + (level_before + 1) * progression.veterancy_damage_growth_per_level) / (1.0 + level_before * progression.veterancy_damage_growth_per_level)
	_check(is_equal_approx(unit.get_effective_stat(&"damage"), damage_before * expected), "The new rank's growth applies to battle stats.")
	_check(unit.get_effective_stat(&"max_hp") > hp_before, "Max HP grows with the rank.")
	session.record_event(CombatEvent.DAMAGE_APPLIED, soldier.unique_id, "dummy", &"attack.basic", &"", 1.0)
	_check(gained.size() == 1, "A rank is gained only once.")
	session.free()
	if failures == 0:
		print("Battle Veterancy tests passed.")
		quit()
	else:
		push_error("Battle Veterancy tests failed: %d" % failures)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
