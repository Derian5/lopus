extends SceneTree

const GEO := preload("res://combat/arena_geometry.gd")
const SESSION := preload("res://combat/combat_session.tscn")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for size in [Vector2(1600, 800), Vector2(1104, 505), Vector2(800, 450)]:
		var bounds := Rect2(Vector2(48, 150), size)
		for point in [Vector2(0.1, 0.1), Vector2(0.90, 0.1), Vector2(0.05, 0.9), Vector2(0.96, 0.92)]:
			_check(not GEO.contains(bounds.position + point * size, bounds), "Marked ruins and lower corner piles are impassable.")
		for point in [Vector2(0.03, 0.45), Vector2(0.97, 0.5), Vector2(0.5, 0.5)]:
			_check(GEO.contains(bounds.position + point * size, bounds, 20.16), "The centre lane and lateral openings remain walkable.")
		for radius in [20.16, 31.92]:
			for x in 17:
				for y in 17:
					var desired: Vector2 = bounds.position + Vector2(x / 16.0, y / 16.0) * size
					var clamped := GEO.clamp_point(desired, bounds, radius)
					_check(GEO.contains(clamped, bounds, radius), "Projection respects unit radius on every boundary.")
		var from: Vector2 = bounds.position + Vector2(0.34, 0.04) * size
		var goal: Vector2 = bounds.position + Vector2(0.03, 0.42) * size
		from = GEO.clamp_point(from, bounds, 20.16)
		goal = GEO.clamp_point(goal, bounds, 20.16)
		_check(not GEO.segment_is_walkable(from, goal, bounds, 20.16), "The upper-left ruin blocks a direct shortcut between two legal points.")
		var first := _route(from, goal, bounds)
		var repeated := _route(from, goal, bounds)
		_check(first == repeated, "Obstacle routing is deterministic, including with a warm graph cache.")
		var pushed := GEO.move_point(from, goal, bounds, 20.16)
		_check(GEO.contains(pushed, bounds, 20.16) and GEO.segment_is_walkable(from, pushed, bounds, 20.16), "A fast displacement cannot tunnel through a ruin.")
		var edge_start := GEO.clamp_point(Vector2(bounds.position.x, bounds.get_center().y), bounds, 20.16)
		var across := GEO.move_point(edge_start, Vector2(bounds.end.x + 500, bounds.get_center().y), bounds, 20.16)
		_check(across.x > bounds.get_center().x and GEO.contains(across, bounds, 20.16), "A displacement heading into the arena leaves its starting wall and stops at the far wall.")
	_test_combat_integration()
	if failures == 0:
		print("Arena geometry tests passed: four cutouts, three arena sizes, radius clearance, deterministic obstacle routing, no tunnelling, deployment, summons and displacement.")
	quit(1 if failures else 0)

func _route(from: Vector2, goal: Vector2, bounds: Rect2) -> Array[Vector2]:
	var trace: Array[Vector2] = []
	var point := GEO.clamp_point(from, bounds, 20.16)
	goal = GEO.clamp_point(goal, bounds, 21.16)
	for step in 1200:
		var waypoint := GEO.next_waypoint(point, goal, bounds, 21.16)
		point = GEO.move_point(point, point.move_toward(waypoint, 3.0), bounds, 20.16)
		trace.append(point)
		_check(GEO.contains(point, bounds, 20.16), "Every routed movement step stays on open ground.")
		if point.distance_to(goal) < 0.1:
			break
	_check(point.distance_to(goal) < 0.1, "Routing goes around the rocks and reaches its goal instead of stopping at a corner.")
	return trace

