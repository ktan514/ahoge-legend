extends Control

const CharacterCatalogScript := preload("res://src/domain/character_catalog.gd")

signal completed(snapshot: Dictionary)

var _online_session = null

var _label: Label
var _completed: bool = false
var _snapshot: Dictionary = {}
var _expected_match_mode: String = "ranked"


func configure_match_mode(match_mode: String) -> void:
	_expected_match_mode = match_mode if match_mode in ["ranked", "friend"] else "ranked"


func _ready() -> void:
	_online_session = get_node("/root/OnlineSession")
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var root := VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.custom_minimum_size = Vector2(560.0, 0.0)
	root.add_theme_constant_override("separation", 18)
	center.add_child(root)

	var title := Label.new()
	title.text = "PRE-BATTLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	root.add_child(title)

	_label = Label.new()
	_label.text = "SERVER STATEを確認中..."
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_label)

	_online_session.match_snapshot_received.connect(_on_snapshot)
	if not _online_session.latest_match_snapshot.is_empty():
		call_deferred("_on_snapshot", _online_session.latest_match_snapshot.duplicate(true))


func _on_snapshot(snapshot: Dictionary) -> void:
	if _completed or str(snapshot.get("match_mode", "")) != _expected_match_mode:
		return
	_snapshot = snapshot.duplicate(true)
	var character_map: Dictionary = snapshot.get("character_id_by_user", {})
	var local_user_id := ""
	if _online_session.session != null:
		local_user_id = str(_online_session.session.user_id)
	var opponent_user_id := ""
	for user_id in character_map.keys():
		if str(user_id) != local_user_id:
			opponent_user_id = str(user_id)
			break

	var local_id := str(character_map.get(local_user_id, ""))
	var opponent_id := str(character_map.get(opponent_user_id, ""))
	var local_name := local_id
	var opponent_name := opponent_id
	var local_character = CharacterCatalogScript.get_by_id(local_id)
	var opponent_character = CharacterCatalogScript.get_by_id(opponent_id)
	if local_character != null:
		local_name = local_character.display_name
	if opponent_character != null:
		opponent_name = opponent_character.display_name

	_label.text = "%s  VS  %s\nREADY..." % [local_name, opponent_name]
	_completed = true
	call_deferred("_finish_after_minimum_display")


func _finish_after_minimum_display() -> void:
	await get_tree().create_timer(1.0).timeout
	completed.emit(_snapshot.duplicate(true))
