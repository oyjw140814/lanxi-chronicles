extends CanvasLayer
## Interface is independent of the simulation. All game commands are explicit signals.
signal action(name: String, payload: Variant)
signal map_clicked(point: Vector2)

const Data = preload("res://scripts/game_data.gd")
const Minimap = preload("res://scripts/minimap.gd")
const ThreatOverlay = preload("res://scripts/threat_overlay.gd")
const UI = preload("res://scripts/ui_theme.gd")
const Icons = preload("res://scripts/ui_icons.gd")
const INK := UI.INK
const IVORY := UI.IVORY
const MIST := UI.MIST
const BRASS := UI.BRASS
const MUTED := UI.MUTED
# Text uses shared normal / large presets in logical viewport units.
const MIN_FONT_SIZE := UI.TEXT_MIN
var _large_text := false
const TUTORIALS := [
	["让群岛再次共鸣", "你是雾岸的引航者。采集资源、拓展营地，摧毁对岸的回响心。先找到青绿色的拾光者。"],
	["选择拾光者", "点击营地周围的拾光者，或点下方「工人」。选中后会出现青色光环。"],
	["第一批补给", "点选拾光者，再直接点树木、果丛或矿石开始采集。也可先点下方「采集」。物资装满后会自动运回回响心。"],
	["建立织锋庭", "选中拾光者，点「织锋庭」，再点一块空地确认建造。红色预览表示位置不可用。"],
	["训练守护者", "选中建成的织锋庭，点「棱盾卫」训练部队。人口满时，请先建造风栖居。"],
	["向雾中进发", "选中部队，向东北方的迷雾移动。右下角海图可移动镜头；注意保护回响心。"],
	["指挥第一场战斗", "点击「军队」集合部队，向可见敌人发出攻击指令。盾卫在前，弦光手在后。"],
	["夺回潮晶航线", "持续补充兵力，摧毁赤铜阵营的回响心。裂岩兽擅长攻坚；保住自己的回响心。"]
]

class DragSelection extends Control:
	var rectangle := Rect2()
	var active := false
	func _draw() -> void:
		if active:
			draw_rect(rectangle, Color(0.3, 0.8, 0.73, 0.12))
			draw_rect(rectangle, Color("8bdfd0"), false, 1.5)

class TideEmblem extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r: float = minf(size.x, size.y) * 0.43
		draw_arc(c, r, -PI * 0.85, PI * 0.85, 48, Color("c9a96c"), 1.1, true)
		draw_arc(c, r * 0.82, -PI * 0.15, PI * 1.15, 42, Color("567a79"), 1.0, true)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.85), c + Vector2(r * 0.33, r * 0.25), c + Vector2(0, r * 0.56), c + Vector2(-r * 0.33, r * 0.25)]), Color("68cbc1"))
		draw_line(c + Vector2(0, -r * 0.85), c + Vector2(0, r * 0.56), Color("e1f2d8"), 1.0, true)
		draw_line(c + Vector2(-r * 0.66, r * 0.55), c + Vector2(r * 0.66, r * 0.55), Color("c9a96c"), 1.0, true)

var sim
var _root: Control
var _theme: Theme
var _display_font: Font
var _top: PanelContainer
var _top_content: HBoxContainer
var _top_scroll: ScrollContainer
var _brand: Label
var _subtitle: Label
var _resources: Dictionary = {}
var _population: Label
var _time: Label
var _mission: PanelContainer
var _mission_number: Label
var _mission_title: Label
var _mission_text: Label
var _tutorial_step := 0
var _tutorial_hidden := false
var _tutorial_initialized := false
var _bottom: PanelContainer
var _bottom_stack: VBoxContainer
var _commands: HBoxContainer
var _commands_scroll: ScrollContainer
var _selection_title: Label
var _selection_detail: Label
var _health: ProgressBar
var _actions: GridContainer
var _selection_box: VBoxContainer
var _action_scroll: ScrollContainer
var _map_panel: PanelContainer
var _map
var _map_title: Label
var _toast: PanelContainer
var _toast_label: Label
var _toast_time := 0.0
var _modal: ColorRect
var _modal_panel: PanelContainer
var _modal_body: VBoxContainer
var _modal_scroll: ScrollContainer
var _modal_chrome: HBoxContainer
var _modal_flow_rows: Array[BoxContainer] = []
var _title_page_emblem: Control
var _title_page_brand: Label
var _portrait: ColorRect
var _notice_margin: MarginContainer
var _notice_column: VBoxContainer
var _notice_emblem: Control
var _notice_brand: Label
var _notice_title: Label
var _notice_text: Label
var _window_too_small := false
var _layout_style_key := ""
var _drag: DragSelection
var _page := ""
var _return_page := "main"
var _build_kind := ""
var _order_kind := ""
var _warning: Button
var _warning_time := 0.0
var _warning_effect
var _recruit_id := -1
var _recruit_feedback := ""
var _selected_signature := ""
var _compact := false
var _small := false
var _last_size := Vector2.ZERO
var _multiselect := false
var _multi_button: Button
var _quality := "high"
var _volume := 0.65
var _last_selected: Array = []
var _paused := false
var _settle_frames := 0
var _bottom_row: HBoxContainer
var _selection_image: TextureRect
var _selection_info: Button
var _map_toggle: Button
var _map_expanded := false
var _tutorial_expanded := false
var _tutorial_toggle: Button
var _modal_fixed: VBoxContainer
var _modal_back: Button
var _modal_caption: Label
var _recruit_wallet: Label
var _recruit_queue: Label
var _recruit_notice: Label
var _recruit_grid: GridContainer
var _settings_tab := "display"
var _settings_tabs: HBoxContainer
var _manual_open: Dictionary = {}
var _modal_tween: Tween
var _safe_area_override := Rect2() # Used by native layout checks; empty uses OS safe area.


func setup(model) -> void:
	sim = model
	layer = 10
	_build_theme()
	_root = Control.new()
	_root.name = "CommandInterface"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _theme
	add_child(_root)
	_drag = DragSelection.new()
	_drag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_drag)
	_build_top()
	_build_mission()
	_build_bottom()
	_build_map()
	_build_toast()
	_build_modal()
	_build_portrait()
	_warning_effect = ThreatOverlay.new()
	_root.add_child(_warning_effect)
	_warning = _button("敌军进入视野 · 定位", "focus_threat")
	_warning.add_theme_stylebox_override("normal", _style(Color("493634"), UI.CORAL, 6, 12, 8, 2))
	_warning.visible = false
	_root.add_child(_warning)
	get_viewport().size_changed.connect(_layout)
	for panel in [_top, _mission, _bottom, _modal_panel]:
		panel.minimum_size_changed.connect(_schedule_layout)
	call_deferred("_layout")
	_layout()
	set_tutorial(0)
	refresh([], Vector2(18, 60), false)

