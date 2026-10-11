extends Node

const CATALOG_BASE_URL = "https://raw.githubusercontent.com/IveBeenAl0ne/literal-mobile-slop/main/client"
var catalog_endpoint: String = CATALOG_BASE_URL
var auto_refresh = true
var layer: CanvasLayer
var list: VBoxContainer
var status: Label
var search: LineEdit
var catalog: Array = []
var installed: Dictionary = {}
var busy = false
var refreshing = false
var world: Node3D
var section = "discover"
var tabs: Dictionary = {}
var cover_textures: Dictionary = {}
var loading_covers = false
var detail: Control
var action_buttons: Array = []

func _ready():
	DirAccess.make_dir_recursive_absolute("user://packs")
	DirAccess.make_dir_recursive_absolute("user://covers")
	if FileAccess.file_exists("user://catalog.json"):
		catalog = valid_entries(JSON.parse_string(FileAccess.get_file_as_string("user://catalog.json")))
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

func style(color: Color, radius = 16) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	return s

func label(text_value: String, font_size: int, color = Color("20242c")) -> Label:
	var node = Label.new()
	node.text = text_value
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	return node

func button(text_value: String, callback: Callable, primary = false) -> Button:
	var node = Button.new()
	node.text = text_value
	node.custom_minimum_size.y = 46
	node.add_theme_font_size_override("font_size", 18)
	node.add_theme_stylebox_override("normal", style(Color("2864ec") if primary else Color("e9edf3"), 13))
	node.add_theme_stylebox_override("hover", style(Color("1b51cd") if primary else Color("dce3ee"), 13))
	node.add_theme_stylebox_override("pressed", style(Color("1745af") if primary else Color("ccd5e4"), 13))
	node.add_theme_stylebox_override("disabled", style(Color("c9d5ef"), 13))
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		node.add_theme_color_override(state, Color.WHITE if primary else Color("333d50"))
	node.pressed.connect(callback)
	return node

func cover(id: String, height: float) -> Control:
	var frame = PanelContainer.new()
	frame.custom_minimum_size.y = height
	frame.add_theme_stylebox_override("panel", style(Color("e1e8ed"), 16))
	frame.clip_contents = true
	var path = "res://assets/covers/%s.png" % id
	if cover_textures.has(id) or ResourceLoader.exists(path):
		var art = TextureRect.new()
		art.texture = cover_textures[id] if cover_textures.has(id) else load(path)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		frame.add_child(art)
	else:
		var art = Control.new()
		art.set_script(load("res://scripts/cover.gd"))
		art.seed_id = id
		frame.add_child(art)
	return frame

func show_library():
	layer = CanvasLayer.new()
	add_child(layer)
	var background = ColorRect.new()
	background.color = Color("f7f8fa")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(background)
	var panel = VBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 22
	panel.offset_right = -22
	panel.offset_top = 32
	panel.offset_bottom = -90
	panel.add_theme_constant_override("separation", 14)
	background.add_child(panel)
	var header = HBoxContainer.new()
	panel.add_child(header)
	var title = label("Tycoon Hub", 32)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(label("PLAY. BUILD. GROW.", 12, Color("727b8c")))
	search = LineEdit.new()
	search.placeholder_text = "Search games"
	search.custom_minimum_size.y = 46
	search.add_theme_font_size_override("font_size", 18)
	search.add_theme_color_override("font_color", Color("20242c"))
	search.add_theme_color_override("font_placeholder_color", Color("737f92"))
	var search_style = style(Color("e9edf2"), 14)
	search_style.content_margin_left = 16
	search.add_theme_stylebox_override("normal", search_style)
	search.add_theme_stylebox_override("focus", search_style)
	search.text_changed.connect(func(_text): render_cards())
	panel.add_child(search)
	status = label("Checking for new games…", 14, Color("727b8c"))
	panel.add_child(status)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 16)
	scroll.add_child(list)
	var nav = PanelContainer.new()
	nav.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	nav.offset_top = -78
	nav.add_theme_stylebox_override("panel", style(Color.WHITE, 0))
	background.add_child(nav)
	tabs.clear()
	var nav_row = HBoxContainer.new()
	nav_row.add_theme_constant_override("separation", 12)
	nav.add_child(nav_row)
	for item in [["discover", "Discover"], ["installed", "My games"]]:
		var key: String = item[0]
		var tab = button(item[1], func(): section = key; render_cards())
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nav_row.add_child(tab)
		tabs[key] = tab
	render_cards()
	if auto_refresh: call_deferred("fetch_catalog")
	else: status.text = "Your games are ready"

