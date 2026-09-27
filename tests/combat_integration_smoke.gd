extends SceneTree

const OnlineConfigScript := preload("res://src/config/online_config.gd")
const CombatInputProtocolScript := preload("res://src/online/combat_input_protocol.gd")

var _second_socket = null
var _second_ticket: String = ""
var _second_match_id: String = ""
var _second_failure: String = ""
var _second_sequence: int = 0

var _p1_states: Array[Dictionary] = []
var _p2_states: Array[Dictionary] = []
var _p1_defense: Array[Dictionary] = []
var _p2_defense: Array[Dictionary] = []
var _p1_contacts: Array[Dictionary] = []
var _p2_contacts: Array[Dictionary] = []
var _p1_hits: Array[Dictionary] = []
var _p2_hits: Array[Dictionary] = []
var _p1_clashes: Array[Dictionary] = []
var _p2_clashes: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var online_session = get_root().get_node_or_null("OnlineSession")
	var nakama = get_root().get_node_or_null("Nakama")
	if online_session == null or nakama == null:
		_fail("OnlineSession / Nakama Autoloadが見つかりません。")
		return

	var auth_result: Dictionary = await online_session.authenticate_local_device()
	if not bool(auth_result.get("ok", false)):
		_fail("P1 Device認証に失敗しました。")
		return
	var p1_user_id := str(auth_result.get("user_id", ""))

	var realtime_result: Dictionary = await online_session.connect_realtime_socket()
	if not bool(realtime_result.get("ok", false)):
		_fail("P1 Realtime Socket接続に失敗しました。")
		return
	online_session.realtime_socket.received_match_state.connect(_on_first_match_state)

	var second_client = nakama.create_client(
		OnlineConfigScript.SERVER_KEY,
		OnlineConfigScript.HOST,
		OnlineConfigScript.PORT,
		OnlineConfigScript.SCHEME,
		OnlineConfigScript.CLIENT_TIMEOUT_SECONDS,
		OnlineConfigScript.CLIENT_LOG_LEVEL
	)
	var second_device_id := Crypto.new().generate_random_bytes(32).hex_encode()
	var second_session = await second_client.authenticate_device_async(second_device_id, null, true)
	if second_session == null or second_session.is_exception():
		_fail("P2 Device認証に失敗しました。")
		return
	var p2_user_id := str(second_session.user_id)

	_second_socket = nakama.create_socket_from(second_client)
	_second_socket.received_matchmaker_matched.connect(_on_second_matchmaker_matched)
	_second_socket.received_match_state.connect(_on_second_match_state)
	var second_connect = await _second_socket.connect_async(
		second_session,
		OnlineConfigScript.SOCKET_APPEAR_ONLINE,
		OnlineConfigScript.SOCKET_CONNECT_TIMEOUT_SECONDS
	)
	if second_connect == null or second_connect.is_exception():
		_fail("P2 Realtime Socket接続に失敗しました。")
		return

	var p1_joined := [""]
	online_session.ranked_match_joined.connect(func(match_id: String) -> void:
		p1_joined[0] = match_id
	)

	var p1_start: Dictionary = await online_session.start_ranked_matchmaking(
		1500,
		OnlineConfigScript.RANKED_CHARACTER_LONG_TEST
	)
	if not bool(p1_start.get("ok", false)):
		_fail("P1 LONG_TESTでRanked Matchmakerを開始できませんでした。")
		return

	var query: String = online_session.build_ranked_matchmaker_query(1500)
	var second_ticket_result = await _second_socket.add_matchmaker_async(
		query,
		OnlineConfigScript.RANKED_MATCHMAKER_MIN_COUNT,
		OnlineConfigScript.RANKED_MATCHMAKER_MAX_COUNT,
		{
			"mode": OnlineConfigScript.RANKED_MATCHMAKER_MODE,
			"character_id": OnlineConfigScript.RANKED_CHARACTER_SHORT_TEST,
		},
		{"rating": 1500.0}
	)
	if second_ticket_result == null or second_ticket_result.is_exception():
		_fail("P2 SHORT_TESTでRanked Matchmakerを開始できませんでした。")
		return
	_second_ticket = str(second_ticket_result.ticket)

	var join_deadline := Time.get_ticks_msec() + 40000
	while Time.get_ticks_msec() < join_deadline:
		if not _second_failure.is_empty():
			_fail(_second_failure)
			return
		if not p1_joined[0].is_empty() and not _second_match_id.is_empty():
			break
		await create_timer(0.1).timeout

	if p1_joined[0].is_empty() or _second_match_id.is_empty():
		_fail("2クライアントがauthoritative matchへjoinできませんでした。")
		return
	if p1_joined[0] != _second_match_id:
		_fail("P1とP2のmatch IDが一致しません。")
		return

	# authoritative Round Countdown完了後に戦闘を開始する。
	await create_timer(3.5).timeout

	# 1. LONG_TEST通常Hit。
	var hit_start := _p1_states.size()
	var hit_sequence := await _start_p1_attack(online_session, p1_user_id, 0.0)
	if hit_sequence <= 0:
		return
	var hit_a := await _wait_event_by_sequence(_p1_hits, hit_sequence, 5000)
	var hit_b := await _wait_event_by_sequence(_p2_hits, hit_sequence, 5000)
	if not _assert_event_pair(hit_a, hit_b, "通常Hit"):
		return
	if not await _wait_for_state_pair(p1_user_id, "IDLE", hit_start, hit_start, 5000):
		_fail("通常Hit後にP1がIDLEへ復帰しませんでした。")
		return

	# 2. 攻撃中DEFENDでAttack cancel。
	var cancel_state_start_p1 := _p1_states.size()
	var cancel_state_start_p2 := _p2_states.size()
	var contact_count_before := _p1_contacts.size()
	var cancel_press: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_PRESS
	)
	if not bool(cancel_press.get("ok", false)):
		_fail("cancel検証用ATTACK_PRESSを送信できませんでした。")
		return
	if not await _wait_for_state_pair(
		p1_user_id,
		"CHARGING",
		cancel_state_start_p1,
		cancel_state_start_p2,
		5000
	):
		_fail("cancel検証でCHARGINGへ遷移しませんでした。")
		return
	var cancel_defend: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_DEFEND
	)
	if not bool(cancel_defend.get("ok", false)):
		_fail("cancel検証用DEFENDを送信できませんでした。")
		return
	if not await _wait_for_state_pair(
		p1_user_id,
		"PARRY",
		cancel_state_start_p1,
		cancel_state_start_p2,
		5000
	):
		_fail("攻撃中DEFENDでPARRYへ遷移しませんでした。")
		return
	if not await _wait_for_state_pair(
		p1_user_id,
		"IDLE",
		cancel_state_start_p1,
		cancel_state_start_p2,
		5000
	):
		_fail("Attack cancel後にIDLEへ復帰しませんでした。")
		return
	await create_timer(0.25).timeout
	if _p1_contacts.size() != contact_count_before or _p2_contacts.size() != contact_count_before:
		_fail("Attack cancel後に不要なContactEventが発生しました。")
		return

	# 3. 通常PARRYでHit抑止。
	var parry_start_p1 := _p1_states.size()
	var parry_start_p2 := _p2_states.size()
	var parry_sequence := await _start_p1_attack(online_session, p1_user_id, 0.0)
	if parry_sequence <= 0:
		return
	if not await _send_p2(CombatInputProtocolScript.ACTION_DEFEND):
		return
	if not await _wait_for_state_pair(
		p2_user_id,
		"PARRY",
		parry_start_p1,
		parry_start_p2,
		5000
	):
		_fail("通常PARRY状態を両clientで確認できませんでした。")
		return
	if not await _assert_defense_pair(parry_sequence, "PARRY", 5000):
		return
	await create_timer(0.25).timeout
	if _has_sequence(_p1_hits, parry_sequence) or _has_sequence(_p2_hits, parry_sequence):
		_fail("PARRY成立攻撃でHitが発生しました。")
		return
	if not await _wait_for_state_pair(
		p1_user_id,
		"IDLE",
		parry_start_p1,
		parry_start_p2,
		5000
	):
		_fail("PARRY検証後にP1がIDLEへ復帰しませんでした。")
		return
	if not await _wait_for_state_pair(
		p2_user_id,
		"IDLE",
		parry_start_p1,
		parry_start_p2,
		5000
	):
		_fail("PARRY検証後にP2がIDLEへ復帰しませんでした。")
		return

	# 4. JUST_PARRY → 攻撃側STAGGER。
	var just_start_p1 := _p1_states.size()
	var just_start_p2 := _p2_states.size()
	var just_sequence := await _start_p1_attack(online_session, p1_user_id, 0.65)
	if just_sequence <= 0:
		return
	if not await _send_p2(CombatInputProtocolScript.ACTION_DEFEND):
		return
	if not await _assert_defense_pair(just_sequence, "JUST_PARRY", 5000):
		return
	var just_stagger := await _wait_for_state_pair_event(
		p1_user_id,
		"STAGGER",
		just_start_p1,
		just_start_p2,
		5000
	)
	if just_stagger.is_empty():
		_fail("JUST_PARRY後に攻撃側STAGGERを確認できませんでした。")
		return
	if not _assert_stagger_ticks(just_stagger, "JUST_PARRY"):
		return
	if not await _wait_for_state_pair(
		p1_user_id,
		"IDLE",
		just_start_p1,
		just_start_p2,
		5000
	):
		_fail("JUST_PARRY Stagger後にP1がIDLEへ復帰しませんでした。")
		return
	if not await _wait_for_state_pair(
		p2_user_id,
		"IDLE",
		just_start_p1,
		just_start_p2,
		5000
	):
		_fail("JUST_PARRY後にP2がIDLEへ復帰しませんでした。")
		return

	# 5. AttackClash → 両者STAGGER。
	var clash_state_start_p1 := _p1_states.size()
	var clash_state_start_p2 := _p2_states.size()
	var clash_event_start_p1 := _p1_clashes.size()
	var clash_event_start_p2 := _p2_clashes.size()

	var p1_clash_press: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_PRESS
	)
	if not bool(p1_clash_press.get("ok", false)):
		_fail("Clash用P1 ATTACK_PRESSを送信できませんでした。")
		return
	if not await _send_p2(CombatInputProtocolScript.ACTION_ATTACK_PRESS):
		return
	if not await _wait_for_state_pair(
		p1_user_id,
		"CHARGING",
		clash_state_start_p1,
		clash_state_start_p2,
		5000
	):
		_fail("Clash用P1 CHARGINGを確認できませんでした。")
		return
	if not await _wait_for_state_pair(
		p2_user_id,
		"CHARGING",
		clash_state_start_p1,
		clash_state_start_p2,
		5000
	):
		_fail("Clash用P2 CHARGINGを確認できませんでした。")
		return

	var p1_clash_release: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_RELEASE
	)
	if not bool(p1_clash_release.get("ok", false)):
		_fail("Clash用P1 ATTACK_RELEASEを送信できませんでした。")
		return
	var p1_clash_sequence := int(p1_clash_release.get("input_sequence", 0))
	if not await _send_p2(CombatInputProtocolScript.ACTION_ATTACK_RELEASE):
		return
	var p2_clash_sequence := _second_sequence

	var p2_short_strike := await _wait_for_state_pair_event(
		p2_user_id,
		"STRIKE",
		clash_state_start_p1,
		clash_state_start_p2,
		5000
	)
	if p2_short_strike.is_empty():
		_fail("Clash中のSHORT STRIKEを確認できませんでした。")
		return
	if bool(p2_short_strike.get("ahoge_available", true)):
		_fail("Clash中のSHORT_TESTがdetachしていません。")
		return
	var clash_regrow_tick := int(p2_short_strike.get("regrow_until_tick", -1))

	var clash_a := await _wait_new_event(_p1_clashes, clash_event_start_p1, 5000)
	var clash_b := await _wait_new_event(_p2_clashes, clash_event_start_p2, 5000)
	if not _assert_event_pair(clash_a, clash_b, "AttackClash"):
		return
	if _has_sequence(_p1_hits, p1_clash_sequence) 			or _has_sequence(_p1_hits, p2_clash_sequence):
		_fail("AttackClashでHitが発生しました。")
		return

	var clash_p1_stagger := await _wait_for_state_pair_event(
		p1_user_id,
		"STAGGER",
		clash_state_start_p1,
		clash_state_start_p2,
		5000
	)
	var clash_p2_stagger := await _wait_for_state_pair_event(
		p2_user_id,
		"STAGGER",
		clash_state_start_p1,
		clash_state_start_p2,
		5000
	)
	if clash_p1_stagger.is_empty() or clash_p2_stagger.is_empty():
		_fail("AttackClash後の両者STAGGERを確認できませんでした。")
		return
	if not _assert_stagger_ticks(clash_p1_stagger, "Clash P1") 			or not _assert_stagger_ticks(clash_p2_stagger, "Clash P2"):
		return
	if not await _wait_for_state_pair(
		p1_user_id,
		"IDLE",
		clash_state_start_p1,
		clash_state_start_p2,
		5000
	):
		_fail("Clash後にP1がIDLEへ復帰しませんでした。")
		return
	if not await _wait_for_state_pair(
		p2_user_id,
		"IDLE",
		clash_state_start_p1,
		clash_state_start_p2,
		5000
	):
		_fail("Clash後にP2がIDLEへ復帰しませんでした。")
		return
	if not await _wait_for_availability_pair(p2_user_id, true, clash_regrow_tick, 5000):
		_fail("Clash後にSHORT_TESTがRegrowしませんでした。")
		return

	# 6. SHORT detach中の通常DODGE。
	var dodge_cycle_start_p1 := _p1_states.size()
	var dodge_cycle_start_p2 := _p2_states.size()
	var short_attack := await _start_p2_attack(p2_user_id, 0.0)
	if short_attack.is_empty():
		return
	var short_strike: Dictionary = short_attack["strike"]
	if bool(short_strike.get("ahoge_available", true)):
		_fail("通常DODGE検証用SHORT attackがdetachしていません。")
		return
	var dodge_regrow_tick := int(short_strike.get("regrow_until_tick", -1))

	var dodge_incoming_sequence := await _start_p1_attack(online_session, p1_user_id, 0.0)
	if dodge_incoming_sequence <= 0:
		return
	if not await _send_p2(CombatInputProtocolScript.ACTION_DEFEND):
		return
	if not await _wait_for_state_pair(
		p2_user_id,
		"DODGE",
		dodge_cycle_start_p1,
		dodge_cycle_start_p2,
		5000
	):
		_fail("detach中DEFENDがDODGEへ遷移しませんでした。")
		return
	if not await _assert_defense_pair(dodge_incoming_sequence, "DODGE", 5000):
		return
	if not await _wait_for_availability_pair(p2_user_id, true, dodge_regrow_tick, 5000):
		_fail("通常DODGE検証後にSHORT_TESTがRegrowしませんでした。")
		return
	if not await _wait_for_state_pair(
		p1_user_id,
		"IDLE",
		dodge_cycle_start_p1,
		dodge_cycle_start_p2,
		5000
	):
		_fail("通常DODGE検証後にP1がIDLEへ復帰しませんでした。")
		return
	if not await _wait_for_state_pair(
		p2_user_id,
		"IDLE",
		dodge_cycle_start_p1,
		dodge_cycle_start_p2,
		5000
	):
		_fail("通常DODGE検証後にP2がIDLEへ復帰しませんでした。")
		return

	# 7. SHORT detach中のJUST_DODGE → 攻撃側STAGGER。
	var just_dodge_start_p1 := _p1_states.size()
	var just_dodge_start_p2 := _p2_states.size()
	var p1_charge_press: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_PRESS
	)
	if not bool(p1_charge_press.get("ok", false)):
		_fail("JUST_DODGE用P1 ATTACK_PRESSを送信できませんでした。")
		return
	if not await _wait_for_state_pair(
		p1_user_id,
		"CHARGING",
		just_dodge_start_p1,
		just_dodge_start_p2,
		5000
	):
		_fail("JUST_DODGE用P1 CHARGINGを確認できませんでした。")
		return

	await create_timer(0.42).timeout
	var short_just_attack := await _start_p2_attack(p2_user_id, 0.0)
	if short_just_attack.is_empty():
		return
	var short_just_strike: Dictionary = short_just_attack["strike"]
	if bool(short_just_strike.get("ahoge_available", true)):
		_fail("JUST_DODGE用SHORT attackがdetachしていません。")
		return
	var just_dodge_regrow_tick := int(short_just_strike.get("regrow_until_tick", -1))

	var p1_charge_release: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_RELEASE
	)
	if not bool(p1_charge_release.get("ok", false)):
		_fail("JUST_DODGE用P1 ATTACK_RELEASEを送信できませんでした。")
		return
	var just_dodge_sequence := int(p1_charge_release.get("input_sequence", 0))
	if not await _wait_for_state_pair(
		p1_user_id,
		"STRIKE",
		just_dodge_start_p1,
		just_dodge_start_p2,
		5000
	):
		_fail("JUST_DODGE用P1 STRIKEを確認できませんでした。")
		return

	if not await _send_p2(CombatInputProtocolScript.ACTION_DEFEND):
		return
	if not await _wait_for_state_pair(
		p2_user_id,
		"DODGE",
		just_dodge_start_p1,
		just_dodge_start_p2,
		5000
	):
		_fail("JUST_DODGE用DODGE状態を確認できませんでした。")
		return
	if not await _assert_defense_pair(just_dodge_sequence, "JUST_DODGE", 5000):
		return

	var just_dodge_stagger := await _wait_for_state_pair_event(
		p1_user_id,
		"STAGGER",
		just_dodge_start_p1,
		just_dodge_start_p2,
		5000
	)
	if just_dodge_stagger.is_empty():
		_fail("JUST_DODGE後に攻撃側STAGGERを確認できませんでした。")
		return
	if not _assert_stagger_ticks(just_dodge_stagger, "JUST_DODGE"):
		return

	if not await _wait_for_availability_pair(
		p2_user_id,
		true,
		just_dodge_regrow_tick,
		5000
	):
		_fail("JUST_DODGE後にSHORT_TESTがRegrowしませんでした。")
		return
	if not await _wait_for_state_pair(
		p1_user_id,
		"IDLE",
		just_dodge_start_p1,
		just_dodge_start_p2,
		5000
	):
		_fail("JUST_DODGE Stagger後にP1がIDLEへ復帰しませんでした。")
		return
	if not await _wait_for_state_pair(
		p2_user_id,
		"IDLE",
		just_dodge_start_p1,
		just_dodge_start_p2,
		5000
	):
		_fail("JUST_DODGE後にP2がIDLEへ復帰しませんでした。")
		return

	# 8. Regrow後はPARRYへ戻る。
	var regrow_parry_start_p1 := _p1_states.size()
	var regrow_parry_start_p2 := _p2_states.size()
	if not await _send_p2(CombatInputProtocolScript.ACTION_DEFEND):
		return
	if not await _wait_for_state_pair(
		p2_user_id,
		"PARRY",
		regrow_parry_start_p1,
		regrow_parry_start_p2,
		5000
	):
		_fail("Regrow後DEFENDがPARRYへ戻りませんでした。")
		return
	if not await _wait_for_state_pair(
		p2_user_id,
		"IDLE",
		regrow_parry_start_p1,
		regrow_parry_start_p2,
		5000
	):
		_fail("Regrow後PARRYからIDLEへ復帰しませんでした。")
		return

	# 9. 最後に両者が新しい入力を受理でき、cancel後IDLEへ戻る。
	var final_start_p1 := _p1_states.size()
	var final_start_p2 := _p2_states.size()
	var final_p1_press: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_PRESS
	)
	if not bool(final_p1_press.get("ok", false)):
		_fail("最終P1 ATTACK_PRESSを送信できませんでした。")
		return
	if not await _send_p2(CombatInputProtocolScript.ACTION_ATTACK_PRESS):
		return
	if not await _wait_for_state_pair(
		p1_user_id,
		"CHARGING",
		final_start_p1,
		final_start_p2,
		5000
	):
		_fail("最終P1 CHARGINGを確認できませんでした。")
		return
	if not await _wait_for_state_pair(
		p2_user_id,
		"CHARGING",
		final_start_p1,
		final_start_p2,
		5000
	):
		_fail("最終P2 CHARGINGを確認できませんでした。")
		return

	var final_p1_defend: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_DEFEND
	)
	if not bool(final_p1_defend.get("ok", false)):
		_fail("最終P1 DEFENDを送信できませんでした。")
		return
	if not await _send_p2(CombatInputProtocolScript.ACTION_DEFEND):
		return
	if not await _wait_for_state_pair(
		p1_user_id,
		"PARRY",
		final_start_p1,
		final_start_p2,
		5000
	):
		_fail("最終P1 PARRYを確認できませんでした。")
		return
	if not await _wait_for_state_pair(
		p2_user_id,
		"PARRY",
		final_start_p1,
		final_start_p2,
		5000
	):
		_fail("最終P2 PARRYを確認できませんでした。")
		return
	if not await _wait_for_state_pair(
		p1_user_id,
		"IDLE",
		final_start_p1,
		final_start_p2,
		5000
	):
		_fail("最終P1がIDLEへ復帰しませんでした。")
		return
	if not await _wait_for_state_pair(
		p2_user_id,
		"IDLE",
		final_start_p1,
		final_start_p2,
		5000
	):
		_fail("最終P2がIDLEへ復帰しませんでした。")
		return

	await create_timer(0.2).timeout
	if not _assert_streams_equal():
		return

	await online_session.realtime_socket.leave_match_async(p1_joined[0])
	await _second_socket.leave_match_async(_second_match_id)
	online_session.disconnect_realtime_socket()
	_second_socket.close()

	print("AHOGE LEGEND combat integration smoke: PASS match_id=%s" % p1_joined[0])
	quit(0)