func _build_theme() -> void:
	_theme = Theme.new()
	if ResourceLoader.exists("res://assets/fonts/NotoSansSC.ttf"):
		var body := FontVariation.new()
		body.base_font = load("res://assets/fonts/NotoSansSC.ttf")
		body.variation_opentype = {2003265652: 450.0}
		_theme.default_font = body
	else:
		var body := SystemFont.new()
		body.font_names = PackedStringArray(["Noto Sans CJK SC", "Microsoft YaHei", "sans-serif"])
		_theme.default_font = body
	var display := FontVariation.new()
	display.base_font = _theme.default_font
	display.spacing_glyph = 1
	display.variation_opentype = {2003265652: 650.0}
	_display_font = display
	_theme.default_font_size = _font_size(18)
	_theme.set_color("font_color", "Label", IVORY)
	_theme.set_color("font_color", "Button", IVORY)
	_theme.set_color("font_hover_color", "Button", Color("ffffff"))
	_theme.set_color("font_pressed_color", "Button", Color("ffffff"))
	_theme.set_color("font_disabled_color", "Button", Color("718784"))
	_theme.set_color("font_color", "CheckButton", IVORY)
	_theme.set_constant("separation", "HBoxContainer", 10)
	_theme.set_constant("separation", "VBoxContainer", 8)
	_theme.set_stylebox("background", "ProgressBar", _style(Color("0d242c"), Color("315250"), 2, 0, 0))
	_theme.set_stylebox("fill", "ProgressBar", _style(MIST, MIST, 2, 0, 0))
	_theme.set_stylebox("panel", "TooltipPanel", _style(Color("122b33"), BRASS, 4, 10, 8))
	_theme.set_color("font_color", "TooltipLabel", IVORY)
	_theme.set_font_size("font_size", "TooltipLabel", _font_size(16))
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		_theme.set_stylebox(state, "Button", UI.button_style(state))

func _font_size(base_size: int) -> int:
	return UI.font_size(base_size, _large_text)

func set_large_text(enabled: bool) -> void:
	_large_text = enabled
	if _root == null: return
	_apply_text_scale(_root)
	_theme.set_font_size("font_size", "TooltipLabel", _font_size(16))
	_theme.default_font_size = _font_size(18)
	_layout_style_key = ""
	_selected_signature = ""
	refresh(_last_selected, _map.camera_center, _paused)
	if _page == "settings": show_menu("settings")
	_layout()

func _apply_text_scale(node: Node) -> void:
	if node is Control and node.has_meta("base_font"):
		node.add_theme_font_size_override("font_size", _font_size(int(node.get_meta("base_font"))))
	for child in node.get_children(): _apply_text_scale(child)

func _style(fill: Color, edge: Color, radius := 6, hpad := 14, vpad := 12, border := 1) -> StyleBoxFlat:
	return UI.surface(fill, edge, radius, hpad, vpad, border)

func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.panel())
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	return panel

func _label(value: String, point_size := 15, color := IVORY, display := false) -> Label:
	var label := Label.new()
	label.text = value
	label.set_meta("base_font", maxi(16, point_size))
	label.add_theme_font_size_override("font_size", _font_size(point_size))
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if display:
		label.add_theme_font_override("font", _display_font)
	return label

func _button(caption: String, command: String, payload: Variant = null, primary := false) -> Button:
	var button := Button.new()
	button.text = caption
	button.set_meta("base_font", 18)
	button.set_meta("command", command)
	button.custom_minimum_size = Vector2(48, 48)
	button.add_theme_font_size_override("font_size", _font_size(18))
	button.icon = Icons.command(command, payload)
	button.expand_icon = true
	if button.icon != null:
		button.custom_minimum_size.x = maxf(48, caption.length() * _font_size(18) + 52)
	button.add_theme_constant_override("icon_max_width", 24)
	button.add_theme_constant_override("h_separation", 8)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.tooltip_text = {"home":"回到营地 · H", "stop":"停止 · S", "attack":"沿途迎击 · A", "pause":"菜单 · Esc / 空格", "manual":"引航手册 · F1", "save":"保存进度 · F5", "load":"读取存档 · F9", "gather":"点采集，再点资源", "move":"点移动，再点目的地"}.get(command, caption)
	button.pressed.connect(func(): _dispatch(command, payload))
	UI.apply_button(button, primary, command == "restart")
	button.button_down.connect(func():
		button.pivot_offset = button.size * 0.5
		button.scale = Vector2(0.98, 0.98))
	button.button_up.connect(func():
		button.create_tween().tween_property(button, "scale", Vector2.ONE, 0.10))
	button.mouse_exited.connect(func(): button.scale = Vector2.ONE)
	return button

func _dispatch(command: String, payload: Variant) -> void:
	match command:
		"map_toggle":
			_map_expanded = not _map_expanded
			_layout()
		"tutorial_details":
			_tutorial_expanded = not _tutorial_expanded
			_mission_text.visible = _tutorial_expanded
			_tutorial_toggle.text = "收起" if _tutorial_expanded else "详情"
			_layout()
		"build_list", "details": action.emit("ui_page", command)
		"ui_build":
			action.emit("resume", null)
			action.emit("build", payload)
		"ui_back":
			if _page in ["recruit", "build_list", "details", "pause"] or _return_page == "":
				action.emit("resume", null)
			else: show_menu(_return_page)
		_: action.emit(command, payload)

func _icon(key: String, extent := 32) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = Icons.texture(key)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(extent, extent)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func _build_top() -> void:
	_top = _panel()
	_top.add_theme_stylebox_override("panel", _style(Color("10272eee"), Color("48645f"), 0, 12, 4))
	_root.add_child(_top)
	var frame := HBoxContainer.new()
	_top.add_child(frame)
	_top_scroll = ScrollContainer.new()
	_top_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_top_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(_top_scroll)
	_top_content = HBoxContainer.new()
	_top_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_scroll.add_child(_top_content)
	_brand = _label("", 16)
	_subtitle = _label("", 16)
	_brand.hide()
	_subtitle.hide()
	_top_content.add_child(_brand)
	_top_content.add_child(_subtitle)
	for key in ["food", "wood", "crystal"]:
		var block := HBoxContainer.new()
		block.add_theme_constant_override("separation", 6)
		_top_content.add_child(block)
		var icon := _icon(key, 28)
		icon.tooltip_text = Data.RESOURCE_NAMES[key]
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		block.add_child(icon)
		var amount := _label("0", 20, IVORY)
		amount.custom_minimum_size.x = 44
		block.add_child(amount)
		_resources[key] = amount
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_content.add_child(spacer)
	_population = _label("人口 0/10", 16, MUTED)
	_top_content.add_child(_population)
	_time = _label("00:00", 16, MUTED)
	_top_content.add_child(_time)
	frame.add_child(_button("菜单", "pause"))

func _build_mission() -> void:
	_mission = _panel()
	_root.add_child(_mission)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	_mission.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	_mission_number = _label("引航手册 01 / 08", 16, BRASS)
	_mission_number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mission_number.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_child(_mission_number)
	_tutorial_toggle = _button("详情", "tutorial_details")
	heading.add_child(_tutorial_toggle)
	var skip := _button("跳过", "skip_tutorial")
	heading.add_child(skip)
	_mission_title = _label("让群岛再次共鸣", 18, IVORY, true)
	_mission_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_mission_title)
	_mission_text = _label("", 16, MUTED)
	_mission_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mission_text.visible = false
	column.add_child(_mission_text)

