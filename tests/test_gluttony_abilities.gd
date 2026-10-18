extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")
const SELECTED_PANEL_SCENE := preload("res://ui/combat/selected_unit_panel.tscn")
const GLUTTONY_ID := &"hero.thorn_warden"
const ABILITY_IDS: Array[StringName] = [
	&"ability.gluttony_lifesteal_aura",
	&"ability.gluttony_regeneration",
	&"ability.gluttony_damage_aura",
	&"ability.gluttony_siphon",
	&"ability.gluttony_death_explosion",
	&"ability.gluttony_grease",
]

var failures := 0
var registry: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	_test_content_levels_and_rewards()
	_test_lifesteal_aura()
	_test_regeneration_stacks()
	_test_damage_aura_and_siphon()
	_test_death_explosion()
	_test_grease()
	if failures == 0:
		print("Gluttony ability tests passed.")
		quit()
	else:
		push_error("Gluttony ability tests failed: %d" % failures)
		quit(1)


func _test_content_levels_and_rewards() -> void:
	var gluttony_definition := registry.get_definition(GLUTTONY_ID) as HeroDefinition
	_check(gluttony_definition != null and gluttony_definition.tags.has(&"melee"), "Gluttony is hero.thorn_warden and has the melee tag.")
	for ability_id in ABILITY_IDS:
		var ability := registry.get_definition(ability_id, false) as AbilityDefinition
		_check(ability != null and ability.allowed_hero_ids == [GLUTTONY_ID] and ability.hero_levels.size() == 4, "%s is a four-level Gluttony-exclusive ability." % ability_id)
	var expected := [8.0, 16.0, 32.0, 64.0]
	var expected_stacks := [10, 20, 40, 80]
	var expected_aura_damage := [10.0, 20.0, 40.0, 80.0]
	var expected_siphon := [100.0, 200.0, 400.0, 800.0]
	var expected_death_damage := [200.0, 300.0, 400.0, 500.0]
	var expected_death_radius := [250.0, 350.0, 450.0, 550.0]
	var expected_miss := [15.0, 30.0, 45.0, 60.0]
	for index in 4:
		var level := index + 1
		var feast := _ability(ABILITY_IDS[0], level).effects[0] as GluttonyLifestealAuraEffect
		var regen := _ability(ABILITY_IDS[1], level).effects[0] as GluttonyRegenerationEffect
		var aura := _ability(ABILITY_IDS[2], level).effects[0] as GluttonyDamageAuraEffect
		var siphon := _ability(ABILITY_IDS[3], level)
		var death := _ability(ABILITY_IDS[4], level).effects[0] as GluttonyDeathExplosionEffect
		var grease := _ability(ABILITY_IDS[5], level)
		_check(feast.radius == 250.0 and feast.lifesteal_percent == expected[index], "Shared Feast Level %d values are exact." % level)
		_check(regen.max_stacks == expected_stacks[index] and regen.max_hp_percent_per_stack == 0.1, "Bottomless Recovery Level %d values are exact." % level)
		_check(aura.radius == 200.0 and aura.interval == 1.0 and aura.damage == expected_aura_damage[index], "Ravenous Miasma Level %d values are exact." % level)
		_check(siphon.cooldown_seconds == 6.0 and siphon.delivery_method == AbilityDefinition.DeliveryMethod.MELEE_HIT and (siphon.effects[0] as GluttonySiphonEffect).damage == expected_siphon[index], "Consume Level %d values and delivery are exact." % level)
		_check(death.damage == expected_death_damage[index] and death.radius == expected_death_radius[index], "Final Course Level %d values are exact." % level)
		_check(grease.cooldown_seconds == 8.0 and grease.area_radius == 200.0 and grease.cast_range == 250.0 and (grease.effects[0] as GluttonyGreaseEffect).miss_percent == expected_miss[index] and (grease.effects[0] as GluttonyGreaseEffect).duration == 4.0, "Grease Spill Level %d values are exact." % level)
	var run := DemoRunFactory.create_starting_run(9800)
	var hero := HeroState.new()
	hero.unique_id = "gluttony-reward"
	hero.definition_id = GLUTTONY_ID
	run.heroes = [hero]
	var route := registry.get_definition(RunState.ROUTE_DEFINITION_ID) as RouteDefinition
	var candidates := HeroAbilityRewardService._candidates(hero, registry, route)
	var candidate_ids := candidates.map(func(entry: Dictionary) -> StringName: return StringName(entry.ability_id))
	_check(ABILITY_IDS.all(func(ability_id: StringName) -> bool: return candidate_ids.has(ability_id)), "HeroAbilityRewardService offers all six Gluttony abilities.")


