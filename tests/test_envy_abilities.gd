extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")
const SELECTED_PANEL_SCENE := preload("res://ui/combat/selected_unit_panel.tscn")
const ENVY_ID := &"hero.army_support"
const ABILITY_IDS: Array[StringName] = [
	&"ability.envy_stat_theft",
	&"ability.envy_strongest_ally_damage",
	&"ability.envy_illusion",
	&"ability.envy_execute",
	&"ability.envy_post_combat_xp",
	&"ability.envy_dart_volley",
]

var failures := 0
var registry: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	_test_content_levels_and_rewards()
	_test_stat_theft_and_damage_copy()
	_test_illusion_and_execute()
	_test_dart_volley()
	_test_post_combat_xp()
	if failures == 0:
		print("Envy ability tests passed.")
		quit()
	else:
		push_error("Envy ability tests failed: %d" % failures)
		quit(1)


func _test_content_levels_and_rewards() -> void:
	for ability_id in ABILITY_IDS:
		var ability := registry.get_definition(ability_id, false) as AbilityDefinition
		_check(ability != null and ability.allowed_hero_ids == [ENVY_ID] and ability.hero_levels.size() == 4, "%s is a four-level Envy-exclusive ability." % ability_id)
	var theft := _ability(&"ability.envy_stat_theft", 4)
	var copy := theft.effects[0] as EnvyStatTheftEffect
	var might := _ability(&"ability.envy_strongest_ally_damage", 4).effects[0] as EnvyStrongestAllyDamageEffect
	var illusion := _ability(&"ability.envy_illusion", 4).effects[0] as EnvyIllusionEffect
	var execute := _ability(&"ability.envy_execute", 4)
	var xp := _ability(&"ability.envy_post_combat_xp", 4).effects[0] as EnvyPostCombatXpEffect
	var darts := _ability(&"ability.envy_dart_volley", 4).effects[0] as EnvyDartVolleyEffect
	_check(theft.cooldown_seconds == 3.0 and copy.steal_percent == 80.0 and copy.duration == 12.0, "Covetous Exchange reaches 80% theft on a three-second cooldown.")
	_check(might.bonus_percent == 120.0 and illusion.stat_percent == 160.0, "Borrowed Might and Perfect Imitation reach their Level 4 scaling.")
	_check(execute.cooldown_seconds == 8.0 and (execute.effects[0] as EnvyExecuteEffect).health_threshold == 0.4, "Coveted Demise reaches 40% HP and an eight-second cooldown.")
	_check(xp.bonus_percent == 60.0 and darts.damage == 48.0 and darts.movement_slow_percent == 30.0, "Envy's XP and dart Level 4 values are authored correctly.")
	var run := DemoRunFactory.create_starting_run(9600)
	var route := registry.get_definition(RunState.ROUTE_DEFINITION_ID) as RouteDefinition
	var envy_candidates := HeroAbilityRewardService._candidates(run.heroes[1], registry, route)
	var greed_candidates := HeroAbilityRewardService._candidates(run.heroes[0], registry, route)
	_check(envy_candidates.size() == 6 and envy_candidates.all(func(data: Dictionary) -> bool: return ABILITY_IDS.has(data.ability_id)), "Only Envy receives all six Envy reward candidates.")
	_check(not greed_candidates.any(func(data: Dictionary) -> bool: return ABILITY_IDS.has(data.ability_id)), "Other Heroes receive no Envy reward candidates.")


