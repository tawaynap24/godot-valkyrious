extends Node2D

# Card.tscn is preloaded into GameCache during the Loading scene.
# Do NOT call load() here — use GameCache.CARD_SCENE instead.
const CARD_DRAW_SPEED = 1

var player_deck: Array = []

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	player_deck = SaveManager.get_active_deck()
	for i in range(4):
		draw_card()

func draw_card():
	if player_deck.is_empty():
		return
	var card_id = player_deck[0]
	player_deck.remove_at(0)
	print("draw card: " + card_id)
	var card_scene: PackedScene = GameCache.CARD_SCENE
	if card_scene == null:
		push_error("Deck: GameCache.CARD_SCENE is null — was the Loading scene skipped?")
		return
	var new_card: Variant = card_scene.instantiate()
	var cm: Variant = get_node("../CardManager")
	cm.add_child(new_card)
	new_card.name = "Card"
	var cdata: Dictionary = CardDatabase.get_effective_dict(card_id)
	new_card.setup(cdata)
	var player_hand: Variant = $"../PlayerHand"
	player_hand.add_card_to_hand(new_card, CARD_DRAW_SPEED)
	BattleLogger.log_card_draw("owner", card_id, cdata.get("name", ""))

func return_card(card_id: String) -> void:
	player_deck.append(card_id)
	$RichTextLabel.text = str(player_deck.size())
