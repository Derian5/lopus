extends SceneTree


## Hero item content and every item mechanic (stats, passives, actives).

const SESSION_SCENE := preload("res://combat/combat_session.tscn")

var failures := 0
var registry: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	registry = root.get_node("ContentRegistry")
	_test_content()
	_test_stat_stacking()
	_test_secondary_stats()
	_test_damage_items()
	_test_tank_items()
	_test_support_items()
	_test_command_items()
	_test_unique_items()
	_test_simulation_smoke()
	if failures == 0:
		print("Item tests passed.")
		quit()
	else:
		push_error("Item tests failed: %d" % failures)
		quit(1)


func _test_content() -> void:
	var items: Array = registry.definitions.values().filter(func(d) -> bool: return d is ItemDefinition)
	_check(items.size() == 42, "42 Hero items are authored (got %d)." % items.size())
	_check(not registry.has_definition(&"item.hero.vanguard_blade") and not registry.has_definition(&"item.hero.titan_seal"), "Old items are removed.")
	var counts := {}
	var icon_paths := {}
	for item in items:
		counts[item.category] = int(counts.get(item.category, 0)) + 1
		_check(item.icon != null, "%s has an item icon." % item.display_name)
		if item.icon != null:
			_check(item.icon.get_size() == Vector2(128, 128), "%s has a 128x128 icon." % item.display_name)
			_check(item.icon.resource_path.begins_with("res://graphics/ui/item_icons/warcraft/") and not icon_paths.has(item.icon.resource_path), "%s has its own approved-style icon." % item.display_name)
			icon_paths[item.icon.resource_path] = true
		_check(item.sell_price == item.price / 2, "%s sells for half its price." % item.display_name)
		for ability_id in item.ability_ids:
			var ability := registry.get_definition(ability_id, false) as AbilityDefinition
			_check(ability != null and not ability.available_to_heroes, "%s ability %s exists and is not a Hero reward." % [item.display_name, ability_id])
			if ability != null:
				_check(ability.icon == item.icon and ability.presentation_icon == item.icon, "%s ability uses its owning item's art." % ability_id)
			_check(not AbilityText.plain(ability).contains("{"), "%s ability text resolves every token." % item.display_name)
	_check(counts == {0: 9, 1: 9, 2: 9, 3: 8, 4: 7}, "Category sizes match the design table.")
	var crown := registry.get_definition(&"item.pride_crown") as ItemDefinition
	var pride := registry.get_definition(&"hero.control_savant") as HeroDefinition
	var wrath := registry.get_definition(&"hero.ashen_duelist") as HeroDefinition
	_check(crown.is_unique() and crown.is_compatible_with_hero(pride) and not crown.is_compatible_with_hero(wrath), "Unique items fit only their Sin.")
	var cleaver := registry.get_definition(&"item.butcher_cleaver") as ItemDefinition
	_check(cleaver.price == 325 and cleaver.is_compatible_with_hero(wrath), "Common items fit any Hero.")