func _test_stat_theft_and_damage_copy() -> void:
	var envy := _snapshot("envy", ENVY_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO, 100.0, 10.0)
	envy.abilities = [_ability(&"ability.envy_strongest_ally_damage", 2)]
	var soldier := _snapshot("soldier", &"job.militia", CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.SOLDIER, 100.0, 40.0)
	var allied_hero := _snapshot("hero", &"hero.control_savant", CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO, 100.0, 200.0)
	var enemy := _snapshot("enemy", &"enemy.raider", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 200.0, 50.0)
	enemy.stats.attack_speed = 2.0
	enemy.stats.armor = 20.0
	var session := _session([envy, soldier, allied_hero], [enemy], 9601)
	var envy_unit := _unit(session, "envy")
	var soldier_unit := _unit(session, "soldier")
	var allied_hero_unit := _unit(session, "hero")
	var enemy_unit := _unit(session, "enemy")
	_check(is_equal_approx(envy_unit.get_effective_stat(&"damage"), 22.0), "Borrowed Might ignores the stronger allied Hero and adds 30% of the Soldier's current damage.")
	allied_hero_unit.force_die(null, &"effect.test")
	var summon := _snapshot("summon", &"enemy.summoned_brawler", CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.SUMMON, 100.0, 60.0)
	session._spawn_combatant(summon, Vector2(300, 300), session.get_arena_bounds()).set_simulation_active(false)
	_check(is_equal_approx(envy_unit.get_effective_stat(&"damage"), 28.0), "Borrowed Might dynamically includes allied summons.")
	_unit(session, "summon").force_die(null, &"effect.test")
	enemy_unit.current_hp = 190.0
	session.deliver_ability(envy_unit, envy_unit, _ability(&"ability.envy_stat_theft", 2))
	_check(is_equal_approx(enemy_unit.get_effective_stat(&"max_hp"), 160.0) and is_equal_approx(enemy_unit.current_hp, 160.0), "Stat theft removes 20% current max HP and safely clamps enemy HP.")
	_check(
		is_equal_approx(soldier_unit.get_effective_stat(&"max_hp"), 140.0)
		and is_equal_approx(soldier_unit.get_effective_stat(&"damage"), 50.0)
		and is_equal_approx(soldier_unit.get_effective_stat(&"attack_speed"), 1.4)
		and is_equal_approx(soldier_unit.get_effective_stat(&"armor"), 4.0),
		"The exact stolen additive values for all four stats transfer to the only eligible ally."
	)
	enemy_unit._update_runtime(12.1)
	soldier_unit._update_runtime(12.1)
	_check(is_equal_approx(enemy_unit.get_effective_stat(&"max_hp"), 200.0) and is_equal_approx(soldier_unit.get_effective_stat(&"max_hp"), 100.0), "Both sides of the theft expire after 12 seconds.")
	session.free()


func _test_illusion_and_execute() -> void:
	var envy := _snapshot("envy", ENVY_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO, 100.0, 10.0)
	var weak := _snapshot("a-weak", &"enemy.raider", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 100.0, 20.0)
	var strong := _snapshot("b-strong", &"enemy.raider", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 300.0, 50.0)
	strong.abilities = [_ability(&"ability.enemy_summon", 1)]
	var boss := _snapshot("boss", &"enemy.iron_warden", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 1000.0, 500.0)
	boss.is_boss = true
	var session := _session([envy], [weak, strong, boss], 9602)
	var envy_unit := _unit(session, "envy")
	var strong_unit := _unit(session, "b-strong")
	var speed_buff := StatModifier.new()
	speed_buff.stat = "movement_speed"
	speed_buff.operation = StatModifier.Operation.MULTIPLY
	speed_buff.value = 1.3
	strong_unit.add_temporary_modifier(speed_buff, 5.0, envy_unit, &"ability.envy_stat_theft", &"effect.test_speed")
	session.deliver_ability(envy_unit, envy_unit, _ability(&"ability.envy_illusion", 2))
	var illusion := _unit(session, "envy-illusion-0001")
	_check(illusion != null and illusion.snapshot.definition_id == strong.definition_id and illusion.snapshot.abilities.is_empty(), "Perfect Imitation copies the strongest non-boss enemy and strips all abilities.")
	_check(is_equal_approx(illusion.snapshot.stats.max_hp, 120.0) and is_equal_approx(illusion.snapshot.stats.damage, 20.0) and illusion.snapshot.team == CombatUnitSnapshot.Team.PLAYER, "The Level 2 illusion receives 40% of copied current combat stats as an ally.")
	_check(is_equal_approx(illusion.snapshot.stats.movement_speed, 130.0), "The illusion exactly copies the enemy's current effective movement speed without level scaling.")
	session.deliver_ability(envy_unit, envy_unit, _ability(&"ability.envy_illusion", 2))
	_check(_unit(session, "envy-illusion-0002") != null, "Multiple deterministic illusion IDs accumulate without replacing earlier illusions.")
	var weak_unit := _unit(session, "a-weak")
	var boss_unit := _unit(session, "boss")
	weak_unit.current_hp = 15.0
	weak_unit.last_stand_remaining = 5.0
	strong_unit.current_hp = 90.0
	boss_unit.current_hp = 1.0
	session.deliver_ability(envy_unit, envy_unit, _ability(&"ability.envy_execute", 1))
	_check(not weak_unit.is_alive() and weak_unit.last_stand_remaining == 0.0 and strong_unit.is_alive() and boss_unit.is_alive(), "Execute globally selects an eligible non-boss target, ignores healthier enemies and bosses, and bypasses last stand.")
	_check(int(session.statistics.unit_stats["envy"].kills) == 1 and String(session.statistics.unit_stats["a-weak"].killer_id) == "envy", "Execute preserves Envy kill attribution and statistics.")
	session.free()


