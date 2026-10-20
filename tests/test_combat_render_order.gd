extends SceneTree


const SESSION_SCENE := preload("res://combat/combat_session.tscn")
const COMBAT_SCENE := preload("res://combat/combat.tscn")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(180, 180)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var session: CombatSession = SESSION_SCENE.instantiate()
	viewport.add_child(session)
	session.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(180, 180)
	# Deliberately spawn the foreground body first: tree order must not decide depth.
	session.setup([_unit("near", Color.RED), _unit("far", Color.BLUE)], [_unit("enemy", Color.GRAY, CombatUnitSnapshot.Team.ENEMY)], 77001)
	session.set_process(false)
	session.set_physics_process(false)
	for unit in session.combatants:
		unit.set_simulation_active(false)
	var near := session.get_combatant_by_runtime_id("near")
	var far := session.get_combatant_by_runtime_id("far")
	near.position = Vector2(90, 100)
	far.position = Vector2(90, 85)
	session.get_combatant_by_runtime_id("enemy").position = Vector2(155, 155)
	_check(session.get_node("Units").y_sort_enabled and near.z_index == far.z_index, "Live bodies share one Y-sorted layer independently of spawn order.")
	var projectile := CombatSession.PROJECTILE_SCENE.instantiate() as Node2D
	var impact := CombatVfx.spawn(session.get_node("Effects"), &"hit_heavy", Vector2.ZERO)
	_check(near.overhead.z_index > projectile.z_index and near.overhead.z_index > impact.z_index, "Health and veterancy indicators render above bodies, projectiles and attack effects.")
	projectile.free()
	impact.free()
	var rendered := DisplayServer.get_name() != "headless"
	if rendered:
		await _draw_frame()
		_check_pixel(viewport, Vector2i(90, 95), Color.RED, "The lower unit covers the upper unit despite spawning first.")
		_check_pixel(viewport, Vector2i(85, 62), Color(0.28, 0.86, 0.38), "A health bar remains visible over another unit's body.")
		far.position.y = 110
		await _draw_frame()
		_check_pixel(viewport, Vector2i(90, 100), Color.BLUE, "Crossing on the vertical axis immediately updates visual depth.")
	far.position.y = 85
	near.force_die(null, &"effect.test")
	_check(near.z_index < far.z_index and not near.overhead.visible, "Death immediately puts the corpse below live bodies and hides its indicators.")
	_check(session.get_node("Units").z_index + near.z_index > session.z_index, "Corpses remain above the battleground rather than disappearing behind it.")
	if rendered:
		await _draw_frame()
		_check_pixel(viewport, Vector2i(90, 95), Color.BLUE, "A corpse never covers a living unit, even at a lower Y position.")
		_check_pixel(viewport, Vector2i(90, 123), Color.RED.darkened(0.65), "The uncovered part of a corpse is still visible above the terrain.")
	# Restored units must not remain stuck on the corpse layer.
	near.current_hp = near.snapshot.stats.max_hp
	near.state = Combatant.State.ACQUIRE_TARGET
	near._process(0.0)
	near.queue_redraw()
	_check(near.z_index == far.z_index and near.overhead.visible, "A restored unit rejoins the Y-sorted body layer with visible indicators.")
	if rendered:
		await _draw_frame()
		_check_pixel(viewport, Vector2i(90, 95), Color.RED, "A restored foreground body is drawn above the background unit again.")
	viewport.free()
	await _test_combat_ui_layers(rendered)
	if failures == 0:
		print("Combat render-order tests passed%s." % (" (including rendered pixel checks)" if rendered else " (layer and lifecycle checks)"))
		quit()
	else:
		quit(1)


func _test_combat_ui_layers(rendered: bool) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1024, 768)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var combat = COMBAT_SCENE.instantiate()
	combat.battle_started = true
	viewport.add_child(combat)
	combat.set_process(false)
	var session: CombatSession = combat.get_node("%CombatSession")
	session.setup([_unit("ui-overlap", Color.BLUE)], [_unit("ui-enemy", Color.GRAY, CombatUnitSnapshot.Team.ENEMY)], 77002)
	session.set_process(false)
	session.set_physics_process(false)
	for unit in session.combatants:
		unit.set_simulation_active(false)
	var body := session.get_combatant_by_runtime_id("ui-overlap")
	var body_z: int = session.get_node("Units").z_index + body.z_index
	var indicator_z := body_z + body.overhead.z_index
	var summary: PanelContainer = combat.get_node("%PostBattlePanel")
	var selected: Control = combat.get_node("%SelectedUnitPanel")
	for name in ["%PlayerStatistics", "%EnemyStatistics", "%SelectedUnitPanel"]:
		_check(combat.get_node(name).z_index > indicator_z, "%s stays above battlefield bodies and their overhead indicators." % name)
	_check(summary.z_index > selected.z_index and combat.get_node("%RunEventPopup").z_index > summary.z_index, "Results cover unit details, and modal events cover results.")
	var result := CombatResult.new()
	result.winner = &"player"
	summary.show_result(result)
	# Use an opaque probe surface on the actual results panel to test composition,
	# without depending on decorative artwork or the contents of an XP row.
	var panel_color := Color(0.08, 0.32, 0.22)
	var style := StyleBoxFlat.new()
	style.bg_color = panel_color
	summary.add_theme_stylebox_override("panel", style)
	for child in summary.get_children():
		if child is CanvasItem:
			child.hide()
	if rendered:
		await _draw_frame()
		var point := Vector2i(summary.get_global_rect().get_center())
		body.position = session.get_global_transform().affine_inverse() * Vector2(point)
		session.get_combatant_by_runtime_id("ui-enemy").position = Vector2(10000, 10000)
		await _draw_frame()
		_check_pixel(viewport, point, panel_color, "A battlefield body cannot bleed through the results window.")
		_check_pixel(viewport, point + Vector2i(0, -38), panel_color, "A battlefield health bar cannot bleed through the results window.")
		summary.hide_summary()
		await _draw_frame()
		_check_pixel(viewport, point, Color.BLUE, "The battlefield remains visible when the results window is hidden.")
	viewport.free()


func _draw_frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw


func _check_pixel(viewport: SubViewport, point: Vector2i, expected: Color, message: String) -> void:
	var image := viewport.get_texture().get_image()
	var actual := image.get_pixelv(point)
	var distance := Vector3(actual.r, actual.g, actual.b).distance_to(Vector3(expected.r, expected.g, expected.b))
	_check(distance < 0.06, "%s Expected %s, got %s." % [message, expected, actual])


func _unit(id: String, color: Color, team := CombatUnitSnapshot.Team.PLAYER) -> CombatUnitSnapshot:
	var unit := CombatUnitSnapshot.new()
	unit.runtime_id = id
	unit.team = team
	unit.placeholder_color = color
	unit.veterancy_level = -1
	unit.stats.max_hp = 1000.0
	return unit


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
