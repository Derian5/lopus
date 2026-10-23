extends SceneTree

const SESSION := preload("res://combat/combat_session.tscn")
const HERO_TRIOS := [
	[&"hero.test_vanguard", &"hero.army_support", &"hero.control_savant"],
	[&"hero.ashen_duelist", &"hero.glass_arcanist", &"hero.thorn_warden"],
	[&"hero.iron_oracle", &"hero.army_support", &"hero.control_savant"],
]
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var registry := root.get_node("ContentRegistry")
	var simulator := RunSimulator.new(self)
	for trio in HERO_TRIOS:
		for arena in [Vector2(1748, 798), Vector2(1820, 870), Vector2(1200, 700)]:
			var ids: Array[StringName] = []
			ids.assign(trio)
			var run := DemoRunFactory.create_starting_run(1, ids)
			var encounter := registry.get_definition(DemoRunFactory.FIRST_ENCOUNTER_ID) as EncounterDefinition
			var session: CombatSession = SESSION.instantiate()
			session.vfx_enabled = false
			session.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			session.size = arena
			root.add_child(session)
			session.set_process(false)
			session.set_physics_process(false)
			session.setup(
				CombatSnapshotBuilder.build_player_army(run, registry),
				CombatDemoFactory.create_enemy_army_from_encounter(encounter, CombatDemoFactory.route_enemy_power(run), 1),
				run.combat_rng.next_seed()
			)
			simulator._take_manual_control(session)
			var idle := {}
			var reported := {}
			for step in 7200:
				if not session.battle_active:
					break
				var before := {}
				for unit in session.combatants:
					before[unit.snapshot.runtime_id] = [unit.position, unit.attack_serial]
				simulator._step(session)
				for unit in session.combatants:
					var id := unit.snapshot.runtime_id
					if unit.snapshot.team != CombatUnitSnapshot.Team.ENEMY or not unit.is_alive() or unit.is_stunned() or unit.is_rooted() or unit.state != Combatant.State.MOVE_INTO_RANGE:
						idle[id] = 0.0
						continue
					var previous: Array = before[id]
					idle[id] = float(idle.get(id, 0.0)) + RunSimulator.STEP if unit.position.distance_to(previous[0]) < 0.05 and unit.attack_serial == previous[1] else 0.0
					if float(idle[id]) >= 1.0 and not reported.has(id):
						reported[id] = true
						_check(false, "Tutorial enemy %s stopped approaching for 1s without control: heroes=%s, arena=%s, time=%.2f, goal distance=%.2f, target distance=%.2f, reach=%.2f." % [id, ids, arena, session.elapsed_time, unit.position.distance_to(unit.approach_goal), unit.position.distance_to(unit.target.position), unit.basic_attack_reach(unit.target)])
			_check(not session.battle_active and not session.last_battle_timed_out, "The first tutorial encounter completes without a timeout for %s at %s." % [ids, arena])
			session.free()
	if failures == 0:
		print("Tutorial combat activity tests passed: 3 Hero trios, 3 arena sizes, no uncontrolled idle enemies or battle timeouts.")
	quit(1 if failures else 0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
