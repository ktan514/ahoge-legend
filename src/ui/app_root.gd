class_name AppRoot
extends Control

const TOP_MENU_SCENE := preload("res://scenes/screens/top_menu/TopMenu.tscn")
const CHARACTER_SELECT_SCENE := preload("res://scenes/screens/character_select/CharacterSelect.tscn")
const BATTLE_SCENE := preload("res://scenes/screens/battle/Battle.tscn")
const MATCH_RESULT_SCENE := preload("res://scenes/screens/result/MatchResult.tscn")

var _current_screen: Control
var _last_player_one_id: String = "LONG_TEST"
var _last_player_two_id: String = "SHORT_TEST"


func _ready() -> void:
	_show_top_menu()


func _show_top_menu() -> void:
	var screen := _replace_screen(TOP_MENU_SCENE) as TopMenu
	screen.local_test_requested.connect(_show_character_select)
	screen.exit_requested.connect(_on_exit_requested)


func _show_character_select() -> void:
	var screen := _replace_screen(CHARACTER_SELECT_SCENE) as CharacterSelect
	screen.configure(_last_player_one_id, _last_player_two_id)
	screen.battle_requested.connect(_show_battle)
	screen.back_requested.connect(_show_top_menu)


func _show_battle(player_one_id: String, player_two_id: String) -> void:
	_last_player_one_id = player_one_id
	_last_player_two_id = player_two_id

	var screen := BATTLE_SCENE.instantiate() as Battle
	screen.configure(player_one_id, player_two_id)
	_replace_screen_instance(screen)
	screen.match_completed.connect(_show_match_result)
	screen.exit_requested.connect(_show_top_menu)


func _show_match_result(summary: Dictionary) -> void:
	var screen := MATCH_RESULT_SCENE.instantiate() as MatchResult
	screen.configure(summary)
	_replace_screen_instance(screen)
	screen.rematch_requested.connect(func() -> void:
		_show_battle(_last_player_one_id, _last_player_two_id)
	)
	screen.character_select_requested.connect(_show_character_select)
	screen.top_requested.connect(_show_top_menu)


func _replace_screen(scene: PackedScene) -> Control:
	var instance := scene.instantiate() as Control
	_replace_screen_instance(instance)
	return instance


func _replace_screen_instance(instance: Control) -> void:
	if is_instance_valid(_current_screen):
		remove_child(_current_screen)
		_current_screen.queue_free()
	_current_screen = instance
	add_child(_current_screen)


func _on_exit_requested() -> void:
	get_tree().quit()
