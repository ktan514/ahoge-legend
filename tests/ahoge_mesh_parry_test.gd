extends SceneTree

const HudScene := preload("res://scenes/screens/battle/BattleHUD.tscn")
const StateScript := preload("res://src/domain/combatant_state.gd")
const ConfigScript := preload("res://src/config/combat_config.gd")
const CatalogScript := preload("res://src/domain/character_catalog.gd")
const ParryScript := preload("res://src/ui/ahoge_parry_motion.gd")
const PROFILE: String = "res://assets/characters/prototype/charactor_01/ahoge_mesh_profile.tres"
const OUT: String = "res://artifacts/ahoge-mesh/parry/"
var failures: Array[String] = []
var records: Array = []
var minimum_area: float = INF
var maximum_width_error: float = 0.0
var geometry_samples: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var profile = load(PROFILE)
	_expect(profile != null and profile.prepare(), "パリィのprofileを準備できません")
	if profile == null or not profile.prepare():
		quit(1)
		return
	_check_geometry(profile)
	var preview_config = ConfigScript.new()
	_expect(
		absf(ParryScript.sweep_at(1.0 / 60.0, preview_config.parry_active_seconds)) <= 0.08,
		"パリィ初動1frameで毛先prepareが急に曲がります"
	)
	_expect(
		absf(ParryScript.PREPARE_ANGLE) <= 0.11,
		"パリィprepare角が初動の毛先折れ候補域を超えています"
	)
	if DisplayServer.get_name() == "headless":
		_expect(false, "パリィの表示試験には実描画が必要です")
	else:
		for resolution in [Vector2i(1280, 720), Vector2i(1600, 900)]:
			for fps in [30, 60, 120]:
				for side in [0, 1]:
					for origin_state in [StateScript.ActionState.IDLE, StateScript.ActionState.CHARGING, StateScript.ActionState.WINDUP, StateScript.ActionState.STRIKE]:
						await _cycle(resolution, fps, side, origin_state)
	var report: Dictionary = {"status": "PASS" if failures.is_empty() else "FAIL", "geometry_samples": geometry_samples, "minimum_twice_area": minimum_area, "maximum_width_error_source_px": maximum_width_error, "cases": records, "failures": failures, "human_verification": "未実施"}
	var file: FileAccess = FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("AHOGE local parry: %s cases=%d geometry=%d area=%f width_error=%f failures=%s" % [report["status"], records.size(), geometry_samples, minimum_area, maximum_width_error, JSON.stringify(failures)])
	quit(0 if failures.is_empty() else 1)


func _check_geometry(profile) -> void:
	var rest: PackedVector2Array = profile.rest_vertices
	var rest_centers: PackedVector2Array = ParryScript.centers_of(rest, profile.WIDTH_POINTS)
	var fractions: PackedFloat32Array = ParryScript.arc_fractions(rest_centers)
	for shape in range(9):
		var base: PackedVector2Array = profile.sample(float(shape) / 8.0)
		var centers: PackedVector2Array = ParryScript.centers_of(base, profile.WIDTH_POINTS)
		for step in range(33):
			var sweep: float = lerpf(ParryScript.SWEEP_ANGLE, ParryScript.PREPARE_ANGLE, float(step) / 32.0)
			var vertices: PackedVector2Array = ParryScript.deform(profile, base, sweep)
			geometry_samples += 1
			_expect(vertices.size() == base.size(), "頂点数が変化しました")
			_expect(vertices[0].is_equal_approx(Vector2.ZERO), "パリィの根元が動きました")
			var after_centers: PackedVector2Array = ParryScript.centers_of(vertices, profile.WIDTH_POINTS)
			_expect(absf(_length(centers) - _length(after_centers)) < 0.03, "パリィで弧長が変化しました")
			for row in range(centers.size() - 2):
				var first: int = 1 + row * profile.WIDTH_POINTS
				var last: int = first + profile.WIDTH_POINTS - 1
				var width_error: float = absf(base[first].distance_to(base[last]) - vertices[first].distance_to(vertices[last]))
				maximum_width_error = maxf(maximum_width_error, width_error)
				_expect(width_error < 0.02, "パリィで断面幅が潰れました")
				if fractions[row + 1] <= ParryScript.FIXED_FRACTION:
					for i in range(first, last + 1):
						_expect(vertices[i].distance_to(base[i]) < 0.001, "根元側62%へ払い変位が入りました")
			for i in range(0, profile.indices.size(), 3):
				var a: Vector2 = vertices[profile.indices[i]]
				var b: Vector2 = vertices[profile.indices[i + 1]]
				var c: Vector2 = vertices[profile.indices[i + 2]]
				var area: float = (b - a).cross(c - a)
				minimum_area = minf(minimum_area, area)
				_expect(area > 0.0001, "パリィの面反転または退化: shape=%d step=%d" % [shape, step])
			if step % 8 == 0:
				_check_boundary(vertices, profile.boundary_indices)
	var swept: PackedVector2Array = ParryScript.deform(profile, rest, ParryScript.SWEEP_ANGLE)
	var travel: float = swept[-1].distance_to(rest[-1]) * 1280.0 / 5200.0
	_expect(travel >= 12.0 and travel <= 110.0, "毛先払いが視認できる近距離の範囲外: %f" % travel)
	var swept_centers: PackedVector2Array = ParryScript.centers_of(swept, profile.WIDTH_POINTS)
	_expect(_length(swept_centers) / swept_centers[0].distance_to(swept_centers[-1]) > 1.5, "パリィでC字の湾曲が失われました")
	print("AHOGE parry geometry tip_displacement_px=%f samples=%d" % [travel, geometry_samples])


