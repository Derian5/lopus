extends Node


const MAIN_MENU_SCENE := preload("res://ui/main_menu/main_menu.tscn")
const MANAGEMENT_SCENE := preload("res://ui/management/management.tscn")
const COMBAT_SCENE := preload("res://combat/combat.tscn")
const GAME_MENU_SCENE := preload("res://ui/game_menu/game_menu.tscn")

@onready var screen_root: Control = $ScreenRoot
@onready var overlay_layer: CanvasLayer = $OverlayLayer

var current_screen: Control
var game_menu: Control
var can_open_game_menu := false


func _ready() -> void:
	show_main_menu()


func _unhandled_input(event: InputEvent) -> void:
	if can_open_game_menu and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if is_instance_valid(game_menu):
			close_game_menu()
		else:
			open_game_menu()


func show_main_menu() -> void:
	close_game_menu()
	can_open_game_menu = false
	var screen = _replace_screen(MAIN_MENU_SCENE)
	screen.new_game_requested.connect(show_management)
	screen.quit_requested.connect(get_tree().quit)


func show_management() -> void:
	close_game_menu()
	can_open_game_menu = true
	var screen = _replace_screen(MANAGEMENT_SCENE)
	screen.combat_requested.connect(show_combat)
	screen.menu_requested.connect(open_game_menu)


func show_combat() -> void:
	close_game_menu()
	can_open_game_menu = true
	var screen = _replace_screen(COMBAT_SCENE)
	screen.management_requested.connect(show_management)
	screen.menu_requested.connect(open_game_menu)


func open_game_menu() -> void:
	if not can_open_game_menu or is_instance_valid(game_menu):
		return

	game_menu = GAME_MENU_SCENE.instantiate()
	overlay_layer.add_child(game_menu)
	game_menu.resume_requested.connect(close_game_menu)
	game_menu.main_menu_requested.connect(show_main_menu)
	game_menu.quit_requested.connect(get_tree().quit)
	get_tree().paused = true


func close_game_menu() -> void:
	get_tree().paused = false
	if is_instance_valid(game_menu):
		game_menu.queue_free()
	game_menu = null


func _replace_screen(scene: PackedScene):
	if is_instance_valid(current_screen):
		current_screen.queue_free()

	current_screen = scene.instantiate()
	screen_root.add_child(current_screen)
	return current_screen
