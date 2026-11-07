extends Node
var failures := 0
var checks := 0
var trace_lines := PackedStringArray()
func trace_line(line: String) -> void:
    trace_lines.append(line)
    print(line)
func _ready() -> void: call_deferred("run_check")
func verify(ok: bool, detail: String) -> void:
    checks += 1
    if not ok: failures += 1
    trace_line("EDITOR_GAME_CHECK " + ("PASS " if ok else "FAIL ") + detail)
func snapshot(label: String) -> void:
    var w := get_window()
    var v := get_viewport()
    var game := get_parent()
    var logical := Vector2(Vector2i(Vector2(w.size) / game._display_density()))
    verify(logical.is_equal_approx(v.get_visible_rect().size), label + " logical viewport follows display density")
    verify(Vector2(v.get_texture().get_image().get_size()).is_equal_approx(Vector2(w.size)), label + " render target follows window")
    verify(game.hud._root.size.is_equal_approx(logical), label + " HUD follows logical window")
    verify((v.get_screen_transform() * logical).distance_to(Vector2(w.size)) < 1.0, label + " logical UI fills native window")
    verify(game.hud._theme.default_font_size >= 26, label + " large default font is active")
    var focus: Vector2 = game.camera_focus
    var screen: Vector2 = game.camera.unproject_position(Vector3(focus.x,0,focus.y))
    verify(game.ground_point(screen).distance_to(focus)<0.01, label + " picking projection stays aligned")
    trace_line("EDITOR_GAME_SIZE %s native=%s viewport=%s mode=%s native_mode=%s args=%s" % [label,w.size,v.get_visible_rect().size,w.mode,DisplayServer.window_get_mode(),OS.get_cmdline_args()])
    await RenderingServer.frame_post_draw
    v.get_texture().get_image().save_png("res://results/"+label+".png")
func run_check() -> void:
    get_parent()._test_running = true
    get_window().title = "岚汐纪 · 启动适配自动检查"
    await get_tree().create_timer(1.0).timeout
    verify(not "--embedded" in OS.get_cmdline_args(), "Play uses native game window")
    # macOS can report WINDOWED for a maximized frame differing by 1-2 pixels.
    # Assert actual coverage of the usable screen, which is what the player sees.
    var usable := DisplayServer.screen_get_usable_rect()
    var outer := DisplayServer.window_get_size_with_decorations()
    verify(absi(outer.x - usable.size.x) <= 8 and absi(outer.y - usable.size.y) <= 8, "Play fills usable display")
    await snapshot("editor-start")
    get_window().mode = Window.MODE_WINDOWED
    await get_tree().create_timer(1.0).timeout
    get_window().size=Vector2i(1280,800)
    await get_tree().create_timer(0.5).timeout
    await snapshot("restored")
    get_window().size=Vector2i(1920,1080)
    await get_tree().create_timer(0.5).timeout
    await snapshot("resized")
    get_window().mode=Window.MODE_MAXIMIZED
    await get_tree().create_timer(1.0).timeout
    await snapshot("maximized-again")
    var log_file := FileAccess.open("res://results/game-window.log",FileAccess.WRITE)
    log_file.store_string("\n".join(trace_lines))
    log_file.close()
    var out := FileAccess.open("res://results/complete.txt",FileAccess.WRITE)
    out.store_string("checks=%d failures=%d" % [checks,failures])
    out.close()
