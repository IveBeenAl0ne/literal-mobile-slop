extends SceneTree
func _initialize(): call_deferred("run")
func wait_for_refresh(hub):
	await process_frame
	var started = Time.get_ticks_msec()
	while (hub.refreshing or hub.loading_covers) and Time.get_ticks_msec() - started < 25000:
		await create_timer(.05).timeout
func run():
	var hub = Node.new()
	hub.set_script(load("res://scripts/hub.gd"))
	hub.catalog_endpoint = "http://127.0.0.1:18787"
	root.add_child(hub)
	await wait_for_refresh(hub)
	if hub.catalog.size() != 1 or hub.catalog[0].id != "download_test":
		push_error("Startup did not refresh the catalog: " + hub.status.text)
		quit(1)
		return
	if not hub.cover_textures.has("download_test"):
		push_error("Remote cover was not downloaded")
		quit(1)
		return
	if hub.search.placeholder_text != "Search games":
		quit(1)
		return
	await hub.download_pack(hub.catalog[0])
	if not hub.installed.has("download_test") or not FileAccess.file_exists("user://packs/download_test.json"):
		push_error("Pack not installed: " + hub.status.text)
		quit(1)
		return
	hub.load_installed()
	hub.play_pack("download_test")
	await process_frame
	if hub.world.sim.pack.id != "download_test":
		quit(1)
		return
	hub.world.save()
	hub.catalog = []
	hub.world.exit_requested.emit()
	await wait_for_refresh(hub)
	if hub.catalog.size() != 1:
		push_error("Returning to the library did not refresh the catalog")
		quit(1)
		return
	# The collection remains playable when the fixed endpoint is unavailable.
	hub.catalog_endpoint = "http://127.0.0.1:1"
	await hub.fetch_catalog()
	hub.load_installed()
	if not hub.installed.has("download_test") or hub.catalog.size() != 1:
		quit(1)
		return
	print("PASS: automatic startup/return refresh, static HTTP installation, offline catalog, and play")
	hub.queue_free()
	await process_frame
	quit(0)