func _test_stat_stacking() -> void:
	var run := _run_with_items([&"item.butcher_cleaver", &"item.rusted_talisman", &"item.lamp_of_penance", &"item.black_bile_flask", &"item.executioner_gloves"])
	var hero := CombatSnapshotBuilder.build_player_army(run, registry)[0]
	var base := (registry.get_definition(run.heroes[0].definition_id) as HeroDefinition).base_stats
	_check(is_equal_approx(hero.stats.damage, base.damage + 45.0 + 80.0), "Flat damage bonuses add up.")
	_check(is_equal_approx(hero.stats.attack_speed, base.attack_speed * 1.5), "Two +25% attack speed bonuses add to +50%.")
	_check(is_equal_approx(hero.stats.cooldown_reduction, 100.0 - 100.0 * 0.65 * 0.65), "Cooldown reduction stacks with diminishing returns (35% + 35% = 57.75%).")
	_check(is_equal_approx(hero.stats.crit_chance, 25.0) and is_equal_approx(hero.stats.crit_multiplier, 2.5), "Crit chance and multiplier come from items.")
	_check(is_equal_approx(hero.stats.hp_regen, 20.0), "HP regeneration adds up.")
	var many := _run_with_items([&"item.crimson_mass_chalice", &"item.plague_doctor_mask", &"item.book_of_damned_names", &"item.seal_of_oblivion"])
	var capped := CombatSnapshotBuilder.build_player_army(many, registry)[0]
	_check(is_equal_approx(capped.stats.cooldown_reduction, CombatStats.MAX_COOLDOWN_REDUCTION), "Cooldown reduction is capped at 75%.")
	_check(hero.abilities.any(func(a: AbilityDefinition) -> bool: return a.id == &"ability.item_butcher_cleaver"), "Item abilities join the Hero's combat abilities.")
	var text := (StatModifier.new())
	text.stat = "attack_speed"
	text.operation = StatModifier.Operation.ADD_PERCENT
	text.value = 25.0
	_check(text.display_text() == "+25% Attack Speed", "Percent bonuses read as +25% Attack Speed.")


func _test_secondary_stats() -> void:
	var hero := _snapshot("hero", CombatUnitSnapshot.Team.PLAYER, 1000.0)
	hero.stats.crit_chance = 100.0
	hero.stats.crit_multiplier = 2.5
	hero.stats.lifesteal = 50.0
	hero.stats.hp_regen = 10.0
	hero.stats.cooldown_reduction = 50.0
	var enemy := _snapshot("enemy", CombatUnitSnapshot.Team.ENEMY, 5000.0)
	enemy.stats.dodge = 0.0
	var session := _session([hero], [enemy], 11)
	var unit := session.get_combatant_by_runtime_id("hero")
	var foe := session.get_combatant_by_runtime_id("enemy")
	var dealt := foe.take_damage(100.0, unit)
	_check(is_equal_approx(dealt, 250.0), "A 100%% crit deals x2.5 basic damage (got %.1f)." % dealt)
	unit.current_hp = 500.0
	unit.apply_basic_attack_lifesteal(100.0)
	_check(is_equal_approx(unit.current_hp, 550.0), "Lifesteal heals 50% of basic-attack damage.")
	unit.current_hp = 500.0
	_step(session, 1.05)
	_check(unit.current_hp >= 509.9 and unit.current_hp <= 510.1, "HP regeneration heals 10 per second.")
	var ability := registry.get_definition(&"ability.item_lamp_of_penance") as AbilityDefinition
	_check(is_equal_approx(unit.cooldown_for(ability), 5.0), "50% cooldown reduction halves a 10s cooldown.")
	foe.snapshot.stats.dodge = 60.0
	var dodged := 0
	for attempt in 200:
		if session.should_dodge(foe, true):
			dodged += 1
	_check(dodged > 90 and dodged < 150, "60%% dodge evades roughly 60%% of basic attacks (%d / 200)." % dodged)
	session.free()


func _test_damage_items() -> void:
	var hero := _hero_with([&"ability.item_butcher_cleaver", &"ability.item_spinner_needle", &"ability.item_hangman_bow", &"ability.item_executioner_gloves"])
	var enemy := _snapshot("enemy", CombatUnitSnapshot.Team.ENEMY, 10000.0)
	var session := _session([hero], [enemy], 21)
	var unit := session.get_combatant_by_runtime_id("hero")
	var foe := session.get_combatant_by_runtime_id("enemy")
	for hit in 3:
		unit.record_successful_basic_hit(foe, 10.0)
	_check(foe.status_stacks(&"status.item_bleed") == 3, "Butcher's Cleaver bleed stacks up to 3.")
	_check(foe.has_status(&"status.item_bound") and foe.status_stacks(&"status.item_thread") == 0, "Three Threads bind the target and are consumed.")
	_check(foe.has_status(&"status.item_noose"), "Every third hit applies the Noose.")
	_check(is_equal_approx(foe.get_effective_stat(&"damage_taken"), 35.0), "Noose adds +35% damage taken.")
	var before_hp := foe.current_hp
	foe.take_damage(100.0, unit, &"test.raw", &"test.raw")
	_check(is_equal_approx(before_hp - foe.current_hp, 135.0), "Noosed targets take 35% more damage.")
	foe.remove_status(&"status.item_bound")
	for hit in 3:
		unit.record_successful_basic_hit(foe, 10.0)
	_check(not foe.has_status(&"status.item_bound"), "Thread binding has an 8s cooldown per target.")
	_step(session, 1.05)
	_check(foe.current_hp < before_hp - 135.0 - 40.0, "Bleed deals damage over time.")
	foe.current_hp = foe.get_effective_stat(&"max_hp") * 0.15
	unit.record_successful_basic_hit(foe, 10.0)
	_check(not foe.is_alive(), "Executioner's Gloves execute enemies below 20% HP.")
	_check(unit.items.execute_gold_earned == 15, "Each execution earns 15 Gold.")
	session.free()


