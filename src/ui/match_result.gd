extends Control

signal rematch_requested
signal next_match_requested
signal character_select_requested
signal leave_room_requested
signal top_requested
signal friend_result_refresh_requested

const FRIEND_RESULT_REFRESH_SECONDS := 0.5

var _summary: Dictionary = {}
var _status_label: Label
var _friend_host_actions: HBoxContainer
var _friend_host_buttons: Array[Button] = []
var _friend_guest_leave: Button
var _friend_role: String = ""


func configure(summary: Dictionary) -> void:
	_summary = summary.duplicate(true)


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var root := VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.custom_minimum_size = Vector2(560.0, 0.0)
	root.add_theme_constant_override("separation", 12)
	center.add_child(root)

	var mode := str(_summary.get("mode", "local"))
	if mode == "ranked":
		_build_ranked_result(root)
	elif mode == "friend":
		_build_friend_result(root)
	else:
		_build_local_result(root)


func _build_ranked_result(root: VBoxContainer) -> void:
	var title := Label.new()
	if bool(_summary.get("is_draw", false)):
		title.text = "DRAW"
	else:
		title.text = "YOU WIN" if bool(_summary.get("local_won", false)) else "YOU LOSE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	root.add_child(title)

	var local_user_id := str(_summary.get("local_user_id", ""))
	var round_wins: Dictionary = _summary.get("round_wins_by_user", {})
	var local_score := int(round_wins.get(local_user_id, 0))
	var opponent_score := 0
	for user_id in round_wins.keys():
		if str(user_id) != local_user_id:
			opponent_score = int(round_wins.get(user_id, 0))
			break

	var details := Label.new()
	details.text = "%s  %d - %d  %s" % [
		str(_summary.get("local_character_id", "")),
		local_score,
		opponent_score,
		str(_summary.get("opponent_character_id", "")),
	]
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(details)

	var cause := Label.new()
	cause.text = "FINISH: %s" % str(_summary.get("finish_cause", ""))
	cause.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(cause)

	var rating_before: Dictionary = _summary.get("rating_before", {})
	var rating_after: Dictionary = _summary.get("rating_after", {})
	var rating := Label.new()
	if not rating_after.is_empty() and not rating_before.is_empty():
		var before_value := int(rating_before.get("rating", 1500))
		var after_value := int(rating_after.get("rating", before_value))
		var delta := after_value - before_value
		rating.text = "PLAYER RATING  %d → %d  (%+d)" % [before_value, after_value, delta]
	elif not rating_after.is_empty():
		rating.text = "PLAYER RATING  %d" % int(rating_after.get("rating", 1500))
	else:
		rating.text = "PLAYER RATING: server settlementを取得できませんでした。"
	rating.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(rating)

	var ahoge_rating := Label.new()
	var settlement: Dictionary = _summary.get("settlement", {})
	if bool(settlement.get("found", false)) and bool(settlement.get("ahoge_rating_available", false)):
		var ahoge_before := int(_summary.get("ahoge_rating_before", 1500))
		var ahoge_after := int(_summary.get("ahoge_rating_after", ahoge_before))
		var ahoge_delta := int(_summary.get("ahoge_rating_delta", ahoge_after - ahoge_before))
		ahoge_rating.text = "AHOGE RATING  %d → %d  (%+d)" % [
			ahoge_before,
			ahoge_after,
			ahoge_delta,
		]
		if bool(settlement.get("ahoge_mirror_match", false)):
			ahoge_rating.text += "  MIRROR"
	else:
		ahoge_rating.text = "AHOGE RATING: server settlementを取得できませんでした。"
	ahoge_rating.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(ahoge_rating)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	root.add_child(actions)

	var next_match := Button.new()
	next_match.text = "NEXT MATCH"
	next_match.pressed.connect(func() -> void:
		next_match_requested.emit()
	)
	actions.add_child(next_match)

	var character_select := Button.new()
	character_select.text = "CHANGE CHARACTER"
	character_select.pressed.connect(func() -> void:
		character_select_requested.emit()
	)
	actions.add_child(character_select)

	var top := Button.new()
	top.text = "EXIT"
	top.pressed.connect(func() -> void:
		top_requested.emit()
	)
	actions.add_child(top)


