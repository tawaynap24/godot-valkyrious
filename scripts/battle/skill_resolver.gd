extends Node

# ─────────────────────────────────────────────────────────────────────────────
# SkillResolver — thin dispatcher. Loads all SkillEffect resources at startup
# and calls execute(card, self) when a skill is triggered.
#
# To add a new skill:
#   1. Create scripts/skills/skill_<id>.gd  (extends SkillEffect)
#   2. Create resources/skills/skill_<id>.tres  (skill_id = "<id>")
#   3. Assign skills = ["<id>"] and skill_triggers = ["trigger_type"]
#      in the character's .tres file.
#
# Available trigger types: "place" | "attack" | "move" | "remove" | "aura"
# ─────────────────────────────────────────────────────────────────────────────

var _cm                          # Variant — parent CardManager
var _skill_map: Dictionary = {}  # skill_id → SkillEffect resource

func _ready() -> void:
	_cm = get_parent()
	_load_skills()

func _load_skills() -> void:
	var dir = DirAccess.open("res://resources/skills/")
	if dir == null:
		push_error("SkillResolver: cannot open res://resources/skills/")
		return
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if fname.ends_with(".tres") or fname.ends_with(".tres.remap"):
			var path := "res://resources/skills/" + fname.trim_suffix(".remap")
			var res = load(path)
			if res != null and res.has_method("execute"):
				_skill_map[res.skill_id] = res
				print("[SkillResolver] loaded skill: %s" % res.skill_id)
		fname = dir.get_next()
	dir.list_dir_end()

# ── Public API ────────────────────────────────────────────────────────────────

# Fires all skills on `card` whose trigger_type matches.
func trigger_skills(card, trigger_type: String) -> void:
	var skills: Array = card.card_data.get("skills", [])
	var triggers: Array = card.card_data.get("skill_triggers", [])
	for i in range(skills.size()):
		if i < triggers.size() and triggers[i] == trigger_type:
			var skill_id: String = skills[i]
			print("[Skill] %s | %s → %s" % [card.card_data.get("name", "?"), trigger_type, skill_id])
			resolve_skill(card, skill_id)

# Looks up the skill resource by id and calls execute(card, self).
func resolve_skill(card, skill_id: String) -> void:
	if _skill_map.has(skill_id):
		_skill_map[skill_id].execute(card, self)
	else:
		push_warning("[SkillResolver] Unknown skill_id: '%s'" % skill_id)

# ── Helpers exposed to SkillEffect scripts ────────────────────────────────────

var field_cards: Array:
	get: return _cm.field_cards

func add_pause(duration: float) -> void:
	_cm._add_pause(duration)

## Apply damage to target respecting barrier. Removes card from field if HP hits 0.
func apply_damage(target, amount: int) -> void:
	if target.barrier:
		target.set_barrier(false)
		return
	target.current_hp -= amount
	target.get_node("HPLabel").text = str(max(0, target.current_hp))
	if target.current_hp <= 0:
		_cm._remove_from_field(target)

func spawn_child(node: Node) -> void:
	_cm.add_child(node)

func make_tween() -> Tween:
	return _cm.create_tween()