func _test_lifesteal_aura() -> void:
	var gluttony := _snapshot("gluttony", GLUTTONY_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO, 1000.0, 100.0)
	gluttony.abilities = [_ability(ABILITY_IDS[0], 2)]
	var melee := _snapshot("melee", &"test.melee", CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.SOLDIER, 500.0, 100.0)
	var ranged := _snapshot("ranged", &"test.ranged", CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.SOLDIER, 500.0, 100.0)
	ranged.attack_type = &"ranged"
	var enemy := _snapshot("enemy", &"test.enemy", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 1000.0, 10.0)
	var session := _session([gluttony, melee, ranged], [enemy], 9801)
	var gluttony_unit := _unit(session, "gluttony")
	var melee_unit := _unit(session, "melee")
	var ranged_unit := _unit(session, "ranged")
	var enemy_unit := _unit(session, "enemy")
	gluttony_unit.position = Vector2(300, 300)
	melee_unit.position = Vector2(310, 300)
	ranged_unit.position = Vector2(320, 300)
	enemy_unit.position = Vector2(340, 300)
	for ally in [gluttony_unit, melee_unit, ranged_unit]:
		ally.current_hp -= 100.0
		_basic_attack_once(ally, enemy_unit)
	_check(gluttony_unit.current_hp == 916.0 and melee_unit.current_hp == 416.0 and ranged_unit.current_hp == 416.0, "The dynamic 250 aura includes Gluttony and heals melee and ranged basic attackers at 16%.")
	melee_unit.position = Vector2(551, 300)
	var hp_before := melee_unit.current_hp
	var dealt := enemy_unit.take_damage(50.0, melee_unit, &"ability.test", &"effect.test")
	melee_unit.apply_basic_attack_lifesteal(0.0)
	_check(melee_unit.current_hp == hp_before and dealt == 50.0, "Ability damage and allies outside radius receive no aura lifesteal.")
	var panel: SelectedUnitPanel = SELECTED_PANEL_SCENE.instantiate()
	root.add_child(panel)
	ranged_unit.position = Vector2(320, 300)
	panel.show_combatant(ranged_unit)
	_check(panel.status_summary_text().contains("Shared Feast") and panel.status_summary_text().contains("16%"), "Active aura lifesteal appears in status indicator tooltips.")
	panel.free()
	session.free()


func _test_regeneration_stacks() -> void:
	var gluttony := _snapshot("gluttony", GLUTTONY_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO, 1000.0, 10.0)
	gluttony.abilities = [_ability(ABILITY_IDS[1], 1)]
	var enemy := _snapshot("enemy", &"test.enemy", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 1000.0, 10.0)
	var session := _session([gluttony], [enemy], 9802)
	var unit := _unit(session, "gluttony")
	var attacker := _unit(session, "enemy")
	unit.take_damage(100.0, attacker, &"ability.test", &"effect.test")
	unit.add_shield(100.0, 10.0, unit, &"ability.test", &"effect.test")
	unit.take_damage(50.0, attacker)
	_check(unit.gluttony_regeneration_stacks == 0, "Abilities and fully absorbed basic attacks grant no regeneration stack.")
	unit.take_damage(60.0, attacker)
	_check(unit.gluttony_regeneration_stacks == 1, "A basic attack that removes HP grants exactly one regeneration stack.")
	for hit in 20:
		unit.take_damage(1.0, attacker)
	_check(unit.gluttony_regeneration_stacks == 10, "Regeneration stacks stop at the authored Level 1 maximum.")
	var hp_before := unit.current_hp
	unit._update_runtime(0.99)
	_check(unit.current_hp == hp_before, "Regeneration does not heal before its first full one-second interval.")
	unit._update_runtime(0.01)
	_check(is_equal_approx(unit.current_hp, hp_before + 10.0), "Ten stacks heal 1% of current effective max HP on the one-second tick.")
	var panel: SelectedUnitPanel = SELECTED_PANEL_SCENE.instantiate()
	root.add_child(panel)
	panel.show_combatant(unit)
	_check(panel.status_summary_text().contains("10/10 stacks") and panel.status_summary_text().contains("10.0 HP per second"), "Regeneration stack count and healing per second appear in status indicator tooltips.")
	panel.free()
	session.free()


