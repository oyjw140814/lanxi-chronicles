@tool
extends EditorPlugin
func _enter_tree() -> void:
    if "--verify-editor-play" in OS.get_cmdline_user_args():
        call_deferred("run_check")
func run_check() -> void:
    get_window().title = "岚汐纪 · 编辑器启动自动检查（请稍候）"
    await get_tree().create_timer(2.0).timeout
    print("EDITOR_LAUNCH_MODE ", ProjectSettings.get_setting("display/window/size/mode"))
    EditorInterface.play_main_scene()
    for attempt in range(40):
        await get_tree().create_timer(0.5).timeout
        if FileAccess.file_exists("res://results/complete.txt"):
            var summary := FileAccess.get_file_as_string("res://results/complete.txt")
            print("EDITOR_PLAY_VERIFIED ", summary)
            EditorInterface.stop_playing_scene()
            await get_tree().create_timer(0.5).timeout
            get_tree().quit(0 if summary.ends_with("failures=0") else 1)
            return
    print("EDITOR_PLAY_CHECK_TIMEOUT")
    EditorInterface.stop_playing_scene()
    get_tree().quit(1)
