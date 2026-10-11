extends Control

var axis = Vector2.ZERO
var finger = -1
var center = Vector2.ZERO
var knob = Vector2.ZERO

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_input)

func _draw():
	var origin = center if finger >= 0 else size * 0.5
	draw_circle(origin, 65, Color(0.05, 0.1, 0.12, 0.3))
	draw_arc(origin, 65, 0, TAU, 64, Color(1, 1, 1, 0.55), 3, true)
	draw_circle(origin + knob, 28, Color(1, 1, 1, 0.85))

func _on_input(event: InputEvent):
	if event is InputEventScreenTouch and event.pressed and finger == -1:
		finger = event.index
		center = event.position
		knob = Vector2.ZERO
		accept_event()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			finger = -2
			center = event.position
		else: release()
	queue_redraw()

func _input(event: InputEvent):
	if event is InputEventScreenDrag and event.index == finger:
		update_axis(get_global_transform_with_canvas().affine_inverse() * event.position)
	if event is InputEventScreenTouch and event.index == finger and not event.pressed: release()
	if event is InputEventMouseMotion and finger == -2:
		update_axis(get_global_transform_with_canvas().affine_inverse() * event.position)
	if event is InputEventMouseButton and not event.pressed and finger == -2: release()

func update_axis(pos: Vector2):
	knob = (pos - center).limit_length(65)
	axis = knob / 65
	queue_redraw()

func release():
	finger = -1
	axis = Vector2.ZERO
	knob = Vector2.ZERO
	queue_redraw()

func _notification(what):
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: release()