func _build_bottom() -> void:
	_bottom = _panel()
	_root.add_child(_bottom)
	_bottom_stack = VBoxContainer.new()
	_bottom_stack.add_theme_constant_override("separation", 8)
	_bottom.add_child(_bottom_stack)
	_bottom_row = HBoxContainer.new()
	_bottom_row.add_theme_constant_override("separation", 12)
	_bottom_stack.add_child(_bottom_row)
	_selection_box = VBoxContainer.new()
	_selection_box.custom_minimum_size.x = 168
	_bottom_row.add_child(_selection_box)
	var identity := HBoxContainer.new()
	_selection_box.add_child(identity)
	_selection_image = _icon("compass", 48)
	identity.add_child(_selection_image)
	_selection_title = _label("雾岸引航者", 19, IVORY, true)
	_selection_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selection_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	identity.add_child(_selection_title)
	_selection_info = _button("", "details")
	_selection_info.tooltip_text = "查看选中单位详情"
	identity.add_child(_selection_info)
	_selection_detail = _label("选择单位查看指令", 16, MUTED)
	_selection_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selection_detail.max_lines_visible = 1
	_selection_detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_selection_box.add_child(_selection_detail)
	_health = ProgressBar.new()
	_health.custom_minimum_size.y = 4
	_health.show_percentage = false
	_health.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_box.add_child(_health)
	_action_scroll = ScrollContainer.new()
	_action_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_action_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_action_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_bottom_row.add_child(_action_scroll)
	_actions = GridContainer.new()
	_actions.columns = 4
	_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actions.add_theme_constant_override("h_separation", 6)
	_actions.add_theme_constant_override("v_separation", 6)
	_action_scroll.add_child(_actions)
	_commands_scroll = ScrollContainer.new()
	_commands_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_commands_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_commands_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_bottom_stack.add_child(_commands_scroll)
	_commands = HBoxContainer.new()
	_commands.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_commands.add_theme_constant_override("separation", 6)
	_commands_scroll.add_child(_commands)
	for entry in [["工人", "select_workers"], ["军队", "select_army"], ["招募", "recruit"], ["回营", "home"], ["停止", "stop"]]:
		_commands.add_child(_button(entry[0], entry[1]))
	_multi_button = _button("多选", "multiselect", true)
	_multi_button.toggle_mode = true
	for connection in _multi_button.pressed.get_connections(): _multi_button.pressed.disconnect(connection.callable)
	_multi_button.toggled.connect(func(on: bool): _multiselect = on; action.emit("multiselect", on))
	_commands.add_child(_multi_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_commands.add_child(spacer)
	_map_toggle = _button("海图", "map_toggle")
	_map_toggle.toggle_mode = true
	_commands.add_child(_map_toggle)
	_commands.add_child(_button("", "zoom", -1))
	_commands.add_child(_button("", "zoom", 1))

func _build_map() -> void:
	_map_panel = _panel()
	_map_panel.add_theme_stylebox_override("panel", _style(Color(0.04, 0.12, 0.15, 0.95), Color("70968b"), 5, 6, 5))
	_root.add_child(_map_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	_map_panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_map_title = _label("雾岸海图", 11, BRASS)
	_map_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_map_title)
	head.add_child(_label("N ↑", 10, MUTED))
	_map = Minimap.new()
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_map)
	_map.setup(sim)
	_map.clicked.connect(func(p: Vector2): map_clicked.emit(p))

func _build_toast() -> void:
	_toast = _panel()
	_toast.add_theme_stylebox_override("panel", _style(Color(0.12, 0.23, 0.24, 0.96), BRASS, 5, 18, 10))
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toast)
	_toast_label = _label("", 15, IVORY)
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_child(_toast_label)

func _build_modal() -> void:
	_modal = ColorRect.new()
	_modal.color = Color(0.025, 0.075, 0.095, 0.64)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.visible = false
	_root.add_child(_modal)
	_modal_panel = _panel()
	_modal.add_child(_modal_panel)
	var frame := VBoxContainer.new()
	frame.add_theme_constant_override("separation", 10)
	_modal_panel.add_child(frame)
	_modal_chrome = HBoxContainer.new()
	frame.add_child(_modal_chrome)
	_modal_caption = _label("引航者日志", 18, BRASS, true)
	_modal_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modal_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_modal_chrome.add_child(_modal_caption)
	_modal_back = _button("返回", "ui_back")
	_modal_chrome.add_child(_modal_back)
	_modal_fixed = VBoxContainer.new()
	frame.add_child(_modal_fixed)
	_modal_scroll = ScrollContainer.new()
	_modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_modal_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modal_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(_modal_scroll)
	_modal_body = VBoxContainer.new()
	_modal_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modal_body.add_theme_constant_override("separation", 12)
	_modal_scroll.add_child(_modal_body)

func _build_portrait() -> void:
	_portrait = ColorRect.new()
	_portrait.color = Color("10262e")
	_portrait.mouse_filter = Control.MOUSE_FILTER_STOP
	_portrait.visible = false
	_root.add_child(_portrait)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait.add_child(center)
	var margin := MarginContainer.new()
	_notice_margin = margin
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	center.add_child(margin)
	var col := VBoxContainer.new()
	_notice_column = col
	col.custom_minimum_size.x = 270
	col.add_theme_constant_override("separation", 18)
	margin.add_child(col)
	var emblem := TideEmblem.new()
	_notice_emblem = emblem
	emblem.custom_minimum_size = Vector2(90, 90)
	emblem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(emblem)
	var title := _label("岚汐纪", 38, IVORY, true)
	_notice_brand = title
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var rotate := _label("请横向使用屏幕", 22, BRASS)
	_notice_title = rotate
	rotate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rotate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(rotate)
	var note := _label("横屏可以更好地观察战场和指挥部队。\n旋转手机，或把窗口调整为横向。\n竖屏期间指令已锁定。", 15, MUTED)
	_notice_text = note
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(note)

func _process(delta: float) -> void:
	if _warning_time > 0.0:
		_warning_time = maxf(0.0,_warning_time-delta)
		_warning.visible = _warning_time > 0.0 and not is_modal_open()
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			_toast.visible = false
	if _root != null and (get_viewport().get_visible_rect().size != _last_size or _settle_frames > 0):
		_settle_frames = maxi(_settle_frames - 1, 0)
		_layout()

func _schedule_layout() -> void:
	# Text wrapping and scrollbars may change minima after the resize notification.
	_settle_frames = maxi(_settle_frames, 2)