func _start_p1_attack(online_session, user_id: String, charge_seconds: float) -> int:
	var start_p1 := _p1_states.size()
	var start_p2 := _p2_states.size()
	var press: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_PRESS
	)
	if not bool(press.get("ok", false)):
		_fail("P1 ATTACK_PRESSを送信できませんでした。")
		return -1
	if not await _wait_for_state_pair(user_id, "CHARGING", start_p1, start_p2, 5000):
		_fail("P1 CHARGINGを確認できませんでした。")
		return -1
	if charge_seconds > 0.0:
		await create_timer(charge_seconds).timeout
	var release: Dictionary = await online_session.send_combat_input(
		CombatInputProtocolScript.ACTION_ATTACK_RELEASE
	)
	if not bool(release.get("ok", false)):
		_fail("P1 ATTACK_RELEASEを送信できませんでした。")
		return -1
	var sequence := int(release.get("input_sequence", 0))
	if not await _wait_for_state_pair(user_id, "STRIKE", start_p1, start_p2, 5000):
		_fail("P1 STRIKEを確認できませんでした。")
		return -1
	return sequence


func _start_p2_attack(user_id: String, charge_seconds: float) -> Dictionary:
	var start_p1 := _p1_states.size()
	var start_p2 := _p2_states.size()
	if not await _send_p2(CombatInputProtocolScript.ACTION_ATTACK_PRESS):
		return {}
	if not await _wait_for_state_pair(user_id, "CHARGING", start_p1, start_p2, 5000):
		_fail("P2 CHARGINGを確認できませんでした。")
		return {}
	if charge_seconds > 0.0:
		await create_timer(charge_seconds).timeout
	if not await _send_p2(CombatInputProtocolScript.ACTION_ATTACK_RELEASE):
		return {}
	var sequence := _second_sequence
	var strike := await _wait_for_state_pair_event(
		user_id,
		"STRIKE",
		start_p1,
		start_p2,
		5000
	)
	if strike.is_empty():
		_fail("P2 STRIKEを確認できませんでした。")
		return {}
	return {"sequence": sequence, "strike": strike}


