extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var statistics := CombatStatistics.new()
	var player_units := CombatDemoFactory.create_player_army(1, 1)
	var enemies := CombatDemoFactory.create_enemy_army(1, 0)
	var hero := player_units[0]
	var soldier := player_units[1]
	var enemy := enemies[0]
	statistics.register_unit(hero)
	statistics.register_unit(soldier)
	statistics.register_unit(enemy)

	var events: Array[CombatEvent] = [
		CombatEvent.new(0.1, CombatEvent.ATTACK_STARTED, hero.runtime_id, enemy.runtime_id, &"attack.basic", &"attack.basic"),
		CombatEvent.new(0.2, CombatEvent.ABILITY_USED, hero.runtime_id, enemy.runtime_id, &"ability.test_fire"),
		CombatEvent.new(0.3, CombatEvent.DAMAGE_APPLIED, hero.runtime_id, enemy.runtime_id, &"ability.test_fire", &"effect.damage", 25.0),
		CombatEvent.new(0.4, CombatEvent.HEALING_APPLIED, hero.runtime_id, soldier.runtime_id, &"ability.test_heal", &"effect.heal", 10.0),
		CombatEvent.new(0.5, CombatEvent.STATUS_APPLIED, hero.runtime_id, enemy.runtime_id, &"ability.test_fire", &"status.burn"),
		CombatEvent.new(0.6, CombatEvent.DAMAGE_APPLIED, soldier.runtime_id, enemy.runtime_id, &"attack.basic", &"attack.basic", 5.0),
		CombatEvent.new(0.7, CombatEvent.UNIT_DIED, hero.runtime_id, enemy.runtime_id, &"", &"status.burn"),
		CombatEvent.new(1.0, CombatEvent.BATTLE_FINISHED, "player", "", &"", &"", 42.0),
	]
	for event in events:
		statistics.consume(event)

	var hero_data: Dictionary = statistics.unit_stats[hero.runtime_id]
	var soldier_data: Dictionary = statistics.unit_stats[soldier.runtime_id]
	var enemy_data: Dictionary = statistics.unit_stats[enemy.runtime_id]
	_check(is_equal_approx(float(hero_data.damage_dealt), 25.0), "Unit damage is aggregated.")
	_check(is_equal_approx(float(hero_data.healing), 10.0), "Unit healing is aggregated.")
	_check(int(hero_data.kills) == 1, "Unit kills are aggregated.")
	_check(int(hero_data.ability_uses) == 1, "Unit ability uses are aggregated.")
	_check(is_equal_approx(float(soldier_data.damage_dealt), 5.0), "Soldier damage is aggregated.")
	_check(int(soldier_data.battles_survived) == 1, "Soldier survival is recorded.")
	_check(int(enemy_data.deaths) == 1, "Victim death is recorded.")
	_check(enemy_data.killer_id == hero.runtime_id, "Death stores the killer.")
	_check(enemy_data.last_effect_id == "status.burn", "Death stores the last effect.")

	var hero_aggregate: Dictionary = statistics.hero_stats[String(hero.definition_id)]
	var job_aggregate: Dictionary = statistics.job_stats[String(soldier.job_id)]
	var fire_aggregate: Dictionary = statistics.ability_stats["ability.test_fire"]
	_check(is_equal_approx(float(hero_aggregate.damage_dealt), 25.0), "Hero aggregation matches unit events.")
	_check(is_equal_approx(float(job_aggregate.damage_dealt), 5.0), "Job aggregation matches unit events.")
	_check(is_equal_approx(float(fire_aggregate.damage), 25.0), "Ability damage is aggregated.")
	_check(int(fire_aggregate.uses) == 1, "Ability uses are aggregated.")
	_check(int(fire_aggregate.statuses_applied) == 1, "Ability statuses are aggregated.")
	_check(statistics.winner == &"player" and is_equal_approx(statistics.duration, 42.0), "Battle result is recorded.")

	for event_type in [
		CombatEvent.ATTACK_STARTED,
		CombatEvent.DAMAGE_APPLIED,
		CombatEvent.HEALING_APPLIED,
		CombatEvent.ABILITY_USED,
		CombatEvent.STATUS_APPLIED,
		CombatEvent.UNIT_DIED,
		CombatEvent.BATTLE_FINISHED,
	]:
		_check(statistics.get_event_count(event_type) > 0, "Event type is consumed: %s" % event_type)

	_test_contribution_filters()
	_test_summon_contribution_attribution()
	await _test_effective_health_changes()

	if failures == 0:
		print("Combat statistics tests passed.")
		quit()
	else:
		push_error("Combat statistics tests failed: %d" % failures)
		quit(1)


