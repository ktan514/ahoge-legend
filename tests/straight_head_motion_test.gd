extends SceneTree

const SessionScript := preload("res://tools/motion_preview/preview_session.gd")
const ProfileScript := preload("res://src/ui/ahoge_mesh_profile.gd")
const ParryScript := preload("res://src/ui/ahoge_parry_motion.gd")
const StateScript := preload("res://src/domain/combatant_state.gd")
const OUT: String = "res://artifacts/straight-head/"
var failures: Array[String] = []
var checks: int = 0
var records: Array = []
var minimum_area: float = INF
var context: String = ""
var first_bad: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var profile = load("res://assets/characters/prototype/charactor_01/ahoge_straight_profile.tres")
	_check(profile != null and profile.prepare(), "直線素材profileの準備")
	if profile == null or not profile.prepare():
		quit(1)
		return
	var texture: Texture2D = load(profile.source_texture_path)
	_check(profile.matches_texture(texture), "承認された素材を変更せず採用")
	_check(profile.bind_vertices.size() == 427, "基準頂点数")
	_check(profile.rest_vertices[0] == Vector2.ZERO, "待機根元")
	_check(profile.bind_vertices[-1].distance_to(profile.rest_vertices[-1]) > 300.0, "画像基準とC字姿勢を分離")
	for i in range(profile.uvs.size()):
		_check((profile.uvs[i] * Vector2(profile.source_size) - profile.root_anchor_px).distance_to(profile.bind_vertices[i]) < 0.005, "UVは素材の基準座標に固定")
	for k in range(65):
		_geometry(profile, profile.sample(float(k) / 64.0))
	if DisplayServer.get_name() == "headless":
		_check(false, "頭部連動の検査には実描画が必要")
	else:
		for resolution in [Vector2i(1280, 720), Vector2i(1600, 900)]:
			for side in [0, 1]:
				for scenario in range(5):
					await _cycle(resolution, side, scenario)
	var result: Dictionary = {"status": "PASS" if failures.is_empty() else "FAIL", "checks": checks, "minimum_area": minimum_area, "cases": records, "failures": failures, "environment": "Godot 4.7.2 / Linux GL Compatibility", "human_verification": "未実施"}
	var f: FileAccess = FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "  "))
	print("STRAIGHT HEAD: %s cases=%d checks=%d failures=%s" % [result.status, records.size(), checks, JSON.stringify(failures)])
	quit(0 if failures.is_empty() else 1)

func _cycle(resolution: Vector2i, side: int, scenario: int) -> void:
	var view: SubViewport = SubViewport.new()
	view.size = resolution
	view.disable_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var session = SessionScript.new()
	await session.reset(view, scenario, 1.0, side, "SHORT_TEST", 60)
	var actor = session.attacker
	var mesh_node = actor.find_child("AhogeDeformMesh", true, false)
	var head: Sprite2D = actor.find_child("HeadSprite", true, false)
	var peak_angle: float = 0.0
	var peak_offset: float = 0.0
	var max_root_error: float = 0.0
	var min_safety: float = 1.0
	var max_lag: float = 0.0
	var frame: int = 0
	var label: String = "%d_%d_%d" % [resolution.x, side, scenario]
	var capture: bool = resolution.x == 1280 and side == 0 and scenario in [0, 1, 3] and not OS.get_cmdline_user_args().has("--no-capture")
	var trace: Array = []
	while session.time < session.total - 0.000001:
		session.advance_to(minf(session.time + 1.0 / 60.0, session.total))
		var points: PackedVector2Array = session.pose()
		_check(points.size() == 427, "実描画頂点: " + label)
		if points.size() != 427:
			break
		context = label + " " + str(session.time) + " " + session.state_name()
		_geometry(mesh_node.profile, mesh_node.current_vertices)
		peak_angle = maxf(peak_angle, absf(head.rotation))
		peak_offset = maxf(peak_offset, actor._head_offset.length())
		min_safety = minf(min_safety, actor.last_safety_scale)
		max_lag = maxf(max_lag, absf(head.rotation - actor._ahoge_rig.rotation))
		var expected_root: Vector2 = actor.ahoge_head_anchor_canvas_position()
		max_root_error = maxf(max_root_error, points[0].distance_to(expected_root))
		_check(max_root_error < 0.02, "頭部が傾いても根元が一致: " + label)
		var bounds: Rect2 = actor.head_canvas_bounds()
		_check(bounds.position.x >= actor.arena_canvas_rect.position.x - 0.5 and bounds.end.x <= actor.arena_canvas_rect.end.x + 0.5, "頭部横端: " + label)
		for point in points:
			_check(actor.arena_canvas_rect.grow(0.5).has_point(point), "アホ毛の見切れ: " + label)
		trace.append({"time": session.time, "safety": actor.last_safety_scale, "head": [actor._head_offset.x, actor._head_offset.y], "angle": head.rotation, "lag_angle": actor._ahoge_rig.rotation, "tip": [points[-1].x, points[-1].y], "state": session.state_name()})
		if capture:
			await process_frame
			await RenderingServer.frame_post_draw
			_check(view.get_texture().get_image().save_png(OUT + "cycle_%d_%03d.png" % [scenario, frame]) == OK, "PNG保存")
		frame += 1
	_check(peak_offset >= 10.0, "頭部に視認可能な移動: " + label)
	_check(peak_angle >= deg_to_rad(3.0), "頭部に視認可能な傾き: " + label)
	# 頭部先行の時刻は既存BattleHeadMotion側で定義。ここでは姿勢と根元を検査する。
	if session.contact_time > 0.0:
		# 先頭から接触時刻へ戻して同じ本体の計算を通す。
		await session.reset(view, scenario, 1.0, side, "SHORT_TEST", 60)
		session.advance_to(session.contact_time)
		_check(session.attacker.last_contact_error <= 2.0, "新素材でも接触: " + label)
	records.append({"label": label, "max_root_error_px": max_root_error, "peak_head_move_px": peak_offset, "peak_head_angle_deg": rad_to_deg(peak_angle), "head_rig_rotation_difference_deg": rad_to_deg(max_lag), "minimum_safety_scale": min_safety, "frames": trace})
	view.free()

func _geometry(profile, points: PackedVector2Array) -> void:
	for i in range(0, profile.indices.size(), 3):
		var a: Vector2 = points[profile.indices[i]]
		var b: Vector2 = points[profile.indices[i + 1]]
		var c: Vector2 = points[profile.indices[i + 2]]
		var area: float = (b - a).cross(c - a)
		minimum_area = minf(minimum_area, area)
		if area <= 0.0001 and not first_bad:
			first_bad = true
			print("FIRST BAD context=%s triangle=%d indices=%s area=%f" % [context, i / 3, str(profile.indices.slice(i, i + 3)), area])
		_check(area > 0.0001, "新素材の面反転または退化")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)