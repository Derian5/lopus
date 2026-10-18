extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")
const WRATH_ID := &"hero.ashen_duelist"
const ABILITY_IDS: Array[StringName] = [
	&"ability.wrath_melee_retaliation",
	&"ability.wrath_focused_damage",
	&"ability.wrath_frenzy",
	&"ability.wrath_leap_slam",
	&"ability.wrath_threshold_guard",
	&"ability.wrath_ground_slam",
]

var failures := 0
var registry: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	_test_content_and_levels()
	_test_retaliation_and_focused_damage()
	_test_frenzy_and_leap()
	_test_threshold_guard_and_ground_slam()
	if failures == 0:
		print("Wrath ability tests passed.")
		quit()
	else:
		push_error("Wrath ability tests failed: %d" % failures)
		quit(1)


func _test_content_and_levels() -> void:
	for ability_id in ABILITY_IDS:
		var ability := registry.get_definition(ability_id, false) as AbilityDefinition
		_check(ability != null and ability.allowed_hero_ids == [WRATH_ID] and ability.hero_levels.size() == 4, "%s is a four-level Wrath-exclusive ability." % ability_id)
	var retaliation := _ability(&"ability.wrath_melee_retaliation", 4).effects[0] as MeleeRetaliationEffect
	var focus := _ability(&"ability.wrath_focused_damage", 4).effects[0] as FocusedDamageEffect
	var frenzy := _ability(&"ability.wrath_frenzy", 4).effects[0] as FrenzyEffect
	var leap := _ability(&"ability.wrath_leap_slam", 4).effects[0] as LeapSlamEffect
	var guard := _ability(&"ability.wrath_threshold_guard", 4).effects[0] as ThresholdGuardEffect
	var slam := _ability(&"ability.wrath_ground_slam", 4)
	_check(retaliation.radius == 400.0 and retaliation.damage_multiplier == 8.0, "Vengeful Host reaches x8 retaliation inside 400 range.")
	_check(focus.damage_per_stack == 40.0 and focus.stack_duration == 7.0, "Fixation reaches +40 damage with seven-second independent stacks.")
	_check(frenzy.attack_speed_multiplier == 8.0 and frenzy.duration == 7.0, "Blind Frenzy reaches x8 attack speed for seven seconds.")
	_check(leap.damage == 800.0 and leap.knockback_distance == 150.0 and leap.stun_duration == 5.0, "Cataclysmic Leap reaches its Level 4 damage, knockback, and stun values.")
	_check(guard.shield_max_hp_multiplier == 1.2 and guard.armor_multiplier == 2.5 and guard.cooldown_seconds == 30.0, "Too Angry to Fall reaches its Level 4 shield and armor values.")
	_check(slam.cooldown_seconds == 3.0 and (slam.effects[0] as GroundSlamEffect).damage_multiplier == 4.0, "Seismic Blow reaches x4 area damage and a three-second cooldown.")


func _test_retaliation_and_focused_damage() -> void:
	var wrath := _snapshot("wrath", CombatUnitSnapshot.Team.PLAYER, 1000.0, 10.0)
	wrath.abilities = [_ability(&"ability.wrath_melee_retaliation", 2), _ability(&"ability.wrath_focused_damage", 1)]
	var ally := _snapshot("ally", CombatUnitSnapshot.Team.PLAYER, 1000.0, 30.0)
	var far_ally := _snapshot("far-ally", CombatUnitSnapshot.Team.PLAYER, 1000.0, 100.0)
	var enemy := _snapshot("enemy", CombatUnitSnapshot.Team.ENEMY, 1000.0, 10.0)
	var session := _session([wrath, ally, far_ally], [enemy], 9501)
	var wrath_unit := session.get_combatant_by_runtime_id("wrath")
	var ally_unit := session.get_combatant_by_runtime_id("ally")
	var far_ally_unit := session.get_combatant_by_runtime_id("far-ally")
	var enemy_unit := session.get_combatant_by_runtime_id("enemy")
	wrath_unit.position = Vector2(300.0, 300.0)
	ally_unit.position = Vector2(400.0, 300.0)
	far_ally_unit.position = Vector2(900.0, 300.0)
	enemy_unit.position = Vector2(320.0, 300.0)
	enemy_unit.current_hp = 1000.0
	wrath_unit.take_damage(10.0, enemy_unit, &"attack.basic", &"attack.basic", true)
	_check(enemy_unit.current_hp == 940.0, "A nearby ally immediately retaliates at x2 damage while Wrath and distant allies do not.")

	_attack_once(wrath_unit, enemy_unit)
	_attack_once(wrath_unit, enemy_unit)
	_check(enemy_unit.current_hp == 915.0, "Repeated basic attacks gain damage from active same-target stacks.")
	wrath_unit._update_runtime(7.1)
	_attack_once(wrath_unit, enemy_unit)
	_check(enemy_unit.current_hp == 905.0, "Each focused damage stack independently expires after seven seconds.")
	session.free()


