extends Control

const FighterVisualScript := preload("res://src/ui/fighter_visual.gd")

signal exit_requested

var _header: Label
var _timer: Label
var _status: Label
var _states: Label
var _message: Label
var _player_one_name: Label
var _player_two_name: Label
var _player_one_visual
var _player_two_visual


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	_header = Label.new()
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.add_theme_font_size_override("font_size", 22)
	root.add_child(_header)

	_timer = Label.new()
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer.add_theme_font_size_override("font_size", 42)
	root.add_child(_timer)

	var battle_area := HBoxContainer.new()
	battle_area.alignment = BoxContainer.ALIGNMENT_CENTER
	battle_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battle_area.add_theme_constant_override("separation", 64)
	root.add_child(battle_area)

	var player_one_box := VBoxContainer.new()
	_player_one_name = Label.new()
	_player_one_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_one_box.add_child(_player_one_name)
	_player_one_visual = FighterVisualScript.new()
	_player_one_visual.custom_minimum_size = Vector2(360.0, 300.0)
	player_one_box.add_child(_player_one_visual)
	battle_area.add_child(player_one_box)

	var player_two_box := VBoxContainer.new()
	_player_two_name = Label.new()
	_player_two_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_two_box.add_child(_player_two_name)
	_player_two_visual = FighterVisualScript.new()
	_player_two_visual.custom_minimum_size = Vector2(360.0, 300.0)
	player_two_box.add_child(_player_two_visual)
	battle_area.add_child(player_two_box)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_status)

	_states = Label.new()
	_states.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_states)

	_message = Label.new()
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_font_size_override("font_size", 24)
	root.add_child(_message)

	var help := Label.new()
	help.text = "P1: 左クリック Attack/Charge・右クリック Parry/Dodge | P2: Q Attack/Charge・E Parry/Dodge"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(help)

	var exit := Button.new()
	exit.text = "EXIT TEST"
	exit.pressed.connect(func() -> void:
		exit_requested.emit()
	)
	root.add_child(exit)


func set_combatants(player_one_character, player_one_state, player_two_character, player_two_state) -> void:
	_player_one_name.text = player_one_character.display_name
	_player_two_name.text = player_two_character.display_name
	_player_one_visual.configure(player_one_character, player_one_state, 1.0)
	_player_two_visual.configure(player_two_character, player_two_state, -1.0)


func render(match_flow, player_one_state, player_two_state) -> void:
	var snapshot: Dictionary = match_flow.snapshot()
	var display_seconds := int(ceil(float(snapshot["remaining_seconds"])))

	_header.text = "P1  ROUNDS %d/%d  HITS %d/%d     |     P2  HITS %d/%d  ROUNDS %d/%d" % [
		int(snapshot["player_one_rounds"]),
		match_flow.config.rounds_to_win_match,
		int(snapshot["player_one_hits"]),
		match_flow.config.hits_to_win_round,
		int(snapshot["player_two_hits"]),
		match_flow.config.hits_to_win_round,
		int(snapshot["player_two_rounds"]),
		match_flow.config.rounds_to_win_match,
	]

	_timer.text = "OVERTIME" if bool(snapshot["overtime"]) else str(display_seconds)
	_status.text = "ROUND %d" % int(snapshot["round_number"])
	_states.text = "P1: %s   |   P2: %s" % [
		player_one_state.action_state_name(),
		player_two_state.action_state_name(),
	]


func flash_message(text: String) -> void:
	_message.text = text
