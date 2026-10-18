extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")
const SELECTED_PANEL_SCENE := preload("res://ui/combat/selected_unit_panel.tscn")
const DESPAIR_ID := &"hero.iron_oracle"
const ABILITY_IDS: Array[StringName] = [
	&"ability.despair_crushing_gloom",
	&"ability.despair_withering_touch",
	&"ability.despair_deep_slumber",
	&"ability.despair_still_sanctuary",
	&"ability.despair_grasping_vines",
	&"ability.despair_endless_descent",
	&"ability.despair_burdened_guard",
]

var failures := 0
var registry: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	_test_content_levels_and_rewards()
	_test_global_basic_proc()
	_test_withering_stacks()
	_test_sleep_wake_rules()
	_test_sanctuary()
	_test_vines()
	_test_growth_and_ui()
	_test_burdened_guard()
	if failures == 0:
		print("Despair ability tests passed.")
		quit()
	else:
		push_error("Despair ability tests failed: %d" % failures)
		quit(1)


func _test_content_levels_and_rewards() -> void:
	var despair := registry.get_definition(DESPAIR_ID) as HeroDefinition
	_check(despair != null and despair.tags.has(&"ranged"), "Despair is hero.iron_oracle and is ranged.")
	_check(registry.validation_errors.is_empty(), "Despair effects and status fields pass ContentRegistry validation.")
	for ability_id in ABILITY_IDS:
		var ability := registry.get_definition(ability_id, false) as AbilityDefinition
		_check(ability != null and ability.allowed_hero_ids == [DESPAIR_ID] and ability.hero_levels.size() == 4, "%s is a four-level Despair-exclusive ability." % ability_id)
	var proc_values := [150.0, 300.0, 600.0, 1200.0]
	var stack_values := [2, 4, 6, 8]
	var sleep_values := [2.5, 5.0, 10.0, 20.0]
	var sanctuary_heal := [6.0, 7.0, 8.0, 9.0]
	var sanctuary_duration := [4.0, 5.0, 6.0, 7.0]
	var vine_counts := [2, 3, 4, 5]
	var growth_values := [2.0, 3.0, 4.0, 5.0]
	var shield_values := [200.0, 300.0, 400.0, 500.0]
	var shield_cooldowns := [7.0, 6.0, 5.0, 4.0]
	for index in 4:
		var proc := _ability(ABILITY_IDS[0], index + 1).effects[0] as DespairTeamProcEffect
		var slow := _ability(ABILITY_IDS[1], index + 1).effects[0] as DespairAttackSlowEffect
		var sleep := _ability(ABILITY_IDS[2], index + 1)
		var sanctuary := _ability(ABILITY_IDS[3], index + 1)
		var vines := _ability(ABILITY_IDS[4], index + 1)
		var growth := _ability(ABILITY_IDS[5], index + 1).effects[0] as DespairGrowthEffect
		var guard := _ability(ABILITY_IDS[6], index + 1)
		_check(proc.proc_chance_percent == 15.0 and proc.total_damage_percent == proc_values[index], "Crushing Gloom Level %d values are exact." % (index + 1))
		_check(slow.max_stacks == stack_values[index] and slow.attack_speed_reduction_per_stack == 10.0 and slow.maximum_reduction_percent == 80.0, "Withering Touch Level %d values are exact." % (index + 1))
		_check(sleep.cooldown_seconds == 8.0 and (sleep.effects[0] as DespairSleepEffect).duration == sleep_values[index], "Deep Slumber Level %d values are exact." % (index + 1))
		var sanctuary_effect := sanctuary.effects[0] as DespairSanctuaryEffect
		_check(sanctuary.cooldown_seconds == 6.0 and sanctuary_effect.health_threshold == 0.3 and sanctuary_effect.max_hp_heal_percent == sanctuary_heal[index] and sanctuary_effect.duration == sanctuary_duration[index], "Still Sanctuary Level %d values are exact." % (index + 1))
		var vines_effect := vines.effects[0] as DespairVinesEffect
		_check(vines.cooldown_seconds == 10.0 and vines_effect.target_count == vine_counts[index] and vines_effect.damage == 50.0 and vines_effect.duration == 5.0 and vines_effect.interval == 1.0, "Grasping Vines Level %d values are exact." % (index + 1))
		_check(growth.max_hp_percent_per_second == growth_values[index] and growth.attack_speed_percent_per_second == growth_values[index] * 0.5 and growth.maximum_bonus_percent == 200.0, "Endless Descent Level %d values are exact." % (index + 1))
		var guard_effect := guard.effects[0] as DespairPressureShieldEffect
		_check(guard.cooldown_seconds == shield_cooldowns[index] and guard_effect.shield_amount == shield_values[index] and is_equal_approx(guard_effect.attack_speed_multiplier, 1.0 / 3.0) and guard_effect.duration == 5.0, "Burdened Guard Level %d values are exact." % (index + 1))
	var run := DemoRunFactory.create_starting_run(9900)
	var hero := HeroState.new()
	hero.unique_id = "despair-reward"
	hero.definition_id = DESPAIR_ID
	run.heroes = [hero]
	var route := registry.get_definition(RunState.ROUTE_DEFINITION_ID) as RouteDefinition
	var candidates := HeroAbilityRewardService._candidates(hero, registry, route)
	var candidate_ids := candidates.map(func(entry: Dictionary) -> StringName: return StringName(entry.ability_id))
	_check(ABILITY_IDS.all(func(ability_id: StringName) -> bool: return candidate_ids.has(ability_id)), "Hero rewards offer all seven Despair abilities.")
	var tooltip := ContentButton.describe_content(ABILITY_IDS[5])
	var descent := registry.get_definition(ABILITY_IDS[5]) as AbilityDefinition
	_check(tooltip.contains("2.5") and AbilityText.plain(descent, 2).contains("+1.5% attack speed") and AbilityText.plain(descent, 4).contains("+5% Max HP"), "Static tooltips and reward cards expose authored Despair level values.")


