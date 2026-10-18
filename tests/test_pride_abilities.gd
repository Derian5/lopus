extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")
const PRIDE_ID := &"hero.control_savant"

var failures := 0
var registry: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	_test_content_and_eligibility()
	await _test_last_stand()
	_test_targeting_cleanse_teleport_and_aura()
	_test_sacrifice_combat_payload()
	_test_sacrifice_result_application()
	if failures == 0:
		print("Pride ability tests passed.")
		quit()
	else:
		push_error("Pride ability tests failed: %d" % failures)
		quit(1)


func _test_content_and_eligibility() -> void:
	var pride_ability_ids: Array[StringName] = [
		&"ability.pride_last_stand",
		&"ability.pride_farthest_attack",
		&"ability.pride_cleanse",
		&"ability.pride_sacrifice",
		&"ability.pride_melee_teleport",
		&"ability.pride_attack_speed_aura",
	]
	for ability_id in pride_ability_ids:
		var ability := registry.get_definition(ability_id, false) as AbilityDefinition
		_check(
			ability != null
			and ability.allowed_hero_ids == [PRIDE_ID]
			and ability.hero_levels.size() == AbilityDefinition.MAX_HERO_ABILITY_LEVEL,
			"%s is a four-level Pride-exclusive ability." % ability_id
		)
	for deleted_id in [
		&"ability.fire_bolt",
		&"ability.guardian_shield",
		&"ability.battle_fury",
		&"ability.hero_summon",
	]:
		_check(registry.get_definition(deleted_id, false) == null, "Deleted shared ability is not registered: %s." % deleted_id)


func _test_last_stand() -> void:
	var pride := _snapshot("pride", PRIDE_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO)
	pride.abilities = [_ability(&"ability.pride_last_stand", 1)]
	var soldier := _snapshot("soldier", &"job.militia", CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.SOLDIER)
	var summon := _snapshot("summon", &"enemy.summoned_brawler", CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.SUMMON)
	var enemy := _snapshot("enemy", &"enemy.raider", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY)
	var session := _session([pride, soldier, summon], [enemy], 9001)
	var pride_unit := _unit(session, "pride")
	var soldier_unit := _unit(session, "soldier")
	var summon_unit := _unit(session, "summon")
	var enemy_unit := _unit(session, "enemy")

	soldier_unit.take_damage(10000.0, enemy_unit)
	_check(soldier_unit.is_alive() and not soldier_unit.is_targetable(), "A Soldier fights at 0 HP during Pride's last stand.")
	var event_count := session.statistics.get_event_count(CombatEvent.DAMAGE_APPLIED)
	soldier_unit.take_damage(10000.0, enemy_unit)
	_check(session.statistics.get_event_count(CombatEvent.DAMAGE_APPLIED) == event_count, "A last-stand unit is invulnerable.")
	_check(session.find_closest_target(enemy_unit) != soldier_unit, "A last-stand unit cannot be targeted.")
	summon_unit.take_damage(10000.0, enemy_unit)
	_check(not summon_unit.is_alive(), "Summons never receive Pride's last stand.")
	pride_unit.take_damage(10000.0, enemy_unit)
	_check(pride_unit.is_alive() and not pride_unit.is_targetable(), "Pride benefits from her own last-stand aura.")
	session._check_battle_end()
	_check(session.battle_active, "Combat continues when only last-stand allies remain.")
	soldier_unit._update_runtime(3.1)
	pride_unit._update_runtime(3.1)
	await process_frame
	_check(not session.battle_active and session.last_winner == &"enemy", "Last-stand units die when their timers expire.")
	session.free()

	var finishing_pride := _snapshot("finishing-pride", PRIDE_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO)
	finishing_pride.abilities = [_ability(&"ability.pride_last_stand", 1)]
	var finishing_enemy := _snapshot("finishing-enemy", &"enemy.raider", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY)
	var finishing_session := _session([finishing_pride], [finishing_enemy], 9011)
	var finishing_pride_unit := _unit(finishing_session, "finishing-pride")
	finishing_pride_unit.take_damage(10000.0, _unit(finishing_session, "finishing-enemy"))
	finishing_session._finish_battle(&"player", false)
	_check(not bool(finishing_session.statistics.unit_stats["finishing-pride"].alive), "A battle ending early still finalizes delayed last-stand deaths.")
	finishing_session.free()


