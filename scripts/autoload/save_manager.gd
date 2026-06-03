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

# ── Locale ────────────────────────────────────────────────────────────────────

func get_locale() -> String:
	return LocalizationSettings.get_language()

func set_locale(new_locale: String) -> void:
	if data:
		data.locale = new_locale
		_save()
	LocalizationSettings.set_language(new_locale)

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
			_migrate_to_v3()
			validate_and_fix_card_upgrades()
			TranslationServer.set_locale(data.locale if data.locale != "" else "th")
			return
	# No save file yet — create fresh with starter deck only (unlock more via gacha)
	data = PlayerData.new()
	data.deck_1.assign(DEFAULT_DECK)
	data.active_deck = 1
	data.owned_cards.assign(DEFAULT_DECK)
	data.coins = 1000000
	data.data_version = 3
	data.locale = "th"
	TranslationServer.set_locale("th")
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

# Migrate to v3 — Clear non-default owned cards from the collection.
func _migrate_to_v3() -> void:
	if data.data_version >= 3:
		return
		
	var old_owned = data.owned_cards.duplicate()
	var old_levels = data.individual_card_levels.duplicate()
	var old_upgrades = data.card_upgrades.duplicate()
	
	var cleaned_owned: Array[String] = []
	for card_id in old_owned:
		if DEFAULT_DECK.has(card_id):
			cleaned_owned.append(card_id)
			
	if cleaned_owned.is_empty():
		cleaned_owned.assign(DEFAULT_DECK)
		
	var new_levels = {}
	var new_upgrades = {}
	for idx in range(cleaned_owned.size()):
		var card_id = cleaned_owned[idx]
		# Find the first occurrence of this card in old_owned to preserve its level
		var old_idx = old_owned.find(card_id)
		if old_idx != -1:
			new_levels[str(idx)] = old_levels.get(str(old_idx), 1)
			new_upgrades[str(idx)] = old_upgrades.get(str(old_idx), {})
		else:
			new_levels[str(idx)] = 1
			new_upgrades[str(idx)] = {}
			
	# Update active decks to map back to the new indices of default cards
	for i in range(1, 4):
		var deck = data.get_deck(i)
		var new_deck: Array[String] = []
		for ref in deck:
			var card_id = ""
			if ref.is_valid_int():
				var idx = int(ref)
				if idx >= 0 and idx < old_owned.size():
					card_id = old_owned[idx]
			else:
				card_id = ref
				
			if DEFAULT_DECK.has(card_id):
				var new_idx = cleaned_owned.find(card_id)
				if new_idx != -1:
					if not new_deck.has(str(new_idx)):
						new_deck.append(str(new_idx))
						
		# If deck became invalid / less than 8, populate with all default indices 0-7
		if new_deck.size() < 8:
			new_deck.clear()
			for idx in range(8):
				new_deck.append(str(idx))
		data.set_deck(i, new_deck)
		
	data.owned_cards = cleaned_owned
	data.individual_card_levels = new_levels
	data.card_upgrades = new_upgrades
	data.data_version = 3
	_save()

func clear_non_default_cards() -> void:
	data.owned_cards.clear()
	data.owned_cards.assign(DEFAULT_DECK)
	data.individual_card_levels.clear()
	data.card_upgrades.clear()
	for idx in range(8):
		data.individual_card_levels[str(idx)] = 1
		data.card_upgrades[str(idx)] = {}
		
	# Update active decks to map back to default cards 0-7
	for i in range(1, 4):
		var new_deck: Array[String] = []
		for idx in range(8):
			new_deck.append(str(idx))
		data.set_deck(i, new_deck)
		
	_save()

func get_fixed_upgrade_path() -> Dictionary:
	return {
		"2": {
			"type": "ATK",
			"atk": 1,
			"hp": 0,
			"cost": 0,
			"text": "👊 ATK +1"
		},
		"3": {
			"type": "HP",
			"atk": 0,
			"hp": 1,
			"cost": 0,
			"text": "❤️ HP +1"
		},
		"4": {
			"type": "ATK_HP",
			"atk": 2,
			"hp": 0,
			"cost": 0,
			"text": "👊 ATK +2"
		},
		"5": {
			"type": "ATK_HP",
			"atk": 0,
			"hp": 2,
			"cost": 0,
			"text": "❤️ HP +2"
		}
	}

