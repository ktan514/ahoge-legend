extends SceneTree

const ProfileAsset = preload("res://assets/characters/prototype/charactor_01/ahoge_mesh_profile.tres")
var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var profile = ProfileAsset
	_expect(profile.prepare().is_empty(), "固定メッシュの初期化と全補間区間の面積検査")
	if not _failures.is_empty():
		_finish()
		return
	_expect(profile.rest_vertices_px.size() == 215, "根元から真の毛先まで215頂点")
	_expect(profile.triangle_indices.size() == 284 * 3, "284面の固定三角形")
	_expect(profile.uvs.size() == profile.rest_vertices_px.size(), "全頂点の固定UV")
	_expect(profile.minimum_area_ratio > 0.7, "区間内極値を含む符号付き面積比")
	var count: int = profile.rest_vertices_px.size()
	profile.prepare()
	_expect(profile.rest_vertices_px.size() == count, "再初期化で頂点を重複しない")
	for amount in [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1.0]:
		var points: PackedVector2Array = profile.vertices_at(amount)
		_expect(points.size() == count, "形状間で頂点IDと個数を固定")
		for vertex_id in profile.root_vertex_indices:
			_expect(points[vertex_id].distance_to(profile.rest_vertices_px[vertex_id]) <= 0.002, "根元固定")
	var straight: PackedVector2Array = profile.centerline_keys[-1]
	for index in range(int(straight.size() * 0.8), straight.size() - 1):
		var direction: Vector2 = straight[index + 1] - straight[index]
		_expect(absf(wrapf(direction.angle() - deg_to_rad(profile.unfold_target_angle_degrees), -PI, PI)) < deg_to_rad(0.2), "毛先側20%が目標方向へ直線化")
	var invalid = ProfileAsset.duplicate(true)
	invalid.section_left_offsets_px[2] = 20.0
	_expect(not invalid.prepare().is_empty(), "壊れた制作断面を拒否")
	var texture := load(profile.source_texture_path) as Texture2D
	_expect(profile.validate_source(texture).is_empty(), "現行ピンク素材のSHA-256一致")
	_expect(profile.validate_source(ImageTexture.create_from_image(texture.get_image())).is_empty(), "export向けの正規化画素識別")
	var tampered: Image = texture.get_image()
	tampered.set_pixel(558, 1124, Color(0.0, 0.0, 0.0, 1.0))
	_expect(not profile.validate_source(ImageTexture.create_from_image(tampered)).is_empty(), "同じ寸法でも可視画素が異なる素材を拒否")
	var wrong_image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	_expect(not profile.validate_source(ImageTexture.create_from_image(wrong_image)).is_empty(), "別素材を拒否")
	DirAccess.make_dir_recursive_absolute("res://artifacts/ahoge-mesh")
	var file := FileAccess.open("res://artifacts/ahoge-mesh/profile_geometry.json", FileAccess.WRITE)
	if file == null:
		_failures.append("幾何学検証資料を保存できません")
	else:
		file.store_string(JSON.stringify(profile.export_verification_data()))
	_finish()


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _finish() -> void:
	for failure in _failures:
		push_error(failure)
	print("Ahoge mesh geometry: %s (%d checks)" % ["PASS" if _failures.is_empty() else "FAIL", _checks])
	quit(0 if _failures.is_empty() else 1)
