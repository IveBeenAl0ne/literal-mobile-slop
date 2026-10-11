extends Node3D

signal exit_requested
var sim: TycoonSimulation
var player: CharacterBody3D
var avatar: Node3D
var camera: Camera3D
var visuals: Dictionary = {}
var labels: Dictionary = {}
var zones: Array = []
var stack: Node3D
var hud: Label
var task: Label
var toast: Label
var stick: Control
var ui_root: Control
var progress: ProgressBar
var upgrade_panel: PanelContainer
var timer = 0.0
var save_timer = 0.0
var gait = 0.0
var last_count = -1
var customers: Array = []
var customer_ticket = 100
var helpers: Array = []
var stock_signatures: Dictionary = {}
var rng = RandomNumberGenerator.new()
var highlighted = ""
var goal_arrow: Node3D
var toast_time = 0.0
var sound_on = true
var sounds: Array = []
var effect_count = 0
var preview_mode = false
var themed = "farm"

func setup(pack: Dictionary):
	sim = TycoonSimulation.new(pack)
	sim.external_actors = true
	if pack.id in ["corner_cafe", "donut_studio"]: themed = "cafe"
	elif pack.id == "dusty_depot": themed = "depot"
	var path = "user://saves/%s.json" % pack.id
	if not preview_mode and FileAccess.file_exists(path): sim.restore(JSON.parse_string(FileAccess.get_file_as_string(path)))

func _ready():
	rng.seed = hash(sim.pack.id)
	var environment = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("b6d9ea")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff4e5")
	env.ambient_light_energy = 0.12
	environment.environment = env
	add_child(environment)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, -25, 0)
	sun.light_energy = 0.32
	sun.shadow_enabled = true
	add_child(sun)
	build_ground()
	for s in sim.pack.stations:
		var station_root = Node3D.new()
		station_root.position = Vector3(s.position[0], 0, s.position[1])
		add_child(station_root)
		visuals[s.id] = station_root
		var pad = cylinder(station_root, Vector3(0, 0.035, 0.6), 1.15, 0.035, Color("5cce95"))
		pad.name = "Pad"
		var marker = make_label(station_root, Vector3(0, 0.12, 0.9), "", 40)
		marker.rotation_degrees.x = -70
		marker.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		marker.name = "Price"
		var title = make_label(station_root, Vector3(0, 3.05, 0), s.name, 28)
		labels[s.id] = title
		build_station(s)
		var stock_root = Node3D.new()
		stock_root.name = "Stock"
		station_root.add_child(stock_root)
		var cash_root = Node3D.new()
		cash_root.name = "Cash"
		station_root.add_child(cash_root)
		if s.kind in ["source", "processor"]: add_zone(s.id, "collect", Vector3(1.5, 0, 0.8) if s.kind == "processor" else Vector3(0, 0, 1.55), Color("59c68e"), "PICK UP")
		if s.kind in ["processor", "shop"]: add_zone(s.id, "deliver", Vector3(-1.5, 0, 0.5), Color("5aacec"), "SUPPLY")
		if s.kind == "shop": add_zone(s.id, "cash", Vector3(0, 0, 1.9), Color("f6c659"), "CASH")
		add_zone(s.id, "build", Vector3(0, 0, 0.7), Color("59c68e"), "BUILD")
	player = CharacterBody3D.new()
	player.position = Vector3(0, 0, 6)
	var collision = CollisionShape3D.new()
	var shape = CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 1.4
	collision.shape = shape
	collision.position.y = 0.7
	player.add_child(collision)
	add_child(player)
	avatar = character(player, Color(sim.pack.theme.player))
	stack = Node3D.new()
	stack.position = Vector3(0, 1.05, 0.48)
	avatar.add_child(stack)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 22
	add_child(camera)
	camera.position = player.position + Vector3(0, 18, 9)
	camera.look_at(player.position + Vector3(0, 0, -3))
	create_ui()
	goal_arrow = Node3D.new()
	add_child(goal_arrow)
	var arrow_mesh = MeshInstance3D.new()
	var arrow = ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-.13, 0, .3), Vector3(.13, 0, .3), Vector3(.13, 0, -.15), Vector3(-.13, 0, .3), Vector3(.13, 0, -.15), Vector3(-.13, 0, -.15), Vector3(-.35, 0, -.15), Vector3(.35, 0, -.15), Vector3(0, 0, -.65)])
	arrow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	arrow_mesh.mesh = arrow
	var arrow_material = material(Color("f9eea7"))
	arrow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	arrow_mesh.material_override = arrow_material
	goal_arrow.add_child(arrow_mesh)
	for _n in range(4):
		var audio = AudioStreamPlayer.new()
		audio.volume_db = -18
		add_child(audio)
		sounds.append(audio)
	for s in sim.pack.stations:
		if s.kind == "shop":
			for n in range(3):
				var actor = Node3D.new()
				add_child(actor)
				var body = character(actor, Color.from_hsv(rng.randf(), 0.48, 0.85))
				actor.position = visuals[s.id].position + Vector3(6, 0, 6 + n)
				customers.append({"node": actor, "avatar": body, "shop": s.id, "slot": n, "ticket": n, "phase": "arriving", "wait": 0.0, "gait": 0.0})
		if s.kind == "worker":
			var actor = Node3D.new()
			add_child(actor)
			actor.position = visuals[s.id].position + Vector3(0, 0, 1.5)
			var body = character(actor, Color(sim.pack.theme.accent))
			var carrying = Node3D.new()
			carrying.position = Vector3(0, 1, 0.45)
			body.add_child(carrying)
			helpers.append({"id": s.id, "node": actor, "avatar": body, "stack": carrying, "item": "", "amount": 0, "source": "", "gait": 0.0, "route": []})
	sim.activity.connect(on_activity)
	refresh()