func validate_and_fix_card_upgrades() -> void:
	var owned = get_owned_cards()
	var changed = false
	for idx in range(owned.size()):
		var card_id = owned[idx]
		var base_stats = CardDatabase.CARDS.get(card_id, {})
		var is_adjusted = base_stats.get("stat_adjusted", false)
		
		var idx_str = str(idx)
		var path = data.card_upgrades.get(idx_str, {})
		
		var needs_regen = false
		if path.is_empty():
			needs_regen = true
		else:
			for lvl in range(2, 6):
				var roll = path.get(str(lvl), {})
				if roll.is_empty() or roll.get("type", "") == "":
					needs_regen = true
					break
					
		if not needs_regen:
			if not is_adjusted:
				var fixed = get_fixed_upgrade_path()
				for lvl in range(2, 6):
					var lvl_str = str(lvl)
					var r_cur = path.get(lvl_str, {})
					var r_fix = fixed[lvl_str]
					if r_cur.get("type", "") != r_fix["type"] or r_cur.get("atk", 0) != r_fix["atk"] or r_cur.get("hp", 0) != r_fix["hp"] or r_cur.get("cost", 0) != r_fix["cost"] or r_cur.get("text", "") != r_fix["text"]:
						needs_regen = true
						break
			else:
				var fixed = get_fixed_upgrade_path()
				var matches_fixed = true
				for lvl in range(2, 6):
					var lvl_str = str(lvl)
					var r_cur = path.get(lvl_str, {})
					var r_fix = fixed[lvl_str]
					if r_cur.get("type", "") != r_fix["type"] or r_cur.get("atk", 0) != r_fix["atk"] or r_cur.get("hp", 0) != r_fix["hp"] or r_cur.get("cost", 0) != r_fix["cost"] or r_cur.get("text", "") != r_fix["text"]:
						matches_fixed = false
						break
				if matches_fixed:
					needs_regen = true
				else:
					var max_sl = base_stats.get("skill_level_values", []).size()
					if max_sl == 0:
						max_sl = 1
					var max_ability_upgrades = max_sl - 1
					var base_cost = base_stats.get("cost", 1)
					var min_cost = 2 if base_cost >= 2 else 1
					
					var ability_count = 0
					var current_cost = base_cost
					for lvl in range(2, 6):
						var roll = path.get(str(lvl), {})
						current_cost += roll.get("cost", 0)
						if current_cost < min_cost:
							needs_regen = true
							break
						if roll.get("type", "") == "ABILITY":
							ability_count += 1
							if ability_count > max_ability_upgrades:
								needs_regen = true
								break
							
		if needs_regen:
			print("[SaveManager] Regenerating/Fixing path for card %s (index %d)" % [card_id, idx])
			if not is_adjusted:
				data.card_upgrades[idx_str] = get_fixed_upgrade_path()
			else:
				var base_atk = base_stats.get("atk", 1)
				var base_hp = base_stats.get("hp", 1)
				var base_cost = base_stats.get("cost", 1)
				var new_path = {}
				var current_atk = base_atk
				var current_hp = base_hp
				var current_cost = base_cost
				var current_ability = 0
				
				for lvl in range(2, 6):
					var roll = _roll_upgrade_for_level(lvl, current_atk, current_hp, current_cost, card_id, current_ability)
					new_path[str(lvl)] = roll
					current_atk += roll.get("atk", 0)
					current_hp += roll.get("hp", 0)
					current_cost += roll.get("cost", 0)
					if roll.get("type", "") == "ABILITY":
						current_ability += 1
						
				data.card_upgrades[idx_str] = new_path
			changed = true
			
	if changed:
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
			var cost_boost = 0
			var skill_lvl = 1
			var path = data.card_upgrades.get(idx_str, {})
			for l in range(2, level + 1):
				var roll = path.get(str(l), {})
				atk_boost += roll.get("atk", 0)
				hp_boost += roll.get("hp", 0)
				cost_boost += roll.get("cost", 0)
				if roll.get("type", "") == "ABILITY":
					skill_lvl += 1
				
			d["atk"] = base.get("atk", 1) + atk_boost
			d["hp"] = base.get("hp", 1) + hp_boost
			d["cost"] = max(1, base.get("cost", 1) + cost_boost)
			d["skill_level"] = skill_lvl
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
		
	var card_id = owned[idx]
	var base_stats = CardDatabase.CARDS.get(card_id, {})
	var is_adjusted = base_stats.get("stat_adjusted", false)
	
	var path = data.card_upgrades.get(idx_str, {})
	var needs_regen = false
	if path.is_empty():
		needs_regen = true
	else:
		for lvl in range(2, 6):
			var roll = path.get(str(lvl), {})
			if roll.is_empty() or roll.get("type", "") == "":
				needs_regen = true
				break
				
	if not needs_regen:
		if not is_adjusted:
			var fixed = get_fixed_upgrade_path()
			for lvl in range(2, 6):
				var lvl_str = str(lvl)
				var r_cur = path.get(lvl_str, {})
				var r_fix = fixed[lvl_str]
				if r_cur.get("type", "") != r_fix["type"] or r_cur.get("atk", 0) != r_fix["atk"] or r_cur.get("hp", 0) != r_fix["hp"] or r_cur.get("cost", 0) != r_fix["cost"] or r_cur.get("text", "") != r_fix["text"]:
					needs_regen = true
					break
		else:
			var fixed = get_fixed_upgrade_path()
			var matches_fixed = true
			for lvl in range(2, 6):
				var lvl_str = str(lvl)
				var r_cur = path.get(lvl_str, {})
				var r_fix = fixed[lvl_str]
				if r_cur.get("type", "") != r_fix["type"] or r_cur.get("atk", 0) != r_fix["atk"] or r_cur.get("hp", 0) != r_fix["hp"] or r_cur.get("cost", 0) != r_fix["cost"] or r_cur.get("text", "") != r_fix["text"]:
					matches_fixed = false
					break
			if matches_fixed:
				needs_regen = true
				
	if needs_regen:
		if not is_adjusted:
			data.card_upgrades[idx_str] = get_fixed_upgrade_path()
		else:
			var base_atk = base_stats.get("atk", 1)
			var base_hp = base_stats.get("hp", 1)
			var base_cost = base_stats.get("cost", 1)
			
			var new_path = {}
			var current_atk = base_atk
			var current_hp = base_hp
			var current_cost = base_cost
			var current_ability = 0
			for lvl in range(2, 6):
				var roll = _roll_upgrade_for_level(lvl, current_atk, current_hp, current_cost, card_id, current_ability)
				new_path[str(lvl)] = roll
				current_atk += roll.get("atk", 0)
				current_hp += roll.get("hp", 0)
				current_cost += roll.get("cost", 0)
				if roll.get("type", "") == "ABILITY":
					current_ability += 1
				
			data.card_upgrades[idx_str] = new_path
		_save()

