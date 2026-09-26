extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")

var failures := 0
var registry: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	_test_content()
	_test_bloodrage_behavior()
	if failures == 0:
		print("Massive Ogre tests passed.")
		quit()
	else:
		push_error("Massive Ogre tests failed: %d" % failures)
		quit(1)


func _test_content() -> void:
	var definition := registry.get_definition(&"enemy.massive_ogre", false) as EnemyDefinition
	_check(definition != null, "Massive Ogre is registered as enemy content.")
	if definition == null:
		return
	_check(
		definition.base_stats.max_hp == 520.0
		and definition.base_stats.damage == 42.0
		and definition.base_stats.attack_speed == 1.5
		and definition.base_stats.armor == 52.0
		and definition.base_stats.movement_speed == 64.0,
		"Massive Ogre has the requested base stats."
	)
	_check(definition.attack_type == &"melee" and definition.ability_ids == [&"ability.massive_ogre_rage"], "Massive Ogre is melee and owns only its self-buff ability.")
	var ability := registry.get_definition(&"ability.massive_ogre_rage") as AbilityDefinition
	var speed_effect := ability.effects[0] as StatModifierEffect
	var empowerment := ability.effects[1] as BasicAttackEmpowerEffect
	_check(
		ability.kind == AbilityDefinition.AbilityKind.ACTIVE
		and ability.targeting_policy == AbilityDefinition.TargetingPolicy.SELF
		and ability.cooldown_seconds == 15.0,
		"Massive Bloodrage is an active self-only ability with a 15-second cooldown."
	)
	_check(speed_effect.duration == 6.0 and speed_effect.modifier.operation == StatModifier.Operation.MULTIPLY and speed_effect.modifier.value == 1.5, "Massive Bloodrage grants x1.5 attack speed for six seconds.")
	_check(empowerment.duration == 6.0 and empowerment.lifesteal_percent == 50.0 and empowerment.size_multiplier == 1.5, "Massive Bloodrage grants the requested lifesteal and size increase.")


func _test_bloodrage_behavior() -> void:
	var definition := registry.get_definition(&"enemy.massive_ogre") as EnemyDefinition
	var ogre := CombatSnapshotBuilder.build_enemy(definition, "ogre", "Massive Ogre", registry)
	var player := CombatUnitSnapshot.new()
	player.runtime_id = "player"
	player.definition_id = &"test.player"
	player.display_name = "Player"
	player.team = CombatUnitSnapshot.Team.PLAYER
	player.unit_kind = CombatUnitSnapshot.UnitKind.HERO
	player.stats.max_hp = 200.0
	player.stats.damage = 10.0
	player.stats.attack_speed = 1.0
	player.stats.movement_speed = 100.0
	player.stats.attack_range = 48.0
	player.stats.armor = 0.0
	var players: Array[CombatUnitSnapshot] = [player]
	var enemies: Array[CombatUnitSnapshot] = [ogre]
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200.0, 600.0)
	root.add_child(session)
	session.setup(players, enemies, 8801)
	for combatant in session.combatants:
		combatant.set_simulation_active(false)
	var ogre_unit := session.get_combatant_by_runtime_id("ogre")
	var player_unit := session.get_combatant_by_runtime_id("player")
	var rage := registry.get_definition(&"ability.massive_ogre_rage") as AbilityDefinition
	_check(session.resolve_ability_target(ogre_unit, rage) == ogre_unit, "Massive Bloodrage can target only its caster.")
	ogre_unit._acquire_target()
	var collision := ogre_unit.get_node("CollisionShape2D").shape as CircleShape2D
	_check(is_equal_approx(ogre_unit.get_effective_stat(&"attack_speed"), 2.25), "Bloodrage multiplies the Ogre's attack speed by 1.5.")
	_check(is_equal_approx(ogre_unit.body_radius, 24.0) and is_equal_approx(collision.radius, 24.0), "Bloodrage increases both model and collision radius by 50%.")
	_check(ogre_unit.ability_cooldowns[&"ability.massive_ogre_rage"] == 15.0, "Casting Bloodrage starts its 15-second cooldown.")

	ogre_unit.current_hp = 400.0
	ogre_unit.position = Vector2(300.0, 300.0)
	player_unit.position = Vector2(340.0, 300.0)
	ogre_unit.target = player_unit
	ogre_unit.pending_ability = null
	ogre_unit.state = Combatant.State.ATTACK_WINDUP
	ogre_unit.state_timer = 0.0
	ogre_unit.windup_duration = 0.0
	var player_hp_before := player_unit.current_hp
	ogre_unit._update_attack_windup(0.0)
	var damage_dealt := player_hp_before - player_unit.current_hp
	_check(is_equal_approx(damage_dealt, 42.0) and is_equal_approx(ogre_unit.current_hp, 421.0), "Bloodrage heals the Ogre for 50% of actual basic-attack damage.")

	ogre_unit._update_runtime(6.1)
	_check(is_equal_approx(ogre_unit.get_effective_stat(&"attack_speed"), 1.5), "Bloodrage attack speed expires after six seconds.")
	_check(is_equal_approx(ogre_unit.body_radius, 16.0) and is_equal_approx(collision.radius, 16.0), "Model and collision size return to normal when Bloodrage expires.")
	var hp_after_expiry := ogre_unit.current_hp
	player_unit.current_hp = player_hp_before
	ogre_unit.target = player_unit
	ogre_unit.state = Combatant.State.ATTACK_WINDUP
	ogre_unit.state_timer = 0.0
	ogre_unit._update_attack_windup(0.0)
	_check(is_equal_approx(ogre_unit.current_hp, hp_after_expiry), "Basic attacks stop granting lifesteal after Bloodrage expires.")
	session.free()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
