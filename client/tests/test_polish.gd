extends SceneTree
var failures = 0
func _initialize(): call_deferred("run")
func check(condition: bool, message: String):
	if not condition: push_error(message); failures += 1
func run():
	var p = TycoonPack.parse_bytes(FileAccess.get_file_as_bytes("res://packs/donut_studio.json"))
	check(not p.is_empty(), "Donut pack validates")
	var sim = TycoonSimulation.new(p)
	# Both an output and an ingredient exist: supply must win in automatic interaction.
	sim.stations.oven.stock = 1
	sim.bag.dough = 1
	sim.interact("oven", .2)
	check(sim.stations.oven.input_stock == 1 and sim.bag.dough == 0, "Processor accepts ingredients before collecting output")
	sim.interact("oven", .2, "collect")
	check(sim.bag.donut == 1, "Output zone collects a donut")
	sim.interact("counter", .2, "deliver")
	sim.external_actors = true
	sim.tick(10)
	check(sim.stations.counter.pending_cash == 0, "A shop cannot sell before a customer arrives")
	check(sim.sell("counter"), "Customer purchases available stock")
	check(not sim.sell("counter"), "Empty counter cannot sell")
	sim.cash = 1000
	check(sim.upgrade("bag") and sim.capacity == 16, "Bag upgrade increases capacity")
	check(sim.upgrade("speed") and sim.speed_level == 1, "Speed upgrade purchased")
	check(sim.upgrade("station", "oven") and sim.storage("oven") == 16, "Station upgrade increases storage")
	var restored = TycoonSimulation.new(p)
	restored.restore(sim.serialize())
	check(restored.capacity == 16 and restored.speed_level == 1 and restored.stations.oven.level == 2, "Upgrades survive saving")
	var world = Node3D.new()
	world.set_script(load("res://scripts/world.gd"))
	world.preview_mode = true
	world.setup(p)
	root.add_child(world)
	for s in p.stations: world.sim.stations[s.id].unlocked = true
	world.sim.stations.counter.input_stock = 6
	for n in range(700): world.update_customers(.05)
	check(world.sim.stations.counter.pending_cash > 0, "Arriving customers generate real sales")
	check(world.sim.stations.counter.input_stock < 6, "Customers consume stocked donuts")
	world.sim.stations.dough.stock = 12
	world.sim.stations.oven.input_stock = 0
	for n in range(900): world.update_helpers(.05)
	check(world.sim.stations.oven.input_stock > 0, "Visible baker transports ingredients to oven")
	check(world.sim.delivered > 0, "Helper deliveries are counted")
	check(world.zones.size() > p.stations.size(), "Separate pickup, supply, cash, and build zones")
	world.queue_free()
	await process_frame
	if failures == 0: print("PASS: processor priorities, customer-driven sales, walking helpers, and persistent upgrades")
	quit(1 if failures > 0 else 0)
