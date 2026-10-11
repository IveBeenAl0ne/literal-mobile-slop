class_name TycoonPack
extends RefCounted

const MAX_BYTES = 1048576
const KINDS = ["source", "processor", "shop", "worker", "decoration"]

static func valid_id(value: Variant) -> bool:
	if not value is String or value.length() < 1 or value.length() > 48:
		return false
	for c in value:
		if not c in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			return false
	return true

static func number(v: Variant, lo: float, hi: float) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and v >= lo and v <= hi

static func validate(p: Variant) -> String:
	if not p is Dictionary:
		return "Pack must be an object."
	if p.get("format") != 1 or not valid_id(p.get("id")):
		return "Unsupported format or invalid ID."
	if not number(p.get("version"), 1, 1000000):
		return "Invalid version."
	for key in ["title", "description"]:
		if not p.get(key) is String or p[key].length() > 500:
			return "Missing or invalid " + key
	if not p.get("theme") is Dictionary:
		return "Missing theme."
	for key in ["ground", "accent", "player"]:
		if not p.theme.get(key) is String or not Color.html_is_valid(p.theme[key]):
			return "Invalid theme color."
	if not number(p.get("starting_cash"), 0, 1000000):
		return "Invalid starting cash."
	if not p.get("items") is Array or p.items.size() < 1 or p.items.size() > 32:
		return "Expected 1–32 items."
	var items: Array = []
	for i in p.items:
		if not i is Dictionary or not valid_id(i.get("id")) or i.id in items:
			return "Invalid or duplicate item."
		if not i.get("color") is String or not Color.html_is_valid(i.color):
			return "Invalid item color."
		items.append(i.id)
	if not p.get("stations") is Array or p.stations.size() < 1 or p.stations.size() > 100:
		return "Expected 1–100 stations."
	var ids: Array = []
	for s in p.stations:
		if not s is Dictionary or not valid_id(s.get("id")) or s.id in ids:
			return "Invalid or duplicate station."
		ids.append(s.id)
		if not s.get("kind") in KINDS or not s.get("name") is String or s.name.length() > 64:
			return "Invalid station kind/name."
		if not s.get("position") is Array or s.position.size() != 2:
			return "Invalid position."
		for n in s.position:
			if not number(n, -18, 18):
				return "Station outside map."
		for key in ["cost", "price", "capacity", "cycle"]:
			var lo = 0.2 if key == "cycle" else (1 if key == "capacity" else 0)
			if not number(s.get(key), lo, 1000000 if key != "capacity" else 100):
				return "Invalid station " + key
		if s.kind in ["source", "processor"] and not s.get("output") in items:
			return "Unknown output."
		if s.kind in ["processor", "shop"] and not s.get("input") in items:
			return "Unknown input."
		if not s.get("requires", []) is Array:
			return "Invalid prerequisites."
		if s.has("visual"):
			if not s.visual is Array or s.visual.size() > 64: return "Too many model parts."
			for part in s.visual:
				if not part is Dictionary or not part.get("shape") in ["box", "cylinder", "cone", "sphere"]: return "Invalid model shape."
				if not part.get("color") is String or not Color.html_is_valid(part.color): return "Invalid model color."
				for key in ["position", "size"]:
					if not part.get(key) is Array or part[key].size() != 3: return "Invalid model vector."
					for value in part[key]:
						if not number(value, -5 if key == "position" else 0.01, 5): return "Invalid model dimensions."
	for s in p.stations:
		for dep in s.get("requires", []):
			if dep not in ids or dep == s.id:
				return "Unknown or self prerequisite."
		if s.kind == "worker" and s.get("target") not in ids:
			return "Worker needs a valid target."
	# A dependency graph must be acyclic.
	var visited: Array = []
	for iteration in range(ids.size()):
		for s in p.stations:
			if s.id not in visited:
				var ready = true
				for dep in s.get("requires", []):
					if dep not in visited: ready = false
				if ready: visited.append(s.id)
	if visited.size() != ids.size():
		return "Circular prerequisites."
	return ""

static func parse_bytes(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() > MAX_BYTES:
		return {}
	var p = JSON.parse_string(bytes.get_string_from_utf8())
	return p if validate(p).is_empty() else {}
