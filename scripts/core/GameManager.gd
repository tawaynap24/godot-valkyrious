extends Node2D

const MATCH_DURATION: float = 30.0
const MAX_COST: int = 10
const COST_INTERVAL_NORMAL: float = 2.0     # +1 per 2s
const COST_INTERVAL_FAST: float = 1.3333    # +1 per 1.333s (x1.5) when ≤15s remaining
const FAST_TIME_THRESHOLD: float = 15.0
const INITIAL_COST: int = 7
const BAR_BOTTOM: float = 113.0
const BAR_HEIGHT: float = 70.0

var match_timer: float = MATCH_DURATION
var owner_cost: int = INITIAL_COST
var match_over: bool = false
var game_started: bool = false
var game_over: bool = false
var battle_paused: bool = false  # updated by CardManager every frame
var _cost_accum: float = 0.0

## Online mode flags — set in _ready() from SceneManager.battle_mode
var is_online_mode: bool = false
var _game_over_sent: bool = false   # prevents double-send to server
var _opponent_display_name: String = ""

func _ready() -> void:
	$GameOverOverlay/RestartButton.pressed.connect(restart_game)
	_update_timer_label()
	_update_cost_bar()
	# Detect online mode (SceneManager stores the requested battle mode)
	is_online_mode = (SceneManager.battle_mode == "online")
	UIShell.hide_shell()
	SceneManager.battle_mode = "ai"  # reset for next battle
	_init_profiles()
	if is_online_mode:
		_init_online_mode()

func _init_online_mode() -> void:
	# Disable AI — the opponent is a real player
	var ai := get_node_or_null("EnemyAI")
	if ai:
		ai.set_process(false)
		ai.set_physics_process(false)
	# Connect network signals
	NetworkManager.opponent_action_received.connect(_on_opponent_action)
	NetworkManager.game_over_received.connect(_on_network_game_over)
	NetworkManager.opponent_disconnected.connect(_on_opponent_disconnected)
	NetworkManager.opponent_profile_received.connect(_on_opponent_profile)
	# Send own profile; show "..." until opponent profile arrives
	NetworkManager.send_profile(SaveManager.get_player_name(), SaveManager.get_profile_icon())
	$EnemyArea/EnemyNameLabel.text = "..."
	# In case opponent profile already arrived before signal connected
	if NetworkManager.opponent_name != "":
		_on_opponent_profile(NetworkManager.opponent_name, NetworkManager.opponent_icon)

func _init_profiles() -> void:
	var pname := SaveManager.get_player_name()
	$ControlsBar/OwnerNameLabel.text = pname if pname != "" else "Player"
	_apply_icon($ControlsBar/OwnerIconRect, SaveManager.get_profile_icon())
	_shift_name_for_icon($ControlsBar/OwnerNameLabel, $ControlsBar/OwnerIconRect)
	if not is_online_mode:
		_opponent_display_name = "AI"
		var lbl := $EnemyArea/EnemyNameLabel
		lbl.offset_top = 92.0
		lbl.offset_bottom = 118.0
		lbl.text = "AI"
		$EnemyArea/EnemyIconRect.visible = false

func _apply_icon(rect: TextureRect, card_id: String) -> void:
	if card_id == "":
		rect.visible = false
		return
	var cdata: Dictionary = CardDatabase.CARDS.get(card_id, {})
	if cdata.get("has_image", false):
		var tex = GameCache.get_texture(cdata.get("image_path", ""))
		if tex:
			rect.texture = tex
			rect.size = Vector2(42.0, 42.0)
			rect.visible = true
			return
	rect.visible = false

func _shift_name_for_icon(name_lbl: Label, icon_rect: TextureRect) -> void:
	if icon_rect.visible:
		# Icon occupies x=246..288 — shift name text right so it doesn't overlap
		name_lbl.offset_left = 50.0
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	else:
		name_lbl.offset_left = 0.0
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _on_opponent_profile(opp_name: String, opp_icon: String) -> void:
	var display_name := opp_name if opp_name != "" else "Opponent"
	_opponent_display_name = display_name
	$EnemyArea/EnemyNameLabel.text = display_name
	_apply_icon($EnemyArea/EnemyIconRect, opp_icon)
	_shift_name_for_icon($EnemyArea/EnemyNameLabel, $EnemyArea/EnemyIconRect)

