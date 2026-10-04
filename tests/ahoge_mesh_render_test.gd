extends SceneTree

const ProfileAsset = preload("res://assets/characters/prototype/charactor_01/ahoge_mesh_profile.tres")
const DeformerScript := preload("res://src/ui/ahoge_mesh_deformer.gd")
var _checks: int = 0
var _failures: Array[String] = []
var _viewport: SubViewport
var _mesh


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/ahoge-mesh/render")
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(800, 620)
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var texture := load(ProfileAsset.source_texture_path) as Texture2D
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = Vector2(240, 550) - ProfileAsset.root_anchor_px * 0.28
	sprite.scale = Vector2(0.28, 0.28)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_viewport.add_child(sprite)
	var reference: Image = await _capture("source")
	sprite.visible = false
	_mesh = DeformerScript.new()
	_viewport.add_child(_mesh)
	_mesh.position = Vector2(240, 550)
	_mesh.scale = Vector2(0.28, 0.28)
	var configured: bool = _mesh.setup(texture, ProfileAsset)
	_expect(configured, "fallbackではなく実メッシュを描画: " + _mesh.failure_reason)
	if not configured:
		_finish()
		return
	var rest: Image = await _capture("rest")
	var reference_data := reference.get_data()
	var rest_data := rest.get_data()
	var alpha_total: float = 0.0
	var alpha_difference: float = 0.0
	for offset in range(0, reference_data.size(), 4):
		alpha_total += reference_data[offset + 3]
		alpha_difference += absf(float(reference_data[offset + 3]) - float(rest_data[offset + 3]))
	var difference_ratio := alpha_difference / maxf(alpha_total, 1.0)
	_expect(alpha_total > 1000.0, "実rendererから非透明な画像を取得")
	_expect(difference_ratio < 0.005, "待機meshとSpriteのalpha差が0.5%未満")
	print("Ahoge mesh rest alpha difference: %.8f" % difference_ratio)
	var original_rid: RID = _mesh.mesh.get_rid()
	var original_uv: PackedVector2Array = _mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var original_indices: PackedInt32Array = _mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	for index in range(9):
		var amount := float(index) / 8.0
		_expect(_mesh.set_straighten(amount), "形状パラメータをGPU頂点更新へ反映")
		var rendered: Image = await _capture("shape_%02d" % index)
		_expect(_mesh.mesh.get_rid() == original_rid, "変形中もmesh RID固定")
		_expect(_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] == original_uv, "UV不変")
		_expect(_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] == original_indices, "index不変")
		var tip: Vector2 = _mesh.position + _mesh.current_vertices[ProfileAsset.tip_vertex_index] * _mesh.scale
		_expect(_alpha_near(rendered, tip, 5) > 0.05, "実際の毛先付近に描画された画素がある")
		_expect(_alpha_near(rendered, _mesh.position, 3) > 0.5, "変形しても根元の描画像を保持")
		var alpha_sum := _sum_alpha(rendered)
		_expect(alpha_sum > alpha_total * 0.65, "変形途中の画像全体が消失・極端に縮退しない")
	for direction in [1.0, -1.0]:
		_mesh.position = Vector2(160, 530) if direction > 0.0 else Vector2(640, 530)
		_mesh.scale = Vector2(0.28 * 1.6 * direction, 0.28 * 0.93)
		_mesh.rotation = 0.7 * direction
		await _capture("strike_right" if direction > 0.0 else "strike_left")
	_expect(_mesh.vertex_stride_bytes > 0, "rendererが返したstrideで頂点を更新")
	_viewport.queue_free()
	_finish()


func _capture(name_value: String) -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	var result := image.save_png("res://artifacts/ahoge-mesh/render/%s.png" % name_value)
	_expect(result == OK, "実描画画像を保存")
	return image


func _alpha_near(image: Image, position_value: Vector2, radius: int) -> float:
	var maximum := 0.0
	for y in range(maxi(int(position_value.y) - radius, 0), mini(int(position_value.y) + radius + 1, image.get_height())):
		for x in range(maxi(int(position_value.x) - radius, 0), mini(int(position_value.x) + radius + 1, image.get_width())):
			maximum = maxf(maximum, image.get_pixel(x, y).a)
	return maximum


func _sum_alpha(image: Image) -> float:
	var bytes := image.get_data()
	var total := 0.0
	for offset in range(3, bytes.size(), 4):
		total += bytes[offset]
	return total


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _finish() -> void:
	for failure in _failures:
		push_error(failure)
	print("Ahoge mesh rendering: %s (%d checks)" % ["PASS" if _failures.is_empty() else "FAIL", _checks])
	quit(0 if _failures.is_empty() else 1)
