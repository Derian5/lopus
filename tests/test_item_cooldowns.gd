extends SceneTree

const SESSION := preload("res://combat/combat_session.tscn")
const PANEL := preload("res://ui/combat/selected_unit_panel.tscn")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var registry := root.get_node("ContentRegistry")
	var inventory := InventoryState.new()
	var hero := HeroState.new()
	hero.unique_id = "cooldown-hero"
	hero.definition_id = &"hero.iron_oracle"
	for id in [&"item.lamp_of_penance", &"item.vial_of_tears", &"item.spinner_needle", &"item.despair_chains", &"item.butcher_cleaver", &"item.bell_of_last_night"]:
		hero.item_ids.append(inventory.create_item(id))
	var snapshot := CombatSnapshotBuilder.build_hero(hero, inventory, registry)
	var enemy := CombatUnitSnapshot.new()
	enemy.runtime_id = "cooldown-enemy"
	enemy.team = CombatUnitSnapshot.Team.ENEMY
	enemy.unit_kind = CombatUnitSnapshot.UnitKind.ENEMY
	enemy.stats.max_hp = 10000.0
	enemy.stats.damage = 10.0
	var session: CombatSession = SESSION.instantiate()
	session.vfx_enabled = false
	root.add_child(session)
	session.setup([snapshot], [enemy], 97621)
	session.set_process(false)
	session.set_physics_process(false)
	for unit in session.combatants:
		unit.set_simulation_active(false)
	var unit := session.get_combatant_by_runtime_id(hero.unique_id)
	var foe := session.get_combatant_by_runtime_id(enemy.runtime_id)
	var panel: SelectedUnitPanel = PANEL.instantiate()
	root.add_child(panel)
	panel.show_combatant(unit)
	var slots: GridContainer = panel.get_node("%ItemIcons")
	for slot in slots.get_children():
		_check(slot is AbilityCooldownIcon, "Hero items use the same cooldown renderer as abilities.")
	var lamp := slots.get_child(0) as AbilityCooldownIcon
	var vial := slots.get_child(1) as AbilityCooldownIcon
	var needle := slots.get_child(2) as AbilityCooldownIcon
	var chains := slots.get_child(3) as AbilityCooldownIcon
	_check(lamp.content_id == &"item.lamp_of_penance" and lamp.icon == registry.get_definition(lamp.content_id).icon, "Cooldown slots retain item identity and artwork.")
	_check(is_zero_approx(lamp.cooldown_ratio), "A ready active item is not darkened.")
	_check(is_equal_approx(vial.cooldown_remaining, 1.0) and is_equal_approx(vial.cooldown_ratio, 1.0), "Periodic healing shows its live interval from the first inspector refresh.")
	unit.current_hp -= 100.0
	var lamp_ability := registry.get_definition(&"ability.item_lamp_of_penance") as AbilityDefinition
	var sleep_ability := registry.get_definition(&"ability.item_despair_chains_sleep") as AbilityDefinition
	_check(unit._try_activate_ability(lamp_ability, true) and unit._try_activate_ability(sleep_ability, true), "Real item activations start their battle cooldowns.")
	panel.refresh_cooldowns()
	var total := unit.cooldown_for(lamp_ability)
	_check(total > 0.0 and total < lamp_ability.cooldown_seconds and is_equal_approx(lamp.cooldown_remaining, total) and is_equal_approx(lamp.cooldown_total, total) and is_equal_approx(lamp.cooldown_ratio, 1.0), "An activated item starts with a full indicator using cooldown reduction.")
	_check(is_equal_approx(chains.cooldown_remaining, unit.cooldown_for(sleep_ability)), "An item with passive and active abilities displays its active cooldown.")
	unit._update_runtime(2.25)
	panel.refresh_cooldowns()
	_check(is_equal_approx(lamp.cooldown_remaining, total - 2.25) and lamp.cooldown_ratio < 1.0, "The icon counts down from the simulation's remaining time.")
	_check(is_equal_approx(vial.cooldown_remaining, 0.75) and is_equal_approx(vial.cooldown_ratio, 0.75), "Periodic item countdown follows pulses, including large simulation steps.")
	for hit in 3:
		unit.items.on_basic_hit(foe, 1.0)
	panel.refresh_cooldowns()
	_check(not unit.items.stack_triggers[0].cooldowns.is_empty() and is_zero_approx(needle.cooldown_ratio), "A per-target proc lockout is not misrepresented as an item-wide cooldown.")
	_check(is_zero_approx((slots.get_child(4) as AbilityCooldownIcon).cooldown_ratio), "An untimed passive item has no countdown overlay.")
	var cooldowns_before := unit.ability_cooldowns.duplicate(true)
	var pulse_before := float(unit.items.pulse_heals[0].remaining)
	var rng_before := session.combat_rng.state
	for refresh in 5:
		panel.refresh_cooldowns()
	_check(unit.ability_cooldowns == cooldowns_before and is_equal_approx(float(unit.items.pulse_heals[0].remaining), pulse_before) and session.combat_rng.state == rng_before, "Refreshing the UI does not advance timers or consume gameplay RNG.")
	unit._update_runtime(total)
	panel.refresh_cooldowns()
	_check(is_zero_approx(lamp.cooldown_ratio) and is_zero_approx(chains.cooldown_ratio), "The overlay disappears when an active item is ready again.")
	var empty_hero := HeroState.new()
	empty_hero.unique_id = "empty-hero"
	empty_hero.definition_id = &"hero.iron_oracle"
	var empty_unit := session._spawn_combatant(CombatSnapshotBuilder.build_hero(empty_hero, InventoryState.new(), registry), session.get_arena_bounds().get_center(), session.get_arena_bounds())
	panel.show_combatant(empty_unit)
	for slot in slots.get_children():
		_check(is_zero_approx((slot as AbilityCooldownIcon).cooldown_ratio), "Switching to an unequipped Hero clears previous item timers.")
	panel.show_combatant(foe)
	_check(not panel.get_node("%Equipment").visible and slots.get_child_count() == 0, "Inspecting an unequipped enemy does not retain Hero item overlays.")
	panel.free()
	session.free()
	if DisplayServer.get_name() != "headless":
		await _test_rendered_overlay(registry.get_definition(&"item.lamp_of_penance"))
	if failures == 0:
		print("Item cooldown tests passed: item art, activation/CDR, periodic pulses, passive effects, multi-ability items, ready state, inspector switching and read-only presentation.")
	quit(1 if failures else 0)

func _test_rendered_overlay(item: ItemDefinition) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(160, 80)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	for index in 2:
		var icon := AbilityCooldownIcon.new()
		viewport.add_child(icon)
		icon.configure(item, &"item", "1")
		icon.position = Vector2(8 + index * 80, 8)
		icon.size = Vector2(64, 64)
		icon.set_cooldown(5.0 if index == 0 else 0.0, 10.0)
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var cooling_bottom := 0.0
	var ready_bottom := 0.0
	var top_difference := 0.0
	for x in range(20, 52):
		for y in range(52, 62):
			cooling_bottom += image.get_pixel(x, y).get_luminance()
			ready_bottom += image.get_pixel(x + 80, y).get_luminance()
		for y in range(16, 24):
			top_difference += absf(image.get_pixel(x, y).get_luminance() - image.get_pixel(x + 80, y).get_luminance())
	_check(cooling_bottom < ready_bottom * 0.75, "Rendered item cooldown darkens the unrecovered part of the artwork.")
	_check(top_difference < 1.0, "The revealed part of a cooling item keeps its normal artwork brightness.")
	viewport.free()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
