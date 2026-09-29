extends SceneTree

const LEGACY_MATCH_PATH := "user://active_online_match.json"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var online_session = get_root().get_node_or_null("OnlineSession")
	if online_session == null:
		_fail("OnlineSession Autoloadが見つかりません。")
		return

	online_session.clear_session()
	_write_legacy_match_file()

	var auth_result: Dictionary = await online_session.authenticate_local_device()
	if not bool(auth_result.get("ok", false)):
		_fail("Device認証に失敗しました。")
		return

	var active: Dictionary = await online_session.refresh_active_online_match()
	if not bool(active.get("ok", false)):
		_fail("server-side active match確認に失敗しました。")
		return
	if bool(active.get("active", false)):
		_fail("fresh userに未解決server matchが存在します。")
		return
	if not online_session.can_start_new_online_match():
		_fail("legacyローカルファイルが新規対戦をblockしています。")
		return

	_remove_legacy_match_file()
	online_session.clear_session()
	print("AHOGE LEGEND lock repair smoke: PASS")
	quit(0)


func _write_legacy_match_file() -> void:
	var file := FileAccess.open(LEGACY_MATCH_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"match_id": "legacy-other-user-match",
		"match_mode": "ranked",
		"user_id": "legacy-other-user",
	}))
	file.flush()


func _remove_legacy_match_file() -> void:
	if FileAccess.file_exists(LEGACY_MATCH_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEGACY_MATCH_PATH))


func _fail(message: String) -> void:
	_remove_legacy_match_file()
	var online_session = get_root().get_node_or_null("OnlineSession")
	if online_session != null:
		online_session.clear_session()
	push_error(message)
	print("AHOGE LEGEND lock repair smoke: FAIL")
	quit(1)
