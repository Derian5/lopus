extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")

var failures := 0
var registry: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	_test_content_and_thresholds()
	_test_targeting_and_immunity()
	if failures == 0:
		print("Priest professionalism tests passed.")
		quit()
	else:
		push_error("Priest professionalism tests failed: %d" % failures)
		quit(1)


func _test_content_and_thresholds() -> void:
	var job := registry.get_definition(&"job.priest") as JobDefinition
	var tier_1 := registry.get_definition(&"ability.priest_professionalism_cleansing_flame_tier_1") as AbilityDefinition
	var tier_2 := registry.get_definition(&"ability.priest_professionalism_cleansing_flame_tier_2") as AbilityDefinition
	var status_1 := ((tier_1.effects[0] as ApplyStatusEffect).status)
	var status_2 := ((tier_2.effects[0] as ApplyStatusEffect).status)
	_check(job.available_ability_ids == [tier_1.id, tier_2.id] and tier_2.upgrades_ability_id == tier_1.id, "Priest skill levels are sequential Market purchases.")
	_check(tier_1.cooldown_seconds == 6.0 and status_1.default_duration == 4.0 and status_1.stat_modifiers[0].value == 40.0, "Cleansing Flame I has +40 armor for four seconds and a six-second cooldown.")
	_check(tier_2.cooldown_seconds == 4.0 and status_2.default_duration == 6.0 and status_2.stat_modifiers[0].value == 80.0, "Cleansing Flame II has +80 armor for six seconds and a four-second cooldown.")
	_check(status_1.grants_negative_status_immunity and status_2.grants_negative_status_immunity and status_1.polarity == StatusDefinition.Polarity.POSITIVE, "Both Cleansing Flame tiers are positive statuses granting negative-status immunity.")
	for count in [2, 3, 5, 6]:
		var snapshots := CombatSnapshotBuilder.build_player_army(_priest_run(count), registry)
		for snapshot in snapshots:
			var tiers := snapshot.abilities.filter(func(ability: AbilityDefinition) -> bool: return String(ability.id).begins_with("ability.priest_professionalism_"))
			_check(tiers.is_empty(), "%d Priests do not unlock unpurchased Cleansing Flame levels." % count)


func _test_targeting_and_immunity() -> void:
	var tier_2 := registry.get_definition(&"ability.priest_professionalism_cleansing_flame_tier_2") as AbilityDefinition
	var priest_snapshot := _snapshot("priest", CombatUnitSnapshot.Team.PLAYER)
	priest_snapshot.abilities.append(tier_2)
	var ally_a_snapshot := _snapshot("ally-a", CombatUnitSnapshot.Team.PLAYER)
	var ally_b_snapshot := _snapshot("ally-b", CombatUnitSnapshot.Team.PLAYER)
	var enemy_a_snapshot := _snapshot("enemy-a", CombatUnitSnapshot.Team.ENEMY)
	var enemy_b_snapshot := _snapshot("enemy-b", CombatUnitSnapshot.Team.ENEMY)
	var enemy_c_snapshot := _snapshot("enemy-c", CombatUnitSnapshot.Team.ENEMY)
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200.0, 700.0)
	root.add_child(session)
	session.setup([priest_snapshot, ally_a_snapshot, ally_b_snapshot], [enemy_a_snapshot, enemy_b_snapshot, enemy_c_snapshot], 9310)
	for combatant in session.combatants:
		combatant.set_simulation_active(false)
	var priest := session.get_combatant_by_runtime_id("priest")
	var ally_a := session.get_combatant_by_runtime_id("ally-a")
	var ally_b := session.get_combatant_by_runtime_id("ally-b")
	session.get_combatant_by_runtime_id("enemy-a").target = ally_a
	session.get_combatant_by_runtime_id("enemy-b").target = ally_b
	session.get_combatant_by_runtime_id("enemy-c").target = ally_b
	_check(session.resolve_ability_target(priest, tier_2) == ally_b, "Cleansing Flame targets the ally selected by the most enemies.")
	_check(priest._try_activate_ability(tier_2, false), "Cleansing Flame activates when an ally is under enemy pressure.")
	_check(ally_b.get_effective_stat(&"armor") == 80.0 and ally_b.has_negative_status_immunity(), "Cleansing Flame II grants 80 armor and negative-status immunity.")
	_check(priest.ability_cooldowns[tier_2.id] == 4.0, "Cleansing Flame II starts its four-second cooldown on cast.")

	var negative := StatusDefinition.new()
	negative.id = &"status.test_priest_immunity"
	negative.default_duration = 10.0
	negative.polarity = StatusDefinition.Polarity.NEGATIVE
	negative.prevents_actions = true
	ally_b.apply_status(negative, priest, &"ability.test")
	_check(not ally_b.has_status(negative.id), "Cleansing Flame blocks newly applied negative statuses.")
	ally_b._update_runtime(6.0)
	ally_b.apply_status(negative, priest, &"ability.test")
	_check(ally_b.get_effective_stat(&"armor") == 0.0 and ally_b.has_status(negative.id), "Armor and immunity expire together after six seconds.")
	session.free()


func _priest_run(count: int) -> RunState:
	var run := RunState.new()
	for index in count:
		var soldier := SoldierState.new()
		soldier.unique_id = "priest-%d" % index
		soldier.generated_name = "Priest %d" % index
		soldier.current_job_id = &"job.priest"
		run.soldiers.append(soldier)
	var build := JobBuildState.new()
	build.job_id = &"job.priest"
	run.job_builds.append(build)
	return run


func _snapshot(runtime_id: String, team: int) -> CombatUnitSnapshot:
	var snapshot := CombatUnitSnapshot.new()
	snapshot.runtime_id = runtime_id
	snapshot.definition_id = &"test.unit"
	snapshot.display_name = runtime_id
	snapshot.team = team
	snapshot.stats.max_hp = 1000.0
	snapshot.stats.damage = 10.0
	snapshot.stats.attack_speed = 1.0
	snapshot.stats.movement_speed = 100.0
	snapshot.stats.attack_range = 100.0
	snapshot.stats.armor = 0.0
	return snapshot


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
