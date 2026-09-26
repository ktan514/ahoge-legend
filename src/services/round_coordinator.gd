extends RefCounted

const RoundStateScript := preload("res://src/domain/round_state.gd")

signal overtime_started
signal round_finished(winner: int)

var config
var state


func _init(config_value, round_number: int) -> void:
	config = config_value
	state = RoundStateScript.new(round_number, config.round_seconds)


func tick(delta: float) -> void:
	if state.finished or state.overtime:
		return
	state.remaining_seconds = maxf(state.remaining_seconds - delta, 0.0)
	if state.remaining_seconds <= 0.0:
		_resolve_timeout()


func register_hit(player_index: int) -> void:
	if state.finished:
		return

	if player_index == 0:
		state.player_one_hits += 1
	elif player_index == 1:
		state.player_two_hits += 1
	else:
		return

	if state.overtime:
		_finish_round(player_index)
		return

	if player_index == 0 and state.player_one_hits >= config.hits_to_win_round:
		_finish_round(0)
	elif player_index == 1 and state.player_two_hits >= config.hits_to_win_round:
		_finish_round(1)


func _resolve_timeout() -> void:
	if state.player_one_hits > state.player_two_hits:
		_finish_round(0)
	elif state.player_two_hits > state.player_one_hits:
		_finish_round(1)
	else:
		state.overtime = true
		overtime_started.emit()


func _finish_round(winner: int) -> void:
	if state.finished:
		return
	state.finished = true
	state.winner = winner
	state.remaining_seconds = 0.0
	round_finished.emit(winner)