func _test_global_basic_proc() -> void:
	var despair := _snapshot("despair", DESPAIR_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO, 1000.0, 20.0)
	despair.attack_type = &"ranged"
	despair.abilities = [_ability(ABILITY_IDS[0], 1)]
	var melee := _snapshot("melee", &"test.melee", CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.SOLDIER, 1000.0, 40.0)
	var ranged := _snapshot("ranged", &"test.ranged", CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.SOLDIER, 1000.0, 40.0)
	ranged.attack_type = &"ranged"
	var enemy := _snapshot("enemy", &"test.enemy", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 100000.0, 1.0)
	var session := _session([despair, melee, ranged], [enemy], 9901)
	var aura := _unit(session, "despair")
	aura.despair_team_proc_chance_percent = 100.0
	var target := _unit(session, "enemy")
	target.position = Vector2(300, 300)
	_unit(session, "melee").position = Vector2(280, 300)
	_unit(session, "ranged").position = Vector2(200, 300)
	_basic_attack_once(_unit(session, "melee"), target)
	_basic_attack_once(_unit(session, "ranged"), target)
	_check(target.current_hp == 99880.0, "The global proc multiplies melee and ranged basic damage at actual impact.")
	var events := session.events.filter(func(event: CombatEvent) -> bool: return event.event_type == CombatEvent.DAMAGE_APPLIED and event.ability_id == &"attack.basic")
	_check(events.size() == 2 and events[0].value == 60.0 and events[1].value == 60.0, "Proc damage remains one basic-attack damage event per hit.")
	var stronger := _snapshot("stronger", DESPAIR_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO, 1000.0, 10.0)
	stronger.abilities = [_ability(ABILITY_IDS[0], 4)]
	var strongest_session := _session([despair, stronger, melee], [enemy], 9902)
	_unit(strongest_session, "despair").despair_team_proc_chance_percent = 100.0
	_unit(strongest_session, "stronger").despair_team_proc_chance_percent = 100.0
	var strongest_target := _unit(strongest_session, "enemy")
	strongest_target.position = Vector2(300, 300)
	_unit(strongest_session, "melee").position = Vector2(280, 300)
	_basic_attack_once(_unit(strongest_session, "melee"), strongest_target)
	_check(strongest_target.current_hp == 99520.0, "Multiple Despairs make one roll and use only the strongest total-damage multiplier.")
	var first := _proc_sequence(session, 9903)
	var second := _proc_sequence(session, 9903)
	_check(first == second and first.any(func(value: float) -> bool: return value > 40.0), "The authored 15% proc produces a deterministic seeded sequence.")
	session.free()
	strongest_session.free()


func _proc_sequence(session: CombatSession, seed: int) -> Array[float]:
	var source := _unit(session, "melee")
	var target := _unit(session, "enemy")
	_unit(session, "despair").despair_team_proc_chance_percent = 15.0
	session.combat_rng.seed = seed
	var result: Array[float] = []
	for _index in 20:
		var before := target.current_hp
		target.take_damage(40.0, source)
		result.append(before - target.current_hp)
	return result


