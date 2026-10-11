extends Node3D

signal exit_requested
var sim: TycoonSimulation
var player: CharacterBody3D
var avatar: Node3D
var camera: Camera3D
var visuals: Dictionary = {}
var labels: Dictionary = {}
var stack: Node3D
var hud: Label
var task: Label
var toast: Label
var stick: Control
var timer = 0.0
var save_timer = 0.0
var gait = 0.0
var last_count = -1
var customers: Array = []
var rng = RandomNumberGenerator.new()

func setup(pack: Dictionary):
	sim = TycoonSimulation.new(pack)
	var path = "user://saves/%s.json" % pack.id
	if FileAccess.file_exists(path): sim.restore(JSON.parse_string(FileAccess.get_file_as_string(path)))

func _ready():
	rng.seed = hash(sim.pack.id)
	var environment = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(sim.pack.theme.ground).darkened(0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.12
	environment.environment = env
	add_child(environment)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 0.4
	sun.shadow_enabled = true
	add_child(sun)
	box(self, Vector3(0, -0.15, 0), Vector3(40, 0.3, 40), Color(sim.pack.theme.ground))
	box(self, Vector3(0, 0.01, 0), Vector3(5.5, 0.02, 38), Color(sim.pack.theme.ground).lightened(0.18))
	for x in [-20.0, 20.0]: barrier(Vector3(x, 0.5, 0), Vector3(0.5, 1, 40))
	for z in [-20.0, 20.0]: barrier(Vector3(0, 0.5, z), Vector3(40, 1, 0.5))
	for n in range(26):
		var pos = Vector3(rng.randf_range(-19, 19), 0, rng.randf_range(-19, 19))
		if absf(pos.x) < 12 and absf(pos.z) < 12: continue
		tree(pos)
	for s in sim.pack.stations:
		var root = Node3D.new()
		root.position = Vector3(s.position[0], 0, s.position[1])
		add_child(root)
		visuals[s.id] = root
		var pad = cylinder(root, Vector3(0, 0.04, 0), 1.55, 0.05, Color(sim.pack.theme.accent).lightened(0.1))
		pad.name = "Pad"
		var label = Label3D.new()
		label.position = Vector3(0, 2.6, 0)
		label.font_size = 38
		label.pixel_size = 0.009
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.outline_size = 10
		root.add_child(label)
		labels[s.id] = label
		build_station(s)
	player = CharacterBody3D.new()
	player.position = Vector3(0, 0, 6)
	var collision = CollisionShape3D.new()
	var shape = CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.35
	collision.shape = shape
	collision.position.y = 0.68
	player.add_child(collision)
	add_child(player)
	avatar = character(player, Color(sim.pack.theme.player))
	stack = Node3D.new()
	stack.position = Vector3(0, 1.25, 0.4)
	player.add_child(stack)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 24
	add_child(camera)
	camera.position = player.position + Vector3(10, 15, 12)
	camera.look_at(player.position)
	create_ui()
	for s in sim.pack.stations:
		if s.kind == "shop":
			for n in range(3):
				var actor = Node3D.new()
				add_child(actor)
				character(actor, Color.from_hsv(rng.randf(), 0.5, 0.95))
				actor.position = Vector3(-18, 0, -15 + n)
				customers.append({"node": actor, "shop": s.id, "phase": n * 2.0})
	refresh()

func material(color: Color) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
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
	shape.radial_segments = 10
	mesh.mesh = shape
	mesh.material_override = material(color)
	mesh.position = pos
	parent.add_child(mesh)
	return mesh

func barrier(pos: Vector3, size: Vector3):
	var body = StaticBody3D.new()
	body.position = pos
	add_child(body)
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)

func tree(pos: Vector3):
	cylinder(self, pos + Vector3(0, 0.65, 0), 0.18, 1.3, Color("805743"))
	for n in range(3):
		var top = cylinder(self, pos + Vector3(0, 1.2 + n * 0.45, 0), 1.1 - n * 0.23, 0.85, Color("67ad59"))
		(top.mesh as CylinderMesh).top_radius = 0.08