func entries() -> Dictionary:
	var result = {}
	for id in installed: result[id] = installed[id]
	for entry in catalog:
		if not result.has(entry.id) or entry.version >= result[entry.id].version: result[entry.id] = entry
	return result

func render_cards():
	if not is_instance_valid(list): return
	for key in tabs:
		var active: bool = section == key
		tabs[key].add_theme_stylebox_override("normal", style(Color("2864ec") if active else Color("e9edf3"), 13))
		for state in ["font_color", "font_hover_color", "font_pressed_color"]:
			tabs[key].add_theme_color_override(state, Color.WHITE if active else Color("333d50"))
		tabs[key].add_theme_stylebox_override("hover", style(Color("1b51cd") if active else Color("dce3ee"), 13))
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	action_buttons.clear()
	var games = entries()
	var query = search.text.strip_edges().to_lower()
	if section == "discover" and query.is_empty() and games.has("corner_cafe"):
		var featured = cover("corner_cafe", 220)
		list.add_child(featured)
		var overlay_host = Control.new()
		featured.add_child(overlay_host)
		var overlay = VBoxContainer.new()
		overlay.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		overlay.offset_left = 16
		overlay.offset_right = -16
		overlay.offset_top = -86
		overlay_host.add_child(overlay)
		var title = label("Small café. Big ambitions.", 25, Color.WHITE)
		title.add_theme_color_override("font_outline_color", Color("232331"))
		title.add_theme_constant_override("outline_size", 5)
		overlay.add_child(title)
		overlay.add_child(button("Explore Corner Café", open_details.bind("corner_cafe"), true))
	list.add_child(label("Your collection" if section == "installed" else "Find your next tycoon", 25))
	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 22)
	list.add_child(grid)
	for id in games:
		if section == "installed" and not installed.has(id): continue
		var p: Dictionary = games[id]
		if not query.is_empty() and not query in (p.title + " " + p.description).to_lower(): continue
		var card = VBoxContainer.new()
		card.custom_minimum_size.x = 235
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_constant_override("separation", 8)
		grid.add_child(card)
		var image_frame = cover(id, 150)
		card.add_child(image_frame)
		var hit = Button.new()
		hit.flat = true
		hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		hit.pressed.connect(open_details.bind(id))
		image_frame.add_child(hit)
		var title = label(p.title, 20)
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		card.add_child(title)
		card.add_child(label("Installed · Offline ready" if installed.has(id) else "Free · Tycoon", 13, Color("737d8e")))
		var caption = "Play" if installed.has(id) else "Get"
		if installed.has(id) and p.has("sha256") and p.version > installed[id].version: caption = "Update & play"
		var action = button(caption, select_game.bind(id), not installed.has(id))
		action.disabled = busy
		action_buttons.append(action)
		card.add_child(action)
	if grid.get_child_count() == 0:
		list.add_child(label("No games match your search.", 18, Color("737d8e")))

func open_details(id: String):
	if busy: return
	if is_instance_valid(detail): detail.queue_free()
	var p: Dictionary = entries()[id]
	detail = ColorRect.new()
	detail.color = Color("f7f8fa")
	detail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(detail)
	var panel = VBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 24
	panel.offset_right = -24
	panel.offset_top = 34
	panel.offset_bottom = -36
	panel.add_theme_constant_override("separation", 20)
	detail.add_child(panel)
	panel.add_child(button("‹ Discover", func(): detail.queue_free(); detail = null))
	panel.add_child(cover(id, 300))
	panel.add_child(label(p.title, 32))
	panel.add_child(label("TYCOON  /  SINGLE PLAYER", 13, Color("737d8e")))
	var description = label(p.description, 20)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(description)
	panel.add_child(button("Play" if installed.has(id) else "Get game", func(): detail.queue_free(); detail = null; select_game(id), true))
	panel.add_child(label("Play offline after downloading.\nYour progress saves automatically.", 17, Color("737d8e")))

func select_game(id: String):
	if busy: return
	var p: Dictionary = entries()[id]
	if p.has("sha256") and (not installed.has(id) or p.version > installed[id].version):
		await download_pack(p)
		if not installed.has(id) or installed[id].version < p.version: return
	play_pack(id)

func fetch(url_string: String) -> Dictionary:
	var http = HTTPRequest.new()
	http.timeout = 20
	http.body_size_limit = TycoonPack.MAX_BYTES
	http.max_redirects = 0
	add_child(http)
	var error = http.request(url_string)
	if error != OK:
		http.queue_free()
		return {"ok": false, "error": "Couldn't connect. Your installed games are ready to play."}
	var result = await http.request_completed
	http.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		return {"ok": false, "error": "You're offline. Your installed games are ready to play."}
	return {"ok": true, "body": result[3]}