func _test_tank_items() -> void:
	var tank := _hero_with([&"ability.item_ash_shroud", &"ability.item_martyr_ribs", &"ability.item_thorn_crown", &"ability.item_shadow_monk_cloak"])
	var ally := _snapshot("ally", CombatUnitSnapshot.Team.PLAYER, 1000.0)
	ally.unit_kind = CombatUnitSnapshot.UnitKind.SOLDIER
	ally.formation_position = Vector2.ZERO
	var enemy := _snapshot("enemy", CombatUnitSnapshot.Team.ENEMY, 10000.0)
	var session := _session([tank, ally], [enemy], 31)
	var unit := session.get_combatant_by_runtime_id("hero")
	var friend := session.get_combatant_by_runtime_id("ally")
	var foe := session.get_combatant_by_runtime_id("enemy")
	friend.position = unit.position + Vector2(50, 0)
	foe.position = unit.position + Vector2(120, 0)
	var unit_hp := unit.current_hp
	friend.take_damage(100.0, foe, &"test.raw", &"test.raw")
	_check(is_equal_approx(friend.current_hp, 940.0), "Martyr's Ribs: the ally takes only 60% of the damage.")
	_check(is_equal_approx(unit.current_hp, unit_hp - 40.0 + 10.0), "Martyr's Ribs: the Hero takes 40% and heals 25% of it.")
	unit.current_hp = unit.get_effective_stat(&"max_hp")
	var foe_hp := foe.current_hp
	unit.take_damage(300.0, foe, &"test.raw", &"test.raw")
	_check(is_equal_approx(foe_hp - foe.current_hp, 250.0) and foe.is_feared(), "Crown of Thorns bursts after 300 damage and fears nearby enemies.")
	unit.current_hp = unit.get_effective_stat(&"max_hp") * 0.45
	unit.take_damage(100.0, foe, &"test.raw", &"test.raw")
	_check(unit.shields.size() == 1 and is_equal_approx(float(unit.shields[0].amount), 600.0), "Ash Shroud shields for 600 below 40% HP.")
	_check(unit.items.regeneration_per_second() >= 30.0, "Ash Shroud adds +30 HP regen while the shield holds.")
	unit.shields.clear()
	unit.current_hp = unit.get_effective_stat(&"max_hp") * 0.1
	unit.take_damage(10.0, foe, &"test.raw", &"test.raw")
	_check(unit.shields.is_empty(), "Ash Shroud triggers once per battle.")
	foe.statuses.clear()
	foe.target = unit
	var cloak := registry.get_definition(&"ability.item_shadow_monk_cloak") as AbilityDefinition
	var low_hp := unit.current_hp
	_check(unit._try_activate_ability(cloak, false), "Shadow Monk's Cloak activates below 40% HP.")
	_check(unit.stealth_remaining > 0.0 and not unit.can_be_targeted_by(foe) and foe.target != unit, "The Hero turns invisible and enemies drop it as a target.")
	_check(unit.current_hp > low_hp, "Vanish restores HP.")
	# Fear makes the enemy run away from its source.
	foe.statuses.clear()
	foe.apply_status((registry.get_definition(&"ability.item_thorn_crown") as AbilityDefinition).effects[0].status, unit, &"ability.item_thorn_crown")
	foe.set_simulation_active(true)
	var distance_before := foe.position.distance_to(unit.position)
	for frame in 20:
		foe._physics_process(1.0 / 60.0)
	_check(foe.position.distance_to(unit.position) > distance_before + 5.0, "Feared units flee from the source.")
	session.free()


