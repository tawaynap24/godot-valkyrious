extends Node

# ─────────────────────────────────────────────────────────────────────────────
# CardDatabase — loads all CharacterStat .tres from res://resources/characters/
# Access via the autoload singleton: CardDatabase.CARDS["ariana"]
# Keys are lowercase card_id strings (e.g. "ange", "ariana").
# ─────────────────────────────────────────────────────────────────────────────

var CARDS: Dictionary = {}

# ── Rarity display constants (single source of truth) ─────────────────────────
const RARITY_NAMES: Array[String] = ["Bronze", "Silver", "Gold"]
const RARITY_COLORS: Array[Color] = [
	Color(0.80, 0.50, 0.18, 1.0),  # Bronze
	Color(0.78, 0.78, 0.82, 1.0),  # Silver
	Color(1.00, 0.78, 0.12, 1.0),  # Gold
]
const RARITY_BG: Array[Color] = [
	Color(0.20, 0.13, 0.06, 1.0),  # Bronze bg
	Color(0.16, 0.16, 0.22, 1.0),  # Silver bg
	Color(0.22, 0.18, 0.04, 1.0),  # Gold bg
]

func _ready() -> void:
	_load_all()

func _load_all() -> void:
	var dir = DirAccess.open("res://resources/characters/")
	if dir == null:
		push_error("CardDatabase: cannot open res://resources/characters/")
		return
	print("[CardDatabase] _load_all started")
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if fname.ends_with(".tres") or fname.ends_with(".tres.remap"):
			var load_path := "res://resources/characters/" + fname.trim_suffix(".remap")
			var res = load(load_path)
			if res is CharacterStat:
				var d = _stat_to_dict(res)
				CARDS[d["id"]] = d
		fname = dir.get_next()
	dir.list_dir_end()
	print("[CardDatabase] loaded %d cards: %s" % [CARDS.size(), str(CARDS.keys())])

func _stat_to_dict(s: CharacterStat) -> Dictionary:
	var id: String = s.card_id if s.card_id != "" else s.char_name.to_lower()
	return {
		"id": id,
		"name": s.char_name,
		"rarity": s.rarity,
		"level": s.level,
		"cost": s.cost,
		"atk": s.atk,
		"hp": s.hp,
		"description": s.description,
		"skills": s.skills.duplicate(),
		"skill_triggers": s.skill_triggers.duplicate(),
		"has_barrier": s.has_barrier,
		"has_image": s.has_image,
		"image_path": s.image_path,
		"bg_color": s.bg_color,
		"time_delay": {
			"place": s.delay_place,
			"attack": s.delay_attack,
			"move": s.delay_move,
			"move_countdown": s.move_countdown,
			"capture_duration": s.capture_duration,
		},
	}

# Resolve a key that may be old-format capitalised ("Ariana") or new lowercase ("ariana").
# Returns the canonical key if found, else empty string.
func resolve_key(key: String) -> String:
	if CARDS.has(key):
		return key
	var lower := key.to_lower()
	if CARDS.has(lower):
		return lower
	return ""

## Returns a copy of the card dict with ATK and HP boosted by the player's upgrade level.
## Level 1 = base stats; each level above 1 adds +1 ATK and +1 HP.
func get_effective_dict(card_id: String) -> Dictionary:
	var base: Dictionary = CARDS.get(card_id, {})
	if base.is_empty():
		return {}
	var d: Dictionary = base.duplicate()
	var level: int = SaveManager.get_character_level(card_id)
	d["level"] = level
	d["atk"] = base.get("atk", 1) + (level - 1)
	d["hp"]  = base.get("hp",  1) + (level - 1)
	return d