func valid_entries(data: Variant) -> Array:
	var result: Array = []
	if not data is Dictionary or data.get("format") != 1 or not data.get("packs") is Array or data.packs.size() > 100: return result
	for entry in data.packs:
		if entry is Dictionary and TycoonPack.valid_id(entry.get("id")) and TycoonPack.number(entry.get("version"), 1, 1000000) and entry.get("sha256") is String and entry.sha256.length() == 64 and entry.get("title") is String and entry.get("description") is String:
			result.append(entry)
	return result

func fetch_catalog():
	if refreshing: return
	refreshing = true
	if is_instance_valid(status): status.text = "Checking for new games…"
	var result = await fetch(catalog_endpoint + "/catalog.json")
	refreshing = false
	if not result.ok:
		if is_instance_valid(status): status.text = result.error
		return
	var data = JSON.parse_string(result.body.get_string_from_utf8())
	if not data is Dictionary or data.get("format") != 1 or not data.get("packs") is Array:
		if is_instance_valid(status): status.text = "Games couldn't refresh. Your collection is still available."
		return
	catalog = valid_entries(data)
	var file = FileAccess.open("user://catalog.json", FileAccess.WRITE)
	if file: file.store_buffer(result.body)
	if is_instance_valid(status): status.text = "%d games to explore · Play anywhere" % entries().size()
	render_cards()
	await load_covers()

func load_covers():
	if loading_covers: return
	loading_covers = true
	for entry in catalog.duplicate():
		var checksum: String = entry.get("cover_sha256", "")
		if checksum.length() != 64: continue
		var valid_checksum = true
		for c in checksum:
			if not c in "0123456789abcdef": valid_checksum = false
		if not valid_checksum: continue
		var path = "user://covers/%s_%s.png" % [entry.id, checksum]
		var bytes: PackedByteArray
		if FileAccess.file_exists(path): bytes = FileAccess.get_file_as_bytes(path)
		else:
			var result = await fetch(catalog_endpoint + "/assets/covers/" + entry.id + ".png")
			if not result.ok: continue
			bytes = result.body
		var hashing = HashingContext.new()
		hashing.start(HashingContext.HASH_SHA256)
		hashing.update(bytes)
		if hashing.finish().hex_encode() != checksum: continue
		var picture = Image.new()
		if picture.load_png_from_buffer(bytes) != OK or picture.get_width() > 2048 or picture.get_height() > 2048: continue
		cover_textures[entry.id] = ImageTexture.create_from_image(picture)
		if not FileAccess.file_exists(path):
			var file = FileAccess.open(path, FileAccess.WRITE)
			if file: file.store_buffer(bytes)
		render_cards()
	loading_covers = false

func download_pack(entry: Dictionary):
	if busy: return
	busy = true
	for action in action_buttons:
		if is_instance_valid(action): action.disabled = true
	status.text = "Getting " + entry.get("title", entry.id) + "…"
	var result = await fetch(catalog_endpoint + "/packs/" + entry.id + ".json")
	busy = false
	if not result.ok:
		status.text = result.error
		render_cards()
		return
	var hashing = HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(result.body)
	if hashing.finish().hex_encode() != entry.sha256:
		status.text = "This game is updating. Try again shortly."
		render_cards()
		return
	var pack = TycoonPack.parse_bytes(result.body)
	if pack.is_empty() or pack.id != entry.id or pack.version != entry.version:
		status.text = "Couldn't install this game. Your previous version is safe."
		render_cards()
		return
	var path = "user://packs/%s.json" % pack.id
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if not file:
		status.text = "Unable to save game"
		render_cards()
		return
	file.store_buffer(result.body)
	file.close()
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		status.text = "Unable to install game"
		render_cards()
		return
	installed[pack.id] = pack
	status.text = "Ready to play · Available offline"
	render_cards()

func play_pack(id: String):
	if busy or not installed.has(id): return
	layer.queue_free()
	list = null
	status = null
	world = Node3D.new()
	world.set_script(load("res://scripts/world.gd"))
	world.setup(installed[id])
	world.exit_requested.connect(func(): world.queue_free(); world = null; show_library())
	add_child(world)

func _notification(what):
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_instance_valid(world): world.save(); world.exit_requested.emit()
		elif is_instance_valid(detail): detail.queue_free(); detail = null
