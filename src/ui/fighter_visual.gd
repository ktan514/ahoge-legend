extends Control

const CombatantStateScript := preload("res://src/domain/combatant_state.gd")
const CharacterDefinitionScript := preload("res://src/domain/character_definition.gd")
const AhogePrototypeRigScript := preload("res://src/ui/ahoge_prototype_rig.gd")

@export var head_clip_horizontal_bleed: float = 180.0
@export_range(0.0, 1.0, 0.001) var ahoge_head_anchor_x_ratio: float = 0.5
@export_range(0.0, 1.0, 0.01) var ahoge_head_anchor_alpha_threshold: float = 0.5

var character
var combat_state
var facing: float = 1.0

var _head_offset := Vector2.ZERO
var _head_velocity := Vector2.ZERO
var _head_acceleration := Vector2.ZERO
var _ahoge_lag: float = 0.0
var _breath_phase: float = 0.0
var _head_rotation: float = 0.0
var _visual_action_state: int = -1
var _visual_action_age: float = 0.0

var _asset_root: Control
var _head_clip: Control
var _head_layer: Node2D
var _head_sprite: Sprite2D
var _ahoge_rig
var _asset_mode: bool = false
var _last_action_state: int = -1
var _ahoge_head_anchor_texture: Texture2D
var _ahoge_head_anchor_px: Vector2 = Vector2.ZERO
var _ahoge_head_anchor_valid: bool = false


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

	_ahoge_rig = AhogePrototypeRigScript.new()
	_ahoge_rig.name = "AhogePrototypeRig"
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
	_cache_ahoge_head_anchor()
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
	if combat_state.action_state != _visual_action_state:
		_visual_action_state = combat_state.action_state
		_visual_action_age = 0.0
	else:
		_visual_action_age += delta

	var charge_ratio := _visual_charge_ratio()
	var action_target := _prototype_head_target(charge_ratio)
	var previous_offset := _head_offset
	var previous_velocity := _head_velocity

	# 元prototypeはhead poseを直接描画し、そこから速度・加速度を算出する。
	_head_offset = action_target

	var raw_velocity := (_head_offset - previous_offset) / maxf(delta, 0.001)
	_head_velocity = _head_velocity.lerp(raw_velocity, 0.48)

	var raw_acceleration := (_head_velocity - previous_velocity) / maxf(delta, 0.001)
	_head_acceleration = _head_acceleration.lerp(raw_acceleration, 0.34)

	var charge_lean := _prototype_charge_lean(charge_ratio)
	var cooldown_lean := _prototype_cooldown_lean(charge_ratio)
	_head_rotation = rad_to_deg(
		(-facing) * (charge_lean + cooldown_lean) * 0.035
	)

	var lag_target := clampf(-_head_velocity.x * 0.10, -34.0, 34.0)
	_ahoge_lag = lerpf(_ahoge_lag, lag_target, minf(delta * 8.0, 1.0))

	if _asset_mode:
		_update_asset_pose()
		_ahoge_rig.set_motion(
			Vector2(_head_velocity.x * facing, _head_velocity.y),
			Vector2(_head_acceleration.x * facing, _head_acceleration.y),
			combat_state.action_state,
			combat_state.ahoge_available,
			charge_ratio,
			_phase_duration_for_state(combat_state.action_state, charge_ratio),
			_max_charge_duration(),
			float(combat_state.config.attack_contact_ratio) if combat_state.config != null else 0.70
		)
		_apply_action_impulse(combat_state.action_state)

	queue_redraw()