func material(color: Color) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.88
	return m

func box(parent: Node, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh = MeshInstance3D.new()
	var shape = BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = material(color)
	mesh.position = pos
	parent.add_child(mesh)
	return mesh

func cylinder(parent: Node, pos: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var mesh = MeshInstance3D.new()
	var shape = CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 16
	mesh.mesh = shape
	mesh.material_override = material(color)
	mesh.position = pos
	parent.add_child(mesh)
	return mesh

func sphere(parent: Node, pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mesh = MeshInstance3D.new()
	var shape = SphereMesh.new()
	shape.radius = radius
	shape.height = radius * 2
	shape.radial_segments = 16
	shape.rings = 8
	mesh.mesh = shape
	mesh.material_override = material(color)
	mesh.position = pos
	parent.add_child(mesh)
	return mesh

func make_label(parent: Node, pos: Vector3, text_value: String, font_size: int) -> Label3D:
	var node = Label3D.new()
	node.text = text_value
	node.font_size = font_size
	node.pixel_size = 0.011
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.outline_size = 7
	node.position = pos
	parent.add_child(node)
	return node

func barrier(pos: Vector3, size: Vector3):
	var body = StaticBody3D.new()
	body.position = pos
	add_child(body)
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	return body

func build_ground():
	box(self, Vector3(0, -0.22, -2), Vector3(32, 0.4, 36), Color(sim.pack.theme.ground))
	box(self, Vector3(0, 0.01, -2), Vector3(3.3, 0.025, 33), Color("e8dbc0") if themed == "farm" else Color("ece4d9"))
	for x in [-16.0, 16.0]: barrier(Vector3(x, 0.5, -2), Vector3(0.5, 1, 36))
	for z in [-20.0, 16.0]: barrier(Vector3(0, 0.5, z), Vector3(32, 1, 0.5))
	if themed == "cafe":
		for x in range(-6, 7):
			for z in range(-9, 5):
				box(self, Vector3(x * 2.0, 0.025, z * 2.0), Vector3(1.96, 0.025, 1.96), Color("f0e9dc") if (x + z) % 2 == 0 else Color("e6dccb"))
		box(self, Vector3(-12, 1, -4), Vector3(0.2, 2, 28), Color("92b7b8"))
		box(self, Vector3(0, 1, -18), Vector3(24, 2, 0.2), Color("92b7b8"))
		make_label(self, Vector3(0, 3.2, -17.8), sim.pack.title.to_upper(), 60)
		for z in [-6, 0, 6]: seating(self, Vector3(9.5, 0, z))
	else:
		for z in range(-18, 17, 3):
			for x in [-13.0, 13.0]:
				box(self, Vector3(x, 0.6, z), Vector3(0.13, 1.2, 0.13), Color("bc8959"))
				box(self, Vector3(x, 0.65, z + 1.5), Vector3(0.12, 0.15, 3), Color("d6a069"))
		for n in range(18):
			var pos = Vector3(rng.randf_range(13.8, 15.2) * (-1 if n % 2 else 1), 0, rng.randf_range(-18, 14))
			tree(pos)
		if themed == "depot":
			for z in range(-14, 11, 4):
				box(self, Vector3(10, 0.5, z), Vector3(3, 1, 1.5), Color("6a8791"))
				box(self, Vector3(10, 1.25, z), Vector3(2.8, 0.5, 1.4), Color("d5aa68"))

func seating(parent: Node, pos: Vector3):
	cylinder(parent, pos + Vector3(0, 0.7, 0), 0.8, 0.15, Color("e5bb85"))
	cylinder(parent, pos + Vector3(0, 0.35, 0), 0.14, 0.7, Color("5f6976"))
	for x in [-1.2, 1.2]:
		box(parent, pos + Vector3(x, 0.4, 0), Vector3(0.65, 0.12, 0.65), Color("e88881"))
		box(parent, pos + Vector3(x, 0.75, 0.3), Vector3(0.65, 0.65, 0.12), Color("e88881"))
		for offset in [-0.22, 0.22]: box(parent, pos + Vector3(x + offset, 0.2, 0), Vector3(0.08, 0.4, 0.5), Color("5f6976"))

func tree(pos: Vector3):
	cylinder(self, pos + Vector3(0, 0.9, 0), 0.16, 1.8, Color("805743"))
	sphere(self, pos + Vector3(0, 2.2, 0), 1.05, Color("76b866"))
	sphere(self, pos + Vector3(0.5, 1.9, 0.2), 0.7, Color("88c36d"))

func character(parent: Node3D, color: Color) -> Node3D:
	var node = Node3D.new()
	parent.add_child(node)
	cylinder(node, Vector3(0, 0.75, 0), 0.28, 0.55, color)
	sphere(node, Vector3(0, 1.24, 0), 0.3, Color("ffcfaa"))
	var hair = sphere(node, Vector3(0, 1.38, 0.04), 0.28, color.darkened(0.5))
	hair.scale.y = 0.65
	for x in [-0.095, 0.095]: sphere(node, Vector3(x, 1.26, -0.27), 0.035, Color("263644"))
	for x in [-0.15, 0.15]:
		var foot = cylinder(node, Vector3(x, 0.23, 0), 0.12, 0.45, Color("36465d"))
		foot.name = "Left" if x < 0 else "Right"
		box(node, Vector3(x, 0.045, -0.06), Vector3(0.23, 0.09, 0.35), Color("253348"))
	for x in [-0.36, 0.36]:
		cylinder(node, Vector3(x, 0.77, 0), 0.09, 0.42, color)
		sphere(node, Vector3(x, 0.55, 0), 0.1, Color("ffcfaa"))
	return node

func build_station(s: Dictionary):
	var station_root: Node3D = visuals[s.id]
	var props = Node3D.new()
	props.name = "Props"
	station_root.add_child(props)
	var accent = Color(sim.pack.theme.accent)
	if s.has("visual"):
		for part in s.visual:
			var pos = Vector3(part.position[0], part.position[1], part.position[2])
			var dimensions = Vector3(part.size[0], part.size[1], part.size[2])
			var color = Color(part.color)
			if part.shape == "box": box(props, pos, dimensions, color)
			elif part.shape in ["cylinder", "cone"]:
				var piece = cylinder(props, pos, dimensions.x * 0.5, dimensions.y, color)
				piece.scale.z = dimensions.z / dimensions.x
				if part.shape == "cone": (piece.mesh as CylinderMesh).top_radius = 0
			else:
				var piece = sphere(props, pos, dimensions.x * 0.5, color)
				piece.scale = Vector3(1, dimensions.y / dimensions.x, dimensions.z / dimensions.x)
	elif s.kind == "source":
		if themed == "farm":
			box(props, Vector3(0, 0.12, 0), Vector3(2.5, 0.24, 1.8), Color("996b49"))
			for x in [-0.85, 0, 0.85]:
				cylinder(props, Vector3(x, 0.45, 0), 0.075, 0.65, Color("619b44"))
				var leaf = sphere(props, Vector3(x, 0.7, 0), 0.42, Color("70b354"))
				leaf.scale = Vector3(0.75, 1.15, 0.55)
		else:
			box(props, Vector3(0, 0.25, 0), Vector3(2.1, 0.5, 1.2), Color("b78757"))
			for x in [-0.9, 0.9]: box(props, Vector3(x, 0.75, 0), Vector3(0.12, 1.5, 1.3), Color("7c7469"))
			for y in [0.65, 1.3]: box(props, Vector3(0, y, 0), Vector3(2, 0.1, 1.2), Color("ede3cc"))
	elif s.kind == "processor":
		box(props, Vector3(0, 0.55, 0), Vector3(1.8, 1.1, 1.25), accent)
		box(props, Vector3(0, 1.13, 0), Vector3(2.1, 0.15, 1.45), Color("f4eee5"))
		box(props, Vector3(0, 0.65, 0.64), Vector3(1.25, 0.45, 0.06), Color("374453"))
		for x in [-0.45, 0.45]: cylinder(props, Vector3(x, 1.3, 0), 0.27, 0.25, Color("657381"))
		var spinner = cylinder(props, Vector3(0, 1.55, 0), 0.48, 0.1, Color("eac174"))
		spinner.name = "Spinner"
		box(spinner, Vector3(0, 0.08, 0), Vector3(0.65, 0.1, 0.12), Color("fff8df"))
	elif s.kind == "shop":
		box(props, Vector3(0, 0.52, 0), Vector3(2.4, 1.04, 1.15), Color("f1ddbe"))
		box(props, Vector3(0, 1.1, 0), Vector3(2.65, 0.15, 1.4), accent)
		box(props, Vector3(0.8, 1.3, 0), Vector3(0.5, 0.3, 0.45), Color("556577"))
		var screen = box(props, Vector3(0.8, 1.55, -0.08), Vector3(0.55, 0.35, 0.06), Color("364452"))
		screen.rotation_degrees.x = -18
		box(props, Vector3(0.8, 1.55, -0.12), Vector3(0.4, 0.2, 0.01), Color("8dddb7"))
		if themed == "farm":
			for x in [-1.12, 1.12]: cylinder(props, Vector3(x, 1.45, -0.45), 0.055, 2.9, Color("99734d"))
			for n in range(6): box(props, Vector3(-1.1 + n * 0.44, 2.9, 0), Vector3(0.44, 0.15, 1.8), accent if n % 2 else Color("fff1d2"))
	elif s.kind == "worker":
		box(props, Vector3(0, 0.08, 0), Vector3(1.7, 0.16, 1.2), accent)
		make_label(props, Vector3(0, 0.55, 0), "HELPER", 30)
	else: seating(props, Vector3.ZERO)
	var blocker = barrier(station_root.position + Vector3(0, 0.6, 0), Vector3(2.1, 1.2, 1.1))
	blocker.name = "Blocker_" + s.id
	# Locked blueprints have no collision until they are built.
	blocker.get_child(0).disabled = not sim.stations[s.id].unlocked or s.kind == "worker"

func add_zone(id: String, action: String, offset: Vector3, color: Color, caption: String):
	var node = Node3D.new()
	visuals[id].add_child(node)
	node.position = offset
	for x in [-0.53, 0.53]: box(node, Vector3(x, 0.045, 0), Vector3(0.065, 0.025, 1.0), color)
	for z in [-0.5, 0.5]: box(node, Vector3(0, 0.045, z), Vector3(1.1, 0.025, 0.065), color)
	var caption_node = make_label(node, Vector3(0, 0.13, 0.1), caption, 24)
	caption_node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	zones.append({"id": id, "action": action, "node": node})

func item_color(id: String) -> Color:
	for i in sim.pack.items:
		if i.id == id: return Color(i.color)
	return Color.WHITE

func item(parent: Node, pos: Vector3, id: String) -> Node3D:
	var node = Node3D.new()
	node.position = pos
	parent.add_child(node)
	if "donut" in id:
		var mesh = MeshInstance3D.new()
		var shape = TorusMesh.new()
		shape.inner_radius = 0.12
		shape.outer_radius = 0.26
		shape.rings = 16
		shape.ring_segments = 8
		mesh.mesh = shape
		mesh.material_override = material(item_color(id))
		node.add_child(mesh)
	elif id in ["coffee", "juice"]:
		cylinder(node, Vector3(0, 0.12, 0), 0.16, 0.28, item_color(id))
		cylinder(node, Vector3(0, 0.28, 0), 0.17, 0.05, Color("fff1dc"))
	elif id in ["tomato", "apple"]:
		sphere(node, Vector3.ZERO, 0.2, item_color(id))
		box(node, Vector3(0, 0.19, 0), Vector3(0.04, 0.1, 0.04), Color("647b43"))
	else: box(node, Vector3.ZERO, Vector3(0.4, 0.19, 0.3), item_color(id))
	return node

func clear_children(node: Node):
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func create_ui():
	var layer = CanvasLayer.new()
	add_child(layer)
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui_root)
	var back = hud_button("‹", Rect2(18, 32, 48, 48), func(): save(); exit_requested.emit())
	back.add_theme_font_size_override("font_size", 32)
	hud = Label.new()
	hud.position = Vector2(300, 36)
	hud.size = Vector2(220, 44)
	hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_theme_font_size_override("font_size", 30)
	hud.add_theme_color_override("font_outline_color", Color("314351"))
	hud.add_theme_constant_override("outline_size", 8)
	ui_root.add_child(hud)
	var task_panel = PanelContainer.new()
	task_panel.position = Vector2(18, 94)
	task_panel.size = Vector2(504, 62)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.99, 0.98, 0.94, 0.94)
	style.set_corner_radius_all(18)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	task_panel.add_theme_stylebox_override("panel", style)
	ui_root.add_child(task_panel)
	task = Label.new()
	task.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	task.add_theme_color_override("font_color", Color("35495b"))
	task.add_theme_font_size_override("font_size", 18)
	task_panel.add_child(task)
	progress = ProgressBar.new()
	progress.position = Vector2(26, 162)
	progress.size = Vector2(488, 8)
	progress.show_percentage = false
	progress.add_theme_font_size_override("font_size", 1)
	var track_style = StyleBoxFlat.new()
	track_style.bg_color = Color(0.2, 0.3, 0.3, 0.18)
	track_style.set_corner_radius_all(4)
	progress.add_theme_stylebox_override("background", track_style)
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = Color("66b89b")
	fill_style.set_corner_radius_all(4)
	progress.add_theme_stylebox_override("fill", fill_style)
	ui_root.add_child(progress)
	toast = Label.new()
	toast.position = Vector2(40, 760)
	toast.size = Vector2(460, 34)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 20)
	toast.add_theme_color_override("font_outline_color", Color("314351"))
	toast.add_theme_constant_override("outline_size", 7)
	ui_root.add_child(toast)
	stick = Control.new()
	stick.set_script(load("res://scripts/joystick.gd"))
	stick.position = Vector2(16, 758)
	stick.size = Vector2(180, 180)
	ui_root.add_child(stick)
	hud_button("Upgrades", Rect2(350, 844, 172, 52), show_upgrades)
	var bag_label = Label.new()
	bag_label.name = "Bag"
	bag_label.position = Vector2(350, 900)
	bag_label.size = Vector2(172, 36)
	bag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bag_label.add_theme_font_size_override("font_size", 19)
	bag_label.add_theme_color_override("font_outline_color", Color("314351"))
	bag_label.add_theme_constant_override("outline_size", 6)
	ui_root.add_child(bag_label)
	hud_button("Sound", Rect2(78, 32, 78, 48), func(): sound_on = not sound_on)

