extends SceneTree
func _initialize(): call_deferred("run")
func run():
	var hub = Node.new()
	hub.set_script(load("res://scripts/hub.gd"))
	root.add_child(hub)
	hub.url.text = "http://127.0.0.1:18787"
	await hub.fetch_catalog()
	if hub.catalog.size() != 1:
		push_error("Catalog should contain test pack: " + hub.status.text)
		quit(1)
		return
	await hub.download_pack(hub.catalog[0])
	if not hub.installed.has("download_test") or not FileAccess.file_exists("user://packs/download_test.json"):
		push_error("Pack not installed: " + hub.status.text)
		quit(1)
		return
	hub.load_installed()
	if not hub.installed.has("download_test"):
		quit(1)
		return
	hub.play_pack("download_test")
	await process_frame
	if hub.world.sim.pack.id != "download_test":
		quit(1)
		return
	hub.world.save()
	print("PASS: real HTTP catalog, hash verification, installation, offline reload, and play")
	hub.queue_free()
	await process_frame
	quit(0)
