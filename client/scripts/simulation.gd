class_name TycoonSimulation
extends RefCounted

var pack: Dictionary
var cash: float
var bag: Dictionary = {}
var capacity = 12
var stations: Dictionary = {}
var earned = 0.0
var delivered = 0
var harvested = 0
var workers: Dictionary = {}
var external_actors = false
var capacity_level = 0
var speed_level = 0
signal activity(kind: String, station: String, item: String, amount: float)

func _init(definition: Dictionary):
	pack = definition
	cash = float(pack.starting_cash)
	for item in pack.items: bag[item.id] = 0
	for s in pack.stations:
		stations[s.id] = {"unlocked": s.cost == 0, "paid": 0.0, "stock": mini(3, int(s.capacity)) if s.kind == "source" and s.cost == 0 else 0, "input_stock": 0, "timer": 0.0, "pending_cash": 0.0, "level": 1}

func bag_count() -> int:
	var total = 0
	for amount in bag.values(): total += int(amount)
	return total

func available(s: Dictionary) -> bool:
	for dep in s.get("requires", []):
		if not stations[dep].unlocked: return false
	return true

func definition(id: String) -> Dictionary:
	for s in pack.stations:
		if s.id == id: return s
	return {}

func storage(id: String) -> int:
	var s = definition(id)
	return int(s.capacity) + 4 * (int(stations[id].level) - 1)

func interact(id: String, delta: float, action = "auto") -> String:
	var s = definition(id)
	if s.is_empty(): return ""
	var state: Dictionary = stations[id]
	if not state.unlocked:
		if not available(s): return "Unlock the previous station first"
		if cash <= 0: return "Collect cash from the counter to build"
		var amount = minf(cash, minf(s.cost - state.paid, maxf(25.0, s.cost * 0.9) * delta))
		state.paid += amount
		cash -= amount
		activity.emit("pay", id, "", amount)
		if state.paid >= s.cost:
			state.unlocked = true
			if s.kind == "source": state.stock = mini(3, storage(id))
			activity.emit("unlock", id, "", 0)
			return s.name + " unlocked!"
		return "Building " + s.name
	# Deliver inputs before collecting outputs. Separate world pads can request either action.
	if action in ["auto", "deliver"] and s.kind in ["processor", "shop"] and int(bag.get(s.input, 0)) > 0 and state.input_stock < storage(id):
		bag[s.input] -= 1
		state.input_stock += 1
		delivered += 1
		activity.emit("deliver", id, s.input, 1)
		return "Delivered " + s.input
	if action in ["auto", "collect"] and s.kind in ["source", "processor"] and state.stock > 0 and bag_count() < capacity:
		state.stock -= 1
		bag[s.output] = int(bag.get(s.output, 0)) + 1
		harvested += 1
		activity.emit("pickup", id, s.output, 1)
		return "+1 " + s.output
	if action in ["auto", "cash"] and s.kind == "shop" and state.pending_cash > 0:
		var amount = state.pending_cash
		cash += amount
		state.pending_cash = 0.0
		activity.emit("cash", id, "", amount)
		return "Collected $%d" % amount
	if s.kind == "worker": return "Helper supplies " + definition(s.target).name
	if action == "collect" and bag_count() >= capacity: return "Bag full · Deliver your items"
	return ""

func sell(id: String) -> bool:
	var s = definition(id)
	if s.is_empty() or s.kind != "shop": return false
	var state: Dictionary = stations[id]
	if not state.unlocked or state.input_stock <= 0: return false
	state.input_stock -= 1
	state.pending_cash += s.price
	earned += s.price
	activity.emit("sale", id, s.input, s.price)
	return true

func tick(delta: float):
	for s in pack.stations:
		var st: Dictionary = stations[s.id]
		if not st.unlocked: continue
		var cycle = float(s.cycle) / (1.0 + 0.3 * (int(st.level) - 1))
		st.timer += delta
		if st.timer < cycle: continue
		var cycles = mini(100, int(st.timer / cycle))
		st.timer = fmod(st.timer, cycle)
		for _iteration in range(cycles):
			if s.kind == "source" and st.stock < storage(s.id):
				st.stock += 1
				activity.emit("produce", s.id, s.output, 1)
			elif s.kind == "processor" and st.input_stock > 0 and st.stock < storage(s.id):
				st.input_stock -= 1
				st.stock += 1
				activity.emit("produce", s.id, s.output, 1)
			elif s.kind == "shop" and not external_actors:
				sell(s.id)
			elif s.kind == "worker" and not external_actors:
				var target = definition(s.target)
				if target.is_empty() or not stations[target.id].unlocked: continue
				var ts: Dictionary = stations[target.id]
				for source in pack.stations:
					var ss: Dictionary = stations[source.id]
					if source.get("output", "") == target.get("input", "?") and ss.unlocked and ss.stock > 0 and ts.input_stock < storage(target.id):
						ss.stock -= 1
						ts.input_stock += 1
						delivered += 1
						break

func upgrade_cost(kind: String, id = "") -> int:
	if kind == "bag": return 80 + capacity_level * 80
	if kind == "speed": return 100 + speed_level * 100
	return 100 * int(stations[id].level) if stations.has(id) else 0

func upgrade(kind: String, id = "") -> bool:
	if kind == "bag" and capacity_level >= 5: return false
	if kind == "speed" and speed_level >= 3: return false
	if kind == "station" and (not stations.has(id) or not stations[id].unlocked or stations[id].level >= 4): return false
	if not kind in ["bag", "speed", "station"]: return false
	var price = upgrade_cost(kind, id)
	if cash < price: return false
	cash -= price
	if kind == "bag":
		capacity_level += 1
		capacity = 12 + capacity_level * 4
	elif kind == "speed": speed_level += 1
	else: stations[id].level += 1
	activity.emit("upgrade", id, kind, price)
	return true

func objective() -> String:
	if earned == 0:
		if bag_count() == 0: return "Collect items from the green pickup zone"
		for s in pack.stations:
			if s.kind == "processor" and int(bag.get(s.input, 0)) > 0: return "Deliver to " + s.name + " · then collect the output"
		return "Stock the sales counter · Customers leave cash"
	for s in pack.stations:
		if not stations[s.id].unlocked and available(s):
			return "Build %s · $%d remaining" % [s.name, s.cost - stations[s.id].paid]
	return "Keep your business supplied · Earned $%d" % earned

func serialize() -> Dictionary:
	return {"capacity_level": capacity_level, "speed_level": speed_level, "schema": 1, "pack_id": pack.id, "cash": cash, "bag": bag, "stations": stations, "earned": earned, "delivered": delivered, "harvested": harvested}

func restore(data: Variant):
	if not data is Dictionary or data.get("schema") != 1 or data.get("pack_id") != pack.id: return
	capacity_level = clampi(int(data.get("capacity_level", 0)), 0, 5)
	speed_level = clampi(int(data.get("speed_level", 0)), 0, 3)
	capacity = 12 + capacity_level * 4
	cash = maxf(0, float(data.get("cash", cash)))
	earned = maxf(0, float(data.get("earned", 0)))
	delivered = int(data.get("delivered", 0))
	harvested = int(data.get("harvested", 0))
	for i in pack.items:
		bag[i.id] = clampi(int(data.get("bag", {}).get(i.id, 0)), 0, capacity)
	for id in stations:
		var old: Dictionary = data.get("stations", {}).get(id, {})
		for key in stations[id]:
			if old.has(key) and typeof(old[key]) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT]: stations[id][key] = old[key]