func character(parent: Node3D, color: Color) -> Node3D:
	var root = Node3D.new()
	parent.add_child(root)
	cylinder(root, Vector3(0, 0.7, 0), 0.27, 0.65, color)
	var head = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.29
	sphere.height = 0.58
	sphere.radial_segments = 12
	sphere.rings = 6
	head.mesh = sphere
	head.material_override = material(color.lightened(0.15))
	head.position.y = 1.22
	root.add_child(head)
	for x in [-0.16, 0.16]:
		var foot = box(root, Vector3(x, 0.22, 0), Vector3(0.21, 0.45, 0.24), color.darkened(0.12))
		foot.name = "Left" if x < 0 else "Right"
	for x in [-0.37, 0.37]: box(root, Vector3(x, 0.73, 0), Vector3(0.18, 0.4, 0.2), color)
	return root

func build_station(s: Dictionary):
	var root: Node3D = visuals[s.id]
	var props = Node3D.new()
	props.name = "Props"
	root.add_child(props)
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
				var piece = MeshInstance3D.new()
				var sphere = SphereMesh.new()
				sphere.radius = dimensions.x * 0.5
				sphere.height = dimensions.x
				sphere.radial_segments = 12
				sphere.rings = 6
				piece.mesh = sphere
				piece.position = pos
				piece.scale = Vector3(1, dimensions.y / dimensions.x, dimensions.z / dimensions.x)
				piece.material_override = material(color)
				props.add_child(piece)
	elif s.kind == "source":
		box(props, Vector3(0, 0.17, 0), Vector3(2, 0.3, 1.6), Color("936146"))
		for x in [-0.65, 0.0, 0.65]:
			cylinder(props, Vector3(x, 0.6, 0), 0.12, 0.65, accent)
			cylinder(props, Vector3(x, 0.98, 0), 0.25, 0.35, item_color(s.output))
	elif s.kind == "processor":
		box(props, Vector3(0, 0.65, 0), Vector3(1.8, 1.3, 1.1), accent)
		box(props, Vector3(0, 1.4, 0), Vector3(1.95, 0.15, 1.3), Color("e8eef2"))
		cylinder(props, Vector3(0.4, 1.6, 0), 0.3, 0.4, Color("53596a"))
	elif s.kind == "shop":
		box(props, Vector3(0, 0.55, 0), Vector3(2.3, 1.1, 1.1), Color("f6ecd9"))
		box(props, Vector3(0, 1.12, 0), Vector3(2.5, 0.15, 1.3), accent)
		for x in [-1.0, 1.0]: cylinder(props, Vector3(x, 1.5, 0), 0.06, 2.6, Color("785641"))
		box(props, Vector3(0, 2.8, 0), Vector3(2.6, 0.2, 1.6), accent)
	elif s.kind == "worker": character(props, accent)
	else:
		box(props, Vector3(0, 0.65, 0), Vector3(1.8, 0.2, 1.2), accent)
		cylinder(props, Vector3(0, 0.3, 0), 0.15, 0.6, Color("785641"))
	# Keep a collision blocker at the station; interaction happens beside it.
	barrier(root.position + Vector3(0, 0.45, 0), Vector3(1.5, 0.9, 0.8))

func item_color(id: String) -> Color:
	for i in sim.pack.items:
		if i.id == id: return Color(i.color)
	return Color.WHITE

func create_ui():
	var layer = CanvasLayer.new()
	add_child(layer)
	var ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	var panel = Panel.new()
	panel.position = Vector2(10, 30)
	panel.size = Vector2(520, 190)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.1, 0.14, 0.85)
	style.set_corner_radius_all(18)
	panel.add_theme_stylebox_override("panel", style)
	ui.add_child(panel)
	var back = Button.new()
	back.text = "‹ Library"
	back.position = Vector2(18, 38)
	back.size = Vector2(115, 48)
	back.pressed.connect(func(): save(); exit_requested.emit())
	ui.add_child(back)
	hud = Label.new()
	hud.position = Vector2(150, 38)
	hud.add_theme_font_size_override("font_size", 24)
	ui.add_child(hud)
	task = Label.new()
	task.position = Vector2(20, 100)
	task.size = Vector2(500, 70)
	task.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	task.add_theme_font_size_override("font_size", 22)
	ui.add_child(task)
	toast = Label.new()
	toast.position = Vector2(20, 178)
	toast.size.x = 500
	toast.add_theme_color_override("font_color", Color("ffe89e"))
	ui.add_child(toast)
	stick = Control.new()
	stick.set_script(load("res://scripts/joystick.gd"))
	stick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	stick.position = Vector2(20, -205)
	stick.size = Vector2(180, 180)
	ui.add_child(stick)
	var help = Label.new()
	help.text = "Stand beside stations to work\nWASD / arrows on desktop"
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	help.position = Vector2(-300, -110)
	help.size = Vector2(280, 80)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	help.add_theme_font_size_override("font_size", 17)
	help.add_theme_color_override("font_outline_color", Color("152324"))
	help.add_theme_constant_override("outline_size", 6)
	ui.add_child(help)

