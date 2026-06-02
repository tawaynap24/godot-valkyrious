extends Node

# ─────────────────────────────────────────────────────────────────────────────
# SaveManager — AutoLoad singleton
# Loads player_data on startup, saves on every deck change.
# ─────────────────────────────────────────────────────────────────────────────

const SAVE_PATH_DEFAULT = "user://player_data.tres"
const SAVE_PATH_P2      = "user://player_data_2.tres"
const DEFAULT_DECK: Array[String] = ["ange", "ariana", "benita", "jenny", "nicole", "ran", "sia", "victoria"]

signal deck_changed(deck_index: int)
signal active_deck_changed(deck_index: int)
signal profile_changed
signal record_changed

const MAX_HISTORY: int = 100

var data: PlayerData = null
var SAVE_PATH: String = SAVE_PATH_DEFAULT

func _ready() -> void:
	if "--p2" in OS.get_cmdline_args():
		SAVE_PATH = SAVE_PATH_P2
	_load()

# ── Public API ────────────────────────────────────────────────────────────────

func get_active_deck() -> Array[String]:
	return data.get_active_cards().duplicate()

func get_deck(index: int) -> Array[String]:
	return data.get_deck(index).duplicate()

func set_deck(index: int, cards: Array[String]) -> void:
	data.set_deck(index, cards)
	_save()
	emit_signal("deck_changed", index)

func get_active_index() -> int:
	return data.active_deck

func set_active_deck(index: int) -> void:
	if index < 1 or index > 3:
		return
	data.active_deck = index
	_save()
	emit_signal("active_deck_changed", index)

# ── Profile ───────────────────────────────────────────────────────────────────

func get_player_name() -> String:
	return data.player_name

func set_player_name(new_name: String) -> void:
	data.player_name = new_name
	_save()
	emit_signal("profile_changed")

func get_profile_icon() -> String:
	return data.profile_icon

func set_profile_icon(card_id: String) -> void:
	data.profile_icon = card_id
	_save()
	emit_signal("profile_changed")

# ── Battle Record ─────────────────────────────────────────────────────────────

func get_wins() -> int:
	return data.wins

func get_losses() -> int:
	return data.losses

func get_draws() -> int:
	return data.draws

func get_battle_history() -> Array:
	return data.battle_history.duplicate()

func record_battle(result: String, opponent: String, mode: String) -> void:
	match result:
		"win":  data.wins  += 1
		"loss": data.losses += 1
		"draw": data.draws  += 1
	var entry := {
		"result":   result,
		"opponent": opponent,
		"mode":     mode,
		"time":     int(Time.get_unix_time_from_system())
	}
	data.battle_history.push_front(entry)
	if data.battle_history.size() > MAX_HISTORY:
		data.battle_history.resize(MAX_HISTORY)
	_save()
	emit_signal("record_changed")

# ── Collection Ownership ──────────────────────────────────────────────────────

func has_playable_deck() -> bool:
	return get_active_deck().size() >= 8

func get_owned_cards() -> Array[String]:
	return data.owned_cards.duplicate()

func has_owned_card(id: String) -> bool:
	return data.owned_cards.has(id)

func own_card(id: String) -> void:
	data.owned_cards.append(id)
	_save()

func own_all_cards() -> void:
	data.owned_cards.assign(CardDatabase.CARDS.keys())
	_save()

# ── Internal ─────────────────────────────────────────────────────────────────

func _load() -> void:
	if ResourceLoader.exists(SAVE_PATH):
		var loaded = ResourceLoader.load(SAVE_PATH)
		if loaded is PlayerData:
			data = loaded
			_migrate_deck_keys()
			_migrate_to_v2()
			return
	# No save file yet — create fresh with starter deck only (unlock more via gacha)
	data = PlayerData.new()
	data.deck_1.assign(DEFAULT_DECK)
	data.active_deck = 1
	data.owned_cards.assign(DEFAULT_DECK)
	data.coins = 1000000
	data.data_version = 2
	_save()

func _save() -> void:
	var err = ResourceSaver.save(data, SAVE_PATH)
	if err != OK:
		push_error("SaveManager: failed to save — error code " + str(err))

# Migrate old saves to v2 — reset owned_cards to DEFAULT_DECK, clear extra decks, set coins.
func _migrate_to_v2() -> void:
	if data.data_version >= 2:
		return
	data.owned_cards.assign(DEFAULT_DECK)
	data.deck_1.assign(DEFAULT_DECK)
	data.deck_2.clear()
	data.deck_3.clear()
	data.active_deck = 1
	data.coins = 1000000
	data.data_version = 2
	_save()

# Convert old capitalized keys ("Ariana") to new lowercase keys ("ariana").
func _migrate_deck_keys() -> void:
	var changed := false
	for i in range(1, 4):
		var deck: Array[String] = data.get_deck(i)
		var j := 0
		while j < deck.size():
			var key: String = deck[j]
			if key != key.to_lower():
				var resolved: String = CardDatabase.resolve_key(key)
				if resolved != "":
					deck[j] = resolved
					changed = true
					j += 1
				else:
					# Unknown key — drop it to avoid a broken deck entry
					deck.remove_at(j)
					changed = true
					# j stays: the element that was at j+1 is now at j
			else:
				j += 1
	if changed:
		_save()

# ── Coins ─────────────────────────────────────────────────────────────────────

func get_coins() -> int:
	return data.coins

func add_coins(amount: int) -> void:
	data.coins += amount
	_save()

# ── Character Upgrade Levels ──────────────────────────────────────────────────

const UPGRADE_COST: int = 10
const UPGRADE_MAX_LEVEL: int = 5

func get_character_level(card_id: String) -> int:
	return int(data.character_levels.get(card_id, 1))

## Upgrades the character by 1 level. Returns true on success.
func upgrade_character(card_id: String) -> bool:
	var cur: int = get_character_level(card_id)
	if cur >= UPGRADE_MAX_LEVEL:
		return false
	if data.coins < UPGRADE_COST:
		return false
	data.coins -= UPGRADE_COST
	data.character_levels[card_id] = cur + 1
	_save()
	return true