func hud_button(caption: String, bounds: Rect2, callback: Callable) -> Button:
	var node = Button.new()
	node.text = caption
	node.position = bounds.position
	node.size = bounds.size
	node.add_theme_font_size_override("font_size", 18)
	var style = StyleBoxFlat.new()
	style.bg_color = Color("fff5df")
	style.set_corner_radius_all(15)
	node.add_theme_stylebox_override("normal", style)
	node.add_theme_color_override("font_color", Color("35495b"))
	node.pressed.connect(callback)
	ui_root.add_child(node)
	return node

func show_upgrades():
	if is_instance_valid(upgrade_panel): upgrade_panel.queue_free(); upgrade_panel = null; return
	stick.release()
	upgrade_panel = PanelContainer.new()
	upgrade_panel.position = Vector2(30, 275)
	upgrade_panel.size = Vector2(480, 310)
	var style = StyleBoxFlat.new()
	style.bg_color = Color("fff7e8")
	style.set_corner_radius_all(24)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	upgrade_panel.add_theme_stylebox_override("panel", style)
	ui_root.add_child(upgrade_panel)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	upgrade_panel.add_child(column)
	var title = Label.new()
	title.text = "Grow your business"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("35495b"))
	column.add_child(title)
	for kind in ["bag", "speed"]:
		var key: String = kind
		var maxed: bool = sim.capacity_level >= 5 if key == "bag" else sim.speed_level >= 3
		var node = Button.new()
		node.text = ("Carry 4 more items" if key == "bag" else "Move faster") + (" · MAX" if maxed else " · $%d" % sim.upgrade_cost(key))
		node.custom_minimum_size.y = 52
		node.disabled = maxed or sim.cash < sim.upgrade_cost(key)
		node.pressed.connect(func(): sim.upgrade(key); show_upgrades(); refresh())
		column.add_child(node)
	if not highlighted.is_empty():
		var s = sim.definition(highlighted)
		if sim.stations[s.id].unlocked and s.kind in ["source", "processor", "shop"]:
			var node = Button.new()
			node.text = "Upgrade " + s.name + " · $%d" % sim.upgrade_cost("station", s.id)
			node.custom_minimum_size.y = 52
			node.disabled = sim.cash < sim.upgrade_cost("station", s.id) or sim.stations[s.id].level >= 4
			node.pressed.connect(func(): sim.upgrade("station", s.id); show_upgrades(); refresh())
			column.add_child(node)
	var close = Button.new()
	close.text = "Done"
	close.custom_minimum_size.y = 44
	close.pressed.connect(show_upgrades)
	column.add_child(close)

