extends SceneTree

const MatchResumeStoreScript := preload("res://src/online/match_resume_store.gd")
const OnlineConfigScript := preload("res://src/config/online_config.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var online_session = get_root().get_node_or_null("OnlineSession")
	if online_session == null:
		_fail("OnlineSession Autoloadが見つかりません。")
		return

	online_session.clear_session()

	var auth_result: Dictionary = await online_session.authenticate_local_device()
	if not bool(auth_result.get("ok", false)):
		_fail("Device認証に失敗しました。")
		return

	var fake_match_id := "nonexistent-match-%d" % Time.get_ticks_usec()
	if not online_session.register_joined_online_match(
		fake_match_id,
		MatchResumeStoreScript.MODE_RANKED
	):
		_fail("stale lock用の保存matchを作成できませんでした。")
		return

	if online_session.can_start_new_online_match():
		_fail("stale lock作成後に新規対戦が許可されています。")
		return

	var repair: Dictionary = await online_session.repair_unresolved_match_context()
	if not bool(repair.get("ok", false)):
		_fail("stale lockの安全修復に失敗しました: %s" % str(repair.get("message", "")))
		return
	if not bool(repair.get("repaired", false)):
		_fail("stale lockが修復済みとして扱われませんでした。")
		return
	if str(repair.get("reason", "")) != "match_not_found":
		_fail("stale lock解除理由がMatch Not Foundではありません。")
		return
	if not online_session.can_start_new_online_match():
		_fail("Match Not Found確認後も新規対戦lockが残っています。")
		return
	if not online_session.get_saved_match_for_current_user().is_empty():
		_fail("Match Not Found確認後も保存match情報が残っています。")
		return

	online_session.clear_session()
	print("AHOGE LEGEND lock repair smoke: PASS")
	quit(0)


func _fail(message: String) -> void:
	var online_session = get_root().get_node_or_null("OnlineSession")
	if online_session != null:
		online_session.clear_session()
	push_error(message)
	print("AHOGE LEGEND lock repair smoke: FAIL")
	quit(1)
