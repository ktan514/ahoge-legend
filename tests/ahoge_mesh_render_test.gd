extends SceneTree

const DeformerScript := preload("res://src/ui/ahoge_mesh_deformer.gd")
const OUT: String = "res://artifacts/ahoge-mesh/"
var _failure: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	if DisplayServer.get_name() == "headless":
		push_error("メッシュの描画試験はheadlessでは実行しません。Xvfb等の描画環境が必要です。")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var source: Texture2D = load("res://assets/characters/prototype/charactor_01/ahoge.png") as Texture2D
	var node: DeformerScript = DeformerScript.new()
	if not node.configure(source):
		push_error("現行素材とメッシュの対応が不一致です。")
		quit(1)
		return
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(640, 640)
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var origin: Vector2 = Vector2(205.0, 580.0)
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = source
	sprite.centered = false
	sprite.position = origin - node.profile.root_anchor_px * 0.30
	sprite.scale = Vector2(0.30, 0.30)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	viewport.add_child(sprite)
	await _capture(viewport, "reference.png")
	sprite.visible = false
	node.position = origin
	node.scale = Vector2(0.30, 0.30)
	viewport.add_child(node)
	for step in range(17):
		node.set_straighten(float(step) / 16.0)
		await _capture(viewport, "shape_%02d.png" % step)
	# 同一ノードの頂点更新で元の絵へ戻ることも確認する。
	node.set_straighten(0.0)
	await _capture(viewport, "returned.png")

	var geometry: Dictionary = {
		"root": [node.profile.root_anchor_px.x, node.profile.root_anchor_px.y],
		"uvs": _points(node.profile.uvs),
		"indices": Array(node.profile.indices),
		"boundary": Array(node.profile.boundary_indices),
		"keys": [],
		"source_file_sha256": node.profile.source_file_sha256,
	}
	for vertices in node.profile.shape_keys:
		geometry["keys"].append(_points(vertices))
	var file: FileAccess = FileAccess.open(OUT + "geometry.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(geometry))
	file.close()
	viewport.free()
	print("AHOGE mesh render capture: PASS renderer=%s" % RenderingServer.get_current_rendering_method())
	quit(1 if _failure else 0)


func _capture(viewport: SubViewport, name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(OUT + name) != OK:
		_failure = true
		push_error("描画画像を保存できません: " + name)


func _points(values: PackedVector2Array) -> Array:
	var result: Array = []
	for p in values:
		result.append([p.x, p.y])
	return result
