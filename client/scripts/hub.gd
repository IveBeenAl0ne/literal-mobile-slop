extends Node

var layer: CanvasLayer
var list: VBoxContainer
var status: Label
var url: LineEdit
var catalog: Array = []
var installed: Dictionary = {}
var base_url = "https://raw.githubusercontent.com/IveBeenAl0ne/literal-mobile-slop/main/client"
var busy = false
var world: Node3D

func _ready():
	DirAccess.make_dir_recursive_absolute("user://packs")
	if FileAccess.file_exists("user://settings.json"):
		var settings = JSON.parse_string(FileAccess.get_file_as_string("user://settings.json"))
		if settings is Dictionary: base_url = settings.get("server", base_url)
	load_installed()
	show_library()

func load_installed():
	installed.clear()
	for id in ["sunny_farm", "corner_cafe", "dusty_depot"]:
		var p = TycoonPack.parse_bytes(FileAccess.get_file_as_bytes("res://packs/%s.json" % id))
		if not p.is_empty(): installed[id] = p
	var dir = DirAccess.open("user://packs")
	if dir:
		for filename in dir.get_files():
			if filename.ends_with(".json"):
				var p = TycoonPack.parse_bytes(FileAccess.get_file_as_bytes("user://packs/" + filename))
				if not p.is_empty() and (not installed.has(p.id) or p.version >= installed[p.id].version): installed[p.id] = p

func show_library():
	layer = CanvasLayer.new()
	add_child(layer)
	var background = ColorRect.new()
	background.color = Color("111827")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(background)
	var panel = VBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 24
	panel.offset_right = -24
	panel.offset_top = 42
	panel.offset_bottom = -30
	panel.add_theme_constant_override("separation", 14)
	background.add_child(panel)
	var heading = Label.new()
	heading.text = "TYCOON HUB"
	heading.add_theme_font_size_override("font_size", 38)
	panel.add_child(heading)
	var subtitle = Label.new()
	subtitle.text = "One app. Your entire tycoon collection."
	subtitle.add_theme_color_override("font_color", Color("94a3b8"))
	panel.add_child(subtitle)
	url = LineEdit.new()
	url.text = base_url
	url.placeholder_text = "https://your-server.example"
	url.custom_minimum_size.y = 48
	panel.add_child(url)
	var refresh = Button.new()
	refresh.text = "Connect / Refresh catalog"
	refresh.custom_minimum_size.y = 48
	refresh.pressed.connect(fetch_catalog)
	panel.add_child(refresh)
	status = Label.new()
	status.text = "Three starter packs installed · Play offline"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(status)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 16)
	scroll.add_child(list)
	render_cards()

func render_cards():
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	var entries = {}
	for id in installed: entries[id] = installed[id]
	for entry in catalog:
		if entry is Dictionary and TycoonPack.valid_id(entry.get("id")): entries[entry.id] = entry
	for id in entries:
		var p: Dictionary = entries[id]
		var card = PanelContainer.new()
		var style = StyleBoxFlat.new()
		style.bg_color = Color("1f2937")
		style.set_corner_radius_all(18)
		style.content_margin_left = 18
		style.content_margin_right = 18
		style.content_margin_top = 18
		style.content_margin_bottom = 18
		card.add_theme_stylebox_override("panel", style)
		list.add_child(card)
		var content = VBoxContainer.new()
		content.add_theme_constant_override("separation", 10)
		card.add_child(content)
		var title = Label.new()
		title.text = p.get("title", id)
		title.add_theme_font_size_override("font_size", 25)
		content.add_child(title)
		var description = Label.new()
		description.text = p.get("description", "")
		description.custom_minimum_size.x = 400
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(description)
		var buttons = HBoxContainer.new()
		content.add_child(buttons)
		if installed.has(id):
			var play = Button.new()
			play.text = "Play · v%d" % installed[id].version
			play.custom_minimum_size = Vector2(175, 48)
			play.pressed.connect(play_pack.bind(id))
			buttons.add_child(play)
		if p.has("sha256") and (not installed.has(id) or p.version > installed[id].version):
			var download = Button.new()
			download.text = "Update" if installed.has(id) else "Download"
			download.custom_minimum_size = Vector2(170, 48)
			download.pressed.connect(download_pack.bind(p))
			buttons.add_child(download)

func fetch(url_string: String) -> Dictionary:
	var http = HTTPRequest.new()
	http.timeout = 20
	http.body_size_limit = TycoonPack.MAX_BYTES
	http.max_redirects = 0
	add_child(http)
	var error = http.request(url_string)
	if error != OK:
		http.queue_free()
		return {"ok": false, "error": "Cannot start request (%d)" % error}
	var result = await http.request_completed
	http.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		return {"ok": false, "error": "Server unavailable (HTTP %d). Installed games still work." % result[1]}
	return {"ok": true, "body": result[3]}

func fetch_catalog():
	if busy: return
	var candidate = url.text.strip_edges().trim_suffix("/")
	if not candidate.begins_with("https://") and not candidate.begins_with("http://"):
		status.text = "Enter a full https:// server address."
		return
	busy = true
	base_url = candidate
	status.text = "Connecting…"
	var result = await fetch(base_url + "/catalog.json")
	busy = false
	if not result.ok:
		status.text = result.error
		return
	var data = JSON.parse_string(result.body.get_string_from_utf8())
	if not data is Dictionary or data.get("format") != 1 or not data.get("packs") is Array or data.packs.size() > 100:
		status.text = "Invalid catalog"
		return
	catalog = []
	for entry in data.packs:
		if entry is Dictionary and TycoonPack.valid_id(entry.get("id")) and TycoonPack.number(entry.get("version"), 1, 1000000) and entry.get("sha256") is String and entry.sha256.length() == 64:
			catalog.append(entry)
	var file = FileAccess.open("user://settings.json", FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"server": base_url}))
	status.text = "%d games on server" % catalog.size()
	render_cards()

func download_pack(entry: Dictionary):
	if busy: return
	busy = true
	status.text = "Downloading " + entry.get("title", entry.id) + "…"
	var result = await fetch(base_url + "/packs/" + entry.id + ".json")
	busy = false
	if not result.ok:
		status.text = result.error
		return
	var hashing = HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(result.body)
	if hashing.finish().hex_encode() != entry.sha256:
		status.text = "Download changed. Refresh catalog and try again."
		return
	var pack = TycoonPack.parse_bytes(result.body)
	if pack.is_empty() or pack.id != entry.id or pack.version != entry.version:
		status.text = "Pack validation failed; previous version preserved."
		return
	var path = "user://packs/%s.json" % pack.id
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if not file:
		status.text = "Unable to save pack"
		return
	file.store_buffer(result.body)
	file.close()
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		status.text = "Unable to install pack"
		return
	installed[pack.id] = pack
	status.text = "Installed! Available offline."
	render_cards()

func play_pack(id: String):
	if busy: return
	layer.queue_free()
	world = Node3D.new()
	world.set_script(load("res://scripts/world.gd"))
	world.setup(installed[id])
	world.exit_requested.connect(func(): world.queue_free(); show_library())
	add_child(world)
