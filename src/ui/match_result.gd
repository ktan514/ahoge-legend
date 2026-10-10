extends Control

const MangaThemeScript := preload("res://src/ui/theme/manga_theme.gd")
const MangaBackdropScript := preload("res://src/ui/theme/manga_backdrop.gd")
const CharacterCatalogScript := preload("res://src/domain/character_catalog.gd")

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
	var backdrop = MangaBackdropScript.new()
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_bottom", 36)
	add_child(margin)

	var center := CenterContainer.new()
	margin.add_child(center)

	var result_panel := PanelContainer.new()
	result_panel.custom_minimum_size = Vector2(760, 0)
	result_panel.add_theme_stylebox_override(
		"panel",
		MangaThemeScript.panel_style(MangaThemeScript.PAPER_0, MangaThemeScript.INK_0, 4, true)
	)
	center.add_child(result_panel)

	var root := VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 18)
	result_panel.add_child(root)

	var mode := str(_summary.get("mode", "local"))
	if mode == "ranked":
		_build_ranked_result(root)
	elif mode == "friend":
		_build_friend_result(root)
	else:
		_build_local_result(root)


func _build_result_title(root: VBoxContainer) -> void:
	var title := Label.new()
	if bool(_summary.get("is_draw", false)):
		title.text = "DRAW"
		MangaThemeScript.apply_impact_label(title, MangaThemeScript.IMPACT_YELLOW)
	elif bool(_summary.get("local_won", false)):
		title.text = "WIN!"
		MangaThemeScript.apply_impact_label(title, MangaThemeScript.IMPACT_YELLOW)
	else:
		title.text = "LOSE"
		MangaThemeScript.apply_impact_label(title, MangaThemeScript.INK_2)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var divider := HSeparator.new()
	root.add_child(divider)


func _build_ranked_result(root: VBoxContainer) -> void:
	_build_result_title(root)

	var local_user_id := str(_summary.get("local_user_id", ""))
	var scores := _score_pair(local_user_id)

	var details := Label.new()
	details.text = "%s   %d - %d   %s" % [
		_character_name(str(_summary.get("local_character_id", ""))),
		scores[0],
		scores[1],
		_character_name(str(_summary.get("opponent_character_id", ""))),
	]
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.add_theme_font_size_override("font_size", 22)
	root.add_child(details)

	var rating_panel := PanelContainer.new()
	rating_panel.add_theme_stylebox_override(
		"panel",
		MangaThemeScript.panel_style(MangaThemeScript.PAPER_1, MangaThemeScript.INK_0, 2, false)
	)
	root.add_child(rating_panel)

	var rating_box := VBoxContainer.new()
	rating_box.add_theme_constant_override("separation", 8)
	rating_panel.add_child(rating_box)

	var rating := Label.new()
	var rating_before: Dictionary = _summary.get("rating_before", {})
	var rating_after: Dictionary = _summary.get("rating_after", {})
	if not rating_after.is_empty() and not rating_before.is_empty():
		var before_value := int(rating_before.get("rating", 1500))
		var after_value := int(rating_after.get("rating", before_value))
		rating.text = "プレイヤーレート  %d → %d  (%+d)" % [
			before_value,
			after_value,
			after_value - before_value,
		]
	elif not rating_after.is_empty():
		rating.text = "プレイヤーレート  %d" % int(rating_after.get("rating", 1500))
	else:
		rating.text = "プレイヤーレートを確認できませんでした"
	rating.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rating_box.add_child(rating)

	var ahoge_rating := Label.new()
	var settlement: Dictionary = _summary.get("settlement", {})
	if bool(settlement.get("found", false)) and bool(settlement.get("ahoge_rating_available", false)):
		var ahoge_before := int(_summary.get("ahoge_rating_before", 1500))
		var ahoge_after := int(_summary.get("ahoge_rating_after", ahoge_before))
		var ahoge_delta := int(_summary.get("ahoge_rating_delta", ahoge_after - ahoge_before))
		ahoge_rating.text = "アホ毛レート  %d → %d  (%+d)" % [
			ahoge_before,
			ahoge_after,
			ahoge_delta,
		]
		if bool(settlement.get("ahoge_mirror_match", false)):
			ahoge_rating.text += "  / 同キャラ戦"
	else:
		ahoge_rating.text = "アホ毛レートを確認できませんでした"
	ahoge_rating.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rating_box.add_child(ahoge_rating)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 14)
	root.add_child(actions)

	var next_match := Button.new()
	next_match.name = "NextMatchButton"
	next_match.text = "次のランクマッチ"
	next_match.pressed.connect(func() -> void:
		next_match_requested.emit()
	)
	MangaThemeScript.apply_primary_button(next_match)
	actions.add_child(next_match)

	var character_select := Button.new()
	character_select.name = "ChangeCharacterButton"
	character_select.text = "キャラクターを変える"
	character_select.pressed.connect(func() -> void:
		character_select_requested.emit()
	)
	MangaThemeScript.apply_secondary_button(character_select)
	actions.add_child(character_select)

	var top := Button.new()
	top.name = "TopButton"
	top.text = "トップへ戻る"
	top.pressed.connect(func() -> void:
		top_requested.emit()
	)
	MangaThemeScript.apply_secondary_button(top)
	actions.add_child(top)


