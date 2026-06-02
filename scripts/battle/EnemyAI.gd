extends Node2D

signal enemy_deploy_requested(card, slot)

# Card.tscn is preloaded into GameCache during the Loading scene.
# Do NOT call load() here — use GameCache.CARD_SCENE instead.
const DEPLOY_INTERVAL_MIN = 2.5
const DEPLOY_INTERVAL_MAX = 5.5
const MAX_COST = 10
const COST_INTERVAL_NORMAL = 2.0
const COST_INTERVAL_FAST = 1.3333
const FAST_TIME_THRESHOLD = 15.0
const INITIAL_COST = 7

const BAR_BOTTOM: float = 113.0
const BAR_HEIGHT: float = 70.0

var _enemy_deck: Array = []
var _enemy_hand: Array = []
var enemy_cost: int = INITIAL_COST
var _cost_accum: float = 0.0
var _deploy_timer: float = 0.0
var _next_deploy_time: float = 3.0

func _ready() -> void:
	_enemy_deck = _generate_deck()
	_next_deploy_time = randf_range(2.0, 4.0)
	_update_enemy_cost_bar()
	for i in range(4):
		_draw_card()

# ── AI Deck Generation ────────────────────────────────────────────────────────
# Single entry point for building the AI deck before each battle.
# Extend here for difficulty levels, boss decks, campaign presets, etc.

func _generate_deck() -> Array:
	var all_ids: Array = CardDatabase.CARDS.keys()
	all_ids.shuffle()
	var deck: Array = all_ids.slice(0, min(8, all_ids.size()))
	_debug_print_deck(deck)
	return deck

func _debug_print_deck(deck: Array) -> void:
	print("── AI Deck Generated ──────────────────")
	for i in range(deck.size()):
		var card_name: String = CardDatabase.CARDS[deck[i]].get("name", deck[i])
		print("  %d. %s" % [i + 1, card_name])
	print("───────────────────────────────────────")

func _process(delta: float) -> void:
	var gm = get_parent()
	if not gm.game_started or gm.game_over:
		return

	# Cost regen (mirror of owner) — frozen during global pause
	if not gm.match_over:
		if not gm.battle_paused:
			var interval = COST_INTERVAL_FAST if gm.match_timer <= FAST_TIME_THRESHOLD else COST_INTERVAL_NORMAL
			_cost_accum += delta
			while _cost_accum >= interval and enemy_cost < MAX_COST:
				_cost_accum -= interval
				enemy_cost += 1
			if enemy_cost >= MAX_COST:
				_cost_accum = 0.0
			_update_enemy_cost_bar()

	# Deploy timer — also frozen during global pause
	if gm.match_over:
		return
	if gm.battle_paused:
		return
	_deploy_timer += delta
	if _deploy_timer >= _next_deploy_time:
		_deploy_timer = 0.0
		_next_deploy_time = randf_range(DEPLOY_INTERVAL_MIN, DEPLOY_INTERVAL_MAX)
		_try_deploy()

func _draw_card() -> void:
	if _enemy_deck.is_empty():
		return
	var idx = randi() % _enemy_deck.size()
	var card_id = _enemy_deck[idx]
	_enemy_deck.remove_at(idx)
	var card_scene: PackedScene = GameCache.CARD_SCENE
	if card_scene == null:
		push_error("EnemyAI: GameCache.CARD_SCENE is null — was the Loading scene skipped?")
		return
	var card: Variant = card_scene.instantiate()
	var cm: Variant = get_node("../CardManager")
	cm.add_child(card)
	card.name = "EnemyHandCard"
	card.setup(CardDatabase.CARDS[card_id])
	card.position = Vector2(-400.0, -400.0)
	card.get_node("Area2D/CollisionShape2D").disabled = true
	_enemy_hand.append(card)

func _try_deploy() -> void:
	if _enemy_hand.is_empty():
		return
	var card_manager: Variant = get_node("../CardManager")
	# Collect available enemy slots
	var slot_nodes_dict = card_manager.get("slot_nodes")
	if slot_nodes_dict == null:
		return
	var available_slots: Array = []
	for key in slot_nodes_dict:
		var slot = slot_nodes_dict[key]
		if slot.get("can_enemy_deploy") and not slot.get("card_in_slot"):
			available_slots.append(slot)
	if available_slots.is_empty():
		return
	# Pick a random affordable card
	var affordable: Array = []
	for card in _enemy_hand:
		if is_instance_valid(card) and card.card_data.get("cost", 0) <= enemy_cost:
			affordable.append(card)
	if affordable.is_empty():
		return
	var card = affordable[randi() % affordable.size()]
	var slot = available_slots[randi() % available_slots.size()]
	enemy_cost -= card.card_data.get("cost", 0)
	_update_enemy_cost_bar()
	_enemy_hand.erase(card)
	emit_signal("enemy_deploy_requested", card, slot)

# Called by CardManager when an enemy field card is removed (died/advanced off grid)
func return_card(card_id: String) -> void:
	_enemy_deck.append(card_id)
	_draw_card()

func _update_enemy_cost_bar() -> void:
	var bar = get_node_or_null("../EnemyArea/EnemyCostBar")
	if bar == null:
		return
	bar.get_node("CostValue").text = str(enemy_cost)
	var ratio: float = float(enemy_cost) / float(MAX_COST)
	bar.get_node("BarFill").offset_top = BAR_BOTTOM - ratio * BAR_HEIGHT