func _physics_process(delta: float):
	var input: Vector2 = stick.axis
	input += Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)), float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	input = input.limit_length(1)
	var right = camera.global_basis.x
	var forward = camera.global_basis.z
	right.y = 0
	forward.y = 0
	var direction = right.normalized() * input.x + forward.normalized() * input.y
	player.velocity = direction * 5
	player.move_and_slide()
	if input.length() > 0.05:
		avatar.rotation.y = lerp_angle(avatar.rotation.y, atan2(-direction.x, -direction.z), minf(1, delta * 12))
	gait += delta * input.length() * 14
	avatar.get_node("Left").rotation.x = sin(gait) * 0.5 * input.length()
	avatar.get_node("Right").rotation.x = -sin(gait) * 0.5 * input.length()
	camera.position = camera.position.lerp(player.position + Vector3(10, 15, 12), 1 - exp(-delta * 5))
	sim.tick(delta)
	timer += delta
	save_timer += delta
	if timer >= 0.15:
		var nearest = ""
		var distance = 2.1
		for s in sim.pack.stations:
			var d = player.position.distance_to(visuals[s.id].position)
			if d < distance:
				distance = d
				nearest = s.id
		if nearest != "":
			var message = sim.interact(nearest, timer)
			if message != "": toast.text = message
		timer = 0
		refresh()
	if save_timer > 5:
		save()
		save_timer = 0
	for c in customers:
		var shop: Dictionary = sim.stations[c.shop]
		c.node.visible = shop.unlocked
		if not shop.unlocked: continue
		c.phase += delta
		var target: Vector3 = visuals[c.shop].position + Vector3(-1.8, 0, 0.6)
		if fmod(c.phase, 12) > 8: target = Vector3(-18, 0, -15)
		var travel: Vector3 = target - c.node.position
		c.node.position += travel.limit_length(delta * 1.7)
		if travel.length() > 0.1: c.node.rotation.y = atan2(-travel.x, -travel.z)

func refresh():
	hud.text = "$%d    Bag %d/%d" % [sim.cash, sim.bag_count(), sim.capacity]
	task.text = sim.objective()
	for s in sim.pack.stations:
		var st: Dictionary = sim.stations[s.id]
		visuals[s.id].get_node("Props").visible = st.unlocked
		var line: String = s.name
		if not st.unlocked:
			line += "\n$%d" % (s.cost - st.paid) if sim.available(s) else "\nLocked"
		elif s.kind in ["source", "processor"]: line += "\nReady %d" % st.stock
		elif s.kind == "shop": line += "\nStock %d · $%d" % [st.input_stock, st.pending_cash]
		labels[s.id].text = line
		labels[s.id].modulate = Color.WHITE if sim.available(s) else Color("adb3bc")
	# Rebuild the visible carried stack only when its composition changes.
	var composition = hash(sim.bag)
	if composition != last_count:
		last_count = composition
		for child in stack.get_children(): child.queue_free()
		var n = 0
		for id in sim.bag:
			for i in range(int(sim.bag[id])):
				box(stack, Vector3(0, n * 0.15, 0), Vector3(0.45, 0.14, 0.35), item_color(id))
				n += 1

func save():
	DirAccess.make_dir_recursive_absolute("user://saves")
	var path = "user://saves/%s.json" % sim.pack.id
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(sim.serialize()))
		file.close()
		DirAccess.rename_absolute(path + ".tmp", path)

func _notification(what):
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST] and sim != null: save()