func _send_p2(action: String) -> bool:
	_second_sequence += 1
	var result = await _second_socket.send_match_state_async(
		_second_match_id,
		CombatInputProtocolScript.OPCODE_COMBAT_INPUT,
		CombatInputProtocolScript.build_input_payload(_second_sequence, action)
	)
	if result != null and result.has_method("is_exception") and result.is_exception():
		_fail("P2 %sを送信できませんでした。" % action)
		return false
	return true


func _on_first_match_state(match_state) -> void:
	_collect(
		match_state,
		_p1_states,
		_p1_defense,
		_p1_contacts,
		_p1_hits,
		_p1_clashes
	)


func _on_second_match_state(match_state) -> void:
	if _second_match_id.is_empty() or str(match_state.match_id) != _second_match_id:
		return
	_collect(
		match_state,
		_p2_states,
		_p2_defense,
		_p2_contacts,
		_p2_hits,
		_p2_clashes
	)


func _collect(
	match_state,
	states: Array[Dictionary],
	defense: Array[Dictionary],
	contacts: Array[Dictionary],
	hits: Array[Dictionary],
	clashes: Array[Dictionary]
) -> void:
	var op_code := int(match_state.op_code)
	if op_code == CombatInputProtocolScript.OPCODE_COMBAT_STATE_CHANGED:
		var event := CombatInputProtocolScript.parse_combat_state_changed_payload(str(match_state.data))
		if not event.is_empty():
			states.append(event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_DEFENSE_RESOLVED:
		var event := CombatInputProtocolScript.parse_defense_resolved_payload(str(match_state.data))
		if not event.is_empty():
			defense.append(event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_CONTACT_REACHED:
		var event := CombatInputProtocolScript.parse_contact_reached_payload(str(match_state.data))
		if not event.is_empty():
			contacts.append(event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_HIT_CONFIRMED:
		var event := CombatInputProtocolScript.parse_hit_confirmed_payload(str(match_state.data))
		if not event.is_empty():
			hits.append(event)
		return
	if op_code == CombatInputProtocolScript.OPCODE_ATTACK_CLASH:
		var event := CombatInputProtocolScript.parse_attack_clash_payload(str(match_state.data))
		if not event.is_empty():
			clashes.append(event)


func _on_second_matchmaker_matched(matched) -> void:
	if matched == null or matched.is_exception():
		_second_failure = "P2 matchmaker matched通知が不正です。"
		return
	if str(matched.ticket) != _second_ticket:
		return
	var match_id := str(matched.match_id)
	if match_id.is_empty():
		_second_failure = "P2 matched通知にauthoritative match IDがありません。"
		return
	var join_result = await _second_socket.join_match_async(match_id)
	if join_result == null or join_result.is_exception():
		_second_failure = "P2 authoritative match joinに失敗しました。"
		return
	_second_match_id = str(join_result.match_id)


func _wait_for_state_pair(
	user_id: String,
	state_name: String,
	start_p1: int,
	start_p2: int,
	timeout_ms: int
) -> bool:
	return not (await _wait_for_state_pair_event(
		user_id,
		state_name,
		start_p1,
		start_p2,
		timeout_ms
	)).is_empty()


func _wait_for_state_pair_event(
	user_id: String,
	state_name: String,
	start_p1: int,
	start_p2: int,
	timeout_ms: int
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var first := _find_state(_p1_states, user_id, state_name, start_p1)
		var second := _find_state(_p2_states, user_id, state_name, start_p2)
		if not first.is_empty() and not second.is_empty():
			if first != second:
				_fail("P1/P2で%s %s state eventが一致しません。" % [user_id, state_name])
				return {}
			return first
		await create_timer(0.02).timeout
	return {}


func _find_state(
	events: Array[Dictionary],
	user_id: String,
	state_name: String,
	start_index: int
) -> Dictionary:
	for index in range(maxi(start_index, 0), events.size()):
		var event := events[index]
		if str(event.get("user_id", "")) == user_id 				and str(event.get("state", "")) == state_name:
			return event
	return {}


func _assert_defense_pair(
	input_sequence: int,
	expected: String,
	timeout_ms: int
) -> bool:
	var first := await _wait_defense(_p1_defense, input_sequence, expected, timeout_ms)
	var second := await _wait_defense(_p2_defense, input_sequence, expected, timeout_ms)
	if first.is_empty() or second.is_empty():
		return false
	return _assert_event_pair(first, second, "DefenseResult %s" % expected)


func _wait_defense(
	events: Array[Dictionary],
	input_sequence: int,
	expected: String,
	timeout_ms: int
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for event in events:
			if int(event.get("input_sequence", -1)) == input_sequence 					and str(event.get("result", "")) == expected:
				return event
		await create_timer(0.02).timeout
	_fail("DefenseResult %sを受信できませんでした。sequence=%d" % [expected, input_sequence])
	return {}


func _wait_event_by_sequence(
	events: Array[Dictionary],
	input_sequence: int,
	timeout_ms: int
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for event in events:
			if int(event.get("input_sequence", -1)) == input_sequence:
				return event
		await create_timer(0.02).timeout
	_fail("sequence=%dのイベントを受信できませんでした。" % input_sequence)
	return {}


func _wait_new_event(
	events: Array[Dictionary],
	start_index: int,
	timeout_ms: int
) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if events.size() > start_index:
			return events[start_index]
		await create_timer(0.02).timeout
	_fail("新しいイベントを受信できませんでした。")
	return {}


func _wait_for_availability_pair(
	user_id: String,
	available: bool,
	minimum_server_tick: int,
	timeout_ms: int
) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var first := _find_availability(_p1_states, user_id, available, minimum_server_tick)
		var second := _find_availability(_p2_states, user_id, available, minimum_server_tick)
		if not first.is_empty() and not second.is_empty():
			if first != second:
				_fail("P1/P2でahoge availability eventが一致しません。")
				return false
			return true
		await create_timer(0.02).timeout
	return false


func _find_availability(
	events: Array[Dictionary],
	user_id: String,
	available: bool,
	minimum_server_tick: int
) -> Dictionary:
	for event in events:
		if str(event.get("user_id", "")) == user_id 				and bool(event.get("ahoge_available", not available)) == available 				and int(event.get("server_tick", -1)) >= minimum_server_tick:
			return event
	return {}


func _assert_event_pair(first: Dictionary, second: Dictionary, label: String) -> bool:
	if first.is_empty() or second.is_empty():
		_fail("%sを両clientで受信できませんでした。" % label)
		return false
	if first != second:
		_fail("%sのpayloadがP1/P2で一致しません。" % label)
		return false
	return true


func _assert_stagger_ticks(event: Dictionary, label: String) -> bool:
	if int(event.get("stagger_until_tick", -1)) - int(event.get("server_tick", -1)) != 14:
		_fail("%sのStagger時間が14tickではありません。" % label)
		return false
	return true


func _has_sequence(events: Array[Dictionary], input_sequence: int) -> bool:
	for event in events:
		if int(event.get("input_sequence", -1)) == input_sequence:
			return true
	return false


func _assert_streams_equal() -> bool:
	if _p1_states != _p2_states:
		_fail("統合完了時にP1/P2のCOMBAT_STATE_CHANGED列が一致しません。")
		return false
	if _p1_defense != _p2_defense:
		_fail("統合完了時にP1/P2のDefenseResult列が一致しません。")
		return false
	if _p1_contacts != _p2_contacts:
		_fail("統合完了時にP1/P2のContactEvent列が一致しません。")
		return false
	if _p1_hits != _p2_hits:
		_fail("統合完了時にP1/P2のHit列が一致しません。")
		return false
	if _p1_clashes != _p2_clashes:
		_fail("統合完了時にP1/P2のAttackClash列が一致しません。")
		return false
	return true


func _fail(message: String) -> void:
	if _second_socket != null:
		_second_socket.close()
	push_error(message)
	print("AHOGE LEGEND combat integration smoke: FAIL")
	quit(1)