func _test_damage_aura_and_siphon() -> void:
	var gluttony := _snapshot("gluttony", GLUTTONY_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO, 1000.0, 10.0)
	gluttony.abilities = [_ability(ABILITY_IDS[2], 2)]
	var near := _snapshot("near", &"test.enemy", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 500.0, 10.0)
	near.stats.armor = 100.0
	var far := _snapshot("far", &"test.enemy", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 500.0, 10.0)
	var session := _session([gluttony], [near, far], 9803)
	var unit := _unit(session, "gluttony")
	var near_unit := _unit(session, "near")
	var far_unit := _unit(session, "far")
	unit.position = Vector2(300, 300)
	near_unit.position = Vector2(500, 300)
	far_unit.position = Vector2(501, 300)
	unit._update_runtime(0.99)
	_check(near_unit.current_hp == 500.0, "Damage aura waits for its first full interval.")
	unit._update_runtime(0.01)
	_check(near_unit.current_hp == 490.0 and far_unit.current_hp == 500.0, "Damage aura includes the 200-radius boundary, excludes farther targets, and uses normal armor.")
	var damage_events := session.events.filter(func(event: CombatEvent) -> bool: return event.event_type == CombatEvent.DAMAGE_APPLIED and event.ability_id == ABILITY_IDS[2])
	_check(damage_events.size() == 1 and damage_events[0].source_id == "gluttony", "Damage aura preserves source and ability attribution for statistics.")
	near_unit.shields = [{"amount": 30.0, "remaining": 10.0, "source_id": "", "ability_id": &"", "effect_id": &""}]
	near_unit.current_hp = 80.0
	unit.current_hp = 800.0
	var siphon := _ability(ABILITY_IDS[3], 2)
	(siphon.effects[0] as GluttonySiphonEffect).apply(unit, near_unit, siphon)
	_check(near_unit.current_hp == 10.0 and unit.current_hp == 870.0, "Consume heals exactly the 70 actual damage remaining after armor and shield.")
	_check(session.resolve_ability_target(unit, siphon) == far_unit, "Consume targeting reflects the target's damage knockback and still chooses the nearest enemy deterministically.")
	session.free()


func _test_death_explosion() -> void:
	var gluttony := _snapshot("gluttony", GLUTTONY_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO, 100.0, 10.0)
	gluttony.abilities = [_ability(ABILITY_IDS[4], 1)]
	var ally := _snapshot("ally", &"test.ally", CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO, 100.0, 10.0)
	var near := _snapshot("near", &"test.enemy", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 1000.0, 10.0)
	near.stats.armor = 100.0
	var far := _snapshot("far", &"test.enemy", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 1000.0, 10.0)
	var session := _session([gluttony, ally], [near, far], 9804)
	var unit := _unit(session, "gluttony")
	var ally_unit := _unit(session, "ally")
	var attacker := _unit(session, "near")
	var far_unit := _unit(session, "far")
	unit.position = Vector2(300, 300)
	attacker.position = Vector2(540, 300)
	far_unit.position = Vector2(541, 300)
	ally_unit.last_stand_aura_duration = 1.0
	# The lethal blow pushes Gluttony a fixed 10 units so the explosion radius edge stays exact.
	unit.damage_knockback_max_distance = 10.0
	unit.take_damage(100.0, attacker)
	_check(unit.last_stand_remaining == 1.0 and attacker.current_hp == 1000.0, "Final Course does not trigger when Gluttony first enters last stand.")
	unit._update_runtime(1.0)
	_check(not unit.is_alive() and attacker.current_hp == 900.0 and far_unit.current_hp == 1000.0, "Final death triggers one armored explosion on targets within the inclusive post-knockback radius.")
	var hp_after := attacker.current_hp
	unit.force_die(attacker, &"effect.forced")
	_check(attacker.current_hp == hp_after, "Final Course cannot explode twice after forced death paths.")
	var explosion_events := session.events.filter(func(event: CombatEvent) -> bool: return event.event_type == CombatEvent.DAMAGE_APPLIED and event.ability_id == ABILITY_IDS[4])
	_check(explosion_events.size() == 1 and explosion_events[0].source_id == "gluttony", "A dead Gluttony retains explosion attribution.")
	session.free()


