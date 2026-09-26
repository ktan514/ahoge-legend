class_name RoundState
extends RefCounted

var round_number: int
var player_one_hits: int = 0
var player_two_hits: int = 0
var remaining_seconds: float
var overtime: bool = false
var finished: bool = false
var winner: int = -1


func _init(round_number_value: int, round_seconds: float) -> void:
	round_number = round_number_value
	remaining_seconds = round_seconds
