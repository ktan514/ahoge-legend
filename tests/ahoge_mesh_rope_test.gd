extends SceneTree

const Motion := preload("res://src/ui/ahoge_action_motion.gd")
const Parts := preload("res://src/ui/ahoge_parry_motion.gd")
const State := preload("res://src/domain/combatant_state.gd")
const Config := preload("res://src/config/combat_config.gd")
const OUT: String = "res://artifacts/ahoge-mesh/rope/"
var checks: int = 0
var failures: Array[String] = []
var records: Array = []
var profile


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	profile = load("res://assets/characters/prototype/charactor_01/ahoge_mesh_profile.tres")
	_expect(profile != null and profile.prepare(), "実素材のprofileを読めません")
	if profile == null or not profile.prepare():
		quit(1)
		return
	_check_open_hang()
	_check_bend_travel()
	_check_charge_timing()
	for charge in [0.0, 0.25, 0.5, 0.75, 1.0]:
		for cooldown in [false, true]:
			_check_late_contact(charge, cooldown)
	_check_curved_parry()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var report: Dictionary = {"status": "PASS" if failures.is_empty() else "FAIL", "checks": checks, "cases": records, "failures": failures, "human_verification": "未実施"}
	var file: FileAccess = FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("AHOGE rope continuity: %s checks=%d cases=%d failures=%s" % [report["status"], checks, records.size(), JSON.stringify(failures)])
	quit(0 if failures.is_empty() else 1)


func _new_motion():
	var motion = Motion.new()
	_expect(motion.configure(profile), "動作を初期化できません")
	return motion


func _check_open_hang() -> void:
	var motion = _new_motion()
	for i in range(120):
		motion.advance(State.ActionState.CHARGING, 0.005, 0.6, 0.6, 1.0, true)
		_check_mesh(motion.vertices)
	var low: float = INF
	var high: float = -INF
	for i in range(motion.fractions.size()):
		if motion.fractions[i] >= 0.6:
			low = minf(low, motion.current_angles[i])
			high = maxf(high, motion.current_angles[i])
	_expect(high - low < 1.7, "最大溜めの先端区間が輪へ巻き込まれています")
	var end_tangent: Vector2 = Vector2.from_angle(motion.current_angles[-1])
	_expect(end_tangent.x < -0.1 and end_tangent.y > 0.1, "溜めの先端が後方下向きではありません")
	_expect(motion.vertices[-1].x < -100.0 and motion.vertices[-1].y > profile.rest_vertices[-1].y + 100.0, "後方への垂れがありません")
	records.append({"case": "open_hang", "tail_turn_range": high - low, "tip": [motion.vertices[-1].x, motion.vertices[-1].y]})


func _check_bend_travel() -> void:
	var config = Config.new()
	var centroids: Array[float] = []
	for normalized in [0.2, 0.5, 0.8]:
		var motion = _new_motion()
		# follow_progress = 2u-u^2 の逆。実advance後の頂点を検査する。
		var seconds: float = Motion.FOLLOW_SECONDS * (1.0 - sqrt(1.0 - normalized))
		motion.advance(State.ActionState.STRIKE, config.normal_strike_seconds * config.attack_contact_ratio + seconds, config.normal_strike_seconds, 0.6, 0.0, true)
		_check_mesh(motion.vertices)
		var base: PackedVector2Array = Parts.centers_of(motion.vertices_from_angles(motion.straight_angles), profile.WIDTH_POINTS)
		var posed: PackedVector2Array = Parts.centers_of(motion.vertices, profile.WIDTH_POINTS)
		var sum_weight: float = 0.0
		var weighted_position: float = 0.0
		var arc: PackedFloat32Array = Parts.arc_fractions(base)
		for i in range(2, base.size() - 1):
			var original_turn: float = (base[i] - base[i - 1]).angle_to(base[i + 1] - base[i])
			var posed_turn: float = (posed[i] - posed[i - 1]).angle_to(posed[i + 1] - posed[i])
			var weight: float = absf(wrapf(posed_turn - original_turn, -PI, PI))
			sum_weight += weight
			weighted_position += arc[i] * weight
		_expect(sum_weight > 0.30, "接触後に毛束の曲がりが変化していません")
		centroids.append(weighted_position / maxf(sum_weight, 0.00001))
	_expect(centroids[1] > centroids[0] + 0.10 and centroids[2] > centroids[1] + 0.10, "実頂点の曲がり変化が先端へ移動していません")
	var flow = _new_motion()
	var hit_time: float = config.normal_strike_seconds * config.attack_contact_ratio
	flow.advance(State.ActionState.STRIKE, hit_time + 0.0001, config.normal_strike_seconds, 0.6, 0.0, true)
	_expect(flow.follow_progress() / 0.0001 > 8.0, "接触後の軌道が速度0で始まっています")
	records.append({"case": "curvature_travel", "centroids": centroids})