func _test_withering_stacks() -> void:
	var despair := _snapshot("despair", DESPAIR_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO, 1000.0, 10.0)
	despair.attack_type = &"ranged"
	despair.abilities = [_ability(ABILITY_IDS[1], 4)]
	var enemy := _snapshot("enemy", &"test.enemy", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 1000.0, 1.0)
	enemy.stats.attack_speed = 2.0
	var session := _session([despair], [enemy], 9904)
	var source := _unit(session, "despair")
	var target := _unit(session, "enemy")
	source.position = Vector2(280, 300)
	target.position = Vector2(300, 300)
	target.add_shield(20.0, 10.0, target, &"ability.test", &"effect.test")
	_basic_attack_once(source, target)
	_check(target.despair_slow_stacks == 0, "A shield-only basic hit does not add a Withering Touch stack.")
	for _index in 10:
		_basic_attack_once(source, target)
	_check(target.despair_slow_stacks == 8 and is_equal_approx(target.get_effective_stat(&"attack_speed"), 0.4), "Withering Touch caps at eight stacks and applies an exact linear 80% reduction.")
	var panel: SelectedUnitPanel = SELECTED_PANEL_SCENE.instantiate()
	root.add_child(panel)
	panel.show_combatant(target)
	_check(panel.status_summary_text().contains("8/8 stacks") and panel.status_summary_text().contains("-80%"), "Withering stacks and exact reduction appear in status indicator tooltips.")
	panel.free()
	session.free()


func _test_sleep_wake_rules() -> void:
	var despair := _snapshot("despair", DESPAIR_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO, 1000.0, 10.0)
	var enemy := _snapshot("enemy", &"test.enemy", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 1000.0, 10.0)
	var session := _session([despair], [enemy], 9905)
	var source := _unit(session, "despair")
	var target := _unit(session, "enemy")
	var sleep := _ability(ABILITY_IDS[2], 2)
	(sleep.effects[0] as DespairSleepEffect).apply(source, target, sleep)
	_check(target.is_stunned() and is_equal_approx(target.statuses[0].remaining_duration, 5.0), "Sleep is a full action stun with the authored duration.")
	target.add_shield(100.0, 10.0, target, &"ability.test", &"effect.test")
	target.take_damage(50.0, source, &"ability.test", &"effect.test")
	_check(target.is_stunned(), "Shield-only damage does not wake sleep.")
	target.take_damage(60.0, source, &"ability.test", &"effect.test")
	_check(not target.is_stunned() and target.current_hp == 990.0, "The first HP-damaging hit deals damage and then wakes sleep.")
	(sleep.effects[0] as DespairSleepEffect).apply(source, target, sleep)
	target.apply_gluttony_grease(100.0, 4.0, source, &"ability.test")
	target.take_damage(50.0, source)
	_check(target.has_status(&"effect.despair_deep_slumber"), "A dodged basic attack does not wake sleep.")
	session.free()


func _test_sanctuary() -> void:
	var despair := _snapshot("despair", DESPAIR_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO, 1000.0, 10.0)
	despair.abilities = [_ability(ABILITY_IDS[3], 1)]
	var low := _snapshot("low", &"test.low", CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.SOLDIER, 1000.0, 10.0)
	var lower := _snapshot("lower", &"test.lower", CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.SOLDIER, 500.0, 10.0)
	var enemy := _snapshot("enemy", &"test.enemy", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 1000.0, 10.0)
	var session := _session([despair, low, lower], [enemy], 9906)
	var source := _unit(session, "despair")
	var low_unit := _unit(session, "low")
	var lower_unit := _unit(session, "lower")
	var attacker := _unit(session, "enemy")
	low_unit.current_hp = 250.0
	lower_unit.current_hp = 100.0
	var sanctuary := _ability(ABILITY_IDS[3], 1)
	_check(session.apply_despair_sanctuary(source, 0.3, 6.0, 4.0, 1.0, sanctuary.id, &"effect.despair_still_sanctuary") == lower_unit, "Sanctuary chooses the lowest-percent other ally below 30% HP.")
	_check(lower_unit.is_stunned() and not lower_unit.can_be_targeted_by(attacker), "Sanctuary fully action-locks its target and blocks hostile selection.")
	var hp_before := lower_unit.current_hp
	lower_unit.take_damage(100.0, attacker)
	var hostile_status := registry.get_definition(&"status.stun") as StatusDefinition
	var hostile_apply := ApplyStatusEffect.new()
	hostile_apply.status = hostile_status
	var hostile_ability := AbilityDefinition.new()
	hostile_ability.id = &"ability.hostile_test"
	hostile_ability.effects = [hostile_apply]
	session._apply_ability_effects(attacker, lower_unit, hostile_ability)
	_check(lower_unit.current_hp == hp_before and lower_unit.statuses.is_empty(), "Sanctuary blocks hostile direct damage and enemy ability effects.")
	lower_unit.receive_healing(10.0, low_unit, &"ability.ally", &"effect.ally")
	lower_unit._update_runtime(4.0)
	_check(lower_unit.current_hp == hp_before + 10.0 + 120.0 and lower_unit.despair_sanctuary_remaining == 0.0, "Allied healing remains valid and sanctuary heals each second through its full duration.")
	var solo_session := _session([despair], [enemy], 9907)
	var solo := _unit(solo_session, "despair")
	_check(not solo._try_activate_ability(_ability(ABILITY_IDS[3], 1), false) and solo.ability_cooldowns.is_empty(), "Sanctuary neither casts nor consumes cooldown without a valid other ally.")
	session.free()
	solo_session.free()


