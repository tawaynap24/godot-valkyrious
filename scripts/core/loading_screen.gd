extends Node2D

var _target: String = ""

func _ready() -> void:
	UIShell.hide_shell()
	$ProgressBar.value = 0.0
	_target = SceneManager.get_target_scene()

	if _target == "":
		# ── Initial preload path (Splash → Loading → Lobby) ──────────────────
		# _process is not needed here; the coroutine drives everything.
		set_process(false)
		_run_initial_preload.call_deferred()
	else:
		# ── Battle scene path (threaded background load) ──────────────────────
		$StatusLabel.text = "Loading battle..."
		ResourceLoader.load_threaded_request(_target)

# ── Initial Preload (runs once on first launch) ───────────────────────────────

func _run_initial_preload() -> void:
	if GameCache.is_preloaded():
		# Already done in a previous session visit — skip straight to Lobby
		$ProgressBar.value = 100.0
		$StatusLabel.text = "Ready!"
		await get_tree().create_timer(0.1).timeout
		SceneManager.go_to_lobby()
		return

	# Stage 1 — Card battle scene (0 → 15%)
	$StatusLabel.text = "Loading card scene..."
	$ProgressBar.value = 5.0
	await get_tree().process_frame

	GameCache.CARD_SCENE = load("res://scenes/battle/card.tscn")
	$ProgressBar.value = 15.0
	await get_tree().process_frame

	# Stage 2 — Card artwork textures (15 → 95%)
	var ids: Array = CardDatabase.CARDS.keys()
	var n: int = ids.size()
	for i in range(n):
		var data: Dictionary = CardDatabase.CARDS[ids[i]]
		if data.get("has_image", false):
			var path: String = data.get("image_path", "")
			if path != "" and not GameCache.TEXTURES.has(path) and ResourceLoader.exists(path):
				var res = ResourceLoader.load(path)
				if res is Texture2D:
					GameCache.TEXTURES[path] = res
		# Update UI every 4 cards to keep the progress bar smooth
		if i % 4 == 0:
			$ProgressBar.value = 15.0 + 80.0 * float(i + 1) / float(n)
			$StatusLabel.text = "Loading artwork... (%d / %d)" % [i + 1, n]
			await get_tree().process_frame

	# Stage 3 — Done
	GameCache.mark_preloaded()
	$ProgressBar.value = 100.0
	$StatusLabel.text = "Ready!"
	await get_tree().create_timer(0.2).timeout
	SceneManager.go_to_lobby()

# ── Battle Scene Load (_process only active when _target != "") ───────────────

func _process(_delta: float) -> void:
	var progress: Array = []
	var status = ResourceLoader.load_threaded_get_status(_target, progress)

	if progress.size() > 0:
		$ProgressBar.value = progress[0] * 100.0

	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			set_process(false)
			var packed = ResourceLoader.load_threaded_get(_target) as PackedScene
			if packed:
				get_tree().change_scene_to_packed(packed)
			else:
				push_error("LoadingScreen: resource is not a PackedScene — " + _target)
				SceneManager.go_to_lobby()

		ResourceLoader.THREAD_LOAD_FAILED:
			set_process(false)
			push_error("LoadingScreen: failed to load — " + _target)
			SceneManager.go_to_lobby()

		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			set_process(false)
			push_error("LoadingScreen: invalid resource — " + _target)
			SceneManager.go_to_lobby()