func _test_support_items() -> void:
	var support := _hero_with([&"ability.item_lamp_of_penance", &"ability.item_beads_of_diligence", &"ability.item_canon_shackles", &"ability.item_vial_of_tears"])
	var ally := _snapshot("ally", CombatUnitSnapshot.Team.PLAYER, 1000.0)
	var weak := _snapshot("weak", CombatUnitSnapshot.Team.ENEMY, 1000.0)
	var strong := _snapshot("strong", CombatUnitSnapshot.Team.ENEMY, 1000.0)
	strong.stats.damage = 80.0
	var session := _session([support, ally], [weak, strong], 41)
	var unit := session.get_combatant_by_runtime_id("hero")
	var friend := session.get_combatant_by_runtime_id("ally")
	friend.position = unit.position + Vector2(40, 0)
	friend.current_hp = 300.0
	var lamp := registry.get_definition(&"ability.item_lamp_of_penance") as AbilityDefinition
	session.deliver_ability(unit, session.resolve_ability_target(unit, lamp), lamp)
	_check(is_equal_approx(friend.current_hp, 700.0), "Lamp of Penance heals the most wounded ally for 400.")
	var shackles := registry.get_definition(&"ability.item_canon_shackles") as AbilityDefinition
	var target := session.resolve_ability_target(unit, shackles)
	_check(target != null and target.snapshot.runtime_id == "strong", "Canon's Shackles target the enemy with the highest damage.")
	session.deliver_ability(unit, target, shackles)
	_check(target.is_rooted(), "Shackled enemies cannot move.")
	var beads := registry.get_definition(&"ability.item_beads_of_diligence") as AbilityDefinition
	session.deliver_ability(unit, unit, beads)
	_check(friend.has_status(&"status.item_diligence") and is_equal_approx(friend.get_effective_stat(&"hp_regen"), 25.0), "Beads give nearby allies +25 HP regen.")
	friend.statuses.clear()
	friend.current_hp = 300.0
	var max_hp := unit.get_effective_stat(&"max_hp")
	_step(session, 1.05)
	_check(friend.current_hp >= 300.0 + max_hp * 0.04 - 0.1, "Vial of Mother's Tears heals wounded allies every second.")
	session.free()


