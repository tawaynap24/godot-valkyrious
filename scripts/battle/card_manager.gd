extends Node2D

const COLLISION_MASK_CARD = 1
const COLLISION_MASK_CARD_SLOT = 2
const DEFAULT_CARD_MOVE_SPEED = 0.1
const CAPTURE_ROW = 1  # R2 (0-indexed)

var screen_size
var card_being_dragged
var is_hovering_on_card
var skill_resolver  # SkillResolver child node
var player_hand_reference

var field_cards: Array = []
var global_pause_remaining: float = 0.0  # current active pause countdown
var _pause_queue: Array = []             # queued additional pauses (each a float)
var grid: Dictionary = {}
var slot_nodes: Dictionary = {}

## Returns true while any global pause is active (current or queued).
func is_paused() -> bool:
	return global_pause_remaining > 0.0 or not _pause_queue.is_empty()

## Queue a pause segment. If nothing is running it starts immediately.
func _add_pause(duration: float) -> void:
	if duration <= 0.0:
		return
	if global_pause_remaining <= 0.0:
		global_pause_remaining = duration
	else:
		_pause_queue.append(duration)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	child_entered_tree.connect(_on_card_child_entered)
	skill_resolver = preload("res://scripts/battle/skill_resolver.gd").new()
	add_child(skill_resolver)
	screen_size = get_viewport_rect().size
	player_hand_reference = $"../PlayerHand"
	$"../InputManager".connect("left_mouse_button_released", on_left_click_released)
	$"../InputManager".connect("card_pressed", start_drag)
	$"../EnemyAI".connect("enemy_deploy_requested", deploy_enemy_card)
	_load_slot_nodes()

func _on_card_child_entered(node: Node) -> void:
	if node.has_signal("hovered") and node.has_signal("hovered_off"):
		if not node.is_connected("hovered", on_hovered_over_card):
			connect_card_signals(node)

func _load_slot_nodes() -> void:
	var battle_grid = get_node("../BattleGrid")
	var row_names = ["R1", "R2", "R3"]
	var col_names = ["C1", "C2", "C3"]
	for r in range(3):
		for c in range(3):
			slot_nodes[_grid_key(r, c)] = battle_grid.get_node("Slot_" + row_names[r] + col_names[c])

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if get_parent().game_over:
		return
	if card_being_dragged:
		var drag_pos: Vector2 = get_viewport().get_mouse_position()
		card_being_dragged.position = Vector2(
			clamp(drag_pos.x, 0, screen_size.x),
			clamp(drag_pos.y, 0, screen_size.y))

	# Tick down current global pause; pop next from queue when done
	if global_pause_remaining > 0.0:
		global_pause_remaining -= delta
		if global_pause_remaining <= 0.0:
			global_pause_remaining = 0.0
			if not _pause_queue.is_empty():
				global_pause_remaining = _pause_queue.pop_front()
		# While paused: card countdowns and cost regen are frozen — skip the rest
		get_parent().battle_paused = true
		return
	get_parent().battle_paused = false

	# When time is up, any side with no cards on the field loses
	if get_parent().match_over:
		var has_owner := false
		var has_enemy := false
		for fc in field_cards:
			if is_instance_valid(fc):
				if fc.is_owner_card: has_owner = true
				else: has_enemy = true
		if not has_owner and not has_enemy:
			get_parent().draw_game()
			return
		if not has_owner:
			get_parent().end_game(false)
			return
		if not has_enemy:
			get_parent().end_game(true)
			return
		# Both sides still have cards — continue battle below (no new deploys blocked elsewhere)

	for card in field_cards.duplicate():
		# If any action this frame set a global pause — stop processing cards immediately
		if global_pause_remaining > 0.0:
			break
		if not is_instance_valid(card):
			field_cards.erase(card)
			continue
		# Tick down stun; stunned cards do not advance their countdown
		if card.stun_remaining > 0.0:
			card.update_stun_timer(delta)
			continue
		card.field_countdown -= delta
		card.update_countdown_display(card.field_countdown)
		_update_arrow_live(card)
		# Capture logic: card stays in R2 for capture_duration seconds
		if card.row_index == CAPTURE_ROW:
			card.capture_timer += delta
			if card.capture_timer >= card.capture_duration:
				_capture_slot(card)
				card.capture_timer = 0.0
		else:
			card.capture_timer = 0.0
		if card.field_countdown <= 0.0:
			card.get_node("CountdownCircle").visible = false
			_attempt_advance(card)