func _physics_process(delta: float):
	if preview_mode: return
	var input: Vector2 = stick.axis
	input += Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)), float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if is_instance_valid(upgrade_panel): input = Vector2.ZERO
	input = input.limit_length(1)
	var direction = Vector3(input.x, 0, input.y)
	player.velocity = player.velocity.move_toward(direction * (5 + sim.speed_level * 0.7), delta * 32)
	player.move_and_slide()
	if input.length() > 0.05: avatar.rotation.y = lerp_angle(avatar.rotation.y, atan2(-direction.x, -direction.z), minf(1, delta * 14))
	gait += delta * input.length() * 14
	animate_walk(avatar, gait, input.length())
	stack.position.y = 1.05 + absf(sin(gait)) * 0.045 * input.length()
	camera.position = camera.position.lerp(player.position + Vector3(0, 18, 9), 1 - exp(-delta * 5))
	sim.tick(delta)
	update_customers(delta)
	update_helpers(delta)
	timer += delta
	save_timer += delta
	toast_time = maxf(0, toast_time - delta)
	toast.modulate.a = minf(1, toast_time * 2)
	if timer >= 0.16:
		var nearest: Dictionary = {}
		var distance = 1.0
		for zone in zones:
			if not zone.node.visible: continue
			var d = player.position.distance_to(zone.node.global_position)
			if d < distance: distance = d; nearest = zone
		highlighted = nearest.get("id", "")
		if not nearest.is_empty() and not is_instance_valid(upgrade_panel):
			var message = sim.interact(nearest.id, timer, nearest.action if nearest.action != "build" else "auto")
			if not message.is_empty(): toast.text = message; toast_time = 1.0
		timer = 0
		refresh()
	if save_timer > 5: save(); save_timer = 0
	for s in sim.pack.stations:
		if s.kind == "processor" and sim.stations[s.id].unlocked:
			var spinner = visuals[s.id].get_node_or_null("Props/Spinner")
			if spinner and sim.stations[s.id].input_stock > 0: spinner.rotation.y += delta * 4

