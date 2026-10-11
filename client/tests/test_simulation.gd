extends SceneTree
var failures = 0

func _initialize():
	call_deferred("run")

func check(condition: bool, message: String):
	if not condition:
		push_error(message)
		failures += 1

func run():
	for id in ["sunny_farm", "corner_cafe", "dusty_depot"]:
		var p = TycoonPack.parse_bytes(FileAccess.get_file_as_bytes("res://packs/%s.json" % id))
		check(not p.is_empty(), "Valid starter pack " + id)
		var model = TycoonSimulation.new(p)
		model.tick(2.1)
		var source: Dictionary = p.stations[0]
		model.interact(source.id, 0.2)
		check(model.bag_count() == 1, "Harvest adds to bag")
		var target: Dictionary = p.stations[1]
		model.interact(target.id, 0.2)
		check(model.bag_count() == 0, "Delivery removes from bag")
		check(model.stations[target.id].input_stock == 1, "Delivery adds stock")
		model.tick(2.1)
		if target.kind == "shop":
			check(model.stations[target.id].pending_cash == target.price, "Sale creates cash")
			model.interact(target.id, 0.2)
			check(model.cash == p.starting_cash + target.price, "Collect sale")
		else:
			check(model.stations[target.id].stock == 1, "Processor produces output")
		var restored = TycoonSimulation.new(p)
		restored.restore(model.serialize())
		check(restored.serialize() == model.serialize(), "Save round trip")
	var farm = TycoonPack.parse_bytes(FileAccess.get_file_as_bytes("res://packs/sunny_farm.json"))
	var sim = TycoonSimulation.new(farm)
	sim.cash = 10
	sim.interact("orchard", 1)
	check(sim.cash == 0 and sim.stations.orchard.paid == 10 and not sim.stations.orchard.unlocked, "Partial purchase")
	sim.cash = 100
	sim.interact("orchard", 10)
	check(sim.stations.orchard.unlocked and sim.cash == 30, "Finish partial purchase")
	sim.interact("helper", 10)
	check(not sim.stations.helper.unlocked, "Cannot unlock without enough cash")
	sim.cash = 1000
	sim.interact("helper", 10)
	sim.stations.patch.stock = 3
	sim.tick(2)
	check(sim.stations.market.input_stock > 0, "Helper supplies assigned shop")
	var bad = farm.duplicate(true)
	bad.id = "../evil"
	check(not TycoonPack.validate(bad).is_empty(), "Reject traversal")
	bad = farm.duplicate(true)
	bad.stations[0].requires = ["market"]
	bad.stations[1].requires = ["patch"]
	check(not TycoonPack.validate(bad).is_empty(), "Reject dependency cycle")
	if failures == 0: print("PASS: all simulation, save, purchase, helper, and validation checks")
	quit(1 if failures > 0 else 0)