func _test_contribution_filters() -> void:
	var statistics := CombatStatistics.new()
	var player_units := CombatDemoFactory.create_player_army(1, 1)
	var enemy := CombatDemoFactory.create_enemy_army(1, 0)[0]
	for snapshot in [player_units[0], player_units[1], enemy]:
		statistics.register_unit(snapshot)
	var hero := player_units[0]
	var soldier := player_units[1]
	statistics.consume(CombatEvent.new(0.1, CombatEvent.DAMAGE_APPLIED, hero.runtime_id, hero.runtime_id, &"", &"", 7.0))
	statistics.consume(CombatEvent.new(0.2, CombatEvent.DAMAGE_APPLIED, hero.runtime_id, soldier.runtime_id, &"", &"", 8.0))
	statistics.consume(CombatEvent.new(0.3, CombatEvent.DAMAGE_APPLIED, enemy.runtime_id, soldier.runtime_id, &"", &"", 9.0))
	statistics.consume(CombatEvent.new(0.4, CombatEvent.HEALING_APPLIED, hero.runtime_id, soldier.runtime_id, &"", &"", 10.0))
	statistics.consume(CombatEvent.new(0.5, CombatEvent.HEALING_APPLIED, enemy.runtime_id, soldier.runtime_id, &"", &"", 6.0))
	statistics.consume(CombatEvent.new(0.6, CombatEvent.UNIT_DIED, enemy.runtime_id, hero.runtime_id, &"", &""))
	statistics.consume(CombatEvent.new(0.7, CombatEvent.DAMAGE_APPLIED, hero.runtime_id, enemy.runtime_id, &"", &"", 5.0))
	statistics.consume(CombatEvent.new(0.8, CombatEvent.UNIT_DIED, enemy.runtime_id, soldier.runtime_id, &"", &""))
	statistics.consume(CombatEvent.new(0.9, CombatEvent.DAMAGE_APPLIED, enemy.runtime_id, soldier.runtime_id, &"", &"", 7.0))
	var hero_data: Dictionary = statistics.unit_stats[hero.runtime_id]
	var soldier_data: Dictionary = statistics.unit_stats[soldier.runtime_id]
	var enemy_data: Dictionary = statistics.unit_stats[enemy.runtime_id]
	_check(is_zero_approx(float(hero_data.damage_dealt)), "Self/friendly damage and post-death damage grant no Damage Dealt contribution.")
	_check(is_equal_approx(float(soldier_data.damage_taken), 24.0), "Damage Taken remains a diagnostic total for actual damage events.")
	_check(is_equal_approx(float(soldier_data.damage_tanked), 9.0), "Only hostile damage received while alive grants tanking contribution.")
	_check(is_equal_approx(float(hero_data.effective_healing), 10.0), "Same-team effective healing grants contribution.")
	_check(is_equal_approx(float(enemy_data.damage_dealt), 9.0), "A living hostile source receives Damage Dealt contribution.")
	_check(is_equal_approx(float(enemy_data.damage_tanked), 5.0), "A delayed hostile hit still grants tanking contribution to its living target.")