func animate_walk(body: Node3D, phase: float, strength: float):
	body.get_node("Left").rotation.x = sin(phase) * 0.6 * strength
	body.get_node("Right").rotation.x = -sin(phase) * 0.6 * strength

func walk_actor(actor: Dictionary, target: Vector3, speed: float, delta: float) -> bool:
	var direction: Vector3 = target - actor.node.position
	if direction.length() < 0.08: animate_walk(actor.avatar, 0, 0); return true
	actor.node.position += direction.limit_length(delta * speed)
	actor.node.rotation.y = lerp_angle(actor.node.rotation.y, atan2(-direction.x, -direction.z), minf(1, delta * 9))
	actor.gait += delta * speed * 4
	animate_walk(actor.avatar, actor.gait, 1)
	return false

func update_customers(delta: float):
	for c in customers:
		var state: Dictionary = sim.stations[c.shop]
		c.node.visible = state.unlocked
		if not state.unlocked: continue
		var station_pos: Vector3 = visuals[c.shop].position
		var rank = 0
		for other in customers:
			if other.shop == c.shop and other.ticket < c.ticket and other.phase in ["arriving", "waiting"]: rank += 1
		var target = station_pos + Vector3(2.0 + rank * 0.7, 0, -0.3)
		if c.phase == "leaving":
			if walk_actor(c, station_pos + Vector3(7, 0, -3), 2.0, delta):
				c.phase = "returning"
				c.wait = 2.0 + c.slot * 0.5
		elif c.phase == "returning":
			c.wait -= delta
			if c.wait <= 0:
				c.node.position = station_pos + Vector3(7, 0, 5)
				c.phase = "arriving"
				c.ticket = customer_ticket
				customer_ticket += 1
		else:
			if walk_actor(c, target, 1.8, delta):
				c.node.rotation.y = PI * 0.5
				# Front customer buys only after arriving, serving, and finding stock.
				var front = rank == 0
				c.phase = "waiting"
				if front:
					c.wait += delta
					if c.wait >= float(sim.definition(c.shop).cycle) / (1 + 0.3 * (state.level - 1)) and sim.sell(c.shop):
						c.phase = "leaving"
						c.wait = 0
						var purchase = item(c.avatar, Vector3(0, 0.85, -0.48), sim.definition(c.shop).input)
						get_tree().create_timer(2.8).timeout.connect(func(): if is_instance_valid(purchase): purchase.queue_free())