func _test_vines() -> void:
	var despair := _snapshot("despair", DESPAIR_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO, 1000.0, 10.0)
	var enemies: Array[CombatUnitSnapshot] = []
	for index in 5:
		var enemy := _snapshot("enemy-%d" % index, &"test.enemy", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 1000.0, 10.0)
		enemy.stats.armor = 100.0
		enemy.is_boss = index == 0
		enemies.append(enemy)
	var first_session := _session([despair], enemies, 9908)
	var second_session := _session([despair], enemies, 9908)
	var vines := _ability(ABILITY_IDS[4], 3).effects[0] as DespairVinesEffect
	var first := first_session.apply_despair_vines(_unit(first_session, "despair"), vines.target_count, vines.damage, vines.duration, vines.interval, ABILITY_IDS[4], vines.effect_id)
	var second := second_session.apply_despair_vines(_unit(second_session, "despair"), vines.target_count, vines.damage, vines.duration, vines.interval, ABILITY_IDS[4], vines.effect_id)
	var first_ids := first.map(func(unit: Combatant) -> String: return unit.snapshot.runtime_id)
	var second_ids := second.map(func(unit: Combatant) -> String: return unit.snapshot.runtime_id)
	_check(first.size() == 4 and first_ids == second_ids and first_ids.duplicate().all(func(id: String) -> bool: return first_ids.count(id) == 1), "Vines selects four distinct enemies deterministically through combat RNG.")
	var target: Combatant = first[0]
	_check(target.is_rooted() and not target.is_stunned(), "Vines roots movement without blocking attacks or casts, including for bosses when selected.")
	target._update_runtime(5.0)
	_check(target.current_hp == 875.0 and not target.is_rooted(), "Vines deals five normal armored 50-damage ticks and expires after five seconds.")
	var empty_session := _session([despair], [], 9909)
	var caster := _unit(empty_session, "despair")
	_check(not caster._try_activate_ability(_ability(ABILITY_IDS[4], 1), false) and caster.ability_cooldowns.is_empty(), "Vines does not activate or consume cooldown without an enemy.")
	first_session.free()
	second_session.free()
	empty_session.free()


func _test_growth_and_ui() -> void:
	var despair := _snapshot("despair", DESPAIR_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO, 100.0, 100.0)
	despair.stats.armor = 100.0
	despair.stats.movement_speed = 100.0
	despair.stats.attack_speed = 1.0
	despair.abilities = [_ability(ABILITY_IDS[5], 1)]
	var enemy := _snapshot("enemy", &"test.enemy", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 100000.0, 1.0)
	var session := _session([despair], [enemy], 9910)
	var unit := _unit(session, "despair")
	unit.current_hp = 50.0
	unit._update_runtime(0.99)
	_check(unit.get_effective_stat(&"max_hp") == 100.0, "Growth waits for its first complete second.")
	unit._update_runtime(0.01)
	_check(unit.get_effective_stat(&"max_hp") == 102.0 and unit.get_effective_stat(&"damage") == 102.0 and unit.get_effective_stat(&"attack_speed") == 1.01 and unit.current_hp == 51.0, "First growth tick uses non-compounding baseline percentages and preserves HP ratio.")
	unit.apply_despair_sanctuary(unit, 0.0, 5.0, 1.0, &"ability.test", &"effect.test")
	unit._update_runtime(9.0)
	_check(is_equal_approx(unit.get_effective_stat(&"damage"), 120.0), "A large delta processes every growth tick while action locked.")
	unit._update_runtime(200.0)
	_check(unit.get_effective_stat(&"max_hp") == 300.0 and unit.get_effective_stat(&"damage") == 300.0 and unit.get_effective_stat(&"armor") == 300.0 and unit.get_effective_stat(&"movement_speed") == 300.0 and unit.get_effective_stat(&"attack_speed") == 3.0, "Each growth stat independently caps at +200%.")
	var panel: SelectedUnitPanel = SELECTED_PANEL_SCENE.instantiate()
	root.add_child(panel)
	panel.show_combatant(unit)
	var status_text: String = panel.status_summary_text()
	_check(status_text.contains("Endless Descent") and status_text.contains("+200.0%") and status_text.contains("Attack Speed +200.0%"), "Current growth appears in STATUS UI.")
	panel.free()
	session.free()


