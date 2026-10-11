extends SceneTree
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	if not ok: push_error(message); failures += 1
func run():
	for id in TycoonModels.STATIONS + TycoonModels.ITEMS + ["character"]:
		var model = TycoonModels.create(id)
		check(model != null, "Model imports: " + id)
		model.free()
	check(TycoonModels.create("../../outside") == null, "Asset paths are allowlisted")
	for id in ["sunny_farm", "apple_orchard", "corner_cafe", "donut_studio", "dusty_depot"]:
		var p = TycoonPack.parse_bytes(FileAccess.get_file_as_bytes("res://packs/%s.json" % id))
		check(not p.is_empty(), "Pack validates: " + id)
		var world = Node3D.new()
		world.set_script(load("res://scripts/world.gd"))
		world.preview_mode = true
		world.setup(p)
		for station in p.stations: world.sim.stations[station.id].unlocked = true
		root.add_child(world)
		world.animate_walk(world.avatar, 1, 1)
		check(world.avatar.find_child("Left", true, false).rotation.x != 0, "Character has animated hip rig")
		for station in p.stations:
			var props = world.visuals[station.id].get_node("Props")
			check(props.get_child_count() == 1, "Station uses authored model")
			if station.kind in ["source", "processor", "shop"]:
				check(props.find_child("StockAnchor", true, false) != null, "Stock has model display anchor")
		world.queue_free()
		await process_frame
	if failures == 0: print("PASS: all authored assets import, five themed worlds use models, characters animate, asset IDs are bounded")
	quit(0 if failures == 0 else 1)