func _test_combat_integration() -> void:
	var players: Array[CombatUnitSnapshot] = []
	for index in 12:
		var unit := CombatUnitSnapshot.new()
		unit.runtime_id = "player-%d" % index
		unit.stats.max_hp = 1000.0
		unit.stats.movement_speed = 100.0
		unit.formation_position = Vector2(0.03, 0.03) if index == 0 else Vector2(-1, -1)
		players.append(unit)
	var enemy := CombatUnitSnapshot.new()
	enemy.runtime_id = "enemy"
	enemy.team = CombatUnitSnapshot.Team.ENEMY
	var session: CombatSession = SESSION.instantiate()
	session.vfx_enabled = false
	session.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	session.size = Vector2(1748, 798)
	root.add_child(session)
	session.setup(players, [enemy], 97521)
	session.set_process(false)
	session.set_physics_process(false)
	var bounds := session.get_arena_bounds()
	for unit in session.combatants:
		unit.set_simulation_active(false)
		_check(GEO.contains(unit.position, bounds, unit.body_radius), "Automatic and legacy custom deployments start outside blocked areas.")
	var actor := session.get_combatant_by_runtime_id("player-0")
	var blocked := bounds.position + Vector2(0.02, 0.9) * bounds.size
	actor.position = blocked
	actor._refresh_body_radius()
	_check(GEO.contains(actor.position, bounds, actor.body_radius), "Resizing/revalidating a body cannot leave it in a blocked corner.")
	actor.velocity = Vector2(-2000, -2000)
	actor._slide(1.0)
	_check(GEO.contains(actor.position, bounds, actor.body_radius), "Ordinary movement uses the same wall collision.")
	var summon_point := session._summon_position(blocked, 1, bounds)
	_check(GEO.contains(summon_point, bounds, Combatant.UNIT_RADIUS), "Summons are placed on walkable ground.")
	var extra := enemy.duplicate_snapshot()
	extra.runtime_id = "reinforcement"
	var reinforcement := session._spawn_combatant(extra, blocked, bounds)
	_check(GEO.contains(reinforcement.position, bounds, reinforcement.body_radius), "Reinforcements and leap/spawn placements are projected onto open ground.")
	var entries: Array[Vector2] = []
	for index in 12:
		var entry := session._reinforcement_position(index, 12, bounds)
		_check(GEO.contains(entry, bounds, Combatant.UNIT_RADIUS), "Large reinforcement waves use the open entry lane.")
		for previous in entries:
			_check(entry.distance_to(previous) >= Combatant.UNIT_RADIUS * 2.0, "Reinforcements spread into inward columns instead of piling up at a cutout.")
		entries.append(entry)
	session.reinforcement_entry_direction = EncounterDefinition.ReinforcementEntryDirection.ALL_SIDES
	for index in 20:
		_check(GEO.contains(session._reinforcement_position(index, 20, bounds), bounds, Combatant.UNIT_RADIUS), "Surrounding reinforcements use the open section of each of the four edges.")
	for step in 120:
		actor._move_to_navigation_point(bounds.get_center(), 1.0 / 60.0)
		_check(GEO.contains(actor.position, bounds, actor.body_radius), "Combat navigation cannot steer through a blocked area.")
	var target := session.get_combatant_by_runtime_id("enemy")
	for unit in session.combatants:
		if unit != actor and unit != target:
			unit.temporarily_removed = true
	actor.position = GEO.clamp_point(bounds.position + Vector2(0.34, 0.04) * bounds.size, bounds, actor.body_radius)
	target.position = GEO.clamp_point(bounds.position + Vector2(0.03, 0.42) * bounds.size, bounds, target.body_radius)
	actor.target = target
	actor.state = Combatant.State.MOVE_INTO_RANGE
	for step in 1800:
		actor._move_toward_target(1.0 / 60.0)
		_check(GEO.contains(actor.position, bounds, actor.body_radius), "A melee approach around a ruin stays outside the blocked zone.")
		if actor.attack_committed:
			break
	_check(actor.attack_committed, "A melee fighter routes around a ruin and reaches a lateral attack position without getting stuck.")
	actor._apply_damage_knockback(target, 100000.0)
	_check(GEO.contains(actor.position, bounds, actor.body_radius), "Damage knockback respects the cutout walls.")
	session.apply_lust_basic_knockback(actor, target, 3000.0, 0.0, &"test.knockback", &"test.knockback")
	_check(GEO.contains(target.position, bounds, target.body_radius), "Ability knockback cannot push a target into the scenery.")
	actor.melee_teleport_distance = 3000.0
	actor._try_melee_teleport(target)
	_check(GEO.contains(actor.position, bounds, actor.body_radius), "Defensive teleport lands on walkable ground.")
	session.teleport_to_farthest_enemy(actor)
	_check(GEO.contains(actor.position, bounds, actor.body_radius), "An offensive teleport cannot place the attacker in a cutout.")
	session.size += Vector2(140, 80)
	var resized := session.get_arena_bounds()
	_check(actor.arena_bounds == resized and GEO.contains(actor.position, resized, actor.body_radius), "Resizing the arena updates navigation and boundary clearance together.")
	session.free()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
