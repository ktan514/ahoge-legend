extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var texture := load("res://assets/characters/prototype/charactor_01/ahoge.png") as Texture2D
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute("res://artifacts/ahoge-mesh")
	image.save_png("res://artifacts/ahoge-mesh/imported_source.png")
	print("Imported source: size=%s bytes=%d mipmaps=%s" % [image.get_size(), image.get_data().size(), image.has_mipmaps()])
	var bytes := image.get_data()
	for offset in range(0, bytes.size(), 4):
		if bytes[offset + 3] < 20:
			bytes[offset] = 0
			bytes[offset + 1] = 0
			bytes[offset + 2] = 0
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	print("Imported canonical SHA-256: " + hashing.finish().hex_encode())
	quit(0)