func start_game() -> void:
	game_started = true
	var _mode := "online" if is_online_mode else "ai"
	BattleLogger.begin_battle({
		"mode":          _mode,
		"player_name":   SaveManager.get_player_name(),
		"opponent_name": _opponent_display_name,
	})

func restart_game() -> void:
	UIShell.show_shell()
	SceneManager.go_to_lobby()

func end_game(won: bool) -> void:
	if game_over:
		return
	game_over = true
	match_over = true
	# Notify the opponent in online mode
	if is_online_mode and not _game_over_sent:
		_game_over_sent = true
		# Send the WINNER's role (not always my_role)
		var winner_role: String
		if won:
			winner_role = NetworkManager.my_role
		else:
			winner_role = "enemy" if NetworkManager.my_role == "owner" else "owner"
		NetworkManager.send_game_over(winner_role)
	_show_result(won)
	var _mode := "online" if is_online_mode else "ai"
	var _result := "win" if won else "loss"
	BattleLogger.end_battle(_result)
	SaveManager.record_battle(_result, _opponent_display_name, _mode)

func _show_result(won: bool) -> void:
	var overlay = $GameOverOverlay
	var label: Label = overlay.get_node("ResultLabel")
	if won:
		label.text = "ชนะ!"
		label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2, 1.0))
	else:
		label.text = "แพ้"
		label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2, 1.0))
	overlay.visible = true

func draw_game() -> void:
	if game_over:
		return
	game_over = true
	match_over = true
	if is_online_mode and not _game_over_sent:
		_game_over_sent = true
		NetworkManager.send_game_over("draw")
	var overlay = $GameOverOverlay
	var label: Label = overlay.get_node("ResultLabel")
	label.text = "เสมอ"
	label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
	overlay.visible = true
	var _mode := "online" if is_online_mode else "ai"
	BattleLogger.end_battle("draw")
	SaveManager.record_battle("draw", _opponent_display_name, _mode)

# ── Online mode handlers ──────────────────────────────────────────────────────

func _on_opponent_action(action: Dictionary) -> void:
	print("[GameManager] _on_opponent_action called: ", action)
	if game_over:
		return
	match action.get("type", ""):
		"deploy":
			$CardManager.deploy_opponent_card_online(
				action.get("card_id", ""),
				action.get("row", 0),
				action.get("col", 0)
			)

func _on_network_game_over(winner: String) -> void:
	if game_over:
		return
	# winner is the server role that won; check against our own role
	var i_won: bool = (winner == NetworkManager.my_role)
	var is_draw: bool = (winner == "draw")
	if is_draw:
		draw_game()
	else:
		end_game(i_won)

func _on_opponent_disconnected() -> void:
	if not game_over:
		end_game(true)   # opponent left = we win

func _process(delta: float) -> void:
	if not game_started or match_over:
		return

	# Match timer countdown
	match_timer -= delta
	if match_timer <= 0.0:
		match_timer = 0.0
		match_over = true
		_update_timer_label()
		return
	_update_timer_label()

	# Cost regeneration — frozen during any global pause
	if not battle_paused:
		var interval = COST_INTERVAL_FAST if match_timer <= FAST_TIME_THRESHOLD else COST_INTERVAL_NORMAL
		_cost_accum += delta
		while _cost_accum >= interval and owner_cost < MAX_COST:
			_cost_accum -= interval
			owner_cost += 1
		if owner_cost >= MAX_COST:
			_cost_accum = 0.0
		_update_cost_bar()
	# Show/hide x1.5 speed label
	$OwnerCostBar/SpeedLabel.visible = (match_timer <= FAST_TIME_THRESHOLD)

## Returns true and deducts cost if affordable, false otherwise.
func spend_cost(amount: int) -> bool:
	if owner_cost >= amount:
		owner_cost -= amount
		_update_cost_bar()
		return true
	return false

func _update_timer_label() -> void:
	var m: int = int(match_timer) / 60
	var s: int = int(match_timer) % 60
	$ControlsBar/TimerLabel.text = "%02d:%02d" % [m, s]

func _update_cost_bar() -> void:
	$OwnerCostBar/CostValue.text = str(owner_cost)
	var ratio: float = float(owner_cost) / float(MAX_COST)
	$OwnerCostBar/BarFill.offset_top = BAR_BOTTOM - ratio * BAR_HEIGHT
