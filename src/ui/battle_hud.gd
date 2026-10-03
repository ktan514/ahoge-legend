extends Control

const BattleArena3DScript := preload("res://src/ui/battle_arena_3d.gd")
const MangaThemeScript := preload("res://src/ui/theme/manga_theme.gd")
const MangaBackdropScript := preload("res://src/ui/theme/manga_backdrop.gd")

signal exit_requested

var _header: Label
var _timer: Label
var _round_label: Label
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
var _player_one_score: Label
var _player_two_score: Label
var _battle_arena_3d
var _message_generation: int = 0

const IMPACT_MESSAGE_SECONDS := 0.24


func _ready() -> void:
	var backdrop = MangaBackdropScript.new()
	backdrop.configure(true)
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var scoreboard := PanelContainer.new()
	scoreboard.custom_minimum_size.y = 92
	scoreboard.add_theme_stylebox_override(
		"panel",
		MangaThemeScript.dark_panel_style(MangaThemeScript.IMPACT_YELLOW)
	)
	root.add_child(scoreboard)

	var score_row := HBoxContainer.new()
	score_row.add_theme_constant_override("separation", 12)
	scoreboard.add_child(score_row)

	var p1_box := VBoxContainer.new()
	p1_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_row.add_child(p1_box)

	_player_one_name = Label.new()
	_player_one_name.text = "P1"
	_player_one_name.add_theme_font_size_override("font_size", 20)
	_player_one_name.add_theme_color_override("font_color", MangaThemeScript.P1_BLUE)
	p1_box.add_child(_player_one_name)

	_player_one_score = Label.new()
	_player_one_score.text = "ROUND 0/2   HIT 0/5"
	_player_one_score.add_theme_font_size_override("font_size", 18)
	_player_one_score.add_theme_color_override("font_color", MangaThemeScript.WHITE)
	p1_box.add_child(_player_one_score)

	var timer_box := VBoxContainer.new()
	timer_box.custom_minimum_size.x = 180
	score_row.add_child(timer_box)

	_timer = Label.new()
	_timer.text = "85"
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer.add_theme_font_size_override("font_size", 64)
	_timer.add_theme_color_override("font_color", MangaThemeScript.IMPACT_YELLOW)
	_timer.add_theme_color_override("font_outline_color", MangaThemeScript.INK_0)
	_timer.add_theme_constant_override("outline_size", 5)
	timer_box.add_child(_timer)

	_round_label = Label.new()
	_round_label.text = "ROUND 1"
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_label.add_theme_color_override("font_color", MangaThemeScript.WHITE)
	_round_label.add_theme_font_size_override("font_size", 15)
	timer_box.add_child(_round_label)

	var p2_box := VBoxContainer.new()
	p2_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_row.add_child(p2_box)

	_player_two_name = Label.new()
	_player_two_name.text = "P2"
	_player_two_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_player_two_name.add_theme_font_size_override("font_size", 20)
	_player_two_name.add_theme_color_override("font_color", MangaThemeScript.P2_RED)
	p2_box.add_child(_player_two_name)

	_player_two_score = Label.new()
	_player_two_score.text = "HIT 0/5   ROUND 0/2"
	_player_two_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_player_two_score.add_theme_font_size_override("font_size", 18)
	_player_two_score.add_theme_color_override("font_color", MangaThemeScript.WHITE)
	p2_box.add_child(_player_two_score)

	# Compatibility field: no longer the visible scoreboard source.
	_header = Label.new()
	_header.visible = false
	root.add_child(_header)

	var arena_panel := PanelContainer.new()
	arena_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arena_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arena_panel.add_theme_stylebox_override(
		"panel",
		MangaThemeScript.panel_style(MangaThemeScript.PAPER_0, MangaThemeScript.INK_0, 4, false)
	)
	root.add_child(arena_panel)

	var arena_stack := VBoxContainer.new()
	arena_stack.add_theme_constant_override("separation", 0)
	arena_panel.add_child(arena_stack)

	var battle_caption := Label.new()
	battle_caption.text = "AHOGE BOUT"
	battle_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	battle_caption.add_theme_font_size_override("font_size", 13)
	battle_caption.add_theme_color_override("font_color", MangaThemeScript.INK_2)
	arena_stack.add_child(battle_caption)

	var battle_area := Control.new()
	battle_area.custom_minimum_size = Vector2(920, 460)
	battle_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battle_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arena_stack.add_child(battle_area)

	_battle_arena_3d = BattleArena3DScript.new()
	_battle_arena_3d.name = "BattleArena3D"
	_battle_arena_3d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_battle_arena_3d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle_area.add_child(_battle_arena_3d)

	_connection = Label.new()
	_connection.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_connection.add_theme_color_override("font_color", MangaThemeScript.WHITE)
	_connection.visible = false
	root.add_child(_connection)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", MangaThemeScript.PAPER_0)
	root.add_child(_status)

	_states = Label.new()
	_states.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_states.visible = false
	root.add_child(_states)

	_help = Label.new()
	_help.visible = false
	root.add_child(_help)

	_exit_button = Button.new()
	_exit_button.text = "テスト終了"
	_exit_button.visible = false
	_exit_button.pressed.connect(func() -> void:
		exit_requested.emit()
	)
	MangaThemeScript.apply_secondary_button(_exit_button)
	root.add_child(_exit_button)

	var effect_layer := CenterContainer.new()
	effect_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	effect_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(effect_layer)

	_message = Label.new()
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MangaThemeScript.apply_impact_label(_message)
	effect_layer.add_child(_message)

	var countdown_layer := CenterContainer.new()
	countdown_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	countdown_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(countdown_layer)

	_countdown = Label.new()
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown.add_theme_font_size_override("font_size", 72)
	_countdown.add_theme_color_override("font_color", MangaThemeScript.IMPACT_YELLOW)
	_countdown.add_theme_color_override("font_outline_color", MangaThemeScript.INK_0)
	_countdown.add_theme_constant_override("outline_size", 8)
	_countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	countdown_layer.add_child(_countdown)

	_network_overlay = Label.new()
	_network_overlay.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_network_overlay.position = Vector2(-260, 128)
	_network_overlay.size = Vector2(520, 90)
	_network_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_network_overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_network_overlay.add_theme_font_size_override("font_size", 26)
	_network_overlay.add_theme_color_override("font_color", MangaThemeScript.IMPACT_YELLOW)
	_network_overlay.add_theme_color_override("font_outline_color", MangaThemeScript.INK_0)
	_network_overlay.add_theme_constant_override("outline_size", 6)
	_network_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	countdown_layer.add_child(_network_overlay)

	_apply_mouse_passthrough(self)