func _test_grease() -> void:
	var gluttony := _snapshot("gluttony", GLUTTONY_ID, CombatUnitSnapshot.Team.PLAYER, CombatUnitSnapshot.UnitKind.HERO, 500.0, 10.0)
	var primary := _snapshot("primary", &"test.enemy", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 500.0, 10.0)
	var secondary := _snapshot("secondary", &"test.enemy", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 500.0, 10.0)
	secondary.is_boss = true
	var outside := _snapshot("outside", &"test.enemy", CombatUnitSnapshot.Team.ENEMY, CombatUnitSnapshot.UnitKind.ENEMY, 500.0, 10.0)
	var session := _session([gluttony], [primary, secondary, outside], 9805)
	var unit := _unit(session, "gluttony")
	var primary_unit := _unit(session, "primary")
	var secondary_unit := _unit(session, "secondary")
	var outside_unit := _unit(session, "outside")
	unit.position = Vector2(100, 300)
	primary_unit.position = Vector2(300, 300)
	secondary_unit.position = Vector2(500, 300)
	outside_unit.position = Vector2(501, 300)
	var grease := _ability(ABILITY_IDS[5], 4)
	session.deliver_ability(unit, primary_unit, grease)
	_check(primary_unit.has_status(&"status.gluttony_grease") and secondary_unit.has_status(&"status.gluttony_grease") and not outside_unit.has_status(&"status.gluttony_grease"), "Grease affects all targetable enemies, including bosses, within 200 of the closest target.")
	primary_unit._update_runtime(2.0)
	session.deliver_ability(unit, primary_unit, grease)
	_check(primary_unit.statuses.size() == 1 and is_equal_approx(primary_unit.statuses[0].remaining_duration, 4.0), "Grease reapplication refreshes duration without stacking.")
	var hp_before := unit.current_hp
	primary_unit.session.combat_rng.seed = 7
	unit.apply_gluttony_grease(100.0, 4.0, primary_unit, ABILITY_IDS[5])
	unit.take_damage(50.0, primary_unit)
	_check(unit.current_hp == hp_before, "A greased basic attack misses before hit resolution.")
	unit.take_damage(50.0, primary_unit, &"ability.test", &"effect.test")
	unit.take_damage(50.0, primary_unit, &"status.dot", &"effect.dot")
	_check(unit.current_hp == hp_before - 100.0, "Grease never makes abilities or periodic damage miss.")
	var first_sequence := []
	var second_sequence := []
	for sequence in [first_sequence, second_sequence]:
		session.combat_rng.seed = 9805
		unit.gluttony_grease_miss_percent = 60.0
		for roll in 8:
			sequence.append(session.should_dodge(unit, true))
	_check(first_sequence == second_sequence, "Grease miss rolls are stable for the same combat seed.")
	var panel: SelectedUnitPanel = SELECTED_PANEL_SCENE.instantiate()
	root.add_child(panel)
	panel.show_combatant(primary_unit)
	var status_text: String = panel.status_summary_text()
	_check(status_text.contains("Greased") and status_text.contains("60%") and status_text.contains("4.0 s"), "Grease miss chance and refreshed duration appear in STATUS UI.")
	panel.free()
	session.free()


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
