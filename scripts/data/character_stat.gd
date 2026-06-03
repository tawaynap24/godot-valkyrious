extends Resource
class_name CharacterStat

# ─────────────────────────────────────────────────────────────────────────────
# CharacterStat — typed Resource for a single character's base stats.
# Loaded as .tres files in resources/characters/
# ─────────────────────────────────────────────────────────────────────────────

@export var card_id: String = ""
@export var char_name: String = ""
@export var name_key: String = ""
@export var description_key: String = ""
@export_enum("Bronze", "Silver", "Gold") var rarity: int = 0
@export var level: int = 1

@export var status: Resource
@export var skill: Resource
@export var appearance: Resource
@export var timings: Resource

@export var stat_adjusted: bool = false
@export var has_barrier: bool = false