func _layout() -> void:
	if _root == null:
		return
	var screen := get_viewport().get_visible_rect().size.max(Vector2.ONE)
	if screen != _last_size:
		# Container sorting and wrapped-text measurement finish on subsequent frames.
		# minimum_size_changed schedules another pass if a later sort changes them.
		_settle_frames = 6
	_last_size = screen
	_root.size = screen
	var safe_left := 0.0
	var safe_right := 0.0
	var safe_top := 0.0
	var safe_bottom := 0.0
	if OS.has_feature("mobile"):
		var safe := DisplayServer.get_display_safe_area()
		var native := DisplayServer.screen_get_size()
		if native.x > 0 and native.y > 0 and safe.size.x > 0:
			# Both the rectangles below and input positions use logical viewport units.
			# Convert the physical display safe area exactly once, including high DPI.
			var ratio := screen / Vector2(native)
			safe_left = safe.position.x * ratio.x
			safe_top = safe.position.y * ratio.y
			safe_right = maxf(0.0, native.x - safe.end.x) * ratio.x
			safe_bottom = maxf(0.0, native.y - safe.end.y) * ratio.y
	if _safe_area_override.has_area():
		safe_left = _safe_area_override.position.x
		safe_top = _safe_area_override.position.y
		safe_right = screen.x - _safe_area_override.end.x
		safe_bottom = screen.y - _safe_area_override.end.y
	var width := maxf(1.0, screen.x - safe_left - safe_right)
	var height := maxf(1.0, screen.y - safe_top - safe_bottom)
	var was_compact := _compact
	_compact = OS.has_feature("mobile") or width < 1050.0 or height < 650.0
	_small = height < 500.0
	if was_compact != _compact:
		_selected_signature = ""
		refresh(_last_selected, _map.camera_center, _paused)
	_window_too_small = width < 480.0 or height < 320.0
	var pad := 10.0 if _compact else 18.0
	var style_key := "%s:%s:%s" % [_compact, _small, width < 600.0]
	if style_key != _layout_style_key:
		_layout_style_key = style_key
		_apply_responsive_style(width)
		_settle_frames = maxi(_settle_frames, 6)
	var top_height := 56.0
	_top.position = Vector2(safe_left, safe_top)
	_top.size = Vector2(width, top_height)
	top_height = _top.size.y
	var map_width := 158.0 if _compact else 194.0
	var bottom_width := maxf(1.0, width - pad * 2.0 - (0.0 if _compact else map_width + pad))
	_selection_box.custom_minimum_size.x = (180 if _large_text else 164) if _small else (190 if _compact else 220)
	_selection_box.visible = bottom_width >= 590
	var selection_width := _selection_box.custom_minimum_size.x + 12 if _selection_box.visible else 0.0
	var action_width := maxf(1.0, bottom_width - 28 - selection_width)
	_actions.columns = maxi(1, mini(_actions.get_child_count(), int(action_width / (112.0 if _large_text else 96.0))))
	var action_rows := ceili(float(_actions.get_child_count()) / _actions.columns)
	var action_height := minf(168.0, action_rows * (58.0 if _small else 82.0))
	_bottom_row.custom_minimum_size.y = maxf(52.0, action_height)
	# A scroll viewport contains the grid only at genuinely undersized windows.
	_bottom_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bottom.size = Vector2(bottom_width, 0)
	_bottom.position = Vector2(safe_left + pad, safe_top + height - pad - _bottom.size.y)
	_map_panel.size = Vector2(map_width, map_width + 30)
	_map_panel.position = Vector2(safe_left + width - pad - map_width, safe_top + height - pad - _map_panel.size.y)
	_map.custom_minimum_size = Vector2(64, 64) if _compact else Vector2(108,108)
	if _compact:
		_map_panel.size.y = maxf(104, minf(map_width + 30, _bottom.position.y - safe_top - top_height - pad * 2))
		_map_panel.position.y = _bottom.position.y - _map_panel.size.y - pad
	_map_toggle.set_pressed_no_signal(_map_expanded)
	_mission.position = Vector2(safe_left + pad, safe_top + top_height + pad)
	_mission.size = Vector2(minf((510.0 if _large_text else 450.0) if _small else 380.0, maxf(1.0, width - pad * 2.0)), 0)
	_update_tutorial_text()
	_toast.size = Vector2(maxf(1.0, minf(width - pad * 2.0, 560.0)), 0)
	_toast.position = Vector2(safe_left + (width - _toast.size.x) * 0.5, maxf(safe_top + top_height + 10.0, _bottom.position.y - _toast.size.y - 10.0))
	_modal.size = screen
	var preferred_width := 920.0 if _page == "recruit" else (760.0 if _page in ["manual", "settings", "build_list", "details"] else 480.0)
	var preferred_height := 620.0 if _page in ["manual", "recruit"] else (520.0 if _page in ["pause", "settings"] else 420.0)
	var modal_width := minf(preferred_width, maxf(1.0, width - pad * 2.0))
	var modal_height := minf(preferred_height, maxf(1.0, height - pad * 2.0))
	if is_instance_valid(_recruit_grid):
		_recruit_grid.columns = 2 if modal_width >= (720.0 if _large_text else 620.0) else 1
	_fit_modal_rows(modal_width)
	_modal_panel.size = Vector2(modal_width, modal_height)
	_modal_panel.position = Vector2(safe_left + (width - _modal_panel.size.x) * 0.5, safe_top + (height - _modal_panel.size.y) * 0.5)
	if _page == "main":
		_modal_panel.position.x = safe_left + minf(maxf(pad, width * 0.075), width - _modal_panel.size.x - pad)
	_portrait.size = screen
	_portrait.visible = screen.x < screen.y or _window_too_small
	_update_window_notice(screen)
	var title_screen := _page == "main" or (_page in ["settings", "manual"] and _return_page == "main")
	_top.visible = not _portrait.visible and not title_screen
	_bottom.visible = not _portrait.visible and not title_screen
	_map_panel.visible = not _portrait.visible and not title_screen and (not _compact or _map_expanded)
	_mission.visible = not _portrait.visible and not title_screen and not _tutorial_hidden
	if _toast.visible and _mission.get_global_rect().intersects(_toast.get_global_rect()): _mission.visible = false
	_toast.visible = _toast_time > 0 and not _modal.visible and not _portrait.visible
	_warning.size = Vector2(minf(320.0,width-pad*2),56)
	_warning.position = Vector2(safe_left+width-pad-_warning.size.x,safe_top+top_height+pad)
	_warning.visible = _warning_time > 0.0 and not is_modal_open()
	if _warning.visible and _warning.get_global_rect().intersects(_mission.get_global_rect()): _mission.visible = false
	if _compact and _map_expanded and _warning.visible:
		_warning.position.x = safe_left + pad
		_mission.visible = false
	_modal_panel.visible = not _portrait.visible
	# Keep a short-window instruction card above the command panel.
	if _mission.visible and _mission.position.y + _mission.size.y > _bottom.position.y - 4.0:
		_mission.visible = false

func _apply_responsive_style(width: float) -> void:
	_population.add_theme_font_size_override("font_size", _font_size(16))
	_time.visible = not _small and width >= 900
	_top_content.add_theme_constant_override("separation", 10 if _compact else 26)
	for resource in _resources.values():
		resource.add_theme_font_size_override("font_size", _font_size(18 if _compact else 22))
	_selection_title.add_theme_font_size_override("font_size", _font_size(16 if _compact else 20))
	_selection_image.visible = not _compact
	_selection_detail.visible = not _small
	_mission_title.visible = not _small
	_mission_text.visible = _tutorial_expanded
	_mission_number.add_theme_font_size_override("font_size", _font_size(16))
	_bottom.add_theme_stylebox_override("panel", UI.surface(Color("142e36f5"), Color("456364"), 10, 12, 8 if _small else 12))
	var modal_padding := 12 if _small else 24
	var chrome := UI.surface(Color("142e36fa"), BRASS, 14, modal_padding, 12 if _small else 20)
	chrome.border_width_top = 2
	_modal_panel.add_theme_stylebox_override("panel", chrome)
	for button in _commands.get_children():
		if button is Button:
			button.custom_minimum_size.x = 48 if button.text.is_empty() else (56 if _compact else 94)
			button.add_theme_font_size_override("font_size", _font_size(16 if _compact else 18))
			button.icon = null if _compact and not button.text.is_empty() else Icons.command(button.get_meta("command", ""), -1 if button == _commands.get_child(_commands.get_child_count()-2) else 1)
	_map_toggle.visible = _compact
	if is_instance_valid(_title_page_emblem):
		_title_page_emblem.custom_minimum_size = Vector2(56,56) if _small else Vector2(88,88)
	if is_instance_valid(_title_page_brand):
		_title_page_brand.add_theme_font_size_override("font_size", _font_size(34 if _small else 48))
	_refresh_action_sizing()

func _refresh_action_sizing() -> void:
	for child in _actions.get_children():
		if child is Button:
			child.add_theme_font_size_override("font_size", _font_size(16))
			child.custom_minimum_size = Vector2(0, 52 if _small else 76)
			child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			child.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			child.clip_text = true
			child.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT if _small else HORIZONTAL_ALIGNMENT_CENTER
			child.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER if _small else VERTICAL_ALIGNMENT_TOP
			child.add_theme_constant_override("icon_max_width", 24 if _small else 36)
	_actions.queue_sort()
	_bottom_stack.queue_sort()