func _test_command_items() -> void:
	var commander := _hero_with([&"ability.item_banner_of_fallen", &"ability.item_necromagister_skull", &"ability.item_horn_of_besieged", &"ability.item_bell_of_last_night"])
	var soldiers: Array[CombatUnitSnapshot] = [commander]
	for index in 4:
		var soldier := _snapshot("soldier-%d" % index, CombatUnitSnapshot.Team.PLAYER, 100.0)
		soldier.veterancy_level = 0 if index == 0 else 2
		soldiers.append(soldier)
	var enemies: Array[CombatUnitSnapshot] = []
	for index in 6:
		enemies.append(_snapshot("enemy-%d" % index, CombatUnitSnapshot.Team.ENEMY, 100.0))
	var session := _session(soldiers, enemies, 51)
	var unit := session.get_combatant_by_runtime_id("hero")
	var recruit := session.get_combatant_by_runtime_id("soldier-0")
	var veteran := session.get_combatant_by_runtime_id("soldier-1")
	recruit.position = unit.position + Vector2(30, 0)
	veteran.position = unit.position + Vector2(0, 30)
	_check(is_equal_approx(recruit.get_effective_stat(&"damage"), 12.5) and is_equal_approx(veteran.get_effective_stat(&"damage"), 14.0), "Banner: +25% Soldier damage, +40% for veterans.")
	var horn := registry.get_definition(&"ability.item_horn_of_besieged") as AbilityDefinition
	_check(not session.can_use_ability(unit, unit, horn), "The Horn waits until 3 allies are below 50% HP.")
	for index in 3:
		session.get_combatant_by_runtime_id("soldier-%d" % (index + 1)).current_hp = 30.0
	_check(session.can_use_ability(unit, unit, horn), "The Horn is ready with 3 wounded allies.")
	session.deliver_ability(unit, unit, horn)
	_check(is_equal_approx(recruit.get_effective_stat(&"attack_speed"), 1.6), "The Horn gives the whole army +60% attack speed.")
	var spawned := 0
	for index in 6:
		var foe := session.get_combatant_by_runtime_id("enemy-%d" % index)
		foe.position = unit.position + Vector2(100, 10 * index)
		foe.take_damage(10000.0, unit, &"test.raw", &"test.raw")
	for combatant in session.combatants:
		if combatant.snapshot.definition_id == &"enemy.summoned_skeleton" and combatant.is_alive():
			spawned += 1
			_check(combatant.snapshot.team == CombatUnitSnapshot.Team.PLAYER and combatant.items.lifetime_remaining > 0.0, "Skeletons fight for the Hero and expire.")
	_check(spawned >= 1 and spawned <= 6, "The Skull raises skeletons from nearby corpses (%d)." % spawned)
	session.free()
	# Bell of the Last Night.
	var bell_hero := _hero_with([&"ability.item_bell_of_last_night"])
	var army: Array[CombatUnitSnapshot] = [bell_hero]
	for index in 4:
		army.append(_snapshot("s-%d" % index, CombatUnitSnapshot.Team.PLAYER, 100.0))
	var bell_session := _session(army, [_snapshot("boss", CombatUnitSnapshot.Team.ENEMY, 1000.0)], 52)
	var ringer := bell_session.get_combatant_by_runtime_id("hero")
	var bell := registry.get_definition(&"ability.item_bell_of_last_night") as AbilityDefinition
	_check(not bell_session.can_use_ability(ringer, ringer, bell), "The Bell waits while most of the army lives.")
	bell_session.get_combatant_by_runtime_id("s-0").force_die(null, &"test")
	bell_session.get_combatant_by_runtime_id("s-1").force_die(null, &"test")
	_check(not bell_session.can_use_ability(ringer, ringer, bell), "Exactly half the army alive is not enough.")
	bell_session.get_combatant_by_runtime_id("s-3").force_die(null, &"test")
	bell_session.get_combatant_by_runtime_id("s-2").current_hp = 50.0
	_check(bell_session.can_use_ability(ringer, ringer, bell), "The Bell rings when less than half the army is alive.")
	bell_session.deliver_ability(ringer, ringer, bell)
	var survivor := bell_session.get_combatant_by_runtime_id("s-2")
	_check(survivor.is_invulnerable() and is_equal_approx(survivor.current_hp, 90.0), "Allies become invulnerable and heal 40% HP.")
	_check(survivor.take_damage(500.0, bell_session.get_combatant_by_runtime_id("boss"), &"test.raw", &"test.raw") == 0.0, "Invulnerable units take no damage.")
	_check(not bell_session.can_use_ability(ringer, ringer, bell), "The Bell works once per battle.")
	bell_session.free()


