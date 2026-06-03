extends Node

# ─────────────────────────────────────────────────────────────────────────────
# CardDatabase — loads all CharacterStat .tres from res://resources/characters/
# Access via the autoload singleton: CardDatabase.CARDS["ariana"]
# Keys are lowercase card_id strings (e.g. "ange", "ariana").
# ─────────────────────────────────────────────────────────────────────────────

var CARDS: Dictionary = {}

# ── Rarity display constants (single source of truth) ─────────────────────────
const RARITY_NAMES: Array[String] = ["UI_BRONZE", "UI_SILVER", "UI_GOLD"]
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
	var name_val = s.name_key if s.name_key != "" else s.char_name
	var desc_val = s.description_key if s.description_key != "" else s.appearance.description
	var skill_name_val = s.skill.name_key if (s.skill != null and s.skill.name_key != "") else (s.skill.skill_name if s.skill != null else "")
	var skill_desc_val = s.skill.description_key if (s.skill != null and s.skill.description_key != "") else (s.skill.skill_description if s.skill != null else "")

	return {
		"id": id,
		"name": name_val,
		"rarity": s.rarity,
		"level": s.level,
		"cost": s.status.cost,
		"atk": s.status.atk,
		"hp": s.status.hp,
		"skill_level": 1,
		"skill_name": skill_name_val,
		"skill_description": skill_desc_val,
		"skill_level_values": s.skill.skill_level_values.duplicate() if s.skill != null else [],
		"skill_params": s.skill.skill_params.duplicate() if s.skill != null else {},
		"stat_adjusted": s.stat_adjusted,
		"description": desc_val,
		"skills": s.skill.skills.duplicate() if s.skill != null else [] as Array[String],
		"skill_triggers": s.skill.skill_triggers.duplicate() if s.skill != null else [] as Array[String],
		"has_barrier": s.has_barrier,
		"has_image": s.appearance.has_image if s.appearance != null else false,
		"image_path": s.appearance.image_path if s.appearance != null else "",
		"bg_color": s.appearance.bg_color if s.appearance != null else Color(0.15, 0.15, 0.35, 1.0),
		"time_delay": {
			"place": s.timings.delay_place if s.timings != null else 0.0,
			"attack": s.timings.delay_attack if s.timings != null else 0.5,
			"move": s.timings.delay_move if s.timings != null else 0.5,
			"move_countdown": s.timings.move_countdown if s.timings != null else 8.0,
			"capture_duration": s.timings.capture_duration if s.timings != null else 4.0,
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
	d["skill_level"] = 1
	return d

func get_scaled_skill_desc(card_id: String, template: String, skill_level: int) -> String:
	if template == "":
		return tr("UI_NO_PASSIVE_SKILL")
	var base = CARDS.get(card_id, {})
	var values: Array = base.get("skill_level_values", [])
	var translated_template = tr(template)
	if values.is_empty():
		return translated_template
	var idx = clamp(skill_level - 1, 0, values.size() - 1)
	var val = values[idx]
	if val is Array:
		return translated_template % val
	else:
		return translated_template % val
