extends RefCounted
## Shared fog-coast design tokens. All dimensions are logical viewport units.
const INK := Color("142e36")
const IVORY := Color("eee8d7")
const MIST := Color("68cbc1")
const BRASS := Color("c9a96c")
const MUTED := Color("a4bcb6")
const CORAL := Color("d98268")
const TEXT_MIN := 16
const TOUCH := 48
const GAP := 8

static func font_size(base: int, large: bool) -> int:
	return ceili(maxi(TEXT_MIN, base) * (1.25 if large else 1.0))

static func surface(fill: Color, edge: Color, cut := 6, hpad := 14, vpad := 12, border := 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(border)
	style.set_corner_radius_all(cut)
	style.corner_detail = 1
	style.content_margin_left = hpad
	style.content_margin_right = hpad
	style.content_margin_top = vpad
	style.content_margin_bottom = vpad
	style.anti_aliasing = true
	return style

static func panel() -> StyleBoxFlat:
	var s := surface(Color("142e36f5"), Color("456364"), 10)
	s.border_width_top = 2
	s.shadow_color = Color(0.01, 0.04, 0.05, 0.22)
	s.shadow_size = 5
	s.shadow_offset = Vector2(0, 3)
	return s

static func button_style(state: String, primary := false, danger := false) -> StyleBoxFlat:
	var accent := CORAL if danger else (BRASS if primary else MIST)
	var fill := Color("23434a")
	var edge := Color("48676b")
	if primary:
		fill = Color("32675f")
		edge = BRASS
	if danger:
		fill = Color("433536")
		edge = Color("926657")
	match state:
		"hover", "hover_pressed":
			fill = fill.lightened(0.12)
			edge = accent
		"pressed":
			fill = Color("315b57") if not danger else Color("68463c")
			edge = accent
		"disabled":
			fill = Color("192f35")
			edge = Color("32494c")
		"focus":
			return surface(Color.TRANSPARENT, BRASS, 6, 10, 7, 2)
	var s := surface(fill, edge, 6, 10, 7)
	s.border_width_bottom = 2 if state != "pressed" else 1
	return s

static func apply_button(button: Button, primary := false, danger := false) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, button_style(state, primary, danger))