func update_helpers(delta: float):
	for h in helpers:
		var s = sim.definition(h.id)
		h.node.visible = sim.stations[h.id].unlocked
		if not h.node.visible: continue
		var target = sim.definition(s.target)
		if not sim.stations[target.id].unlocked: continue
		if h.amount <= 0:
			if h.source.is_empty():
				for source in sim.pack.stations:
					if source.get("output", "") == target.input and sim.stations[source.id].unlocked and sim.stations[source.id].stock > 0:
						h.source = source.id
						break
			if h.source.is_empty(): continue
			var source_pos: Vector3 = visuals[h.source].position + Vector3(0, 0, 1.6)
			if walk_helper(h, source_pos, delta):
				var source_state: Dictionary = sim.stations[h.source]
				h.amount = mini(4, int(source_state.stock))
				source_state.stock -= h.amount
				h.item = target.input
				clear_children(h.stack)
				for n in range(h.amount): item(h.stack, Vector3(0, n * 0.24, 0), h.item)
				if h.amount == 0: h.source = ""
		else:
			var target_pos: Vector3 = visuals[target.id].position + Vector3(-1.5, 0, 0.5)
			if walk_helper(h, target_pos, delta):
				var state: Dictionary = sim.stations[target.id]
				var count = mini(h.amount, sim.storage(target.id) - int(state.input_stock))
				state.input_stock += count
				h.amount -= count
				sim.delivered += count
				if h.amount == 0: h.source = ""; clear_children(h.stack)

