extends Control
var rectangle := Rect2()
var active := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func show_box(start: Vector2, finish: Vector2) -> void:
	rectangle = Rect2(start, finish - start).abs()
	active = true
	queue_redraw()

func clear_box() -> void:
	active = false
	queue_redraw()

func _draw() -> void:
	if active:
		draw_rect(rectangle, Color(0.39, 0.85, 0.75, 0.12))
		draw_rect(rectangle, Color(0.55, 0.94, 0.82, 0.9), false, 1.5)