func _roll_upgrade_for_level(lvl: int, cur_atk: int, cur_hp: int, cur_cost: int, card_id: String = "", current_ability: int = 0) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	var max_ability_upgrades = 999
	var min_cost = 1
	if card_id != "":
		var base_stats = CardDatabase.CARDS.get(card_id, {})
		var max_sl = base_stats.get("skill_level_values", []).size()
		if max_sl == 0:
			max_sl = 1
		max_ability_upgrades = max_sl - 1
		
		var base_cost = base_stats.get("cost", 1)
		min_cost = 2 if base_cost >= 2 else 1
		
	while true:
		var type = ""
		var atk_diff = 0
		var hp_diff = 0
		var cost_diff = 0
		var text = ""
		
		if lvl == 2:
			# lvl 2 options: +1HP, +1ATK, +1ABILITY
			# Weights ratio: HP/ATK: 50%, ABILITY: 30%, COST: 0% -> Scale to 50:30 (total 80)
			var roll_val = rng.randi_range(1, 80)
			if roll_val <= 50:
				# HP/ATK (split 50/50)
				if roll_val <= 25:
					type = "HP"
					hp_diff = 1
					text = "❤️ HP +1"
				else:
					type = "ATK"
					atk_diff = 1
					text = "👊 ATK +1"
			else:
				type = "ABILITY"
				text = "⚡ Ability +1"
				
		elif lvl == 3:
			# lvl 3 options:
			# - HP/ATK (50%): +1HP, +1ATK
			# - ABILITY (30%): +1ABILITY, +1ABILITY -1HP, +1ABILITY -1ATK
			# - COST (20%): -1COST -1HP, -1COST -1ATK
			var roll_val = rng.randi_range(1, 100)
			if roll_val <= 50:
				type = "HP" if roll_val <= 25 else "ATK"
				if type == "HP":
					hp_diff = 1
					text = "❤️ HP +1"
				else:
					atk_diff = 1
					text = "👊 ATK +1"
			elif roll_val <= 80:
				type = "ABILITY"
				var sub = rng.randi_range(1, 3)
				if sub == 1:
					text = "⚡ Ability +1"
				elif sub == 2:
					hp_diff = -1
					text = "⚡ Ability +1  ❤️ HP -1"
				else:
					atk_diff = -1
					text = "⚡ Ability +1  👊 ATK -1"
			else:
				type = "COST"
				var sub = rng.randi_range(1, 2)
				cost_diff = -1
				if sub == 1:
					hp_diff = -1
					text = "🪙 Cost -1  ❤️ HP -1"
				else:
					atk_diff = -1
					text = "🪙 Cost -1  👊 ATK -1"
					
		elif lvl == 4:
			# lvl 4 options:
			# - HP/ATK (50%): +1HP, +1ATK, +2HP, +2ATK, +2ATK -1HP, +2HP -1ATK
			# - ABILITY (30%): +1ABILITY, +1ABILITY -1HP, +1ABILITY -1ATK
			# - COST (20%): -1COST, -1COST -1HP, -1COST -1ATK
			var roll_val = rng.randi_range(1, 100)
			if roll_val <= 50:
				var sub = rng.randi_range(1, 6)
				if sub == 1:
					type = "HP"
					hp_diff = 1
					text = "❤️ HP +1"
				elif sub == 2:
					type = "ATK"
					atk_diff = 1
					text = "👊 ATK +1"
				elif sub == 3:
					type = "HP"
					hp_diff = 2
					text = "❤️ HP +2"
				elif sub == 4:
					type = "ATK"
					atk_diff = 2
					text = "👊 ATK +2"
				elif sub == 5:
					type = "ATK"
					hp_diff = -1
					atk_diff = 2
					text = "❤️ HP -1  👊 ATK +2"
				else:
					type = "HP"
					hp_diff = 2
					atk_diff = -1
					text = "❤️ HP +2  👊 ATK -1"
			elif roll_val <= 80:
				type = "ABILITY"
				var sub = rng.randi_range(1, 3)
				if sub == 1:
					text = "⚡ Ability +1"
				elif sub == 2:
					hp_diff = -1
					text = "⚡ Ability +1  ❤️ HP -1"
				else:
					atk_diff = -1
					text = "⚡ Ability +1  👊 ATK -1"
			else:
				type = "COST"
				var sub = rng.randi_range(1, 3)
				cost_diff = -1
				if sub == 1:
					text = "🪙 Cost -1"
				elif sub == 2:
					hp_diff = -1
					text = "🪙 Cost -1  ❤️ HP -1"
				else:
					atk_diff = -1
					text = "🪙 Cost -1  👊 ATK -1"
					
		else: # lvl 5
			# lvl 5 options:
			# - HP/ATK (50%): +1HP, +1ATK, +2HP, +2ATK, +3HP -1ATK, +3ATK -1HP
			# - ABILITY (30%): +1ABILITY, +1ABILITY -1HP, +1ABILITY -1ATK
			# - COST (20%): -1COST, -1COST -1HP, -1COST -1ATK
			var roll_val = rng.randi_range(1, 100)
			if roll_val <= 50:
				var sub = rng.randi_range(1, 6)
				if sub == 1:
					type = "HP"
					hp_diff = 1
					text = "❤️ HP +1"
				elif sub == 2:
					type = "ATK"
					atk_diff = 1
					text = "👊 ATK +1"
				elif sub == 3:
					type = "HP"
					hp_diff = 2
					text = "❤️ HP +2"
				elif sub == 4:
					type = "ATK"
					atk_diff = 2
					text = "👊 ATK +2"
				elif sub == 5:
					type = "HP"
					hp_diff = 3
					atk_diff = -1
					text = "❤️ HP +3  👊 ATK -1"
				else:
					type = "ATK"
					hp_diff = -1
					atk_diff = 3
					text = "👊 ATK +3  ❤️ HP -1"
			elif roll_val <= 80:
				type = "ABILITY"
				var sub = rng.randi_range(1, 3)
				if sub == 1:
					text = "⚡ Ability +1"
				elif sub == 2:
					hp_diff = -1
					text = "⚡ Ability +1  ❤️ HP -1"
				else:
					atk_diff = -1
					text = "⚡ Ability +1  👊 ATK -1"
			else:
				type = "COST"
				var sub = rng.randi_range(1, 3)
				cost_diff = -1
				if sub == 1:
					text = "🪙 Cost -1"
				elif sub == 2:
					hp_diff = -1
					text = "🪙 Cost -1  ❤️ HP -1"
				else:
					atk_diff = -1
					text = "🪙 Cost -1  👊 ATK -1"
					
		if type == "ABILITY" and current_ability >= max_ability_upgrades:
			continue
			
		# Check if resulting stats >= 1 (or min_cost for cost)
		if cur_atk + atk_diff >= 1 and cur_hp + hp_diff >= 1 and cur_cost + cost_diff >= min_cost:
			return {
				"type": type,
				"atk": atk_diff,
				"hp": hp_diff,
				"cost": cost_diff,
				"text": text
			}
	return {}