func _fit_modal_rows(modal_width: float) -> void:
	var style := _modal_panel.get_theme_stylebox("panel")
	var available := maxf(1.0, modal_width - style.get_content_margin(SIDE_LEFT) - style.get_content_margin(SIDE_RIGHT) - _modal_scroll.get_v_scroll_bar().get_combined_minimum_size().x)
	for row in _modal_flow_rows:
		if not is_instance_valid(row):
			continue
		var horizontal_minimum := 0.0
		var count := 0
		for child in row.get_children():
			if child is Control and child.visible:
				horizontal_minimum += child.get_combined_minimum_size().x
				count += 1
		horizontal_minimum += maxi(count - 1, 0) * row.get_theme_constant("separation")
		var stack := horizontal_minimum > available
		if row.vertical != stack:
			row.vertical = stack
			_settle_frames = maxi(_settle_frames, 4)

func _update_window_notice(screen: Vector2) -> void:
	var portrait := screen.y > screen.x
	_notice_column.custom_minimum_size.x = maxf(1.0, minf(270.0, screen.x - 40.0))
	_notice_margin.add_theme_constant_override("margin_left", 20)
	_notice_margin.add_theme_constant_override("margin_right", 20)
	_notice_emblem.visible = screen.y >= 420.0
	_notice_text.visible = screen.y >= 160.0
	_notice_brand.visible = screen.y >= 320.0
	_notice_title.text = "请横向使用屏幕" if portrait else "请放大游戏窗口"
	_notice_text.text = "横屏可以更好地观察战场和指挥部队。\n旋转手机，或把窗口调整为横向。\n竖屏期间指令已锁定。" if portrait else "请将窗口调整到至少 480 × 320。\n窗口恢复后即可继续，战局已暂停。"
	if screen.y < 320.0:
		_notice_text.text = "战局已暂停。"
	_notice_title.add_theme_font_size_override("font_size", _font_size(22 if screen.y >= 320.0 else 18))
	_notice_text.add_theme_font_size_override("font_size", _font_size(15 if screen.y >= 320.0 else 13))

func refresh(selected: Array, camera_center: Vector2, paused: bool) -> void:
	if sim == null:
		return
	_last_selected = selected.duplicate()
	_paused = paused
	var wallet: Dictionary = sim.resources[0]
	for key in _resources:
		var amount := int(wallet.get(key, 0))
		_resources[key].text = ("%.1f万" % (amount / 10000.0)) if amount >= 10000 else str(amount)
		_resources[key].tooltip_text = "%s %d" % [Data.RESOURCE_NAMES[key], amount]
	var pop: Vector2i = sim.population(0)
	_population.text = "人口 %d/%d" % [pop.x, pop.y]
	_population.add_theme_color_override("font_color", BRASS if pop.x >= pop.y else MUTED)
	var elapsed := int(sim.elapsed)
	_time.text = "%02d:%02d%s" % [elapsed / 60, elapsed % 60, " · 暂停" if paused else ""]
	_map.camera_center = camera_center
	var entities: Array = []
	for id in selected:
		var entity: Dictionary = sim.entity(id)
		if not entity.is_empty() and float(entity.get("hp", 0)) > 0:
			entities.append(entity)
	_selection_image.texture = Icons.texture(str(entities[0].kind)) if not entities.is_empty() else Icons.texture("compass")
	_selection_info.disabled = entities.is_empty()
	var signature := str(selected) + "|" + _build_kind + "|" + _order_kind + "|tech:" + str(sim.tech[0])
	for entity in entities:
		signature += "|%s:%s:%s" % [entity.get("kind", ""), float(entity.get("built", 1.0)) >= 1.0, entity.get("team", 0)]
	if signature != _selected_signature:
		_selected_signature = signature
		_update_actions(entities)
		_refresh_action_sizing()
		_settle_frames = 6
	if entities.is_empty():
		_selection_title.text = "雾岸引航者"
		_selection_detail.text = "点击单位查看指令" if _compact else "选择单位或建筑以发出指令"
		_health.visible = false
	elif entities.size() > 1:
		_selection_title.text = "%d 个单位" % entities.size()
		_selection_detail.text = "点目标下令 · 多选追加"
		_health.visible = true
		var current := 0.0
		var maximum := 0.0
		for entity in entities:
			current += float(entity.get("hp", 0))
			maximum += float(entity.get("max_hp", 1))
		_health.max_value = maximum
		_health.value = current
	else:
		var entity: Dictionary = entities[0]
		var kind: String = entity.get("kind", "")
		_selection_title.text = Data.title(kind)
		_health.visible = entity.get("team", -1) >= 0
		_health.max_value = float(entity.get("max_hp", 1))
		_health.value = float(entity.get("hp", 0))
		var detail := "%d / %d  生命" % [int(entity.get("hp", 0)), int(entity.get("max_hp", 1))]
		if float(entity.get("built", 1.0)) < 1.0:
			detail = "建造中 · %d%%" % int(float(entity.get("built", 0)) * 100)
		elif not entity.get("queue", []).is_empty():
			var queued: Array = entity.get("queue", [])
			detail = "%s %d%% · 队列 %d" % [Data.title(queued[0]), mini(100, int(float(entity.get("train_progress", 0.0)) / float(Data.UNITS[queued[0]].train_time) * 100.0)), queued.size()]
		elif int(entity.get("carry", 0)) > 0:
			detail = "携带 %s %d" % [Data.RESOURCE_NAMES.get(entity.get("carry_kind", ""), "资源"), int(entity.carry)]
		elif entity.get("team", -1) == -1:
			detail = "选中拾光者，再点此资源采集"
		if entity.get("team", -1) == 0 and kind == "worker":
			var status: String = {"gather":"采集中 / 前往资源", "return":"运回物资", "build":"施工中 / 前往建筑", "move":"移动中", "idle":"待命：点资源开始采集", "attack":"攻击中"}.get(entity.get("state", ""), "")
			detail = status + (" · 携带 %d / 12" % int(entity.get("carry", 0)) if int(entity.get("carry", 0)) > 0 else "")
		_selection_detail.text = detail
	if not _build_kind.is_empty():
		_selection_detail.text = "放置 %s · Esc 取消" % Data.title(_build_kind)
	elif not _order_kind.is_empty():
		_selection_detail.text = {"gather":"请点资源 · 取消指令可退出", "move":"请点目的地 · 取消指令可退出", "attack":"请点敌人或目的地 · 沿途迎击"}.get(_order_kind, "")
	for child in _actions.get_children():
		if child is Button and child.has_meta("cost_kind"):
			var kind: String = child.get_meta("cost_kind")
			var affordable := true
			for resource in Data.COSTS.get(kind, {}):
				if int(wallet.get(resource, 0)) < int(Data.COSTS[kind][resource]):
					affordable = false
			child.modulate = Color.WHITE if affordable else Color(0.75, 0.78, 0.76)
			# Keep unaffordable actions clickable so the simulation explains the exact shortage.