func _prototype_head_target(charge_ratio: float) -> Vector2:
	var breathe := (
		sin(_breath_phase * 2.0 + (0.0 if facing > 0.0 else 0.7)) * 4.0
		+ sin(_breath_phase * 0.8) * 1.6
	)
	var target := Vector2(0.0, breathe)

	var charge_lean := _prototype_charge_lean(charge_ratio)
	var cooldown_lean := _prototype_cooldown_lean(charge_ratio)

	target.x += -facing * 78.0 * charge_lean
	target.y += 10.0 * charge_lean

	match combat_state.action_state:
		CombatantStateScript.ActionState.WINDUP:
			var duration := _phase_duration_for_state(
				CombatantStateScript.ActionState.WINDUP,
				charge_ratio
			)
			var q := _ease_out(clampf(_visual_action_age / duration, 0.0, 1.0))
			var back_amp := 82.0 + 72.0 * charge_ratio
			target.x += -facing * back_amp * q
			target.y += (7.0 + 6.0 * charge_ratio) * q

		CombatantStateScript.ActionState.STRIKE:
			var duration := _phase_duration_for_state(
				CombatantStateScript.ActionState.STRIKE,
				charge_ratio
			)
			var u := clampf(_visual_action_age / duration, 0.0, 1.0)
			var back_amp := 82.0 + 72.0 * charge_ratio
			var forward_amp := 86.0 + 74.0 * charge_ratio

			var phase1 := 1.0 - _ease_out(clampf(u / 0.20, 0.0, 1.0))
			var phase2 := _ease_out(clampf((u - 0.12) / 0.42, 0.0, 1.0))
			var phase3 := _ease_out(clampf((u - 0.46) / 0.40, 0.0, 1.0))

			var retreat_remain := back_amp * phase1
			var forward_drive := forward_amp * 0.62 * phase2
			var final_push := forward_amp * 0.38 * phase3
			var motion := -retreat_remain + forward_drive + final_push

			target.x += facing * motion
			target.y += 4.0 * phase1
			target.y -= 8.0 * phase2
			target.y -= 5.0 * phase3

		CombatantStateScript.ActionState.PARRY:
			var duration := _phase_duration_for_state(
				CombatantStateScript.ActionState.PARRY,
				charge_ratio
			)
			var u := clampf(_visual_action_age / duration, 0.0, 1.0)
			var down := _ease_out(clampf(u / 0.18, 0.0, 1.0))
			var up := _ease_out(clampf((u - 0.10) / 0.25, 0.0, 1.0))
			var slam := _ease_out(clampf((u - 0.31) / 0.23, 0.0, 1.0))
			var settle := _ease_out(clampf((u - 0.56) / 0.34, 0.0, 1.0))

			target.y += 44.0 * down
			target.y -= 118.0 * up
			target.y += 48.0 * slam
			target.y -= 18.0 * settle
			target.x += facing * (14.0 * up - 8.0 * slam)

		CombatantStateScript.ActionState.DODGE:
			target += Vector2(-facing * 18.0, 24.0)

		CombatantStateScript.ActionState.STAGGER:
			target += Vector2(-facing * 34.0, 8.0)

	target.x += -facing * 46.0 * cooldown_lean
	target.y += 7.0 * cooldown_lean
	return target


func _prototype_charge_lean(charge_ratio: float) -> float:
	if combat_state.action_state != CombatantStateScript.ActionState.CHARGING:
		return 0.0
	var threshold := 0.18
	var pre := clampf(_visual_action_age / threshold, 0.0, 1.0)
	return clampf(0.52 * pre + 0.65 * charge_ratio, 0.0, 1.15)


func _prototype_cooldown_lean(charge_ratio: float) -> float:
	if combat_state.action_state != CombatantStateScript.ActionState.COOLDOWN:
		return 0.0
	var duration := _phase_duration_for_state(
		CombatantStateScript.ActionState.COOLDOWN,
		charge_ratio
	)
	var p := clampf(_visual_action_age / duration, 0.0, 1.0)
	return (
		pow(1.0 - p, 0.58)
		* (1.0 + sin(p * PI * 3.0) * 0.15 * (1.0 - p))
	)


func _visual_charge_ratio() -> float:
	if combat_state.action_state == CombatantStateScript.ActionState.CHARGING:
		var threshold := 0.18
		var maximum := _max_charge_duration()
		if _visual_action_age < threshold:
			return 0.0
		return clampf(
			(_visual_action_age - threshold) / maxf(maximum - threshold, 0.001),
			0.0,
			1.0
		)
	return clampf(float(combat_state.attack_charge_ratio), 0.0, 1.0)


