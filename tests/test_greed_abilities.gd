extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")
const GREED_ID := &"hero.test_vanguard"
const ABILITY_IDS: Array[StringName] = [
	&"ability.greed_golden_reserve",
	&"ability.greed_gilded_armory",
	&"ability.greed_shadowstep",
	&"ability.greed_bounty_hunter",
	&"ability.greed_dagger_nova",
	&"ability.greed_smoke_bomb",
]

var failures := 0
var registry: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	_test_content_and_exclusivity()
	_test_gold_and_item_scaling()
	_test_shadowstep_daggers_and_smoke()
	_test_kill_rewards_and_result_application()
	if failures == 0:
		print("Greed ability tests passed.")
		quit()
	else:
		push_error("Greed ability tests failed: %d" % failures)
		quit(1)


func _test_content_and_exclusivity() -> void:
	for ability_id in ABILITY_IDS:
		var ability := registry.get_definition(ability_id, false) as AbilityDefinition
		_check(ability != null and ability.allowed_hero_ids == [GREED_ID] and ability.hero_levels.size() == 4, "%s is a four-level Greed-exclusive ability." % ability_id)
	for deleted_id in [
		&"ability.battle_fury", &"ability.hero_summon", &"ability.fire_bolt", &"ability.stunning_blow",
		&"ability.mending_light", &"ability.fortify", &"ability.guardian_shield",
	]:
		_check(registry.get_definition(deleted_id, false) == null, "Shared ability was fully removed: %s" % deleted_id)
	var golden := _ability(&"ability.greed_golden_reserve", 4).effects[0] as GoldArmyScalingEffect
	var armory := _ability(&"ability.greed_gilded_armory", 4).effects[0] as ItemStatScalingEffect
	var shadow := _ability(&"ability.greed_shadowstep", 4).effects[0] as TeleportStealthEffect
	var bounty := _ability(&"ability.greed_bounty_hunter", 4).effects[0] as KillRewardEffect
	var daggers := _ability(&"ability.greed_dagger_nova", 4)
	var smoke := _ability(&"ability.greed_smoke_bomb", 4).effects[0] as SmokeBombEffect
	_check(golden.percent_per_gold == 0.8 and armory.bonus_percent == 128.0 and shadow.duration == 24.0, "Greed economy and stealth abilities reach their authored Level 4 values.")
	_check(bounty.gold_per_kill == 80 and bounty.permanent_damage_per_kill == 8.0, "Bounty Hunter reaches its authored Level 4 rewards.")
	_check(daggers.cooldown_seconds == 5.0 and (daggers.effects[0] as RadialEnemyDamageEffect).damage == 280.0, "Dagger Nova reaches 280 damage and a five-second cooldown.")
	_check(smoke.activation_enemy_radius == 100.0 and smoke.radius == 200.0 and smoke.duration == 6.0 and smoke.dodge_percent == 80.0, "Smoke Bomb activates near enemies and reaches 80% dodge in its authored zone.")


func _test_gold_and_item_scaling() -> void:
	var baseline := DemoRunFactory.create_starting_run(9401)
	baseline.gold = 100
	var scaled := RunState.from_dictionary(baseline.to_dictionary())
	var greed := scaled.heroes[0]
	_add_hero_ability(greed, &"ability.greed_golden_reserve", 1)
	var baseline_army := CombatSnapshotBuilder.build_player_army(baseline, registry)
	var scaled_army := CombatSnapshotBuilder.build_player_army(scaled, registry)
	_check(is_equal_approx(scaled_army[0].stats.max_hp, baseline_army[0].stats.max_hp * 1.1) and is_equal_approx(scaled_army[3].stats.damage, baseline_army[3].stats.damage * 1.1), "100 Gold at Level 1 increases Hero and Soldier combat stats by 10%.")
	_check(is_equal_approx(scaled_army[0].stats.movement_speed, baseline_army[0].stats.movement_speed) and is_equal_approx(scaled_army[3].stats.movement_speed, baseline_army[3].stats.movement_speed), "Golden Reserve never changes movement speed.")

	var item_run := DemoRunFactory.create_starting_run(9402)
	item_run.inventory.create_item(&"item.hero.vanguard_blade")
	var item_hero := item_run.heroes[0]
	_add_hero_ability(item_hero, &"ability.greed_gilded_armory", 1)
	item_hero.item_ids.append(StringName(item_run.inventory.items[0].instance_id))
	var item_snapshot := CombatSnapshotBuilder.build_hero(item_hero, item_run.inventory, registry)
	var greed_definition := registry.get_definition(GREED_ID) as HeroDefinition
	_check(is_equal_approx(item_snapshot.stats.damage, greed_definition.base_stats.damage + 6.0 * 1.16), "Gilded Armory increases only Greed's equipped item modifier at Level 1.")


