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
			if data.individual_card_levels == null:
				data.individual_card_levels = {}
			if data.card_upgrades == null:
				data.card_upgrades = {}
			if data.coins <= 0:
				data.coins = 1000000
				_save()
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

func get_card_level_at(idx: int) -> int:
	_ensure_card_instance(idx)
	return data.individual_card_levels.get(str(idx), 1)

func get_character_level(card_id: String) -> int:
	# Fallback to the first copy of card_id in owned_cards
	var owned = get_owned_cards()
	var idx = owned.find(card_id)
	if idx != -1:
		return get_card_level_at(idx)
	return 1

## Upgrades the card copy at index `idx` by 1 level. Returns true on success.
func upgrade_character_at(idx: int) -> bool:
	_ensure_card_instance(idx)
	var idx_str = str(idx)
	var cur: int = data.individual_card_levels.get(idx_str, 1)
	if cur >= UPGRADE_MAX_LEVEL:
		return false
	var cost = 10 * (cur + 1)
	if data.coins < cost:
		return false
	data.coins -= cost
	data.individual_card_levels[idx_str] = cur + 1
	_save()
	return true

## Upgrades the character by 1 level. (Kept for compatibility, redirects to first copy)
func upgrade_character(card_id: String) -> bool:
	var owned = get_owned_cards()
	var idx = owned.find(card_id)
	if idx != -1:
		return upgrade_character_at(idx)
	return false

func get_card_id_by_ref(ref: String) -> String:
	if ref.is_valid_int():
		var idx = int(ref)
		var owned = get_owned_cards()
		if idx >= 0 and idx < owned.size():
			return owned[idx]
	return ref

## Returns the effective card stats dictionary for the card ref (index string or card_id string).
func get_effective_card_dict(ref: String) -> Dictionary:
	if ref.is_valid_int():
		var idx = int(ref)
		var owned = get_owned_cards()
		if idx >= 0 and idx < owned.size():
			var card_id = owned[idx]
			var base = CardDatabase.CARDS.get(card_id, {})
			if base.is_empty():
				return {}
			var d = base.duplicate()
			
			_ensure_card_instance(idx)
			
			var idx_str = str(idx)
			var level = data.individual_card_levels.get(idx_str, 1)
			d["level"] = level
			
			var atk_boost = 0
			var hp_boost = 0
			var path = data.card_upgrades.get(idx_str, {})
			for l in range(2, level + 1):
				var roll = path.get(str(l), {})
				atk_boost += roll.get("atk", 0)
				hp_boost += roll.get("hp", 0)
				
			d["atk"] = base.get("atk", 1) + atk_boost
			d["hp"] = base.get("hp", 1) + hp_boost
			return d
	return CardDatabase.get_effective_dict(ref)

func get_card_upgrades_at(idx: int) -> Dictionary:
	_ensure_card_instance(idx)
	return data.card_upgrades.get(str(idx), {})

func _ensure_card_instance(idx: int) -> void:
	var idx_str = str(idx)
	var owned = get_owned_cards()
	if idx < 0 or idx >= owned.size():
		return
		
	if not data.individual_card_levels.has(idx_str):
		data.individual_card_levels[idx_str] = 1
		
	if not data.card_upgrades.has(idx_str):
		var card_id = owned[idx]
		var base_stats = CardDatabase.CARDS.get(card_id, {})
		var base_atk = base_stats.get("atk", 1)
		var base_hp = base_stats.get("hp", 1)
		
		var path = {}
		var current_atk = base_atk
		var current_hp = base_hp
		
		for lvl in range(2, 6):
			var roll = _roll_upgrade_for_level(lvl, current_atk, current_hp)
			path[str(lvl)] = roll
			current_atk += roll["atk"]
			current_hp += roll["hp"]
			
		data.card_upgrades[idx_str] = path
		_save()

func _roll_upgrade_for_level(lvl: int, cur_atk: int, cur_hp: int) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	while true:
		var type = ""
		var atk_diff = 0
		var hp_diff = 0
		var text = ""
		
		var roll_val = rng.randi_range(1, 100)
		
		if lvl == 2:
			# lvl2 50:50:0:0 
			if roll_val <= 50:
				type = "HP"
				hp_diff = 1
				text = "❤️ Life +1"
			else:
				type = "ATK"
				atk_diff = 1
				text = "👊 ATK +1"
		elif lvl == 3:
			# lvl3 35:35:20:10
			if roll_val <= 35:
				type = "HP"
				hp_diff = 1
				text = "❤️ Life +1"
			elif roll_val <= 70:
				type = "ATK"
				atk_diff = 1
				text = "👊 ATK +1"
			elif roll_val <= 90:
				type = "ABILITY"
				atk_diff = 1
				text = "⚡ Ability +1"
			else:
				type = "SPECIAL_STAT"
				var spec_roll = rng.randi_range(1, 3)
				if spec_roll == 1:
					hp_diff = 2
					atk_diff = -1
					text = "❤️ Life +2  👊 ATK -1"
				elif spec_roll == 2:
					atk_diff = 2
					text = "👊 ATK +2"
				else:
					hp_diff = -1
					text = "❤️ Life -1"
		else:
			# lvl4 & lvl5 25:25:30:20
			if roll_val <= 25:
				type = "HP"
				hp_diff = 2
				text = "❤️ Life +2"
			elif roll_val <= 50:
				type = "ATK"
				atk_diff = 2
				text = "👊 ATK +2"
			elif roll_val <= 80:
				type = "ABILITY"
				atk_diff = 1
				text = "⚡ Ability +1"
			else:
				type = "SPECIAL_STAT"
				var spec_roll = rng.randi_range(1, 3)
				if spec_roll == 1:
					hp_diff = 3
					atk_diff = -1
					text = "❤️ Life +3  👊 ATK -1"
				elif spec_roll == 2:
					atk_diff = 3
					text = "👊 ATK +3"
				else:
					hp_diff = -1
					text = "❤️ Life -1"
					
		# Check if resulting stats > 0
		if cur_atk + atk_diff > 0 and cur_hp + hp_diff > 0:
			return {
				"type": type,
				"atk": atk_diff,
				"hp": hp_diff,
				"text": text
			}
	return {}
