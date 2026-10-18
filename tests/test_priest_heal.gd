extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")
const SELECTED_PANEL_SCENE := preload("res://ui/combat/selected_unit_panel.tscn")

var failures := 0
var registry: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	_test_content()
	_test_targeting_and_cast_range()
	_test_veterancy_scaling_and_description()
	if failures == 0:
		print("Priest Heal tests passed.")
		quit()
	else:
		push_error("Priest Heal tests failed: %d" % failures)
		quit(1)


func _test_content() -> void:
	var job := registry.get_definition(&"job.priest", false) as JobDefinition
	var ability := registry.get_definition(&"ability.priest_heal", false) as AbilityDefinition
	_check(job != null and job.innate_ability_ids == [&"ability.priest_heal"], "Priest has Heal as its innate default ability.")
	if ability == null:
		_fail("Priest Heal is registered as ability content.")
		return
	var effect := ability.effects[0] as HealEffect
	_check(
		ability.targeting_policy == AbilityDefinition.TargetingPolicy.LOWEST_CURRENT_HP_ALLY
		and ability.cooldown_seconds == 3.0
		and ability.target_search_radius == 600.0
		and ability.cast_range == 300.0
		and effect != null
		and effect.amount == 50.0
		and effect.veterancy_bonus_percent_per_level == 25.0,
		"Priest Heal exposes the authored healing, cooldown, search radius, and cast range."
	)


func _test_targeting_and_cast_range() -> void:
	var ability := registry.get_definition(&"ability.priest_heal") as AbilityDefinition
	var priest := _snapshot("priest", CombatUnitSnapshot.Team.PLAYER, 100.0)
	priest.abilities.append(ability)
	var low_current_hp := _snapshot("low-current", CombatUnitSnapshot.Team.PLAYER, 100.0)
	var low_ratio := _snapshot("low-ratio", CombatUnitSnapshot.Team.PLAYER, 500.0)
	var outside_search := _snapshot("outside-search", CombatUnitSnapshot.Team.PLAYER, 100.0)
	var enemy := _snapshot("enemy", CombatUnitSnapshot.Team.ENEMY, 100.0)
	var players: Array[CombatUnitSnapshot] = [priest, low_current_hp, low_ratio, outside_search]
	var enemies: Array[CombatUnitSnapshot] = [enemy]
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200.0, 600.0)
	root.add_child(session)
	session.setup(players, enemies, 7319)
	for combatant in session.combatants:
		combatant.set_simulation_active(false)

	var priest_unit := session.get_combatant_by_runtime_id("priest")
	var low_current_unit := session.get_combatant_by_runtime_id("low-current")
	var low_ratio_unit := session.get_combatant_by_runtime_id("low-ratio")
	var outside_unit := session.get_combatant_by_runtime_id("outside-search")
	priest_unit.position = Vector2(100.0, 100.0)
	low_current_unit.position = Vector2(500.0, 100.0)
	low_ratio_unit.position = Vector2(450.0, 200.0)
	outside_unit.position = Vector2(701.0, 100.0)
	low_current_unit.current_hp = 40.0
	low_ratio_unit.current_hp = 50.0
	outside_unit.current_hp = 1.0

	_check(session.resolve_ability_target(priest_unit, ability) == low_current_unit, "Heal selects the lowest absolute current HP inside its search radius.")
	priest_unit._acquire_target()
	_check(
		priest_unit.pending_ability == ability
		and priest_unit.target == low_current_unit
		and priest_unit.state == Combatant.State.MOVE_INTO_RANGE
		and not priest_unit.ability_cooldowns.has(ability.id)
		and low_current_unit.current_hp == 40.0,
		"Priest moves toward a selected ally without starting cooldown or healing outside cast range."
	)
	priest_unit.position = Vector2(200.0, 100.0)
	priest_unit._move_toward_target(0.0)
	priest_unit._update_attack_windup(0.3)
	_check(low_current_unit.current_hp == 90.0 and priest_unit.ability_cooldowns[ability.id] == 3.0, "Heal restores 50 HP at 300 range and starts its three-second cooldown.")

	low_current_unit.current_hp = low_current_unit.get_effective_stat(&"max_hp")
	low_ratio_unit.current_hp = low_ratio_unit.get_effective_stat(&"max_hp")
	outside_unit.position = Vector2(801.0, 100.0)
	_check(session.resolve_ability_target(priest_unit, ability) == null, "Heal ignores a lower-HP ally outside its 600 search radius.")
	session.free()