func walk_helper(h: Dictionary, target: Vector3, delta: float) -> bool:
	# Route through the unobstructed central aisle rather than through the stations.
	if h.route.is_empty():
		h.route = [Vector3(0, 0, h.node.position.z), Vector3(0, 0, target.z), target]
	if walk_actor(h, h.route[0], 2.6, delta):
		h.route.pop_front()
		return h.route.is_empty()
	return false

func update_goal():
	var target = Vector3.ZERO
	var found = false
	for zone in zones:
		var s = sim.definition(zone.id)
		var st: Dictionary = sim.stations[s.id]
		if zone.action == "cash" and st.pending_cash > 0:
			target = zone.node.global_position; found = true; break
	if not found:
		for zone in zones:
			var s = sim.definition(zone.id)
			if zone.action == "deliver" and sim.stations[s.id].unlocked and sim.bag.get(s.input, 0) > 0:
				target = zone.node.global_position; found = true; break
	if not found:
		for zone in zones:
			var s = sim.definition(zone.id)
			if zone.action == "build" and not sim.stations[s.id].unlocked and sim.available(s) and sim.cash >= s.cost - sim.stations[s.id].paid:
				target = zone.node.global_position; found = true; break
	if not found:
		for zone in zones:
			if zone.action == "collect" and sim.stations[zone.id].unlocked and sim.stations[zone.id].stock > 0 and sim.bag_count() < sim.capacity:
				target = zone.node.global_position; found = true; break
	goal_arrow.visible = found and player.position.distance_to(target) > 1.2
	if goal_arrow.visible:
		var direction = (target - player.position).normalized()
		goal_arrow.position = player.position + direction * 1.0 + Vector3(0, .07, 0)
		goal_arrow.look_at(target + Vector3(0, .07, 0))

func refresh():
	update_goal()
	hud.text = "$ %d" % sim.cash
	ui_root.get_node("Bag").text = "Bag %d / %d" % [sim.bag_count(), sim.capacity]
	task.text = sim.objective()
	var unlocked = 0
	for s in sim.pack.stations:
		var st: Dictionary = sim.stations[s.id]
		var station_root: Node3D = visuals[s.id]
		station_root.get_node("Props").visible = st.unlocked
		station_root.get_node("Pad").visible = not st.unlocked and sim.available(s)
		station_root.get_node("Price").visible = not st.unlocked and sim.available(s)
		station_root.get_node("Price").text = "$%d" % ceili(s.cost - st.paid)
		var col = get_node("Blocker_" + s.id).get_child(0)
		col.set_deferred("disabled", not st.unlocked or s.kind == "worker")
		labels[s.id].visible = st.unlocked or sim.available(s)
		var line: String = s.name
		if st.unlocked:
			unlocked += 1
			if s.kind in ["source", "processor"]: line += "\n%d ready" % st.stock
			if s.kind == "shop": line += "\n%d in stock" % st.input_stock
			if st.level > 1: line += " · Lv.%d" % st.level
		else: line = "Build " + s.name
		labels[s.id].text = line
		var signature = hash([st.stock, st.input_stock, st.pending_cash, st.unlocked])
		if stock_signatures.get(s.id) != signature:
			stock_signatures[s.id] = signature
			refresh_stock(s)
	for zone in zones:
		var st: Dictionary = sim.stations[zone.id]
		zone.node.visible = (st.unlocked and zone.action != "build") or (not st.unlocked and sim.available(sim.definition(zone.id)) and zone.action == "build")
		if zone.action == "cash": zone.node.visible = st.unlocked and st.pending_cash > 0
	progress.value = 100.0 * unlocked / sim.pack.stations.size()
	var composition = hash(sim.bag)
	if composition != last_count:
		last_count = composition
		clear_children(stack)
		var n = 0
		for id in sim.bag:
			for _i in range(int(sim.bag[id])):
				item(stack, Vector3(0, n * 0.22, 0), id)
				n += 1

