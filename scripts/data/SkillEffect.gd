extends Resource
class_name SkillEffect

# ─────────────────────────────────────────────────────────────────────────────
# SkillEffect — base class for all skill resources.
# Each skill is a .tres file in res://resources/skills/ with a script that
# extends this class and overrides execute().
#
# resolver (SkillResolver) exposes helpers:
#   resolver.field_cards            → Array of all cards on the field
#   resolver.add_pause(seconds)     → add a global battle pause
#   resolver.apply_damage(target, amount) → apply damage respecting barrier
#   resolver.spawn_child(node)      → add a visual node under CardManager
#   resolver.make_tween()           → create a Tween on CardManager
# ─────────────────────────────────────────────────────────────────────────────

@export var skill_id: String = ""

## Override in each skill subclass.
func execute(card, resolver) -> void:
	pass