func _phase_duration_for_state(action_state: int, charge_ratio: float) -> float:
	var config = combat_state.config
	if config == null:
		return 0.20

	match action_state:
		CombatantStateScript.ActionState.WINDUP:
			return maxf(config.attack_windup_seconds(charge_ratio), 0.001)
		CombatantStateScript.ActionState.STRIKE:
			return maxf(config.attack_strike_seconds(charge_ratio), 0.001)
		CombatantStateScript.ActionState.COOLDOWN:
			return maxf(config.attack_cooldown_seconds(charge_ratio), 0.001)
		CombatantStateScript.ActionState.PARRY:
			return maxf(float(config.parry_active_seconds), 0.001)
		CombatantStateScript.ActionState.DODGE:
			return maxf(float(config.dodge_active_seconds), 0.001)
		CombatantStateScript.ActionState.STAGGER:
			return maxf(float(config.stagger_seconds), 0.001)
	return 0.20


func _max_charge_duration() -> float:
	if combat_state.config == null:
		return 0.62
	return maxf(float(combat_state.config.max_charge_seconds), 0.001)


func _ease_out(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


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

	# 頭部の最終Transformから固定アンカーをCanvas座標へ変換し、
	# アホ毛Rigのローカル原点（根元）を毎frameそこへ一致させる。
	_bind_ahoge_root_to_head_anchor()


func _cache_ahoge_head_anchor() -> void:
	_ahoge_head_anchor_valid = false
	_ahoge_head_anchor_texture = null
	_ahoge_head_anchor_px = Vector2.ZERO
	if _head_sprite == null or _head_sprite.texture == null:
		return
	var image: Image = _head_sprite.texture.get_image()
	if image == null or image.is_empty():
		return
	if image.is_compressed() and image.decompress() != OK:
		return
	var used: Rect2i = image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return
	var ratio: float = clampf(ahoge_head_anchor_x_ratio, 0.0, 1.0)
	var x: int = clampi(
		int(round(float(used.position.x) + float(maxi(used.size.x - 1, 0)) * ratio)),
		used.position.x,
		used.end.x - 1
	)
	var found := Vector2i(-1, -1)
	var max_radius: int = mini(16, used.size.x - 1)
	for radius in range(max_radius + 1):
		var candidates: Array[int] = [x] if radius == 0 else [x - radius, x + radius]
		for candidate_x in candidates:
			if candidate_x < used.position.x or candidate_x >= used.end.x:
				continue
			for y in range(used.position.y, used.end.y):
				if image.get_pixel(candidate_x, y).a >= ahoge_head_anchor_alpha_threshold:
					found = Vector2i(candidate_x, y)
					break
			if found.x >= 0:
				break
		if found.x >= 0:
			break
	if found.x < 0:
		return
	_ahoge_head_anchor_texture = _head_sprite.texture
	_ahoge_head_anchor_px = Vector2(found)
	_ahoge_head_anchor_valid = true


func ahoge_head_anchor_texture_position() -> Vector2:
	if _head_sprite != null and (_ahoge_head_anchor_texture != _head_sprite.texture or not _ahoge_head_anchor_valid):
		_cache_ahoge_head_anchor()
	return _ahoge_head_anchor_px


func _ahoge_head_anchor_local() -> Vector2:
	if _head_sprite == null or _head_sprite.texture == null:
		return Vector2.ZERO
	if _ahoge_head_anchor_texture != _head_sprite.texture or not _ahoge_head_anchor_valid:
		_cache_ahoge_head_anchor()
	if not _ahoge_head_anchor_valid:
		return Vector2.ZERO
	return _ahoge_head_anchor_px - _head_sprite.texture.get_size() * 0.5


func ahoge_head_anchor_canvas_position() -> Vector2:
	if not _asset_mode or _head_sprite == null or _head_sprite.texture == null:
		return Vector2.ZERO
	return _head_sprite.to_global(_ahoge_head_anchor_local())


func ahoge_root_canvas_position() -> Vector2:
	if _ahoge_rig == null:
		return Vector2.ZERO
	return _ahoge_rig.to_global(Vector2.ZERO)


func _bind_ahoge_root_to_head_anchor() -> void:
	if not _asset_mode or _ahoge_rig == null or _ahoge_rig.get_parent() == null:
		return
	var target_canvas: Vector2 = ahoge_head_anchor_canvas_position()
	var parent_canvas := _ahoge_rig.get_parent() as CanvasItem
	if parent_canvas == null:
		return
	_ahoge_rig.position = parent_canvas.get_global_transform().affine_inverse() * target_canvas


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