func _test_unique_items() -> void:
	# Pride: isolation.
	var pride := _hero_with([&"ability.item_pride_crown"])
	var friend := _snapshot("friend", CombatUnitSnapshot.Team.PLAYER, 100.0)
	var enemy := _snapshot("enemy", CombatUnitSnapshot.Team.ENEMY, 1000.0)
	var session := _session([pride, friend], [enemy], 61)
	var unit := session.get_combatant_by_runtime_id("hero")
	var ally := session.get_combatant_by_runtime_id("friend")
	ally.position = unit.position + Vector2(100, 0)
	_check(is_equal_approx(unit.get_effective_stat(&"damage"), 10.0), "Pride's Crown is inactive with an ally nearby.")
	ally.position = unit.position + Vector2(0, 600)
	_check(is_equal_approx(unit.get_effective_stat(&"damage"), 19.0) and is_equal_approx(unit.get_effective_stat(&"damage_taken"), -45.0), "Alone, Pride deals +90% damage and takes 45% less.")
	session.free()
	# Envy: stacks from enemy casts.
	var envy := _hero_with([&"ability.item_envy_mask"])
	var caster := _snapshot("caster", CombatUnitSnapshot.Team.ENEMY, 1000.0)
	caster.abilities = [registry.get_definition(&"ability.troll_priest_heal") as AbilityDefinition]
	session = _session([envy], [caster], 62)
	unit = session.get_combatant_by_runtime_id("hero")
	var foe := session.get_combatant_by_runtime_id("caster")
	foe.position = unit.position + Vector2(200, 0)
	for cast in 6:
		session.record_ability_used(foe, foe, &"ability.troll_priest_heal")
	_check(unit.status_stacks(&"status.item_stolen_joy") == 5 and is_equal_approx(unit.get_effective_stat(&"attack_speed"), 2.25), "Envy's Mask stacks to 5 (+125% attack speed).")
	session.free()
	# Wrath: Rage and armor penetration.
	var wrath := _hero_with([&"ability.item_wrath_axe"])
	var armored := _snapshot("armored", CombatUnitSnapshot.Team.ENEMY, 100000.0)
	armored.stats.armor = 100.0
	session = _session([wrath], [armored], 63)
	unit = session.get_combatant_by_runtime_id("hero")
	foe = session.get_combatant_by_runtime_id("armored")
	unit.snapshot.stats.max_hp = 5000.0
	unit.current_hp = 5000.0
	unit.take_damage(599.0, foe, &"test.raw", &"test.raw")
	_check(not unit.has_status(&"status.item_fury"), "Rage needs 40 points (600 damage).")
	unit.take_damage(10.0, foe, &"test.raw", &"test.raw")
	_check(unit.has_status(&"status.item_fury") and is_equal_approx(unit.get_effective_stat(&"attack_speed"), 2.2), "Fury: +120% attack speed.")
	var plain := CombatRules.calculate_damage(100.0, 100.0)
	var pierced := foe.take_damage(100.0, unit, &"test.raw", &"test.raw")
	_check(pierced > plain and is_equal_approx(pierced, CombatRules.calculate_damage(100.0, 20.0)), "Fury ignores 80% of the target's armor.")
	session.free()
	# Despair: slow aura and sleep.
	var despair := _hero_with([&"ability.item_despair_chains_aura", &"ability.item_despair_chains_sleep"])
	var near := _snapshot("near", CombatUnitSnapshot.Team.ENEMY, 1000.0)
	session = _session([despair], [near], 64)
	unit = session.get_combatant_by_runtime_id("hero")
	foe = session.get_combatant_by_runtime_id("near")
	foe.position = unit.position + Vector2(200, 0)
	_check(is_equal_approx(foe.get_effective_stat(&"attack_speed"), 0.55) and is_equal_approx(foe.get_effective_stat(&"movement_speed"), 55.0), "Despair's Chains slow nearby enemies by 45%.")
	var sleep := registry.get_definition(&"ability.item_despair_chains_sleep") as AbilityDefinition
	session.deliver_ability(unit, session.resolve_ability_target(unit, sleep), sleep)
	foe.take_damage(50.0, unit, &"test.raw", &"test.raw")
	_check(foe.is_stunned(), "Eternal Slumber is not broken by damage.")
	session.free()
	# Greed: gold scaling and post-battle gold.
	var run := _run_with_items([&"item.greed_idol"], &"hero.test_vanguard")
	run.gold = 400
	var greed := CombatSnapshotBuilder.build_player_army(run, registry)[0]
	var base := (registry.get_definition(&"hero.test_vanguard") as HeroDefinition).base_stats
	_check(is_equal_approx(greed.stats.damage, (base.damage + 70.0) * 1.16), "Greed's Idol: +2% damage per 50 Gold (400 Gold = +16%).")
	run.gold = 5000
	greed = CombatSnapshotBuilder.build_player_army(run, registry)[0]
	_check(is_equal_approx(greed.stats.max_hp, (base.max_hp + 700.0) * 1.5), "Greed's Idol bonus is capped at +50%.")
	session = _session([greed], [_snapshot("loot", CombatUnitSnapshot.Team.ENEMY, 10.0)], 65)
	session.get_combatant_by_runtime_id("loot").force_die(session.get_combatant_by_runtime_id(greed.runtime_id), &"test")
	session._check_battle_end()
	_check(session.statistics.bonus_gold == 50, "Greed's Idol adds 50 Gold after a won battle.")
	session.free()
	# Gluttony: kill growth that persists.
	var glutton := _hero_with([&"ability.item_gluttony_maw"])
	glutton.permanent_gains[&"ability.item_gluttony_maw"] = 490.0
	var snacks: Array[CombatUnitSnapshot] = [_snapshot("snack-a", CombatUnitSnapshot.Team.ENEMY, 10.0), _snapshot("snack-b", CombatUnitSnapshot.Team.ENEMY, 10.0)]
	session = _session([glutton], snacks, 66)
	unit = session.get_combatant_by_runtime_id("hero")
	var hp_before := unit.get_effective_stat(&"max_hp")
	session.get_combatant_by_runtime_id("snack-a").take_damage(100.0, unit, &"test.raw", &"test.raw")
	session.get_combatant_by_runtime_id("snack-b").take_damage(100.0, unit, &"test.raw", &"test.raw")
	_check(is_equal_approx(unit.get_effective_stat(&"max_hp"), hp_before + 10.0), "Insatiable Maw growth stops at +500 for the run.")
	_check(session.statistics.permanent_stat_gains.size() == 1, "Maw growth is recorded as a permanent Hero gain.")
	session.free()
	# Lust: charm.
	var lust := _hero_with([&"ability.item_lust_veil"])
	var big := _snapshot("big", CombatUnitSnapshot.Team.ENEMY, 900.0)
	var small := _snapshot("small", CombatUnitSnapshot.Team.ENEMY, 100.0)
	session = _session([lust], [big, small], 67)
	unit = session.get_combatant_by_runtime_id("hero")
	var veil := registry.get_definition(&"ability.item_lust_veil") as AbilityDefinition
	var victim := session.resolve_ability_target(unit, veil)
	_check(victim != null and victim.snapshot.runtime_id == "big", "The Veil charms the enemy with the most HP.")
	session.deliver_ability(unit, victim, veil)
	_check(victim.snapshot.team == CombatUnitSnapshot.Team.PLAYER and session.find_closest_target(victim).snapshot.runtime_id == "small", "Charmed enemies attack their allies.")
	session.get_combatant_by_runtime_id("small").force_die(unit, &"test")
	session._check_battle_end()
	_check(session.battle_active, "A charmed enemy still counts as an enemy for victory.")
	_step(session, 5.1)
	_check(victim.snapshot.team == CombatUnitSnapshot.Team.ENEMY, "Charm ends after 5 seconds.")
	session.free()