func _test_targeting_cleanse_teleport_and_aura() -> void:
	var pride := _snapshot("pride", PRIDE_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO)
	pride.stats.attack_range = 100.0
	pride.abilities = [
		_ability(&"ability.pride_farthest_attack", 1),
		_ability(&"ability.pride_melee_teleport", 1),
		_ability(&"ability.pride_attack_speed_aura", 2),
	]
	var enemy_near := _snapshot("enemy-near", &"enemy.raider", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY)
	var enemy_far := _snapshot("enemy-far", &"enemy.raider", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY)
	var session := _session([pride], [enemy_near, enemy_far], 9002)
	var pride_unit := _unit(session, "pride")
	var near_unit := _unit(session, "enemy-near")
	var far_unit := _unit(session, "enemy-far")
	pride_unit.position = Vector2(400.0, 300.0)
	near_unit.position = Vector2(450.0, 300.0)
	far_unit.position = Vector2(530.0, 300.0)
	_check(is_equal_approx(pride_unit.get_effective_stat(&"attack_range"), 150.0), "Pride receives the authored attack range bonus.")
	_check(session.find_basic_attack_target(pride_unit) == far_unit, "Pride targets the farthest enemy inside basic attack range.")
	_check(is_equal_approx(near_unit.get_effective_stat(&"attack_speed"), near_unit.snapshot.stats.attack_speed * 0.6), "The aura reduces nearby enemy attack speed by 40%.")
	far_unit.position = Vector2(700.0, 300.0)
	_check(is_equal_approx(far_unit.get_effective_stat(&"attack_speed"), far_unit.snapshot.stats.attack_speed), "The aura does not affect enemies outside its radius.")

	var slow := registry.get_definition(&"status.slow") as StatusDefinition
	var armor_buff := registry.get_definition(&"status.armor_buff") as StatusDefinition
	pride_unit.apply_status(slow, near_unit, &"ability.test_slow")
	pride_unit.apply_status(armor_buff, pride_unit, &"ability.test_positive_status")
	var cleanse := _ability(&"ability.pride_cleanse", 1)
	_check(session.resolve_ability_target(pride_unit, cleanse) == pride_unit, "Cleanse includes Pride when choosing the nearest affected ally.")
	session.deliver_ability(pride_unit, pride_unit, cleanse)
	_check(not pride_unit.has_negative_status() and pride_unit.statuses.size() == 1 and pride_unit.statuses[0].definition == armor_buff, "Cleanse removes one negative status and preserves positive statuses.")

	near_unit.position = Vector2(300.0, 300.0)
	var original_position := pride_unit.position
	pride_unit.take_damage(1.0, near_unit, &"attack.basic", &"attack.basic", true)
	_check(pride_unit.position.x > original_position.x and pride_unit.melee_teleport_cooldown_remaining > 0.0, "Melee damage teleports Pride away from the attacker.")
	var cooldown_position := pride_unit.position
	var cooldown_hit := pride_unit.take_damage(60.0, near_unit, &"attack.basic", &"attack.basic", true)
	_check(is_equal_approx(pride_unit.position.distance_to(cooldown_position), pride_unit.damage_knockback_for(cooldown_hit)) and pride_unit.melee_teleport_cooldown_remaining > 0.0, "Melee teleport stays on cooldown while the global hit reaction still applies its damage-scaled knockback.")
	session.free()


