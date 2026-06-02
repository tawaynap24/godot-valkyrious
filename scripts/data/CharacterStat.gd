extends Resource
class_name CharacterStat

# ─────────────────────────────────────────────────────────────────────────────
# CharacterStat — typed Resource for a single character's base stats.
# Loaded as .tres files in resources/characters/
# ─────────────────────────────────────────────────────────────────────────────

@export var card_id: String = ""
@export var char_name: String = ""
@export_enum("Bronze", "Silver", "Gold") var rarity: int = 0
@export var level: int = 1
@export var cost: int = 1
@export var atk: int = 1
@export var hp: int = 1
@export var description: String = ""
@export var skills: Array[String] = []
@export var skill_triggers: Array[String] = []  # parallel to skills[]; each: "place"|"move"|"remove"|"attack"|"aura"
@export var has_barrier: bool = false
@export var has_image: bool = false
@export var image_path: String = ""
@export var bg_color: Color = Color(0.15, 0.15, 0.35, 1.0)

@export_group("Time Delay")
@export var delay_place: float = 0.0
@export var delay_attack: float = 0.5
@export var delay_move: float = 0.5
@export var move_countdown: float = 8.0
@export var capture_duration: float = 4.0
