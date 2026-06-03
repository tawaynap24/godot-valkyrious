extends Node2D

# ─────────────────────────────────────────────────────────────────────────────
# MatchmakingScreen — handles connect, create room, join room, random match
#
# States:
#   IDLE        → show three option buttons
#   CONNECTING  → connecting to server
#   CREATE_WAIT → room created, showing code, waiting for opponent
#   JOIN_WAIT   → joining room, waiting
#   RANDOM_WAIT → in random queue
#   MATCHED     → match found, transitioning to battle
# ─────────────────────────────────────────────────────────────────────────────

enum State { IDLE, CONNECTING, CREATE_WAIT, JOIN_WAIT, RANDOM_WAIT, MATCHED }

var _state: State = State.IDLE
var _pending_action: String = ""   # "create" | "join" | "random" — queued while connecting

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_wire_ui()
	_wire_network()
	_set_state(State.IDLE)
	UIShell.set_active_tab("battle")

func _wire_ui() -> void:
	$TopBar/BackButton.pressed.connect(_on_back)
	$CreateRoomBtn.pressed.connect(_on_create_room)
	$JoinSection/JoinRoomBtn.pressed.connect(_on_join_room)
	$RandomMatchBtn.pressed.connect(_on_random_match)
	$CancelBtn.pressed.connect(_on_cancel)

func _wire_network() -> void:
	NetworkManager.connected_to_server.connect(_on_connected)
	NetworkManager.disconnected_from_server.connect(_on_disconnected)
	NetworkManager.room_created.connect(_on_room_created)
	NetworkManager.waiting_for_opponent.connect(_on_waiting)
	NetworkManager.match_found.connect(_on_match_found)
	NetworkManager.error_received.connect(_on_error)

# ── State machine ─────────────────────────────────────────────────────────────

func _set_state(s: State) -> void:
	_state = s
	var btns_visible: bool = (s == State.IDLE)
	$CreateRoomBtn.visible  = btns_visible
	$JoinSection.visible    = btns_visible
	$RandomMatchBtn.visible = btns_visible
	$OrLabel.visible        = btns_visible

	$RoomCodePanel.visible  = (s == State.CREATE_WAIT)
	$CancelBtn.visible      = (s != State.IDLE and s != State.MATCHED)

	match s:
		State.IDLE:
			_set_status(tr("UI_SELECT_PLAY_MODE"))
		State.CONNECTING:
			_set_status(tr("UI_CONNECTING_TO_SERVER"))
		State.CREATE_WAIT:
			_set_status(tr("UI_WAITING_FOR_OTHER_PLAYERS"))
		State.JOIN_WAIT:
			_set_status(tr("UI_ENTERING_ROOM"))
		State.RANDOM_WAIT:
			_set_status(tr("UI_SEARCHING_FOR_OPPONENT"))
		State.MATCHED:
			_set_status(tr("UI_MATCH_FOUND"))


func _set_status(text: String) -> void:
	$StatusPanel/StatusLabel.text = text

# ── Button handlers ───────────────────────────────────────────────────────────

func _on_back() -> void:
	NetworkManager.disconnect_from_server()
	SceneManager.go_to_lobby()

func _on_create_room() -> void:
	_pending_action = "create"
	_connect_then_act()

func _on_join_room() -> void:
	var code: String = $JoinSection/CodeInput.text.strip_edges()
	if code.length() < 4:
		_set_status(tr("UI_ENTER_ROOM_CODE"))
		return
	_pending_action = "join:" + code.to_upper()
	_connect_then_act()

func _on_random_match() -> void:
	_pending_action = "random"
	_connect_then_act()

## Cancel while waiting / connecting
func _on_cancel() -> void:
	NetworkManager.disconnect_from_server()
	_set_state(State.IDLE)

func _connect_then_act() -> void:
	if NetworkManager.is_connected:
		_dispatch_pending()
	else:
		_set_state(State.CONNECTING)
		NetworkManager.connect_to_server()

func _dispatch_pending() -> void:
	if _pending_action == "create":
		_set_state(State.CREATE_WAIT)
		NetworkManager.send_create_room()
	elif _pending_action.begins_with("join:"):
		_set_state(State.JOIN_WAIT)
		NetworkManager.send_join_room(_pending_action.substr(5))
	elif _pending_action == "random":
		_set_state(State.RANDOM_WAIT)
		NetworkManager.send_join_random()
	_pending_action = ""

# ── Network callbacks ─────────────────────────────────────────────────────────

func _on_connected() -> void:
	_dispatch_pending()

func _on_disconnected() -> void:
	if _state != State.MATCHED:
		_set_state(State.IDLE)
		_set_status(tr("ERROR_CONNECTION_LOST"))

func _on_room_created(code: String) -> void:
	$RoomCodePanel/RoomCodeLabel.text = tr("UI_ROOM_CODE") + "\n" + code
	_set_state(State.CREATE_WAIT)

func _on_waiting() -> void:
	_set_state(State.RANDOM_WAIT)

func _on_match_found(_role: String, _seed: int) -> void:
	_set_state(State.MATCHED)
	await get_tree().create_timer(1.0).timeout
	SceneManager.go_to_battle_online()

func _on_error(message: String) -> void:
	_set_status(tr("ERROR_PREFIX") + tr(message))
	_set_state(State.IDLE)
