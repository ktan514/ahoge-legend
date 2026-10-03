extends Control

const CombatantStateScript := preload("res://src/domain/combatant_state.gd")
const CharacterDefinitionScript := preload("res://src/domain/character_definition.gd")
const AhogeBoneRigScript := preload("res://src/ui/ahoge_bone_rig.gd")

@export var head_clip_horizontal_bleed: float = 180.0

var character
var combat_state
var facing: float = 1.0

var _head_offset := Vector2.ZERO
var _head_velocity := Vector2.ZERO
var _head_acceleration := Vector2.ZERO
var _ahoge_lag: float = 0.0
var _breath_phase: float = 0.0
var _head_rotation: float = 0.0

var _asset_root: Control
var _head_clip: Control
var _head_layer: Node2D
var _head_sprite: Sprite2D
var _ahoge_rig
var _asset_mode: bool = false
var _last_action_state: int = -1


func configure(character_value, combat_state_value, facing_value: float) -> void:
	character = character_value
	combat_state = combat_state_value
	facing = facing_value
	if is_inside_tree():
		_refresh_asset_mode()
	queue_redraw()


func _ready() -> void:
	clip_contents = true
	_build_asset_nodes()
	_refresh_asset_mode()
	set_process(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_head_clip_bounds()
		if _asset_mode:
			_update_asset_pose()


func _build_asset_nodes() -> void:
	_asset_root = Control.new()
	_asset_root.name = "ImageFighterRoot"
	_asset_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_asset_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_asset_root.clip_contents = false
	_asset_root.visible = false
	add_child(_asset_root)

	_head_clip = Control.new()
	_head_clip.name = "HeadClipControl"
	_head_clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_head_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_head_clip.clip_contents = true
	_asset_root.add_child(_head_clip)

	_head_layer = Node2D.new()
	_head_layer.name = "HeadLayer"
	_head_clip.add_child(_head_layer)
	_update_head_clip_bounds()

	_head_sprite = Sprite2D.new()
	_head_sprite.name = "HeadSprite"
	_head_sprite.centered = true
	_head_sprite.z_index = 0
	_head_layer.add_child(_head_sprite)

	_ahoge_rig = AhogeBoneRigScript.new()
	_ahoge_rig.name = "AhogeBoneRig"
	_ahoge_rig.z_index = 5
	_asset_root.add_child(_ahoge_rig)


func _update_head_clip_bounds() -> void:
	if _head_clip == null or _head_layer == null:
		return

	# 頭部は下端だけをcropしたい。Controlのclipは矩形なので、
	# 左右へbleedを持たせ、前後モーションでfighter列の端に見切れないようにする。
	var bleed := maxf(head_clip_horizontal_bleed, 0.0)
	_head_clip.offset_left = -bleed
	_head_clip.offset_top = 0.0
	_head_clip.offset_right = bleed
	_head_clip.offset_bottom = 0.0
	# clip領域の原点を左へ広げた分だけ座標系を戻し、既存head_centerを維持する。
	_head_layer.position = Vector2(bleed, 0.0)


func _refresh_asset_mode() -> void:
	_asset_mode = false
	clip_contents = true
	if _asset_root != null:
		_asset_root.visible = false

	if character == null or _head_sprite == null or _ahoge_rig == null:
		queue_redraw()
		return

	var head_path := str(character.head_asset_path)
	var ahoge_path := str(character.ahoge_asset_path)
	if head_path.is_empty() or ahoge_path.is_empty():
		queue_redraw()
		return
	if not ResourceLoader.exists(head_path) or not ResourceLoader.exists(ahoge_path):
		queue_redraw()
		return

	var head_texture := load(head_path) as Texture2D
	var ahoge_texture := load(ahoge_path) as Texture2D
	if head_texture == null or ahoge_texture == null:
		queue_redraw()
		return

	_head_sprite.texture = head_texture
	_ahoge_rig.configure(ahoge_texture, facing)
	_asset_root.visible = true
	_asset_mode = true
	# 画像modeではアホ毛をFighterVisual矩形でclipしない。
	# 頭部だけHeadClipControlが下端cropを担当する。
	clip_contents = false
	_update_asset_pose()
	queue_redraw()


func _process(delta: float) -> void:
	if combat_state == null or delta <= 0.0:
		return

	_breath_phase += delta

	var action_target := Vector2.ZERO
	var rotation_target := 0.0
	match combat_state.action_state:
		CombatantStateScript.ActionState.CHARGING:
			action_target.x = -facing * 28.0
			rotation_target = -2.5 * facing
		CombatantStateScript.ActionState.WINDUP:
			action_target.x = -facing * 36.0
			rotation_target = -3.5 * facing
		CombatantStateScript.ActionState.STRIKE:
			action_target.x = facing * 18.0
			rotation_target = 4.0 * facing
		CombatantStateScript.ActionState.PARRY:
			action_target.y = -22.0
			rotation_target = -2.0 * facing
		CombatantStateScript.ActionState.DODGE:
			action_target = Vector2(-facing * 18.0, 24.0)
			rotation_target = 2.5 * facing
		CombatantStateScript.ActionState.COOLDOWN:
			action_target.x = facing * 12.0
			rotation_target = 1.5 * facing
		CombatantStateScript.ActionState.STAGGER:
			action_target.x = -facing * 16.0
			rotation_target = -4.0 * facing

	var breath_scale := 1.0
	if combat_state.action_state in [
		CombatantStateScript.ActionState.CHARGING,
		CombatantStateScript.ActionState.WINDUP,
		CombatantStateScript.ActionState.STRIKE,
		CombatantStateScript.ActionState.PARRY,
		CombatantStateScript.ActionState.DODGE,
		CombatantStateScript.ActionState.STAGGER,
		CombatantStateScript.ActionState.ROUND_LOCKED,
	]:
		breath_scale = 0.0

	var breath_offset := Vector2(
		sin(_breath_phase * 1.35) * 4.0,
		sin(_breath_phase * 0.92 + 0.45) * 4.5
	) * breath_scale
	var target := action_target + breath_offset

	var previous_offset := _head_offset
	var previous_velocity := _head_velocity
	var head_response := 10.0
	if combat_state.action_state == CombatantStateScript.ActionState.STRIKE:
		head_response = 22.0
	elif combat_state.action_state == CombatantStateScript.ActionState.CHARGING:
		head_response = 8.0
	_head_offset = _head_offset.lerp(target, minf(delta * head_response, 1.0))
	_head_velocity = (_head_offset - previous_offset) / maxf(delta, 0.001)
	_head_acceleration = (_head_velocity - previous_velocity) / maxf(delta, 0.001)

	_head_rotation = lerpf(
		_head_rotation,
		rotation_target + sin(_breath_phase * 0.8) * 0.65,
		minf(delta * 8.0, 1.0)
	)

	var lag_target := clampf(-_head_velocity.x * 0.10, -34.0, 34.0)
	_ahoge_lag = lerpf(_ahoge_lag, lag_target, minf(delta * 8.0, 1.0))

	if _asset_mode:
		_update_asset_pose()
		_ahoge_rig.set_motion(
			Vector2(_head_velocity.x * facing, _head_velocity.y),
			Vector2(_head_acceleration.x * facing, _head_acceleration.y),
			combat_state.action_state,
			combat_state.ahoge_available
		)
		_apply_action_impulse(combat_state.action_state)

	queue_redraw()


func _apply_action_impulse(action_state: int) -> void:
	if action_state == _last_action_state:
		return
	_last_action_state = action_state

	match action_state:
		CombatantStateScript.ActionState.STRIKE:
			_ahoge_rig.kick(1.0)
		CombatantStateScript.ActionState.PARRY:
			_ahoge_rig.kick(0.55)
		CombatantStateScript.ActionState.DODGE:
			_ahoge_rig.kick(0.45)
		CombatantStateScript.ActionState.STAGGER:
			_ahoge_rig.kick(0.8)


func _update_asset_pose() -> void:
	if not _asset_mode or _head_sprite == null or _head_sprite.texture == null:
		return

	var texture_size := _head_sprite.texture.get_size()
	if texture_size.y <= 0.0:
		return

	var display_height := minf(410.0, maxf(330.0, size.y * 0.86))
	var head_scale := display_height / texture_size.y
	var head_center := Vector2(size.x * 0.5, size.y + 44.0) + _head_offset

	_head_sprite.position = head_center
	_head_sprite.scale = Vector2(head_scale * facing, head_scale)
	_head_sprite.rotation = deg_to_rad(_head_rotation)

	var crown_anchor := Vector2(
		head_center.x + facing * 10.0,
		head_center.y - display_height * 0.5 + 34.0
	)
	_ahoge_rig.position = crown_anchor


func _draw() -> void:
	if character == null or _asset_mode:
		return

	var head_center := Vector2(size.x * 0.5, size.y + 44.0) + _head_offset
	var head_radius := minf(122.0, maxf(92.0, size.x * 0.28))
	var hair_color := Color("#3f86ff") if facing > 0.0 else Color("#ff4f58")
	var ink := Color("#151515")
	var highlight := hair_color.lightened(0.22)

	# 顔を描かず、画面下端から頭頂部だけを見せる。
	draw_circle(head_center, head_radius + 5.0, ink)
	draw_circle(head_center, head_radius, hair_color)

	# 漫画的な髪のハイライト。目・鼻・口などの顔要素は描画しない。
	var crown_y := head_center.y - head_radius * 0.62
	draw_arc(
		head_center + Vector2(-head_radius * 0.16, -head_radius * 0.12),
		head_radius * 0.62,
		PI * 1.10,
		PI * 1.72,
		24,
		highlight,
		9.0,
		true
	)
	for index in range(4):
		var x := head_center.x - head_radius * 0.48 + float(index) * head_radius * 0.32
		draw_line(
			Vector2(x, crown_y),
			Vector2(x + facing * 12.0, crown_y - 20.0 - float(index % 2) * 10.0),
			Color(highlight.r, highlight.g, highlight.b, 0.68),
			5.0,
			true
		)

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

	draw_line(root, middle, ink, 14.0, true)
	draw_line(middle, tip, ink, 12.0, true)
	draw_line(root, middle, hair_color.lightened(0.12), 8.0, true)
	draw_line(middle, tip, hair_color.lightened(0.12), 6.0, true)
