extends Resource
class_name CharacterSkill

@export var skills: Array[String] = []
@export var skill_triggers: Array[String] = []  # parallel to skills[]; each: "place"|"move"|"remove"|"attack"|"aura"
@export var skill_name: String = ""
@export var skill_description: String = ""
@export var name_key: String = ""
@export var description_key: String = ""
@export var skill_level_values: Array = []
@export var skill_params: Dictionary = {}  # skill-specific params, e.g. {"pause_duration": 1.2}

