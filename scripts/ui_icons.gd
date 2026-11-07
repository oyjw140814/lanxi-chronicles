extends RefCounted
## Original SVG symbols and offline portraits rendered from the game's own models.
const COMMANDS := {
	"select_workers":"worker", "select_army":"guard", "recruit":"recruit",
	"home":"home", "stop":"stop", "multiselect":"select", "pause":"pause",
	"gather":"gather", "move":"move", "attack":"attack", "research":"crystal",
	"cancel":"close", "start":"compass", "resume":"play", "load":"load",
	"save":"save", "manual":"book", "settings":"settings", "restart":"restart",
	"replay_tutorial":"compass", "focus_threat":"alert", "build_list":"build",
	"map_toggle":"map", "details":"info", "ui_back":"back"
}
static var cache: Dictionary = {}

static func texture(key: String) -> Texture2D:
	if cache.has(key): return cache[key]
	var path := "res://assets/ui/portraits/%s.png" % key
	if not ResourceLoader.exists(path): path = "res://assets/ui/icons/%s.svg" % key
	if not ResourceLoader.exists(path): return null
	cache[key] = load(path)
	return cache[key]

static func command(key: String, payload: Variant = null) -> Texture2D:
	if key in ["build", "train", "recruit_unit"]: return texture(str(payload))
	if key == "zoom": return texture("minus" if int(payload) < 0 else "plus")
	return texture(COMMANDS.get(key, key))
