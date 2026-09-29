extends Control

signal cancel_requested
signal match_joined(match_id: String)

var _online_session = null

var _character_id: String = "LONG_TEST"
var _rating: int = 1500
var _range_label: Label
var _elapsed_label: Label
var _status_label: Label
var _started_msec: int = 0
var _matched: bool = false


func configure(character_id: String, rating: int) -> void:
	_character_id = character_id
	_rating = rating


func _ready() -> void:
	_online_session = get_node("/root/OnlineSession")
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var root := VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.custom_minimum_size = Vector2(460.0, 0.0)
	root.add_theme_constant_override("separation", 10)
	center.add_child(root)

	var title := Label.new()
	title.text = "RANKED MATCH"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	root.add_child(title)

	var matching := Label.new()
	matching.text = "MATCHING..."
	matching.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	matching.add_theme_font_size_override("font_size", 24)
	root.add_child(matching)

	var selected := Label.new()
	selected.text = "SELECTED AHOGE: %s" % _character_id
	selected.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(selected)

	var rating_label := Label.new()
	rating_label.text = "Rating %d" % _rating
	rating_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(rating_label)

	_range_label = Label.new()
	_range_label.text = "SEARCH RANGE: ±100"
	_range_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_range_label)

	_elapsed_label = Label.new()
	_elapsed_label.text = "00:00"
	_elapsed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_elapsed_label)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_status_label)

	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.pressed.connect(_on_cancel_pressed)
	root.add_child(cancel)

	_online_session.ranked_matchmaking_range_changed.connect(_on_range_changed)
	_online_session.ranked_matchmaking_prolonged_wait.connect(_on_prolonged_wait)
	_online_session.ranked_match_joined.connect(_on_match_joined)
	_online_session.ranked_matchmaking_failed.connect(_on_matchmaking_failed)
	_started_msec = Time.get_ticks_msec()
	call_deferred("_start_matchmaking")


func _process(_delta: float) -> void:
	if _started_msec <= 0 or _matched:
		return
	var elapsed := maxi(0, int((Time.get_ticks_msec() - _started_msec) / 1000))
	_elapsed_label.text = "%02d:%02d" % [int(elapsed / 60), elapsed % 60]


func _start_matchmaking() -> void:
	var result: Dictionary = await _online_session.start_ranked_matchmaking(
		_rating,
		_character_id
	)
	if not bool(result.get("ok", false)):
		_status_label.text = str(result.get("message", "Matchmakingを開始できませんでした。"))


func _on_cancel_pressed() -> void:
	if _matched:
		return
	if _online_session.is_matchmaking():
		var result: Dictionary = await _online_session.cancel_ranked_matchmaking()
		if not bool(result.get("ok", false)):
			_status_label.text = str(result.get("message", "Matchmakingを取消できませんでした。"))
			return
	cancel_requested.emit()


func _on_range_changed(min_rating: int, max_rating: int, _elapsed_seconds: int) -> void:
	_range_label.text = "SEARCH RANGE: %d - %d" % [min_rating, max_rating]


func _on_prolonged_wait(elapsed_seconds: int, min_rating: int, max_rating: int) -> void:
	_status_label.text = "SEARCHING... %ds  (%d - %d)" % [
		elapsed_seconds,
		min_rating,
		max_rating,
	]


func _on_match_joined(match_id: String) -> void:
	if _matched:
		return
	_matched = true
	_status_label.text = "MATCH FOUND"
	match_joined.emit(match_id)


func _on_matchmaking_failed(_step: String, message: String) -> void:
	if not _matched:
		_status_label.text = message
