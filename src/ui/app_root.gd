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
	var screen = _replace_screen(TOP_MENU_SCENE)
	screen.connect("local_test_requested", Callable(self, "_show_character_select"))
	screen.connect("exit_requested", Callable(self, "_on_exit_requested"))


func _show_character_select() -> void:
	var screen = _replace_screen(CHARACTER_SELECT_SCENE)
	screen.call("configure", _last_player_one_id, _last_player_two_id)
	screen.connect("battle_requested", Callable(self, "_show_battle"))
	screen.connect("back_requested", Callable(self, "_show_top_menu"))


func _show_battle(player_one_id: String, player_two_id: String) -> void:
	_last_player_one_id = player_one_id
	_last_player_two_id = player_two_id

	var screen = BATTLE_SCENE.instantiate()
	screen.call("configure", player_one_id, player_two_id)
	_replace_screen_instance(screen)
	screen.connect("match_completed", Callable(self, "_show_match_result"))
	screen.connect("exit_requested", Callable(self, "_show_top_menu"))


func _show_match_result(summary: Dictionary) -> void:
	var screen = MATCH_RESULT_SCENE.instantiate()
	screen.call("configure", summary)
	_replace_screen_instance(screen)
	screen.connect("rematch_requested", Callable(self, "_on_rematch_requested"))
	screen.connect("character_select_requested", Callable(self, "_show_character_select"))
	screen.connect("top_requested", Callable(self, "_show_top_menu"))


func _on_rematch_requested() -> void:
	_show_battle(_last_player_one_id, _last_player_two_id)


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