func start_drag(card):
	var gm = get_parent()
	if not gm.game_started or gm.game_over:
		return
	card_being_dragged = card
	card.scale = Vector2(1, 1)

func finish_drag():
	var card_slot_found = raycast_check_for_card_slot()
	var gm = get_parent()
	if card_slot_found and not card_slot_found.get("card_in_slot") and card_slot_found.get("can_owner_deploy") \
			and not gm.match_over:
		var deploy_cost = card_being_dragged.card_data.get("cost", 0)
		if not get_parent().spend_cost(deploy_cost):
			player_hand_reference.add_card_to_hand(card_being_dragged, DEFAULT_CARD_MOVE_SPEED)
			card_being_dragged = null
			return
		# Snap card to slot position immediately
		card_being_dragged.global_position = card_slot_found.global_position
		card_being_dragged.scale = Vector2(1.0, 1.0)
		card_being_dragged.z_index = 1
		card_being_dragged.get_node("Area2D/CollisionShape2D").disabled = true
		card_slot_found.set("card_in_slot", true)
		player_hand_reference.remove_card_from_hand(card_being_dragged)
		_finalize_deploy(card_being_dragged, card_slot_found)
		card_being_dragged = null
	else:
		player_hand_reference.add_card_to_hand(card_being_dragged, DEFAULT_CARD_MOVE_SPEED)
		card_being_dragged = null

func _finalize_deploy(card, slot) -> void:
	var deploy_card_id: String = card.card_data.get("id", "")
	print("[CardManager] _finalize_deploy: name=%s id=%s card_data=%s" % [card.name, deploy_card_id, str(card.card_data)])
	_register_on_field(card, slot, true)
	skill_resolver.trigger_skills(card, "place")
	card.set_field_border(true)
	var deck = get_node("../Deck")
	deck.return_card(deploy_card_id)
	deck.draw_card()
	# Log deployment
	var gp_deploy := _slot_to_grid(slot)
	BattleLogger.log_deploy(
		"owner",
		deploy_card_id,
		card.card_data.get("name", ""),
		gp_deploy.x,
		gp_deploy.y,
		card.card_data.get("cost", 0)
	)
	# Online: broadcast own deploy so the opponent can mirror it
	var gm = get_parent()
	if gm.is_online_mode:
		NetworkManager.send_action({
			"type":    "deploy",
			"card_id": deploy_card_id,
			"row":     gp_deploy.x,
			"col":     gp_deploy.y
		})

func deploy_enemy_card(card, slot) -> void:
	card.global_position = slot.global_position
	card.scale = Vector2(1.0, 1.0)
	card.z_index = 1
	slot.set("card_in_slot", true)
	_register_on_field(card, slot, false)
	skill_resolver.trigger_skills(card, "place")
	card.set_field_border(false)
	var gp_enemy := _slot_to_grid(slot)
	BattleLogger.log_deploy(
		"enemy",
		card.card_data.get("id", ""),
		card.card_data.get("name", ""),
		gp_enemy.x,
		gp_enemy.y,
		card.card_data.get("cost", 0)
	)

func _register_on_field(card, slot_node, is_owner: bool = true) -> void:
	var gp = _slot_to_grid(slot_node)
	card.row_index = gp.x
	card.col_index = gp.y
	card.is_owner_card = is_owner
	card.current_hp = card.card_data.get("hp", 1)
	card.current_atk = card.card_data.get("atk", 1)
	card.field_countdown = card.move_countdown
	card.capture_timer = 0.0
	card.is_on_field = true
	card.set_barrier(card.card_data.get("has_barrier", false))
	card.get_node("CountdownCircle").set_max(card.move_countdown)
	grid[_grid_key(gp.x, gp.y)] = card
	field_cards.append(card)
	card.set_attack_arrow("U" if is_owner else "D")
	_refresh_all_arrows()
	skill_resolver.trigger_skills(card, "aura")