func _test_shadowstep_daggers_and_smoke() -> void:
	var greed := _unit_snapshot("greed", CombatUnitSnapshot.Team.PLAYER, 500.0)
	var ally := _unit_snapshot("ally", CombatUnitSnapshot.Team.PLAYER, 500.0)
	var near_enemy := _unit_snapshot("near", CombatUnitSnapshot.Team.ENEMY, 500.0)
	var far_enemy := _unit_snapshot("far", CombatUnitSnapshot.Team.ENEMY, 500.0)
	var players: Array[CombatUnitSnapshot] = [greed, ally]
	var enemies: Array[CombatUnitSnapshot] = [near_enemy, far_enemy]
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200.0, 600.0)
	root.add_child(session)
	session.setup(players, enemies, 9403)
	for combatant in session.combatants:
		combatant.set_simulation_active(false)
	var greed_unit := session.get_combatant_by_runtime_id("greed")
	var ally_unit := session.get_combatant_by_runtime_id("ally")
	var near_unit := session.get_combatant_by_runtime_id("near")
	var far_unit := session.get_combatant_by_runtime_id("far")
	greed_unit.position = Vector2(100.0, 100.0)
	ally_unit.position = Vector2(200.0, 100.0)
	near_unit.position = Vector2(400.0, 100.0)
	far_unit.position = Vector2(900.0, 100.0)
	var shadow := _ability(&"ability.greed_shadowstep", 4)
	session._apply_ability_effects(greed_unit, greed_unit, shadow)
	_check(greed_unit.position.distance_to(far_unit.position) < 100.0 and greed_unit.stealth_remaining == 24.0, "Shadowstep teleports to the farthest enemy and applies Level 4 stealth.")
	_check(session.find_closest_target(far_unit) == ally_unit, "Enemies cannot select a stealthed Greed as a target.")
	var hp_before := greed_unit.current_hp
	greed_unit.take_damage(10.0, far_unit)
	_check(greed_unit.current_hp == hp_before - 10.0, "Stealth does not grant immunity to untargeted area damage.")

	greed_unit.position = Vector2(100.0, 100.0)
	near_unit.position = Vector2(200.0, 100.0)
	far_unit.position = Vector2(500.0, 100.0)
	var dagger := _ability(&"ability.greed_dagger_nova", 4)
	session._apply_ability_effects(greed_unit, greed_unit, dagger)
	_check(near_unit.current_hp == 220.0 and far_unit.current_hp == 500.0, "Dagger Nova damages every enemy inside 200 range and no enemy outside it.")

	var smoke_effect := (_ability(&"ability.greed_smoke_bomb", 1).effects[0] as SmokeBombEffect).duplicate() as SmokeBombEffect
	smoke_effect.dodge_percent = 100.0
	var smoke_ability := _ability(&"ability.greed_smoke_bomb", 1)
	near_unit.position = Vector2(201.0, 100.0)
	_check(not session.can_use_ability(greed_unit, greed_unit, smoke_ability), "Smoke Bomb waits while every enemy is farther than 100.")
	near_unit.position = Vector2(200.0, 100.0)
	_check(session.can_use_ability(greed_unit, greed_unit, smoke_ability), "Smoke Bomb becomes usable when an enemy enters 100 range.")
	smoke_effect.apply(greed_unit, greed_unit, _ability(&"ability.greed_smoke_bomb", 1))
	ally_unit.position = greed_unit.position
	hp_before = ally_unit.current_hp
	ally_unit.take_damage(20.0, near_unit)
	_check(ally_unit.current_hp == hp_before, "An ally inside smoke dodges incoming damage according to the zone chance.")
	ally_unit.position = Vector2(500.0, 500.0)
	ally_unit.take_damage(20.0, near_unit)
	_check(ally_unit.current_hp == hp_before - 20.0, "Smoke dodge stops applying after an ally leaves the zone.")
	session.free()