func set_combatants(player_one_character, player_one_state, player_two_character, player_two_state) -> void:
	_player_one_name.text = "1P  %s" % player_one_character.display_name
	_player_two_name.text = "%s  2P" % player_two_character.display_name
	_battle_arena_3d.configure(
		player_one_character,
		player_one_state,
		player_two_character,
		player_two_state
	)


func set_connection_status(text: String) -> void:
	_connection.text = text
	var normalized := text.to_upper()
	_connection.visible = (
		normalized.contains("RECONNECT")
		or normalized.contains("WAITING")
		or normalized.contains("FAILED")
	)


func set_help_text(text: String) -> void:
	_help.text = text


func set_exit_button_text(text: String) -> void:
	_exit_button.text = text
	_exit_button.visible = not text.contains("退出不可")


func show_round_result(winner_label: String, round_number: int, p1_score: int, p2_score: int) -> void:
	_countdown.text = "ROUND %d\n%s\n%d - %d" % [
		round_number,
		winner_label,
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
	_network_overlay.text = _humanize_network_text(text)


func show_opponent_wait_countdown(remaining_seconds: int) -> void:
	_status.text = "相手の復帰を待っています…"
	_timer.text = ""
	_message.text = ""
	_network_overlay.text = "相手を待っています…\n%d" % maxi(0, remaining_seconds)


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
	var p1_rounds := int(snapshot.get("player_one_rounds", 0))
	var p2_rounds := int(snapshot.get("player_two_rounds", 0))
	var p1_hits := int(snapshot.get("player_one_hits", 0))
	var p2_hits := int(snapshot.get("player_two_hits", 0))

	_header.text = "P1 %d/%d %d/%d | P2 %d/%d %d/%d" % [
		p1_rounds,
		rounds_to_win,
		p1_hits,
		hits_to_win,
		p2_hits,
		hits_to_win,
		p2_rounds,
		rounds_to_win,
	]
	_player_one_score.text = "ROUND %d/%d   HIT %d/%d" % [
		p1_rounds,
		rounds_to_win,
		p1_hits,
		hits_to_win,
	]
	_player_two_score.text = "HIT %d/%d   ROUND %d/%d" % [
		p2_hits,
		hits_to_win,
		p2_rounds,
		rounds_to_win,
	]

	_timer.text = "OT" if bool(snapshot.get("overtime", false)) else str(display_seconds)
	_round_label.text = "ROUND %d" % int(snapshot.get("round_number", 1))
	_status.text = "MATCH FINISHED" if bool(snapshot.get("match_finished", false)) else ""
	_states.text = "P1: %s | P2: %s" % [
		player_one_state.action_state_name(),
		player_two_state.action_state_name(),
	]


func flash_message(text: String) -> void:
	_message_generation += 1
	var generation := _message_generation
	_message.text = _impact_copy(text)
	if text.is_empty():
		return
	call_deferred("_clear_message_after_delay", generation)


func _clear_message_after_delay(generation: int) -> void:
	await get_tree().create_timer(IMPACT_MESSAGE_SECONDS).timeout
	if generation == _message_generation:
		_message.text = ""


func _impact_copy(text: String) -> String:
	var upper := text.to_upper()
	if upper.contains("JUST"):
		return "JUST!"
	if upper.contains("PARRY"):
		return "PARRY!"
	if upper.contains("DODGE"):
		return "DODGE!"
	if upper.contains("CLASH"):
		return "CLASH!"
	if upper.contains("HIT"):
		return "HIT!"
	if upper.contains("STAGGER"):
		return "STAGGER!"
	if upper.contains("OVERTIME"):
		return "OVERTIME!"
	return text


func _humanize_network_text(text: String) -> String:
	var upper := text.to_upper()
	if upper.contains("RECONNECT"):
		return "再接続中…"
	if upper.contains("WAITING FOR OPPONENT"):
		return "相手を待っています…"
	if upper.contains("FAILED"):
		return "接続を復旧できませんでした"
	return text


func _apply_mouse_passthrough(control: Control) -> void:
	if not control is BaseButton:
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for child in control.get_children():
		if child is Control:
			_apply_mouse_passthrough(child)