func _build_friend_result(root: VBoxContainer) -> void:
	var title := Label.new()
	if bool(_summary.get("is_draw", false)):
		title.text = "DRAW"
	else:
		title.text = "YOU WIN" if bool(_summary.get("local_won", false)) else "YOU LOSE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	root.add_child(title)

	var local_user_id := str(_summary.get("local_user_id", ""))
	var round_wins: Dictionary = _summary.get("round_wins_by_user", {})
	var local_score := int(round_wins.get(local_user_id, 0))
	var opponent_score := 0
	for user_id in round_wins.keys():
		if str(user_id) != local_user_id:
			opponent_score = int(round_wins.get(user_id, 0))
			break

	var details := Label.new()
	details.text = "%s  %d - %d  %s" % [
		str(_summary.get("local_character_id", "")),
		local_score,
		opponent_score,
		str(_summary.get("opponent_character_id", "")),
	]
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(details)

	var note := Label.new()
	note.text = "NO RATING CHANGE (FRIEND MATCH)"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(note)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_label)

	_friend_host_actions = HBoxContainer.new()
	_friend_host_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_friend_host_actions.add_theme_constant_override("separation", 12)
	root.add_child(_friend_host_actions)

	var rematch := Button.new()
	rematch.text = "REMATCH"
	rematch.pressed.connect(func() -> void:
		rematch_requested.emit()
	)
	_friend_host_actions.add_child(rematch)
	_friend_host_buttons.append(rematch)

	var character_select := Button.new()
	character_select.text = "CHANGE CHARACTER"
	character_select.pressed.connect(func() -> void:
		character_select_requested.emit()
	)
	_friend_host_actions.add_child(character_select)
	_friend_host_buttons.append(character_select)

	var leave_room := Button.new()
	leave_room.text = "LEAVE ROOM"
	leave_room.pressed.connect(func() -> void:
		leave_room_requested.emit()
	)
	_friend_host_actions.add_child(leave_room)
	_friend_host_buttons.append(leave_room)

	_friend_guest_leave = Button.new()
	_friend_guest_leave.text = "LEAVE ROOM"
	_friend_guest_leave.pressed.connect(func() -> void:
		leave_room_requested.emit()
	)
	root.add_child(_friend_guest_leave)

	set_friend_role(str(_summary.get("friend_role", "")))
	set_friend_result_actions_enabled(false)

	var timer := Timer.new()
	timer.wait_time = FRIEND_RESULT_REFRESH_SECONDS
	timer.one_shot = false
	timer.autostart = true
	timer.timeout.connect(func() -> void:
		friend_result_refresh_requested.emit()
	)
	add_child(timer)


func set_friend_role(role: String) -> void:
	_friend_role = role
	if _friend_host_actions != null:
		_friend_host_actions.visible = role == "host"
	if _friend_guest_leave != null:
		_friend_guest_leave.visible = role == "guest"

	if _status_label == null:
		return
	if role == "guest":
		_status_label.text = "WAITING FOR HOST..."
	elif role == "host":
		_status_label.text = "SYNCING FRIEND ROOM..."
	else:
		_status_label.text = "SYNCING FRIEND ROOM..."


func set_friend_result_actions_enabled(enabled: bool) -> void:
	for button in _friend_host_buttons:
		button.disabled = not enabled
	if _friend_guest_leave != null:
		_friend_guest_leave.disabled = not enabled


func set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message


func _build_local_result(root: VBoxContainer) -> void:
	var title := Label.new()
	var winner := int(_summary.get("winner", 0))
	title.text = "PLAYER %d WIN" % (winner + 1)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	root.add_child(title)

	var details := Label.new()
	details.text = "%s  %d - %d  %s" % [
		str(_summary.get("player_one_id", "LONG_TEST")),
		int(_summary.get("player_one_rounds", 0)),
		int(_summary.get("player_two_rounds", 0)),
		str(_summary.get("player_two_id", "SHORT_TEST")),
	]
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(details)

	var note := Label.new()
	note.text = "ローカル縦切り検証のため、Rating / Ranking更新は行いません。"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(note)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	root.add_child(actions)

	var rematch := Button.new()
	rematch.text = "REMATCH"
	rematch.pressed.connect(func() -> void:
		rematch_requested.emit()
	)
	actions.add_child(rematch)

	var character_select := Button.new()
	character_select.text = "CHANGE CHARACTER"
	character_select.pressed.connect(func() -> void:
		character_select_requested.emit()
	)
	actions.add_child(character_select)

	var top := Button.new()
	top.text = "TOP"
	top.pressed.connect(func() -> void:
		top_requested.emit()
	)
	actions.add_child(top)
