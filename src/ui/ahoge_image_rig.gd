extends Node2D

const CombatantStateScript := preload("res://src/domain/combatant_state.gd")

@export var display_height: float = 248.0
@export var segments: int = 22
@export var idle_amplitude: float = 7.0
@export var secondary_amplitude: float = 3.0
@export var lag_response: float = 7.5
@export var lag_scale: float = 0.075
@export var max_lag: float = 26.0
@export var tip_power: float = 1.85

var _polygon: Polygon2D
var _texture: Texture2D
var _facing: float = 1.0
var _phase: float = 0.0
var _lag: float = 0.0
var _lag_target: float = 0.0
var _action_bend: float = 0.0
var _impulse: float = 0.0
var _available: bool = true
var _display_width: float = 120.0


func _ready() -> void:
	_polygon = Polygon2D.new()
	_polygon.name = "AhogePolygon"
	add_child(_polygon)
	set_process(true)
	_refresh_mesh()


func configure(texture_value: Texture2D, facing_value: float) -> void:
	_texture = texture_value
	_facing = 1.0 if facing_value >= 0.0 else -1.0
	scale.x = _facing
	if _polygon != null:
		_polygon.texture = _texture
	_refresh_dimensions()
	_refresh_mesh()


func set_motion(relative_head_velocity_x: float, action_state: int, available: bool) -> void:
	_available = available
	visible = available
	_lag_target = clampf(
		-relative_head_velocity_x * lag_scale,
		-max_lag,
		max_lag
	)

	match action_state:
		CombatantStateScript.ActionState.CHARGING:
			_action_bend = -8.0
		CombatantStateScript.ActionState.WINDUP:
			_action_bend = -11.0
		CombatantStateScript.ActionState.STRIKE:
			_action_bend = -20.0
		CombatantStateScript.ActionState.PARRY:
			_action_bend = 9.0
		CombatantStateScript.ActionState.DODGE:
			_action_bend = 13.0
		CombatantStateScript.ActionState.STAGGER:
			_action_bend = 17.0
		_:
			_action_bend = 0.0


func kick(power: float = 1.0) -> void:
	_impulse = clampf(_impulse + power, 0.0, 1.0)


func _process(delta: float) -> void:
	if delta <= 0.0 or not _available:
		return

	_phase += delta
	_lag = lerpf(_lag, _lag_target, minf(delta * lag_response, 1.0))
	_impulse = move_toward(_impulse, 0.0, delta * 2.8)
	_refresh_mesh()


func _refresh_dimensions() -> void:
	if _texture == null:
		return
	var source_size := _texture.get_size()
	if source_size.y <= 0.0:
		return
	_display_width = display_height * source_size.x / source_size.y


func _refresh_mesh() -> void:
	if _polygon == null or _texture == null:
		return

	var safe_segments := maxi(segments, 4)
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()

	var source_size := _texture.get_size()

	for index in range(safe_segments + 1):
		var t := float(index) / float(safe_segments)
		var center := _segment_center(t)
		points.append(center + Vector2(-_display_width * 0.5, 0.0))
		uvs.append(Vector2(0.0, source_size.y * (1.0 - t)))

	for index in range(safe_segments, -1, -1):
		var t := float(index) / float(safe_segments)
		var center := _segment_center(t)
		points.append(center + Vector2(_display_width * 0.5, 0.0))
		uvs.append(Vector2(source_size.x, source_size.y * (1.0 - t)))

	_polygon.polygon = points
	_polygon.uv = uvs
	_polygon.texture = _texture


func _segment_center(t: float) -> Vector2:
	var tip_weight := pow(t, tip_power)
	var idle_wave := sin(_phase * 2.15 + t * 3.8) * idle_amplitude
	var secondary_wave := sin(_phase * 3.37 + t * 6.4) * secondary_amplitude
	var impulse_wave := sin(_phase * 8.0 + t * 4.0) * (18.0 * _impulse)
	var x := (idle_wave + secondary_wave + _lag + _action_bend + impulse_wave) * tip_weight
	var y_wave := sin(_phase * 1.55 + t * 5.0) * 2.5 * tip_weight
	return Vector2(x, -display_height * t + y_wave)
