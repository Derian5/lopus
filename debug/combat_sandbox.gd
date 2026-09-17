extends Control


const SPEEDS: Array[float] = [1.0, 2.0, 4.0]

@onready var combat_session: CombatSession = %CombatSession

var speed_index := 0


func _ready() -> void:
	combat_session.battle_finished.connect(_on_battle_finished)
	tree_exiting.connect(_reset_time_scale)
	_start_selected_battle()


func _on_start_button_pressed() -> void:
	_start_selected_battle()


func _on_restart_button_pressed() -> void:
	%ResultLabel.text = ""
	combat_session.restart_battle()


func _on_speed_button_pressed() -> void:
	speed_index = wrapi(speed_index + 1, 0, SPEEDS.size())
	Engine.time_scale = SPEEDS[speed_index]
	%SpeedButton.text = "SPEED x%d" % int(SPEEDS[speed_index])


func _start_selected_battle() -> void:
	%ResultLabel.text = ""
	var hero_count := int(%HeroCount.value)
	var soldier_count := int(%SoldierCount.value)
	var melee_count := int(%MeleeCount.value)
	var ranged_count := int(%RangedCount.value)
	combat_session.setup(
		CombatDemoFactory.create_player_army(hero_count, soldier_count),
		CombatDemoFactory.create_enemy_army(melee_count, ranged_count),
		1
	)


func _on_battle_finished(winner: StringName, duration: float, timed_out: bool) -> void:
	var timeout_text := " / TIME LIMIT" if timed_out else ""
	%ResultLabel.text = "%s wins in %.1f s%s" % [winner, duration, timeout_text]


func _reset_time_scale() -> void:
	Engine.time_scale = 1.0