func _check_charge_timing() -> void:
	var config = Config.new()
	var previous: float = INF
	for step in range(21):
		var charge: float = float(step) / 20.0
		var windup: float = config.attack_windup_seconds(charge)
		var strike: float = config.attack_strike_seconds(charge)
		var contact: float = strike * config.attack_contact_ratio
		_expect(windup + contact < previous, "チャージ量を増やしても接触まで速くなりません")
		previous = windup + contact
		var motion = _new_motion()
		motion.advance(State.ActionState.WINDUP, windup, windup, config.max_charge_seconds, charge, true)
		motion.advance(State.ActionState.STRIKE, contact, strike, config.max_charge_seconds, charge, true)
		_expect(motion.straighten >= 0.999 and motion.vertices[-1].is_finite(), "判定時刻と毛先の解放が一致しません")
		records.append({"case": "charge_timing", "charge": charge, "release_to_contact_seconds": windup + contact})


func _check_late_contact(charge: float, cooldown: bool) -> void:
	var config = Config.new()
	var motion = _new_motion()
	var strike: float = config.attack_strike_seconds(charge)
	motion.advance(State.ActionState.STRIKE, strike * config.attack_contact_ratio + 0.012, strike, 0.6, charge, true)
	if cooldown:
		motion.advance(State.ActionState.COOLDOWN, 0.025, config.attack_cooldown_seconds(charge), 0.6, charge, true)
	var vertices: PackedVector2Array = motion.vertices.duplicate()
	var elapsed: float = motion.elapsed
	var follow: float = motion.follow_seconds()
	_expect(not motion.force_contact(), "通過済みの接触通知で再接触を要求しました")
	_expect(motion.vertices == vertices, "遅延Hitが現在の曲がりを直線に戻しました")
	_expect(motion.elapsed == elapsed and motion.follow_seconds() == follow, "遅延Hitが振り抜き時計を巻き戻しました")
	var early = _new_motion()
	early.advance(State.ActionState.STRIKE, 0.001, strike, 0.6, charge, true)
	_expect(early.force_contact() and early.straighten >= 0.999, "接触前の確定結果へ追従できません")
	early.advance(State.ActionState.PARRY, 0.01, config.parry_active_seconds, 0.6, charge, true)
	_expect(not early.force_contact(), "防御中断後の古い攻撃を再生しました")
	records.append({"case": "late_contact", "charge": charge, "cooldown": cooldown})


func _check_curved_parry() -> void:
	var base: PackedVector2Array = Parts.centers_of(profile.rest_vertices, profile.WIDTH_POINTS)
	var posed: PackedVector2Array = Parts.centers_of(Parts.deform(profile, profile.rest_vertices, Parts.SWEEP_ANGLE), profile.WIDTH_POINTS)
	var arc: PackedFloat32Array = Parts.arc_fractions(base)
	for i in range(2, base.size() - 1):
		if arc[i - 1] >= 0.85:
			var old_turn: float = (base[i] - base[i - 1]).angle_to(base[i + 1] - base[i])
			var new_turn: float = (posed[i] - posed[i - 1]).angle_to(posed[i + 1] - posed[i])
			_expect(absf(wrapf(old_turn - new_turn, -PI, PI)) < 0.001, "末端の湾曲を開閉してパリィを代用しています")


func _check_mesh(vertices: PackedVector2Array) -> void:
	_expect(vertices.size() == profile.rest_vertices.size(), "頂点数が変わりました")
	for i in range(0, profile.indices.size(), 3):
		var a: Vector2 = vertices[profile.indices[i]]
		var b: Vector2 = vertices[profile.indices[i + 1]]
		var c: Vector2 = vertices[profile.indices[i + 2]]
		_expect((b - a).cross(c - a) > 0.0001, "ロープ変形に面反転・退化があります")


func _expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)
