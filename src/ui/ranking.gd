extends Control

signal player_tab_requested
signal ahoge_tab_requested
signal back_requested

var _tab: String = "player"
var _response: Dictionary = {}
var _view_state: String = "LOADING"


func configure(tab: String, response: Dictionary) -> void:
	_tab = "ahoge" if tab == "ahoge" else "player"
	_response = response.duplicate(true)
	if is_node_ready():
		_rebuild()


func _ready() -> void:
	_rebuild()


func current_tab_name() -> String:
	return "AHOGE LEGEND" if _tab == "ahoge" else "PLAYER"


func view_state() -> String:
	return _view_state


func displayed_season_id() -> String:
	return str(_response.get("season_id", ""))


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var root := VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.custom_minimum_size = Vector2(900.0, 0.0)
	root.add_theme_constant_override("separation", 12)
	center.add_child(root)

	var title := Label.new()
	title.text = "RANKING"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	root.add_child(title)

	var season := Label.new()
	season.name = "SeasonLabel"
	season.text = _format_season(str(_response.get("season_id", "")))
	season.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(season)

	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 10)
	root.add_child(tabs)

	var player_button := Button.new()
	player_button.name = "PlayerTabButton"
	player_button.text = "PLAYER"
	player_button.disabled = _tab == "player"
	player_button.pressed.connect(func() -> void:
		player_tab_requested.emit()
	)
	tabs.add_child(player_button)

	var ahoge_button := Button.new()
	ahoge_button.name = "AhogeTabButton"
	ahoge_button.text = "AHOGE LEGEND"
	ahoge_button.disabled = _tab == "ahoge"
	ahoge_button.pressed.connect(func() -> void:
		ahoge_tab_requested.emit()
	)
	tabs.add_child(ahoge_button)

	var body := VBoxContainer.new()
	body.name = "RankingBody"
	body.custom_minimum_size = Vector2(900.0, 380.0)
	body.add_theme_constant_override("separation", 8)
	root.add_child(body)

	_render_response(body)

	var back := Button.new()
	back.text = "BACK"
	back.pressed.connect(func() -> void:
		back_requested.emit()
	)
	root.add_child(back)


func _render_response(body: VBoxContainer) -> void:
	if not bool(_response.get("ok", false)):
		_view_state = "ERROR"
		_add_status(
			body,
			"RANKING ERROR: %s" % str(_response.get("message", "server response error"))
		)
		return

	if not bool(_response.get("ranking_public", true)):
		_view_state = "FINALIZING"
		_add_status(body, "FINALIZING...")
		var publish_at := int(_response.get("ranking_hidden_until_unix_ms", 0))
		if publish_at > 0:
			var note := Label.new()
			note.text = "Final result will be published after the server closing window."
			note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			body.add_child(note)
		return

	var records = _response.get("records", [])
	if not records is Array:
		_view_state = "ERROR"
		_add_status(body, "RANKING ERROR: invalid records")
		return

	if records.is_empty():
		_view_state = "EMPTY"
		_add_status(body, "NO RANKING DATA")
		return

	_view_state = "READY"
	var header := Label.new()
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.text = (
		"RANK / PLAYER / RATING / RECORD"
		if _tab == "player"
		else "RANK / CHARACTER / AHOGE RATING / RECORD"
	)
	body.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(900.0, 340.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)

	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)

	for raw_record in records:
		if not raw_record is Dictionary:
			continue
		var record: Dictionary = raw_record
		var row := Label.new()
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.text = (
			_player_row_text(record)
			if _tab == "player"
			else _ahoge_row_text(record)
		)
		rows.add_child(row)


func _add_status(body: VBoxContainer, message: String) -> void:
	var status := Label.new()
	status.name = "RankingStatus"
	status.text = message
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 22)
	body.add_child(status)


func _player_row_text(record: Dictionary) -> String:
	var player_name := str(record.get("player_name", ""))
	if player_name.is_empty():
		player_name = str(record.get("player_id", "UNKNOWN PLAYER"))
	return "#%d  %s  RATING %d  %s  W %d / L %d / D %d" % [
		int(record.get("display_rank", 0)),
		player_name,
		int(record.get("rating", 0)),
		str(record.get("rank_tier", "")),
		int(record.get("wins", 0)),
		int(record.get("losses", 0)),
		int(record.get("draws", 0)),
	]


func _ahoge_row_text(record: Dictionary) -> String:
	var legendary := "LEGENDARY AHOGE  " if bool(record.get("legendary", false)) else ""
	return "%s#%d  %s  AHOGE RATING %d  W %d / M %d" % [
		legendary,
		int(record.get("display_rank", 0)),
		str(record.get("character_id", "")),
		int(record.get("ahoge_rating", 0)),
		int(record.get("total_match_wins", 0)),
		int(record.get("total_ranked_matches", 0)),
	]


func _format_season(season_id: String) -> String:
	if season_id.length() == 7 and season_id.substr(4, 1) == "-":
		return "SEASON  %s / %s" % [
			season_id.substr(0, 4),
			season_id.substr(5, 2),
		]
	return "SEASON  %s" % (season_id if not season_id.is_empty() else "---- / --")
