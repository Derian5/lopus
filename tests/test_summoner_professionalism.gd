extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")

var failures := 0
var registry: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	_test_content_and_thresholds()
	_test_merge_and_split()
	_test_tier_two_and_death()
	if failures == 0:
		print("Summoner professionalism tests passed.")
		quit()
	else:
		push_error("Summoner professionalism tests failed: %d" % failures)
		quit(1)


func _test_content_and_thresholds() -> void:
	var job := registry.get_definition(&"job.summoner") as JobDefinition
	var tier_1 := registry.get_definition(&"ability.summoner_professionalism_merge_tier_1") as AbilityDefinition
	var tier_2 := registry.get_definition(&"ability.summoner_professionalism_merge_tier_2") as AbilityDefinition
	_check(job.professionalism_thresholds == [3, 6], "Summoner professionalism unlocks at three and six assignments.")
	_check(tier_1.cooldown_seconds == 20.0 and tier_1.initial_cooldown_seconds == 20.0 and tier_2.cooldown_seconds == 20.0 and tier_2.initial_cooldown_seconds == 20.0, "Both Convergence tiers start on and use a 20-second cooldown.")
	_check((tier_1.effects[0] as SummonMergeEffect).stat_multiplier == 1.0 and (tier_2.effects[0] as SummonMergeEffect).stat_multiplier == 2.0, "Convergence tiers use 100% and 200% aggregate stat multipliers.")
	for count in [2, 3, 5, 6]:
		var snapshots := CombatSnapshotBuilder.build_player_army(_summoner_run(count), registry)
		var expected: StringName
		if count >= 6:
			expected = tier_2.id
		elif count >= 3:
			expected = tier_1.id
		for snapshot in snapshots:
			var tiers := snapshot.abilities.filter(func(ability: AbilityDefinition) -> bool: return String(ability.id).begins_with("ability.summoner_professionalism_"))
			_check(tiers.size() == (0 if expected.is_empty() else 1) and (expected.is_empty() or tiers[0].id == expected), "%d Summoners receive only the highest Convergence tier." % count)


func _test_merge_and_split() -> void:
	var tier_1 := registry.get_definition(&"ability.summoner_professionalism_merge_tier_1") as AbilityDefinition
	var session := _summoner_session(tier_1, 9410)
	var summoner := session.get_combatant_by_runtime_id("summoner")
	_check(summoner.ability_cooldowns[tier_1.id] == 20.0 and not summoner._try_activate_ability(tier_1, true), "Convergence cannot activate during its initial cooldown.")
	var components := _spawn_components(session, summoner, 3)
	for component in components:
		component.snapshot.stats.armor = 10.0
	summoner.ability_cooldowns[tier_1.id] = 0.0
	_check(summoner._try_activate_ability(tier_1, true), "Convergence activates after its initial cooldown when at least two summons exist.")
	var merge: Dictionary = session.active_summon_merges[summoner.snapshot.runtime_id]
	var merged := merge.merged as Combatant
	_check(merged.get_effective_stat(&"max_hp") == 510.0 and merged.get_effective_stat(&"damage") == 18.0 and merged.get_effective_stat(&"armor") == 30.0, "Convergence I sums HP, damage, and armor at 100%.")
	_check(merged.get_effective_stat(&"attack_speed") == 1.6 and merged.get_effective_stat(&"attack_range") == 40.0 and merged.get_effective_stat(&"movement_speed") == 105.0, "Merged attack speed gains 20% per summon while range and movement remain unsummed.")
	_check(components.all(func(component: Combatant) -> bool: return component.temporarily_removed and not component.visible and not component.is_alive()), "Absorbed summons are suspended without being killed.")
	_check(not session.can_spawn_summon(summoner, &"ability.summoner_job_summon", &"effect.summoner_job_summon", 6), "Ordinary summoning is blocked during Convergence.")
	merged.current_hp = merged.get_effective_stat(&"max_hp") * 0.5
	session._update_summon_merges(10.0)
	_check(not session.active_summon_merges.has(summoner.snapshot.runtime_id), "Convergence splits after ten seconds.")
	_check(components.all(func(component: Combatant) -> bool: return not component.temporarily_removed and component.visible and is_equal_approx(component.current_hp, 85.0)), "Split summons inherit the merged creature's remaining HP ratio.")
	_check(session.can_spawn_summon(summoner, &"ability.summoner_job_summon", &"effect.summoner_job_summon", 6), "Ordinary summoning resumes after the merged creature splits.")
	session.free()


func _test_tier_two_and_death() -> void:
	var tier_2 := registry.get_definition(&"ability.summoner_professionalism_merge_tier_2") as AbilityDefinition
	var session := _summoner_session(tier_2, 9411)
	var summoner := session.get_combatant_by_runtime_id("summoner")
	var components := _spawn_components(session, summoner, 2)
	for component in components:
		component.snapshot.stats.armor = 10.0
	summoner.ability_cooldowns[tier_2.id] = 0.0
	summoner._try_activate_ability(tier_2, true)
	var merged := (session.active_summon_merges[summoner.snapshot.runtime_id] as Dictionary).merged as Combatant
	_check(merged.get_effective_stat(&"max_hp") == 680.0 and merged.get_effective_stat(&"damage") == 24.0 and merged.get_effective_stat(&"armor") == 40.0 and merged.get_effective_stat(&"attack_speed") == 1.4, "Convergence II doubles summed HP, damage, and armor without doubling attack speed.")
	merged.force_die(null, &"effect.test")
	_check(components.all(func(component: Combatant) -> bool: return component.state == Combatant.State.DEAD and component.current_hp == 0.0), "Killing the merged creature kills every absorbed summon.")
	session.free()


func _summoner_session(tier: AbilityDefinition, seed: int) -> CombatSession:
	var summoner_snapshot := _snapshot("summoner", CombatUnitSnapshot.Team.PLAYER)
	summoner_snapshot.abilities.append(tier)
	var enemy_snapshot := _snapshot("enemy", CombatUnitSnapshot.Team.ENEMY)
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200.0, 700.0)
	root.add_child(session)
	session.setup([summoner_snapshot], [enemy_snapshot], seed)
	for combatant in session.combatants:
		combatant.set_simulation_active(false)
	return session


func _spawn_components(session: CombatSession, summoner: Combatant, count: int) -> Array[Combatant]:
	var definition := registry.get_definition(&"enemy.summoned_brawler") as EnemyDefinition
	var result: Array[Combatant] = []
	for index in count:
		var component := session.spawn_summon(summoner, definition, &"ability.summoner_job_summon", &"effect.summoner_job_summon", 6, 25.0)
		component.set_simulation_active(false)
		result.append(component)
	return result


func _summoner_run(count: int) -> RunState:
	var run := RunState.new()
	for index in count:
		var soldier := SoldierState.new()
		soldier.unique_id = "summoner-%d" % index
		soldier.generated_name = "Summoner %d" % index
		soldier.current_job_id = &"job.summoner"
		run.soldiers.append(soldier)
	var build := JobBuildState.new()
	build.job_id = &"job.summoner"
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
