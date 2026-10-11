extends SceneTree
var world
func _initialize(): call_deferred("run")
func run():
	world = Node3D.new()
	world.set_script(load("res://scripts/world.gd"))
	var pack = TycoonPack.parse_bytes(FileAccess.get_file_as_bytes("res://packs/sunny_farm.json"))
	pack.stations[0].visual = [{"shape": "cone", "position": [0, 0.5, 0], "size": [1, 1, 1], "color": "49b98b"}]
	world.setup(pack)
	root.add_child(world)
	await process_frame
	await process_frame
	if world.player == null or world.visuals.size() != 6:
		quit(1)
		return
	world.player.position = Vector3(-4, 0, 3.3)
	for n in range(150): await physics_frame
	if world.sim.bag_count() <= 0:
		quit(1)
		return
	world.save()
	print("PASS: native world instantiation, gameplay, and save")
	world.queue_free()
	await process_frame
	quit(0)
