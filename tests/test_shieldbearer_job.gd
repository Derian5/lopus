extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")

var failures := 0
var registry: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	_test_content_and_stats()
	_test_no_assignment_unlocks()
	_test_attack_reflection()
	if failures == 0:
		print("Shieldbearer Job tests passed.")
		quit()
	else:
		push_error("Shieldbearer Job tests failed: %d" % failures)
		quit(1)


func _test_content_and_stats() -> void:
	var job := registry.get_definition(&"job.shieldbearer", false) as JobDefinition
	var tier_1 := registry.get_definition(&"ability.shieldbearer_professionalism_reflect_tier_1", false) as AbilityDefinition
	var tier_2 := registry.get_definition(&"ability.shieldbearer_professionalism_reflect_tier_2", false) as AbilityDefinition
	_check(job != null and tier_1 != null and tier_2 != null, "Shieldbearer Job and both professionalism tiers are registered.")
	_check(job.available_ability_ids == [tier_1.id, tier_2.id] and tier_2.upgrades_ability_id == tier_1.id, "Shieldbearer skill levels are sequential Market purchases.")
	_check((tier_1.effects[0] as AttackReflectEffect).reflect_percent == 30.0 and (tier_2.effects[0] as AttackReflectEffect).reflect_percent == 60.0, "Shieldbearer professionalism reflects exactly 30% and 60% attack damage.")
	var snapshots := CombatSnapshotBuilder.build_player_army(_shieldbearer_run(6), registry)
	_check(snapshots[0].stats.max_hp == 600.0 and snapshots[0].stats.armor == 80.0 and snapshots[0].stats.attack_speed == 0.5, "Shieldbearer has 600 HP, 80 armor, and 0.5 attacks per second before other modifiers.")
	var tooltip := ContentButton.describe_content(&"job.shieldbearer")
	_check(tooltip.contains("Level 1: Spiked Shields I") and tooltip.contains("Level 2: Spiked Shields II"), "Shieldbearer tooltip lists both purchasable skill levels.")


func _test_no_assignment_unlocks() -> void:
	for count in [2, 3, 5, 6]:
		var snapshots := CombatSnapshotBuilder.build_player_army(_shieldbearer_run(count), registry)
		for snapshot in snapshots:
			var professionalism := snapshot.abilities.filter(func(ability: AbilityDefinition) -> bool: return String(ability.id).begins_with("ability.shieldbearer_professionalism_"))
			_check(professionalism.is_empty(), "%d Shieldbearers do not unlock unpurchased shield skills." % count)


func _test_attack_reflection() -> void:
	var tier_1 := registry.get_definition(&"ability.shieldbearer_professionalism_reflect_tier_1") as AbilityDefinition
	var tier_2 := registry.get_definition(&"ability.shieldbearer_professionalism_reflect_tier_2") as AbilityDefinition
	var defender_snapshot := _snapshot("shieldbearer", CombatUnitSnapshot.Team.PLAYER, 100.0)
	defender_snapshot.abilities.append(tier_1)
	var attacker_snapshot := _snapshot("attacker", CombatUnitSnapshot.Team.ENEMY, 0.0)
	attacker_snapshot.abilities.append(tier_2)
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200.0, 700.0)
	root.add_child(session)
	session.setup([defender_snapshot], [attacker_snapshot], 9061)
	var defender := session.get_combatant_by_runtime_id("shieldbearer")
	var attacker := session.get_combatant_by_runtime_id("attacker")
	defender.set_simulation_active(false)
	attacker.set_simulation_active(false)

	defender.take_damage(100.0, attacker)
	_check(defender.current_hp == 950.0 and attacker.current_hp == 985.0, "Tier 1 reflects 30% of the 50 HP damage remaining after Shieldbearer armor.")
	var attacker_hp := attacker.current_hp
	defender.take_damage(100.0, attacker, &"ability.test", &"effect.test")
	_check(attacker.current_hp == attacker_hp, "Shieldbearer does not reflect ability damage.")
	defender.set_attack_reflection(60.0, tier_2.id, (tier_2.effects[0] as AttackReflectEffect).effect_id)
	defender.take_damage(100.0, attacker)
	_check(attacker.current_hp == attacker_hp - 30.0, "Tier 2 reflects 60% of basic attack HP damage, including ranged basic attacks.")
	var reflected_events := session.events.filter(func(event: CombatEvent) -> bool: return event.event_type == CombatEvent.DAMAGE_APPLIED and event.source_id == "shieldbearer" and String(event.ability_id).begins_with("ability.shieldbearer_professionalism_"))
	_check(reflected_events.size() == 2, "Reflected damage retains Shieldbearer professionalism attribution and does not recursively reflect.")
	session.free()


func _shieldbearer_run(count: int) -> RunState:
	var run := RunState.new()
	for index in count:
		var soldier := SoldierState.new()
		soldier.unique_id = "shieldbearer-%d" % index
		soldier.generated_name = "Shieldbearer %d" % index
		soldier.current_job_id = &"job.shieldbearer"
		run.soldiers.append(soldier)
	var build := JobBuildState.new()
	build.job_id = &"job.shieldbearer"
	run.job_builds.append(build)
	return run


func _snapshot(runtime_id: String, team: int, armor: float) -> CombatUnitSnapshot:
	var snapshot := CombatUnitSnapshot.new()
	snapshot.runtime_id = runtime_id
	snapshot.definition_id = &"test.unit"
	snapshot.display_name = runtime_id
	snapshot.team = team
	snapshot.stats.max_hp = 1000.0
	snapshot.stats.damage = 100.0
	snapshot.stats.attack_speed = 1.0
	snapshot.stats.movement_speed = 100.0
	snapshot.stats.attack_range = 100.0
	snapshot.stats.armor = armor
	return snapshot


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