func _test_veterancy_scaling_and_description() -> void:
	var soldier := SoldierState.new()
	soldier.unique_id = "veteran-priest"
	soldier.current_job_id = &"job.priest"
	soldier.veterancy_level = 2
	var snapshot := CombatSnapshotBuilder.build_soldier(soldier, null, registry)
	var heal := snapshot.abilities.filter(func(ability: AbilityDefinition) -> bool: return ability.id == &"ability.priest_heal")[0] as AbilityDefinition
	var heal_effect := heal.effects[0] as HealEffect
	var authored_heal := registry.get_definition(&"ability.priest_heal") as AbilityDefinition
	_check(heal_effect.amount == 75.0, "Priest Heal gains 25% of its base amount per Veterancy level.")
	_check((authored_heal.effects[0] as HealEffect).amount == 50.0, "Veterancy scaling does not mutate the shared authored Heal resource.")

	var ally := _snapshot("wounded", CombatUnitSnapshot.Team.PLAYER, 500.0)
	var enemy := _snapshot("enemy", CombatUnitSnapshot.Team.ENEMY, 500.0)
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200.0, 600.0)
	root.add_child(session)
	session.setup([snapshot, ally], [enemy], 7320)
	for combatant in session.combatants:
		combatant.set_simulation_active(false)
	var priest_unit := session.get_combatant_by_runtime_id("veteran-priest")
	var ally_unit := session.get_combatant_by_runtime_id("wounded")
	ally_unit.current_hp = 100.0
	(heal.effects[0] as HealEffect).apply(priest_unit, ally_unit, heal)
	_check(ally_unit.current_hp == 175.0, "The scaled runtime Heal restores its displayed amount.")

	var panel: SelectedUnitPanel = SELECTED_PANEL_SCENE.instantiate()
	root.add_child(panel)
	panel.show_combatant(priest_unit)
	var heal_slot := panel.get_node("%AbilityIcons").get_child(0) as ContentIconButton
	_check(heal_slot.content_id == heal.id and heal_slot.tooltip_override.to_lower().contains("heals [b]75[/b]"), "Selected-unit skill icon tooltip shows the Priest's effective Heal amount.")
	var first_stat_icon := panel.get_node("%StatsGrid").get_child(0).get_child(0).get_child(0) as TextureRect
	_check(panel.get_node("%StatsGrid").get_child_count() == 6 and first_stat_icon.texture is AtlasTexture, "Selected-unit panel renders six atlas-backed characteristic icons.")
	_check(panel.get_node("%AbilityIcons").get_child_count() >= HeroState.MAX_ABILITY_SLOTS and not panel.get_node("%Equipment").visible, "Selected Soldier panel reserves four ability icons without an item grid.")
	panel.free()
	session.free()


func _snapshot(runtime_id: String, team: int, max_hp: float) -> CombatUnitSnapshot:
	var snapshot := CombatUnitSnapshot.new()
	snapshot.runtime_id = runtime_id
	snapshot.definition_id = &"test.unit"
	snapshot.display_name = runtime_id
	snapshot.team = team
	snapshot.unit_kind = CombatUnitSnapshot.UnitKind.SOLDIER if team == CombatUnitSnapshot.Team.PLAYER else CombatUnitSnapshot.UnitKind.ENEMY
	snapshot.attack_type = &"ranged"
	snapshot.stats.max_hp = max_hp
	snapshot.stats.damage = 10.0
	snapshot.stats.attack_speed = 1.0
	snapshot.stats.movement_speed = 100.0
	snapshot.stats.attack_range = 100.0
	snapshot.stats.armor = 0.0
	return snapshot


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	failures += 1
	push_error(message)
