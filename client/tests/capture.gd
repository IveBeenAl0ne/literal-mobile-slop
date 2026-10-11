extends SceneTree
func _initialize(): call_deferred("run")
func run():
	var mode = OS.get_environment("TYCOON_CAPTURE_MODE")
	var output = OS.get_environment("TYCOON_PREVIEW_OUTPUT")
	if mode == "cover":
		root.content_scale_size = Vector2i(960, 640)
		root.size = Vector2i(960, 640)
		DisplayServer.window_set_size(Vector2i(960, 640))
	var id = OS.get_environment("TYCOON_CAPTURE_PACK")
	if id.is_empty(): id = "sunny_farm"
	if mode == "library":
		var hub = Node.new()
		hub.set_script(load("res://scripts/hub.gd"))
		hub.auto_refresh = false
		root.add_child(hub)
		hub.installed.erase("download_test")
		hub.catalog = hub.valid_entries(JSON.parse_string(FileAccess.get_file_as_string("res://catalog.json")))
		hub.render_cards()
	else:
		var world = Node3D.new()
		world.set_script(load("res://scripts/world.gd"))
		world.preview_mode = true
		world.setup(TycoonPack.parse_bytes(FileAccess.get_file_as_bytes("res://packs/%s.json" % id)))
		if mode == "cover":
			for s in world.sim.pack.stations:
				world.sim.stations[s.id].unlocked = true
				if s.kind in ["source", "processor"]: world.sim.stations[s.id].stock = 6
				if s.kind == "shop": world.sim.stations[s.id].input_stock = 6
		root.add_child(world)
		if mode == "game":
			world.player.position = Vector3(0, 0, -0.5)
			world.camera.position = world.player.position + Vector3(0, 18, 9)
			world.sim.bag[world.sim.pack.items[1].id] = 4
			for s in world.sim.pack.stations:
				if s.kind == "shop" and world.sim.stations[s.id].unlocked:
					world.sim.stations[s.id].input_stock = 4
					world.sim.stations[s.id].pending_cash = s.price * 3
			for c in world.customers:
				c.node.position = world.visuals[c.shop].position + Vector3(2 + c.slot * .7, 0, 0)
			world.refresh()
		if mode == "cover":
			world.ui_root.visible = false
			world.camera.position = Vector3(9, 15, 16)
			world.camera.look_at(Vector3(0, 0, -1))
			world.camera.size = 14
			world.player.position = Vector3(0, 0, 1)
			world.sim.bag[world.sim.pack.items[0].id] = 6
			for c in world.customers:
				c.node.position = world.visuals[c.shop].position + Vector3(2 + c.slot * .65, 0, 0)
			world.refresh()
	for n in range(12): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output)
	quit()
