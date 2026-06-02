extends Node

# ─────────────────────────────────────────────────────────────────────────────
# GameCache — centralized resource cache (AutoLoad singleton).
#
# Populated once during the Loading scene's initial pass (Splash → Loading →
# Lobby). After that every screen reads from memory — no disk access.
#
# Usage:
#   GameCache.CARD_SCENE              → PackedScene for battle/Card.tscn
#   GameCache.get_texture(path)       → Texture2D from cache (or null)
#   GameCache.is_preloaded()          → true after initial preload is done
# ─────────────────────────────────────────────────────────────────────────────

## The card battle scene — preloaded once, reused for every card draw.
var CARD_SCENE: PackedScene = null

## Image textures keyed by res:// path. Populated by LoadingScreen.
var TEXTURES: Dictionary = {}

var _preloaded: bool = false

# ── Public API ────────────────────────────────────────────────────────────────

func is_preloaded() -> bool:
	return _preloaded

func mark_preloaded() -> void:
	_preloaded = true

## Returns cached Texture2D for path, or null if not found.
## Includes a lazy-load fallback for any card whose image was missed during
## the initial preload (e.g. newly added resources).
func get_texture(path: String) -> Texture2D:
	if path == "":
		return null
	if TEXTURES.has(path):
		return TEXTURES[path]
	# Lazy fallback — should rarely trigger after initial preload
	if ResourceLoader.exists(path):
		var res = ResourceLoader.load(path)
		if res is Texture2D:
			TEXTURES[path] = res
			return res
	return null