func _test_burdened_guard() -> void:
	var despair := _snapshot("despair", DESPAIR_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO, 1000.0, 10.0)
	despair.abilities = [_ability(ABILITY_IDS[6], 3)]
	var ally_a := _snapshot("ally-a", &"test.ally", CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.SOLDIER, 1000.0, 10.0)
	var ally_b := _snapshot("ally-b", &"test.ally", CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.SOLDIER, 1000.0, 10.0)
	ally_b.stats.attack_speed = 3.0
	var enemy_a := _snapshot("enemy-a", &"test.enemy", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 1000.0, 10.0)
	var enemy_b := _snapshot("enemy-b", &"test.enemy", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 1000.0, 10.0)
	var enemy_c := _snapshot("enemy-c", &"test.enemy", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 1000.0, 10.0)
	var session := _session([despair, ally_a, ally_b], [enemy_a, enemy_b, enemy_c], 9911)
	var source := _unit(session, "despair")
	var first_ally := _unit(session, "ally-a")
	var protected := _unit(session, "ally-b")
	_unit(session, "enemy-a").target = first_ally
	_unit(session, "enemy-b").target = protected
	_unit(session, "enemy-c").target = protected
	var guard := _ability(ABILITY_IDS[6], 3)
	var effect := guard.effects[0] as DespairPressureShieldEffect
	_check(session.apply_despair_pressure_shield(source, effect.shield_amount, effect.attack_speed_multiplier, effect.duration, guard.id, effect.effect_id) == protected, "Burdened Guard chooses the ally targeted by the most enemies.")
	_check(protected.shields.size() == 1 and protected.shields[0].amount == 400.0 and is_equal_approx(protected.get_effective_stat(&"attack_speed"), 1.0), "Burdened Guard grants the authored barrier and reduces attack speed to one third.")
	protected.take_damage(100.0, _unit(session, "enemy-b"))
	session.apply_despair_pressure_shield(source, effect.shield_amount, effect.attack_speed_multiplier, effect.duration, guard.id, effect.effect_id)
	_check(protected.shields.size() == 1 and protected.shields[0].amount == 400.0 and protected.temporary_modifiers.size() == 1 and is_equal_approx(protected.get_effective_stat(&"attack_speed"), 1.0), "Reapplication refreshes the barrier and slow without stacking either effect.")
	protected._update_runtime(5.0)
	_check(protected.shields.is_empty() and protected.temporary_modifiers.is_empty() and protected.get_effective_stat(&"attack_speed") == 3.0, "Barrier and attack-speed penalty expire together after five seconds.")
	var empty_session := _session([despair, ally_a], [enemy_a], 9912)
	var empty_source := _unit(empty_session, "despair")
	_check(not empty_source._try_activate_ability(_ability(ABILITY_IDS[6], 1), false) and empty_source.ability_cooldowns.is_empty(), "Burdened Guard does not activate or consume cooldown when no ally is being attacked.")
	session.free()
	empty_session.free()


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


func _basic_attack_once(source: Combatant, target: Combatant) -> void:
	source.target = target
	source.pending_ability = null
	source._start_attack()
	source._update_attack_windup(1.0)
	if source.snapshot.attack_type == &"ranged":
		var projectile := source.session.get_node("Projectiles").get_child(-1) as CombatProjectile
		projectile._physics_process(1.0)


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
	snapshot.stats.attack_range = 50.0
	snapshot.stats.armor = 0.0
	return snapshot


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
