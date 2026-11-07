extends Control
## A fog-aware chart. Drawing is intentionally throttled to four updates per second.
signal clicked(point: Vector2)

const MAP_SIZE := 80.0
const CELLS := 40
var sim
var camera_center := Vector2(18, 60)
var _clock := 0.0
var _dragging := false

func setup(model) -> void:
	sim = model
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(108, 108)
	gui_input.connect(_on_input)
	resized.connect(queue_redraw)
	queue_redraw()

func _process(delta: float) -> void:
	_clock += delta
	if _clock >= 0.25:
		_clock = 0.0
		queue_redraw()

func _chart() -> Rect2:
	var side := maxf(1.0, minf(size.x, size.y) - 10.0)
	return Rect2((size - Vector2.ONE * side) * 0.5, Vector2.ONE * side)

func _point(p: Vector2) -> Vector2:
	var chart := _chart()
	return chart.position + p / MAP_SIZE * chart.size

func _draw() -> void:
	var chart := _chart()
	draw_rect(Rect2(Vector2.ZERO, size), Color("10262d"))
	draw_rect(chart, Color("0b1c23"))
	if sim == null or chart.size.x <= 0 or chart.size.y <= 0:
		return
	var cell := chart.size / float(CELLS)
	for z in CELLS:
		for x in CELLS:
			var p := Vector2((x + 0.5) * 2.0, (z + 0.5) * 2.0)
			var explored: bool = sim.is_explored(p, 0)
			if not explored:
				continue
			var visible: bool = sim.is_visible(p, 0)
			var color := Color("35534c") if visible else Color("1b3235")
			# Fine, quiet alternating chart cells help judge movement distances.
			if (x + z) % 2 == 0:
				color = color.lightened(0.025)
			draw_rect(Rect2(chart.position + Vector2(x, z) * cell, cell + Vector2.ONE * 0.3), color)
	for division in range(1, 4):
		var ratio := division / 4.0
		draw_line(chart.position + Vector2(chart.size.x * ratio, 0), chart.position + Vector2(chart.size.x * ratio, chart.size.y), Color(0.58, 0.72, 0.67, 0.11), 1.0)
		draw_line(chart.position + Vector2(0, chart.size.y * ratio), chart.position + Vector2(chart.size.x, chart.size.y * ratio), Color(0.58, 0.72, 0.67, 0.11), 1.0)
	for entity in sim.entities:
		if float(entity.get("hp", 1.0)) <= 0.0:
			continue
		var team: int = entity.get("team", -1)
		var world: Vector2 = entity.get("pos", Vector2.ZERO)
		if team == 1 and not sim.is_visible(world, 0):
			continue
		if team == -1 and not sim.is_explored(world, 0):
			continue
		var at := _point(world)
		var kind: String = entity.get("kind", "")
		if team == -1:
			var resource_color: Color = {"tree": Color("789377"), "berry": Color("c8b37b"), "ore": Color("95b8d2")}.get(kind, Color("7b9c99"))
			draw_circle(at, 1.25, resource_color)
			continue
		var tint := Color("7fe5d5") if team == 0 else Color("ee9d76")
		var is_building := kind in ["heart", "house", "barracks", "tower"]
		if is_building:
			var extent := 3.8 if kind == "heart" else 2.6
			draw_rect(Rect2(at - Vector2.ONE * extent, Vector2.ONE * extent * 2.0), tint, false, 1.5)
			if kind == "heart":
				draw_circle(at, 1.5, tint)
		elif team == 0:
			draw_circle(at, 1.8, tint)
		else:
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -2.8), at + Vector2(2.8, 0), at + Vector2(0, 2.8), at + Vector2(-2.8, 0)]), tint)
	var center := _point(camera_center.clamp(Vector2.ZERO, Vector2.ONE * MAP_SIZE))
	var camera_rect := Rect2(center - chart.size * Vector2(0.115, 0.075), chart.size * Vector2(0.23, 0.15)).intersection(chart)
	draw_rect(camera_rect, Color(0.98, 0.94, 0.79, 0.9), false, 1.25)
	draw_rect(chart, Color("76968d"), false, 1.0)

func _navigate(local: Vector2) -> void:
	var chart := _chart()
	var p := ((local - chart.position) / chart.size * MAP_SIZE).clamp(Vector2.ZERO, Vector2.ONE * MAP_SIZE)
	clicked.emit(p)

func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_navigate(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_navigate(event.position)
		accept_event()
	elif event is InputEventScreenTouch:
		_dragging = event.pressed
		if event.pressed:
			_navigate(event.position)
		accept_event()
	elif event is InputEventScreenDrag and _dragging:
		_navigate(event.position)
		accept_event()