func _test_frenzy_and_leap() -> void:
	var wrath := _snapshot("wrath", CombatUnitSnapshot.Team.PLAYER, 1000.0, 10.0)
	var ally := _snapshot("ally", CombatUnitSnapshot.Team.PLAYER, 1000.0, 10.0)
	var primary := _snapshot("primary", CombatUnitSnapshot.Team.ENEMY, 1000.0, 10.0)
	var secondary := _snapshot("secondary", CombatUnitSnapshot.Team.ENEMY, 1000.0, 10.0)
	var session := _session([wrath, ally], [primary, secondary], 9502)
	var wrath_unit := session.get_combatant_by_runtime_id("wrath")
	var ally_unit := session.get_combatant_by_runtime_id("ally")
	var primary_unit := session.get_combatant_by_runtime_id("primary")
	var secondary_unit := session.get_combatant_by_runtime_id("secondary")
	wrath_unit.position = Vector2(100.0, 300.0)
	ally_unit.position = Vector2(500.0, 300.0)
	primary_unit.position = Vector2(250.0, 300.0)
	secondary_unit.position = Vector2(300.0, 300.0)
	var frenzy := _ability(&"ability.wrath_frenzy", 4)
	_check(not session.can_use_ability(wrath_unit, wrath_unit, frenzy), "Blind Frenzy cannot activate before Wrath damages an enemy.")
	primary_unit.take_damage(1.0, wrath_unit)
	session.elapsed_time = 2.9
	_check(not session.can_use_ability(wrath_unit, wrath_unit, frenzy), "Blind Frenzy waits three seconds from Wrath's first enemy damage.")
	session.elapsed_time = 3.0
	_check(session.can_use_ability(wrath_unit, wrath_unit, frenzy), "Blind Frenzy becomes available three seconds after the first enemy damage.")
	session._apply_ability_effects(wrath_unit, wrath_unit, frenzy)
	_check(wrath_unit.get_effective_stat(&"attack_speed") == 8.0, "Blind Frenzy multiplies attack speed by its authored value.")
	ally_unit.position = Vector2(130.0, 300.0)
	primary_unit.position = Vector2(700.0, 300.0)
	secondary_unit.position = Vector2(800.0, 300.0)
	_check(session.find_frenzy_attack_target(wrath_unit) == ally_unit, "Frenzy includes nearby allies in its random attack targets.")
	var ally_hp := ally_unit.current_hp
	wrath_unit._update_frenzy(0.1)
	wrath_unit._update_frenzy(1.0)
	_check(ally_unit.current_hp < ally_hp, "Wrath attacks an ally selected during Blind Frenzy.")
	ally_unit.position = Vector2(900.0, 500.0)
	var position_before_roaming := wrath_unit.position
	wrath_unit.state = Combatant.State.ACQUIRE_TARGET
	wrath_unit._update_frenzy(0.2)
	_check(wrath_unit.position != position_before_roaming and wrath_unit.frenzy_destination != Vector2.ZERO, "Blind Frenzy moves Wrath toward seeded random arena points when no unit is in attack range.")
	wrath_unit.frenzy_remaining = 0.0
	primary_unit.current_hp = 1000.0
	primary_unit.position = Vector2(250.0, 300.0)
	secondary_unit.position = Vector2(300.0, 300.0)
	var leap := _ability(&"ability.wrath_leap_slam", 2)
	session._apply_ability_effects(wrath_unit, primary_unit, leap)
	_check(primary_unit.current_hp == 600.0 and wrath_unit.position.distance_to(primary_unit.position) <= wrath_unit.body_radius + primary_unit.body_radius + primary_unit.damage_knockback_max_distance + 1.0, "Cataclysmic Leap moves to its primary target, damages it, and applies the global hit knockback.")
	_check(secondary_unit.position.x == 450.0 and secondary_unit.is_stunned() and is_equal_approx(secondary_unit.statuses[0].remaining_duration, 3.0), "Other enemies are knocked back 150 and stunned for the level duration.")
	session.free()