func _test_kill_rewards_and_result_application() -> void:
	var run := DemoRunFactory.create_starting_run(9404)
	var greed := run.heroes[0]
	_add_hero_ability(greed, &"ability.greed_bounty_hunter", 2)
	var greed_snapshot := CombatSnapshotBuilder.build_hero(greed, run.inventory, registry)
	var enemy_snapshot := _unit_snapshot("bounty-target", CombatUnitSnapshot.Team.ENEMY, 10.0)
	var players: Array[CombatUnitSnapshot] = [greed_snapshot]
	var enemies: Array[CombatUnitSnapshot] = [enemy_snapshot]
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200.0, 600.0)
	root.add_child(session)
	session.setup(players, enemies, 9404)
	for combatant in session.combatants:
		combatant.set_simulation_active(false)
	var greed_unit := session.get_combatant_by_runtime_id(greed.unique_id)
	var enemy_unit := session.get_combatant_by_runtime_id("bounty-target")
	var damage_before := greed_unit.snapshot.stats.damage
	enemy_unit.take_damage(20.0, greed_unit)
	_check(session.statistics.bonus_gold == 20 and greed_unit.snapshot.stats.damage == damage_before + 2.0 and session.statistics.permanent_stat_gains.size() == 1, "A personal Level 2 kill immediately records 20 Gold and 2 permanent damage.")
	session.record_event(CombatEvent.BATTLE_FINISHED, "player", "", &"", &"", 1.0)
	var encounter := registry.get_definition(&"encounter.tutorial_volley") as EncounterDefinition
	var progression := registry.get_definition(&"progression.demo") as ProgressionDefinition
	var result := CombatResult.from_statistics("greed-bounty-result", session.statistics, encounter, false, progression)
	run.run_phase = &"combat"
	var old_gold := run.gold
	_check(CombatResultApplicator.apply(result, run, registry), "A combat result with Greed kill rewards applies successfully.")
	_check(run.gold == old_gold + encounter.gold_reward + 20 and run.heroes[0].stat_modifiers[-1].value == 2.0, "Post-battle application grants bounty Gold and permanent damage exactly once.")
	_check(not CombatResultApplicator.apply(result, run, registry), "Greed kill rewards remain idempotent with the combat result.")
	session.free()


func _ability(ability_id: StringName, level: int) -> AbilityDefinition:
	return (registry.get_definition(ability_id) as AbilityDefinition).for_hero_level(level)


func _add_hero_ability(hero: HeroState, ability_id: StringName, level: int) -> void:
	hero.unlock_ability(ability_id)
	hero.equip_ability(ability_id)
	hero.ability_levels[String(ability_id)] = level


func _unit_snapshot(runtime_id: String, team: int, hp: float) -> CombatUnitSnapshot:
	var snapshot := CombatUnitSnapshot.new()
	snapshot.runtime_id = runtime_id
	snapshot.definition_id = &"test.unit"
	snapshot.display_name = runtime_id
	snapshot.team = team
	snapshot.unit_kind = CombatUnitSnapshot.UnitKind.HERO if team == CombatUnitSnapshot.Team.PLAYER else CombatUnitSnapshot.UnitKind.ENEMY
	snapshot.stats.max_hp = hp
	snapshot.stats.damage = 10.0
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