func _build_friend_result(root: VBoxContainer) -> void:
	_build_result_title(root)

	var local_user_id := str(_summary.get("local_user_id", ""))
	var scores := _score_pair(local_user_id)

	var details := Label.new()
	details.text = "%s   %d - %d   %s" % [
		_character_name(str(_summary.get("local_character_id", ""))),
		scores[0],
		scores[1],
		_character_name(str(_summary.get("opponent_character_id", ""))),
	]
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.add_theme_font_size_override("font_size", 22)
	root.add_child(details)

	var note := Label.new()
	note.text = "フレンド対戦 / レート変動なし"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MangaThemeScript.apply_caption(note)
	root.add_child(note)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 18)
	root.add_child(_status_label)

	_friend_host_actions = HBoxContainer.new()
	_friend_host_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_friend_host_actions.add_theme_constant_override("separation", 14)
	root.add_child(_friend_host_actions)

	var rematch := Button.new()
	rematch.name = "RematchButton"
	rematch.text = "再戦する"
	rematch.pressed.connect(func() -> void:
		rematch_requested.emit()
	)
	MangaThemeScript.apply_primary_button(rematch)
	_friend_host_actions.add_child(rematch)
	_friend_host_buttons.append(rematch)

	var character_select := Button.new()
	character_select.name = "ChangeCharacterButton"
	character_select.text = "キャラクターを選び直す"
	character_select.pressed.connect(func() -> void:
		character_select_requested.emit()
	)
	MangaThemeScript.apply_secondary_button(character_select)
	_friend_host_actions.add_child(character_select)
	_friend_host_buttons.append(character_select)

	var leave_room := Button.new()
	leave_room.name = "CloseRoomButton"
	leave_room.text = "ルームを終了"
	leave_room.pressed.connect(func() -> void:
		leave_room_requested.emit()
	)
	MangaThemeScript.apply_destructive_button(leave_room)
	_friend_host_actions.add_child(leave_room)
	_friend_host_buttons.append(leave_room)

	_friend_guest_leave = Button.new()
	_friend_guest_leave.name = "LeaveRoomButton"
	_friend_guest_leave.text = "ルームを抜ける"
	_friend_guest_leave.pressed.connect(func() -> void:
		leave_room_requested.emit()
	)
	MangaThemeScript.apply_secondary_button(_friend_guest_leave)
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
		_status_label.text = "ホストの選択を待っています…"
	elif role == "host":
		_status_label.text = "ルーム状態を確認しています…"
	else:
		_status_label.text = "ルーム状態を確認しています…"


func set_friend_result_actions_enabled(enabled: bool) -> void:
	for button in _friend_host_buttons:
		button.disabled = not enabled
	if _friend_guest_leave != null:
		_friend_guest_leave.disabled = not enabled


func set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = _humanize_status(message)


func _build_local_result(root: VBoxContainer) -> void:
	var title := Label.new()
	var winner := int(_summary.get("winner", 0))
	title.text = "1P WIN!" if winner == 0 else "2P WIN!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MangaThemeScript.apply_impact_label(title)
	root.add_child(title)

	var details := Label.new()
	details.text = "%s  %d - %d  %s" % [
		_character_name(str(_summary.get("player_one_id", "LONG_TEST"))),
		int(_summary.get("player_one_rounds", 0)),
		int(_summary.get("player_two_rounds", 0)),
		_character_name(str(_summary.get("player_two_id", "SHORT_TEST"))),
	]
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(details)

	var note := Label.new()
	note.text = "ローカルテスト / レート更新なし"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MangaThemeScript.apply_caption(note)
	root.add_child(note)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 14)
	root.add_child(actions)

	var rematch := Button.new()
	rematch.text = "再戦する"
	rematch.pressed.connect(func() -> void:
		rematch_requested.emit()
	)
	MangaThemeScript.apply_primary_button(rematch)
	actions.add_child(rematch)

	var character_select := Button.new()
	character_select.text = "キャラクターを変える"
	character_select.pressed.connect(func() -> void:
		character_select_requested.emit()
	)
	MangaThemeScript.apply_secondary_button(character_select)
	actions.add_child(character_select)

	var top := Button.new()
	top.text = "トップへ戻る"
	top.pressed.connect(func() -> void:
		top_requested.emit()
	)
	MangaThemeScript.apply_secondary_button(top)
	actions.add_child(top)


func _score_pair(local_user_id: String) -> Array[int]:
	var round_wins: Dictionary = _summary.get("round_wins_by_user", {})
	var local_score := int(round_wins.get(local_user_id, 0))
	var opponent_score := 0
	for user_id in round_wins.keys():
		if str(user_id) != local_user_id:
			opponent_score = int(round_wins.get(user_id, 0))
			break
	return [local_score, opponent_score]


func _character_name(character_id: String) -> String:
	var character = CharacterCatalogScript.get_by_id(character_id)
	if character == null:
		return character_id
	return character.display_name


func _humanize_status(message: String) -> String:
	var upper := message.to_upper()
	if upper.contains("SYNCING") or upper.contains("確認"):
		return "ルーム状態を確認しています…"
	if upper.contains("REMATCH"):
		return "再戦を準備しています…"
	if upper.contains("LOBBY"):
		return "ロビーへ戻っています…"
	if upper.contains("EXIT") or upper.contains("終了"):
		return message
	return message