func _attempt_advance(card) -> void:
	# Guard: card may have been removed from field this frame (e.g. both combatants died)
	if not field_cards.has(card):
		return
	var next_row = card.row_index - 1 if card.is_owner_card else card.row_index + 1
	var row = card.row_index
	var col = card.col_index

	var is_enemy = func(t): \
		return t != null and is_instance_valid(t) and t.is_owner_card != card.is_owner_card

	# Adjacency check: only cells sharing exactly one edge
	var is_adjacent = func(t):
		if t == null or not is_instance_valid(t): return false
		var dr = abs(t.row_index - row)
		var dc = abs(t.col_index - col)
		return (dr == 0 and dc == 1) or (dr == 1 and dc == 0)

	# --- Target lock: keep fighting the same enemy until it DIES ---
	# (even if it moves out of range, keep the lock and wait)
	if card.locked_target != null and is_instance_valid(card.locked_target) \
			and is_enemy.call(card.locked_target):
		var t = card.locked_target
		if is_adjacent.call(t):
			# Target still adjacent — attack it
			_set_arrow_toward(card, t)
			_do_combat(card, t)
			global_pause_remaining = card.delay_attack
		else:
			# Target alive but moved away — hold position and wait
			_set_arrow_toward(card, t)
			card.field_countdown = card.move_countdown
		return

	# --- No valid lock — scan for new target ---
	# Priority: front (toward enemy base) > side (same row) > back
	var back_row = card.row_index + 1 if card.is_owner_card else card.row_index - 1
	var side_left  = grid.get(_grid_key(row, col - 1), null) if col > 0 else null
	var side_right = grid.get(_grid_key(row, col + 1), null) if col < 2 else null
	var front_in_bounds = (next_row >= 0 and next_row <= 2)
	var back_in_bounds  = (back_row >= 0 and back_row <= 2)
	var front = grid.get(_grid_key(next_row, col), null) if front_in_bounds else null
	var back  = grid.get(_grid_key(back_row,  col), null) if back_in_bounds  else null

	var new_target = null
	if is_enemy.call(front):
		new_target = front
	elif is_enemy.call(side_left):
		new_target = side_left
	elif is_enemy.call(side_right):
		new_target = side_right
	elif is_enemy.call(back):
		new_target = back

	if new_target != null:
		card.locked_target = new_target
		_set_arrow_toward(card, new_target)
		_do_combat(card, new_target)
		# _add_pause is handled inside _do_combat
		return

	# --- No enemies adjacent — try to move or end game ---
	card.locked_target = null
	card.set_attack_arrow("U" if card.is_owner_card else "D")

	if not front_in_bounds:
		_remove_from_field(card)
		get_parent().end_game(card.is_owner_card)
		_add_pause(card.delay_move)
		return

	if front == null:
		_move_card(card, next_row, col)
		_add_pause(card.delay_move)
	else:
		# Friendly blocks the path — wait
		card.field_countdown = card.move_countdown

