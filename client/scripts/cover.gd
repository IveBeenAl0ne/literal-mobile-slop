extends Control
var seed_id = ""
func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
func _draw():
	var hue = fmod(absf(float(hash(seed_id))) / 10000.0, 1.0)
	var accent = Color.from_hsv(hue, 0.45, 0.86)
	draw_rect(Rect2(Vector2.ZERO, size), accent.lightened(0.25))
	var center = size * Vector2(0.5, 0.65)
	draw_colored_polygon(PackedVector2Array([center + Vector2(-85, 0), center + Vector2(0, 40), center + Vector2(85, 0), center + Vector2(0, -40)]), accent.darkened(0.1))
	draw_rect(Rect2(center + Vector2(-45, -60), Vector2(90, 50)), Color("fff0d7"))
	draw_rect(Rect2(center + Vector2(-52, -72), Vector2(104, 18)), accent.darkened(0.25))
	for x in [-28, 0, 28]: draw_circle(center + Vector2(x, -26), 8, Color("e5b25b"))
