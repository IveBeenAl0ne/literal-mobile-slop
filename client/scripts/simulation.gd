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

func _init(definition: Dictionary):
	pack = definition
	cash = float(pack.starting_cash)
	for item in pack.items: bag[item.id] = 0
	for s in pack.stations:
		stations[s.id] = {"unlocked": s.cost == 0, "paid": 0.0, "stock": 0, "input_stock": 0, "timer": 0.0, "pending_cash": 0.0, "level": 1}

func bag_count() -> int:
	var total = 0
	for amount in bag.values(): total += int(amount)
	return total

func available(s: Dictionary) -> bool:
	for dep in s.get("requires", []):
		if not stations[dep].unlocked: return false
	return true

func interact(id: String, delta: float) -> String:
	var s: Dictionary = {}
	for candidate in pack.stations:
		if candidate.id == id: s = candidate
	if s.is_empty(): return ""
	var state: Dictionary = stations[id]
	if not state.unlocked:
		if not available(s): return "Unlock the previous station first"
		var amount = minf(cash, minf(s.cost - state.paid, maxf(10.0, s.cost * 0.8) * delta))
		state.paid += amount
		cash -= amount
		if state.paid >= s.cost:
			state.unlocked = true
			return s.name + " unlocked!"
		return "Building " + s.name
	if s.kind in ["source", "processor"] and state.stock > 0 and bag_count() < capacity:
		state.stock -= 1
		bag[s.output] = int(bag.get(s.output, 0)) + 1
		harvested += 1
		return "+1 " + s.output
	if s.kind in ["processor", "shop"] and int(bag.get(s.input, 0)) > 0 and state.input_stock < s.capacity:
		bag[s.input] -= 1
		state.input_stock += 1
		delivered += 1
		return "Delivered " + s.input
	if s.kind == "shop" and state.pending_cash > 0:
		var amount = state.pending_cash
		cash += amount
		state.pending_cash = 0.0
		return "Collected $%d" % amount
	if s.kind == "worker": return "Helper is delivering automatically"
	return "Bag full" if bag_count() >= capacity else ""

func tick(delta: float):
	for s in pack.stations:
		var st: Dictionary = stations[s.id]
		if not st.unlocked: continue
		st.timer += delta
		if st.timer < s.cycle: continue
		st.timer = fmod(st.timer, s.cycle)
		if s.kind == "source" and st.stock < s.capacity:
			st.stock += 1
		elif s.kind == "processor" and st.input_stock > 0 and st.stock < s.capacity:
			st.input_stock -= 1
			st.stock += 1
		elif s.kind == "shop" and st.input_stock > 0:
			st.input_stock -= 1
			st.pending_cash += s.price
			earned += s.price
		elif s.kind == "worker":
			var target: Dictionary = {}
			for t in pack.stations:
				if t.id == s.target: target = t
			if target.is_empty() or not stations[target.id].unlocked: continue
			var ts: Dictionary = stations[target.id]
			for source in pack.stations:
				var ss: Dictionary = stations[source.id]
				if source.get("output", "") == target.get("input", "?") and ss.unlocked and ss.stock > 0 and ts.input_stock < target.capacity:
					ss.stock -= 1
					ts.input_stock += 1
					delivered += 1
					break

func objective() -> String:
	for s in pack.stations:
		if not stations[s.id].unlocked and available(s):
			return "Build %s · $%d remaining" % [s.name, s.cost - stations[s.id].paid]
	return "Keep your business supplied · Earned $%d" % earned

func serialize() -> Dictionary:
	return {"schema": 1, "pack_id": pack.id, "cash": cash, "bag": bag, "stations": stations, "earned": earned, "delivered": delivered, "harvested": harvested}

func restore(data: Variant):
	if not data is Dictionary or data.get("schema") != 1 or data.get("pack_id") != pack.id: return
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