func _do_combat(card_a, card_b) -> void:
	# ── Phase 1: pre-attack skill pauses ────────────────────────────────────
	var skill_pause_a: float = card_a.card_data.get("time_delay", {}).get("skill_pause", 0.0)
	var skill_pause_b: float = card_b.card_data.get("time_delay", {}).get("skill_pause", 0.0)
	if skill_pause_a > 0.0:
		_add_pause(skill_pause_a)
	skill_resolver.trigger_skills(card_a, "attack")
	if skill_pause_b > 0.0:
		_add_pause(skill_pause_b)
	skill_resolver.trigger_skills(card_b, "attack")

	# ── Phase 2: animation sequence ─────────────────────────────────────────
	# Step 1 — card_a lunges to card_b
	# Step 2 — show damage numbers on both cards (no number if barrier)
	# Step 3 — card_a returns; damage labels travel with it (parented to card_a)
	# Step 4 — animation end: apply HP change, handle barrier/death
	var attack_duration: float = card_a.delay_attack
	_add_pause(attack_duration)

	var origin_pos: Vector2 = card_a.global_position
	var target_pos: Vector2 = card_b.global_position
	var half: float = attack_duration * 0.5

	# Pre-calculate what the damage numbers will show (before any state change)
	var dmg_to_a: int = card_b.current_atk  # damage card_a would take (0 if card_b is stunned)
	var dmg_to_b: int = card_a.current_atk  # damage card_b would take
	# Snapshot stun state at time of attack — stunned defender cannot retaliate
	var b_is_stunned: bool = card_b.stun_remaining > 0.0
	if b_is_stunned:
		dmg_to_a = 0

	# Last-stand rule: when time is up and only these 2 cards remain,
	# if the attacker can kill the defender this hit → attacker takes no damage and wins.
	var _last_stand_win: bool = (
		get_parent().match_over
		and field_cards.size() == 2
		and not card_b.barrier
		and card_a.current_atk >= card_b.current_hp
	)
	if _last_stand_win:
		dmg_to_a = 0

	var tween := create_tween()
	# Step 1: lunge forward
	tween.tween_property(card_a, "global_position", target_pos, half)
	# Step 2: at contact — spawn damage number labels
	tween.tween_callback(func() -> void:
		# Damage label on card_b (centred, floats in place on card_b)
		if is_instance_valid(card_b) and not card_b.barrier:
			var lbl_b := Label.new()
			lbl_b.text = "-" + str(dmg_to_b)
			lbl_b.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25, 1.0))
			lbl_b.add_theme_font_size_override("font_size", 18)
			lbl_b.z_index = 30
			lbl_b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl_b.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl_b.size = Vector2(60, 30)
			lbl_b.position = Vector2(-30, -15)
			card_b.add_child(lbl_b)
			# Fade out and float up over half duration, then free
			var tw_b := create_tween()
			tw_b.tween_property(lbl_b, "position:y", lbl_b.position.y - 20, half)
			tw_b.parallel().tween_property(lbl_b, "modulate:a", 0.0, half)
			tw_b.tween_callback(lbl_b.queue_free)
		# Damage label on card_a (parented to card_a so it travels back)
		if is_instance_valid(card_a) and not card_a.barrier:
			var lbl_a := Label.new()
			lbl_a.text = "-" + str(dmg_to_a)
			lbl_a.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25, 1.0))
			lbl_a.add_theme_font_size_override("font_size", 18)
			lbl_a.z_index = 30
			lbl_a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl_a.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl_a.size = Vector2(60, 30)
			lbl_a.position = Vector2(-30, -15)
			card_a.add_child(lbl_a)
			var tw_a := create_tween()
			tw_a.tween_property(lbl_a, "position:y", lbl_a.position.y - 20, half)
			tw_a.parallel().tween_property(lbl_a, "modulate:a", 0.0, half)
			tw_a.tween_callback(lbl_a.queue_free)
	)
	# Step 3: card_a returns to origin
	tween.tween_property(card_a, "global_position", origin_pos, half)
	# Step 4: animation done — apply damage, handle barrier/death
	tween.tween_callback(func() -> void:
		if not is_instance_valid(card_a) or not is_instance_valid(card_b):
			return
		var hp_a_before = card_a.current_hp
		var hp_b_before = card_b.current_hp
		# card_a takes damage only if card_b is not stunned
		if dmg_to_a > 0:
			if card_a.barrier:
				card_a.set_barrier(false)
			else:
				card_a.current_hp -= dmg_to_a
		if card_b.barrier:
			card_b.set_barrier(false)
		else:
			card_b.current_hp -= card_a.current_atk
		if is_instance_valid(card_a):
			card_a.get_node("HPLabel").text = str(max(0, card_a.current_hp))
		if is_instance_valid(card_b):
			card_b.get_node("HPLabel").text = str(max(0, card_b.current_hp))
		BattleLogger.log_attack(
			{
				"player":    "owner" if card_a.is_owner_card else "enemy",
				"card_id":   card_a.card_data.get("id", ""),
				"card_name": card_a.card_data.get("name", ""),
				"atk":       card_a.current_atk,
				"hp_before": hp_a_before,
				"hp_after":  card_a.current_hp,
			},
			{
				"player":    "owner" if card_b.is_owner_card else "enemy",
				"card_id":   card_b.card_data.get("id", ""),
				"card_name": card_b.card_data.get("name", ""),
				"atk":       card_b.current_atk,
				"hp_before": hp_b_before,
				"hp_after":  card_b.current_hp,
			}
		)
		var a_dead: bool = card_a.current_hp <= 0
		var b_dead: bool = card_b.current_hp <= 0
		if a_dead:
			_remove_from_field(card_a)
		else:
			card_a.field_countdown = card_a.move_countdown
			card_a.update_countdown_display(card_a.field_countdown)
		if b_dead:
			_remove_from_field(card_b)
	)

func _move_card(card, new_row: int, col: int) -> void:
	var from_row = card.row_index
	var from_col = card.col_index
	var old_key = _grid_key(card.row_index, card.col_index)
	slot_nodes[old_key].set("card_in_slot", false)
	grid.erase(old_key)
	card.row_index = new_row
	var new_key = _grid_key(new_row, col)
	slot_nodes[new_key].set("card_in_slot", true)
	grid[new_key] = card
	card.global_position = slot_nodes[new_key].global_position
	card.field_countdown = card.move_countdown
	card.capture_timer = 0.0
	card.locked_target = null
	card.update_countdown_display(card.field_countdown)
	_refresh_all_arrows()
	skill_resolver.trigger_skills(card, "move")
	BattleLogger.log_move(
		"owner" if card.is_owner_card else "enemy",
		card.card_data.get("id", ""),
		card.card_data.get("name", ""),
		from_row, from_col, new_row, col
	)

