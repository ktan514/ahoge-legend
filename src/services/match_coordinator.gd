extends RefCounted

const RoundCoordinatorScript := preload("res://src/services/round_coordinator.gd")

signal round_started(round_number: int)
signal round_finished(round_number: int, winner: int, player_one_rounds: int, player_two_rounds: int)
signal match_finished(winner: int)

var config
var round
var player_one_rounds: int = 0
var player_two_rounds: int = 0
var match_winner: int = -1


func _init(config_value) -> void:
	config = config_value
	_start_round(1)


func tick(delta: float) -> void:
	if match_winner >= 0:
		return
	round.tick(delta)


func register_hit(player_index: int) -> void:
	if match_winner >= 0:
		return
	round.register_hit(player_index)


func snapshot() -> Dictionary:
	return {
		"round_number": round.state.round_number,
		"player_one_hits": round.state.player_one_hits,
		"player_two_hits": round.state.player_two_hits,
		"remaining_seconds": round.state.remaining_seconds,
		"overtime": round.state.overtime,
		"player_one_rounds": player_one_rounds,
		"player_two_rounds": player_two_rounds,
		"match_winner": match_winner,
	}


func _start_round(round_number: int) -> void:
	round = RoundCoordinatorScript.new(config, round_number)
	round.round_finished.connect(_on_round_finished)
	round_started.emit(round_number)


func _on_round_finished(winner: int) -> void:
	var finished_round_number: int = round.state.round_number

	if winner == 0:
		player_one_rounds += 1
	else:
		player_two_rounds += 1

	round_finished.emit(
		finished_round_number,
		winner,
		player_one_rounds,
		player_two_rounds
	)

	if player_one_rounds >= config.rounds_to_win_match:
		match_winner = 0
		match_finished.emit(0)
	elif player_two_rounds >= config.rounds_to_win_match:
		match_winner = 1
		match_finished.emit(1)
	else:
		_start_round(finished_round_number + 1)
