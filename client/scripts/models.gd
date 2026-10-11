class_name TycoonModels
extends RefCounted

const STATIONS = ["tomato_plot", "orchard_tree", "ingredient_pallet", "coffee_delivery", "scrap_bin", "donut_fryer", "chocolate_glazer", "coffee_roaster", "juice_press", "recycler", "market_stall", "coffee_counter", "bakery_counter", "parts_counter", "table_set", "staff_locker", "planter", "shade_tree", "delivery_van"]
const ITEMS = ["tomato", "apple", "beans", "dough", "coffee", "juice", "scrap", "parts", "donut", "chocolate_donut", "cash_bundle"]
const SETTINGS = ["farm", "orchard", "cafe", "bakery", "depot"]
static var scenes: Dictionary = {}
static var shirts: Dictionary = {}

static func create(id: String) -> Node3D:
	if not id in STATIONS and not id in ITEMS and id != "character": return null
	if not scenes.has(id): scenes[id] = load("res://assets/models/" + id + ".glb")
	return scenes[id].instantiate()

static func station(s: Dictionary, setting: String) -> String:
	if not s.get("model", "").is_empty(): return s.model
	match s.kind:
		"source": return {"farm":"tomato_plot", "orchard":"orchard_tree", "cafe":"coffee_delivery", "bakery":"ingredient_pallet", "depot":"scrap_bin"}.get(setting, "tomato_plot")
		"processor": return {"cafe":"coffee_roaster", "bakery":"donut_fryer", "depot":"recycler"}.get(setting, "juice_press")
		"shop": return {"cafe":"coffee_counter", "bakery":"bakery_counter", "depot":"parts_counter"}.get(setting, "market_stall")
		"worker": return "staff_locker"
	return "table_set"

static func dress(node: Node, color: Color):
	if node is MeshInstance3D:
		for i in node.mesh.get_surface_count():
			var original = node.mesh.surface_get_material(i)
			if original and original.resource_name == "Shirt":
				var key = color.to_html()
				if not shirts.has(key):
					var tinted = original.duplicate()
					tinted.albedo_color = color
					shirts[key] = tinted
				node.set_surface_override_material(i, shirts[key])
	for child in node.get_children(): dress(child, color)
