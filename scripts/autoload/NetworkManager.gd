extends Node

# ─────────────────────────────────────────────────────────────────────────────
# NetworkManager — WebSocket client autoload
#
# Autoload singleton — accessible everywhere as "NetworkManager".
#
# Usage:
#   NetworkManager.connect_to_server()
#   NetworkManager.send_create_room()
#   NetworkManager.send_join_room("ABCD")
#   NetworkManager.send_join_random()
#   NetworkManager.send_action({"type":"deploy","card_id":"ange","row":2,"col":1})
#   NetworkManager.send_game_over("owner")   # my_role won
#   NetworkManager.disconnect_from_server()
#
# Change SERVER_URL to point at your deployed server.
# ─────────────────────────────────────────────────────────────────────────────

# ── Signals ───────────────────────────────────────────────────────────────────
signal connected_to_server
signal disconnected_from_server
signal room_created(code: String)
signal waiting_for_opponent
signal match_found(role: String, seed: int)
signal opponent_action_received(action: Dictionary)
signal game_over_received(winner: String)
signal opponent_profile_received(opp_name: String, opp_icon: String)
signal opponent_disconnected
signal error_received(message: String)

# ── Config ────────────────────────────────────────────────────────────────────
const SERVER_URL := "ws://localhost:8765"

# ── State ─────────────────────────────────────────────────────────────────────
var _socket:     WebSocketPeer = null
var is_connected: bool  = false

## Set by the server at match start.  "owner" = first player, "enemy" = second.
var my_role:     String = ""
var match_seed:  int    = 0

## Populated when opponent sends their profile.
var opponent_name: String = ""
var opponent_icon: String = ""  # card_id

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	set_process(false)

func _process(_delta: float) -> void:
	if _socket == null:
		return
	_socket.poll()
	var state := _socket.get_ready_state()
	match state:
		WebSocketPeer.STATE_OPEN:
			if not is_connected:
				is_connected = true
				emit_signal("connected_to_server")
			while _socket.get_available_packet_count() > 0:
				var raw  := _socket.get_packet()
				var text := raw.get_string_from_utf8()
				_on_message(text)
		WebSocketPeer.STATE_CLOSED:
			if is_connected:
				is_connected = false
				emit_signal("disconnected_from_server")
			set_process(false)
			_socket = null

# ── Connect / Disconnect ──────────────────────────────────────────────────────

func connect_to_server() -> void:
	if _socket != null:
		_socket.close()
	_socket = WebSocketPeer.new()
	var err := _socket.connect_to_url(SERVER_URL)
	if err != OK:
		push_error("NetworkManager: connect failed (%s)" % str(err))
		emit_signal("error_received", "Cannot connect to server")
		return
	set_process(true)

func disconnect_from_server() -> void:
	if _socket != null:
		_socket.close()
		_socket = null
	is_connected = false
	set_process(false)

# ── Message dispatch ──────────────────────────────────────────────────────────

func _on_message(text: String) -> void:
	var result = JSON.parse_string(text)
	if result == null or not result is Dictionary:
		return
	var msg: Dictionary = result
	match msg.get("type", ""):
		"room_created":
			emit_signal("room_created", msg.get("code", ""))
		"waiting":
			emit_signal("waiting_for_opponent")
		"match_found":
			my_role    = msg.get("role", "owner")
			match_seed = msg.get("seed", 0)
			opponent_name = ""
			opponent_icon = ""
			emit_signal("match_found", my_role, match_seed)
		"opponent_action":
			var act = msg.get("action", {})
			print("[NetworkManager] opponent_action received: ", act)
			emit_signal("opponent_action_received", act)
		"profile":
			opponent_name = msg.get("player_name", "")
			opponent_icon = msg.get("profile_icon", "")
			emit_signal("opponent_profile_received", opponent_name, opponent_icon)
		"game_over":
			emit_signal("game_over_received", msg.get("winner", "draw"))
		"opponent_disconnected":
			emit_signal("opponent_disconnected")
		"error":
			emit_signal("error_received", msg.get("message", "Unknown error"))
		"pong":
			pass  # keepalive acknowledged

# ── Send helpers ──────────────────────────────────────────────────────────────

func send_create_room() -> void:
	_send({"type": "create_room"})

func send_join_room(code: String) -> void:
	_send({"type": "join_room", "code": code.to_upper()})

func send_join_random() -> void:
	_send({"type": "join_random"})

func send_action(action: Dictionary) -> void:
	_send({"type": "action", "action": action})

## Call once when the local game ends — tells the server who won.
## winner must be the SERVER role string: "owner", "enemy", or "draw".
func send_game_over(winner: String) -> void:
	_send({"type": "game_over", "winner": winner})

func send_profile(player_name: String, profile_icon: String) -> void:
	_send({"type": "profile", "player_name": player_name, "profile_icon": profile_icon})

func send_ping() -> void:
	_send({"type": "ping"})

func _send(obj: Dictionary) -> void:
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		push_warning("NetworkManager: send attempted while not connected")
		return
	_socket.send_text(JSON.stringify(obj))
