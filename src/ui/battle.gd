extends Control

const CombatConfigScript := preload("res://src/config/combat_config.gd")
const MatchCoordinatorScript := preload("res://src/services/match_coordinator.gd")
const CombatResolverScript := preload("res://src/services/combat_resolver.gd")
const CharacterCatalogScript := preload("res://src/domain/character_catalog.gd")

signal match_completed(summary: Dictionary)
signal exit_requested

@onready var hud = $BattleHUD

var _player_one_id: String = "LONG_TEST"
var _player_two_id: String = "SHORT_TEST"
var _config
var _match
var _combat
var _completion_emitted: bool = false


func configure(player_one_id: String, player_two_id: String) -> void:
	_player_one_id = player_one_id
	_player_two_id = player_two_id


func _ready() -> void:
	# Battle全体を覆うControl自身がマウス入力を消費しないようにする。
	# 操作用のButtonだけはBattleHUD側で通常のmouse_filterを維持する。
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_config = CombatConfigScript.new()
	_match = MatchCoordinatorScript.new(_config)

	var player_one = CharacterCatalogScript.get_by_id(_player_one_id)
	var player_two = CharacterCatalogScript.get_by_id(_player_two_id)
	_combat = CombatResolverScript.new(_config, _match, player_one, player_two)

	_match.round_finished.connect(_on_round_finished)
	_match.match_finished.connect(_on_match_finished)
	_combat.combat_event.connect(_on_combat_event)

	hud.exit_requested.connect(func() -> void:
		exit_requested.emit()
	)
	hud.set_combatants(
		player_one,
		_combat.get_state(0),
		player_two,
		_combat.get_state(1)
	)
	hud.render(_match, _combat.get_state(0), _combat.get_state(1))


func _process(delta: float) -> void:
	if _completion_emitted:
		return
	_combat.tick(delta)
	hud.render(_match, _combat.get_state(0), _combat.get_state(1))


func _unhandled_input(event: InputEvent) -> void:
	if _completion_emitted:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_combat.press_attack(0)
			else:
				_combat.release_attack(0)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_combat.defend(0)

	if event is InputEventKey and not event.echo:
		if event.keycode == KEY_Q:
			if event.pressed:
				_combat.press_attack(1)
			else:
				_combat.release_attack(1)
		elif event.keycode == KEY_E and event.pressed:
			_combat.defend(1)


func _on_combat_event(event_name: String, actor_index: int) -> void:
	if actor_index < 0:
		hud.flash_message(event_name)
	else:
		hud.flash_message("P%d %s" % [actor_index + 1, event_name])


func _on_round_finished(round_number: int, winner: int, _p1_rounds: int, _p2_rounds: int) -> void:
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