func _test_simulation_smoke() -> void:
	# Every item on every slot of three Heroes, a full simulated battle must not error.
	var ids: Array = registry.definitions.values().filter(func(d) -> bool: return d is ItemDefinition and not d.is_unique()).map(func(d) -> StringName: return d.id)
	var heroes: Array[CombatUnitSnapshot] = []
	for index in 6:
		var hero := _snapshot("hero-%d" % index, CombatUnitSnapshot.Team.PLAYER, 600.0)
		hero.unit_kind = CombatUnitSnapshot.UnitKind.HERO
		for item_index in range(index * 6, mini(index * 6 + 6, ids.size())):
			var item := registry.get_definition(ids[item_index]) as ItemDefinition
			for ability_id in item.ability_ids:
				hero.abilities.append(registry.get_definition(ability_id) as AbilityDefinition)
		heroes.append(hero)
	var uniques: Array = registry.definitions.values().filter(func(d) -> bool: return d is ItemDefinition and d.is_unique())
	var unique_hero := _snapshot("unique", CombatUnitSnapshot.Team.PLAYER, 600.0)
	unique_hero.unit_kind = CombatUnitSnapshot.UnitKind.HERO
	for item in uniques:
		for ability_id in item.ability_ids:
			unique_hero.abilities.append(registry.get_definition(ability_id) as AbilityDefinition)
	heroes.append(unique_hero)
	var enemies: Array[CombatUnitSnapshot] = []
	for index in 8:
		var foe := _snapshot("foe-%d" % index, CombatUnitSnapshot.Team.ENEMY, 900.0)
		foe.stats.damage = 25.0
		foe.abilities = [registry.get_definition(&"ability.troll_priest_heal") as AbilityDefinition]
		enemies.append(foe)
	var session := _session(heroes, enemies, 71)
	for combatant in session.combatants:
		combatant.set_simulation_active(true)
	_step(session, 60.0, true)
	_check(not session.battle_active or session.elapsed_time > 0.0, "A battle with every item runs to completion without errors.")
	session.free()


