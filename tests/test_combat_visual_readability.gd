extends SceneTree

const SESSION := preload("res://combat/combat_session.tscn")
const PANEL := preload("res://ui/combat/selected_unit_panel.tscn")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var foot_image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	foot_image.fill_rect(Rect2i(5, 2, 6, 4), Color(0.5, 0.4, 0.3))
	foot_image.fill_rect(Rect2i(4, 6, 8, 9), Color.GREEN)
	var foot_texture := ImageTexture.create_from_image(foot_image)
	var alpha_feet := Combatant._scan_feet(foot_texture, false)
	var chroma_feet := Combatant._scan_feet(foot_texture, true)
	_check(Vector2(alpha_feet[0]).y > Vector2(chroma_feet[0]).y, "Transparent art keeps green clothing when locating the ground contact.")
	var registry := root.get_node("ContentRegistry")
	var run := DemoRunFactory.create_starting_run(9701)
	var session: CombatSession = SESSION.instantiate()
	root.add_child(session)
	session.setup(CombatSnapshotBuilder.build_player_army(run, registry), CombatDemoFactory.create_enemy_army(1, 1), 9701)
	session.set_process(false)
	session.set_physics_process(false)
	for unit in session.combatants:
		unit.set_simulation_active(false)
	var ally: Combatant = session.combatants[0]
	var enemy: Combatant = session.combatants[-1]
	_check(ally.overhead_health_color() != enemy.overhead_health_color(), "Allies and enemies have distinct health colours.")
	_check(enemy.unit_sprite.visible and enemy.placeholder_medallion == null, "An animated enemy replaces its fallback role medallion.")
	_check((ally.overhead.material as CanvasItemMaterial).light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED, "Spell lights cannot bleach the health indicators.")
	_check(ally.ground_marker != null and ally.ground_marker.z_index < session.get_node("Units").z_index, "Selection is drawn on the ground below bodies.")
	ally._update_health_trail(0.0)
	var original_hp := ally.current_hp
	ally.current_hp *= 0.5
	ally._update_health_trail(0.01)
	_check(is_equal_approx(ally.health_trail_ratio, 1.0), "Damage leaves a brief readable loss trail.")
	ally._update_health_trail(1.0)
	_check(is_equal_approx(ally.health_trail_ratio, 0.5) and is_equal_approx(ally.current_hp, original_hp * 0.5), "The trail settles without mutating real health.")
	ally.current_hp = original_hp
	ally._update_health_trail(0.0)
	_check(is_equal_approx(ally.health_trail_ratio, 1.0), "Healing updates the indicator immediately.")
	_check(CombatVfx.projectile_for(&"enemy.summoner") == &"hex_orb" and CombatVfx.projectile_for(&"enemy.troll_priest") == &"witch_orb" and CombatVfx.HEAVY_HITTERS.has(&"enemy.raider"), "Enemy effects use persistent content IDs rather than file names.")
	var panel: SelectedUnitPanel = PANEL.instantiate()
	root.add_child(panel)
	ally.snapshot.abilities.clear()
	ally.snapshot.equipped_item_definition_ids.clear()
	panel.show_combatant(ally)
	_check(not panel.get_node("%Equipment").visible, "An unequipped unit does not waste inspector space on empty item slots.")
	for slot in panel.get_node("%AbilityIcons").get_children():
		_check(not slot.visible, "Empty combat ability slots are hidden.")
	var closed := [false]
	panel.close_requested.connect(func() -> void: closed[0] = true)
	panel.get_node("%CloseButton").pressed.emit()
	_check(closed[0], "Unit details expose a working close action.")
	panel.free()
	session.free()
	if failures == 0:
		print("Combat visual readability tests passed: team colours, animated enemies, unshaded HUD, ground selection, damage trail, content IDs and compact inspector.")
	quit(1 if failures else 0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
