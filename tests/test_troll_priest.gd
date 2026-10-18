extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")

var failures := 0
var registry: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	_test_content()
	_test_combat_behavior()
	if failures == 0:
		print("Troll Priest tests passed.")
		quit()
	else:
		push_error("Troll Priest tests failed: %d" % failures)
		quit(1)


func _test_content() -> void:
	var definition := registry.get_definition(&"enemy.troll_priest", false) as EnemyDefinition
	_check(definition != null, "Troll Priest is registered as enemy content.")
	if definition == null:
		return
	_check(
		definition.base_stats.max_hp == 200.0
		and definition.base_stats.damage == 21.0
		and definition.base_stats.armor == 0.0
		and definition.base_stats.attack_range == 250.0
		and definition.attack_type == &"ranged",
		"Troll Priest has the requested base stats and ranged attack type."
	)
	_check(definition.ability_ids == [&"ability.troll_priest_heal", &"ability.troll_priest_poison"], "Troll Priest owns both active abilities in priority order.")
	var heal := registry.get_definition(&"ability.troll_priest_heal") as AbilityDefinition
	var poison := registry.get_definition(&"ability.troll_priest_poison") as AbilityDefinition
	var status := registry.get_definition(&"status.troll_priest_poison") as StatusDefinition
	var heal_effect := heal.effects[0] as HealEffect
	var poison_tick := status.periodic_effects[0] as DamageEffect
	_check(heal.kind == AbilityDefinition.AbilityKind.ACTIVE and heal.cooldown_seconds == 3.0 and heal_effect.amount == 50.0, "The heal restores 50 HP with a three-second cooldown.")
	_check(poison.kind == AbilityDefinition.AbilityKind.ACTIVE and poison.cooldown_seconds == 5.0 and poison.excluded_target_status_id == status.id, "Poison has a five-second cooldown and excludes already poisoned targets.")
	_check(status.default_duration == 0.0 and status.periodic_interval == 1.0 and poison_tick.amount == 20.0, "Poison lasts until battle end and deals 20 damage each second.")


func _test_combat_behavior() -> void:
	var troll_definition := registry.get_definition(&"enemy.troll_priest") as EnemyDefinition
	var troll := CombatSnapshotBuilder.build_enemy(troll_definition, "troll", "Troll Priest", registry)
	var ally := _snapshot("troll-ally", CombatUnitSnapshot.Team.ENEMY)
	var player_a := _snapshot("player-a", CombatUnitSnapshot.Team.PLAYER)
	var player_b := _snapshot("player-b", CombatUnitSnapshot.Team.PLAYER)
	var players: Array[CombatUnitSnapshot] = [player_a, player_b]
	var enemies: Array[CombatUnitSnapshot] = [troll, ally]
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200.0, 600.0)
	root.add_child(session)
	session.setup(players, enemies, 7701)
	for combatant in session.combatants:
		combatant.set_simulation_active(false)

	var troll_unit := session.get_combatant_by_runtime_id("troll")
	var ally_unit := session.get_combatant_by_runtime_id("troll-ally")
	var player_a_unit := session.get_combatant_by_runtime_id("player-a")
	var player_b_unit := session.get_combatant_by_runtime_id("player-b")
	ally_unit.current_hp = 25.0
	troll_unit._acquire_target()
	_check(ally_unit.current_hp == 75.0 and troll_unit.ability_cooldowns[&"ability.troll_priest_heal"] == 3.0, "Troll Priest heals the lowest-health ally and starts the authored cooldown.")

	var poison := registry.get_definition(&"ability.troll_priest_poison") as AbilityDefinition
	var first_target := session.resolve_ability_target(troll_unit, poison)
	_check(first_target in [player_a_unit, player_b_unit], "Poison chooses a valid enemy without poison.")
	session._apply_ability_effects(troll_unit, first_target, poison)
	var second_target := session.resolve_ability_target(troll_unit, poison)
	_check(second_target != null and second_target != first_target, "The next poison application selects a new unpoisoned target.")
	session._apply_ability_effects(troll_unit, second_target, poison)
	_check(session.resolve_ability_target(troll_unit, poison) == null, "Poison cannot target an enemy while every enemy is already poisoned.")

	var hp_before := first_target.current_hp
	first_target._update_runtime(1.0)
	_check(first_target.current_hp == hp_before - 20.0, "Poison deals 20 damage after one second.")
	_check(first_target.statuses.size() == 1 and first_target.statuses[0].infinite_duration, "Poison remains active indefinitely during combat.")
	var slow := registry.get_definition(&"status.slow") as StatusDefinition
	first_target.apply_status(slow, troll_unit, &"ability.test_slow")
	first_target._update_runtime(slow.default_duration + 0.1)
	_check(first_target.has_status(&"status.troll_priest_poison") and not first_target.has_status(&"status.slow"), "Finite statuses still expire while battle-long poison remains.")
	session.free()


func _snapshot(runtime_id: String, team: int) -> CombatUnitSnapshot:
	var snapshot := CombatUnitSnapshot.new()
	snapshot.runtime_id = runtime_id
	snapshot.definition_id = &"test.unit"
	snapshot.display_name = runtime_id
	snapshot.team = team
	snapshot.unit_kind = CombatUnitSnapshot.UnitKind.ENEMY if team == CombatUnitSnapshot.Team.ENEMY else CombatUnitSnapshot.UnitKind.HERO
	snapshot.stats.max_hp = 100.0
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