func _test_threshold_guard_and_ground_slam() -> void:
	var wrath := _snapshot("wrath", CombatUnitSnapshot.Team.PLAYER, 1000.0, 10.0)
	wrath.stats.armor = 20.0
	wrath.abilities = [_ability(&"ability.wrath_threshold_guard", 2)]
	var primary := _snapshot("primary", CombatUnitSnapshot.Team.ENEMY, 1000.0, 10.0)
	var secondary := _snapshot("secondary", CombatUnitSnapshot.Team.ENEMY, 1000.0, 10.0)
	var session := _session([wrath], [primary, secondary], 9503)
	var wrath_unit := session.get_combatant_by_runtime_id("wrath")
	var primary_unit := session.get_combatant_by_runtime_id("primary")
	var secondary_unit := session.get_combatant_by_runtime_id("secondary")
	wrath_unit.position = Vector2(300.0, 300.0)
	primary_unit.position = Vector2(350.0, 300.0)
	secondary_unit.position = Vector2(430.0, 300.0)
	wrath_unit.take_damage(1000.0, primary_unit)
	_check(is_equal_approx(wrath_unit.current_hp, 166.66667) and wrath_unit.shields.size() == 1 and is_equal_approx(float(wrath_unit.shields[0].amount), 600.0), "Dropping below 30% health grants the Level 2 max-health shield.")
	_check(is_equal_approx(wrath_unit.get_effective_stat(&"armor"), 30.0) and wrath_unit.threshold_guard_cooldown_remaining == 30.0, "Threshold guard multiplies armor for ten seconds and starts its cooldown.")

	wrath_unit.snapshot.stats.armor = 0.0
	wrath_unit.temporary_modifiers.clear()
	wrath_unit.shields.clear()
	var slam := _ability(&"ability.wrath_ground_slam", 2)
	session._apply_ability_effects(wrath_unit, wrath_unit, slam)
	_attack_once(wrath_unit, primary_unit)
	_check(primary_unit.current_hp == 970.0 and secondary_unit.current_hp == 980.0, "Seismic Blow adds x2 area damage on top of the normal primary attack.")
	_check(wrath_unit.ground_slam_damage_multiplier == 0.0, "Seismic Blow is consumed by exactly one basic attack.")
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


func _attack_once(source: Combatant, target: Combatant) -> void:
	source.target = target
	source.pending_ability = null
	source._start_attack()
	source._update_attack_windup(1.0)


func _ability(ability_id: StringName, level: int) -> AbilityDefinition:
	return (registry.get_definition(ability_id) as AbilityDefinition).for_hero_level(level)


func _snapshot(runtime_id: String, team: int, hp: float, damage: float) -> CombatUnitSnapshot:
	var snapshot := CombatUnitSnapshot.new()
	snapshot.runtime_id = runtime_id
	snapshot.definition_id = WRATH_ID if runtime_id == "wrath" else &"test.unit"
	snapshot.display_name = runtime_id
	snapshot.team = team
	snapshot.unit_kind = CombatUnitSnapshot.UnitKind.HERO if team == CombatUnitSnapshot.Team.PLAYER else CombatUnitSnapshot.UnitKind.ENEMY
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
