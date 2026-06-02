extends Node

# ─────────────────────────────────────────────────────────────────────────────
# SceneManager — handles all scene transitions
# Usage:
#   SceneManager.go_to_lobby()
#   SceneManager.go_to_battle_ai()
#   SceneManager.load_scene("res://scenes/SomeScene.tscn")
# ─────────────────────────────────────────────────────────────────────────────

const SPLASH_SCENE        = "res://scenes/splash.tscn"
const LOADING_SCENE       = "res://scenes/loading.tscn"
const LOBBY_SCENE         = "res://scenes/lobby.tscn"
const BATTLE_SCENE        = "res://scenes/battle/battle.tscn"
const DECK_BUILDER_SCENE  = "res://scenes/deck_builder.tscn"
const COLLECTION_SCENE    = "res://scenes/collection.tscn"
const GACHA_SCENE         = "res://scenes/gacha.tscn"
const MATCHMAKING_SCENE   = "res://scenes/matchmaking.tscn"
const SHOP_SCENE          = "res://scenes/shop.tscn"
const RECORDS_SCENE       = "res://scenes/records.tscn"

## Set before loading the battle scene so GameManager knows which mode to run.
## Values: "ai" | "online"
var battle_mode: String = "ai"

# Stored by load_scene(), read once by LoadingScreen
var _target_scene: String = ""

func go_to_lobby() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)

## Called by SplashScreen on first run — takes the Loading screen path with
## an empty target so LoadingScreen runs the initial preload sequence.
func go_to_initial_loading() -> void:
	# _target_scene stays "" — LoadingScreen detects this and runs preload
	get_tree().change_scene_to_file(LOADING_SCENE)

func go_to_deck_builder() -> void:
	get_tree().change_scene_to_file(DECK_BUILDER_SCENE)

func go_to_collection() -> void:
	get_tree().change_scene_to_file(COLLECTION_SCENE)

func go_to_gacha() -> void:
	get_tree().change_scene_to_file(GACHA_SCENE)

func go_to_battle_ai() -> void:
	battle_mode = "ai"
	load_scene(BATTLE_SCENE)

func go_to_battle_online() -> void:
	battle_mode = "online"
	load_scene(BATTLE_SCENE)

func go_to_matchmaking() -> void:
	get_tree().change_scene_to_file(MATCHMAKING_SCENE)

func go_to_shop() -> void:
	get_tree().change_scene_to_file(SHOP_SCENE)

func go_to_records() -> void:
	get_tree().change_scene_to_file(RECORDS_SCENE)

func load_scene(path: String) -> void:
	_target_scene = path
	get_tree().change_scene_to_file(LOADING_SCENE)

# Called by LoadingScreen — clears the target after reading
func get_target_scene() -> String:
	var t = _target_scene
	_target_scene = ""
	return t