func _test_dart_volley() -> void:
	var envy := _snapshot("envy", ENVY_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO, 100.0, 10.0)
	var enemies: Array[CombatUnitSnapshot] = []
	for index in 4:
		enemies.append(_snapshot("enemy-%d" % index, &"enemy.raider", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 100.0, 10.0))
	var session := _session([envy], enemies, 9603)
	var envy_unit := _unit(session, "envy")
	session.deliver_ability(envy_unit, envy_unit, _ability(&"ability.envy_dart_volley", 2))
	_check(session.get_node("Projectiles").get_child_count() == 3, "Jealous Barbs launches exactly three darts at distinct enemies when four are available.")
	for projectile in session.get_node("Projectiles").get_children():
		projectile.position = projectile.target.position
		projectile._physics_process(0.01)
	var hit_count := 0
	for index in 4:
		var enemy := _unit(session, "enemy-%d" % index)
		if enemy.has_status(&"status.envy_dart_poison"):
			hit_count += 1
			_check(is_equal_approx(enemy.current_hp, 100.0) and is_equal_approx(enemy.get_effective_stat(&"movement_speed"), 70.0), "Darts deal no impact damage and apply one battle-long poison and 30% movement slow.")
			enemy._update_runtime(0.99)
			_check(is_equal_approx(enemy.current_hp, 100.0), "Jealous Poison does not deal damage before its one-second interval.")
			enemy._update_runtime(0.02)
			_check(is_equal_approx(enemy.current_hp, 76.0), "Level 2 Jealous Poison deals its authored 24 damage after one second.")
			enemy._update_runtime(1.0)
			_check(is_equal_approx(enemy.current_hp, 52.0), "Jealous Poison continues dealing damage every second.")
			enemy.apply_envy_dart_poison(24.0, 30.0, envy_unit, &"ability.envy_dart_volley", &"effect.envy_dart_volley")
			_check(enemy.statuses.filter(func(status: StatusInstance) -> bool: return status.definition.id == &"status.envy_dart_poison").size() == 1 and enemy.temporary_modifiers.size() == 1, "Repeated darts do not stack poison or slow.")
			var panel: SelectedUnitPanel = SELECTED_PANEL_SCENE.instantiate()
			root.add_child(panel)
			panel.show_combatant(enemy)
			_check(panel.status_summary_text().contains("Jealous Poison") and panel.status_summary_text().contains("-30% Move Speed") and panel.status_summary_text().contains("permanent"), "The selected-unit status indicators expose authored debuffs with values and duration.")
			panel.free()
	_check(hit_count == 3, "No enemy receives more than one dart in a volley.")
	session.free()


