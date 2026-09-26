class_name Battle
extends Control

signal match_completed(summary: Dictionary)
signal exit_requested

@onready var hud: BattleHUD = $BattleHUD

var _player_one_id: String = "LONG_TEST"
var _player_two_id: String = "SHORT_TEST"
var _config: CombatConfig
var _match: MatchCoordinator
var _player_one_state: CombatantState
var _player_two_state: CombatantState
var _completion_emitted: bool = false


func configure(player_one_id: String, player_two_id: String) -> void:
	_player_one_id = player_one_id
	_player_two_id = player_two_id


func _ready() -> void:
	_config = CombatConfig.new()
	_match = MatchCoordinator.new(_config)
	_player_one_state = CombatantState.new(_config)
	_player_two_state = CombatantState.new(_config)

	_match.round_finished.connect(_on_round_finished)
	_match.round_started.connect(_on_round_started)
	_match.match_finished.connect(_on_match_finished)

	hud.debug_hit_requested.connect(_on_debug_hit_requested)
	hud.exit_requested.connect(func() -> void:
		exit_requested.emit()
	)

	var player_one := CharacterCatalog.get_by_id(_player_one_id)
	var player_two := CharacterCatalog.get_by_id(_player_two_id)
	hud.set_character_names(player_one.display_name, player_two.display_name)
	hud.render(_match, _player_one_state, _player_two_state)


func _process(delta: float) -> void:
	if _completion_emitted:
		return
	_player_one_state.tick(delta)
	_player_two_state.tick(delta)
	_match.tick(delta)
	hud.render(_match, _player_one_state, _player_two_state)


func _unhandled_input(event: InputEvent) -> void:
	if _completion_emitted:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_player_one_state.begin_attack()
			else:
				_player_one_state.release_attack()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_player_one_state.start_defense()

	if event is InputEventKey and not event.echo:
		if event.keycode == KEY_Q:
			if event.pressed:
				_player_two_state.begin_attack()
			else:
				_player_two_state.release_attack()
		elif event.keycode == KEY_E and event.pressed:
			_player_two_state.start_defense()
		elif event.keycode == KEY_1 and event.pressed:
			_match.register_hit(0)
		elif event.keycode == KEY_2 and event.pressed:
			_match.register_hit(1)


func _on_debug_hit_requested(player_index: int) -> void:
	_match.register_hit(player_index)


func _on_round_started(_round_number: int) -> void:
	if _player_one_state != null:
		_player_one_state.unlock_round()
	if _player_two_state != null:
		_player_two_state.unlock_round()


func _on_round_finished(round_number: int, winner: int, _p1_rounds: int, _p2_rounds: int) -> void:
	_player_one_state.lock_round()
	_player_two_state.lock_round()
	hud.flash_message("ROUND %d WINNER: P%d" % [round_number, winner + 1])


func _on_match_finished(winner: int) -> void:
	if _completion_emitted:
		return
	_completion_emitted = true

	var summary := {
		"winner": winner,
		"player_one_id": _player_one_id,
		"player_two_id": _player_two_id,
		"player_one_rounds": _match.player_one_rounds,
		"player_two_rounds": _match.player_two_rounds,
	}
	call_deferred("_emit_match_completed", summary)


func _emit_match_completed(summary: Dictionary) -> void:
	match_completed.emit(summary)