# --- helpers -----------------------------------------------------------------------

func _hero_with(ability_ids: Array) -> CombatUnitSnapshot:
	var hero := _snapshot("hero", CombatUnitSnapshot.Team.PLAYER, 1000.0)
	hero.unit_kind = CombatUnitSnapshot.UnitKind.HERO
	for ability_id in ability_ids:
		hero.abilities.append(registry.get_definition(ability_id) as AbilityDefinition)
	return hero


func _run_with_items(item_ids: Array, hero_id: StringName = &"hero.ashen_duelist") -> RunState:
	var run := RunState.new()
	var hero := HeroState.new()
	hero.unique_id = "hero-a"
	hero.definition_id = hero_id
	hero.level = 1
	run.heroes.append(hero)
	for item_id in item_ids:
		hero.item_ids.append(run.inventory.create_item(item_id))
	return run


func _snapshot(runtime_id: String, team: int, max_hp: float) -> CombatUnitSnapshot:
	var snapshot := CombatUnitSnapshot.new()
	snapshot.runtime_id = runtime_id
	snapshot.definition_id = &"test.unit"
	snapshot.display_name = runtime_id
	snapshot.team = team
	snapshot.unit_kind = CombatUnitSnapshot.UnitKind.SOLDIER if team == CombatUnitSnapshot.Team.PLAYER else CombatUnitSnapshot.UnitKind.ENEMY
	snapshot.stats.max_hp = max_hp
	snapshot.stats.damage = 10.0
	snapshot.stats.attack_speed = 1.0
	snapshot.stats.movement_speed = 100.0
	snapshot.stats.attack_range = 100.0
	snapshot.stats.armor = 0.0
	return snapshot


func _session(players: Array[CombatUnitSnapshot], enemies: Array[CombatUnitSnapshot], seed: int) -> CombatSession:
	var session: CombatSession = SESSION_SCENE.instantiate()
	session.set_anchors_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1200.0, 700.0)
	root.add_child(session)
	session.setup(players, enemies, seed)
	for combatant in session.combatants:
		combatant.set_simulation_active(false)
	return session


## Advances the battle by hand: runtime ticks always, full AI only when simulate is set.
func _step(session: CombatSession, seconds: float, simulate := false) -> void:
	var delta := 1.0 / 60.0
	var frames := int(ceil(seconds / delta))
	for frame in frames:
		if not session.battle_active and simulate:
			return
		for combatant in session.combatants.duplicate():
			if simulate:
				combatant._physics_process(delta)
			elif combatant.state != Combatant.State.DEAD:
				combatant._update_runtime(delta)
		session._process(delta)
		if simulate:
			session._physics_process(delta)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
