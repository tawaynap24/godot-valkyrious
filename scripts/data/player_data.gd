extends Resource
class_name PlayerData

# ─────────────────────────────────────────────────────────────────────────────
# PlayerData — saved to user://player_data.tres
# deck_1/2/3 store card IDs (char_name strings), up to 8 each.
# active_deck is 1, 2, or 3.
# ─────────────────────────────────────────────────────────────────────────────

@export var active_deck: int = 1
@export var deck_1: Array[String] = []
@export var deck_2: Array[String] = []
@export var deck_3: Array[String] = []
# All card_ids the player has unlocked. Populated on first run with every available card.
@export var owned_cards: Array[String] = []
@export var player_name: String = ""
@export var profile_icon: String = ""  # card_id for profile picture

# ── Battle Record ─────────────────────────────────────────────────────────────
@export var wins: int = 0
@export var losses: int = 0
@export var draws: int = 0
@export var battle_history: Array = []  # Array of {result, opponent, mode, time}

# ── Upgrade System ────────────────────────────────────────────────────────────
@export var coins: int = 1000000
@export var character_levels: Dictionary = {}  # card_id → level (int 1–5)
@export var individual_card_levels: Dictionary = {}  # instance_idx (String) -> level (int)
@export var card_upgrades: Dictionary = {}            # instance_idx (String) -> upgrades path (Dictionary)
@export var data_version: int = 0

func get_deck(index: int) -> Array[String]:
	match index:
		1: return deck_1
		2: return deck_2
		3: return deck_3
	return deck_1

func set_deck(index: int, cards: Array[String]) -> void:
	match index:
		1: deck_1 = cards
		2: deck_2 = cards
		3: deck_3 = cards

func get_active_cards() -> Array[String]:
	return get_deck(active_deck)