func _test_post_combat_xp() -> void:
	var run := DemoRunFactory.create_starting_run(9604)
	run.run_phase = &"combat"
	var result := CombatResult.new()
	result.result_id = "result-envy-xp"
	result.winner = &"player"
	result.encounter_id = run.selected_encounter_id
	for hero in run.heroes:
		result.unit_statistics.append(_result_stats(hero.unique_id, hero.definition_id, CombatUnitSnapshot.UnitKind.HERO, 10, 30.0 if hero.definition_id == ENVY_ID else 0.0))
	result.unit_statistics.append(_result_stats(run.soldiers[0].unique_id, &"job.militia", CombatUnitSnapshot.UnitKind.SOLDIER, 10, 0.0))
	result.unit_statistics.append(_result_stats("temporary-summon", &"enemy.summoned_brawler", CombatUnitSnapshot.UnitKind.SUMMON, 10, 0.0))
	_check(CombatResultApplicator.apply(result, run, registry), "An Envy XP result applies successfully.")
	_check(run.heroes.all(func(hero: HeroState) -> bool: return hero.xp == 13) and run.soldiers[0].veterancy_xp == 13, "Level 2 grants every participating persistent Hero and surviving Soldier a rounded 30% XP bonus.")
	_check(int(result.application_summary.hero_changes[0].base_xp) == 10 and int(result.application_summary.hero_changes[0].bonus_xp) == 3 and result.application_summary.xp_bonus_percent == 30.0, "The result summary explicitly separates base XP, rounded Envy bonus, and percentage.")
	_check(not CombatResultApplicator.apply(result, run, registry) and run.heroes.all(func(hero: HeroState) -> bool: return hero.xp == 13), "Envy's post-combat XP bonus remains idempotent.")


func _result_stats(runtime_id: String, definition_id: StringName, kind: int, total_xp: int, bonus_percent: float) -> Dictionary:
	return {
		"runtime_id": runtime_id, "display_name": runtime_id, "definition_id": String(definition_id),
		"team": CombatUnitSnapshot.Team.PLAYER, "unit_kind": kind, "alive": true,
		"damage_dealt": 0.0, "damage_taken": 0.0, "damage_tanked": 0.0,
		"healing": 0.0, "effective_healing": 0.0, "kills": 0, "deaths": 0,
		"ability_uses": 0, "battles_survived": 0, "post_combat_xp_bonus_percent": bonus_percent,
		"contribution": {"damage_dealt": 0.0, "effective_healing": 0.0, "damage_tanked": 0.0, "damage_xp": 0, "healing_xp": 0, "tanking_xp": 0, "total_xp": total_xp},
	}


func _ability(ability_id: StringName, level: int) -> AbilityDefinition:
	return (registry.get_definition(ability_id) as AbilityDefinition).for_hero_level(level)


func _snapshot(runtime_id: String, definition_id: StringName, team: int, kind: int, hp: float, damage: float) -> CombatUnitSnapshot:
	var snapshot := CombatUnitSnapshot.new()
	snapshot.runtime_id = runtime_id
	snapshot.definition_id = definition_id
	snapshot.display_name = runtime_id
	snapshot.team = team
	snapshot.unit_kind = kind
	snapshot.stats.max_hp = hp
	snapshot.stats.damage = damage
	snapshot.stats.attack_speed = 1.0
	snapshot.stats.movement_speed = 100.0
	snapshot.stats.attack_range = 100.0
	snapshot.stats.armor = 0.0
	return snapshot


func _session(players: Array[CombatUnitSnapshot], enemies: Array[CombatUnitSnapshot], seed: int) -> CombatSession:
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200.0, 600.0)
	root.add_child(session)
	session.setup(players, enemies, seed)
	for combatant in session.combatants:
		combatant.set_simulation_active(false)
	return session


func _unit(session: CombatSession, runtime_id: String) -> Combatant:
	return session.get_combatant_by_runtime_id(runtime_id)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
