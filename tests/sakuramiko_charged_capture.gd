extends SceneTree

const PreviewScene := preload("res://tools/motion_preview/NeckRangePreview.tscn")
const OUT: String = "res://artifacts/neck-range/sakuramiko-charged/"


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
		push_error("NeckRangePreviewを起動できません")
		quit(1)
		return

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
	scene._mode.select(scene.PreviewMode.CHARGED_ATTACK)
	await scene.rebuild()
	scene.stop_oscillation()
	scene.set_ratio(0.0)
	scene.set_process(false)

	# 現在HEADのチャージ攻撃1周期を30fps固定で決定論的に進める。
	var fps: float = 30.0
	var delta: float = 1.0 / fps
	var cycle: float = scene.CHARGED_PREVIEW_SECONDS
	var frames: int = ceili(cycle * fps) + 1
	var elapsed: float = 0.0
	for frame in range(frames):
		var sample_time: float = minf(elapsed, cycle - 0.000001)
		scene._apply_preview_frame(sample_time, 0.0 if frame == 0 else delta)
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = scene.viewport.get_texture().get_image()
		if image == null or image.is_empty():
			push_error("チャージ攻撃frameを取得できません: %d" % frame)
			quit(1)
			return
		var path: String = OUT + "frame_%03d.png" % frame
		if image.save_png(path) != OK:
			push_error("チャージ攻撃frameを保存できません: " + path)
			quit(1)
			return
		elapsed += delta

	print("SAKURAMIKO CHARGED CAPTURE: PASS frames=%d cycle=%f" % [frames, cycle])
	scene.free()
	quit(0)
