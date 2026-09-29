extends Control

const FighterVisualScript := preload("res://src/ui/fighter_visual.gd")

signal exit_requested

var _header: Label
var _timer: Label
var _status: Label
var _states: Label
var _message: Label
var _connection: Label
var _countdown: Label
var _network_overlay: Label
var _help: Label
var _exit_button: Button
var _player_one_name: Label
var _player_two_name: Label
var _player_one_visual
var _player_two_visual


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	_connection = Label.new()
	_connection.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_connection.text = "LOCAL"
	root.add_child(_connection)

	_header = Label.new()
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.add_theme_font_size_override("font_size", 18)
	root.add_child(_header)

	_timer = Label.new()
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer.add_theme_font_size_override("font_size", 38)
	root.add_child(_timer)

	var arena_center := CenterContainer.new()
	arena_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(arena_center)

	var arena_panel := PanelContainer.new()
	# 550:440 = 5:4。M1 Human Verification用の候補値であり最終確定ではない。
	arena_panel.custom_minimum_size = Vector2(550.0, 440.0)
	arena_center.add_child(arena_panel)

	var battle_area := HBoxContainer.new()
	battle_area.alignment = BoxContainer.ALIGNMENT_CENTER
	battle_area.add_theme_constant_override("separation", 20)
	arena_panel.add_child(battle_area)

	var player_one_box := VBoxContainer.new()
	_player_one_name = Label.new()
	_player_one_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_one_box.add_child(_player_one_name)
	_player_one_visual = FighterVisualScript.new()
	_player_one_visual.custom_minimum_size = Vector2(250.0, 380.0)
	player_one_box.add_child(_player_one_visual)
	battle_area.add_child(player_one_box)

	var player_two_box := VBoxContainer.new()
	_player_two_name = Label.new()
	_player_two_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_two_box.add_child(_player_two_name)
	_player_two_visual = FighterVisualScript.new()
	_player_two_visual.custom_minimum_size = Vector2(250.0, 380.0)
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
	_message.add_theme_font_size_override("font_size", 20)
	root.add_child(_message)

	_help = Label.new()
	_help.text = "P1: 左クリック Attack/Charge・右クリック Parry/Dodge | P2: Q Attack/Charge・E Parry/Dodge"
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_help)

	_exit_button = Button.new()
	_exit_button.text = "EXIT TEST"
	_exit_button.pressed.connect(func() -> void:
		exit_requested.emit()
	)
	root.add_child(_exit_button)

	var countdown_layer := CenterContainer.new()
	countdown_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	countdown_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(countdown_layer)

	_countdown = Label.new()
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown.add_theme_font_size_override("font_size", 72)
	_countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	countdown_layer.add_child(_countdown)

	_network_overlay = Label.new()
	_network_overlay.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_network_overlay.position = Vector2(-260.0, 120.0)
	_network_overlay.size = Vector2(520.0, 100.0)
	_network_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_network_overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_network_overlay.add_theme_font_size_override("font_size", 32)
	_network_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	countdown_layer.add_child(_network_overlay)

	# HUDは画面全体を覆うため、そのままだとControl群がマウスイベントを消費して
	# Battle._input()へ届かない。操作ボタン以外は入力を透過する。
	_apply_mouse_passthrough(self)


func set_combatants(player_one_character, player_one_state, player_two_character, player_two_state) -> void:
	_player_one_name.text = player_one_character.display_name
	_player_two_name.text = player_two_character.display_name
	_player_one_visual.configure(player_one_character, player_one_state, 1.0)
	_player_two_visual.configure(player_two_character, player_two_state, -1.0)


func set_connection_status(text: String) -> void:
	_connection.text = text


func set_help_text(text: String) -> void:
	if _help != null:
		_help.text = text


func set_exit_button_text(text: String) -> void:
	if _exit_button != null:
		_exit_button.text = text


func show_round_result(winner_label: String, round_number: int, p1_score: int, p2_score: int) -> void:
	_countdown.text = "%s TAKES ROUND %d\nSCORE %d - %d" % [
		winner_label,
		round_number,
		p1_score,
		p2_score,
	]


func show_round_countdown(round_number: int, countdown_value: int) -> void:
	if countdown_value > 0:
		_countdown.text = "ROUND %d\n%d" % [round_number, countdown_value]
	else:
		_countdown.text = "GO!"


func clear_round_countdown() -> void:
	_countdown.text = ""


func show_network_overlay(text: String) -> void:
	_network_overlay.text = text


func show_opponent_wait_countdown(remaining_seconds: int) -> void:
	_status.text = "NEXT ROUND: WAITING FOR OPPONENT"
	_timer.text = ""
	_message.text = ""
	_network_overlay.text = "WAITING FOR OPPONENT...\n%d" % maxi(0, remaining_seconds)


func clear_network_overlay() -> void:
	_network_overlay.text = ""


func render(match_flow, player_one_state, player_two_state) -> void:
	var snapshot: Dictionary = match_flow.snapshot()
	_render_snapshot(
		snapshot,
		match_flow.config.rounds_to_win_match,
		match_flow.config.hits_to_win_round,
		player_one_state,
		player_two_state
	)


func render_authoritative(snapshot: Dictionary, player_one_state, player_two_state) -> void:
	_render_snapshot(snapshot, 2, 5, player_one_state, player_two_state)


func _render_snapshot(
	snapshot: Dictionary,
	rounds_to_win: int,
	hits_to_win: int,
	player_one_state,
	player_two_state
) -> void:
	var display_seconds := int(snapshot.get("remaining_seconds", 85))

	_header.text = "P1  ROUNDS %d/%d  HITS %d/%d     |     P2  HITS %d/%d  ROUNDS %d/%d" % [
		int(snapshot.get("player_one_rounds", 0)),
		rounds_to_win,
		int(snapshot.get("player_one_hits", 0)),
		hits_to_win,
		int(snapshot.get("player_two_hits", 0)),
		hits_to_win,
		int(snapshot.get("player_two_rounds", 0)),
		rounds_to_win,
	]

	_timer.text = "OVERTIME" if bool(snapshot.get("overtime", false)) else str(display_seconds)
	var match_suffix := "  MATCH FINISHED" if bool(snapshot.get("match_finished", false)) else ""
	_status.text = "ROUND %d%s" % [int(snapshot.get("round_number", 1)), match_suffix]
	_states.text = "P1: %s   |   P2: %s" % [
		player_one_state.action_state_name(),
		player_two_state.action_state_name(),
	]


func flash_message(text: String) -> void:
	_message.text = text


func _apply_mouse_passthrough(control: Control) -> void:
	if not control is BaseButton:
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for child in control.get_children():
		if child is Control:
			_apply_mouse_passthrough(child)