func refresh_stock(s: Dictionary):
	var st: Dictionary = sim.stations[s.id]
	var stock_root: Node3D = visuals[s.id].get_node("Stock")
	var cash_root: Node3D = visuals[s.id].get_node("Cash")
	clear_children(stock_root)
	clear_children(cash_root)
	if not st.unlocked: return
	var count: int = st.input_stock if s.kind == "shop" else st.stock
	var id: String = s.input if s.kind == "shop" else s.output
	for n in range(mini(12, count)):
		var pos = Vector3(-0.6 + (n % 3) * 0.42, 1.25 + (n / 6) * 0.27, -0.25 + ((n / 3) % 2) * 0.4)
		if s.kind == "source": pos.y = (0.8 if themed == "farm" else 1.5) + (n / 6) * 0.22
		item(stock_root, pos, id)
	if s.kind == "shop" and st.pending_cash > 0:
		for n in range(mini(12, ceili(st.pending_cash / maxf(1, s.price)))):
			var pos = Vector3(-0.35 + (n % 3) * 0.34, 0.08 + (n / 3) * 0.055, 1.85)
			box(cash_root, pos, Vector3(0.3, 0.05, 0.18), Color("70b657"))
		make_label(cash_root, Vector3(0, 0.7, 1.9), "$%d" % st.pending_cash, 30)

func on_activity(kind: String, id: String, item_id: String, amount: float):
	if kind in ["pickup", "deliver"]:
		var origin: Vector3 = visuals[id].position + Vector3(0, 1.2, 0)
		var target: Vector3 = player.position + Vector3(0, 1.3, 0)
		if kind == "deliver": var swap = origin; origin = target; target = swap
		if effect_count < 24:
			var prop = item(self, origin, item_id)
			effect_count += 1
			var tween = create_tween()
			tween.tween_property(prop, "position", target + Vector3(0, 0.5, 0), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(prop, "position", target, 0.1)
			tween.tween_callback(func(): prop.queue_free(); effect_count -= 1)
		play_tone(680 if kind == "pickup" else 480, 0.055)
	elif kind in ["cash", "sale", "unlock", "upgrade"]:
		var pos: Vector3 = visuals[id].position + Vector3(0, 2, 0) if visuals.has(id) else player.position + Vector3(0, 2, 0)
		var text_value = "+$%d" % amount if kind in ["cash", "sale"] else "UPGRADED!" if kind == "upgrade" else "OPEN!"
		var floating = make_label(self, pos, text_value, 40)
		floating.modulate = Color("ffee80")
		var tween = create_tween().set_parallel()
		tween.tween_property(floating, "position:y", floating.position.y + 1.5, 1.1)
		tween.tween_property(floating, "modulate:a", 0.0, 1.1)
		tween.chain().tween_callback(floating.queue_free)
		play_tone(960 if kind in ["unlock", "upgrade"] else 820, 0.14)
		if kind == "unlock":
			var props = visuals[id].get_node("Props")
			props.scale = Vector3(0.2, 0.2, 0.2)
			create_tween().tween_property(props, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func play_tone(frequency: float, duration: float):
	if not sound_on or preview_mode: return
	for audio in sounds:
		if audio.playing: continue
		var stream = AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = 22050
		var bytes = PackedByteArray()
		bytes.resize(int(duration * 22050) * 2)
		for n in range(bytes.size() / 2):
			var time = float(n) / 22050.0
			var envelope = minf(1, time * 160) * pow(maxf(0, 1 - time / duration), 2)
			bytes.encode_s16(n * 2, int(sin(time * TAU * frequency) * 14000 * envelope))
		stream.data = bytes
		audio.stream = stream
		audio.play()
		break

func save():
	if preview_mode: return
	# Goods in helper hands are returned to their source before serializing a snapshot.
	var snapshot = sim.serialize().duplicate(true)
	for h in helpers:
		if h.amount > 0 and not h.source.is_empty(): snapshot.stations[h.source].stock += h.amount
	DirAccess.make_dir_recursive_absolute("user://saves")
	var path = "user://saves/%s.json" % sim.pack.id
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(snapshot))
		file.close()
		DirAccess.rename_absolute(path + ".tmp", path)

func _notification(what):
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST] and sim != null: save()