func _remove_from_field(card) -> void:
	var key = _grid_key(card.row_index, card.col_index)
	if grid.get(key) == card:
		grid.erase(key)
	var slot = slot_nodes.get(key)
	if slot:
		slot.set("card_in_slot", false)
	field_cards.erase(card)
	# Log death if card HP hit zero
	if card.current_hp <= 0:
		skill_resolver.trigger_skills(card, "remove")
		BattleLogger.log_death(
			"owner" if card.is_owner_card else "enemy",
			card.card_data.get("id", ""),
			card.card_data.get("name", ""),
			card.row_index, card.col_index
		)
	# In AI mode, returning an enemy card to the AI deck allows it to re-deploy.
	# In online mode there is no AI, so we skip this entirely.
	var gm = get_parent()
	if not card.is_owner_card and not gm.is_online_mode:
		var ai = get_node_or_null("../EnemyAI")
		if ai:
			ai.return_card(card.card_data.get("id", ""))
	# Any card that had this as its locked target: clear the lock.
	# Do NOT reset their countdown — arrow will update via _update_arrow_live,
	# and they will find a new target naturally when their countdown next expires.
	for fc in field_cards:
		if is_instance_valid(fc) and fc.locked_target == card:
			fc.locked_target = null
	card.set_attack_arrow("")
	card.queue_free()

func _refresh_all_arrows() -> void:
	for fc in field_cards:
		if is_instance_valid(fc):
			_update_arrow_live(fc)

func _update_arrow_live(card) -> void:
	var row = card.row_index
	var col = card.col_index
	var is_enemy = func(t): \
		return t != null and is_instance_valid(t) and t.is_owner_card != card.is_owner_card
	# Follow locked target if still alive — never change until it dies
	if card.locked_target != null and is_instance_valid(card.locked_target) \
			and is_enemy.call(card.locked_target):
		_set_arrow_toward(card, card.locked_target)
		return
	# No lock yet — scan adjacent cells and lock onto the FIRST enemy found
	# (same priority as _attempt_advance: front > side > back)
	# Setting locked_target here makes the choice sticky immediately,
	# so subsequent _refresh_all_arrows calls won't override it.
	var next_row = card.row_index - 1 if card.is_owner_card else card.row_index + 1
	var back_row = card.row_index + 1 if card.is_owner_card else card.row_index - 1
	var side_left  = grid.get(_grid_key(row, col - 1), null) if col > 0 else null
	var side_right = grid.get(_grid_key(row, col + 1), null) if col < 2 else null
	var front_in_bounds = (next_row >= 0 and next_row <= 2)
	var back_in_bounds  = (back_row >= 0 and back_row <= 2)
	var front = grid.get(_grid_key(next_row, col), null) if front_in_bounds else null
	var back  = grid.get(_grid_key(back_row,  col), null) if back_in_bounds  else null
	var found = null
	if is_enemy.call(front):
		found = front
	elif is_enemy.call(side_left):
		found = side_left
	elif is_enemy.call(side_right):
		found = side_right
	elif is_enemy.call(back):
		found = back
	if found != null:
		card.locked_target = found
		_set_arrow_toward(card, found)
	else:
		card.set_attack_arrow("U" if card.is_owner_card else "D")

func _grid_key(r: int, c: int) -> String:
	return str(r) + "," + str(c)

func _set_arrow_toward(card, target) -> void:
	var dc = target.col_index - card.col_index
	var dr = target.row_index - card.row_index
	if dc == -1:
		card.set_attack_arrow("L")
	elif dc == 1:
		card.set_attack_arrow("R")
	elif dr < 0:
		card.set_attack_arrow("U")
	else:
		card.set_attack_arrow("D")

func _capture_slot(card) -> void:
	var key = _grid_key(card.row_index, card.col_index)
	var slot = slot_nodes.get(key)
	if slot == null:
		return
	if card.is_owner_card:
		slot.set("can_owner_deploy", true)
		slot.get_node("OwnerIndicator").visible = true
	else:
		slot.set("can_enemy_deploy", true)
		slot.get_node("EnemyIndicator").visible = true
	print("CAPTURE: '" + card.card_data.get("name", "?") + "' captured slot " + key)
	BattleLogger.log_capture(
		"owner" if card.is_owner_card else "enemy",
		card.card_data.get("id", ""),
		card.card_data.get("name", ""),
		card.row_index, card.col_index
	)

