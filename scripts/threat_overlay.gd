extends Control
## Slow amber edge pulse; never captures battlefield clicks.
var remaining := 0.0
var phase := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func alert() -> void:
	remaining = 7.0
	phase = 0.0
	queue_redraw()

func clear() -> void:
	remaining = 0.0
	queue_redraw()

func _process(dt: float) -> void:
	if remaining <= 0.0: return
	remaining = maxf(0.0,remaining-dt)
	phase += dt
	queue_redraw()

func _draw() -> void:
	if remaining <= 0.0: return
	var strength := (0.55+sin(phase*TAU*0.7)*0.18)*minf(remaining,1.0)
	for i in range(10):
		var inset := float(i)*2.0
		draw_rect(Rect2(Vector2.ONE*inset,size-Vector2.ONE*inset*2),Color(1.0,0.42,0.16,strength*(1.0-i/10.0)*0.5),false,2.0)