func _update_actions(entities: Array) -> void:
	for child in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()
	if entities.is_empty():
		var hint := _label("守住回响心\n探索迷雾，夺回潮晶航线", 13, MUTED)
		_actions.add_child(hint)
		return
	if not _build_kind.is_empty():
		var cancel := _button("取消放置", "cancel")
		cancel.custom_minimum_size = Vector2(108, 62)
		_actions.add_child(cancel)
		return
	if not _order_kind.is_empty():
		var cancel := _button("取消指令", "cancel")
		cancel.custom_minimum_size = Vector2(108, 62)
		_actions.add_child(cancel)
		return
	var has_worker := false
	var production: Dictionary = {}
	for entity in entities:
		if entity.get("team", -1) != 0:
			continue
		if entity.get("kind", "") == "worker":
			has_worker = true
		if Data.BUILDINGS.has(entity.get("kind", "")) and float(entity.get("built", 1.0)) >= 1.0:
			production = entity
	if has_worker:
		var gather_button := _button("采集", "gather")
		gather_button.custom_minimum_size = Vector2(126, 62)
		_actions.add_child(gather_button)
		if _compact:
			_actions.add_child(_button("建造", "build_list"))
		else:
			for kind in ["house", "barracks", "tower"]:
				_add_action_card(kind, "build", "建造")
	elif not production.is_empty():
		var recruit := _button("招募中心", "recruit", int(production.id))
		recruit.custom_minimum_size = Vector2(188,68)
		_actions.add_child(recruit)
		if not _compact:
			for kind in Data.BUILDINGS[production.kind].get("trains", []):
				_add_action_card(kind, "train", "训练")
		if production.kind == "heart":
			var research := _button("潮晶共鸣", "research")
			research.tooltip_text = "花费：%s\n己方攻击 +25%%，采集速度 +20%%。" % Data.cost_text("research")
			research.set_meta("cost_kind", "research")
			research.custom_minimum_size = Vector2(120, 64)
			if sim.tech[0] >= 1:
				research.text = "共鸣已完成"
				research.disabled = true
			_actions.add_child(research)
	if entities.any(func(e): return e.get("team", -1) == 0 and Data.UNITS.has(e.get("kind", ""))):
		var move_button := _button("移动", "move")
		move_button.custom_minimum_size = Vector2(126, 62)
		_actions.add_child(move_button)
		var attack_button := _button("沿途迎击", "attack")
		attack_button.custom_minimum_size = Vector2(126, 62)
		_actions.add_child(attack_button)
	if _actions.get_child_count() == 0:
		var names: PackedStringArray = []
		for entity in entities:
			var name_text: String = Data.title(entity.get("kind", ""))
			if not names.has(name_text):
				names.append(name_text)
		var info := _label("、".join(names) + "\n选己方单位，再点目标下令", 13, MUTED)
		_actions.add_child(info)

func _add_action_card(kind: String, command: String, verb: String) -> void:
	var button := _button(Data.title(kind), command, kind)
	button.custom_minimum_size = Vector2(126 if _compact else 148, 62)
	button.add_theme_font_size_override("font_size", _font_size(16 if _compact else 18))
	button.tooltip_text = "%s%s · %s\n%s" % [verb, Data.title(kind), Data.cost_text(kind), Data.UNITS.get(kind, Data.BUILDINGS.get(kind, {})).get("description", "")]
	button.set_meta("cost_kind", kind)
	_actions.add_child(button)

func set_tutorial(step: int) -> void:
	if _tutorial_initialized and _tutorial_step == clampi(step, 0, TUTORIALS.size() - 1) and _tutorial_hidden == (step < 0):
		return
	_tutorial_initialized = true
	_tutorial_step = clampi(step, 0, TUTORIALS.size() - 1)
	_tutorial_hidden = step < 0
	_mission.visible = not _tutorial_hidden
	_mission_number.text = "引航手册  %02d / 08" % (_tutorial_step + 1)
	_update_tutorial_text()
	_mission.size.y = 0
	_settle_frames = 3

func _update_tutorial_text() -> void:
	var compact_hints := ["点工人开始引航", "点拾光者或「工人」", "选工人，再点资源采集", "选工人 → 织锋庭 → 空地", "选织锋庭 → 棱盾卫", "选军队，向东北方移动", "选军队，再点可见敌人", "摧毁敌方回响心"]
	_mission_number.text = "%02d · %s" % [_tutorial_step + 1, compact_hints[_tutorial_step]] if _small else "引航手册  %02d / 08" % (_tutorial_step + 1)
	_mission_title.text = TUTORIALS[_tutorial_step][0]
	_mission_text.text = TUTORIALS[_tutorial_step][1]

func show_toast(message: String) -> void:
	_toast_label.text = message
	_toast.visible = true
	_toast_time = 4.0
	_layout()

func set_drag_rect(rect: Rect2, active: bool) -> void:
	_drag.rectangle = rect.abs()
	_drag.active = active
	_drag.queue_redraw()

func set_order_mode(kind: String) -> void:
	_order_kind = kind

func set_build_mode(kind: String) -> void:
	if _build_kind == kind:
		return
	_build_kind = kind
	_selected_signature = ""
	if not kind.is_empty():
		show_toast("选择空地放置%s · 点「取消放置」可退出" % Data.title(kind))

func set_multiselect(enabled: bool) -> void:
	_multiselect = enabled
	if _multi_button != null:
		_multi_button.set_pressed_no_signal(enabled)
		_multi_button.text = "多选 ✓" if enabled else "多选"

func is_pointer_over_ui(point: Vector2) -> bool:
	if is_modal_open():
		return true
	for panel in [_top, _mission, _bottom, _map_panel, _warning]:
		if panel.visible and panel.get_global_rect().has_point(point):
			return true
	return false

func is_modal_open() -> bool:
	return (_modal != null and _modal.visible) or (_portrait != null and _portrait.visible)

func hide_menu() -> void:
	_modal.visible = false
	_page = ""
	_layout()

func _clear_modal() -> void:
	_modal_flow_rows.clear()
	_title_page_emblem = null
	_title_page_brand = null
	_recruit_grid = null
	_settings_tabs = null
	for container in [_modal_body, _modal_fixed]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()
	_modal_scroll.scroll_vertical = 0
	_modal_body.add_theme_constant_override("separation", 12)

func show_menu(page: String = "pause") -> void:
	if page in ["settings", "manual"] and _page not in ["settings", "manual"]:
		_return_page = _page if _page in ["main", "pause", "victory", "defeat"] else ""
	var opening := not _modal.visible or page != _page
	_page = page
	_modal_chrome.visible = page != "main"
	_modal_caption.text = {"pause":"引航者日志", "settings":"航行设置", "manual":"引航手册", "recruit":"招募中心", "build_list":"营地建设", "details":"单位档案", "victory":"战局结算", "defeat":"战局结算"}.get(page, "岚汐纪")
	_modal_back.text = "返回战场" if page in ["recruit", "build_list", "details", "pause"] else "返回"
	_modal_back.visible = page not in ["victory", "defeat"]
	_modal.color.a = 0.18 if page == "main" else 0.64
	_clear_modal()
	_modal.visible = true
	match page:
		"main": _main_menu()
		"pause": _pause_menu()
		"settings": _settings_menu()
		"manual": _manual_menu()
		"recruit": _recruitment_menu()
		"build_list": _build_catalog()
		"details": _unit_details()
		"victory", "defeat": _result_menu(page == "victory")
		_: _pause_menu()
	_layout_style_key = ""
	_settle_frames = 6
	_layout()
	if opening:
		if _modal_tween: _modal_tween.kill()
		_modal_panel.modulate.a = 0.0
		_modal_tween = create_tween()
		_modal_tween.tween_property(_modal_panel, "modulate:a", 1.0, 0.14)

func show_threat() -> void:
	_warning_time = 7.0
	_warning_effect.alert()
	_layout()

func clear_threat() -> void:
	_warning_time = 0.0
	_warning.visible = false
	_warning_effect.clear()

func show_recruitment(building_id: int, feedback: String = "") -> void:
	var same_building := _page == "recruit" and _recruit_id == building_id
	_recruit_id = building_id
	_recruit_feedback = feedback
	if same_building:
		_update_recruit_status()
	else: show_menu("recruit")

