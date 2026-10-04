extends "res://src/ui/ahoge_prototype_rig.gd"

# 全体運動は既存リグをそのまま使用し、曲がりをほどく形状パラメータだけ追加する。
const DeformerScript := preload("res://src/ui/ahoge_mesh_deformer.gd")
const ProfileAsset = preload("res://assets/characters/prototype/charactor_01/ahoge_mesh_profile.tres")

@export var straighten_enabled: bool = true
@export var straighten_contact_ratio: float = 0.70
@export var recovery_seconds: float = 0.16
@export var interrupt_seconds: float = 0.10

var straighten: float = 0.0
var mesh_ready: bool = false
var fallback_reason: String = ""
var _deformer
var _straighten_clock: float = 0.0
var _transition_start: float = 0.0


func _ready() -> void:
	super._ready()
	_deformer = DeformerScript.new()
	_deformer.name = "AhogeMeshInstance"
	_motion_root.add_child(_deformer)
	_deformer.deformation_failed.connect(_on_deformation_failed)
	if _texture != null:
		configure(_texture, _facing)


func configure(texture_value: Texture2D, facing_value: float) -> void:
	super.configure(texture_value, facing_value)
	straighten = 0.0
	_straighten_clock = 0.0
	_transition_start = 0.0
	mesh_ready = false
	if _deformer == null:
		return
	mesh_ready = _deformer.setup(texture_value, ProfileAsset)
	if mesh_ready:
		fallback_reason = ""
		# 現行素材の接続点へ元Spriteもそろえ、異常時に表示位置を飛ばさない。
		_sprite.position = -ProfileAsset.root_anchor_px
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sprite.visible = not mesh_ready
	_deformer.visible = mesh_ready
	_apply_visual_transform()


func set_motion(head_velocity: Vector2, head_acceleration: Vector2,
		action_state: int, available: bool, charge_ratio: float = 0.0,
		phase_duration: float = 0.20, max_charge_duration: float = 0.60) -> void:
	if action_state != _action_state:
		_straighten_clock = 0.0
		_transition_start = straighten
	super.set_motion(head_velocity, head_acceleration, action_state, available,
		charge_ratio, phase_duration, max_charge_duration)
	if not available or action_state == CombatantStateScript.ActionState.ROUND_LOCKED:
		straighten = 0.0
		_transition_start = 0.0
		_straighten_clock = 0.0
		if mesh_ready:
			_deformer.set_straighten(0.0)


func _process(delta: float) -> void:
	if delta <= 0.0 or not _available or _texture == null:
		return
	_straighten_clock += delta
	if _action_state == CombatantStateScript.ActionState.STRIKE:
		var duration := maxf(_phase_duration * straighten_contact_ratio, 0.001)
		straighten = lerpf(_transition_start, 1.0, smoothstep(0.0, duration, _straighten_clock))
	else:
		var duration := recovery_seconds if _action_state == CombatantStateScript.ActionState.COOLDOWN else interrupt_seconds
		straighten = lerpf(_transition_start, 0.0, smoothstep(0.0, maxf(duration, 0.001), _straighten_clock))
	if not straighten_enabled:
		straighten = 0.0
	if mesh_ready:
		mesh_ready = _deformer.set_straighten(straighten)
	super._process(delta)


func _apply_visual_transform() -> void:
	super._apply_visual_transform()
	if _sprite == null:
		return
	if mesh_ready:
		_sprite.visible = false
		_deformer.visible = true


func _on_deformation_failed(reason: String) -> void:
	mesh_ready = false
	fallback_reason = reason
	if _sprite != null:
		_sprite.visible = true
	push_warning("アホ毛メッシュを元画像へ戻しました: " + reason)


func mesh_head_attachment_reference() -> Vector2:
	return ProfileAsset.head_attachment_reference


func actual_tip_local_position() -> Vector2:
	if not mesh_ready:
		return Vector2.INF
	return _motion_root.transform * _deformer.current_vertices[ProfileAsset.tip_vertex_index]


func debug_straighten() -> float:
	return straighten
