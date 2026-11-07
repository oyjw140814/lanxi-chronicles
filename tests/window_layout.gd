extends SceneTree
var failures := 0
var checks := 0
var font_checks := 0
var _large := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL ",detail)
func audit_text(node: Node) -> void:
	if node is Control and not node.is_visible_in_tree(): return
	if node is Label or node is Button:
		font_checks += 1
		check(node.get_theme_font_size("font_size") >= (20 if _large else 16), "small text: " + node.text.left(40))
	for child in node.get_children(): audit_text(child)

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var hud = load("res://scripts/hud.gd").new(); root.add_child(hud)
	var sim = load("res://scripts/simulation.gd").new(); hud.setup(sim)
	hud._recruit_id = int(sim.entities[0].id)
	var worker := -1
	for e in sim.entities:
		if e.team == 0 and e.kind == "worker": worker=e.id; break
	var sizes := [Vector2i(3440,1440),Vector2i(1470,837),Vector2i(1920,1080),Vector2i(640,480),Vector2i(700,400),Vector2i(1049,649),Vector2i(1051,651),Vector2i(1049,499),Vector2i(1280,800),Vector2i(844,390),Vector2i(480,320),Vector2i(800,320),Vector2i(320,180),Vector2i(200,100),Vector2i(390,844),Vector2i(1024,768),Vector2i(1920,1080)]
	for repeat in range(2):
		_large = repeat == 1
		hud.set_large_text(_large)
		for size in sizes:
			root.size=size
			hud.hide_menu()
			hud.set_build_mode("house" if repeat==1 else "")
			for frame in range(10):
				hud.refresh([worker],Vector2(20,60),false)
				await process_frame
			audit_text(hud._root)
			var bounds := Rect2(Vector2.ZERO,Vector2(size))
			for panel in [hud._top,hud._mission,hud._bottom,hud._map_panel,hud._portrait]:
				if panel.is_visible_in_tree():
					check(bounds.grow(0.1).encloses(panel.get_global_rect()),"panel "+str(size)+str(panel.get_global_rect()))
			if hud._portrait.is_visible_in_tree():
				for node in [hud._notice_title,hud._notice_text,hud._notice_brand,hud._notice_emblem]:
					if node.is_visible_in_tree():
						check(bounds.encloses(node.get_global_rect()), "window notice overflow " + str(size))
			if hud._bottom.is_visible_in_tree():
				check(not hud._map_panel.is_visible_in_tree() or not hud._bottom.get_global_rect().intersects(hud._map_panel.get_global_rect()),"bottom overlaps map "+str(size))
				check(absf(hud._bottom.get_global_rect().end.y-(size.y-(10 if hud._compact else 18)))<0.1,"bottom margin "+str(size))
			for page in ["main","pause","settings","manual","recruit","victory","defeat", "build_list", "details"]:
				hud.show_menu(page)
				for frame in range(8): await process_frame
				if hud._modal_panel.is_visible_in_tree():
					audit_text(hud._modal_panel)
					check(bounds.grow(0.1).encloses(hud._modal_panel.get_global_rect()),"modal "+page+str(size)+str(hud._modal_panel.get_global_rect()))
					check(hud._modal_body.size.x <= hud._modal_scroll.size.x+0.1,"modal body overflow "+page+str(size))
			# Exercise a growing resource counter in the same width without changing layout modes.
			hud.hide_menu()
			sim.resources[0]={"food":999999999,"wood":999999999,"crystal":999999999}
			hud.refresh([worker],Vector2(20,60),false)
			for frame in range(8): await process_frame
			if hud._top.is_visible_in_tree(): check(bounds.encloses(hud._top.get_global_rect()),"resource header overflow "+str(size))
	check(hud._theme.get_font_size("font_size", "TooltipLabel") >= (20 if _large else 16), "tooltip font")
	print("HUD_RESIZE_CHECKS ",checks," FONT_CHECKS ",font_checks," FAILURES ",failures)
	quit(1 if failures else 0)
