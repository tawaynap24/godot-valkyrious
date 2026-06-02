extends Node2D

const SPLASH_DURATION: float = 1.5

var _timer: float = 0.0

func _ready() -> void:
	UIShell.hide_shell()

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= SPLASH_DURATION:
		set_process(false)
		# Route through Loading so the initial preload (textures, card scene)
		# runs before the Lobby opens. LoadingScreen detects the empty target
		# and runs the preload sequence automatically.
		SceneManager.go_to_initial_loading()
