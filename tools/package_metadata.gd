extends SceneTree
func _initialize() -> void:
	var notices := "Godot Engine\n\n" + Engine.get_license_text() + "\n\nBundled library attribution\n"
	for entry in Engine.get_copyright_info():
		notices += "\n" + str(entry)
	var licenses: Dictionary = Engine.get_license_info()
	for key in licenses:
		notices += "\n\n" + str(key) + "\n" + str(licenses[key])
	var file := FileAccess.open("res://docs/THIRD_PARTY_NOTICES.txt", FileAccess.WRITE)
	file.store_string(notices)
	file.close()
	var icon := Image.new()
	icon.load_svg_from_string(FileAccess.get_file_as_string("res://icon.svg"), 4.0)
	icon.save_png("res://builds/icon-1024.png")
	quit()