func _slot_to_grid(slot_node: Node2D) -> Vector2i:
	# "Slot_R1C1" → row digit at index 6, col digit at index 8
	var sn: String = str(slot_node.name)
	return Vector2i(int(sn[6]) - 1, int(sn[8]) - 1)

# ── Skill Trigger System — moved to scripts/battle/SkillResolver.gd ──────────
# Use skill_resolver.trigger_skills(card, trigger_type) from this file.

func connect_card_signals(card):
	card.connect("hovered", on_hovered_over_card)
	card.connect("hovered_off", on_hovered_off_card)

func on_left_click_released():
	if card_being_dragged:
		finish_drag()

func on_hovered_over_card(card):
	if !is_hovering_on_card:
		is_hovering_on_card = true
		highlight_card(card, true)

func on_hovered_off_card(card):
	if(!card_being_dragged):
		highlight_card(card, false)
		var new_card_hovered = raycast_check_for_card()
		if new_card_hovered:
			highlight_card(new_card_hovered, true)
		else:
			is_hovering_on_card = false

func highlight_card(card, hovered):
	var base_scale = 1.0 if card.is_on_field else 1.2
	if hovered:
		card.scale = Vector2(base_scale + 0.05, base_scale + 0.05)
		card.z_index = 2
	else:
		card.scale = Vector2(base_scale, base_scale)
		card.z_index = 1

func raycast_check_for_card():
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = get_viewport().get_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_CARD
	var result = space_state.intersect_point(parameters)
	if result.size() > 0:
		return get_card_with_highest_z_index(result)
	return null

func raycast_check_for_card_slot():
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = get_viewport().get_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_CARD_SLOT
	var result = space_state.intersect_point(parameters)
	if result.size() > 0:
		return result[0].collider.get_parent()
	return null

func get_card_with_highest_z_index(cards):
	var highest_z_card = cards[0].collider.get_parent()
	var highest_z_index = highest_z_card.z_index
	for i in range(1, cards.size()):
		var current_card = cards[i].collider.get_parent()
		if current_card.z_index > highest_z_index:
			highest_z_card = current_card
			highest_z_index = current_card.z_index
	return highest_z_card

# ── Online opponent deploy ─────────────────────────────────────────────────────
# Called by GameManager when an "opponent_action / deploy" network message arrives.
# row / col are from the OPPONENT's perspective, so we mirror the row.

func deploy_opponent_card_online(card_id: String, row: int, col: int) -> void:
	var mirrored_row := 2 - row
	var slot_key := _grid_key(mirrored_row, col)
	print("[CardManager] deploy_opponent_card_online: card_id=%s row=%d col=%d → mirrored_row=%d slot_key=%s" % [card_id, row, col, mirrored_row, slot_key])
	var slot = slot_nodes.get(slot_key)
	if slot == null:
		print("[CardManager] ERROR: slot '%s' not found in slot_nodes (keys: %s)" % [slot_key, str(slot_nodes.keys())])
		return
	if slot.get("card_in_slot"):
		print("[CardManager] Slot '%s' already occupied — skipping" % slot_key)
		return
	var card_data: Dictionary = CardDatabase.CARDS.get(card_id, {})
	if card_data.is_empty():
		push_warning("deploy_opponent_card_online: unknown card_id '%s'" % card_id)
		print("[CardManager] ERROR: unknown card_id '%s'. Known ids: %s" % [card_id, str(CardDatabase.CARDS.keys())])
		return
	var card_scene: PackedScene = GameCache.CARD_SCENE
	if card_scene == null:
		push_error("deploy_opponent_card_online: GameCache.CARD_SCENE is null")
		return
	var card: Variant = card_scene.instantiate()
	add_child(card)
	card.name = "OnlineEnemyCard"
	card.setup(card_data)
	connect_card_signals(card)
	card.position = Vector2(-400.0, -400.0)
	card.get_node("Area2D/CollisionShape2D").disabled = true
	deploy_enemy_card(card, slot)
	print("[CardManager] Opponent card placed at slot '%s' pos=%s" % [slot_key, str(slot.global_position)])