func _check_boundary(vertices: PackedVector2Array, boundary: PackedInt32Array) -> void:
	for i in range(boundary.size()):
		for j in range(i + 2, boundary.size()):
			if i == 0 and j == boundary.size() - 1:
				continue
			var cross_point = Geometry2D.segment_intersects_segment(vertices[boundary[i]], vertices[boundary[(i + 1) % boundary.size()]], vertices[boundary[j]], vertices[boundary[(j + 1) % boundary.size()]])
			_expect(cross_point == null, "パリィの外周が自己交差しました")


func _cycle(resolution: Vector2i, fps: int, side: int, origin_state: int) -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = resolution
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var hud = HudScene.instantiate()
	viewport.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var director = hud.contact_director
	director.set_process(false)
	var config = ConfigScript.new()
	var state = StateScript.new(config)
	var other_state = StateScript.new(config)
	var character = CatalogScript.get_by_id("LONG_TEST")
	if side == 0:
		hud.set_combatants(character, state, character, other_state)
	else:
		hud.set_combatants(character, other_state, character, state)
	await process_frame
	await process_frame
	var actor = director.fighters[side]
	var mesh_node = actor.find_child("AhogeDeformMesh", true, false)
	var motion: Node2D = actor.find_child("AhogeMotionRoot", true, false) as Node2D
	var head: Sprite2D = actor.find_child("HeadSprite", true, false) as Sprite2D
	var label: String = "%d_%d_%d_%d" % [resolution.x, fps, side, origin_state]
	_expect(hud.size.is_equal_approx(Vector2(resolution)), "HUD寸法が不正: " + label)
	_expect(mesh_node != null and mesh_node.configured, "パリィメッシュがありません: " + label)
	if mesh_node == null or not mesh_node.configured:
		viewport.free()
		return
	var original_rid: RID = mesh_node.mesh.get_rid()
	var original_uv: PackedVector2Array = mesh_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var original_indices: PackedInt32Array = mesh_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	state.action_state = origin_state
	for i in range(maxi(1, int(0.1 * fps))):
		director.advance(1.0 / fps)
	var before: PackedVector2Array = mesh_node.current_vertices.duplicate()
	var before_transform: Transform2D = motion.transform
	state.action_state = StateScript.ActionState.PARRY
	director.advance(1.0 / fps)
	_expect(_difference(before, mesh_node.current_vertices) < 0.002, "パリィ開始で形状が飛びました: " + label)
	_expect(before_transform.is_equal_approx(motion.transform), "パリィ開始で全体姿勢が飛びました: " + label)
	var peak_displacement: float = 0.0
	var capture_sequence: bool = resolution.x == 1280 and fps == 60 and side == 0 and origin_state == StateScript.ActionState.IDLE
	var screenshot_done: bool = false
	var frame: int = 0
	var elapsed: float = 0.0
	while elapsed < float(config.parry_active_seconds) + 0.035:
		director.advance(1.0 / fps)
		elapsed += 1.0 / fps
		var vertices: PackedVector2Array = mesh_node.current_vertices
		var canvas: PackedVector2Array = actor.mesh_canvas_vertices()
		for point in canvas:
			_expect(actor.arena_canvas_rect.grow(0.5).has_point(point), "パリィが画面外: " + label)
		if elapsed >= ParryScript.ENTRY_SECONDS:
			_expect(actor.rendered_straighten() < 0.001, "パリィ中に攻撃直線化が残っています: " + label)
			_expect(actor.last_presentation_weight == 0.0, "パリィに遠方接触補正が掛かっています: " + label)
			_expect(actor.last_safety_scale >= 0.999, "パリィを画面保護で縮めています: " + label)
			_expect(absf(head.position.y - (actor.size.y + 44.0)) <= 4.0, "パリィで頭部が大きく上下しました: " + label)
			var displacement: float = (motion.transform * (vertices[-1] - mesh_node.profile.rest_vertices[-1])).length()
			peak_displacement = maxf(peak_displacement, displacement)
			var same_pose: PackedVector2Array = canvas.duplicate()
			actor.present_toward(Vector2(-5000.0, -5000.0))
			_expect(_difference(same_pose, actor.mesh_canvas_vertices()) < 0.002, "パリィが相手頭部目標へ追従しました: " + label)
		if capture_sequence:
			await _save(viewport, "cycle_%03d.png" % frame)
			frame += 1
		if not screenshot_done and elapsed >= float(config.parry_active_seconds) * 0.52:
			screenshot_done = true
			await _save(viewport, "sweep_" + label + ".png")
	_expect(peak_displacement >= 10.0, "先端の払いが小さすぎます: " + label)
	state.action_state = StateScript.ActionState.COOLDOWN
	for i in range(24):
		director.advance(1.0 / 60.0)
	_expect(absf(mesh_node.parry_sweep) < 0.001, "払いの余韻が残っています: " + label)
	_expect(not actor.confirm_contact(), "パリィ後に古い攻撃接触を受け付けました: " + label)
	state.action_state = StateScript.ActionState.PARRY
	director.advance(0.01)
	state.ahoge_available = false
	director.advance(0.01)
	state.ahoge_available = true
	director.advance(0.04)
	_expect(absf(mesh_node.parry_sweep) < 0.001 and actor.rendered_straighten() < 0.001, "再表示でパリィを再発しました: " + label)
	state.action_state = StateScript.ActionState.ROUND_LOCKED
	director.advance(0.01)
	_expect(absf(mesh_node.parry_sweep) < 0.001, "Round lockに払いが残りました: " + label)
	_expect(original_rid == mesh_node.mesh.get_rid(), "パリィでmesh RIDが変わりました: " + label)
	_expect(original_uv == mesh_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV], "パリィでUVが変わりました: " + label)
	_expect(original_indices == mesh_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX], "パリィで三角形接続が変わりました: " + label)
	records.append({"label": label, "peak_tip_displacement_px": peak_displacement, "render_saved": screenshot_done})
	viewport.free()


func _length(centers: PackedVector2Array) -> float:
	var total: float = 0.0
	for i in range(1, centers.size()):
		total += centers[i].distance_to(centers[i - 1])
	return total


func _difference(a: PackedVector2Array, b: PackedVector2Array) -> float:
	if a.size() != b.size():
		return INF
	var maximum: float = 0.0
	for i in range(a.size()):
		maximum = maxf(maximum, a[i].distance_to(b[i]))
	return maximum


func _save(viewport: SubViewport, name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	_expect(image != null and not image.is_empty(), "パリィ描画画像が空です")
	if image != null:
		_expect(image.save_png(OUT + name) == OK, "パリィ描画を保存できません")


func _expect(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)