func _recruitment_menu() -> void:
	var building: Dictionary = sim.entity(_recruit_id)
	_recruit_wallet = _label("", 16, IVORY)
	_recruit_wallet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_modal_fixed.add_child(_recruit_wallet)
	_recruit_queue = _label("", 16, MIST)
	_recruit_queue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_modal_fixed.add_child(_recruit_queue)
	_recruit_notice = _label("", 16, BRASS)
	_recruit_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_modal_fixed.add_child(_recruit_notice)
	if building.is_empty() or building.get("team",-1) != 0:
		_recruit_notice.text = "需要己方回响心或已完工的织锋庭。"
		return
	_recruit_grid = GridContainer.new()
	_recruit_grid.columns = 2
	_recruit_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recruit_grid.add_theme_constant_override("h_separation", 12)
	_recruit_grid.add_theme_constant_override("v_separation", 12)
	_modal_body.add_child(_recruit_grid)
	for kind in Data.BUILDINGS[building.kind].get("trains",[]):
		var card := _catalog_card(kind, "recruit_unit", "招募" + Data.ROLES[kind])
		_recruit_grid.add_child(card)
	_update_recruit_status()

func _update_recruit_status() -> void:
	var building: Dictionary = sim.entity(_recruit_id)
	if building.is_empty() or not is_instance_valid(_recruit_wallet): return
	var wallet: Dictionary = sim.resources[0]
	var population: Vector2i = sim.population(0)
	_recruit_wallet.text = "穗粮 %d   枝材 %d   岚晶 %d   人口 %d/%d" % [wallet.food,wallet.wood,wallet.crystal,population.x,population.y]
	var queued: PackedStringArray = []
	for kind in building.queue: queued.append(Data.ROLES[kind])
	_recruit_queue.text = "队列 %d/5 · %s" % [building.queue.size(), " → ".join(queued) if not queued.is_empty() else "空闲"]
	_recruit_notice.text = _recruit_feedback if not _recruit_feedback.is_empty() else "战局已暂停 · 返回战场后训练"
	_recruit_notice.add_theme_color_override("font_color", UI.CORAL if "不足" in _recruit_feedback or "已满" in _recruit_feedback else BRASS)
	_settle_frames = 4

