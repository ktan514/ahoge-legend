extends SceneTree

const PreviewScene := preload("res://tools/motion_preview/NeckRangePreview.tscn")
const OUT: String = "res://artifacts/neck-range/sakuramiko-breath/"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1440, 960)
	var scene = PreviewScene.instantiate()
	root.add_child(scene)
	for _i in range(30):
		await process_frame
		if scene.ready_for_input:
			break
	if not scene.ready_for_input:
		push_error("さくらみこPreviewを起動できません")
		quit(1)
		return

	# 正式キャラクター「さくらみこ」を明示選択する。
	var sakuramiko_index: int = -1
	for i in range(scene._character.item_count):
		if str(scene._character.get_item_metadata(i)) == "SAKURAMIKO":
			sakuramiko_index = i
			break
	if sakuramiko_index < 0 or scene._character.is_item_disabled(sakuramiko_index):
		push_error("さくらみこを選択できません")
		quit(1)
		return

	scene._character.select(sakuramiko_index)
	await scene.rebuild()
	scene._side.select(0)
	scene._resolution.select(0)
	await scene.rebuild()
	scene.stop_oscillation()
	scene.set_ratio(0.0)
	scene.set_process(false)

	# 呼吸とPassive Flexだけを30fps固定で進める。
	var delta: float = 1.0 / 30.0
	for frame in range(90):
		scene.fighter.advance_neck_preview(delta)
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = scene.viewport.get_texture().get_image()
		if image == null or image.is_empty():
			push_error("Preview frameを取得できません: %d" % frame)
			quit(1)
			return
		var path: String = OUT + "frame_%03d.png" % frame
		if image.save_png(path) != OK:
			push_error("Preview frameを保存できません: " + path)
			quit(1)
			return

	print("SAKURAMIKO GIF CAPTURE: PASS frames=90")
	scene.free()
	quit(0)
