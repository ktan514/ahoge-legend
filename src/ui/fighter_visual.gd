extends Control

const CombatantStateScript := preload("res://src/domain/combatant_state.gd")
const CharacterDefinitionScript := preload("res://src/domain/character_definition.gd")

var character
var combat_state
var facing: float = 1.0

var _head_offset := Vector2.ZERO
var _head_velocity := Vector2.ZERO
var _ahoge_lag: float = 0.0


func configure(character_value, combat_state_value, facing_value: float) -> void:
	character = character_value
	combat_state = combat_state_value
	facing = facing_value
	queue_redraw()


func _ready() -> void:
	clip_contents = true
	set_process(true)


func _process(delta: float) -> void:
	if combat_state == null or delta <= 0.0:
		return

	var target := Vector2.ZERO
	match combat_state.action_state:
		CombatantStateScript.ActionState.CHARGING:
			target.x = -facing * 24.0
		CombatantStateScript.ActionState.WINDUP:
			target.x = -facing * 30.0
		CombatantStateScript.ActionState.STRIKE:
			target.x = facing * 34.0
		CombatantStateScript.ActionState.PARRY:
			target.y = -22.0
		CombatantStateScript.ActionState.DODGE:
			target = Vector2(-facing * 18.0, 24.0)
		CombatantStateScript.ActionState.STAGGER:
			target.x = -facing * 16.0

	var previous := _head_offset
	_head_offset = _head_offset.lerp(target, minf(delta * 12.0, 1.0))
	_head_velocity = (_head_offset - previous) / maxf(delta, 0.001)

	var lag_target := clampf(-_head_velocity.x * 0.10, -34.0, 34.0)
	_ahoge_lag = lerpf(_ahoge_lag, lag_target, minf(delta * 8.0, 1.0))
	queue_redraw()


func _draw() -> void:
	if character == null:
		return

	var head_center := Vector2(size.x * 0.5, size.y + 54.0) + _head_offset
	var head_radius := 100.0
	draw_circle(head_center, head_radius, Color(0.25, 0.25, 0.27))

	if combat_state == null or not combat_state.ahoge_available:
		return

	var root := head_center + Vector2(0.0, -head_radius + 6.0)
	var length := 102.0
	if character.ahoge_type == CharacterDefinitionScript.AhogeType.SHORT:
		length = 58.0

	var forward_extension := 0.0
	if combat_state.action_state == CombatantStateScript.ActionState.STRIKE:
		forward_extension = 62.0 if length > 60.0 else 38.0
	elif combat_state.action_state == CombatantStateScript.ActionState.CHARGING:
		forward_extension = -18.0

	var middle := root + Vector2(
		facing * (_ahoge_lag * 0.35),
		-length * 0.50
	)
	var tip := root + Vector2(
		facing * (forward_extension + _ahoge_lag),
		-length
	)

	draw_line(root, middle, Color(0.92, 0.92, 0.94), 8.0, true)
	draw_line(middle, tip, Color(0.92, 0.92, 0.94), 6.0, true)