func _catalog_card(kind: String, command: String, caption: String) -> PanelContainer:
	var card := _panel()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	card.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	row.add_child(_icon(kind, 76))
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(names)
	var title := _label(Data.title(kind), 20, IVORY, true)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(title)
	if Data.ROLES.has(kind): names.add_child(_label(Data.ROLES[kind], 16, BRASS))
	var costs := _label(Data.cost_text(kind), 16, MUTED)
	costs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(costs)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	var recruit := _button(caption, command, kind, true)
	recruit.icon = null
	recruit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(recruit)
	var detail_toggle := _button("详情", "")
	for connection in detail_toggle.pressed.get_connections(): detail_toggle.pressed.disconnect(connection.callable)
	actions.add_child(detail_toggle)
	var definition: Dictionary = Data.UNITS.get(kind, Data.BUILDINGS.get(kind, {}))
	var description := str(definition.get("description", ""))
	if Data.UNITS.has(kind): description += "\n生命 %d · 攻击 %d · 射程 %.1f · 训练 %d 秒" % [definition.hp,definition.damage,definition.range,definition.train_time]
	var detail := _label(description, 16, MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.visible = false
	column.add_child(detail)
	detail_toggle.pressed.connect(func(): detail.visible = not detail.visible; detail_toggle.text = "收起" if detail.visible else "详情")
	return card

func _build_catalog() -> void:
	_modal_body.add_child(_label("选择建筑，再点战场空地放置", 18, MUTED))
	for kind in ["house", "barracks", "tower"]:
		_modal_body.add_child(_catalog_card(kind, "ui_build", "建造" + Data.title(kind)))

func _unit_details() -> void:
	var shown: Dictionary = {}
	for id in _last_selected:
		var entity: Dictionary = sim.entity(id)
		if entity.is_empty(): continue
		var kind: String = entity.kind
		if shown.has(kind): continue
		shown[kind] = true
		var row := HBoxContainer.new()
		_modal_body.add_child(row)
		row.add_child(_icon(kind, 72))
		var name_label := _label(Data.title(kind), 24, IVORY, true)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(name_label)
		var definition: Dictionary = Data.UNITS.get(kind, Data.BUILDINGS.get(kind, {}))
		_manual_section("生命 %d / %d" % [entity.hp, entity.max_hp], str(definition.get("description", "")))
		if Data.COSTS.has(kind): _modal_body.add_child(_label(Data.cost_text(kind), 16, BRASS))
		if Data.UNITS.has(kind): _modal_body.add_child(_label("攻击 %d · 射程 %.1f · 训练 %d 秒" % [definition.damage, definition.range, definition.train_time], 16, MIST))

func _modal_heading(eyebrow: String, heading: String, detail: String = "") -> void:
	_modal_body.add_child(_label(eyebrow, 12, BRASS))
	var title := _label(heading, 28, IVORY, true)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_modal_body.add_child(title)
	if not detail.is_empty():
		var label := _label(detail, 15, MUTED)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_modal_body.add_child(label)
	var line := HSeparator.new()
	line.add_theme_color_override("separator", Color("567873"))
	_modal_body.add_child(line)

func _main_menu() -> void:
	_modal_body.add_theme_constant_override("separation", 16)
	var crest := HBoxContainer.new()
	_modal_body.add_child(crest)
	_title_page_emblem = TideEmblem.new()
	_title_page_emblem.custom_minimum_size = Vector2(88,88)
	crest.add_child(_title_page_emblem)
	var mast := VBoxContainer.new()
	crest.add_child(mast)
	_title_page_brand = _label("岚汐纪", 48, IVORY, true)
	mast.add_child(_title_page_brand)
	mast.add_child(_label("潮  晶  之  争", 16, BRASS))
	var lore := _label("沿着潮晶的微光，向雾岸启程。", 18, MUTED)
	lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_modal_body.add_child(lore)
	_modal_body.add_child(HSeparator.new())
	_modal_body.add_child(_button("启程 · 新的战局", "start", null, true))
	var resume := _button("继续存档", "load")
	resume.disabled = not (FileAccess.file_exists("user://campaign.json") or FileAccess.file_exists("user://autosave.json"))
	_modal_body.add_child(resume)
	var links := BoxContainer.new()
	_modal_flow_rows.append(links)
	_modal_body.add_child(links)
	for entry in [["引航手册", "manual"], ["航行设置", "settings"]]:
		var button := _button(entry[0],entry[1])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		links.add_child(button)

func _pause_menu() -> void:
	_modal_heading("雾岸航线暂歇", "战局已暂停")
	_modal_body.add_child(_button("继续战局", "resume", null, true))
	var grid := GridContainer.new()
	grid.columns = 2
	_modal_body.add_child(grid)
	for entry in [["保存进度", "save"], ["读取存档", "load"], ["引航手册", "manual"], ["航行设置", "settings"]]:
		var button := _button(entry[0],entry[1])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if entry[1] == "load": button.disabled = not (FileAccess.file_exists("user://campaign.json") or FileAccess.file_exists("user://autosave.json"))
		grid.add_child(button)
	_modal_body.add_child(_button("重新开启教学", "replay_tutorial"))
	_modal_body.add_child(_button("重新开始战局", "restart"))

func _settings_menu() -> void:
	_settings_tabs = HBoxContainer.new()
	_modal_fixed.add_child(_settings_tabs)
	for entry in [["画面与文字", "display"], ["声音", "audio"], ["难度", "gameplay"]]:
		var tab := _button(entry[0], "")
		tab.icon = null
		tab.toggle_mode = true
		tab.button_pressed = _settings_tab == entry[1]
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for connection in tab.pressed.get_connections(): tab.pressed.disconnect(connection.callable)
		tab.pressed.connect(func(): _settings_tab = entry[1]; show_menu("settings"))
		_settings_tabs.add_child(tab)
	match _settings_tab:
		"display":
			_modal_body.add_child(_label("画面质量", 20, BRASS, true))
			_settings_choices([["流畅", "low"], ["均衡", "medium"], ["精致", "high"]], "quality", _quality)
			_modal_body.add_child(_label("文字大小", 20, BRASS, true))
			_settings_choices([["正常", false], ["大字 · 125%", true]], "large_text", _large_text)
			_manual_section("阅读与操作", "大字模式会同步调整布局。手机横屏游玩，按钮始终保留足够的点击空间。")
			if not OS.has_feature("mobile"):
				var full := _button("全屏显示", "")
				full.toggle_mode = true
				full.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
				for connection in full.pressed.get_connections(): full.pressed.disconnect(connection.callable)
				full.toggled.connect(func(on: bool): action.emit("fullscreen", on))
				_modal_body.add_child(full)
		"audio":
			_modal_body.add_child(_label("主音量", 20, BRASS, true))
			var slider := HSlider.new()
			slider.custom_minimum_size.y = 48
			slider.max_value = 1.0
			slider.step = 0.05
			slider.value = _volume
			slider.value_changed.connect(func(value: float): _volume = value; action.emit("volume", value))
			_modal_body.add_child(slider)
			_manual_section("雾岸的声音", "调节音乐、战斗提示与采集声的整体音量。")
		"gameplay":
			_modal_body.add_child(_label("人机难度", 20, BRASS, true))
			_settings_choices([["休闲 · 新手推荐", "relaxed"], ["标准", "standard"]], "difficulty", sim.difficulty)
			_manual_section("休闲", "前 8 分钟不主动出征，前两波最多 2 人、间隔 150 秒，敌军伤害降低 30%。切换后已出征敌军回营，留出至少 3 分钟准备；敌营仍会自卫。")
			_manual_section("标准", "首波约 90 秒，适合熟悉采集、建设和兵种配合的玩家。")

func _settings_choices(entries: Array, command: String, current: Variant) -> void:
	var row := BoxContainer.new()
	_modal_flow_rows.append(row)
	_modal_body.add_child(row)
	var group := ButtonGroup.new()
	for entry in entries:
		var button := _button(entry[0], command, entry[1])
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = entry[1] == current
		button.text = ("✓ " if button.button_pressed else "") + str(entry[0])
		button.toggled.connect(func(on: bool): button.text = ("✓ " if on else "") + str(entry[0]))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if command == "quality": button.pressed.connect(func(): _quality = entry[1])
		row.add_child(button)

func _manual_menu() -> void:
	_modal_heading("随时查阅的引航手册", "游玩说明书", "目标：摧毁敌方回响心，并保护自己的回响心。")
	_manual_section("第一次启程", "默认休闲人机，前 8 分钟不主动出征。点底部「招募」打开居中的招募中心，花费穗粮等资源生产工人和士兵。每个队列最多 5 人；返回战场后训练继续。先选择拾光者，指派它采集穗果丛和风铃木。用枝材建造织锋庭，生产棱盾卫与弦光手。人口将满时建风栖居。积攒岚晶后训练裂岩兽，集合军队探索东北方的敌营。")
	_manual_section("鼠标与键盘", "点选己方单位，再普通点击空地移动、资源采集或敌人攻击；右键也可下令。拖框多选；Shift 或「多选」添加选择。工人可点「采集」后点资源；「取消指令」退出。滚轮或双指捏合缩放，方向键、中键或触控板双指平移镜头。H 回营，A 沿途迎击，S 停止，B 建造风栖居，空格暂停，Esc 取消或开关菜单，F1 打开手册，F5 保存，F9 读取。Ctrl（Mac 也可用 Command）+ 1～5 保存编队，1～5 选取编队。")
	_manual_section("手机与平板", "点选单位后，点空地移动，点资源采集，点敌人攻击。拖动空地移动镜头，双指缩放。「多选」打开后可连续点选单位；关闭后恢复单选。「工人」「军队」快速选择，海图移动镜头。手机请横屏游玩。")
	_manual_section("资源与人口", "穗粮来自穗果丛，用于生产单位；枝材来自风铃木，用于建筑及武器；岚晶来自矿脉，用于精锐部队、哨塔和科技。拾光者每次携带 12 份回营交付。回响心提供 10 人口，风栖居建成后增加 6 人口。建造时先选工人，再选建筑，最后点空地。")
	for kind in ["heart", "house", "barracks", "tower"]:
		_manual_section(Data.title(kind), Data.BUILDINGS[kind].description + ("\n花费：" + Data.cost_text(kind) if Data.COSTS.has(kind) else ""))
	for kind in Data.UNITS:
		_manual_section(Data.ROLES[kind]+" · "+Data.title(kind), Data.UNITS[kind].description + "\n花费：" + Data.cost_text(kind))
	_manual_section("探索与交战", "未探索区域被深雾覆盖；探索过但当前无己方视野的区域会变暗，敌军只在己方视野中显示。不要让远程部队单独冲锋。辉棱哨会自动防守，裂岩兽适合摧毁建筑。敌我阵营还通过圆环、方形与建筑轮廓区分。")
	_manual_section("柔和采集音效", "摘果有轻轻的摘取与叶片声，伐木是温润的木头敲击声，采矿是柔和的晶石声。只在附近画面内实际采集时响起，多人工作会自动减少叠加。可在设置中调节音量，暂停时采集音也会停止。")
	_manual_section("科技与存档", "选中回响心使用「潮晶共鸣」，己方攻击提高 25%，采集速度提高 20%；花费穗粮 100、枝材 100、岚晶 60，每局只能研究一次。通过菜单保存当前战局，读取存档会替换正在进行的战局。重新开始会创建新的初始战局。")
	_manual_section("常见问题", "资源不足：继续采集，留意工人是否已把物资送回。无法建造：远离建筑、资源、地图边缘和其他障碍。无法训练：等待建筑完成，并检查资源和人口。部队拥挤：分批下令或选择更宽的路线。画面卡顿：在设置中切换流畅档。")
	var tutorial := _button("重新开启分步教学", "replay_tutorial", null, true)
	_modal_body.add_child(tutorial)
	_add_back_button()

func _manual_section(heading: String, text: String) -> void:
	var paragraph := _label(text, 18, MUTED)
	paragraph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _page == "manual":
		var toggle := _button(heading, "")
		toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
		toggle.toggle_mode = true
		toggle.button_pressed = _manual_open.get(heading, false)
		paragraph.visible = toggle.button_pressed
		for connection in toggle.pressed.get_connections(): toggle.pressed.disconnect(connection.callable)
		toggle.toggled.connect(func(on: bool): paragraph.visible = on; _manual_open[heading] = on)
		_modal_body.add_child(toggle)
	else: _modal_body.add_child(_label(heading, 20, BRASS, true))
	_modal_body.add_child(paragraph)

func _result_menu(victory: bool) -> void:
	_modal_heading("潮晶再度鸣响" if victory else "回响渐入沉寂", "胜利 · 航线重归雾岸" if victory else "战败 · 回响心失守", "赤铜远征队的回响心已被摧毁。群岛的航线，再次属于你。" if victory else "你的回响心已失守。重新组织采集与防守，再向雾岸启程。")
	var elapsed := int(sim.elapsed) if sim != null else 0
	_modal_body.add_child(_label("战局用时  %02d:%02d" % [elapsed / 60, elapsed % 60], 19, MIST))
	_modal_body.add_child(_button("再次启程", "restart", null, true))
	_modal_body.add_child(_button("查看游玩说明", "manual"))

func _add_back_button() -> void:
	# Navigation lives in fixed chrome, outside the scrolling document.
	pass