func _test_sacrifice_combat_payload() -> void:
	var pride := _snapshot("pride", PRIDE_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO)
	pride.abilities = [_ability(&"ability.pride_last_stand", 1)]
	var soldier := _snapshot("soldier", &"job.militia", CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.SOLDIER)
	soldier.stats.max_hp = 200.0
	soldier.stats.damage = 30.0
	soldier.stats.armor = 10.0
	var enemy := _snapshot("enemy", &"enemy.raider", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY)
	var session := _session([pride, soldier], [enemy], 9003)
	var pride_unit := _unit(session, "pride")
	var soldier_unit := _unit(session, "soldier")
	var original_pride_stats := pride_unit.snapshot.stats.duplicate_stats()
	pride_unit.position = Vector2(300.0, 300.0)
	soldier_unit.position = Vector2(350.0, 300.0)
	var temporary_damage := StatModifier.new()
	temporary_damage.stat = "damage"
	temporary_damage.operation = StatModifier.Operation.MULTIPLY
	temporary_damage.value = 2.0
	soldier_unit.add_temporary_modifier(temporary_damage, 10.0, pride_unit, &"test", &"test")
	session.deliver_ability(pride_unit, pride_unit, _ability(&"ability.pride_sacrifice", 2))
	_check(not soldier_unit.is_alive() and soldier_unit.last_stand_remaining == 0.0, "Sacrifice kills its Soldier immediately and bypasses last stand.")
	_check(int(session.statistics.unit_stats["pride"].kills) == 0, "A friendly sacrifice is not counted as a combat kill.")
	_check(session.statistics.permanent_stat_gains.size() == 1, "Sacrifice emits one permanent stat-gain payload.")
	var stats: Dictionary = session.statistics.permanent_stat_gains[0].stats
	_check(
		is_equal_approx(float(stats.max_hp), 40.0)
		and is_equal_approx(float(stats.damage), 6.0)
		and is_equal_approx(float(stats.armor), 2.0),
		"Sacrifice uses snapshot stats, including persistent build values but excluding temporary combat buffs."
	)
	_check(
		is_equal_approx(pride_unit.snapshot.stats.max_hp, original_pride_stats.max_hp + 40.0)
		and is_equal_approx(pride_unit.snapshot.stats.damage, original_pride_stats.damage + 6.0)
		and is_equal_approx(pride_unit.snapshot.stats.armor, original_pride_stats.armor + 2.0),
		"Sacrifice grants the same stat payload immediately in the current battle."
	)
	session.free()


func _test_sacrifice_result_application() -> void:
	var run := DemoRunFactory.create_starting_run(9004)
	run.run_phase = &"combat"
	var pride: HeroState
	for hero in run.heroes:
		if hero.definition_id == PRIDE_ID:
			pride = hero
			break
	var result := CombatResult.new()
	result.result_id = "result-pride-sacrifice"
	result.winner = &"player"
	result.encounter_id = run.selected_encounter_id
	result.permanent_stat_gains = [{
		"target_runtime_id": pride.unique_id,
		"source_runtime_id": "soldier-00",
		"ability_id": "ability.pride_sacrifice",
		"stats": {"max_hp": 40.0, "damage": 6.0, "armor": 2.0},
	}]
	_check(CombatResultApplicator.apply(result, run, registry), "A sacrifice result applies to the run.")
	_check(pride.stat_modifiers.size() == 3 and pride.stat_modifiers.all(func(modifier: RuntimeStatModifier) -> bool: return modifier.battles_remaining < 0), "Sacrifice creates permanent additive Hero modifiers.")
	var snapshot := CombatSnapshotBuilder.build_hero(pride, run.inventory, registry)
	var definition := registry.get_definition(PRIDE_ID) as HeroDefinition
	_check(snapshot.stats.max_hp >= definition.base_stats.max_hp + 40.0 and snapshot.stats.damage >= definition.base_stats.damage + 6.0, "Future combat snapshots include sacrifice gains.")
	_check(not CombatResultApplicator.apply(result, run, registry) and pride.stat_modifiers.size() == 3, "Sacrifice gains are idempotent with the CombatResult.")


func _ability(ability_id: StringName, level: int) -> AbilityDefinition:
	return (registry.get_definition(ability_id) as AbilityDefinition).for_hero_level(level)


func _snapshot(runtime_id: String, definition_id: StringName, team: int, kind: int) -> CombatUnitSnapshot:
	var snapshot := CombatUnitSnapshot.new()
	snapshot.runtime_id = runtime_id
	snapshot.definition_id = definition_id
	snapshot.display_name = runtime_id
	snapshot.team = team
	snapshot.unit_kind = kind
	snapshot.stats.max_hp = 100.0
	snapshot.stats.damage = 10.0
	snapshot.stats.attack_speed = 1.0
	snapshot.stats.movement_speed = 100.0
	snapshot.stats.attack_range = 50.0
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