func _test_summon_contribution_attribution() -> void:
	var statistics := CombatStatistics.new()
	var summoner := CombatDemoFactory.create_player_army(0, 1)[0]
	var enemy := CombatDemoFactory.create_enemy_army(1, 0)[0]
	var summon := CombatUnitSnapshot.new()
	summon.runtime_id = "summon-attribution-test"
	summon.definition_id = &"enemy.summoned_brawler"
	summon.display_name = "Summoned Brawler"
	summon.team = summoner.team
	summon.unit_kind = CombatUnitSnapshot.UnitKind.SUMMON
	summon.summoner_runtime_id = summoner.runtime_id
	summon.summoner_contribution_percent = 50.0
	for snapshot in [summoner, summon, enemy]:
		statistics.register_unit(snapshot)
	statistics.consume(CombatEvent.new(0.1, CombatEvent.DAMAGE_APPLIED, summon.runtime_id, enemy.runtime_id, &"attack.basic", &"attack.basic", 20.0))
	statistics.consume(CombatEvent.new(0.2, CombatEvent.DAMAGE_APPLIED, enemy.runtime_id, summon.runtime_id, &"attack.basic", &"attack.basic", 15.0))
	statistics.consume(CombatEvent.new(0.3, CombatEvent.HEALING_APPLIED, summon.runtime_id, summoner.runtime_id, &"ability.test_heal", &"effect.heal", 10.0))
	var summoner_data: Dictionary = statistics.unit_stats[summoner.runtime_id]
	var summon_data: Dictionary = statistics.unit_stats[summon.runtime_id]
	_check(
		is_equal_approx(float(summoner_data.damage_dealt), 10.0)
		and is_equal_approx(float(summoner_data.damage_tanked), 7.5)
		and is_equal_approx(float(summoner_data.effective_healing), 5.0),
		"Summon damage, tanking, and healing contribution are attributed to its summoner at the configured percentage."
	)
	_check(
		is_zero_approx(float(summon_data.damage_dealt))
		and is_zero_approx(float(summon_data.damage_tanked))
		and is_zero_approx(float(summon_data.effective_healing))
		and is_equal_approx(float(summon_data.damage_taken), 15.0),
		"Summon contribution is not duplicated while its diagnostic damage taken remains visible."
	)
	var job_data: Dictionary = statistics.job_stats[String(summoner.job_id)]
	_check(is_equal_approx(float(job_data.damage_dealt), 10.0) and is_equal_approx(float(job_data.damage_tanked), 7.5) and is_equal_approx(float(job_data.effective_healing), 5.0), "Scaled summon contribution rolls into the summoner's Job aggregate.")


func _test_effective_health_changes() -> void:
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200.0, 600.0)
	root.add_child(session)
	session.setup(CombatDemoFactory.create_player_army(1, 1), CombatDemoFactory.create_enemy_army(1, 0), 9901)
	await process_frame
	session.battle_active = false
	for combatant in session.combatants:
		combatant.set_simulation_active(false)
	var hero := _unit(session, "player-hero-00")
	var soldier := _unit(session, "player-soldier-00")
	var enemy := _unit(session, "enemy-00")
	enemy.current_hp = 5.0
	var applied_damage := enemy.take_damage(100.0, hero)
	_check(is_equal_approx(applied_damage, 5.0), "Overkill damage is capped to actual HP lost.")
	_check(is_equal_approx(float(session.statistics.unit_stats[hero.snapshot.runtime_id].damage_dealt), 5.0), "Overkill grants XP contribution only for actual HP lost.")
	soldier.current_hp = soldier.get_effective_stat(&"max_hp") - 3.0
	var applied_healing := soldier.receive_healing(100.0, hero, &"ability.test_heal", &"effect.heal")
	_check(is_equal_approx(applied_healing, 3.0), "Overhealing is capped to actual HP restored.")
	_check(is_equal_approx(float(session.statistics.unit_stats[hero.snapshot.runtime_id].effective_healing), 3.0), "Overhealing grants XP contribution only for actual HP restored.")
	soldier.current_hp = soldier.get_effective_stat(&"max_hp") + 1.0
	_check(is_zero_approx(soldier.receive_healing(10.0, hero, &"ability.test_heal", &"effect.heal")), "Healing cannot become negative above effective max HP.")
	session.free()


func _unit(session: CombatSession, runtime_id: String) -> Combatant:
	for combatant in session.combatants:
		if combatant.snapshot.runtime_id == runtime_id:
			return combatant
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
