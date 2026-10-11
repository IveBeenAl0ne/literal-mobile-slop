extends SceneTree
func _initialize(): call_deferred("run")
func run():
	var world = Node3D.new()
	world.set_script(load("res://scripts/world.gd"))
	world.setup(TycoonPack.parse_bytes(FileAccess.get_file_as_bytes("res://packs/sunny_farm.json")))
	root.add_child(world)
	for n in range(45): await process_frame
	await RenderingServer.frame_post_draw
	var output = OS.get_environment("TYCOON_PREVIEW_OUTPUT")
	if output.is_empty(): output = "user://runtime-preview.png"
	root.get_texture().get_image().save_png(output)
	quit()
